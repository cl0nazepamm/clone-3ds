/*
	CopyUVChannels v2.0
	Description: Provides a UI to copy UV map channels (e.g. UV0 -> UV1) for selected objects.
	Install: Drag and drop into viewport or run script.
	Access: Customize User Interface > "CloneTools" > "Copy UV Channels"
*/

macroscript CopyUVChannels
category:"CloneTools"
tooltip:"Copy UV Channels"
buttonText:"Copy UVs"
(
	try(if CloneUI == undefined do fileIn ((getDir #userScripts) + "\\CloneTools\\CloneUI.ms"))catch(try(fileIn ((getFilenamePath (getSourceFileName())) + "CloneUI.ms"))catch())
	try(CloneCopyUVChannels_Form.Close())catch()
	try(CloneCopyUVChannels_Form.Dispose())catch()
	global CloneCopyUVChannels_Form = dotNetObject "System.Windows.Forms.Form"

	fn processObject obj srcCh tgtCh =
	(
		if (canConvertTo obj Editable_Poly) or (canConvertTo obj Editable_Mesh) then
		(
			try
			(
				channelInfo.CopyChannel obj 3 srcCh
				channelInfo.PasteChannel obj 3 tgtCh
				channelInfo.NameChannel obj 3 tgtCh ("Map Channel " + (tgtCh as string))
				return true
			)
			catch
			(
				format "Error processing object '%': %\n" obj.name (getCurrentException())
				return false
			)
		)
		else return false
	)

	local frm = CloneUI.skinForm CloneCopyUVChannels_Form "Copy UV Channels" 340 360
	local shell = CloneUI.addShell frm "Copy UV Channels" version:"v2.0"
	local pad = shell[1]
	local iW = shell[2]
	local Y = shell[3]

	frm.controls.add (CloneUI.mkLabel "Source Channel (UV0 = 1)" (pad+4) Y 180 18 fObj:CloneUI.fSmall cObj:CloneUI.cDim)
	local srcBox = CloneUI.mkNumeric (pad+198) (Y-2) 90 1 99 1
	frm.controls.add srcBox
	Y += 30

	frm.controls.add (CloneUI.mkLabel "Target Channel (UV1 = 2)" (pad+4) Y 180 18 fObj:CloneUI.fSmall cObj:CloneUI.cDim)
	local tgtBox = CloneUI.mkNumeric (pad+198) (Y-2) 90 1 99 2
	frm.controls.add tgtBox
	Y += 42

	local btnCopy = CloneUI.mkBtn "Copy Channel" pad Y iW 32
	frm.controls.add btnCopy
	Y += 48

	local credit = CloneUI.mkLabel "clone" 0 Y 340 16 fObj:CloneUI.fSmall cObj:(CloneUI.clr.FromArgb 55 55 55)
	credit.TextAlign = CloneUI.alC.MiddleCenter
	frm.controls.add credit
	frm.Size = dotNetObject CloneUI.szC 340 (Y + 24)

	fn onCloneCopyUV s e =
	(
		local srcCh = srcBox.Value as integer
		local tgtCh = tgtBox.Value as integer
		if selection.count == 0 then
		(
			messageBox "Please select one or more objects first." title:"Selection Error"
			return()
		)
		local successCount = 0
		local failCount = 0

		undo "Copy UV Channels" on
		(
			for obj in selection do
			(
				if (processObject obj srcCh tgtCh) then successCount += 1 else failCount += 1
			)
		)

		local msg = "Copied Channel " + (srcCh as string) + " to " + (tgtCh as string) + "\n\n"
		msg += "Success: " + (successCount as string) + " objects.\n"
		if failCount > 0 do msg += "Failed: " + (failCount as string) + " objects."
		messageBox msg title:"Operation Complete"
	)

	dotNet.addEventHandler btnCopy "Click" onCloneCopyUV
	append CloneUI_handlers onCloneCopyUV
	frm.Show()
)
