/*
    GLTF_Maker v2.0
    Clone-styled .NET UI for creating glTF or USD Preview Surface materials
    from PBR texture sets.
*/

macroscript GLTF_Maker
category:"CloneTools"
tooltip:"GLTF Material Maker"
buttonText:"GLTF Maker"
(
    try(if CloneUI == undefined do fileIn ((getDir #userScripts) + "\\CloneTools\\CloneUI.ms"))catch(try(fileIn ((getFilenamePath (getSourceFileName())) + "..\\Utilities\\CloneUI.ms"))catch())
    try(CloneGLTFMaker_Form.Close())catch()
    try(CloneGLTFMaker_Form.Dispose())catch()
    global CloneGLTFMaker_Form = dotNetObject "System.Windows.Forms.Form"

    local baseColorPath = ""
    local normalPath = ""
    local roughnessPath = ""
    local metalnessPath = ""
    local aoPath = ""
    local ormPath = ""
    local emissionPath = ""
    local alphaPath = ""
    local displacementPath = ""

    fn isORMTexture filename =
    (
        local lowerName = toLower filename
        local ormIndicators = #("occlusionroughnessmetallic", "roughnessmetallicocclusion", "_orm_", "_orm.", "-orm-", "-orm.")
        for indicator in ormIndicators do if findString lowerName indicator != undefined do return true
        local ormPos = findString lowerName "orm"
        if ormPos != undefined do
        (
            local beforeChar = if ormPos > 1 then lowerName[ormPos-1] else "_"
            local afterPos = ormPos + 3
            local afterChar = if afterPos <= lowerName.count then lowerName[afterPos] else "_"
            if (beforeChar == "_" or beforeChar == "-" or beforeChar == " " or ormPos == 1) and \
               (afterChar == "_" or afterChar == "-" or afterChar == "." or afterChar == " " or afterPos > lowerName.count) then return true
        )
        false
    )

    fn getTextureType filename =
    (
        local lowerName = toLower (getFilenameFile filename)
        if isORMTexture lowerName then return #orm
        if findString lowerName "basecolor" != undefined or findString lowerName "base_color" != undefined or findString lowerName "albedo" != undefined or findString lowerName "diffuse" != undefined or findString lowerName "_diff" != undefined or findString lowerName "_col." != undefined or findString lowerName "_col_" != undefined or findString lowerName "_color" != undefined then return #baseColor
        if findString lowerName "normal" != undefined or findString lowerName "_nrm" != undefined or findString lowerName "_nor." != undefined or findString lowerName "_nor_" != undefined then return #normal
        if findString lowerName "roughness" != undefined or findString lowerName "_rough" != undefined or findString lowerName "_rgh" != undefined then return #roughness
        if findString lowerName "metallic" != undefined or findString lowerName "metalness" != undefined or findString lowerName "_met." != undefined or findString lowerName "_met_" != undefined or findString lowerName "_mtl" != undefined then return #metalness
        if (findString lowerName "occlusion" != undefined and findString lowerName "roughness" == undefined) or findString lowerName "_ao." != undefined or findString lowerName "_ao_" != undefined or findString lowerName "ambientocclusion" != undefined then return #ao
        if findString lowerName "emission" != undefined or findString lowerName "emissive" != undefined or findString lowerName "_emit" != undefined or findString lowerName "_glow" != undefined then return #emission
        if findString lowerName "alpha" != undefined or findString lowerName "opacity" != undefined or findString lowerName "transparency" != undefined then return #alpha
        if findString lowerName "displacement" != undefined or findString lowerName "_disp" != undefined or findString lowerName "_height" != undefined then return #displacement
        #unknown
    )

    local frm = CloneUI.skinForm CloneGLTFMaker_Form "GLTF Maker" 520 760
    local shell = CloneUI.addShell frm "GLTF Material Maker" version:"v2.0"
    local pad = shell[1]
    local iW = shell[2]
    local Y = shell[3]

    frm.controls.add (CloneUI.mkLabel "Material Name" (pad+4) Y 100 18 fObj:CloneUI.fSmall cObj:CloneUI.cDim)
    local edt_matName = CloneUI.mkText (pad+120) (Y-2) 260 22 text:"M_Objects"
    frm.controls.add edt_matName
    Y += 30
    local chk_autoDetect = CloneUI.mkCheck "Auto-detect ORM from filename" (pad+4) Y (iW-8) chk:true
    frm.controls.add chk_autoDetect
    Y += 36

    local btn_loadAll = CloneUI.mkBtn "Select Textures" pad Y iW 32
    frm.controls.add btn_loadAll
    Y += 40

    frm.controls.add (CloneUI.mkSep pad Y iW)
    Y += 12
    frm.controls.add (CloneUI.mkLabel "DETECTED MAPS" pad Y iW 18 fObj:CloneUI.fBold cObj:CloneUI.cHead)
    Y += 26

    fn addMapRow labelText y =
    (
        frm.controls.add (CloneUI.mkLabel labelText (pad+4) y 105 18 fObj:CloneUI.fSmall cObj:CloneUI.cDim)
        local t = CloneUI.mkText (pad+116) (y-3) (iW-120) 22
        t.ReadOnly = true
        frm.controls.add t
        t
    )

    local edt_baseColor = addMapRow "Base Color" Y; Y += 28
    local edt_normal = addMapRow "Normal" Y; Y += 28
    local edt_roughness = addMapRow "Roughness" Y; Y += 28
    local edt_metalness = addMapRow "Metalness" Y; Y += 28
    local edt_ao = addMapRow "AO" Y; Y += 28
    local edt_orm = addMapRow "ORM Packed" Y; Y += 28
    local edt_emission = addMapRow "Emission" Y; Y += 28
    local edt_alpha = addMapRow "Alpha" Y; Y += 28
    local edt_disp = addMapRow "Displacement" Y; Y += 34

    frm.controls.add (CloneUI.mkSep pad Y iW)
    Y += 12
    frm.controls.add (CloneUI.mkLabel "TARGET MATERIAL" pad Y iW 18 fObj:CloneUI.fBold cObj:CloneUI.cHead)
    Y += 24

    local rbGLTF = dotNetObject "System.Windows.Forms.RadioButton"
    rbGLTF.Text = "glTF Material"
    rbGLTF.Checked = true
    rbGLTF.Location = dotNetObject CloneUI.ptC (pad+4) Y
    rbGLTF.Size = dotNetObject CloneUI.szC 160 22
    rbGLTF.ForeColor = CloneUI.cText
    rbGLTF.BackColor = CloneUI.cBg
    rbGLTF.Font = CloneUI.fNorm
    frm.controls.add rbGLTF

    local rbUSD = dotNetObject "System.Windows.Forms.RadioButton"
    rbUSD.Text = "USD Preview Surface"
    rbUSD.Location = dotNetObject CloneUI.ptC (pad+180) Y
    rbUSD.Size = dotNetObject CloneUI.szC 190 22
    rbUSD.ForeColor = CloneUI.cText
    rbUSD.BackColor = CloneUI.cBg
    rbUSD.Font = CloneUI.fNorm
    frm.controls.add rbUSD
    Y += 34

    frm.controls.add (CloneUI.mkLabel "WORKFLOW" pad Y iW 18 fObj:CloneUI.fBold cObj:CloneUI.cHead)
    Y += 24
    local rbStandard = dotNetObject "System.Windows.Forms.RadioButton"
    rbStandard.Text = "Standard PBR"
    rbStandard.Checked = true
    rbStandard.Location = dotNetObject CloneUI.ptC (pad+4) Y
    rbStandard.Size = dotNetObject CloneUI.szC 160 22
    rbStandard.ForeColor = CloneUI.cText
    rbStandard.BackColor = CloneUI.cBg
    rbStandard.Font = CloneUI.fNorm
    frm.controls.add rbStandard

    local rbORM = dotNetObject "System.Windows.Forms.RadioButton"
    rbORM.Text = "ORM Packed"
    rbORM.Location = dotNetObject CloneUI.ptC (pad+180) Y
    rbORM.Size = dotNetObject CloneUI.szC 160 22
    rbORM.ForeColor = CloneUI.cText
    rbORM.BackColor = CloneUI.cBg
    rbORM.Font = CloneUI.fNorm
    frm.controls.add rbORM
    Y += 40

    local btn_clear = CloneUI.mkBtn "Clear" pad Y ((iW - 8) / 2) 30
    local btn_create = CloneUI.mkBtn "Create Material" (pad + ((iW - 8) / 2) + 8) Y ((iW - 8) / 2) 30
    frm.controls.add btn_clear
    frm.controls.add btn_create
    Y += 40

    local lbl_status = CloneUI.mkLabel "" pad Y iW 36 fObj:CloneUI.fSmall cObj:CloneUI.cDim
    frm.controls.add lbl_status
    Y += 42

    local credit = CloneUI.mkLabel "clone" 0 Y 520 16 fObj:CloneUI.fSmall cObj:(CloneUI.clr.FromArgb 55 55 55)
    credit.TextAlign = CloneUI.alC.MiddleCenter
    frm.controls.add credit
    frm.Size = dotNetObject CloneUI.szC 520 (Y + 24)

    fn clearAllPaths =
    (
        baseColorPath = ""; normalPath = ""; roughnessPath = ""; metalnessPath = ""; aoPath = ""; ormPath = ""; emissionPath = ""; alphaPath = ""; displacementPath = ""
        edt_baseColor.Text = ""; edt_normal.Text = ""; edt_roughness.Text = ""; edt_metalness.Text = ""; edt_ao.Text = ""; edt_orm.Text = ""; edt_emission.Text = ""; edt_alpha.Text = ""; edt_disp.Text = ""
    )

    fn processFiles files =
    (
        local foundORM = false
        local assignedCount = 0
        for f in files do
        (
            local ext = toLower (getFilenameType f)
            if findItem #(".png", ".jpg", ".jpeg", ".tga", ".tif", ".tiff", ".bmp", ".exr") ext > 0 do
            (
                local texType = getTextureType f
                case texType of
                (
                    #baseColor: (baseColorPath = f; edt_baseColor.Text = getFilenameFile f; assignedCount += 1)
                    #normal: (normalPath = f; edt_normal.Text = getFilenameFile f; assignedCount += 1)
                    #roughness: (roughnessPath = f; edt_roughness.Text = getFilenameFile f; assignedCount += 1)
                    #metalness: (metalnessPath = f; edt_metalness.Text = getFilenameFile f; assignedCount += 1)
                    #ao: (aoPath = f; edt_ao.Text = getFilenameFile f; assignedCount += 1)
                    #orm: (ormPath = f; edt_orm.Text = getFilenameFile f; foundORM = true; assignedCount += 1)
                    #emission: (emissionPath = f; edt_emission.Text = getFilenameFile f; assignedCount += 1)
                    #alpha: (alphaPath = f; edt_alpha.Text = getFilenameFile f; assignedCount += 1)
                    #displacement: (displacementPath = f; edt_disp.Text = getFilenameFile f; assignedCount += 1)
                )
            )
        )
        if foundORM and chk_autoDetect.Checked do rbORM.Checked = true
        assignedCount
    )

    fn createBitmapNode filePath =
    (
        if filePath != "" and doesFileExist filePath then
        (
            local bmp = Bitmaptexture filename:filePath
            bmp.name = getFilenameFile filePath
            return bmp
        )
        undefined
    )

    fn putMaterialInEditor mat =
    (
        try(medit.PutMtlToMtlEditor mat activeMeditSlot)catch(meditMaterials[activeMeditSlot] = mat)
        try(medit.SetActiveMtlSlot activeMeditSlot true)catch()
    )

    fn onLoadTextures s e =
    (
        local ofd = dotNetObject "System.Windows.Forms.OpenFileDialog"
        ofd.Title = "Select Texture Maps"
        ofd.Filter = "Image Files (*.png;*.jpg;*.jpeg;*.tga;*.tif;*.tiff;*.bmp;*.exr)|*.png;*.jpg;*.jpeg;*.tga;*.tif;*.tiff;*.bmp;*.exr|All Files (*.*)|*.*"
        ofd.Multiselect = true
        if ofd.ShowDialog() == (dotNetClass "System.Windows.Forms.DialogResult").OK do
        (
            clearAllPaths()
            local maxFiles = #()
            for i = 1 to ofd.FileNames.count do append maxFiles ofd.FileNames[i]
            local cnt = processFiles maxFiles
            lbl_status.Text = "Assigned " + (cnt as string) + " of " + (maxFiles.count as string) + " textures"
            local firstName = getFilenameFile maxFiles[1]
            local suffixes = #("_basecolor", "_base_color", "_albedo", "_diffuse", "_diff", "_normal", "_nrm", "_roughness", "_rough", "_metallic", "_metalness", "_ao", "_occlusion", "_orm", "_emission", "_emissive", "_alpha", "_opacity", "_disp", "_displacement", "_height")
            local baseName = firstName
            for suffix in suffixes do
            (
                local pos = findString (toLower baseName) suffix
                if pos != undefined do baseName = substring baseName 1 (pos-1)
            )
            if baseName != "" and baseName != firstName do edt_matName.Text = "M_" + baseName
        )
    )

    fn onClear s e =
    (
        clearAllPaths()
        rbStandard.Checked = true
        lbl_status.Text = "Cleared all maps"
    )

    fn onCreateMaterial s e =
    (
        local isUSD = rbUSD.Checked
        if not isUSD and (classof glTFMaterial) == UndefinedClass do
        (
            messageBox "glTFMaterial class not found.\n\nPlease ensure the Babylon.js Exporter plugin is installed." title:"Error"
            return()
        )
        if isUSD and (classof MaxUsdPreviewSurface) == UndefinedClass do
        (
            messageBox "MaxUsdPreviewSurface class not found.\n\nPlease ensure the USD plugin is installed." title:"Error"
            return()
        )

        local matName = edt_matName.Text
        if matName == "" do matName = "M_Objects"
        local finalMat = undefined
        local mapsAssigned = 0

        if isUSD then
        (
            finalMat = MaxUsdPreviewSurface name:matName
            finalMat.diffuseColor = color 255 255 255
            if baseColorPath != "" do (local bmp = createBitmapNode baseColorPath; if bmp != undefined do (finalMat.diffuseColor_map = bmp; mapsAssigned += 1))
            if normalPath != "" do (local bmp = createBitmapNode normalPath; if bmp != undefined do (finalMat.normal_map = bmp; mapsAssigned += 1))
            if alphaPath != "" do (local bmp = createBitmapNode alphaPath; if bmp != undefined do (finalMat.opacity_map = bmp; mapsAssigned += 1))
            if emissionPath != "" do (local bmp = createBitmapNode emissionPath; if bmp != undefined do (finalMat.emissiveColor_map = bmp; mapsAssigned += 1))
            if displacementPath != "" do (local bmp = createBitmapNode displacementPath; if bmp != undefined do (finalMat.displacement_map = bmp; mapsAssigned += 1))
            if rbORM.Checked then
            (
                if ormPath != "" do
                (
                    local bmp = createBitmapNode ormPath
                    if bmp != undefined do (finalMat.occlusion_map = bmp; finalMat.roughness_map = bmp; finalMat.metallic_map = bmp; mapsAssigned += 1)
                )
            )
            else
            (
                if roughnessPath != "" do (local bmp = createBitmapNode roughnessPath; if bmp != undefined do (finalMat.roughness_map = bmp; mapsAssigned += 1))
                if metalnessPath != "" do (local bmp = createBitmapNode metalnessPath; if bmp != undefined do (finalMat.metallic_map = bmp; mapsAssigned += 1))
                if aoPath != "" do (local bmp = createBitmapNode aoPath; if bmp != undefined do (finalMat.occlusion_map = bmp; mapsAssigned += 1))
            )
        )
        else
        (
            finalMat = glTFMaterial name:matName
            if baseColorPath != "" do (local bmp = createBitmapNode baseColorPath; if bmp != undefined do (finalMat.baseColorMap = bmp; mapsAssigned += 1))
            if normalPath != "" do (local bmp = createBitmapNode normalPath; if bmp != undefined do (finalMat.normalMap = bmp; mapsAssigned += 1))
            if alphaPath != "" do (local bmp = createBitmapNode alphaPath; if bmp != undefined do (finalMat.alphaMap = bmp; mapsAssigned += 1))
            if emissionPath != "" do (local bmp = createBitmapNode emissionPath; if bmp != undefined do (finalMat.emissionMap = bmp; mapsAssigned += 1))
            if rbORM.Checked then
            (
                if ormPath != "" do
                (
                    local bmp = createBitmapNode ormPath
                    if bmp != undefined do
                    (
                        try(finalMat.ambientOcclusionMap = bmp)catch()
                        try(finalMat.roughnessMetallicMap = bmp)catch()
                        try(finalMat.roughnessMap = bmp)catch()
                        try(finalMat.metalnessMap = bmp)catch()
                        mapsAssigned += 1
                    )
                )
            )
            else
            (
                if roughnessPath != "" do (local bmp = createBitmapNode roughnessPath; if bmp != undefined do (try(finalMat.roughnessMap = bmp; mapsAssigned += 1)catch()))
                if metalnessPath != "" do (local bmp = createBitmapNode metalnessPath; if bmp != undefined do (try(finalMat.metalnessMap = bmp; mapsAssigned += 1)catch()))
                if aoPath != "" do (local bmp = createBitmapNode aoPath; if bmp != undefined do (try(finalMat.ambientOcclusionMap = bmp; mapsAssigned += 1)catch()))
            )
        )

        putMaterialInEditor finalMat
        local modeStr = if rbORM.Checked then "ORM" else "Standard PBR"
        local typeStr = if isUSD then "USD" else "glTF"
        lbl_status.Text = "Created: " + matName + " (" + typeStr + "/" + modeStr + ") - " + (mapsAssigned as string) + " maps"
    )

    dotNet.addEventHandler btn_loadAll "Click" onLoadTextures
    dotNet.addEventHandler btn_clear "Click" onClear
    dotNet.addEventHandler btn_create "Click" onCreateMaterial
    append CloneUI_handlers #(onLoadTextures, onClear, onCreateMaterial)
    frm.Show()
)
