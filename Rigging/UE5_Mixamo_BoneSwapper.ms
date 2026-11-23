try(destroyDialog ro_PureRenamer)catch()
(
try(if CloneUI == undefined do fileIn ((getDir #userScripts) + "\\CloneTools\\CloneUI.ms"))catch(try(fileIn ((getFilenamePath (getSourceFileName())) + "..\\Utilities\\CloneUI.ms"))catch())

global CloneMixamoRenameForm
try(CloneMixamoRenameForm.Close())catch()
try(CloneMixamoRenameForm.Dispose())catch()
CloneMixamoRenameForm = dotNetObject "System.Windows.Forms.Form"

-- DATA MAPPING: #("UE5_Name", "Mixamo_Name")
global CloneMixamoBoneMap = #(
    #("pelvis", "mixamorig:Hips"), #("spine_01", "mixamorig:Spine"), #("spine_02", "mixamorig:Spine1"), #("spine_03", "mixamorig:Spine2"),
    #("neck_01", "mixamorig:Neck"), #("head", "mixamorig:Head"),
    #("thigh_l", "mixamorig:LeftUpLeg"), #("calf_l", "mixamorig:LeftLeg"), #("foot_l", "mixamorig:LeftFoot"), #("ball_l", "mixamorig:LeftToeBase"),
    #("thigh_r", "mixamorig:RightUpLeg"), #("calf_r", "mixamorig:RightLeg"), #("foot_r", "mixamorig:RightFoot"), #("ball_r", "mixamorig:RightToeBase"),
    #("clavicle_l", "mixamorig:LeftShoulder"), #("upperarm_l", "mixamorig:LeftArm"), #("lowerarm_l", "mixamorig:LeftForeArm"), #("hand_l", "mixamorig:LeftHand"),
    #("clavicle_r", "mixamorig:RightShoulder"), #("upperarm_r", "mixamorig:RightArm"), #("lowerarm_r", "mixamorig:RightForeArm"), #("hand_r", "mixamorig:RightHand"),
    #("thumb_01_l", "mixamorig:LeftHandThumb1"), #("thumb_02_l", "mixamorig:LeftHandThumb2"), #("thumb_03_l", "mixamorig:LeftHandThumb3"),
    #("index_01_l", "mixamorig:LeftHandIndex1"), #("index_02_l", "mixamorig:LeftHandIndex2"), #("index_03_l", "mixamorig:LeftHandIndex3"),
    #("middle_01_l", "mixamorig:LeftHandMiddle1"), #("middle_02_l", "mixamorig:LeftHandMiddle2"), #("middle_03_l", "mixamorig:LeftHandMiddle3"),
    #("ring_01_l", "mixamorig:LeftHandRing1"), #("ring_02_l", "mixamorig:LeftHandRing2"), #("ring_03_l", "mixamorig:LeftHandRing3"),
    #("pinky_01_l", "mixamorig:LeftHandPinky1"), #("pinky_02_l", "mixamorig:LeftHandPinky2"), #("pinky_03_l", "mixamorig:LeftHandPinky3"),
    #("thumb_01_r", "mixamorig:RightHandThumb1"), #("thumb_02_r", "mixamorig:RightHandThumb2"), #("thumb_03_r", "mixamorig:RightHandThumb3"),
    #("index_01_r", "mixamorig:RightHandIndex1"), #("index_02_r", "mixamorig:RightHandIndex2"), #("index_03_r", "mixamorig:RightHandIndex3"),
    #("middle_01_r", "mixamorig:RightHandMiddle1"), #("middle_02_r", "mixamorig:RightHandMiddle2"), #("middle_03_r", "mixamorig:RightHandMiddle3"),
    #("ring_01_r", "mixamorig:RightHandRing1"), #("ring_02_r", "mixamorig:RightHandRing2"), #("ring_03_r", "mixamorig:RightHandRing3"),
    #("pinky_01_r", "mixamorig:RightHandPinky1"), #("pinky_02_r", "mixamorig:RightHandPinky2"), #("pinky_03_r", "mixamorig:RightHandPinky3")
)

local frm = CloneUI.skinForm CloneMixamoRenameForm "UE5 Mixamo Renamer" 340 330
local shell = CloneUI.addShell frm "UE5 / Mixamo Renamer" version:"v1.0"
local pad = shell[1]
local iW = shell[2]
local Y = shell[3]

local hint = CloneUI.mkLabel "Swaps names between UE5 and Mixamo formats. Hierarchy is not changed." pad Y iW 34 fObj:CloneUI.fSmall cObj:CloneUI.cDim
frm.controls.add hint
Y += 46

local btnSwap = CloneUI.mkBtn "Swap Names" pad Y iW 34
frm.controls.add btnSwap
Y += 50

local credit = CloneUI.mkLabel "clone" 0 Y 340 16 fObj:CloneUI.fSmall cObj:(CloneUI.clr.FromArgb 55 55 55)
credit.TextAlign = CloneUI.alC.MiddleCenter
frm.controls.add credit
frm.Size = dotNetObject CloneUI.szC 340 (Y + 24)

fn CloneMixamoSwapNames =
(
    local count = 0
    undo "Bone Rename" on
    (
        for o in objects do
        (
            local renamed = false
            for pair in CloneMixamoBoneMap where not renamed do
            (
                if o.name == pair[1] then
                (
                    o.name = pair[2]
                    renamed = true
                    count += 1
                )
                else if o.name == pair[2] then
                (
                    o.name = pair[1]
                    renamed = true
                    count += 1
                )
            )
        )
    )
    format "Swapped names for % bones.\n" count
)

fn onCloneMixamoSwap s e = CloneMixamoSwapNames()
dotNet.addEventHandler btnSwap "Click" onCloneMixamoSwap
append CloneUI_handlers onCloneMixamoSwap
frm.Show()
)
