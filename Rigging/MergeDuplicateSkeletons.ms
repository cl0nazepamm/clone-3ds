/*
    MergeDuplicateSkeletons.ms
    --------------------------
    Merges duplicate skeleton copies into one master rig.

    Common layouts:
      - glTF / modular rigs: parentless "root" + copies under Rig.001_*
      - DAZ Genesis: "Genesis9" with a child "hip" skeleton per mesh

    Usage:
        fileIn (pathConfig.appendPath (getDir #userScripts) "CloneTools\\Rigging\\MergeDuplicateSkeletons.ms")
        mergeDuplicateSkeletons()

    Genesis shortcut:
        mergeGenesisSkeletons()
*/

global MergeDuplicateSkeletons

struct MergeDuplicateSkeletons (
    skeletonRootName = "root",
    useParentlessMaster = true,
    masterFigureName = "Genesis9",
    rigContainerPattern = "Rig.001_*",
    gltfRootName = "glTF_root",
    referenceMeshName = "Body01.003",
    saveHold = true,
    maxReplacePasses = 8,
    verbose = true,

    fn log msg = (
        if verbose do format "%\n" msg
    ),

    fn findBoneByName root boneName = (
        if root == undefined then return undefined
        if root.name == boneName then return root
        for c in root.children do (
            local found = findBoneByName c boneName
            if found != undefined then return found
        )
        undefined
    ),

    fn collectBones root = (
        local bones = #()
        if root != undefined do (
            append bones root
            for c in root.children do join bones (collectBones c)
        )
        bones
    ),

    fn isUnderMaster node masterSkeletonRoot = (
        while node != undefined do (
            if node == masterSkeletonRoot then return true
            node = node.parent
        )
        false
    ),

    fn getSkinMod obj = (
        local skinMod = undefined
        for m in obj.modifiers where classOf m == Skin do skinMod = m
        skinMod
    ),

    fn getSkinnedMeshes = (
        local meshes = #()
        for obj in objects do (
            if getSkinMod obj != undefined do append meshes obj
        )
        meshes
    ),

    fn getPreserveNames = (
        local names = #()
        for obj in objects where obj.parent == undefined do append names obj.name
        for obj in objects where matchPattern obj.name pattern:rigContainerPattern do (
            if findItem names obj.name == 0 do append names obj.name
        )
        names
    ),

    armBranchRoots = #("shoulder.r", "shoulder.l"),

    fn alignBranch masterStart dupStart = (
        if masterStart == undefined or dupStart == undefined then return 0

        local aligned = 1
        dupStart.pos = masterStart.pos
        dupStart.rotation = masterStart.rotation
        dupStart.scale = masterStart.scale

        for mc in masterStart.children do (
            for dc in dupStart.children where dc.name == mc.name do (
                aligned += alignBranch mc dc
            )
        )
        aligned
    ),

    fn moveDuplicateRootsToMaster masterSkeletonRoot = (
        local moved = 0
        for dupRoot in objects where dupRoot.name == skeletonRootName and classOf dupRoot == Dummy do (
            if dupRoot == masterSkeletonRoot do continue
            at time 0 with animate off (
                dupRoot.transform = masterSkeletonRoot.transform
            )
            moved += 1
        )
        moved
    ),

    fn alignDuplicateSkeletonsToMaster masterSkeletonRoot = (
        local aligned = 0
        for dupRoot in objects where dupRoot.name == skeletonRootName and classOf dupRoot == Dummy do (
            if dupRoot == masterSkeletonRoot do continue
            for branchName in armBranchRoots do (
                aligned += alignBranch \
                    (findBoneByName masterSkeletonRoot branchName) \
                    (findBoneByName dupRoot branchName)
            )
        )
        aligned
    ),

    fn getMasterSkeletonRoot = (
        if useParentlessMaster do (
            for obj in objects where obj.name == skeletonRootName and classOf obj == Dummy do (
                if obj.parent == undefined then return obj
            )
            throw ("Parentless skeleton root not found: " + skeletonRootName)
        )

        local masterFigure = getNodeByName masterFigureName
        if masterFigure == undefined do throw ("Master figure not found: " + masterFigureName)

        local skeletonRoot = undefined
        for c in masterFigure.children where c.name == skeletonRootName and classOf c == Dummy do (
            skeletonRoot = c
        )
        if skeletonRoot == undefined do (
            throw ("Skeleton root '" + skeletonRootName + "' not found under " + masterFigureName)
        )
        skeletonRoot
    ),

    fn replaceSkinBones skinMod masterSkeletonRoot = (
        local replaced = 0
        local boneCount = skinOps.GetNumberBones skinMod
        for i = 1 to boneCount do (
            local oldBone = skinOps.GetBoneNode skinMod i
            if oldBone != undefined do (
                local masterBone = findBoneByName masterSkeletonRoot oldBone.name
                if masterBone != undefined and masterBone != oldBone do (
                    skinOps.ReplaceBone skinMod oldBone masterBone
                    replaced += 1
                )
            )
        )
        replaced
    ),

    fn reparentOffMasterBones masterSkeletonRoot masterSet = (
        local reparented = 0
        local seen = #()
        for obj in getSkinnedMeshes() do (
            local skinMod = getSkinMod obj
            if skinMod == undefined do continue
            for i = 1 to (skinOps.GetNumberBones skinMod) do (
                local boneNode = skinOps.GetBoneNode skinMod i
                if boneNode == undefined do continue
                if findItem masterSet boneNode > 0 do continue
                if findItem seen boneNode > 0 do continue
                append seen boneNode

                local parentName = if boneNode.parent != undefined then boneNode.parent.name else undefined
                if parentName != undefined do (
                    local masterParent = findBoneByName masterSkeletonRoot parentName
                    if masterParent != undefined and masterParent != boneNode.parent do (
                        boneNode.parent = masterParent
                        reparented += 1
                    )
                )
            )
        )
        reparented
    ),

    fn countOffMasterBones masterSet = (
        local report = #()
        for obj in getSkinnedMeshes() do (
            local skinMod = getSkinMod obj
            if skinMod == undefined do continue
            local offMaster = 0
            for i = 1 to (skinOps.GetNumberBones skinMod) do (
                local boneNode = skinOps.GetBoneNode skinMod i
                if findItem masterSet boneNode == 0 do offMaster += 1
            )
            if offMaster > 0 do append report #(obj.name, offMaster)
        )
        report
    ),

    fn deleteDuplicateSkeletonRoots masterSkeletonRoot = (
        local deleted = 0
        local rootsToDelete = #()
        for obj in objects where obj.name == skeletonRootName and classOf obj == Dummy do (
            if obj != masterSkeletonRoot do append rootsToDelete obj
        )
        for skeletonRoot in rootsToDelete do (
            delete skeletonRoot
            deleted += 1
        )
        deleted
    ),

    fn deleteOrphanBones masterSkeletonRoot preserveNames = (
        local deleted = 0
        local toDelete = #()
        for obj in objects where classOf obj == Dummy do (
            local keep = isUnderMaster obj masterSkeletonRoot
            if not keep do (
                for preserveName in preserveNames where obj.name == preserveName do keep = true
            )
            if not keep do append toDelete obj
        )
        for d in toDelete do (
            delete d
            deleted += 1
        )
        deleted
    ),

    fn run = (
        local masterSkeletonRoot = getMasterSkeletonRoot()
        if saveHold do holdMaxFile()

        local totalReplaced = 0
        local totalReparented = 0
        local movedRoots = 0
        local alignedBones = 0

        undo "Merge Duplicate Skeletons" on (
            local skinnedMeshes = getSkinnedMeshes()
            if skinnedMeshes.count == 0 do throw "No skinned meshes found in the scene."

            movedRoots = moveDuplicateRootsToMaster masterSkeletonRoot
            alignedBones = alignDuplicateSkeletonsToMaster masterSkeletonRoot
            log ("Moved duplicate roots to master: " + movedRoots as string)
            log ("Aligned arm bones to master T-pose: " + alignedBones as string)

            for pass = 1 to maxReplacePasses do (
                local passReplaced = 0
                local passReparented = 0
                local masterSet = collectBones masterSkeletonRoot

                for mesh in skinnedMeshes do (
                    local skinMod = getSkinMod mesh
                    if skinMod == undefined do continue
                    passReplaced += replaceSkinBones skinMod masterSkeletonRoot
                )

                masterSet = collectBones masterSkeletonRoot
                passReparented = reparentOffMasterBones masterSkeletonRoot masterSet

                totalReplaced += passReplaced
                totalReparented += passReparented
                log ("Pass " + pass as string + ": replaced=" + passReplaced as string + ", reparented=" + passReparented as string)

                if passReplaced == 0 and passReparented == 0 do exit
            )

            local preserveNames = getPreserveNames()
            local deletedRoots = deleteDuplicateSkeletonRoots masterSkeletonRoot
            local deletedOrphans = deleteOrphanBones masterSkeletonRoot preserveNames

            local finalMasterSet = collectBones masterSkeletonRoot
            local remaining = countOffMasterBones finalMasterSet

            local masterLabel = if useParentlessMaster then (
                "parentless " + skeletonRootName
            ) else (
                masterFigureName + "/" + skeletonRootName
            )

            local summary = ""
            summary += "Merged duplicate skeletons into " + masterLabel + "\n\n"
            summary += "Skinned meshes: " + skinnedMeshes.count as string + "\n"
            summary += "Duplicate roots moved to master: " + movedRoots as string + "\n"
            summary += "Arm bones aligned to T-pose: " + alignedBones as string + "\n"
            summary += "Master bones: " + finalMasterSet.count as string + "\n"
            summary += "Skin bone replacements: " + totalReplaced as string + "\n"
            summary += "Extra bones reparented: " + totalReparented as string + "\n"
            summary += "Duplicate skeleton roots deleted: " + deletedRoots as string + "\n"
            summary += "Orphan bones deleted: " + deletedOrphans as string + "\n"

            if remaining.count == 0 then (
                summary += "\nAll skinned meshes now use the unified skeleton."
            ) else (
                summary += "\nWarning: some meshes still have off-master bones:\n"
                for item in remaining do (
                    summary += "  " + item[1] + ": " + item[2] as string + "\n"
                )
            )

            log summary
            summary
        )
    )
)

