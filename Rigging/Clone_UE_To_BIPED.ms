/*
    Clone_UE_To_BIPED.ms
    --------------------
    Configurable source-skeleton to 3ds Max Biped remapper.

    The default path opens a UI:
        fileIn @"C:\...\Rigging\Clone_UE_To_BIPED.ms"

    To run the old immediate Unreal conversion path:
        global CloneBipedRemapperAutoRun = true
        fileIn @"C:\...\Rigging\Clone_UE_To_BIPED.ms"

    To customize:
        global CloneBipedRemapperAutoRun = false
        fileIn @"C:\...\Rigging\Clone_UE_To_BIPED.ms"
        cfg = CloneBipedRemapper.makeUEPreset()
        cfg.boneMap = CloneBipedRemapper.replaceBoneName cfg.boneMap #pelvis "my_hips"
        CloneBipedRemapper.run cfg

    Preset data is intentionally plain arrays so a new skeleton is mostly a
    name-map and link-table edit instead of another hard-coded script.

    How the fit works (same engine as Clone_Genesis9_Importer.ms):
      - Biped root sits between the thighs (Biped always puts the thighs at
        root height); the pelvis Z scale is the exact hip width.
      - Every link is aimed at its child joint from joint positions only and
        re-measured until it is within 0.05 degrees. Roll is only changed
        from real geometry: elbow/knee bend plane, palm width, finger curl.
      - Link length is the exact joint distance. The foot is solved so the
        Toe0 pivot lands on the sole under the ball; head top, fingertips and
        toe tips come from the skinned body mesh.
      - The source root follows a hidden driver point linked to the Biped
        (COM when the rig has a separate pelvis bone, Biped Pelvis otherwise).
        Everything else gets relative Orientation constraints; Position
        constraints are only added where the joints coincide.
      - The run reports joint offsets, links that missed their target and
        bind-pose vertex drift in the Listener.

    Link table formats:
        boneMap:        #(slotSymbol, "SourceBoneName")
        bodyLinks:      #("Biped Suffix", sourceSlot, childSlot, helperType, doPos, doRot, doScale, constraintMode)
        fingerChains:   #(sourceSlotArray, bipedSuffixArray, helperType)
        toeConstraints: #(sourceSlot, "Biped Toe Suffix", constraintMode, setToePosition)
        twistConstraints: #(sourceSlot, "Biped Twist Suffix", constraintMode)

    Helper types: #none skips aiming a link; anything else aims it.
    The roll reference is chosen from the Biped part (arm, leg, hand, finger).
    Constraint modes: #both, #pos, #rot, #none.
*/

global CloneBipedRemapper
global CloneBipedRemapperAutoRun
global CloneBipedRemapperOpenUI
global CloneBipedRemapperUIConfig

if CloneBipedRemapperAutoRun == undefined do CloneBipedRemapperAutoRun = false
if CloneBipedRemapperOpenUI == undefined do CloneBipedRemapperOpenUI = true

struct CloneBipedRemapPreset
(
    name = "Unreal",
    verbose = true,
    createBiped = true,
    createConstraints = true,
    exitFigureMode = true,
    holdScene = true,

    bipedName = "Bip001",
    bipedSize = 200,            -- fallback height when no skinned body mesh is found
    bipedAngle = -90,           -- fallback facing when the feet and balls are not mapped
    bipedPosition = [0, 0, 0],

    arms = true,
    fingers = 5,
    fingerLinks = 3,
    toes = 1,
    toeLinks = 1,
    forearmTwistLinks = 2,      -- upper bounds; the mapped twist bones found decide the count
    upperarmTwistLinks = 2,
    thighTwistLinks = 2,
    calfTwistLinks = 2,
    minimumSpineLinks = 1,
    minimumNeckLinks = 1,
    maximumSpineLinks = 10,
    maximumNeckLinks = 5,

    rootSource = #pelvis,
    pelvisSource = #pelvisBone, -- optional pelvis bone under the root (CC_Base_Pelvis); drives Bip Pelvis
    headSource = #head,
    headBiped = "Head",

    spineNames = #(),
    spineDetectPrefix = "spine_0",
    spineDetectMax = 5,
    neckNames = #(),
    neckDetectPrefix = "neck_0",
    neckDetectMax = 2,

    footScaleEnabled = true,
    bendThreshold = 8.0,        -- degrees; a chain bent less than this counts as straight

    requiredSlots = #(#pelvis, #head),
    boneMap = #(),
    bodyLinks = #(),
    fingerChains = #(),
    toeConstraints = #(),
    twistConstraints = #(),
    postRotations = #(),        -- optional manual tweaks: #("Biped Suffix", degrees, localAxis)
    postMoves = #()             -- optional manual tweaks: #("Biped Suffix", worldOffset)
)

