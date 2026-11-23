/*
	EqualizeVertChain v1.0
	Description: Redistributes a selected chain of vertices on an Editable Poly
	             evenly along their arc length. The first and last vertex of the
	             chain stay put; only the intermediates move. Vertex count is
	             preserved (no topology change).
	Install: Drag and drop into viewport, or run script.
	Usage:   Edit Poly > Vertex sub-object > select an open chain of vertices
	         (must be connected by mesh edges, exactly 2 endpoints), then run.
	Access:  Customize User Interface > Category: "CloneTools" > "Equalize Verts"
*/

macroscript EqualizeVertChain
category:"CloneTools"
tooltip:"Equalize Vertex Chain"
buttonText:"Equalize Verts"
(
	fn equalizeVertChain o =
	(
		if not (isKindOf o Editable_Poly) then
		(
			messageBox "Select an Editable Poly object." title:"Equalize Verts"
			return false
		)

		local sel = (getVertSelection o) as array
		if sel.count < 3 then
		(
			messageBox "Select at least 3 connected vertices." title:"Equalize Verts"
			return false
		)

		-- Build adjacency: for each selected vert, list of selected neighbors
		local selSet = #{}
		for v in sel do selSet[v] = true
		local idxOf = #()
		for i = 1 to sel.count do idxOf[sel[i]] = i
		local adj = for i = 1 to sel.count collect #()
		for i = 1 to sel.count do
		(
			local v = sel[i]
			local edges = (polyOp.getEdgesUsingVert o v) as array
			for e in edges do
			(
				local verts = (polyOp.getVertsUsingEdge o e) as array
				for vv in verts do
				(
					if vv != v and selSet[vv] do appendIfUnique adj[i] (idxOf[vv])
				)
			)
		)

		-- Endpoints: selected verts with exactly one selected neighbor
		local endpoints = for i = 1 to sel.count where adj[i].count == 1 collect i
		if endpoints.count != 2 then
		(
			messageBox ("Selection must form an open chain (found " + (endpoints.count as string) + " endpoints).") title:"Equalize Verts"
			return false
		)

		-- Walk chain from one endpoint to the other
		local ordered = #(endpoints[1])
		local prev = 0
		local cur = endpoints[1]
		while ordered.count < sel.count do
		(
			local nxt = 0
			for nb in adj[cur] do if nb != prev do (nxt = nb; exit)
			if nxt == 0 then
			(
				messageBox ("Chain broken after " + (ordered.count as string) + " of " + (sel.count as string) + " verts.") title:"Equalize Verts"
				return false
			)
			append ordered nxt
			prev = cur
			cur = nxt
		)

		-- Capture positions in chain order
		local positions = for oi in ordered collect (polyOp.getVert o sel[oi])

		-- Cumulative arc length per vertex along the chain
		local n = positions.count
		local cum = #(0.0)
		local segLen = #()
		for i = 2 to n do
		(
			local d = distance positions[i-1] positions[i]
			append segLen d
			append cum (cum[i-1] + d)
		)
		local total = cum[n]
		if total < 0.0001 then
		(
			messageBox "Chain has zero length." title:"Equalize Verts"
			return false
		)

		-- Move only intermediate verts (i = 2..n-1) to evenly-spaced arc-length positions
		undo "Equalize Vert Chain" on
		(
			for i = 2 to n - 1 do
			(
				local target = total * (i - 1) / (n - 1.0)
				local seg = 1
				while seg < n - 1 and cum[seg + 1] < target do seg += 1
				local localT = if segLen[seg] > 0.0001 then (target - cum[seg]) / segLen[seg] else 0.0
				local pos = positions[seg] + (positions[seg + 1] - positions[seg]) * localT
				polyOp.setVert o sel[ordered[i]] pos
			)
			update o
		)
		true
	)

	on execute do
	(
		if selection.count == 1 then equalizeVertChain selection[1]
		else messageBox "Select a single Editable Poly object first." title:"Equalize Verts"
	)
)
