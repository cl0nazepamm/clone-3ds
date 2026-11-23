(
	/*
		Slate Material Editor - Quick Connect Nodes
		Auto-connects selected texture maps to material slots based on
		pattern matching rules defined in connector_rules.ms.
	*/

	struct ConnectRule (regex, properties, normalBump)
	struct StdSlot (slotIndex, regex)

	fn _sortByY a b = if a[2] > b[2] then 1 else if a[2] < b[2] then -1 else 0

	fn _buildRegex patterns rgxOpt = (
		local parts = for p in patterns where p.count > 0 collect p
		local str = "("
		for i = 1 to parts.count do (
			if i > 1 do append str "|"
			append str parts[i]
		)
		append str ")$"
		dotnetObject "System.Text.RegularExpressions.Regex" str rgxOpt
	)

	fn _wrapForOSL theMap = (
		if classOf theMap == OSLmap then (
			local w = MultiOutputChannelTexmapToTexmap()
			w.sourceMap = theMap
			w.outputChannelIndex = 1
			w
		) else theMap
	)

	fn _createNormalBumpNode theMap parentMat = (
		local node = if classOf parentMat == VrayMtl then VRayNormalMap() else Normal_Bump()
		node.normal_map = theMap
		node
	)

	fn connectorMain = (
		if not (MatEditor.isOpen() and MatEditor.mode == #advanced) do return false
		local viewNode = sme.GetView (sme.activeView)
		if viewNode == undefined do return false

		-- Read auto-add-slots preference
		local settingsPath = (getDir #userScripts) + @"\CloneTools\settings.ini"
		local addNewSlots = (
			local v = getINISetting settingsPath "QuickConnect" "AutoAdd"
			if v == "true" then true
			else if v == "false" then false
			else (
				setINISetting settingsPath "QuickConnect" "AutoAdd" "false"
				true
			)
		)

		-- Locate and load MAXScript rules file
		local scriptDir = getFilenamePath (getSourceFileName())
		if scriptDir == "" do scriptDir = (getDir #userscripts) + @"\CloneTools\"
		local rulesPath = scriptDir + "connector_rules.ms"

		if not (doesFileExist rulesPath) do (
			messageBox ("Rules file not found:\n" + rulesPath) title:"Quick Connect"
			return false
		)

		local config
		try (
			config = execute ((dotNetClass "System.IO.File").ReadAllText rulesPath)
		) catch (
			messageBox ("Failed to parse:\n" + rulesPath + "\n\n" + getCurrentException()) title:"Quick Connect"
			return false
		)

		if classOf config != Array or config.count < 4 do (
			messageBox ("Invalid rules format in:\n" + rulesPath) title:"Quick Connect"
			return false
		)

		local rgxOpt = (dotNetClass "System.Text.RegularExpressions.RegexOptions").IgnoreCase

		local mapProperties = config[1]
		local ignoreBumpClasses = config[2]

		-- Pre-compile generic rules: #(patterns, properties, normalBump)
		local rules = for r in config[3] collect (
			ConnectRule \
				regex:(_buildRegex r[1] rgxOpt) \
				properties:r[2] \
				normalBump:r[3]
		)

		-- Pre-compile standard material slot rules: #(index, patterns)
		local stdSlots = for s in config[4] collect (
			StdSlot \
				slotIndex:s[1] \
				regex:(_buildRegex s[2] rgxOpt)
		)

		-- Categorize selected SME nodes
		local selNodes = try (viewNode.GetSelectedNodes()) catch #()
		if selNodes == undefined do selNodes = #()
		if selNodes.count == 0 do return false

		local materials = #()
		local multiMaterials = #()
		local switchMaterials = #()
		local textureMaps = #()

		for n in selNodes do (
			local ref = n.reference
			local yPos = n.position[2]
			if superClassOf ref == material then (
				case classOf ref of (
					Multimaterial: append multiMaterials ref
					Material_Switcher: append switchMaterials ref
					default: append materials #(ref, yPos)
				)
			) else if superClassOf ref == texturemap do (
				append textureMaps #(ref, yPos)
			)
		)

		-------------------------------------------------------
		-- MultiMaterial: assign materials to empty slots
		-------------------------------------------------------
		if multiMaterials.count == 1 then (
			qsort materials _sortByY
			local mm = multiMaterials[1]
			local freeSlots = for i in 1 to mm.materialList.count where mm.materialList[i] == undefined collect i

			for i = 1 to materials.count do (
				if i <= freeSlots.count then (
					mm.materialList[freeSlots[i]] = materials[i][1]
				) else if addNewSlots do (
					mm.numSubs += 1
					try (
						local autoMat = mm.materialList[mm.numSubs]
						viewNode.SetSelectedNodes #(autoMat)
						viewNode.DeleteSelection()
					) catch ()
					mm.materialList[mm.numSubs] = materials[i][1]
				)
			)

		-------------------------------------------------------
		-- SwitchMaterial: assign materials to empty slots
		-------------------------------------------------------
		) else if switchMaterials.count == 1 then (
			qsort materials _sortByY
			local sm = switchMaterials[1]
			local freeSlots = for i in 1 to sm.materialList.count where sm.materialList[i] == undefined collect i

			for i = 1 to materials.count do (
				if i <= freeSlots.count then (
					sm.materialList[freeSlots[i]] = materials[i][1]
				) else if addNewSlots do (
					sm.nummats += 1
					try (
						local autoMat = sm.materialList[sm.nummats]
						viewNode.SetSelectedNodes #(autoMat)
						viewNode.DeleteSelection()
					) catch ()
					sm.materialList[sm.nummats] = materials[i][1]
				)
			)

		-------------------------------------------------------
		-- Single Material: auto-connect texture maps by name
		-------------------------------------------------------
		) else if materials.count == 1 and textureMaps.count > 0 do (
			local currentMat = materials[1][1]
			local matProps = getPropNames currentMat
			local isStdMat = (classOf currentMat == standardMaterial)

			for mapItem in textureMaps do (
				local currentMap = mapItem[1]
				local connected = false

				-- Extract filename from the map's file-path properties
				local theFileName = ""
				for prop in mapProperties while theFileName == "" do (
					if isProperty currentMap prop do (
						local val = try (getProperty currentMap prop) catch ""
						if classOf val == String and val.count > 0 do
							theFileName = getFileNameFile val
					)
				)

				-- Attempt matching: first by filename (with normal-bump support),
				-- then fall back to map name (without normal-bump)
				local attempts = if theFileName.count > 0
					then #(#(theFileName, true), #(currentMap.name, false))
					else #(#(currentMap.name, false))

				for attempt in attempts while not connected do (
					local testName = attempt[1]
					local allowNormalBump = attempt[2]

					if isStdMat then (
						for slot in stdSlots while not connected do (
							if slot.regex.IsMatch testName do (
								currentMat.maps[slot.slotIndex] = _wrapForOSL currentMap
								connected = true
							)
						)
					) else (
						for rule in rules while not connected do (
							if rule.regex.IsMatch testName do (
								for prop in rule.properties while not connected do (
									if findItem matProps prop > 0 and getProperty currentMat prop == undefined do (
										local mapToAssign = if classOf currentMap == OSLmap \
											then _wrapForOSL currentMap \
											else currentMap
										if allowNormalBump and rule.normalBump \
											and (findItem ignoreBumpClasses (classOf currentMat) == 0) do
											mapToAssign = _createNormalBumpNode mapToAssign currentMat

										setProperty currentMat prop mapToAssign
										connected = true
									)
								)
							)
						)
					)
				)
			)
		)

		redrawViews()
		true
	)

	connectorMain()
	OK
)
