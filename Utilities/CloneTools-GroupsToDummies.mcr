macroScript GroupsToDummies
category: "CloneTools"
tooltip: "Convert Groups to Dummies"
buttonText: "Groups>Dummies"
(
	on execute do
	(
		local newParents = #()
		local groupHeads = for obj in objects where isGroupHead obj collect with redraw off
		(
			setGroupOpen obj true
			local helper = obj.children.parent = Dummy name:obj.name pos:obj.pos boxSize:obj.boxSize
			if isValidNode obj.parent do helper.parent = obj.parent
			append newParents helper
			obj
		)
		delete groupHeads
		select newParents
	)
)
