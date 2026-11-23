-- Pastes the clipboard image into the scene as a textured reference plane.
-- Works with copied image data (screenshots, "Copy image" in a browser), image files
-- copied in Explorer, and a copied path to an image file.
-- The plane is sized from the image's pixel dimensions, faces the active view snapped
-- to the nearest world axis, and shows the image unlit.
-- Clipboard image data is saved as PNG to a ClipboardRefs folder next to the scene
-- (or in the project's image folder while the scene is unsaved).
macroScript PasteClipboardImagePlane
	category:"CloneTools"
	tooltip:"Paste Clipboard Image as Reference Plane"
	buttonText:"Paste Image Plane"
(
	local unitsPerPixel = 0.1   -- plane size in system units = image size in pixels * this

	fn report msg =
	(
		format "Paste Image Plane: %\n" msg
		displayTempPrompt ("Paste Image Plane: " + msg) 4000
	)

	fn newRefFile =
	(
		local dir = (if maxFilePath != "" then maxFilePath else (getDir #image) + "\\") + "ClipboardRefs\\"
		makeDir dir all:true
		dir + "clip_" + ((dotNetClass "System.DateTime").Now.ToString "yyyyMMdd_HHmmss_fff") + ".png"
	)

	-- Image files the clipboard refers to. Raw image data is written to disk first.
	fn clipboardImageFiles =
	(
		dotNet.loadAssembly "System.Windows.Forms"
		dotNet.loadAssembly "System.Drawing"
		local clip = dotNetClass "System.Windows.Forms.Clipboard"
		local data = clip.GetDataObject()
		local files = #()
		local file

		if data != undefined do
		(
			if data.GetDataPresent "PNG" then
			(
				-- Browsers and screenshot tools also offer the image as PNG, which keeps
				-- the alpha that Clipboard.GetImage() drops.
				file = newRefFile()
				local fs = dotNetObject "System.IO.FileStream" file (dotNetClass "System.IO.FileMode").Create
				(data.GetData "PNG").CopyTo fs
				fs.Close()
				append files file
			)
			else if clip.ContainsImage() then
			(
				file = newRefFile()
				local img = clip.GetImage()
				img.Save file (dotNetClass "System.Drawing.Imaging.ImageFormat").Png
				img.Dispose()
				append files file
			)
			else if clip.ContainsFileDropList() then
			(
				local dropped = clip.GetFileDropList()
				for i = 0 to dropped.Count - 1 do append files dropped.Item[i]
			)
			else if clip.ContainsText() do
			(
				local copied = trimRight (trimLeft (clip.GetText()) " \t\r\n\"") " \t\r\n\""
				if doesFileExist copied do append files copied
			)
		)
		files
	)

	fn snapToAxis v =
	(
		local a = [abs v.x, abs v.y, abs v.z]
		if a.x >= a.y and a.x >= a.z then [(if v.x < 0 then -1 else 1), 0, 0]
		else if a.y >= a.z then [0, (if v.y < 0 then -1 else 1), 0]
		else [0, 0, (if v.z < 0 then -1 else 1)]
	)

	-- Frame for the plane: X = image right, Y = image up, Z = toward the viewer,
	-- each snapped to a world axis, centred on what the active view looks at.
	fn placementFrame =
	(
		local viewTM = inverse (viewport.getTM())
		local toViewer = viewTM.row3
		local facing = snapToAxis toViewer
		local up = viewTM.row2 - facing * (dot viewTM.row2 facing)
		up = if length up < 0.001 then (if facing.z != 0 then [0, 1, 0] else [0, 0, 1]) else snapToAxis up

		-- A plane at the point the view is centred on would usually sit inside the model and be
		-- hidden by it: slide it along the line of sight until it clears the visible scene.
		local near = 0.0, far = 0.0
		for o in objects where not o.isHiddenInVpt do
		(
			near = amax near (dot o.max facing) (dot o.min facing)
			far = amin far (dot o.max facing) (dot o.min facing)
		)
		local depth = near + 0.01 * (near - far)
		local slide = (depth - dot viewTM.row4 facing) / (dot toViewer facing)
		if viewport.isPerspView() do
		(
			-- Points ahead of the eye have a negative slide. With the eye inside the scene or at
			-- its edge there is no clear spot ahead, so fall back to the view's focus point.
			local focal = viewport.getFocalDistance()
			if -slide < 0.1 * focal do slide = -focal
		)

		matrix3 (cross up facing) up facing (viewTM.row4 + toViewer * slide)
	)

	-- An alpha channel alone says little: screenshots are saved with a fully opaque one.
	-- Samples a 16 x 16 grid that includes the corners and borders.
	fn hasTransparency bm =
	(
		local found = false
		if bm.hasAlpha do
			for iy = 0 to 15 while not found do
				for ix = 0 to 15 while not found do
				(
					local px = getPixels bm [ix * (bm.width - 1) / 15, iy * (bm.height - 1) / 15] 1
					found = px[1].alpha < 255
				)
		found
	)

	fn makeRefMaterial file hasAlpha =
	(
		local base = getFilenameFile file
		local tex = bitmapTexture name:base filename:file
		local mat = standardMaterial name:("Ref_" + base) diffuseMap:tex selfIllumAmount:100 specularLevel:0 twoSided:on
		if hasAlpha do
		(
			tex.alphaSource = 2   -- none: colour stays unmatted, opacity comes from its own map
			mat.opacityMap = bitmapTexture name:(base + "_alpha") filename:file monoOutput:1 rgbOutput:1
		)
		showTextureMap mat on
		mat
	)

	on execute do
	(
		local files = try (clipboardImageFiles()) catch
		(
			format "Paste Image Plane: could not read the clipboard: %\n" (getCurrentException())
			#()
		)
		local frame = placementFrame()
		local created = #()
		local rightEdge = 0.0

		undo "Paste Image Plane" on
		(
			for file in files do
			(
				local bm = try (openBitmap file) catch (undefined)
				if bm != undefined do
				(
					local w = bm.width * unitsPerPixel
					local h = bm.height * unitsPerPixel
					local hasAlpha = hasTransparency bm
					close bm

					-- Several copied files are laid out left to right.
					local x = if created.count == 0 then 0.0 else rightEdge + w * 0.55
					rightEdge = x + w * 0.5

					local ref = plane name:(uniqueName ("Ref_" + (getFilenameFile file) + "_")) \
						width:w length:h widthsegs:1 lengthsegs:1 mapCoords:on realWorldMapSize:off
					ref.transform = preTranslate frame [x, 0, 0]
					ref.material = makeRefMaterial file hasAlpha
					ref.showFrozenInGray = off
					append created ref
				)
			)
		)

		if created.count > 0 then
		(
			select created
			report (created.count as string + " reference plane(s) created")
		)
		else
			report "no image in the clipboard"
	)
)
