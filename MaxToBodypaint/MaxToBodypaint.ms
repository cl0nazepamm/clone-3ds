/*
    MaxToBodypaint.ms
    -----------------
    One click: the selected meshes go to Cinema 4D (R20) for painting in BodyPaint.

    Each mesh goes as it is shown (modifiers and skin evaluated; no skin, bones or animation),
    written as OBJ by this script: polygons as they are (quads and n-gons), UVs (map channel 1)
    and per-face materials named as in Max (multi/sub: by material ID). The MTL only names the
    materials; send.json lists each one's maps with their full paths, and MaxToBodypaint.pyp in
    Cinema 4D sets them up, referenced in place: textures are never copied.
      base colour (OpenPBR/Physical base_color_map, Standard diffuse)  -> Luminance
      opacity (OpenPBR geometry_opacity_map, Physical cutout_map,
               Standard opacity; a bitmap set to its alpha output keeps using alpha) -> Alpha
    Slots switched off in Max are not sent. Cinema 4D adds the smoothing (Phong) on import. Max's
    own OBJ exporter and its settings are not used.

    Files: send.obj, send.mtl, send.json in %LOCALAPPDATA%\MaxToBodypaint\ (overwritten by each
    send; send.json is written last and tells Cinema 4D a send is ready).

    Install: drag this file into 3ds Max once. The button: Customize > Customize User Interface >
    Category "CloneTools" > "To BodyPaint" (drag it onto a toolbar or a quad menu).
*/

