/*
	Instance From First - Keep Materials
	Usage:
	1. Select the source object first.
	2. Add the objects to replace to the selection.
	3. Run this macro.

	Every selected object after the first becomes an instance of the first
	selected object while keeping its own material assignment.
*/

macroScript InstanceFromFirstKeepMaterials
category:"CloneTools"
tooltip:"Instance From First - Keep Materials"
buttonText:"Instance From First"
(
	fn cloneToolsInstanceFromFirstKeepMaterials =
	(
		if selection.count < 2 then
		(
			messageBox "Select the source object first, then select one or more objects to replace." title:"Instance From First"
			return false
		)

		local selectedNodes = selection as array
		local sourceNode = selectedNodes[1]

		if not (isValidNode sourceNode) then
		(
			messageBox "The first selected source object is not valid." title:"Instance From First"
			return false
		)

		local replacedCount = 0
		local skippedNames = #()

		undo "Instance From First - Keep Materials" on
		(
			for i = 2 to selectedNodes.count do
			(
				local targetNode = selectedNodes[i]

				if not (isValidNode targetNode) then
				(
					append skippedNames ("<deleted node at selection index " + (i as string) + ">")
				)
				else if targetNode == sourceNode then
				(
					append skippedNames targetNode.name
				)
				else
				(
					local originalMaterial = targetNode.material

					try
					(
						instanceReplace targetNode sourceNode
						targetNode.material = originalMaterial
						replacedCount += 1
					)
					catch
					(
						append skippedNames targetNode.name
					)
				)
			)
		)

		format "Instance From First: replaced % object(s) with instances of %.\n" replacedCount sourceNode.name
		if skippedNames.count > 0 do format "Instance From First: skipped %\n" skippedNames

		select selectedNodes
		completeRedraw()
		true
	)

	on execute do cloneToolsInstanceFromFirstKeepMaterials()
)
