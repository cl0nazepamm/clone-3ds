/*
    Clone_Genesis9_Importer.ms
    --------------------------
    DAZ Genesis 9 FBX -> one skeleton -> Biped.

    DAZ exports every figure (body, Eyes, Mouth, Tear, Eyelashes, clothing)
    with its own copy of the "hip" skeleton, and each Skin modifier points at
    its own copy. This tool:
      1. Imports the FBX (or takes a figure that is already in the scene).
      2. Rebinds every Skin modifier to the body skeleton, moves bones that
         only exist on a sub-figure (tongue01-05, clothing bones) onto it,
         and deletes the duplicate skeletons.
      3. Fits a Biped to the body skeleton in Figure Mode, using joint
         positions only (DAZ bones import without roll information).
      4. Drives the Genesis 9 bones from the Biped: hip follows a hidden
         driver point linked to the Biped COM, the body chain gets relative
         Orientation constraints, and relative Position constraints go where
         the two hierarchies differ (spine base, clavicles, thighs).

    Skin weights are never edited. Face bones, eyes, jaw, tongue, pectorals,
    metacarpals and individual toes stay as children of the driven bones.
    Bind-pose vertex drift is measured after the merge and after constraining.

    Usage:
        Import the Genesis 9 FBX, then drag this script onto a viewport.
        It converts the selected figure, or every figure in the scene, holds
        the scene first (Edit > Fetch undoes) and prints a report to the Listener.

        Scripted:
        global CloneG9AutoRun = false
        fileIn @"...\Rigging\Clone_Genesis9_Importer.ms"
        CloneG9.importFBX @"D:\chars\figure.fbx"
        CloneG9.convertScene()
*/

global CloneG9
global CloneG9AutoRun