macroScript SendToBodypaint category:"CloneTools" buttonText:"To BodyPaint" tooltip:"Send the selected meshes to Cinema 4D BodyPaint"
(
    -- first bitmap in a map tree (a bitmap inside Color Correction, Mix, ...), breadth first
    fn firstBitmap t =
    (
        local queue = #(t), found = undefined, i = 1
        while found == undefined and i <= queue.count do
        (
            local x = queue[i]
            i += 1
            if x != undefined do
            (
                if classOf x == Bitmaptexture then found = x
                else for k = 1 to (getNumSubTexmaps x) do append queue (getSubTexmap x k)
            )
        )
        found
    )

    -- the bitmap in a material's map slot, when the slot is on: #(full path, uses the image's
    -- alpha) or undefined. slots: #(#(map property, on/off property), ...); the first found wins.
    fn slotBitmap m slots =
    (
        local b = undefined
        for s in slots do
            if b == undefined and isProperty m s[1] and (not (isProperty m s[2]) or (getProperty m s[2]) != false) do
                b = firstBitmap (getProperty m s[1])
        if b == undefined or b.filename == undefined or b.filename == "" then undefined else
        (
            local full = mapPaths.getFullFilePath b.filename
            #(substituteString (if full != "" then full else b.filename) "\\" "/", b.monoOutput == 1)
        )
    )

    fn jsonText s = "\"" + (substituteString (substituteString s "\\" "\\\\") "\"" "\\\"") + "\""

    -- a material's maps for Cinema 4D as a JSON object, or undefined when it has none
    fn materialJson m =
    (
        local color = slotBitmap m #(#(#base_color_map, #base_color_map_on), #(#diffuseMap, #diffuseMapEnable))
        -- OpenPBR opacity, Physical cutout (not its transparency: that is glass), Standard opacity
        local opacity = slotBitmap m #(#(#geometry_opacity_map, #geometry_opacity_map_on), #(#cutout_map, #cutout_map_on), #(#opacityMap, #opacityMapEnable))
        local parts = #()
        if color != undefined do append parts ("\"color\": " + jsonText color[1])
        if opacity != undefined do
        (
            append parts ("\"opacity\": " + jsonText opacity[1])
            append parts ("\"opacityAlpha\": " + (if opacity[2] then "true" else "false"))
        )
        if parts.count == 0 then undefined else
        (
            local s = "{"
            for i = 1 to parts.count do s += (if i > 1 then ", " else "") + parts[i]
            s + "}"
        )
    )

    -- OBJ/MTL names have no spaces
    fn objName s =
    (
        local r = substituteString (trimLeft (trimRight s)) " " "_"
        if r == "" then "unnamed" else r
    )

    -- the material a face shows: multi/sub by material ID, as Max renders it
    fn faceMaterial m id =
    (
        if classOf m != Multimaterial then m
        else if m.materialList.count == 0 then undefined
        else
        (
            local i = findItem m.materialIDList id
            m.materialList[if i > 0 then i else (mod (id - 1) m.materialList.count) + 1]
        )
    )

    on execute do
    (
        local meshes = for o in selection where superClassOf o == GeometryClass and not o.isHiddenInVpt collect o
        if meshes.count == 0 then messageBox "Select the (visible) meshes to send first." title:"To BodyPaint"
        else
        (
            local dir = (systemTools.getEnvVariable "LOCALAPPDATA") + "\\MaxToBodypaint\\"
            makeDir dir all:true
            local objPath = dir + "send.obj"
            local cmPerUnit = 1.0 / (units.decodeValue "1cm")   -- OBJ in cm, as Cinema 4D reads it
            local matNames = #(), matMaps = #()
            local faces = 0
            local f = createFile objPath encoding:#utf8 writeBOM:false
            format "# MaxToBodypaint (3ds Max -> Cinema 4D BodyPaint)\nmtllib send.mtl\n" to:f
            local vBase = 0, tBase = 0
            with undo off, redraw off
            (
                for o in meshes do
                (
                    -- Topology: a temporary copy collapsed to Editable Poly keeps the polygons, UVs
                    -- and material IDs exactly as they are (a snapshot goes through triangles and
                    -- rebuilds them differently). Positions: the world-space mesh as shown, skin and
                    -- modifiers evaluated at the current frame. A collapsed skinned copy can't give
                    -- those: Skin already outputs world positions, so its node transform (e.g. an
                    -- FBX import's Y-up rotation) would be applied twice. Same vertices, same order.
                    local c = copy o
                    convertToPoly c
                    local shown = snapshotAsMesh o
                    local nv = polyop.getNumVerts c, nf = polyop.getNumFaces c
                    local useShown = (getNumVerts shown) == nv
                    if not useShown do format "To BodyPaint: % changes vertex count when collapsed; positions from the collapsed copy\n" o.name
                    local hasUV = polyop.getMapSupport c 1
                    local nt = if hasUV then polyop.getNumMapVerts c 1 else 0
                    format "o %\ng %\n" (objName o.name) (objName o.name) to:f
                    -- Max is Z up; OBJ (and Cinema 4D's reader) Y up
                    for i = 1 to nv do
                    (
                        local p = (if useShown then getVert shown i else polyop.getVert c i node:c) * cmPerUnit
                        format "v % % %\n" p.x p.z (-p.y) to:f
                    )
                    delete shown
                    for i = 1 to nt do (local t = polyop.getMapVert c 1 i; format "vt % %\n" t.x t.y to:f)
                    local last = ""
                    for fi = 1 to nf do
                    (
                        local m = faceMaterial o.material (polyop.getFaceMatID c fi)
                        local mn = if m == undefined then "default" else objName m.name
                        if mn != last do
                        (
                            format "usemtl %\n" mn to:f
                            last = mn
                            if findItem matNames mn == 0 do
                            (
                                append matNames mn
                                append matMaps (if m == undefined then undefined else materialJson m)
                            )
                        )
                        local vs = polyop.getFaceVerts c fi
                        local ts = if hasUV then polyop.getMapFace c 1 fi else #()
                        format "f" to:f
                        for k = 1 to vs.count do
                            if hasUV then format " %/%" (vs[k] + vBase) (ts[k] + tBase) to:f else format " %" (vs[k] + vBase) to:f
                        format "\n" to:f
                    )
                    vBase += nv
                    tBase += nt
                    faces += nf
                    delete c
                )
            )
            close f

            -- the MTL only names the materials: maps come from send.json, never copied
            local m = createFile (dir + "send.mtl") encoding:#utf8 writeBOM:false
            for n in matNames do format "newmtl %\nKd 1 1 1\n\n" n to:m
            close m

            -- send.json last: Cinema 4D picks the send up when it appears
            local id = ((dotNetClass "System.DateTime").Now).ToString "yyyyMMdd_HHmmss_fff"
            local textures = for i = 1 to matNames.count where matMaps[i] != undefined collect ((jsonText matNames[i]) + ": " + matMaps[i])
            local j = createFile (dir + "send.json") encoding:#utf8 writeBOM:false
            format "{\n  \"id\": %,\n  \"obj\": %,\n  \"objects\": [" (jsonText id) (jsonText (substituteString objPath "\\" "/")) to:j
            for i = 1 to meshes.count do format "%%" (if i > 1 then ", " else "") (jsonText (objName meshes[i].name)) to:j
            format "],\n  \"materials\": {" to:j
            for i = 1 to textures.count do format "%\n    %" (if i > 1 then "," else "") textures[i] to:j
            format "\n  }\n}\n" to:j
            close j
            local msg = "To BodyPaint: " + meshes.count as string + " mesh(es), " + faces as string + " faces, " + textures.count as string + " material(s) with maps sent"
            displayTempPrompt msg 4000
            format "%\n" msg
        )
    )
)
