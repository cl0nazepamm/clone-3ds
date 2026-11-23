global CloneTools_ImportObsidianCanvasImages

fn CloneTools_OC_trimText value =
(
	local s = if value == undefined then "" else (value as string)
	while s.count > 0 and (s[1] == " " or s[1] == "\t" or s[1] == "\r" or s[1] == "\n" or s[1] == "\"") do
		s = substring s 2 -1
	while s.count > 0 and (s[s.count] == " " or s[s.count] == "\t" or s[s.count] == "\r" or s[s.count] == "\n" or s[s.count] == "\"") do
		s = substring s 1 (s.count - 1)
	s
)

fn CloneTools_OC_safeName value =
(
	local s = CloneTools_OC_trimText value
	local invalid = "\\/:*?\"<>|"
	for i = 1 to invalid.count do s = substituteString s invalid[i] "_"
	if s == "" then "ObsidianCanvas" else s
)

fn CloneTools_OC_parseCanvasNodeObjects jsonText =
(
	local objects = #()
	local nodesKey = findString jsonText "\"nodes\""
	if nodesKey == undefined do return objects

	local arrayStart = nodesKey
	while arrayStart <= jsonText.count and jsonText[arrayStart] != "[" do arrayStart += 1
	if arrayStart > jsonText.count do return objects

	local inString = false
	local escaped = false
	local depth = 0
	local objectStart = 0

	for i = (arrayStart + 1) to jsonText.count do
	(
		local c = jsonText[i]
		if inString then
		(
			if escaped then
			(
				escaped = false
			)
			else if c == "\\" then
			(
				escaped = true
			)
			else if c == "\"" do
			(
				inString = false
			)
		)
		else
		(
			if c == "\"" then
			(
				inString = true
			)
			else if c == "{" then
			(
				if depth == 0 do objectStart = i
				depth += 1
			)
			else if c == "}" then
			(
				depth -= 1
				if depth == 0 and objectStart > 0 do
				(
					append objects (substring jsonText objectStart (i - objectStart + 1))
					objectStart = 0
				)
			)
			else if c == "]" and depth == 0 do
			(
				exit
			)
		)
	)
	objects
)

fn CloneTools_OC_jsonValueStart objectText key =
(
	local keyToken = "\"" + key + "\""
	local keyPos = findString objectText keyToken
	if keyPos == undefined do return 0

	local i = keyPos + keyToken.count
	while i <= objectText.count and objectText[i] != ":" do i += 1
	if i > objectText.count do return 0

	i += 1
	while i <= objectText.count and (objectText[i] == " " or objectText[i] == "\t" or objectText[i] == "\r" or objectText[i] == "\n") do i += 1
	if i > objectText.count then 0 else i
)

fn CloneTools_OC_jsonString objectText key fallback:"" =
(
	local i = CloneTools_OC_jsonValueStart objectText key
	if i == 0 or objectText[i] != "\"" do return fallback

	i += 1
	local result = ""
	local escaped = false
	while i <= objectText.count do
	(
		local c = objectText[i]
		if escaped then
		(
			if c == "\"" then result += "\"" else
			if c == "\\" then result += "\\" else
			if c == "/" then result += "/" else
			if c == "n" then result += "\n" else
			if c == "r" then result += "\r" else
			if c == "t" then result += "\t" else
				result += c
			escaped = false
		)
		else if c == "\\" then
		(
			escaped = true
		)
		else if c == "\"" then
		(
			exit
		)
		else
		(
			result += c
		)
		i += 1
	)
	result
)

fn CloneTools_OC_jsonFloat objectText key fallback =
(
	local i = CloneTools_OC_jsonValueStart objectText key
	if i == 0 do return fallback

	local token = ""
	while i <= objectText.count and (findString "0123456789+-.eE" objectText[i]) != undefined do
	(
		token += objectText[i]
		i += 1
	)

	local result = fallback
	try (result = token as float) catch ()
	result
)

