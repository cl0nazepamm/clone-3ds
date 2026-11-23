/*
	DecimateVertChain v1.0
	Description: Removes every other vertex along a selected chain on an
	             Editable Poly, preserving start/end and the curve shape (verts
	             that stay are unmoved). Uses Editable Poly Remove (heals
	             topology) so connected face strips merge into wider faces.
	             Re-run to halve again.
	Install: Drag and drop into viewport, or run script.
	Usage:   Edit Poly > Vertex sub-object > select an open chain of vertices
	         (must be connected by mesh edges, exactly 2 endpoints), then run.
	Access:  Customize User Interface > Category: "CloneTools" > "Decimate Verts"
*/

macroscript DecimateVertChain
category:"CloneTools"
tooltip:"Decimate Vertex Chain"
buttonText:"Decimate Verts"
(
	fn decimateVertChain o =
	(
		if not (isKindOf o Editable_Poly) then
		(
			messageBox "Select an Editable Poly object." title:"Decimate Verts"
			return false
		)

		local sel = (getVertSelection o) as array
		if sel.count < 3 then
		(
			messageBox "Select at least 3 connected vertices." title:"Decimate Verts"
			return false
		)

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

		local endpoints = for i = 1 to sel.count where adj[i].count == 1 collect i
		if endpoints.count != 2 then
		(
			messageBox ("Selection must form an open chain (found " + (endpoints.count as string) + " endpoints).") title:"Decimate Verts"
			return false
		)

		local ordered = #(endpoints[1])
		local prev = 0
		local cur = endpoints[1]
		while ordered.count < sel.count do
		(
			local nxt = 0
			for nb in adj[cur] do if nb != prev do (nxt = nb; exit)
			if nxt == 0 then
			(
				messageBox ("Chain broken after " + (ordered.count as string) + " of " + (sel.count as string) + " verts.") title:"Decimate Verts"
				return false
			)
			append ordered nxt
			prev = cur
			cur = nxt
		)

		local n = ordered.count
		-- Build remove bitarray: every even chain index that isn't the last
		local removeBA = #{}
		for ci = 2 to n - 1 do
		(
			if (mod ci 2) == 0 do removeBA[sel[ordered[ci]]] = true
		)
		if removeBA.numberSet == 0 then
		(
			messageBox "Nothing to remove (chain too short)." title:"Decimate Verts"
			return false
		)

		undo "Decimate Vert Chain" on
		(
			o.SetSelection #Vertex removeBA
			o.EditablePoly.Remove()
			update o
		)
		format "Decimated: removed % of % chain verts (kept start, end, every other)\n" removeBA.numberSet n
		true
	)

	on execute do
	(
		if selection.count == 1 then decimateVertChain selection[1]
		else messageBox "Select a single Editable Poly object first." title:"Decimate Verts"
	)
)
