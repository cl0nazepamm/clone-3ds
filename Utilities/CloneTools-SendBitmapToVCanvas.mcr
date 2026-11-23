macroScript SendBitmapToVCanvas
	category:"CloneTools"
	tooltip:"Send Bitmap to Viewport Canvas"
	buttontext:"Send to VCanvas"
(
	try(if CloneUI == undefined do fileIn ((getDir #userScripts) + "\\CloneTools\\CloneUI.ms"))catch(try(fileIn ((getFilenamePath (getSourceFileName())) + "CloneUI.ms"))catch())

	-- Ensure Viewport Canvas is loaded
	if VCanvas == undefined do
		filein ((GetDir #maxroot) + "stdplugs\\stdscripts\\(PolyTools)\\ViewportCanvas.ms")

	if $ == undefined do (
		messageBox "Select a scene object first." title:"Send to Viewport Canvas"
		return false
	)
	if $.material == undefined do (
		messageBox "Selected object has no material." title:"Send to Viewport Canvas"
		return false
	)

	-- Get selected BitmapTexture from Slate Material Editor via GetSelectedNodes
	local smeView = ::sme.GetView (::sme.activeView)
	if smeView == undefined do (
		messageBox "No active SME view." title:"Send to Viewport Canvas"
		return false
	)

	local selectedBitmap = undefined
	local selNodes = smeView.GetSelectedNodes()
	for i = 1 to selNodes.count do (
		try (
			local ref = selNodes[i].reference
			if classOf ref == BitmapTexture do (
				selectedBitmap = ref
				exit
			)
		) catch ()
	)

	if selectedBitmap == undefined do (
		messageBox "Select a BitmapTexture node in the Slate Material Editor." title:"Send to Viewport Canvas"
		return false
	)

	---------------------------------------------------------------
	-- If bitmap file doesn't exist, offer to create a blank one
	---------------------------------------------------------------
	if selectedBitmap.filename == "" or not (doesFileExist selectedBitmap.filename) do
	(
		local createdFile = false
		try(CloneCreateBlankTexture_Form.Close())catch()
		try(CloneCreateBlankTexture_Form.Dispose())catch()
		global CloneCreateBlankTexture_Form = dotNetObject "System.Windows.Forms.Form"
		local frm = CloneUI.skinForm CloneCreateBlankTexture_Form "Create Blank Texture" 340 430
		local shell = CloneUI.addShell frm "Create Blank Texture" version:"v1.0"
		local pad = shell[1]
		local iW = shell[2]
		local Y = shell[3]

		local lblInfo = CloneUI.mkLabel "No texture file found. Create one:" pad Y iW 20 fObj:CloneUI.fSmall cObj:CloneUI.cDim
		frm.controls.add lblInfo
		Y += 34

		frm.controls.add (CloneUI.mkLabel "Size" (pad+4) Y 80 18 fObj:CloneUI.fSmall cObj:CloneUI.cDim)
		local ddSize = dotNetObject "System.Windows.Forms.ComboBox"
		ddSize.Location = dotNetObject CloneUI.ptC (pad+120) (Y-2)
		ddSize.Size = dotNetObject CloneUI.szC 120 22
		ddSize.DropDownStyle = (dotNetClass "System.Windows.Forms.ComboBoxStyle").DropDownList
		ddSize.BackColor = CloneUI.clr.FromArgb 38 38 38
		ddSize.ForeColor = CloneUI.cText
		for s in #("512", "1024", "2048", "4096") do ddSize.Items.Add s
		ddSize.SelectedIndex = 2
		frm.controls.add ddSize
		Y += 34

		frm.controls.add (CloneUI.mkLabel "Save As" (pad+4) Y 80 18 fObj:CloneUI.fSmall cObj:CloneUI.cDim)
		Y += 22
		local defName = selectedBitmap.name
		if defName == "" do defName = "untitled"
		local edPath = CloneUI.mkText pad Y (iW - 38) 22 text:((getDir #image) + "\\" + defName + ".png")
		local btnBrowse = CloneUI.mkBtn "..." (pad + iW - 30) (Y-1) 30 24
		frm.controls.add edPath
		frm.controls.add btnBrowse
		Y += 42

		local btnOK = CloneUI.mkBtn "Create" pad Y ((iW - 8) / 2) 30
		local btnCancel = CloneUI.mkBtn "Cancel" (pad + ((iW - 8) / 2) + 8) Y ((iW - 8) / 2) 30
		frm.controls.add btnOK
		frm.controls.add btnCancel
		Y += 46

		local credit = CloneUI.mkLabel "clone" 0 Y 340 16 fObj:CloneUI.fSmall cObj:(CloneUI.clr.FromArgb 55 55 55)
		credit.TextAlign = CloneUI.alC.MiddleCenter
		frm.controls.add credit
		frm.Size = dotNetObject CloneUI.szC 340 (Y + 24)

		fn onBlankBrowse s e =
		(
			local f = getSaveFileName caption:"Save Texture" filename:edPath.Text types:"PNG (*.png)|*.png|JPEG (*.jpg)|*.jpg|BMP (*.bmp)|*.bmp|"
			if f != undefined do edPath.Text = f
		)
		fn onBlankCancel s e = frm.Close()
		fn onBlankCreate s e =
		(
			local filePath = edPath.Text
			if filePath == "" do
			(
				messageBox "Pick a save location." title:"Create Texture"
				return()
			)

			local sz = (ddSize.SelectedItem as string) as integer
			local dir = getFilenamePath filePath
			if dir != "" and not (doesFileExist dir) do makeDir dir

			local bmp = bitmap sz sz color:(color 128 128 128)
			bmp.filename = filePath
			save bmp
			close bmp

			selectedBitmap.filename = filePath
			selectedBitmap.bitmap = openBitmap filePath
			createdFile = true
			frm.Close()
		)

		dotNet.addEventHandler btnBrowse "Click" onBlankBrowse
		dotNet.addEventHandler btnCancel "Click" onBlankCancel
		dotNet.addEventHandler btnOK "Click" onBlankCreate
		append CloneUI_handlers #(onBlankBrowse, onBlankCancel, onBlankCreate)
		frm.ShowDialog()

		if not createdFile do return false
	)

	---------------------------------------------------------------
	-- Walk material tree to find which slot holds this bitmap
	---------------------------------------------------------------
	global _vcWalkTexmap
	fn _vcWalkTexmap tex targetRef &slotName &parentNode =
	(
		if slotName != undefined do return true
		local numMaps = 0
		try (numMaps = getNumSubTexmaps tex) catch (return false)
		for i = 1 to numMaps do (
			if slotName != undefined do exit
			local subTex = undefined
			try (subTex = getSubTexmap tex i) catch ()
			if subTex != undefined do (
				if subTex == targetRef then (
					slotName = getSubTexmapSlotName tex i
					parentNode = tex
				) else (
					_vcWalkTexmap subTex targetRef &slotName &parentNode
				)
			)
		)
		slotName != undefined
	)

	global _vcWalkMaterial
	fn _vcWalkMaterial mat targetRef &slotName &parentNode =
	(
		if slotName != undefined do return true
		local numSubs = 0
		try (numSubs = getNumSubMtls mat) catch ()
		for i = 1 to numSubs do (
			if slotName != undefined do exit
			local sm = undefined
			try (sm = getSubMtl mat i) catch ()
			if sm != undefined do
				_vcWalkMaterial sm targetRef &slotName &parentNode
		)
		if slotName != undefined do return true
		local numMaps = 0
		try (numMaps = getNumSubTexmaps mat) catch ()
		for i = 1 to numMaps do (
			if slotName != undefined do exit
			local tex = undefined
			try (tex = getSubTexmap mat i) catch ()
			if tex != undefined do (
				if tex == targetRef then (
					slotName = getSubTexmapSlotName mat i
					parentNode = mat
				) else (
					_vcWalkTexmap tex targetRef &slotName &parentNode
				)
			)
		)
		slotName != undefined
	)

	local foundSlotName = undefined
	local foundParent = undefined
	_vcWalkMaterial $.material selectedBitmap &foundSlotName &foundParent

	if foundSlotName == undefined do (
		messageBox "Could not find this bitmap in the selected object's material tree." title:"Send to Viewport Canvas"
		return false
	)

	---------------------------------------------------------------
	-- Assign to Viewport Canvas and start painting
	---------------------------------------------------------------
	VCanvas.currentTextureFile = selectedBitmap.filename
	VCanvas.mapSlotName = foundSlotName
	VCanvas.currentMaterial = $.material
	VCanvas.usedMapSlot = selectedBitmap
	VCanvas.currentObject = $

	try (
		VCSetSetting 4 selectedBitmap.coords.mapchannel
		VCOptionsRoll.mapch.value = selectedBitmap.coords.mapchannel
	) catch ()

	try ( VCOptionsRoll.mapbut.text = foundSlotName ) catch ()
	try ( VCSetUsingNewTexture() ) catch ()

	if VCanvas.doRestartTool do
		VCanvas.StartPaintTool VCanvas.currentTool

	format "Viewport Canvas: painting on '%' (%)\n" foundSlotName selectedBitmap.filename
)