fn CloneTools_OC_getClipboardText =
(
	local result = ""
	try
	(
		dotNet.loadAssembly "System.Windows.Forms"
		result = ((dotNetClass "System.Windows.Forms.Clipboard").GetText()) as string
	)
	catch ()
	CloneTools_OC_trimText result
)

fn CloneTools_OC_normalizePath value =
(
	local s = CloneTools_OC_trimText value
	s = substituteString s "/" "\\"
	s
)

fn CloneTools_OC_urlDecode value =
(
	local s = value as string
	try (s = ((dotNetClass "System.Uri").UnescapeDataString s) as string) catch ()
	s
)

fn CloneTools_OC_getVaultRoot canvasPath =
(
	local ioDir = dotNetClass "System.IO.Directory"
	local ioPath = dotNetClass "System.IO.Path"
	local root = ioPath.GetDirectoryName canvasPath
	local current = root
	local found = undefined
	while found == undefined and current != undefined and current != "" do
	(
		local obsidianDir = ioPath.Combine current ".obsidian"
		if ioDir.Exists obsidianDir then
			found = current
		else
			current = ioPath.GetDirectoryName current
	)
	if found == undefined then root else found
)

fn CloneTools_OC_isImagePath filePath =
(
	local ext = toLower (getFilenameType filePath)
	findItem #(".png", ".jpg", ".jpeg", ".bmp", ".gif", ".tif", ".tiff", ".tga", ".webp") ext > 0
)

fn CloneTools_OC_resolveCanvasFile canvasPath rawFile =
(
	local ioPath = dotNetClass "System.IO.Path"
	local s = CloneTools_OC_trimText rawFile
	if s == "" do return undefined
	s = CloneTools_OC_urlDecode s

	if matchPattern (toLower s) pattern:"file://*" do
	(
		try
		(
			local uri = dotNetObject "System.Uri" s
			s = uri.LocalPath as string
		)
		catch ()
	)

	s = CloneTools_OC_normalizePath s
	local candidates = #()
	if ioPath.IsPathRooted s then
	(
		append candidates s
	)
	else
	(
		while s.count > 0 and (s[1] == "\\" or s[1] == "/") do s = substring s 2 -1
		local canvasDir = ioPath.GetDirectoryName canvasPath
		local vaultRoot = CloneTools_OC_getVaultRoot canvasPath
		append candidates (ioPath.Combine vaultRoot s)
		append candidates (ioPath.Combine canvasDir s)
	)

	for candidate in candidates where doesFileExist candidate do return candidate
	undefined
)

fn CloneTools_OC_canvasLayer layerName =
(
	local layer = layerManager.getLayerFromName layerName
	if layer == undefined do layer = layerManager.newLayerFromName layerName
	layer
)

fn CloneTools_OC_makeCanvasMaterial imagePath matName =
(
	local mat = standardMaterial name:matName diffuse:(color 0 0 0)
	local diffuseBitmap = bitmapTexture filename:imagePath
	mat.diffuseMap = diffuseBitmap
	mat.diffuseMapEnable = true
	try (mat.selfIllumAmount = 100.0) catch ()
	try (mat.selfIllumination = 100.0) catch ()
	try (mat.showInViewport = true) catch ()

	local bitmapInfo = undefined
	try (bitmapInfo = getBitmapInfo imagePath) catch ()
	if bitmapInfo != undefined and bitmapInfo.count >= 9 and bitmapInfo[9] do
	(
		local alphaBitmap = bitmapTexture filename:imagePath
		try (diffuseBitmap.alphaSource = 2) catch ()
		try (alphaBitmap.monoOutput = 1) catch ()
		try (alphaBitmap.RGBOutput = 1) catch ()
		mat.opacityMap = alphaBitmap
		try (mat.opacityMapEnable = true) catch ()
	)

	try (enableHardwareMaterial mat true) catch ()
	try (showHWTextureMap mat true) catch ()
	mat
)

