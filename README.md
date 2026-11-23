# CloneTools for 3ds Max

![Clone Logo](images/Logo.png)

Small 3ds Max scripts and macros for material work, rigging fixes, viewport utilities, and day-to-day scene cleanup.

## Install

Copy the scripts or macros you want into the matching 3ds Max ENU folders:

```text
%USERPROFILE%\AppData\Local\Autodesk\3dsMax\<version>\ENU\scripts\
%USERPROFILE%\AppData\Local\Autodesk\3dsMax\<version>\ENU\usermacros\
```

Some tools use the shared UI helper:

```text
Utilities\CloneUI.ms
images\Logo.png
```

Keep those available under `scripts\CloneTools\` when deploying the styled tools.

## Materials

- `PowerShader.ms` - Material search, creation, and instancing workflow with drag-to-viewport support.
- `GLTF_Maker.ms` - Builds GLTF/USD Preview Surface materials from texture folders.
- `TextureFolderPalette.ms` - Creates material palettes from texture directories.
- `Offset_Material_IDs.ms` - Offsets material ID values on selected objects.
- `PropagateMaterial.ms` - Converts detached multi-material assignments into direct materials.

## Rigging

- `clone_cc_to_biped.ms` - Drag onto a viewport: fits a Biped to a Reallusion/Character Creator (`CC_Base_*`) rig and drives it. Runs the Character Creator preset of `Clone_UE_To_BIPED.ms`, so keep both files together.
- `Clone_UE_To_BIPED.ms` - UI-driven skeleton-to-Biped remapper with Unreal and Character Creator presets. Fits the Biped from joint positions, constrains the source bones, and reports joint offsets and bind drift in the Listener.
- `UE5_Mixamo_BoneSwapper.ms` - Swaps UE5 and Mixamo bone names.
- `MergeDuplicateSkeletons.ms` - Merges duplicate skeleton copies into one master rig (`root` / `Rig.001_*` or Genesis `hip`).
- `Clone_Genesis9_Importer.ms` - Drag onto a viewport after importing a DAZ Genesis 9 FBX: merges the per-figure skeletons (eyes, mouth, tear, lashes, clothing) into the body, fits a Biped and constrains the Genesis bones to it. Skin weights are untouched.

## Utilities

- `ActivateManualRetopo.mcr` - Enables a selected object as a live retopology surface.
- `autoLogo.ms` - Batch processes SVG logo assets into 3D geometry.
- `Collapse.ms` - Collapses modifier stacks while preserving selected modifiers.
- `CopyUV0toUV1.ms` / `CopyUVChannels.ms` - Copies UV data between channels.
- `CloneTools-InstanceFromFirstKeepMaterials.mcr` - Replaces selected objects with instances of the first selected source while preserving each target material.
- `CloneTools-SendBitmapToVCanvas.mcr` - Sends a bitmap to Viewport Canvas.
- `CloneTools-RotationAxisSnap.mcr` - Blender-style viewport rotation axis snapping.
- `CloneTools-SwapViewports.mcr` - Swaps left and right viewport layouts.
- `ViewportOpacitySlider.ms` / `CloneTools-ViewportOpacitySlider.mcr` - Click-drag viewport opacity control.
- `ViewportTimeSlider.ms` / `CloneTools-ViewportTimeSlider.mcr` - Click-drag timeline scrubbing from the viewport.
- `ToggleTrackView.ms` - Toggles Track View modes.

## SME

- `OSL_SME_DropHandler.ms` - Changes Slate drag/drop texture behavior to OSL Bitmap.
- `SME_RandomizeBitmapNames.ms` - Adds random seed values to bitmap node names.

## Requirements

- Autodesk 3ds Max 2024 or newer.

## License

MIT License
