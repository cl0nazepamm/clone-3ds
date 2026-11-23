# CloneTools-ImageMagick

A collection of batch scripts and Python tools for image processing, optimized for game development and 3D workflows.

## Requirements

- [ImageMagick](https://imagemagick.org/) installed and available in PATH
- Python 3.x (for Python scripts)
- PIL/Pillow (for Python scripts): `pip install Pillow`

## Scripts

### Batch Converters

| Script | Description |
|--------|-------------|
| `ConvertToJPEG.bat` | Converts images (PNG, TGA, TIF, BMP, WebP, EXR, HDR) to optimized JPEG. Supports optional resize by max dimension or percentage. |
| `EXR_to_HDR.bat` | Converts EXR files to Radiance HDR format. |
| `EXR_to_RGBM.bat` | Converts EXR files to RGBM encoded format (for mobile/web HDR). |
| `CombineMapsAdditive.bat` | Combines texture maps additively (useful for combining masks). |

### Cubemap_Maker

Python tool for creating cubemaps from panoramic images.

**Usage:**
```bash
cd Cubemap_Maker
python make_cubemap.py input_panorama.hdr
```

Or use the batch launcher:
```bash
run_cubemap.bat
```

### ImageQuickResize

Python tool for batch resizing texture bakes.

**Usage:**
```bash
cd ImageQuickResize
python convert_bakes.py
```

Or use the batch launcher:
```bash
run_convert.bat
```

## Usage Examples

### Convert folder of images to JPEG
```bash
# Drag folder onto ConvertToJPEG.bat
# Or from command line:
ConvertToJPEG.bat "C:\textures"
```

### Convert with resize
```bash
# Resize to max 2048px on longest side
ConvertToJPEG.bat "C:\textures" 2048

# Resize to 50%
ConvertToJPEG.bat "C:\textures" 50%
```

### Convert EXR to HDR
```bash
# Drag EXR file or folder onto EXR_to_HDR.bat
EXR_to_HDR.bat "C:\hdri\environment.exr"
```

## Installation

1. Ensure ImageMagick is installed and `magick` command is available in PATH
2. For Python scripts, install dependencies:
   ```bash
   pip install Pillow numpy
   ```
3. Place scripts in a convenient location or add to PATH

## License

MIT License

## Author

Clone
