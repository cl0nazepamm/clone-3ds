-- Creates a Biped from a Character Creator rig (CC_Base_*) and drives the CC bones with it.
-- Drag onto a viewport: runs the Character Creator preset of Clone_UE_To_BIPED.ms (same folder),
-- which fits the Biped from the joint positions and reports offsets and bind drift in the Listener.
-- For Unreal skeletons use Clone_UE_To_BIPED.ms.

global CloneBipedRemapper
global CloneBipedRemapperAutoRun
global CloneBipedRemapperOpenUI

(
    local here = try (getFilenamePath (getSourceFileName())) catch ""
    local candidates = #(here + "Clone_UE_To_BIPED.ms", (getDir #userScripts) + "\\CloneTools\\Clone_UE_To_BIPED.ms")
    local engine = undefined
    for c in candidates where engine == undefined and doesFileExist c do engine = c

    if engine == undefined then
    (
        messageBox "Clone_UE_To_BIPED.ms not found next to clone_cc_to_biped.ms." title:"CC to Biped"
    )
    else
    (
        local prevAutoRun = CloneBipedRemapperAutoRun
        local prevOpenUI = CloneBipedRemapperOpenUI
        CloneBipedRemapperAutoRun = false
        CloneBipedRemapperOpenUI = false
        fileIn engine
        CloneBipedRemapperAutoRun = prevAutoRun
        CloneBipedRemapperOpenUI = prevOpenUI

        local ok = CloneBipedRemapper.run (CloneBipedRemapper.makeCCPreset())
        displayTempPrompt (if ok == true then "CC -> Biped done (Edit > Fetch undoes). Report in the MAXScript Listener." else "CC -> Biped failed, see the MAXScript Listener.") 8000
    )
)
