macroScript CloneTools_MakeEdgeSmooth
	buttonText:"Make Edge Smooth"
	toolTip:"Make Edge Smooth"
	category:"CloneTools"
(
	fn runNativeEdgeOp obj op =
	(
		if obj == undefined then return false
		if getSelectionLevel obj != #edge then return false

		if isKindOf obj Editable_Poly or isKindOf obj Edit_Poly then
		(
			obj.buttonOp op
			if isKindOf obj Edit_Poly do try(obj.commit())catch()
			true
		)
		else
		(
			false
		)
	)

	on execute do
	(
		local obj = modPanel.getCurrentObject()

		runNativeEdgeOp obj #MakeSmoothEdges
	)
)
