macroScript CloneToolsApplyOptimizePreset
category: "CloneTools"
tooltip: "Apply Optimize Preset"
buttonText: "Optimize Preset"
(
    fn getOrCreateOptimizeModifier node =
    (
        if node == undefined then return undefined

        local modCount = 0
        try modCount = node.modifiers.count catch modCount = 0

        for i = 1 to modCount do
        (
            local m = undefined
            try m = node.modifiers[i] catch m = undefined
            if m != undefined do
            (
                local clsName = classof m as string
                if matchPattern clsName pattern:"*optimize*" ignoreCase:true do return m
            )
        )

        local newMod = undefined
        try
        (
            newMod = Optimize()
            addModifier node newMod
        )
        catch
        (
            newMod = undefined
        )

        newMod
    )

    fn applyOptimizePreset m =
    (
        if m == undefined then return false

        m.autoEdge = true
        m.renderLOD = 0
        m.viewLOD = 0

        m.facethreshold1 = 4.0
        m.edgethreshold1 = 1.0
        m.bias1 = 0.1
        m.preservemat1 = true
        m.preservesmooth1 = true
        m.maxedgelength1 = 0.0

        m.facethreshold2 = 4.0
        m.edgethreshold2 = 1.0
        m.bias2 = 0.1
        m.preservemat2 = false
        m.preservesmooth2 = false
        m.maxedgelength2 = 0.0

        m.manualupdate = false
        true
    )

    if selection.count == 0 then
    (
        format "CloneToolsApplyOptimizePreset: no selection.\n"
        false
    )
    else
    (
        local appliedCount = 0

        undo "CloneTools Apply Optimize Preset" on
        (
            for obj in selection do
            (
                local optMod = getOrCreateOptimizeModifier obj
                if applyOptimizePreset optMod do appliedCount += 1
            )
        )

        format "Optimize preset applied on % object(s).\n" appliedCount
        true
    )
)
