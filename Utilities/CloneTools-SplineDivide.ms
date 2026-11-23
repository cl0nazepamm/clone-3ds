/*
	SplineDivide v1.0
	Description: Bakes one extra interpolation step into selected subsplines as
	             real knots. The shape's overall .steps stays the same; only the
	             targeted subsplines gain knots. divisions = shp.steps + 1
	             (e.g. steps=1 -> divisions=2: each segment becomes 3 sub-segments,
	             matching the visual of steps=2).
	Install: Drag and drop into viewport, or run script.
	Access: Customize User Interface > Category: "CloneTools" > "Spline Divide"
*/

macroscript SplineDivide
category:"CloneTools"
tooltip:"Spline Divide"
buttonText:"Spline Divide"
(
	fn bakeSubsplineInterpolation shp splineIdxs:unsupplied divisions:unsupplied =
	(
		local base = if isProperty shp "baseObject" then shp.baseObject else shp
		if not isKindOf base SplineShape do return false
		if divisions == unsupplied do divisions = shp.steps + 1
		if splineIdxs == unsupplied do
		(
			local sel = getSplineSelection shp
			splineIdxs = if sel.count > 0 then (sel as array) \
			             else (for i = 1 to numSplines shp collect i)
		)
		if classOf splineIdxs == Integer do splineIdxs = #(splineIdxs)

		-- subdivideSegment isn't undoable, but refineSegment is.
		-- Replicate uniform subdivision by inserting knots one at a time at
		-- t = i / (i+1) on the (shrinking) current segment, going high to low.
		undo "Spline Divide" on
		(
			for splineIdx in splineIdxs do
			(
				if splineIdx >= 1 and splineIdx <= (numSplines shp) do
				(
					local segCount = numSegments shp splineIdx
					-- Outer loop backwards so adding knots in earlier segs
					-- doesn't shift the indices of segs we still need to visit.
					for seg = segCount to 1 by -1 do
					(
						for i = divisions to 1 by -1 do
						(
							refineSegment shp splineIdx seg (i / (i + 1.0))
						)
					)
				)
			)
			updateShape shp
		)
		divisions
	)

	on execute do
	(
		local shp = if selection.count == 1 then selection[1] else undefined
		local base = if shp != undefined and isProperty shp "baseObject" then shp.baseObject else undefined
		if shp == undefined or not isKindOf base SplineShape then
		(
			messageBox "Select a single editable spline first." title:"Spline Divide"
		)
		else
		(
			local d = bakeSubsplineInterpolation shp
			format "Spline Divide: % -> divisions=%\n" shp.name d
		)
	)
)