fn mergeDuplicateSkeletons \
    skeletonRootName:"root" \
    useParentlessMaster:true \
    masterFigureName:"Genesis9" \
    rigContainerPattern:"Rig.001_*" \
    saveHold:true \
    verbose:true = (
    local merger = MergeDuplicateSkeletons \
        skeletonRootName:skeletonRootName \
        useParentlessMaster:useParentlessMaster \
        masterFigureName:masterFigureName \
        rigContainerPattern:rigContainerPattern \
        saveHold:saveHold \
        verbose:verbose
    local summary = merger.run()
    messageBox summary title:"Merge Duplicate Skeletons"
    summary
)

fn mergeGenesisSkeletons saveHold:true verbose:true = (
    mergeDuplicateSkeletons \
        skeletonRootName:"hip" \
        useParentlessMaster:false \
        masterFigureName:"Genesis9" \
        rigContainerPattern:"*" \
        saveHold:saveHold \
        verbose:verbose
)

rollout mergeDuplicateSkeletonsRollout "Merge Duplicate Skeletons" width:340 (
    label lblInfo "Merge duplicate skeleton copies into one master rig." align:#left

    radiobuttons radMode labels:#("Parentless root (glTF)", "Figure child bone (Genesis)") default:1 columns:1 align:#left

    edittext edtSkeletonRoot "Skeleton root name:" text:"root"
    edittext edtMasterFigure "Master figure name:" text:"Genesis9" enabled:false
    edittext edtRigPattern "Rig container pattern:" text:"Rig.001_*"
    checkbox chkHold "Save Hold before merge" checked:true

    button btnRun "Merge Skeletons" width:320 height:32

    on radMode changed state do (
        case state of (
            1: (
                edtSkeletonRoot.text = "root"
                edtMasterFigure.enabled = false
                edtRigPattern.enabled = true
            )
            2: (
                edtSkeletonRoot.text = "hip"
                edtMasterFigure.enabled = true
                edtRigPattern.enabled = false
            )
        )
    )

    on btnRun pressed do (
        try (
            if radMode.state == 1 then (
                mergeDuplicateSkeletons \
                    skeletonRootName:edtSkeletonRoot.text \
                    useParentlessMaster:true \
                    rigContainerPattern:edtRigPattern.text \
                    saveHold:chkHold.checked
            ) else (
                mergeDuplicateSkeletons \
                    skeletonRootName:edtSkeletonRoot.text \
                    useParentlessMaster:false \
                    masterFigureName:edtMasterFigure.text \
                    saveHold:chkHold.checked
            )
        ) catch (
            messageBox (getCurrentException()) title:"Merge Duplicate Skeletons"
        )
    )
)

fn mergeDuplicateSkeletonsUI = (
    try destroyDialog mergeDuplicateSkeletonsRollout catch ()
    createDialog mergeDuplicateSkeletonsRollout
)

fn mergeGenesisSkeletonsUI = mergeDuplicateSkeletonsUI()

/*
    glTF / Rig.001 layout:
        mergeDuplicateSkeletons()

    DAZ Genesis:
        mergeGenesisSkeletons()

    UI:
        mergeDuplicateSkeletonsUI()
*/