fn CloneTools_ImportObsidianCanvasImages canvasPath scale:0.1 layerName:undefined selectCreated:true =
(
	local path = CloneTools_OC_normalizePath canvasPath
	if path == "" or not (doesFileExist path) do
	(
		format "Obsidian canvas import: canvas file not found: %\n" path
		return #()
	)

	local jsonText = undefined
	try (jsonText = ((dotNetClass "System.IO.File").ReadAllText path)) catch ()
	if jsonText == undefined do
	(
		format "Obsidian canvas import: could not read %\n" path
		return #()
	)

	local nodeObjects = CloneTools_OC_parseCanvasNodeObjects jsonText
	if nodeObjects.count == 0 do
	(
		format "Obsidian canvas import: no nodes in %\n" path
		return #()
	)

	if layerName == undefined do
		layerName = "ObsidianCanvas_" + (CloneTools_OC_safeName (getFilenameFile path))
	local importLayer = CloneTools_OC_canvasLayer layerName

	local created = #()
	local missing = #()
	local skipped = 0

	undo "Import Obsidian Canvas Images" on
	(
		with redraw off
		(
			for nodeText in nodeObjects do
			(
				local nodeType = CloneTools_OC_jsonString nodeText "type"
				if nodeType == "file" then
				(
					local rawFile = CloneTools_OC_jsonString nodeText "file"
					local imagePath = CloneTools_OC_resolveCanvasFile path rawFile
					if imagePath != undefined and CloneTools_OC_isImagePath imagePath then
					(
						local w = CloneTools_OC_jsonFloat nodeText "width" 100.0
						local h = CloneTools_OC_jsonFloat nodeText "height" 100.0
						local x = CloneTools_OC_jsonFloat nodeText "x" 0.0
						local y = CloneTools_OC_jsonFloat nodeText "y" 0.0
						local nodeId = CloneTools_OC_jsonString nodeText "id"
						local baseName = CloneTools_OC_safeName (getFilenameFile imagePath)
						local objName = uniqueName ("OC_" + baseName + "_")
						local matName = uniqueName ("OC_" + baseName + "_mat_")
						local planeObj = plane name:objName width:(w * scale) length:(h * scale) widthsegs:1 lengthsegs:1 pos:[(x + (w * 0.5)) * scale, -((y + (h * 0.5)) * scale), 0]

						try (planeObj.mapcoords = true) catch ()
						planeObj.showFrozenInGray = false
						planeObj.wireColor = color 90 150 220
						planeObj.material = CloneTools_OC_makeCanvasMaterial imagePath matName

						try (setUserProp planeObj "obsidian_canvas" path) catch ()
						try (setUserProp planeObj "obsidian_node_id" nodeId) catch ()
						try (setUserProp planeObj "obsidian_image" imagePath) catch ()
						try (importLayer.addNode planeObj) catch ()
						append created planeObj
					)
					else
					(
						if rawFile != "" do append missing rawFile
					)
				)
				else
				(
					skipped += 1
				)
			)
		)
	)

	if selectCreated and created.count > 0 do select created
	format "Obsidian canvas import: % image planes created on layer '%'. Missing/non-image files: %. Skipped non-file nodes: %.\n" created.count layerName missing.count skipped
	if missing.count > 0 do format "Missing/non-image: %\n" missing
	created
)

macroScript ImportObsidianCanvasImages
	category:"CloneTools"
	tooltip:"Import image nodes from an Obsidian .canvas path"
	buttonText:"Canvas Images"
(
	on execute do
	(
		local canvasPath = CloneTools_OC_getClipboardText()
		if canvasPath == "" or (toLower (getFilenameType canvasPath)) != ".canvas" do
		(
			format "Copy an Obsidian .canvas path first, or call: CloneTools_ImportObsidianCanvasImages @\"C:\\path\\board.canvas\"\n"
			return false
		)
		CloneTools_ImportObsidianCanvasImages canvasPath
	)
)
