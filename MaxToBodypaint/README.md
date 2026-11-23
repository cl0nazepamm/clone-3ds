# MaxToBodypaint

One click in 3ds Max: the selected meshes appear in Cinema 4D R20, ready to paint in BodyPaint.

- The mesh **as it is shown** (skin and modifiers evaluated at the current frame): no skin, bones or
  animation. Polygons (quads, n-gons), UVs (channel 1) and per-face materials exactly as in Max.
- Each material's maps, referenced where they are (textures are never copied):
  - **base colour** (OpenPBR/Physical `base_color_map`, Standard diffuse) → **Luminance** only
    (colour and reflectance off), so it shows flat and unlit
  - **opacity** (OpenPBR `geometry_opacity_map`, Physical `cutout_map`, Standard opacity) →
    **Alpha**; a bitmap set to its alpha output in Max uses Image Alpha. Physical's
    `transparency_map` is glass, not cut-out, so it isn't sent.
  - slots switched off in Max aren't sent.

## Install

- **3ds Max:** drag `MaxToBodypaint.ms` into Max once. The button: Customize > Customize User
  Interface > Category **CloneTools** > **To BodyPaint** (put it on a toolbar or quad menu).
- **Cinema 4D R20:** copy `MaxToBodypaint.pyp` into
  `%APPDATA%\MAXON\Cinema 4D R20_4FA5020E\plugins\MaxToBodypaint\` and restart. The Console
  (Script > Console) shows `MaxToBodypaint: listening for 3ds Max sends in ...`.

## How it works

Max writes `send.obj`, `send.mtl` and, last, `send.json` into `%LOCALAPPDATA%\MaxToBodypaint\`
(overwritten by every send). Cinema 4D checks `send.json` every half second, merges the OBJ into
the open document, sets the materials to Luminance from the paths in `send.json`, selects the new
objects and overwrites `send.json` with `{"done": ...}` so a send is imported once. Results and
errors print to the Console.

- Hidden meshes are skipped.
- Positions come from what Max shows (`snapshotAsMesh`); the topology from a temporary copy
  collapsed to Editable Poly. A collapsed skinned copy alone is wrong: Skin already outputs world
  positions, so an FBX import's Y-up node rotation would be applied twice.
- Max's own OBJ exporter isn't used: it names OpenPBR materials after the wire colour and wrote
  no normals. Its settings (e.g. a ZBrush preset) are never touched. Cinema 4D adds the smoothing
  (Phong) on import.
- The plugin is Python 2.7 / 3 compatible (checked: R20 loads it; the import was tested headless
  with Cinema 4D 2026's `c4dpy`). Plugin ID 1000005 is from Maxon's test range.