struct CloneBipedRemapperStruct
(
    missing = #(),
    unaimed = #(),
    hingeOffsets = #(),
    report = #(),
    resolved = undefined,

    fn log cfg msg =
    (
        append report msg
        if cfg != undefined do
        (
            if cfg.verbose do format "%\n" msg
        )
    ),

    fn resetState =
    (
        missing = #()
        unaimed = #()
        hingeOffsets = #()
        report = #()
        resolved = Dictionary #string
    ),

    fn replaceBoneName boneMap slot newName =
    (
        local result = #()
        local replaced = false

        for pair in boneMap do
        (
            if pair.count >= 2 and pair[1] == slot then
            (
                append result #(slot, newName)
                replaced = true
            )
            else
            (
                append result pair
            )
        )

        if not replaced do append result #(slot, newName)
        result
    ),

    fn slotLabel slot =
    (
        local label = slot as string
        if label.count > 1 do
        (
            if (substring label 1 1) == "#" do label = substring label 2 (label.count - 1)
        )

        label
    ),

    fn joinNameText names =
    (
        local result = ""

        for i = 1 to names.count do
        (
            if i > 1 do result += ", "
            result += names[i]
        )

        result
    ),

    fn splitNameText textValue =
    (
        local result = #()
        local parts = filterString textValue ",; "

        for part in parts do
        (
            if part != "" do append result part
        )

        result
    ),

    fn lowerText value =
    (
        if value == undefined then "" else toLower (value as string)
    ),

    fn stringEndsWith textValue suffixValue =
    (
        local textLower = lowerText textValue
        local suffixLower = lowerText suffixValue

        if suffixLower.count == 0 then return true
        if textLower.count < suffixLower.count then return false

        (substring textLower (textLower.count - suffixLower.count + 1) suffixLower.count) == suffixLower
    ),

    fn sourceNameMatches requestedName sceneName =
    (
        local wanted = lowerText requestedName
        local actual = lowerText sceneName

        if wanted == "" or actual == "" then return false
        if actual == wanted then return true

        -- Imported FBX rigs often prepend namespaces or object prefixes.
        for prefixSep in #(":", "|", "/", "\\", ".", " ", "_") do
        (
            if stringEndsWith actual (prefixSep + wanted) do return true
        )

        false
    ),

    fn findSourceNodeByName requestedName nodePool =
    (
        if requestedName == undefined then return undefined
        if requestedName == "" then return undefined

        if nodePool == undefined then
        (
            local exact = getNodeByName requestedName
            if exact != undefined then return exact

            for obj in objects do
            (
                if sourceNameMatches requestedName obj.name do return obj
            )
        )
        else
        (
            for obj in nodePool do
            (
                if obj.name == requestedName do return obj
            )

            for obj in nodePool do
            (
                if sourceNameMatches requestedName obj.name do return obj
            )
        )

        undefined
    ),

    fn appendUniqueName names nameValue =
    (
        if nameValue == undefined then return names

        local exists = false
        for n in names where n == nameValue do exists = true
        if not exists do append names nameValue

        names
    ),

    fn collectHierarchy rootNode =
    (
        local nodes = #()

        if rootNode != undefined do
        (
            append nodes rootNode
            for c in rootNode.children do
            (
                join nodes (collectHierarchy c)
            )
        )

        nodes
    ),

    fn autoMapBoneNames cfg rootNode =
    (
        local nodePool = if rootNode == undefined then undefined else collectHierarchy rootNode
        local mappedCount = 0

        for pair in cfg.boneMap do
        (
            if pair.count >= 2 do
            (
                local found = findSourceNodeByName pair[2] nodePool
                if found != undefined do
                (
                    cfg.boneMap = replaceBoneName cfg.boneMap pair[1] found.name
                    mappedCount += 1
                )
            )
        )

        mappedCount
    ),

    fn boneMapItems cfg =
    (
        local items = #()

        for pair in cfg.boneMap do
        (
            local slotText = if pair.count >= 1 then slotLabel pair[1] else "<slot>"
            local sourceText = if pair.count >= 2 then pair[2] else ""
            local statusText = ""
            local resolvedNode = findSourceNodeByName sourceText undefined

            if sourceText == undefined or sourceText == "" then
            (
                statusText = "  [empty]"
            )
            else
            (
                if resolvedNode == undefined then
                (
                    statusText = "  [missing]"
                )
                else
                (
                    if resolvedNode.name != sourceText do statusText = "  [found: " + resolvedNode.name + "]"
                )
            )

            append items (slotText + " -> " + (sourceText as string) + statusText)
        )

        items
    ),

    fn missingBoneMapItems cfg =
    (
        local items = #()

        for pair in cfg.boneMap do
        (
            if pair.count >= 2 do
            (
                local sourceText = pair[2]
                if sourceText == undefined or sourceText == "" then
                (
                    append items ((slotLabel pair[1]) + " -> <empty>")
                )
                else
                (
                    if findSourceNodeByName sourceText undefined == undefined do append items ((slotLabel pair[1]) + " -> " + sourceText)
                )
            )
        )

        items
    ),

    fn sourceName cfg slot =
    (
        if slot == undefined then return undefined
        if classOf slot == String then return slot

        for pair in cfg.boneMap do
        (
            if pair.count >= 2 and pair[1] == slot do return pair[2]
        )

        undefined
    ),

    -- Resolved once per run; false marks a slot that was looked up and not found.
    fn sourceNode cfg slot =
    (
        if slot == undefined then return undefined
        local key = if classOf slot == String then ("@" + slot) else (slot as string)
        if resolved != undefined and hasDictValue resolved key do
        (
            local cached = resolved[key]
            return (if cached == false then undefined else cached)
        )

        local nodeName = sourceName cfg slot
        local found = if nodeName == undefined then undefined else findSourceNodeByName nodeName undefined
        if resolved != undefined do resolved[key] = (if found == undefined then false else found)
        found
    ),

    fn sourcePos cfg slot =
    (
        local n = sourceNode cfg slot
        if n == undefined then undefined else n.transform.pos
    ),

    fn sideSlot side suffix = ((side + suffix) as name),

    fn bipedName cfg suffix =
    (
        if suffix == #root then cfg.bipedName else (cfg.bipedName + " " + suffix)
    ),

    fn bipedNode cfg suffix =
    (
        getNodeByName (bipedName cfg suffix)
    ),

    fn bipedSpineName cfg idx =
    (
        cfg.bipedName + " " + (if idx == 1 then "Spine" else ("Spine" + ((idx - 1) as string)))
    ),

    fn bipedNeckName cfg idx =
    (
        cfg.bipedName + " " + (if idx == 1 then "Neck" else ("Neck" + ((idx - 1) as string)))
    ),

    fn bipedSpineNode cfg idx =
    (
        getNodeByName (bipedSpineName cfg idx)
    ),

    fn bipedNeckNode cfg idx =
    (
        getNodeByName (bipedNeckName cfg idx)
    ),

    fn rememberMissing label =
    (
        append missing label
    ),

    fn existingNameList names =
    (
        local result = #()

        for n in names do
        (
            local found = findSourceNodeByName n undefined
            if found != undefined do result = appendUniqueName result found.name
        )

        result
    ),

    fn detectedNameList explicitNames prefix maxCount =
    (
        local result = existingNameList explicitNames

        if result.count == 0 do
        (
            if prefix != undefined do
            (
                if prefix != "" do
                (
                    for i = 1 to maxCount do
                    (
                        local n = prefix + (i as string)
                        local found = findSourceNodeByName n undefined
                        if found != undefined do result = appendUniqueName result found.name
                    )
                )
            )
        )

        result
    ),

    fn setFigureMode cfg state =
    (
        local root = bipedNode cfg #root
        if root != undefined do
        (
            try(root.controller.figureMode = state)catch()
        )
    ),

    fn boundedCount value minValue maxValue =
    (
        local result = value
        if result < minValue do result = minValue
        if result > maxValue do result = maxValue
        result
    ),

    fn fmt v = (formattedPrint v format:".4f"),

    -- ------------------------------------------------------------ fit math

    fn safeNorm v fallback = (if (length v) < 1e-6 then fallback else normalize v),

    fn angleBetween a b = acos (amax -1.0 (amin 1.0 (dot (normalize a) (normalize b)))),

    -- Normal of the plane a chain bends in, or undefined when the chain is (nearly) straight.
    fn bendHint a b threshold =
    (
        if a == undefined or b == undefined then return undefined
        if (length a) < 1e-6 or (length b) < 1e-6 then return undefined
        if (angleBetween a b) < threshold then undefined else normalize (cross a b)
    ),

    -- Smallest rotation of tm that puts its X axis on dir (keeps the Biped's own roll).
    fn aimFrame tm dir =
    (
        local x0 = normalize tm.row1
        local y0 = normalize tm.row2
        local x1 = normalize dir
        local c = dot x0 x1
        local axis = cross x0 x1
        local sn = length axis
        local y1 = y0
        if sn > 1e-6 then
        (
            local k = axis / sn
            y1 = y0 * c + (cross k y0) * sn + k * ((dot k y0) * (1.0 - c))
        )
        else if c < 0 do y1 = -y0
        local z1 = normalize (cross x1 y1)
        y1 = normalize (cross z1 x1)
        matrix3 x1 y1 z1 tm.row4
    ),

    -- Rolls tm about X so Z lies on the hint line, taking the sign closest to the current Z.
    fn rollFrame tm hint =
    (
        local x = normalize tm.row1
        local z = hint - x * (dot hint x)
        if (length z) < 1e-4 then return tm
        z = normalize z
        if (dot z tm.row3) < 0 do z = -z
        matrix3 x (normalize (cross z x)) z tm.row4
    ),

    fn isAimed bn dir hint =
    (
        local done = (angleBetween bn.transform.row1 dir) < 0.05
        if done and hint != undefined do done = (angleBetween bn.transform.row3 (rollFrame bn.transform hint).row3) < 0.1
        done
    ),

    -- rotate on a Biped node reads the axis in the node's own frame, not in world space
    fn rotateWorld bn angle worldAxis =
    (
        local t = bn.transform
        local ax = normalize worldAxis
        rotate bn (angleaxis angle [dot ax (normalize t.row1), dot ax (normalize t.row2), dot ax (normalize t.row3)])
    ),

    -- Biped does not take every requested rotation literally: thighs drop part of it and clavicles
    -- flatten biped.setTransform #rotation in Figure Mode. Re-aim from the result, then fall back to
    -- rotate steps until the link really points along dir (and rolls onto hint).
    fn aimLoop bn dir hint =
    (
        dir = normalize dir
        for i = 1 to 4 while not (isAimed bn dir hint) do
        (
            local tm = aimFrame bn.transform dir
            if hint != undefined do tm = rollFrame tm hint
            biped.setTransform bn #rotation tm.rotation false
        )
        for i = 1 to 12 while not (isAimed bn dir hint) do
        (
            if hint != undefined do
            (
                local z = normalize bn.transform.row3
                local want = (rollFrame bn.transform hint).row3
                local rax = cross z want
                if (length rax) > 1e-7 do rotateWorld bn (angleBetween z want) rax
            )
            local cur = normalize bn.transform.row1
            local ax = cross cur dir
            if (length ax) > 1e-7 do rotateWorld bn (angleBetween cur dir) ax
        )
        -- when Biped refuses the roll (finger twist), the direction still has to land
        for i = 1 to 8 while (angleBetween bn.transform.row1 dir) >= 0.05 do
        (
            local cur = normalize bn.transform.row1
            local ax = cross cur dir
            if (length ax) > 1e-7 do rotateWorld bn (angleBetween cur dir) ax
        )
        if (angleBetween bn.transform.row1 dir) >= 0.05 do append unaimed (bn.name + " " + fmt (angleBetween bn.transform.row1 dir) + " deg")
        bn
    ),

    fn fitDir bn dir len hint w h doScale:true =
    (
        if bn == undefined or len < 1e-3 then return false
        aimLoop bn dir hint
        if doScale do biped.setTransform bn #scale [len, w, h] false
        true
    ),

    fn fitLink bn fromPos toPos hint thickness doScale:true =
    (
        if bn == undefined or fromPos == undefined or toPos == undefined then return false
        local d = toPos - fromPos
        local len = length d
        fitDir bn (safeNorm d [1, 0, 0]) len hint (len * thickness) (len * thickness) doScale:doScale
    ),

    fn pointsNear pts center radius =
    (
        local r2 = radius * radius
        for pt in pts where (dot (pt - center) (pt - center)) < r2 collect pt
    ),

    -- Farthest mesh point in front of origin along dir, inside a tube of the given radius.
    fn extentAlong pts origin dir tube fallback =
    (
        local best = 0.0
        for pt in pts do
        (
            local v = pt - origin
            local t = dot v dir
            if t > best and (length (v - dir * t)) < tube do best = t
        )
        if best > 1e-3 then best else fallback
    ),

    -- ------------------------------------------------------------ mesh data

    fn skinOf o =
    (
        for m in o.modifiers where classOf m == Skin do return m
        undefined
    ),

    fn skinBones sk = for i = 1 to (skinOps.GetNumberBones sk) collect (skinOps.GetBoneNode sk i),

    fn meshPoints o maxCount:0 =
    (
        local m = snapshotAsMesh o
        local stepSize = if maxCount > 0 then (amax 1 (m.numverts / maxCount)) else 1
        local pts = for i = 1 to m.numverts by stepSize collect (getVert m i)
        delete m
        pts
    ),

    fn maxDrift a b =
    (
        local worst = 0.0
        if a.count != b.count then return 1e9
        for i = 1 to a.count do
        (
            local d = distance a[i] b[i]
            if d > worst do worst = d
        )
        worst
    ),

    fn sourceMeshes cfg =
    (
        local bones = #()
        for pair in cfg.boneMap do
        (
            local n = sourceNode cfg pair[1]
            if n != undefined do appendIfUnique bones n
        )
        local out = #()
        for o in objects where (skinOf o) != undefined do
        (
            for b in (skinBones (skinOf o)) where findItem bones b > 0 do
            (
                append out o
                exit
            )
        )
        out
    ),

    fn bodyMeshPoints cfg =
    (
        local hand = sourceNode cfg #lHand
        local foot = sourceNode cfg #lFoot
        local best = undefined
        local bestCount = 0
        for o in objects where (skinOf o) != undefined do
        (
            local bones = skinBones (skinOf o)
            if findItem bones hand > 0 and findItem bones foot > 0 do
            (
                local n = (getPolygonCount o)[2]
                if n > bestCount do (best = o; bestCount = n)
            )
        )
        if best == undefined then #() else meshPoints best
    ),

    -- ------------------------------------------------------------ biped fit

    fn validateRequired cfg =
    (
        local ok = true

        for slot in cfg.requiredSlots do
        (
            if sourceNode cfg slot == undefined do
            (
                ok = false
                rememberMissing ((slot as string) + " -> " + ((sourceName cfg slot) as string))
            )
        )

        ok
    ),

    fn twistCount cfg prefix maxLinks =
    (
        local n = 0
        for def in cfg.twistConstraints where def.count >= 2 and (matchPattern def[2] pattern:(prefix + "*")) and (sourceNode cfg def[1]) != undefined do n += 1
        boundedCount n 0 maxLinks
    ),

    fn createBipedFor cfg spineCount neckCount fig =
    (
        local sCount = boundedCount spineCount cfg.minimumSpineLinks cfg.maximumSpineLinks
        local nCount = boundedCount neckCount cfg.minimumNeckLinks cfg.maximumNeckLinks

        if cfg.createBiped then
        (
            local nUT = twistCount cfg "LUpArmTwist" cfg.upperarmTwistLinks
            local nFT = twistCount cfg "L ForeTwist" cfg.forearmTwistLinks
            local nTT = twistCount cfg "LThighTwist" cfg.thighTwistLinks
            local nCT = twistCount cfg "LCalfTwist" cfg.calfTwistLinks
            log cfg ("Creating Biped: " + (sCount as string) + " spine, " + (nCount as string) + " neck, twist " + \
                nUT as string + "/" + nFT as string + "/" + nTT as string + "/" + nCT as string + ", height " + fmt fig[4])
            local bipObj = biped.createNew fig[4] fig[6] fig[7] arms:cfg.arms neckLinks:nCount spineLinks:sCount \
                fingers:cfg.fingers fingerLinks:cfg.fingerLinks toes:cfg.toes toeLinks:cfg.toeLinks \
                upperarmTwistLinks:nUT forearmTwistLinks:nFT thighTwistLinks:nTT calfTwistLinks:nCT

            if bipObj != undefined do
            (
                try(cfg.bipedName = bipObj.name)catch()
            )
        )
        else
        (
            log cfg ("Using existing Biped root: " + cfg.bipedName)
        )

        setFigureMode cfg true
    ),

    -- #(bodyPoints, ground, top, height, forward, angle, rootPos)
    fn measureFigure cfg =
    (
        local up = [0, 0, 1]
        local pts = bodyMeshPoints cfg
        local ground = 1e9
        local top = -1e9
        for pt in pts do
        (
            if pt.z < ground do ground = pt.z
            if pt.z > top do top = pt.z
        )
        local head = sourcePos cfg cfg.headSource
        local lFoot = sourcePos cfg #lFoot
        local rFoot = sourcePos cfg #rFoot
        if pts.count == 0 do
        (
            ground = if lFoot != undefined then lFoot.z else 0.0
            top = if head != undefined then head.z + (head.z - ground) * 0.13 else ground + cfg.bipedSize
        )

        local angleValue = cfg.bipedAngle
        local fwd = [cos angleValue, sin angleValue, 0]
        local lBall = sourcePos cfg #lBall
        local rBall = sourcePos cfg #rBall
        if lFoot != undefined and rFoot != undefined and lBall != undefined and rBall != undefined do
        (
            local f = (lBall - lFoot) + (rBall - rFoot)
            f = f - up * (dot f up)
            if (length f) > 1e-3 do
            (
                fwd = normalize f
                angleValue = atan2 fwd.y fwd.x
            )
        )

        local lThigh = sourcePos cfg #lThigh
        local rThigh = sourcePos cfg #rThigh
        local rootPos = if lThigh != undefined and rThigh != undefined then (lThigh + rThigh) * 0.5 else sourcePos cfg cfg.rootSource
        if rootPos == undefined do rootPos = cfg.bipedPosition

        #(pts, ground, top, (amax 1.0 (top - ground)), fwd, angleValue, rootPos)
    ),

    fn alignRoot cfg fig =
    (
        local bipRoot = bipedNode cfg #root
        if bipRoot == undefined then return false

        -- Biped puts the thighs at the root height; the pelvis Z scale is the hip width.
        biped.setTransform bipRoot #pos fig[7] false
        local lThigh = sourcePos cfg #lThigh
        local rThigh = sourcePos cfg #rThigh
        local pelvisBip = bipedNode cfg "Pelvis"
        if lThigh != undefined and rThigh != undefined and pelvisBip != undefined do
        (
            local hipWidth = distance lThigh rThigh
            biped.setTransform pelvisBip #scale [hipWidth * 0.5, hipWidth * 0.9, hipWidth] false
        )
        log cfg "Root placed between the thighs."
        true
    ),

    fn chestWidth cfg =
    (
        local l = sourcePos cfg #lUpperArm
        local r = sourcePos cfg #rUpperArm
        if l != undefined and r != undefined then (distance l r) * 0.55 else 15.0
    ),

    fn alignSpine cfg spineNames neckNames =
    (
        if spineNames.count == 0 then
        (
            log cfg "No source spine bones found; skipping spine alignment."
            return false
        )

        log cfg ("Aligning spine chain: " + (spineNames as string))
        local w = chestWidth cfg
        local first = bipedSpineNode cfg 1
        if first != undefined do biped.setTransform first #pos (getNodeByName spineNames[1]).transform.pos false

        for i = 1 to spineNames.count do
        (
            local src = getNodeByName spineNames[i]
            local nextName = if i < spineNames.count then spineNames[i + 1] else (if neckNames.count > 0 then neckNames[1] else sourceName cfg cfg.headSource)
            local tgt = findSourceNodeByName nextName undefined
            local bip = bipedSpineNode cfg i
            if src != undefined and tgt != undefined and bip != undefined do
            (
                local d = tgt.transform.pos - src.transform.pos
                fitDir bip (safeNorm d [0, 0, 1]) (length d) undefined (w * 0.75) w
            )
        )

        true
    ),

    fn alignNeck cfg neckNames =
    (
        if neckNames.count == 0 then
        (
            log cfg "No source neck bones found; skipping neck alignment."
            return false
        )

        log cfg ("Aligning neck chain: " + (neckNames as string))
        local w = (chestWidth cfg) * 0.35
        local first = bipedNeckNode cfg 1
        if first != undefined do biped.setTransform first #pos (getNodeByName neckNames[1]).transform.pos false

        for i = 1 to neckNames.count do
        (
            local src = getNodeByName neckNames[i]
            local nextName = if i < neckNames.count then neckNames[i + 1] else sourceName cfg cfg.headSource
            local tgt = findSourceNodeByName nextName undefined
            local bip = bipedNeckNode cfg i
            if src != undefined and tgt != undefined and bip != undefined do
            (
                local d = tgt.transform.pos - src.transform.pos
                fitDir bip (safeNorm d [0, 0, 1]) (length d) undefined w w
            )
        )

        true
    ),

    fn alignHead cfg fig =
    (
        local head = sourcePos cfg cfg.headSource
        local bip = bipedNode cfg cfg.headBiped
        if head == undefined or bip == undefined then return false

        local up = [0, 0, 1]
        local headLen = extentAlong (pointsNear fig[1] head (fig[4] * 0.25)) head up (fig[4] * 0.07) (amax 1.0 (fig[3] - head.z))
        fitDir bip up headLen undefined (headLen * 1.1) (headLen * 0.85)
        log cfg "Head aligned."
        true
    ),

    fn palmAcross cfg side =
    (
        local index1 = sourcePos cfg (sideSlot side "Index1")
        local pinky1 = sourcePos cfg (sideSlot side "Pinky1")
        if index1 == undefined or pinky1 == undefined then undefined else pinky1 - index1
    ),

    -- #(middleJointTarget, hingeAxis) for a two-link limb. A bent limb keeps its own joints.
    -- A (nearly) straight limb cannot be matched by Biped's hinge knee/elbow when its slight bend
    -- is sideways, so it is solved like 2-bone IK: start and end joints exact, middle joint in the
    -- plane that bends toward pole.
    fn limbSolve cfg side a b c pole =
    (
        local pa = sourcePos cfg (sideSlot side a)
        local pb = sourcePos cfg (sideSlot side b)
        local pc = sourcePos cfg (sideSlot side c)
        if pa == undefined or pb == undefined or pc == undefined then return #(pb, undefined)
        local hint = bendHint (pb - pa) (pc - pb) cfg.bendThreshold
        if hint != undefined then return #(pb, hint)

        local l1 = distance pa pb
        local l2 = distance pb pc
        local reach = distance pa pc
        if reach < 1e-3 then return #(pb, undefined)
        local u = normalize (pc - pa)
        local v = pole - u * (dot pole u)
        if (length v) < 1e-4 then return #(pb, undefined)
        v = normalize v
        local hipAngle = acos (amax -1.0 (amin 1.0 ((l1 * l1 + reach * reach - l2 * l2) / (2.0 * l1 * reach))))
        local mid = pa + (u * (cos hipAngle) + v * (sin hipAngle)) * l1
        local offset = distance mid pb
        if offset > 1e-3 do append hingeOffsets #((sourceNode cfg (sideSlot side b)).name, offset)
        #(mid, normalize (cross u v))
    ),

    fn linkValue link idx defaultValue =
    (
        if link.count >= idx then link[idx] else defaultValue
    ),

    fn fitFoot cfg bip footPos ballPos fig =
    (
        local up = [0, 0, 1]
        local footFwd = safeNorm ((ballPos - footPos) - up * (dot (ballPos - footPos) up)) fig[5]
        -- foot X points down to the sole, Y forward to the ball
        aimLoop bip (-up) (cross (-up) footFwd)
        if cfg.footScaleEnabled do
        (
            local ankleH = amax 0.1 (footPos.z - fig[2])
            local ballDist = amax 0.1 (dot (ballPos - footPos) footFwd)
            -- the Toe0 pivot sits at [scale.x, 0.8 * scale.y] in foot space: sole height, under the ball
            biped.setTransform bip #scale [ankleH, ballDist / 0.8, ballDist * 0.5] false
        )
        footFwd
    ),

    fn alignBodyLinks cfg fig =
    (
        if cfg.bodyLinks.count == 0 then return false

        log cfg "Aligning configured body links..."

        -- knees bend toward the facing direction, elbows away from it
        local limbs = Dictionary #string
        for side in #("l", "r") do
        (
            limbs[side + "arm"] = limbSolve cfg side "UpperArm" "Forearm" "Hand" (-fig[5])
            limbs[side + "leg"] = limbSolve cfg side "Thigh" "Calf" "Foot" fig[5]
        )

        for link in cfg.bodyLinks do
        (
            local suffix = link[1]
            local bip = bipedNode cfg suffix
            local src = sourcePos cfg link[2]
            local child = sourcePos cfg link[3]
            local sideKey = toLower (substring suffix 1 1)
            if matchPattern suffix pattern:"* UpperArm" do child = limbs[sideKey + "arm"][1]
            if matchPattern suffix pattern:"* Forearm" do src = limbs[sideKey + "arm"][1]
            if matchPattern suffix pattern:"* Thigh" do child = limbs[sideKey + "leg"][1]
            if matchPattern suffix pattern:"* Calf" do src = limbs[sideKey + "leg"][1]
            local helperType = linkValue link 4 #arm
            local doPos = linkValue link 5 true
            local doRot = linkValue link 6 true
            local doScale = linkValue link 7 true
            if bip == undefined or src == undefined do continue
            local side = toLower (substring suffix 1 1)

            if matchPattern suffix pattern:"* Foot" then
            (
                if child != undefined do fitFoot cfg bip src child fig
            )
            else
            (
                -- only clavicles take a position; the rest hang off their parent link
                if doPos and matchPattern suffix pattern:"* Clavicle" do biped.setTransform bip #pos src false
                if doRot and helperType != #none and child != undefined do
                (
                    local hint = undefined
                    local thickness = 0.26
                    if matchPattern suffix pattern:"* UpperArm" or matchPattern suffix pattern:"* Forearm" do hint = limbs[side + "arm"][2]
                    if matchPattern suffix pattern:"* Thigh" or matchPattern suffix pattern:"* Calf" do (hint = limbs[side + "leg"][2]; thickness = 0.28)
                    if matchPattern suffix pattern:"* Hand" do hint = palmAcross cfg side
                    if matchPattern suffix pattern:"* Clavicle" do thickness = 0.3
                    if matchPattern suffix pattern:"* Hand" then
                    (
                        local across = palmAcross cfg side
                        local palmWidth = if across != undefined then length across else (distance src child) * 0.8
                        local d = child - src
                        fitDir bip (safeNorm d [1, 0, 0]) (length d) hint (palmWidth * 0.35) (palmWidth * 1.15) doScale:doScale
                    )
                    else fitLink bip src child hint thickness doScale:doScale
                )
            )
        )

        true
    ),

    fn alignFingerChain cfg chain fig =
    (
        if chain.count < 2 then return false

        local slots = chain[1]
        local bips = chain[2]
        local limit = amin slots.count bips.count
        if limit == 0 then return false

        local joints = #()
        for i = 1 to limit do
        (
            local p = sourcePos cfg slots[i]
            if p == undefined then exit
            append joints p
        )
        if joints.count < 2 then return false

        local side = toLower (substring bips[1] 1 1)
        local links = for i = 1 to joints.count collect (bipedNode cfg bips[i])
        if links[1] == undefined then return false

        local across = palmAcross cfg side
        local fingerW = if across != undefined then (length across) * 0.26 else (distance joints[1] joints[2]) * 0.4
        local hint = if joints.count >= 3 then bendHint (joints[2] - joints[1]) (joints[3] - joints[2]) cfg.bendThreshold else undefined
        if hint == undefined and not (matchPattern bips[1] pattern:"*Finger0") do hint = across

        biped.setTransform links[1] #pos joints[1] false
        for i = 1 to joints.count - 1 do fitLink links[i] joints[i] joints[i + 1] hint ((fingerW / (distance joints[i] joints[i + 1])) * (1.0 - 0.1 * (i - 1)))

        -- last link has no child joint: keep the direction, take the length from the fingertip on the mesh
        local lastIdx = joints.count
        local lastBip = links[lastIdx]
        if lastBip != undefined do
        (
            local tipDir = normalize (joints[lastIdx] - joints[lastIdx - 1])
            local lastLen = distance joints[lastIdx - 1] joints[lastIdx]
            local handPts = pointsNear fig[1] joints[lastIdx] (fig[4] * 0.08)
            local tipLen = extentAlong handPts joints[lastIdx] tipDir (lastLen * 0.45) (lastLen * 0.8)
            tipLen = amax (lastLen * 0.5) (amin (lastLen * 2.0) tipLen)
            fitDir lastBip tipDir tipLen hint (fingerW * 0.8) (fingerW * 0.8)
        )

        true
    ),

    fn alignFingers cfg fig =
    (
        if cfg.fingerChains.count == 0 then return false

        log cfg "Aligning configured finger chains..."

        for chain in cfg.fingerChains do alignFingerChain cfg chain fig
        true
    ),

    fn alignToes cfg fig =
    (
        for toeDef in cfg.toeConstraints where toeDef.count >= 2 do
        (
            local ball = sourcePos cfg toeDef[1]
            local toeBip = bipedNode cfg toeDef[2]
            local side = toLower (substring toeDef[2] 1 1)
            local foot = sourcePos cfg (sideSlot side "Foot")
            if ball != undefined and toeBip != undefined and foot != undefined do
            (
                local up = [0, 0, 1]
                local fwd = safeNorm ((ball - foot) - up * (dot (ball - foot) up)) fig[5]
                local ballDist = dot (ball - foot) fwd
                local toeLen = extentAlong (pointsNear fig[1] ball (fig[4] * 0.15)) ball fwd (ballDist * 0.25) (ballDist * 0.45)
                fitDir toeBip fwd toeLen undefined ((amax 0.1 (foot.z - fig[2])) * 0.35) (ballDist * 0.45)
            )
        )
    ),

    fn applyPostAdjustments cfg =
    (
        for rotDef in cfg.postRotations do
        (
            if rotDef.count >= 3 do
            (
                local bip = bipedNode cfg rotDef[1]
                if bip != undefined do
                (
                    in coordsys local rotate bip (angleaxis rotDef[2] rotDef[3])
                )
            )
        )

        for moveDef in cfg.postMoves do
        (
            if moveDef.count >= 2 do
            (
                local bip = bipedNode cfg moveDef[1]
                if bip != undefined do move bip moveDef[2]
            )
        )
    ),

    -- ----------------------------------------------------------- constrain

    -- #(sourceNode, bipedNode, mode) for every mapped pair; the root is handled separately
    fn collectPairs cfg spineNames neckNames =
    (
        local pairs = #()
        local pelvisSrc = sourceNode cfg cfg.pelvisSource
        local rootSrc = sourceNode cfg cfg.rootSource
        if pelvisSrc != undefined and pelvisSrc != rootSrc do append pairs #(pelvisSrc, bipedNode cfg "Pelvis", #rot)
        for i = 1 to spineNames.count do append pairs #(getNodeByName spineNames[i], bipedSpineNode cfg i, (if i == 1 then #both else #rot))
        for i = 1 to neckNames.count do append pairs #(getNodeByName neckNames[i], bipedNeckNode cfg i, #rot)
        append pairs #(sourceNode cfg cfg.headSource, bipedNode cfg cfg.headBiped, #rot)
        for link in cfg.bodyLinks do append pairs #(sourceNode cfg link[2], bipedNode cfg link[1], linkValue link 8 #both)
        for chain in cfg.fingerChains where chain.count >= 2 do
        (
            for i = 1 to (amin chain[1].count chain[2].count) do append pairs #(sourceNode cfg chain[1][i], bipedNode cfg chain[2][i], #rot)
        )
        for toeDef in cfg.toeConstraints where toeDef.count >= 2 do append pairs #(sourceNode cfg toeDef[1], bipedNode cfg toeDef[2], (if toeDef.count >= 3 then toeDef[3] else #rot))
        for twistDef in cfg.twistConstraints where twistDef.count >= 2 do append pairs #(sourceNode cfg twistDef[1], bipedNode cfg twistDef[2], (if twistDef.count >= 3 then twistDef[3] else #rot))
        pairs
    ),

    fn applyAllConstraints cfg spineNames neckNames fig =
    (
        if not cfg.createConstraints then return false

        log cfg "Applying constraints after figure mode..."
        local bipRoot = bipedNode cfg #root
        local rootSrc = sourceNode cfg cfg.rootSource
        local pelvisSrc = sourceNode cfg cfg.pelvisSource
        local pairs = collectPairs cfg spineNames neckNames
        local posTolerance = fig[4] * 0.003
        local usePos = for pr in pairs collect \
            ((pr[3] == #both or pr[3] == #pos) and pr[1] != undefined and pr[2] != undefined and (distance pr[1].transform.pos pr[2].transform.pos) <= posTolerance)
        local count = 0
        local skippedPos = #()

        with animate off
        (
            -- the root rides on a point linked to the Biped; world-space constraints respect any
            -- rotation on the rig's parent nodes (FBX axis conversion), a Link constraint would not
            if rootSrc != undefined and bipRoot != undefined do
            (
                local driverParent = if pelvisSrc != undefined and pelvisSrc != rootSrc then bipRoot else (bipedNode cfg "Pelvis")
                local driver = Point name:(bipRoot.name + " Root Driver") size:(fig[4] * 0.05) box:true cross:false axistripod:false centermarker:false
                driver.transform = rootSrc.transform
                driver.parent = driverParent
                hide driver
                local pc = Position_Constraint()
                rootSrc.position.controller = pc
                pc.appendTarget driver 100.0
                local oc = Orientation_Constraint()
                rootSrc.rotation.controller = oc
                oc.appendTarget driver 100.0
                count += 1
            )

            for i = 1 to pairs.count do
            (
                local src = pairs[i][1]
                local bip = pairs[i][2]
                local mode = pairs[i][3]
                if src == undefined or bip == undefined or mode == #none or src == rootSrc do continue
                if mode == #both or mode == #rot do
                (
                    local oc = Orientation_Constraint()
                    src.rotation.controller = oc
                    oc.appendTarget bip 100.0
                    oc.relative = true
                )
                if usePos[i] then
                (
                    local pc = Position_Constraint()
                    src.position.controller = pc
                    pc.appendTarget bip 100.0
                    pc.relative = true
                )
                else if (mode == #both or mode == #pos) and (for h in hingeOffsets where h[1] == src.name collect h).count == 0 do append skippedPos src.name
                count += 1
            )
        )

        log cfg ("Constrained " + count as string + " source bones.")
        if skippedPos.count > 0 do log cfg ("Position constraint skipped (joint offset above tolerance): " + skippedPos as string)
        true
    ),

    fn reportFit cfg spineNames neckNames =
    (
        local worst = 0.0
        local worstName = ""
        local hingeNames = for h in hingeOffsets collect h[1]
        for pr in (collectPairs cfg spineNames neckNames) where pr[1] != undefined and pr[2] != undefined do
        (
            local k = toLower pr[1].name
            if matchPattern k pattern:"*twist*" or matchPattern k pattern:"*toe*" or matchPattern k pattern:"*ball*" or pr[1] == sourceNode cfg cfg.pelvisSource do continue
            if findItem hingeNames pr[1].name > 0 do continue
            local d = distance pr[1].transform.pos pr[2].transform.pos
            if d > worst do (worst = d; worstName = pr[1].name)
        )
        log cfg ("Biped fitted. Largest joint offset " + fmt worst + " (" + worstName + ").")
        if hingeOffsets.count > 0 do
            log cfg ("Straight limbs solved on the hinge plane (end joints exact), knee/elbow moved: " + \
                ((for h in hingeOffsets collect (h[1] + " " + fmt h[2])) as string))
        if unaimed.count > 0 do log cfg ("WARNING: Biped links that did not reach their target: " + unaimed as string)
    ),

    fn cleanup cfg =
    (
        clearSelection()
        local root = bipedNode cfg #root
        if root != undefined do select root
    ),

    -- ------------------------------------------------------------- presets

    fn makeUEBoneMap =
    (
        #(
            #(#root, "root"), #(#pelvis, "pelvis"), #(#head, "head"),
            #(#lClavicle, "clavicle_l"), #(#lUpperArm, "upperarm_l"), #(#lForearm, "lowerarm_l"), #(#lHand, "hand_l"),
            #(#rClavicle, "clavicle_r"), #(#rUpperArm, "upperarm_r"), #(#rForearm, "lowerarm_r"), #(#rHand, "hand_r"),
            #(#lThigh, "thigh_l"), #(#lCalf, "calf_l"), #(#lFoot, "foot_l"), #(#lBall, "ball_l"),
            #(#rThigh, "thigh_r"), #(#rCalf, "calf_r"), #(#rFoot, "foot_r"), #(#rBall, "ball_r"),
            #(#lThumb1, "thumb_01_l"), #(#lThumb2, "thumb_02_l"), #(#lThumb3, "thumb_03_l"),
            #(#lIndex1, "index_01_l"), #(#lIndex2, "index_02_l"), #(#lIndex3, "index_03_l"),
            #(#lMiddle1, "middle_01_l"), #(#lMiddle2, "middle_02_l"), #(#lMiddle3, "middle_03_l"),
            #(#lRing1, "ring_01_l"), #(#lRing2, "ring_02_l"), #(#lRing3, "ring_03_l"),
            #(#lPinky1, "pinky_01_l"), #(#lPinky2, "pinky_02_l"), #(#lPinky3, "pinky_03_l"),
            #(#rThumb1, "thumb_01_r"), #(#rThumb2, "thumb_02_r"), #(#rThumb3, "thumb_03_r"),
            #(#rIndex1, "index_01_r"), #(#rIndex2, "index_02_r"), #(#rIndex3, "index_03_r"),
            #(#rMiddle1, "middle_01_r"), #(#rMiddle2, "middle_02_r"), #(#rMiddle3, "middle_03_r"),
            #(#rRing1, "ring_01_r"), #(#rRing2, "ring_02_r"), #(#rRing3, "ring_03_r"),
            #(#rPinky1, "pinky_01_r"), #(#rPinky2, "pinky_02_r"), #(#rPinky3, "pinky_03_r"),
            #(#lUpperArmTwist1, "upperarm_twist_01_l"), #(#lUpperArmTwist2, "upperarm_twist_02_l"),
            #(#lForearmTwist1, "lowerarm_twist_01_l"), #(#lForearmTwist2, "lowerarm_twist_02_l"),
            #(#rUpperArmTwist1, "upperarm_twist_01_r"), #(#rUpperArmTwist2, "upperarm_twist_02_r"),
            #(#rForearmTwist1, "lowerarm_twist_01_r"), #(#rForearmTwist2, "lowerarm_twist_02_r"),
            #(#lThighTwist1, "thigh_twist_01_l"), #(#lThighTwist2, "thigh_twist_02_l"),
            #(#lCalfTwist1, "calf_twist_01_l"), #(#lCalfTwist2, "calf_twist_02_l"),
            #(#rThighTwist1, "thigh_twist_01_r"), #(#rThighTwist2, "thigh_twist_02_r"),
            #(#rCalfTwist1, "calf_twist_01_r"), #(#rCalfTwist2, "calf_twist_02_r")
        )
    ),

    fn makeCCBoneMap =
    (
        #(
            #(#root, "CC_Base_BoneRoot"), #(#pelvis, "CC_Base_Hip"), #(#pelvisBone, "CC_Base_Pelvis"), #(#head, "CC_Base_Head"),
            #(#lClavicle, "CC_Base_L_Clavicle"), #(#lUpperArm, "CC_Base_L_Upperarm"), #(#lForearm, "CC_Base_L_Forearm"), #(#lHand, "CC_Base_L_Hand"),
            #(#rClavicle, "CC_Base_R_Clavicle"), #(#rUpperArm, "CC_Base_R_Upperarm"), #(#rForearm, "CC_Base_R_Forearm"), #(#rHand, "CC_Base_R_Hand"),
            #(#lThigh, "CC_Base_L_Thigh"), #(#lCalf, "CC_Base_L_Calf"), #(#lFoot, "CC_Base_L_Foot"), #(#lBall, "CC_Base_L_ToeBase"),
            #(#rThigh, "CC_Base_R_Thigh"), #(#rCalf, "CC_Base_R_Calf"), #(#rFoot, "CC_Base_R_Foot"), #(#rBall, "CC_Base_R_ToeBase"),
            #(#lThumb1, "CC_Base_L_Thumb1"), #(#lThumb2, "CC_Base_L_Thumb2"), #(#lThumb3, "CC_Base_L_Thumb3"),
            #(#lIndex1, "CC_Base_L_Index1"), #(#lIndex2, "CC_Base_L_Index2"), #(#lIndex3, "CC_Base_L_Index3"),
            #(#lMiddle1, "CC_Base_L_Mid1"), #(#lMiddle2, "CC_Base_L_Mid2"), #(#lMiddle3, "CC_Base_L_Mid3"),
            #(#lRing1, "CC_Base_L_Ring1"), #(#lRing2, "CC_Base_L_Ring2"), #(#lRing3, "CC_Base_L_Ring3"),
            #(#lPinky1, "CC_Base_L_Pinky1"), #(#lPinky2, "CC_Base_L_Pinky2"), #(#lPinky3, "CC_Base_L_Pinky3"),
            #(#rThumb1, "CC_Base_R_Thumb1"), #(#rThumb2, "CC_Base_R_Thumb2"), #(#rThumb3, "CC_Base_R_Thumb3"),
            #(#rIndex1, "CC_Base_R_Index1"), #(#rIndex2, "CC_Base_R_Index2"), #(#rIndex3, "CC_Base_R_Index3"),
            #(#rMiddle1, "CC_Base_R_Mid1"), #(#rMiddle2, "CC_Base_R_Mid2"), #(#rMiddle3, "CC_Base_R_Mid3"),
            #(#rRing1, "CC_Base_R_Ring1"), #(#rRing2, "CC_Base_R_Ring2"), #(#rRing3, "CC_Base_R_Ring3"),
            #(#rPinky1, "CC_Base_R_Pinky1"), #(#rPinky2, "CC_Base_R_Pinky2"), #(#rPinky3, "CC_Base_R_Pinky3"),
            #(#lUpperArmTwist1, "CC_Base_L_UpperarmTwist01"), #(#lUpperArmTwist2, "CC_Base_L_UpperarmTwist02"),
            #(#lForearmTwist1, "CC_Base_L_ForearmTwist01"), #(#lForearmTwist2, "CC_Base_L_ForearmTwist02"),
            #(#rUpperArmTwist1, "CC_Base_R_UpperarmTwist01"), #(#rUpperArmTwist2, "CC_Base_R_UpperarmTwist02"),
            #(#rForearmTwist1, "CC_Base_R_ForearmTwist01"), #(#rForearmTwist2, "CC_Base_R_ForearmTwist02"),
            #(#lThighTwist1, "CC_Base_L_ThighTwist01"), #(#lThighTwist2, "CC_Base_L_ThighTwist02"),
            #(#lCalfTwist1, "CC_Base_L_CalfTwist01"), #(#lCalfTwist2, "CC_Base_L_CalfTwist02"),
            #(#rThighTwist1, "CC_Base_R_ThighTwist01"), #(#rThighTwist2, "CC_Base_R_ThighTwist02"),
            #(#rCalfTwist1, "CC_Base_R_CalfTwist01"), #(#rCalfTwist2, "CC_Base_R_CalfTwist02")
        )
    ),

    fn makeDefaultBodyLinks =
    (
        #(
            #("L Clavicle", #lClavicle, #lUpperArm, #arm, true, true, true, #both),
            #("L UpperArm", #lUpperArm, #lForearm, #arm, true, true, true, #both),
            #("L Forearm", #lForearm, #lHand, #arm, true, true, true, #both),
            #("L Hand", #lHand, #lMiddle1, #arm, true, true, true, #both),
            #("R Clavicle", #rClavicle, #rUpperArm, #arm, true, true, true, #both),
            #("R UpperArm", #rUpperArm, #rForearm, #arm, true, true, true, #both),
            #("R Forearm", #rForearm, #rHand, #arm, true, true, true, #both),
            #("R Hand", #rHand, #rMiddle1, #arm, true, true, true, #both),
            #("L Thigh", #lThigh, #lCalf, #leg, true, true, true, #both),
            #("L Calf", #lCalf, #lFoot, #leg, true, true, true, #both),
            #("L Foot", #lFoot, #lBall, #none, true, false, false, #both),
            #("R Thigh", #rThigh, #rCalf, #leg, true, true, true, #both),
            #("R Calf", #rCalf, #rFoot, #leg, true, true, true, #both),
            #("R Foot", #rFoot, #rBall, #none, true, false, false, #both)
        )
    ),

    fn makeDefaultFingerChains =
    (
        #(
            #(#(#rThumb1, #rThumb2, #rThumb3), #("R Finger0", "R Finger01", "R Finger02"), #finger),
            #(#(#rIndex1, #rIndex2, #rIndex3), #("R Finger1", "R Finger11", "R Finger12"), #finger),
            #(#(#rMiddle1, #rMiddle2, #rMiddle3), #("R Finger2", "R Finger21", "R Finger22"), #finger),
            #(#(#rRing1, #rRing2, #rRing3), #("R Finger3", "R Finger31", "R Finger32"), #finger),
            #(#(#rPinky1, #rPinky2, #rPinky3), #("R Finger4", "R Finger41", "R Finger42"), #finger),
            #(#(#lThumb1, #lThumb2, #lThumb3), #("L Finger0", "L Finger01", "L Finger02"), #finger),
            #(#(#lIndex1, #lIndex2, #lIndex3), #("L Finger1", "L Finger11", "L Finger12"), #finger),
            #(#(#lMiddle1, #lMiddle2, #lMiddle3), #("L Finger2", "L Finger21", "L Finger22"), #finger),
            #(#(#lRing1, #lRing2, #lRing3), #("L Finger3", "L Finger31", "L Finger32"), #finger),
            #(#(#lPinky1, #lPinky2, #lPinky3), #("L Finger4", "L Finger41", "L Finger42"), #finger)
        )
    ),

    fn makeDefaultTwistConstraints =
    (
        #(
            #(#lUpperArmTwist1, "LUpArmTwist", #rot), #(#lUpperArmTwist2, "LUpArmTwist1", #rot),
            #(#lForearmTwist1, "L ForeTwist", #rot), #(#lForearmTwist2, "L ForeTwist1", #rot),
            #(#rUpperArmTwist1, "RUpArmTwist", #rot), #(#rUpperArmTwist2, "RUpArmTwist1", #rot),
            #(#rForearmTwist1, "R ForeTwist", #rot), #(#rForearmTwist2, "R ForeTwist1", #rot),
            #(#lThighTwist1, "LThighTwist", #rot), #(#lThighTwist2, "LThighTwist1", #rot),
            #(#lCalfTwist1, "LCalfTwist", #rot), #(#lCalfTwist2, "LCalfTwist1", #rot),
            #(#rThighTwist1, "RThighTwist", #rot), #(#rThighTwist2, "RThighTwist1", #rot),
            #(#rCalfTwist1, "RCalfTwist", #rot), #(#rCalfTwist2, "RCalfTwist1", #rot)
        )
    ),

    -- the Toe0 pivot sits on the sole, below the ball joint, so toes take rotation only
    fn makeDefaultToeConstraints =
    (
        #(
            #(#lBall, "L Toe0", #rot, false),
            #(#rBall, "R Toe0", #rot, false)
        )
    ),

    fn makeUEPreset =
    (
        local cfg = CloneBipedRemapPreset()
        cfg.name = "Unreal"
        cfg.boneMap = makeUEBoneMap()
        cfg.bodyLinks = makeDefaultBodyLinks()
        cfg.fingerChains = makeDefaultFingerChains()
        cfg.twistConstraints = makeDefaultTwistConstraints()
        cfg.toeConstraints = makeDefaultToeConstraints()
        cfg.spineNames = #()
        cfg.spineDetectPrefix = "spine_0"
        cfg.spineDetectMax = 5
        cfg.neckNames = #()
        cfg.neckDetectPrefix = "neck_0"
        cfg.neckDetectMax = 2
        cfg.requiredSlots = #(#pelvis, #head)
        cfg
    ),

    fn makeCCPreset =
    (
        local cfg = makeUEPreset()
        cfg.name = "Character Creator"
        cfg.boneMap = makeCCBoneMap()
        cfg.spineNames = #("CC_Base_Waist", "CC_Base_Spine01", "CC_Base_Spine02")
        cfg.spineDetectPrefix = ""
        cfg.spineDetectMax = 0
        cfg.neckNames = #("CC_Base_NeckTwist01", "CC_Base_NeckTwist02")
        cfg.neckDetectPrefix = ""
        cfg.neckDetectMax = 0
        cfg
    ),

    fn run cfg =
    (
        if cfg == undefined do cfg = makeUEPreset()

        resetState()

        local spineNames = detectedNameList cfg.spineNames cfg.spineDetectPrefix cfg.spineDetectMax
        local neckNames = detectedNameList cfg.neckNames cfg.neckDetectPrefix cfg.neckDetectMax

        log cfg ("Clone Biped Remapper preset: " + cfg.name)
        log cfg ("Detected spine bones: " + (spineNames as string))
        log cfg ("Detected neck bones: " + (neckNames as string))

        if not (validateRequired cfg) then
        (
            format "Clone Biped Remapper aborted. Missing required source bones: %\n" missing
            return false
        )

        local rootSrc = sourceNode cfg cfg.rootSource
        if cfg.createConstraints and rootSrc != undefined and classOf rootSrc.rotation.controller == Orientation_Constraint do
        (
            format "Clone Biped Remapper aborted: % is already constrained (rig already converted).\n" rootSrc.name
            return false
        )

        if cfg.holdScene do holdMaxFile()

        local watched = sourceMeshes cfg
        local before = for o in watched collect (meshPoints o maxCount:20000)
        local fig = measureFigure cfg

        createBipedFor cfg spineNames.count neckNames.count fig
        alignRoot cfg fig
        alignSpine cfg spineNames neckNames
        alignNeck cfg neckNames
        alignHead cfg fig
        alignBodyLinks cfg fig
        alignFingers cfg fig
        alignToes cfg fig
        applyPostAdjustments cfg
        reportFit cfg spineNames neckNames

        if cfg.createConstraints or cfg.exitFigureMode do setFigureMode cfg false

        applyAllConstraints cfg spineNames neckNames fig

        if cfg.createConstraints do
        (
            local drift = 0.0
            local driftName = ""
            for i = 1 to watched.count where isValidNode watched[i] do
            (
                local d = maxDrift before[i] (meshPoints watched[i] maxCount:20000)
                if d > drift do (drift = d; driftName = watched[i].name)
            )
            log cfg ("Bind drift with Biped driving: " + fmt drift + (if driftName != "" then " (" + driftName + ")" else "") + " over " + watched.count as string + " skinned mesh(es).")
            if drift > fig[4] * 0.001 do log cfg "WARNING: the Biped does not reproduce the bind pose; check the constraints above."
        )
        cleanup cfg

        if missing.count > 0 do format "Clone Biped Remapper skipped missing optional items: %\n" missing
        print "Clone Biped Remapper complete."
        true
    )
)