struct CloneG9Struct
(
    mergeSkeletons = true,
    flattenFigures = true,
    createBiped = true,
    constrainBones = true,
    holdScene = true,
    importMorphs = true,
    importAnimation = false,
    bipedName = "",             -- empty keeps the Biped default (Bip001, Bip002, ...)
    bendThreshold = 8.0,        -- degrees; a chain bent less than this counts as straight
    verbose = true,

    report = #(),
    unaimed = #(),
    hingeOffsets = #(),
    src = undefined,            -- Dictionary: lower-case bone name -> body skeleton node

    bodyKeys = #("pelvis", "spine1", "neck1", "head", "l_upperarm", "l_hand", "r_hand", "l_thigh", "l_foot", "r_foot"),
    requiredKeys = #("hip", "pelvis", "spine1", "neck1", "head", \
        "l_shoulder", "l_upperarm", "l_forearm", "l_hand", "r_shoulder", "r_upperarm", "r_forearm", "r_hand", \
        "l_thigh", "l_shin", "l_foot", "r_thigh", "r_shin", "r_foot"),
    fingerDefs = #(#("thumb", 0), #("index", 1), #("mid", 2), #("ring", 3), #("pinky", 4)),

    -- ------------------------------------------------------------------ utils

    fn log msg =
    (
        append report msg
        if verbose do format "[Genesis9] %\n" msg
    ),

    fn baseName n =
    (
        local parts = filterString (toLower n.name) ":|"
        if parts.count > 0 then parts[parts.count] else ""
    ),

    fn collectTree root =
    (
        local out = #()
        local stack = #(root)
        while stack.count > 0 do
        (
            local n = stack[stack.count]
            stack.count = stack.count - 1
            append out n
            for c in n.children do append stack c
        )
        out
    ),

    fn nameMap nodes =
    (
        local d = Dictionary #string
        for n in nodes do
        (
            local k = baseName n
            if not (hasDictValue d k) do d[k] = n
        )
        d
    ),

    fn topRoot n =
    (
        while n.parent != undefined do n = n.parent
        n
    ),

    fn hasHipAncestor n =
    (
        local p = n.parent
        while p != undefined do
        (
            if (baseName p) == "hip" do return true
            p = p.parent
        )
        false
    ),

    fn skinOf o =
    (
        for m in o.modifiers where classOf m == Skin do return m
        undefined
    ),

    fn skinnedNodes = for o in objects where (skinOf o) != undefined collect o,

    fn skinBones sk = for i = 1 to (skinOps.GetNumberBones sk) collect (skinOps.GetBoneNode sk i),

    fn meshPoints o =
    (
        local m = snapshotAsMesh o
        local pts = for i = 1 to m.numverts collect (getVert m i)
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

    fn fmt v = (formattedPrint v format:".4f"),

    -- ------------------------------------------------------------ discovery

    -- One entry per character: #(bodyHip, #(duplicateHips), characterRoot)
    fn findCharacters pool =
    (
        local hips = for n in pool where (baseName n) == "hip" and not (hasHipAncestor n) collect n
        local roots = #()
        local groups = #()
        for h in hips do
        (
            local r = topRoot h
            local idx = findItem roots r
            if idx == 0 do
            (
                append roots r
                append groups #()
                idx = roots.count
            )
            append groups[idx] h
        )

        local chars = #()
        local orphans = #()
        for gi = 1 to groups.count do
        (
            local best = undefined
            local bestScore = -1
            for h in groups[gi] do
            (
                local tree = collectTree h
                local d = nameMap tree
                local isBody = true
                for k in bodyKeys where not (hasDictValue d k) do isBody = false
                if isBody do
                (
                    -- DAZ puts the base figure's hip directly under the figure root
                    local score = tree.count + (if h.parent == roots[gi] then 100000 else 0)
                    if score > bestScore do (best = h; bestScore = score)
                )
            )
            if best == undefined then
            (
                join orphans groups[gi]
            )
            else
            (
                local dups = for h in groups[gi] where h != best collect h
                append chars #(best, dups, best.parent)
            )
        )

        if orphans.count > 0 do
        (
            if chars.count == 1 then
            (
                join chars[1][2] orphans
            )
            else
            (
                log ("Skipped " + orphans.count as string + " sub-figure skeleton(s) that could not be matched to a single body.")
            )
        )
        chars
    ),

    -- ---------------------------------------------------------------- merge

    fn mergeInto bodyHip dupHips =
    (
        local byName = nameMap (collectTree bodyHip)
        local remap = Dictionary #integer
        local doomed = #()
        local adopted = #()

        for dupHip in dupHips do
        (
            for b in (collectTree dupHip) do
            (
                local k = baseName b
                if hasDictValue byName k then
                (
                    remap[b.inode.handle] = byName[k]
                    append doomed b
                )
                else
                (
                    local newParent = bodyHip
                    if b.parent != undefined and hasDictValue remap b.parent.inode.handle do newParent = remap[b.parent.inode.handle]
                    b.parent = newParent
                    byName[k] = b
                    remap[b.inode.handle] = b
                    append adopted b
                )
            )
        )

        local relinked = 0
        local touched = 0
        for o in skinnedNodes() do
        (
            local sk = skinOf o
            local current = skinBones sk
            local changed = false
            for b in current where b != undefined and hasDictValue remap b.inode.handle do
            (
                local target = remap[b.inode.handle]
                if target != b and findItem current target == 0 do
                (
                    skinOps.ReplaceBone sk b target
                    relinked += 1
                    changed = true
                )
            )
            if changed do touched += 1
        )

        -- A duplicate that is still skinned (e.g. its body twin was already in that Skin) is kept
        -- and rides on its body twin instead of being deleted.
        local kept = #()
        for o in skinnedNodes() do
        (
            for b in (skinBones (skinOf o)) where b != undefined and findItem doomed b > 0 do appendIfUnique kept b
        )
        for b in kept do
        (
            deleteItem doomed (findItem doomed b)
            b.parent = remap[b.inode.handle]
        )
        for d in doomed do
        (
            for c in d.children where findItem doomed c == 0 do c.parent = remap[d.inode.handle]
        )
        local removed = doomed.count
        if removed > 0 do delete doomed

        log ("Merged " + dupHips.count as string + " duplicate skeleton(s): " + removed as string + " bones deleted, " + \
            relinked as string + " skin bones relinked on " + touched as string + " mesh(es).")
        if adopted.count > 0 do log ("Moved onto the body skeleton: " + ((for a in adopted collect a.name) as string))
        if kept.count > 0 do log ("Kept (still skinned alongside their body twin): " + ((for a in kept collect a.name) as string))
        true
    ),

    fn flattenInto charRoot containers =
    (
        if charRoot == undefined then return 0
        local moved = 0
        local removed = 0
        for c in containers where isValidNode c and c != charRoot do
        (
            for o in (for k in c.children collect k) where superClassOf o == GeometryClass do
            (
                o.parent = charRoot
                moved += 1
            )
            if c.children.count == 0 and classOf c == Dummy do
            (
                delete c
                removed += 1
            )
        )
        if moved > 0 do log ("Moved " + moved as string + " figure mesh(es) under " + charRoot.name + ", removed " + removed as string + " empty container(s).")
        moved
    ),

    -- ------------------------------------------------------------ fit math

    fn g k = (if src != undefined and hasDictValue src k then src[k] else undefined),

    fn P k = (g k).transform.pos,

    fn safeNorm v fallback = (if (length v) < 1e-6 then fallback else normalize v),

    fn angleBetween a b = acos (amax -1.0 (amin 1.0 (dot (normalize a) (normalize b)))),

    -- Normal of the plane a chain bends in, or undefined when the chain is (nearly) straight.
    fn bendHint a b =
    (
        if (angleBetween a b) < bendThreshold then undefined else normalize (cross a b)
    ),

    -- #(middleJointTarget, hingeAxis) for a two-link limb. A bent limb keeps its own joints.
    -- A (nearly) straight limb cannot be matched by Biped's hinge knee/elbow when its slight bend
    -- is sideways, so it is solved like 2-bone IK: start and end joints exact, middle joint in the
    -- plane that bends toward pole.
    fn limbSolve pa pb pc pole midName =
    (
        local hint = bendHint (pb - pa) (pc - pb)
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
        if offset > 1e-3 do append hingeOffsets #(midName, offset)
        #(mid, normalize (cross u v))
    ),

    -- Smallest rotation of tm that puts its X axis on dir (keeps the Biped's own roll).
    fn aimFrame tm dir =
    (
        local x0 = normalize tm.row1
        local y0 = normalize tm.row2
        local x1 = normalize dir
        local c = dot x0 x1
        local axis = cross x0 x1
        local s = length axis
        local y1 = y0
        if s > 1e-6 then
        (
            local k = axis / s
            y1 = y0 * c + (cross k y0) * s + k * ((dot k y0) * (1.0 - c))
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

    fn fitDir bn dir len hint w h =
    (
        if bn == undefined or len < 1e-3 then return false
        aimLoop bn dir hint
        biped.setTransform bn #scale [len, w, h] false
        true
    ),

    fn fitLink bn fromPos toPos hint w h =
    (
        local d = toPos - fromPos
        fitDir bn (safeNorm d [1, 0, 0]) (length d) hint w h
    ),

    fn pointsNear pts center radius =
    (
        local r2 = radius * radius
        for p in pts where (dot (p - center) (p - center)) < r2 collect p
    ),

    -- Farthest mesh point in front of origin along dir, inside a tube of the given radius.
    fn extentAlong pts origin dir tube fallback =
    (
        local best = 0.0
        for p in pts do
        (
            local v = p - origin
            local t = dot v dir
            if t > best and (length (v - dir * t)) < tube do best = t
        )
        if best > 1e-3 then best else fallback
    ),

    fn bodyMeshPoints =
    (
        local best = undefined
        local bestCount = 0
        local hand = g "l_hand"
        local foot = g "l_foot"
        for o in skinnedNodes() do
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

    fn chainNames prefix limit =
    (
        local out = #()
        for i = 1 to limit while (g (prefix + i as string)) != undefined do append out (prefix + i as string)
        out
    ),

    fn fitBiped =
    (
        local missing = for k in requiredKeys where (g k) == undefined collect k
        if missing.count > 0 do
        (
            log ("Biped skipped, body bones missing: " + missing as string)
            return undefined
        )

        unaimed = #()
        hingeOffsets = #()
        local up = [0, 0, 1]
        local spines = chainNames "spine" 10
        local necks = chainNames "neck" 5
        local nUT = (chainNames "l_upperarmtwist" 10).count
        local nFT = (chainNames "l_forearmtwist" 10).count
        local nTT = (chainNames "l_thightwist" 10).count

        local pts = bodyMeshPoints()
        local ground = 1e9
        local top = -1e9
        for p in pts do
        (
            if p.z < ground do ground = p.z
            if p.z > top do top = p.z
        )
        if pts.count == 0 do
        (
            ground = amin (P "l_foot").z (P "r_foot").z
            top = (P "head").z + (distance (P "neck1") (P "head")) * 2.0
        )
        local figH = top - ground

        local fwd = [0, -1, 0]
        if (g "l_toes") != undefined and (g "r_toes") != undefined do
        (
            local f = ((P "l_toes") - (P "l_foot")) + ((P "r_toes") - (P "r_foot"))
            fwd = safeNorm (f - up * (dot f up)) fwd
        )

        local thighMid = ((P "l_thigh") + (P "r_thigh")) * 0.5
        local hipWidth = distance (P "l_thigh") (P "r_thigh")
        local shoulderSpan = distance (P "l_upperarm") (P "r_upperarm")

        local bipRoot = biped.createNew figH (atan2 fwd.y fwd.x) thighMid arms:true \
            neckLinks:(amax 1 necks.count) spineLinks:(amax 1 spines.count) fingers:5 fingerLinks:3 \
            toes:1 toeLinks:1 upperarmTwistLinks:nUT forearmTwistLinks:nFT thighTwistLinks:nTT calfTwistLinks:0
        if bipRoot == undefined do
        (
            log "biped.createNew failed."
            return undefined
        )
        if bipedName != "" do
        (
            try (bipRoot.controller.rootName = bipedName) catch (log ("Could not rename the Biped to " + bipedName))
        )
        bipRoot.controller.figureMode = true

        local bipByName = Dictionary #string
        for n in (collectTree bipRoot) do bipByName[toLower n.name] = n
        local rootName = bipRoot.name
        fn B d suffix rootName = (local k = toLower (rootName + " " + suffix); if hasDictValue d k then d[k] else undefined)

        local pairs = #()     -- #(genesisNode, bipedNode, #rot | #posrot)

        -- root and pelvis: Biped places the thighs at the root height, pelvis Z scale is the hip width
        biped.setTransform bipRoot #pos thighMid false
        local pelvis = B bipByName "Pelvis" rootName
        biped.setTransform pelvis #scale [hipWidth * 0.5, hipWidth * 0.9, hipWidth] false
        append pairs #(g "pelvis", pelvis, #rot)

        -- spine
        local spineW = shoulderSpan * 0.55
        local spineB = for i = 1 to spines.count collect (B bipByName (if i == 1 then "Spine" else ("Spine" + (i - 1) as string)) rootName)
        biped.setTransform spineB[1] #pos (P spines[1]) false
        for i = 1 to spines.count do
        (
            local nextPos = if i < spines.count then P spines[i + 1] else P "neck1"
            fitLink spineB[i] (P spines[i]) nextPos undefined (spineW * 0.75) spineW
            append pairs #(g spines[i], spineB[i], (if i == 1 then #posrot else #rot))
        )

        -- neck and head
        local neckB = for i = 1 to necks.count collect (B bipByName (if i == 1 then "Neck" else ("Neck" + (i - 1) as string)) rootName)
        biped.setTransform neckB[1] #pos (P necks[1]) false
        for i = 1 to necks.count do
        (
            local nextPos = if i < necks.count then P necks[i + 1] else P "head"
            fitLink neckB[i] (P necks[i]) nextPos undefined (spineW * 0.35) (spineW * 0.35)
            append pairs #(g necks[i], neckB[i], #rot)
        )
        local headB = B bipByName "Head" rootName
        local headLen = extentAlong (pointsNear pts (P "head") (figH * 0.25)) (P "head") up (figH * 0.07) (top - (P "head").z)
        fitDir headB up headLen undefined (headLen * 1.1) (headLen * 0.85)
        append pairs #(g "head", headB, #rot)

        -- arms, hands, fingers
        for side in #("l", "r") do
        (
            local S = toUpper side
            local sh = P (side + "_shoulder")
            local ua = P (side + "_upperarm")
            local fa = P (side + "_forearm")
            local hd = P (side + "_hand")

            local clavB = B bipByName (S + " Clavicle") rootName
            biped.setTransform clavB #pos sh false
            local clavLen = distance sh ua
            fitLink clavB sh ua undefined (clavLen * 0.3) (clavLen * 0.3)
            append pairs #(g (side + "_shoulder"), clavB, #posrot)

            -- elbows bend away from the facing direction
            local arm = limbSolve ua fa hd (-fwd) (g (side + "_forearm")).name
            local elbow = arm[1]
            local uaB = B bipByName (S + " UpperArm") rootName
            local faB = B bipByName (S + " Forearm") rootName
            fitLink uaB ua elbow arm[2] ((distance ua elbow) * 0.28) ((distance ua elbow) * 0.28)
            fitLink faB elbow hd arm[2] ((distance elbow hd) * 0.24) ((distance elbow hd) * 0.24)
            append pairs #(g (side + "_upperarm"), uaB, #rot)
            append pairs #(g (side + "_forearm"), faB, #rot)

            local across = undefined
            local palmWidth = (distance fa hd) * 0.35
            if (g (side + "_index1")) != undefined and (g (side + "_pinky1")) != undefined do
            (
                across = (P (side + "_pinky1")) - (P (side + "_index1"))
                palmWidth = length across
            )
            local handTarget = if (g (side + "_mid1")) != undefined then P (side + "_mid1") else hd + (hd - fa) * 0.3
            local handB = B bipByName (S + " Hand") rootName
            fitLink handB hd handTarget across (palmWidth * 0.35) (palmWidth * 1.15)
            append pairs #(g (side + "_hand"), handB, #rot)

            local handPts = pointsNear pts hd (figH * 0.18)
            local fingerW = palmWidth * 0.26
            for fd in fingerDefs do
            (
                local joints = for i = 1 to 3 where (g (side + "_" + fd[1] + i as string)) != undefined collect (side + "_" + fd[1] + i as string)
                if joints.count == 3 do
                (
                    local p1 = P joints[1]
                    local p2 = P joints[2]
                    local p3 = P joints[3]
                    local hint = bendHint (p2 - p1) (p3 - p2)
                    if hint == undefined and fd[2] != 0 do hint = across
                    local links = for i = 1 to 3 collect (B bipByName (S + " Finger" + fd[2] as string + (if i > 1 then (i - 1) as string else "")) rootName)
                    biped.setTransform links[1] #pos p1 false
                    fitLink links[1] p1 p2 hint fingerW fingerW
                    fitLink links[2] p2 p3 hint (fingerW * 0.9) (fingerW * 0.9)
                    local tipDir = normalize (p3 - p2)
                    local lastLen = distance p2 p3
                    local tipLen = extentAlong handPts p3 tipDir (lastLen * 0.45) (lastLen * 0.8)
                    tipLen = amax (lastLen * 0.5) (amin (lastLen * 2.0) tipLen)
                    fitDir links[3] tipDir tipLen hint (fingerW * 0.8) (fingerW * 0.8)
                    for i = 1 to 3 do append pairs #(g joints[i], links[i], #rot)
                )
            )

            local upTwist = chainNames (side + "_upperarmtwist") 10
            for i = 1 to upTwist.count do
                append pairs #(g upTwist[i], (B bipByName (S + "UpArmTwist" + (if i > 1 then (i - 1) as string else "")) rootName), #rot)
            local foreTwist = chainNames (side + "_forearmtwist") 10
            for i = 1 to foreTwist.count do
                append pairs #(g foreTwist[i], (B bipByName (S + " ForeTwist" + (if i > 1 then (i - 1) as string else "")) rootName), #rot)
        )

        -- legs, feet, toes
        for side in #("l", "r") do
        (
            local S = toUpper side
            local th = P (side + "_thigh")
            local sn = P (side + "_shin")
            local ft = P (side + "_foot")
            -- knees bend toward the facing direction
            local leg = limbSolve th sn ft fwd (g (side + "_shin")).name
            local legHint = leg[2]
            sn = leg[1]

            local thB = B bipByName (S + " Thigh") rootName
            local cfB = B bipByName (S + " Calf") rootName
            fitLink thB th sn legHint ((distance th sn) * 0.3) ((distance th sn) * 0.3)
            fitLink cfB sn ft legHint ((distance sn ft) * 0.22) ((distance sn ft) * 0.22)
            append pairs #(g (side + "_thigh"), thB, #posrot)
            append pairs #(g (side + "_shin"), cfB, #rot)

            local toes = if (g (side + "_toes")) != undefined then P (side + "_toes") else ft + fwd * ((distance sn ft) * 0.28)
            local footFwd = safeNorm ((toes - ft) - up * (dot (toes - ft) up)) fwd
            local ankleH = amax 0.1 (dot (ft - [0, 0, ground]) up)
            local ballDist = amax 0.1 (dot (toes - ft) footFwd)
            local footW = ballDist * 0.45
            if (g (side + "_bigtoe1")) != undefined and (g (side + "_pinkytoe1")) != undefined do
                footW = (distance (P (side + "_bigtoe1")) (P (side + "_pinkytoe1"))) * 1.35

            local footB = B bipByName (S + " Foot") rootName
            -- foot X points down to the sole, Y forward to the ball
            aimLoop footB (-up) (cross (-up) footFwd)
            -- the Toe0 pivot sits at [scale.x, 0.8 * scale.y] in foot space: sole height, under the ball
            biped.setTransform footB #scale [ankleH, ballDist / 0.8, footW] false
            append pairs #(g (side + "_foot"), footB, #posrot)

            local toeB = B bipByName (S + " Toe0") rootName
            if toeB != undefined and (g (side + "_toes")) != undefined do
            (
                local footPts = pointsNear pts toes (figH * 0.15)
                local toeLen = extentAlong footPts toes footFwd (footW * 0.5) (ballDist * 0.45)
                fitDir toeB footFwd toeLen undefined (ankleH * 0.35) (footW * 0.9)
                append pairs #(g (side + "_toes"), toeB, #rot)
            )

            local thighTwist = chainNames (side + "_thightwist") 10
            for i = 1 to thighTwist.count do
                append pairs #(g thighTwist[i], (B bipByName (S + "ThighTwist" + (if i > 1 then (i - 1) as string else "")) rootName), #rot)
        )

        -- joints that should coincide after the fit
        local worst = 0.0
        local worstName = ""
        local hingeNames = for h in hingeOffsets collect h[1]
        for pr in pairs where pr[1] != undefined and pr[2] != undefined do
        (
            local k = baseName pr[1]
            if matchPattern k pattern:"*twist*" or matchPattern k pattern:"*toes" or k == "pelvis" do continue
            if findItem hingeNames pr[1].name > 0 do continue
            local d = distance pr[1].transform.pos pr[2].transform.pos
            if d > worst do (worst = d; worstName = pr[1].name)
        )
        log ("Biped " + bipRoot.name + " fitted: " + spines.count as string + " spine, " + necks.count as string + " neck, twist " + \
            nUT as string + "/" + nFT as string + "/" + nTT as string + ". Largest joint offset " + fmt worst + " (" + worstName + ").")
        if hingeOffsets.count > 0 do
            log ("Straight limbs solved on the hinge plane (end joints exact), knee/elbow moved: " + \
                ((for h in hingeOffsets collect (h[1] + " " + fmt h[2])) as string))
        if unaimed.count > 0 do log ("WARNING: Biped links that did not reach their target: " + unaimed as string)

        bipRoot.controller.figureMode = false
        #(bipRoot, pairs, figH)
    ),

    -- ----------------------------------------------------------- constrain

    fn constrainToBiped bipRoot pairs figureHeight =
    (
        local hip = g "hip"
        local posTolerance = figureHeight * 0.003
        local count = 0
        local skippedPos = #()
        local unmatched = #()

        -- decide position constraints on the bind pose, before anything moves
        local usePos = for pr in pairs collect \
            (pr[3] == #posrot and pr[1] != undefined and pr[2] != undefined and (distance pr[1].transform.pos pr[2].transform.pos) <= posTolerance)

        with animate off
        (
            -- hip rides on a point linked to the Biped COM. World-space constraints respect the
            -- Genesis9 root's Y-up rotation; a Link constraint would apply it twice.
            local driver = Point name:(bipRoot.name + " G9 Hip Driver") size:(figureHeight * 0.05) box:true cross:false axistripod:false centermarker:false
            driver.transform = hip.transform
            driver.parent = bipRoot
            hide driver
            local hpc = Position_Constraint()
            hip.position.controller = hpc
            hpc.appendTarget driver 100.0
            local hoc = Orientation_Constraint()
            hip.rotation.controller = hoc
            hoc.appendTarget driver 100.0
            count += 1

            for i = 1 to pairs.count do
            (
                local gn = pairs[i][1]
                local bn = pairs[i][2]
                if gn == undefined do continue
                if bn == undefined do
                (
                    append unmatched gn.name
                    continue
                )
                local oc = Orientation_Constraint()
                gn.rotation.controller = oc
                oc.appendTarget bn 100.0
                oc.relative = true
                if usePos[i] then
                (
                    local pc = Position_Constraint()
                    gn.position.controller = pc
                    pc.appendTarget bn 100.0
                    pc.relative = true
                )
                else if pairs[i][3] == #posrot do append skippedPos gn.name
                count += 1
            )
        )

        log ("Constrained " + count as string + " Genesis 9 bones to " + bipRoot.name + ".")
        if skippedPos.count > 0 do log ("Position constraint skipped (joint offset above tolerance): " + skippedPos as string)
        if unmatched.count > 0 do log ("No Biped node for: " + unmatched as string)
        count
    ),

    -- ------------------------------------------------------------- drivers

    fn convertCharacter bodyHip dupHips charRoot =
    (
        local label = if charRoot != undefined then charRoot.name else bodyHip.name
        log ("--- " + label + " ---")

        local containers = for h in dupHips where h.parent != undefined and h.parent != charRoot collect h.parent
        local meshes = skinnedNodes()
        local before = for o in meshes collect (meshPoints o)

        if mergeSkeletons and dupHips.count > 0 do mergeInto bodyHip dupHips
        if mergeSkeletons and flattenFigures do flattenInto charRoot containers

        src = nameMap (collectTree bodyHip)

        local drift = 0.0
        local driftName = ""
        for i = 1 to meshes.count where isValidNode meshes[i] do
        (
            local d = maxDrift before[i] (meshPoints meshes[i])
            if d > drift do (drift = d; driftName = meshes[i].name)
        )
        log ("Bind drift after merge: " + fmt drift + (if driftName != "" then " (" + driftName + ")" else ""))

        local hip = g "hip"
        if hip != undefined and classOf hip.rotation.controller == Orientation_Constraint do
        (
            log "hip is already constrained; Biped step skipped (already converted)."
            return true
        )

        if createBiped do
        (
            local fit = fitBiped()
            if fit != undefined and constrainBones do
            (
                local skel = collectTree bodyHip
                local bindPos = for n in skel collect n.transform.pos
                constrainToBiped fit[1] fit[2] fit[3]
                local boneMove = 0.0
                local boneName = ""
                for i = 1 to skel.count do
                (
                    local d = distance bindPos[i] skel[i].transform.pos
                    if d > boneMove do (boneMove = d; boneName = skel[i].name)
                )
                log ("Largest bone move when constraining: " + fmt boneMove + (if boneName != "" then " (" + boneName + ")" else ""))
                local poseDrift = 0.0
                local poseName = ""
                for i = 1 to meshes.count where isValidNode meshes[i] do
                (
                    local d = maxDrift before[i] (meshPoints meshes[i])
                    if d > poseDrift do (poseDrift = d; poseName = meshes[i].name)
                )
                log ("Bind drift with Biped driving: " + fmt poseDrift + (if poseName != "" then " (" + poseName + ")" else ""))
                if poseDrift > fit[3] * 0.001 do log "WARNING: the Biped does not reproduce the bind pose; check the constraints above."
            )
            if fit != undefined do select fit[1]
        )
        true
    ),

    fn convertNodes pool holdFirst:true =
    (
        report = #()
        local chars = findCharacters pool
        if chars.count == 0 do
        (
            log "No Genesis 9 body skeleton found (a 'hip' tree with pelvis, spine, arms and legs)."
            return false
        )
        if holdFirst and holdScene do holdMaxFile()

        local ok = true
        undo off
        (
            for ch in chars do
            (
                try (convertCharacter ch[1] ch[2] ch[3])
                catch
                (
                    ok = false
                    log ("ERROR: " + getCurrentException())
                )
            )
        )
        redrawViews()
        ok
    ),

    fn convertScene =
    (
        local pool = #()
        if selection.count > 0 then
        (
            local roots = #()
            for s in selection do appendIfUnique roots (topRoot s)
            for r in roots do join pool (collectTree r)
        )
        else pool = objects as array
        convertNodes pool
    ),

    fn importFBX fbxPath =
    (
        report = #()
        if fbxPath == undefined or not (doesFileExist fbxPath) do
        (
            log ("File not found: " + fbxPath as string)
            return false
        )
        if holdScene do holdMaxFile()

        local settings = #(#("Mode", #create), #("Skin", true), #("Shape", importMorphs), #("Animation", importAnimation), #("Cameras", false), #("Lights", false))
        local saved = for s in settings collect #(s[1], (try (FBXImporterGetParam s[1]) catch undefined))
        for s in settings do FBXImporterSetParam s[1] s[2]

        local lastHandle = 0
        for o in objects where o.inode.handle > lastHandle do lastHandle = o.inode.handle
        local imported = importFile fbxPath #noPrompt using:FBXIMP
        for s in saved where s[2] != undefined do try (FBXImporterSetParam s[1] s[2]) catch ()

        if not imported do
        (
            log ("FBX import failed: " + fbxPath)
            return false
        )
        local newNodes = for o in objects where o.inode.handle > lastHandle collect o
        log ("Imported " + newNodes.count as string + " nodes from " + filenameFromPath fbxPath)
        local keep = report
        local ok = convertNodes newNodes holdFirst:false
        report = keep + report
        ok
    )
)

CloneG9 = CloneG9Struct()

-- Dropping the script on a viewport converts the selected figure, or every figure in the scene.
-- Set CloneG9AutoRun = false before fileIn to only load the functions (applies to that one load).
if CloneG9AutoRun != false do
(
    local ok = CloneG9.convertScene()
    local warned = false
    for l in CloneG9.report where matchPattern l pattern:"WARNING*" or matchPattern l pattern:"ERROR*" do warned = true
    local status = if not ok and CloneG9.report.count > 0 then ("Genesis 9 -> Biped: " + CloneG9.report[CloneG9.report.count]) \
        else if warned then "Genesis 9 -> Biped done WITH WARNINGS, see the MAXScript Listener (Edit > Fetch undoes)." \
        else "Genesis 9 -> Biped done (Edit > Fetch undoes). Report in the MAXScript Listener."
    displayTempPrompt status 8000
)
CloneG9AutoRun = undefined
