/*
	SplineArc v1.1
	Description: Slider-style tool that bulges the segment between 2 selected
	             knots into an arc. Tangent directions at both knots come from
	             the neighboring segments (G1 preserved); the slider only scales
	             tangent magnitude. If the 2 selected knots are the open
	             endpoints of a subspline, the spline is closed first to create
	             the bridging segment.
	Install: Drag and drop into viewport, or run script.
	Usage:   Select a spline, enter Knot sub-object, select 2 knots that are
	         either adjacent or the open endpoints of the same subspline.
	         Run macro, click in viewport, drag horizontally to bulge,
	         right-click to confirm. Shift = 4x speed, Alt = 0.2x.
	Access:  Customize User Interface > Category: "CloneTools" > "Spline Arc"
*/

macroscript SplineArc
category:"CloneTools"
tooltip:"Spline Arc"
buttonText:"Spline Arc"
(
	tool cloneToolsSplineArcTool
	(
		local pixelsPerUnit = 20.0
		local lastMouseX
		local dragging = false
		local shp
		local splineIdx
		local kA, kB
		local A_pos, B_pos
		local chord_unit, chord_len
		local fwd_dir_A, fwd_dir_B
		local current_L = 0.0

		-- Returns #(shape, splineIdx, kA, kB, needsClose) or undefined.
		fn findArcKnots =
		(
			if selection.count != 1 do return undefined
			local s = selection[1]
			if not (isProperty s "baseObject" and isKindOf s.baseObject SplineShape) do return undefined
			for si = 1 to numSplines s do
			(
				local sel = (getKnotSelection s si) as array
				if sel.count == 2 do
				(
					local i1 = sel[1]
					local i2 = sel[2]
					local nk = numKnots s si
					local closed = isClosed s si
					-- Adjacent
					if (i2 == i1 + 1) do return #(s, si, i1, i2, false)
					-- Closed wrap segment
					if (closed and i1 == 1 and i2 == nk) do return #(s, si, nk, 1, false)
					-- Open endpoints: need to close the spline first
					if (not closed and i1 == 1 and i2 == nk) do return #(s, si, nk, 1, true)
				)
			)
			undefined
		)

		fn applyTangents L =
		(
			setOutVec shp splineIdx kA (A_pos + fwd_dir_A * L)
			setInVec  shp splineIdx kB (B_pos - fwd_dir_B * L)
			updateShape shp
			completeRedraw()
		)

		fn cancelHold =
		(
			try (theHold.Cancel()) catch ()
		)

		on mousePoint clickno do
		(
			if clickno == 1 then
			(
				local v = findArcKnots()
				if v == undefined then
				(
					messageBox "Select 2 knots on a single editable spline.\nKnots must be adjacent OR the open endpoints of the same subspline." title:"Spline Arc"
					#stop
				)
				else
				(
					shp = v[1]
					splineIdx = v[2]
					kA = v[3]
					kB = v[4]
					local needsClose = v[5]

					theHold.Begin()
					if needsClose do
					(
						close shp splineIdx
						updateShape shp
					)

					A_pos = getKnotPoint shp splineIdx kA
					B_pos = getKnotPoint shp splineIdx kB
					local chord = B_pos - A_pos
					chord_len = length chord
					if chord_len < 0.0001 then
					(
						cancelHold()
						messageBox "Selected knots are coincident." title:"Spline Arc"
						#stop
					)
					else
					(
						chord_unit = normalize chord

						-- Forward direction at A = continuation of previous segment past A.
						-- inVec is the in-handle position; (A - inVec) points forward.
						local inVecA = getInVec shp splineIdx kA
						local inOff = inVecA - A_pos
						if length inOff < 0.0001 then fwd_dir_A = chord_unit \
						else fwd_dir_A = -normalize inOff

						-- Forward direction at B = continuation of next segment leaving B.
						local outVecB = getOutVec shp splineIdx kB
						local outOff = outVecB - B_pos
						if length outOff < 0.0001 then fwd_dir_B = chord_unit \
						else fwd_dir_B = normalize outOff

						setKnotType shp splineIdx kA #bezierCorner
						setKnotType shp splineIdx kB #bezierCorner
						setSegmentType shp splineIdx kA #curve

						current_L = 0.0
						applyTangents 0.0
						lastMouseX = mouse.screenpos.x
						dragging = true
					)
				)
			)
			else if clickno == 2 then
			(
				dragging = false
				theHold.Accept "Spline Arc"
				#stop
			)
		)

		on mouseMove clickno do
		(
			if dragging and lastMouseX != undefined do
			(
				local cur = mouse.screenpos.x
				local dx = cur - lastMouseX
				lastMouseX = cur
				local mult = 1.0
				if keyboard.shiftPressed do mult = 4.0
				if keyboard.altPressed do mult = 0.2
				current_L += (dx / pixelsPerUnit) * mult
				if current_L < 0.0 do current_L = 0.0
				applyTangents current_L
			)
		)

		on mouseAbort clickno do
		(
			dragging = false
			cancelHold()
			#stop
		)
	)

	on execute do startTool cloneToolsSplineArcTool
)