CloneBipedRemapper = CloneBipedRemapperStruct()

try(destroyDialog CloneBipedRemapperRollout)catch()

rollout CloneBipedRemapperRollout "Clone Biped Remapper" width:620 height:735
(
    local uiUpdating = false

    dropdownlist ddlPreset "Preset" items:#("Unreal", "Character Creator") pos:[12, 10] width:190
    button btnLoadPreset "Load Preset" pos:[210, 8] width:92 height:24
    button btnScan "Scan Missing" pos:[310, 8] width:100 height:24
    button btnRun "Run Remap" pos:[504, 8] width:100 height:24

    groupBox grpOptions "Options" pos:[12, 42] width:592 height:112
    checkbox chkCreateBiped "Create Biped" pos:[24, 62] width:116 checked:true
    checkbox chkCreateConstraints "Create Constraints" pos:[150, 62] width:130 checked:true
    checkbox chkHold "Hold Scene" pos:[290, 62] width:120 checked:true
    checkbox chkVerbose "Verbose Log" pos:[430, 62] width:95 checked:true
    edittext edtBipedName "Biped Root" pos:[24, 88] width:190 height:18
    spinner spnSize "Size" pos:[240, 88] width:112 range:[1, 10000, 200] type:#float scale:1
    spinner spnAngle "Angle" pos:[374, 88] width:112 range:[-360, 360, -90] type:#float scale:1
    checkbox chkFootScale "Foot Scale" pos:[500, 90] width:90 checked:true
    spinner spnMinSpine "Min Spine" pos:[24, 120] width:118 range:[1, 10, 1] type:#integer
    spinner spnMaxSpine "Max Spine" pos:[158, 120] width:118 range:[1, 10, 10] type:#integer
    spinner spnMinNeck "Min Neck" pos:[292, 120] width:118 range:[1, 5, 1] type:#integer
    spinner spnMaxNeck "Max Neck" pos:[426, 120] width:118 range:[1, 5, 5] type:#integer

    groupBox grpDetect "Spine / Neck Detection" pos:[12, 164] width:592 height:118
    edittext edtSpineNames "Spine Names" pos:[24, 186] width:280 height:18
    edittext edtNeckNames "Neck Names" pos:[314, 186] width:280 height:18
    edittext edtSpinePrefix "Spine Prefix" pos:[24, 216] width:190 height:18
    spinner spnSpineDetectMax "Max" pos:[230, 216] width:88 range:[0, 20, 5] type:#integer
    edittext edtNeckPrefix "Neck Prefix" pos:[314, 216] width:190 height:18
    spinner spnNeckDetectMax "Max" pos:[520, 216] width:74 range:[0, 10, 2] type:#integer
    label lblDetectHint "Leave explicit names empty to use prefix detection. Size/Angle are fallbacks; the mesh and feet decide." pos:[24, 250] width:560 height:16

    listbox lbBoneMap "Bone Map" pos:[12, 300] width:592 height:23

    groupBox grpEdit "Selected Bone Slot" pos:[12, 660] width:592 height:68
    label lblSlot "Slot: -" pos:[24, 682] width:190 height:16
    edittext edtSource "Source" pos:[156, 678] width:240 height:18
    button btnUseSelected "Use Selected" pos:[404, 676] width:92 height:24
    button btnSetSource "Set" pos:[504, 676] width:42 height:24
    button btnSelectSource "Select" pos:[552, 676] width:48 height:24
    button btnClearSource "Clear" pos:[504, 704] width:96 height:20

    fn getConfig =
    (
        if CloneBipedRemapperUIConfig == undefined do CloneBipedRemapperUIConfig = CloneBipedRemapper.makeUEPreset()
        CloneBipedRemapperUIConfig
    )

    fn selectedBoneMapIndex =
    (
        local idx = lbBoneMap.selection
        if idx == undefined do idx = 0
        idx
    )

    fn pullOptions =
    (
        local cfg = getConfig()

        cfg.createBiped = chkCreateBiped.checked
        cfg.createConstraints = chkCreateConstraints.checked
        cfg.holdScene = chkHold.checked
        cfg.verbose = chkVerbose.checked
        cfg.footScaleEnabled = chkFootScale.checked
        cfg.bipedName = edtBipedName.text
        cfg.bipedSize = spnSize.value
        cfg.bipedAngle = spnAngle.value
        cfg.minimumSpineLinks = spnMinSpine.value as integer
        cfg.maximumSpineLinks = spnMaxSpine.value as integer
        cfg.minimumNeckLinks = spnMinNeck.value as integer
        cfg.maximumNeckLinks = spnMaxNeck.value as integer
        cfg.spineNames = CloneBipedRemapper.splitNameText edtSpineNames.text
        cfg.neckNames = CloneBipedRemapper.splitNameText edtNeckNames.text
        cfg.spineDetectPrefix = edtSpinePrefix.text
        cfg.neckDetectPrefix = edtNeckPrefix.text
        cfg.spineDetectMax = spnSpineDetectMax.value as integer
        cfg.neckDetectMax = spnNeckDetectMax.value as integer

        cfg
    )

    fn refreshSelectedSlot =
    (
        local cfg = getConfig()
        local idx = selectedBoneMapIndex()

        if idx > 0 and idx <= cfg.boneMap.count then
        (
            local pair = cfg.boneMap[idx]
            lblSlot.text = "Slot: " + CloneBipedRemapper.slotLabel pair[1]

            if pair.count >= 2 then
            (
                edtSource.text = pair[2] as string
            )
            else
            (
                edtSource.text = ""
            )
        )
        else
        (
            lblSlot.text = "Slot: -"
            edtSource.text = ""
        )
    )

    fn refreshBoneList preferredIndex =
    (
        local cfg = getConfig()
        local idx = preferredIndex

        lbBoneMap.items = CloneBipedRemapper.boneMapItems cfg

        if idx == undefined do idx = 1
        if idx < 1 do idx = 1
        if idx > lbBoneMap.items.count do idx = lbBoneMap.items.count
        if lbBoneMap.items.count > 0 do lbBoneMap.selection = idx

        refreshSelectedSlot()
    )

    fn pushConfigToUI =
    (
        local cfg = getConfig()

        uiUpdating = true

        if cfg.name == "Character Creator" then
        (
            ddlPreset.selection = 2
        )
        else
        (
            ddlPreset.selection = 1
        )
        chkCreateBiped.checked = cfg.createBiped
        chkCreateConstraints.checked = cfg.createConstraints
        chkHold.checked = cfg.holdScene
        chkVerbose.checked = cfg.verbose
        chkFootScale.checked = cfg.footScaleEnabled
        edtBipedName.text = cfg.bipedName
        spnSize.value = cfg.bipedSize
        spnAngle.value = cfg.bipedAngle
        spnMinSpine.value = cfg.minimumSpineLinks
        spnMaxSpine.value = cfg.maximumSpineLinks
        spnMinNeck.value = cfg.minimumNeckLinks
        spnMaxNeck.value = cfg.maximumNeckLinks
        edtSpineNames.text = CloneBipedRemapper.joinNameText cfg.spineNames
        edtNeckNames.text = CloneBipedRemapper.joinNameText cfg.neckNames
        edtSpinePrefix.text = cfg.spineDetectPrefix
        edtNeckPrefix.text = cfg.neckDetectPrefix
        spnSpineDetectMax.value = cfg.spineDetectMax
        spnNeckDetectMax.value = cfg.neckDetectMax

        refreshBoneList 1

        uiUpdating = false
    )

    fn loadPreset idx =
    (
        if idx == 2 then
        (
            CloneBipedRemapperUIConfig = CloneBipedRemapper.makeCCPreset()
        )
        else
        (
            CloneBipedRemapperUIConfig = CloneBipedRemapper.makeUEPreset()
        )

        pushConfigToUI()
    )

    fn setCurrentSource sourceName =
    (
        local cfg = getConfig()
        local idx = selectedBoneMapIndex()

        if idx > 0 and idx <= cfg.boneMap.count do
        (
            local pair = cfg.boneMap[idx]
            cfg.boneMap = CloneBipedRemapper.replaceBoneName cfg.boneMap pair[1] sourceName
            refreshBoneList idx
        )
    )

    on CloneBipedRemapperRollout open do
    (
        if CloneBipedRemapperUIConfig == undefined do CloneBipedRemapperUIConfig = CloneBipedRemapper.makeUEPreset()
        pushConfigToUI()
    )

    on ddlPreset selected idx do
    (
        if not uiUpdating do loadPreset idx
    )
    on btnLoadPreset pressed do loadPreset ddlPreset.selection
    on lbBoneMap selected idx do refreshSelectedSlot()

    on btnUseSelected pressed do
    (
        if selection.count > 0 then
        (
            edtSource.text = selection[1].name
            setCurrentSource edtSource.text
        )
        else
        (
            messageBox "Select a source bone first." title:"Clone Biped Remapper"
        )
    )

    on btnSetSource pressed do setCurrentSource edtSource.text

    on btnClearSource pressed do
    (
        edtSource.text = ""
        setCurrentSource ""
    )

    on btnSelectSource pressed do
    (
        local cfg = getConfig()
        local idx = selectedBoneMapIndex()

        if idx > 0 and idx <= cfg.boneMap.count do
        (
            local pair = cfg.boneMap[idx]
            local src = undefined
            if pair.count >= 2 do src = getNodeByName pair[2]

            if src != undefined then
            (
                select src
            )
            else
            (
                messageBox "Mapped source bone was not found in the scene." title:"Clone Biped Remapper"
            )
        )
    )

    on btnScan pressed do
    (
        local cfg = pullOptions()
        local missingItems = CloneBipedRemapper.missingBoneMapItems cfg

        if missingItems.count == 0 then
        (
            messageBox "All mapped source bones exist in the scene." title:"Clone Biped Remapper"
        )
        else
        (
            local msg = "Missing or empty mapped bones:\n\n" + CloneBipedRemapper.joinNameText missingItems
            format "%\n" msg
            messageBox msg title:"Clone Biped Remapper"
        )

        refreshBoneList (selectedBoneMapIndex())
    )

    on btnRun pressed do
    (
        local cfg = pullOptions()
        CloneBipedRemapper.run cfg
        refreshBoneList (selectedBoneMapIndex())
    )
)

fn CloneBipedRemapperUI =
(
    if CloneBipedRemapperUIConfig == undefined do CloneBipedRemapperUIConfig = CloneBipedRemapper.makeUEPreset()
    try(destroyDialog CloneBipedRemapperRollout)catch()
    createDialog CloneBipedRemapperRollout
)

if CloneBipedRemapperAutoRun then
(
    CloneBipedRemapper.run (CloneBipedRemapper.makeUEPreset())
)
else
(
    if CloneBipedRemapperOpenUI do CloneBipedRemapperUI()
)
