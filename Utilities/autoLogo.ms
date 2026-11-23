-- This maxscript processes SVG logo files by converting them to high-DPI PNGs,
-- applying alpha bleed, and assigning them as textures to 3D models in the scene.

try(if CloneUI == undefined do fileIn ((getDir #userScripts) + "\\CloneTools\\CloneUI.ms"))catch(try(fileIn ((getFilenamePath (getSourceFileName())) + "CloneUI.ms"))catch())
global CloneSvgLogoPipeline_Form
global CloneSvgLogoPipeline_dpiBox
global CloneSvgLogoPipeline_rbSingle

fn singleSvgToTexture dpiValue = (
    local svgPath = getOpenFileName caption:"Select Single SVG File:" types:"SVG (*.svg)|*.svg|" 
    if svgPath != undefined do (
        print ("Processing single: " + (getFilenameFile svgPath) + " at " + dpiValue as string + " DPI")
        
        -- Import the SVG first
        local importSuccess = importFile svgPath #noPrompt
        if not importSuccess do (
            messageBox ("Failed to import: " + svgPath)
            return undefined
        )
        
        local baseName = getFilenameFile svgPath
        local dir = getFilenamePath svgPath
        local pngPath = dir + baseName + ".png"
        local bleedPng = dir + baseName + "_bleed.png"
        
        -- Fix paths: Replace \ with / for DOS compatibility (double \\ for literal backslash)
        local svgPathFixed = substituteString svgPath "\\" "/"
        local pngPathFixed = substituteString pngPath "\\" "/"
        local bleedPngFixed = substituteString bleedPng "\\" "/"
        
        print ("Fixed paths - SVG: " + svgPathFixed + " PNG: " + pngPathFixed + " Bleed: " + bleedPngFixed)  -- Debug: Verify in listener
        
        -- Convert SVG to high-DPI PNG with ImageMagick (transparent bg, non-blocking)
        local magickCmd = "magick convert -density " + dpiValue as string + " -background none \"" + svgPathFixed + "\" \"" + pngPathFixed + "\""
        print ("Running: " + magickCmd)
        HiddenDOSCommand magickCmd donotwait:true
        sleep 1.0  -- Pause for stability
        if not (doesFileExist pngPath) do (
            messageBox ("Magick failed for " + baseName + ". Cmd: " + magickCmd)
            return undefined
        )
        
        -- Run alpha-bleed.exe
        local bleedCmd = "alpha-bleed.exe \"" + pngPathFixed + "\" \"" + bleedPngFixed + "\""
        print ("Running: " + bleedCmd)
        HiddenDOSCommand bleedCmd donotwait:true
        sleep 1.0
        if not (doesFileExist bleedPng) do (
            messageBox ("Bleed failed for " + baseName + ". Cmd: " + bleedCmd)
            return undefined
        )
        
        -- Find the imported model with SVG import suffix
        local modelName = baseName + ".svg_FillEditPoly"
        local model = getNodeByName modelName exact:true ignoreCase:false
        if model == undefined then (
            model = getNodeByName baseName exact:true ignoreCase:false
        )
        if model != undefined then (
            -- Add UVW Map modifier first for proper texture coords (channel 0 for maps)
            addModifier model (UVWMap maptype:0 channel:0)  -- Planar mapping, channel 0; tweak if needed
            
            -- Add Shell modifier for thickness
            addModifier model (Shell thickness:0.1 outerAmount:1.0 innerAmount:0.0)  -- 0.1 unit thickness, full outer; adjust as needed
            
            -- Apply material
            local mat = StandardMaterial()
            mat.diffuseMap = BitmapTexture filename:bleedPng
            showTextureMap mat true  -- Optional: show map in viewport
            model.material = mat
            
            -- Rename to baseName
            model.name = baseName
            
            print ("Done: " + model.name)
            messageBox ("Single processed: " + model.name + " is thicc and textured at " + dpiValue as string + " DPI.")
        ) else (
            messageBox ("Model not found for: " + baseName)
        )
    )
)

fn batchSvgToTexture dpiValue = (
    local folderPath = getSavePath caption:"Select Folder with SVG Files:"  -- Picks output/input dir
    if folderPath != undefined do (
        -- Fix any trailing BS in folderPath
        folderPath = trimRight folderPath "\\"  -- Strip extra backslashes
        folderPath += "/"  -- Use / for cross-compat, but Windows digs it
        
        print ("Selected folder: " + folderPath)  -- Debug: Confirm path
        
        local searchPath = folderPath + "*.svg"  -- Search string
        print ("Searching: " + searchPath)  -- Debug: Exact glob
        
        local svgFiles = getFiles searchPath  -- Grabs all .svg in folder
        print ("getFiles returned: " + svgFiles.count as string + " matches")  -- Debug: Raw count
        
        -- Extra debug: List all files in dir to see what's actually there
        local allFiles = getFiles (folderPath + "*.*")
        print ("All files in dir (" + allFiles.count as string + "):")
        for f in allFiles do print ("  " + (getFilenameFile f) + getFilenameType f)
        
        if svgFiles.count == 0 do (
            messageBox ("No SVG files found in " + folderPath + "—check extensions (.svg or .SVG?) or subdirs. See listener for file list.")
            return undefined
        )
        
        print ("Batching " + svgFiles.count as string + " SVGs at " + dpiValue as string + " DPI...")
        
        for svgPath in svgFiles do (
            print ("Processing: " + (getFilenameFile svgPath))
            
            -- Import the SVG first
            local importSuccess = importFile svgPath #noPrompt
            if not importSuccess do (
                messageBox ("Failed to import: " + svgPath)
                continue
            )
            
            local baseName = getFilenameFile svgPath
            local dir = getFilenamePath svgPath
            local pngPath = dir + baseName + ".png"
            local bleedPng = dir + baseName + "_bleed.png"
            
            -- Fix paths: Replace \ with / for DOS compatibility (double \\ for literal backslash)
            local svgPathFixed = substituteString svgPath "\\" "/"
            local pngPathFixed = substituteString pngPath "\\" "/"
            local bleedPngFixed = substituteString bleedPng "\\" "/"
            
            print ("Fixed paths - SVG: " + svgPathFixed + " PNG: " + pngPathFixed + " Bleed: " + bleedPngFixed)  -- Debug: Verify in listener
            
            -- Convert SVG to high-DPI PNG with ImageMagick (transparent bg, non-blocking)
            local magickCmd = "magick convert -density " + dpiValue as string + " -background none \"" + svgPathFixed + "\" \"" + pngPathFixed + "\""
            print ("Running: " + magickCmd)
            HiddenDOSCommand magickCmd donotwait:true
            sleep 1.0  -- Upped pause for batch stability
            if not (doesFileExist pngPath) do (
                messageBox ("Magick failed for " + baseName + ". Cmd: " + magickCmd)
                continue
            )
            
            -- Run alpha-bleed.exe
            local bleedCmd = "alpha-bleed.exe \"" + pngPathFixed + "\" \"" + bleedPngFixed + "\""
            print ("Running: " + bleedCmd)
            HiddenDOSCommand bleedCmd donotwait:true
            sleep 1.0
            if not (doesFileExist bleedPng) do (
                messageBox ("Bleed failed for " + baseName + ". Cmd: " + bleedCmd)
                continue
            )
            
            -- Find the imported model with SVG import suffix
            local modelName = baseName + ".svg_FillEditPoly"
            local model = getNodeByName modelName exact:true ignoreCase:false
            if model == undefined then (
                model = getNodeByName baseName exact:true ignoreCase:false
            )
            if model != undefined then (
                -- Add UVW Map modifier first for proper texture coords (channel 0 for maps)
                addModifier model (UVWMap maptype:0 channel:0)  -- Planar mapping, channel 0; tweak if needed
                
                -- Add Shell modifier for thickness
                addModifier model (Shell thickness:0.1 outerAmount:1.0 innerAmount:0.0)  -- 0.1 unit thickness, full outer; adjust as needed
                
                -- Apply material
                local mat = StandardMaterial()
                mat.diffuseMap = BitmapTexture filename:bleedPng
                showTextureMap mat true  -- Optional: show map in viewport
                model.material = mat
                
                -- Rename to baseName
                model.name = baseName
                
                print ("Done: " + model.name)
            ) else (
                messageBox ("Model not found for: " + baseName)
            )
        )
        print "Batch complete—your logos are thicc and ready."
        messageBox ("Batch done: " + svgFiles.count as string + " logos processed at " + dpiValue as string + " DPI.")
    )
)

-- Main launcher: Single unified dialog
fn launchSvgProcessor = (
    try(CloneSvgLogoPipeline_Form.Close())catch()
    try(CloneSvgLogoPipeline_Form.Dispose())catch()
    CloneSvgLogoPipeline_Form = dotNetObject "System.Windows.Forms.Form"

    local frm = CloneUI.skinForm CloneSvgLogoPipeline_Form "SVG Logo Pipeline" 340 390
    local shell = CloneUI.addShell frm "SVG Logo Pipeline" version:"v1.0"
    local pad = shell[1]
    local iW = shell[2]
    local Y = shell[3]

    frm.controls.add (CloneUI.mkLabel "DPI for Rasterization" (pad+4) Y 180 18 fObj:CloneUI.fSmall cObj:CloneUI.cDim)
    CloneSvgLogoPipeline_dpiBox = CloneUI.mkNumeric (pad+198) (Y-2) 90 100 2000 600
    CloneSvgLogoPipeline_dpiBox.Increment = 50
    frm.controls.add CloneSvgLogoPipeline_dpiBox
    Y += 38

    frm.controls.add (CloneUI.mkSep pad Y iW)
    Y += 12
    frm.controls.add (CloneUI.mkLabel "MODE" pad Y iW 18 fObj:CloneUI.fBold cObj:CloneUI.cHead)
    Y += 26

    CloneSvgLogoPipeline_rbSingle = dotNetObject "System.Windows.Forms.RadioButton"
    CloneSvgLogoPipeline_rbSingle.Text = "Single File"
    CloneSvgLogoPipeline_rbSingle.Location = dotNetObject CloneUI.ptC (pad+4) Y
    CloneSvgLogoPipeline_rbSingle.Size = dotNetObject CloneUI.szC (iW-8) 22
    CloneSvgLogoPipeline_rbSingle.ForeColor = CloneUI.cText
    CloneSvgLogoPipeline_rbSingle.BackColor = CloneUI.cBg
    CloneSvgLogoPipeline_rbSingle.Font = CloneUI.fNorm
    CloneSvgLogoPipeline_rbSingle.Checked = true
    frm.controls.add CloneSvgLogoPipeline_rbSingle
    Y += 26

    local rbBatch = dotNetObject "System.Windows.Forms.RadioButton"
    rbBatch.Text = "Batch Folder"
    rbBatch.Location = dotNetObject CloneUI.ptC (pad+4) Y
    rbBatch.Size = dotNetObject CloneUI.szC (iW-8) 22
    rbBatch.ForeColor = CloneUI.cText
    rbBatch.BackColor = CloneUI.cBg
    rbBatch.Font = CloneUI.fNorm
    frm.controls.add rbBatch
    Y += 38

    local btnProcess = CloneUI.mkBtn "Process SVGs" pad Y ((iW - 8) / 2) 30
    local btnCancel = CloneUI.mkBtn "Cancel" (pad + ((iW - 8) / 2) + 8) Y ((iW - 8) / 2) 30
    frm.controls.add btnProcess
    frm.controls.add btnCancel
    Y += 46

    local credit = CloneUI.mkLabel "clone" 0 Y 340 16 fObj:CloneUI.fSmall cObj:(CloneUI.clr.FromArgb 55 55 55)
    credit.TextAlign = CloneUI.alC.MiddleCenter
    frm.controls.add credit
    frm.Size = dotNetObject CloneUI.szC 340 (Y + 24)

    fn onSvgProcess s e =
    (
        local dpiValue = CloneSvgLogoPipeline_dpiBox.Value as integer
        CloneSvgLogoPipeline_Form.Close()
        if CloneSvgLogoPipeline_rbSingle.Checked then singleSvgToTexture dpiValue else batchSvgToTexture dpiValue
    )
    fn onSvgCancel s e = CloneSvgLogoPipeline_Form.Close()
    dotNet.addEventHandler btnProcess "Click" onSvgProcess
    dotNet.addEventHandler btnCancel "Click" onSvgCancel
    append CloneUI_handlers #(onSvgProcess, onSvgCancel)
    frm.Show()
)

launchSvgProcessor()
