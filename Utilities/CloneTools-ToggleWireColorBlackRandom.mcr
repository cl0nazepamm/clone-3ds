macroScript ToggleWireColorBlackRandom
category: "CloneTools"
tooltip: "Wire Random/Black"
buttonText: "Wire Black/Random"
(
	fn randomWireColor =
	(
		color (random 40 255) (random 40 255) (random 40 255)
	)

	fn isPureBlack c =
	(
		c.r == 0 and c.g == 0 and c.b == 0
	)

	on execute do
	(
		local objs = for obj in selection where isValidNode obj collect obj
		if objs.count == 0 do return()

		local hasBlack = false
		local hasNonBlack = false

		for obj in objs do
		(
			if isPureBlack obj.wirecolor then
				hasBlack = true
			else
				hasNonBlack = true
		)

		undo "Toggle Wire Colors" on
		(
			if hasBlack and not hasNonBlack then
			(
				for obj in objs do obj.wirecolor = randomWireColor()
			)
			else
			(
				for obj in objs do obj.wirecolor = black
			)

			redrawViews()
		)
	)
)
