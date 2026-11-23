-- Offset Material IDs Script for 3ds Max
-- This script offsets the material IDs of faces in selected Editable Poly or Editable Mesh objects by a specified number.

macroScript OffsetMaterialIDs
category:"CloneTools"
toolTip:"Offset Material IDs"
buttonText:"Offset Mat IDs"
(
    try(if CloneUI == undefined do fileIn ((getDir #userScripts) + "\\CloneTools\\CloneUI.ms"))catch(try(fileIn ((getFilenamePath (getSourceFileName())) + "..\\Utilities\\CloneUI.ms"))catch())
    try(OffsetMaterialIDs_Form.Close())catch()
    try(OffsetMaterialIDs_Form.Dispose())catch()
    global OffsetMaterialIDs_Form = dotNetObject "System.Windows.Forms.Form"
    local frm = CloneUI.skinForm OffsetMaterialIDs_Form "Offset Material IDs" 340 330
    local shell = CloneUI.addShell frm "Material ID Offset" version:"v1.0"
    local pad = shell[1]
    local iW = shell[2]
    local Y = shell[3]

    frm.controls.add (CloneUI.mkLabel "Offset Amount" (pad+4) Y 150 18 fObj:CloneUI.fSmall cObj:CloneUI.cDim)
    local offsetBox = CloneUI.mkNumeric (pad+168) (Y-2) 120 -1000 1000 2
    frm.controls.add offsetBox
    Y += 36

    local applyButton = CloneUI.mkBtn "Apply Offset" pad Y iW 30
    frm.controls.add applyButton
    Y += 46

    local credit = CloneUI.mkLabel "clone" 0 Y 340 16 fObj:CloneUI.fSmall cObj:(CloneUI.clr.FromArgb 55 55 55)
    credit.TextAlign = CloneUI.alC.MiddleCenter
    frm.controls.add credit
    frm.Size = dotNetObject CloneUI.szC 340 (Y + 24)

    fn applyMaterialIDOffset offset =
    (
        if offset == 0 then
        (
            messageBox "Offset is 0. No changes will be made."
            return()
        )

        undo "Offset Mat IDs" on
        (
            for obj in selection where (superClassOf obj == GeometryClass) do
            (
                local base = obj.baseObject
                if (classOf base == Editable_Poly) then
                (
                    for f = 1 to polyOp.getNumFaces obj do
                    (
                        local currentID = polyOp.getFaceMatID obj f
                        local newID = currentID + offset
                        if newID < 1 then newID = 1
                        polyOp.setFaceMatID obj f newID
                    )
                )
                else if (classOf base == Editable_Mesh) then
                (
                    for f = 1 to meshOp.getNumFaces obj do
                    (
                        local currentID = getFaceMatID obj f
                        local newID = currentID + offset
                        if newID < 1 then newID = 1
                        setFaceMatID obj f newID
                    )
                    update obj
                )
                else
                (
                    messageBox ("Object " + obj.name + " is not an Editable Poly or Mesh. Skipping.")
                )
            )
        )
        messageBox "Material IDs offset complete!"
    )

    fn onApplyOffset s e = applyMaterialIDOffset (offsetBox.Value as integer)
    dotNet.addEventHandler applyButton "Click" onApplyOffset
    append CloneUI_handlers onApplyOffset
    frm.Show()
)
