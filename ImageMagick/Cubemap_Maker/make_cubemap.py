#!/usr/bin/env python3
"""
Cubemap Generator - Creates a horizontal cross cubemap from 6 face images.

Usage:
    python make_cubemap.py [input_directory] [output_filename]

Arguments:
    input_directory  - Directory containing face images (default: dialog or current directory)
    output_filename  - Output filename (default: cubemap_cross.png)

Expected face images: front, back, left, right, top, bottom (case-insensitive, fuzzy match supported)
"""

import sys
import os
from pathlib import Path

# Wrap imports in try/except to prevent immediate crash (flashing window) on missing dependencies
try:
    from PIL import Image
except ImportError:
    print("\nCRITICAL ERROR: 'Pillow' library not found.")
    print("Please install it by running: pip install Pillow")
    print("\nPress Enter to exit...")
    input()
    sys.exit(1)

# Try to import tkinter for folder selection dialog
try:
    import tkinter as tk
    from tkinter import filedialog
    HAS_TKINTER = True
except ImportError:
    HAS_TKINTER = False


def find_image_file(directory: Path, face_name: str) -> Path:
    """
    Find an image file for a given face name (e.g., 'front').
    Priorities:
    1. Exact match (e.g., 'front.png', 'front.jpg')
    2. Filename contains the face name (e.g., 'my_front_view.png')
    """
    valid_extensions = {".png", ".jpg", ".jpeg", ".tga", ".bmp", ".tif", ".tiff"}
    
    # 1. Look for exact matches first
    for ext in valid_extensions:
        exact_path = directory / f"{face_name}{ext}"
        if exact_path.exists():
            return exact_path

    # 2. Look for fuzzy matches (file contains face name)
    # Get all files with valid extensions
    files = [f for f in directory.iterdir() if f.suffix.lower() in valid_extensions and f.is_file()]
    
    candidates = []
    for f in files:
        if face_name.lower() in f.stem.lower():
            candidates.append(f)
    
    if len(candidates) == 1:
        return candidates[0]
    elif len(candidates) > 1:
        # If multiple matches, try to be smarter or just warn
        print(f"Warning: Multiple files match '{face_name}': {[f.name for f in candidates]}. Using '{candidates[0].name}'.")
        return candidates[0]

    raise FileNotFoundError(f"Could not find image for '{face_name}' in {directory}")


def create_cubemap(input_dir: Path, output_name: str = "cubemap_cross.png") -> Path:
    """Create a horizontal cross cubemap from 6 face images."""

    faces = ["front", "back", "left", "right", "top", "bottom"]
    images = {}

    print(f"Scanning directory: {input_dir}")

    # Load all face images
    for face in faces:
        try:
            face_path = find_image_file(input_dir, face)
            images[face] = Image.open(face_path)
            print(f"Loaded ({face}): {face_path.name} ({images[face].size[0]}x{images[face].size[1]})")
        except FileNotFoundError as e:
            raise FileNotFoundError(f"Missing face image for '{face}'. Ensure a file named '{face}' or containing '{face}' exists.") from e

    # Get face size (assume all faces are the same size)
    face_size = images["front"].size[0]

    # Verify all faces are square and same size
    for face, img in images.items():
        if img.size[0] != img.size[1]:
            raise ValueError(f"{face} image is not square: {img.size}")
        if img.size[0] != face_size:
            raise ValueError(f"{face} size {img.size[0]} doesn't match expected {face_size}")

    # Create horizontal cross layout (4 wide x 3 tall)
    # Layout:
    #        [top]
    # [left] [front] [right] [back]
    #        [bottom]

    canvas_width = face_size * 4
    canvas_height = face_size * 3

    # Create canvas with black background
    cubemap = Image.new("RGBA", (canvas_width, canvas_height), (0, 0, 0, 255))

    # Position mapping (column, row) for each face
    positions = {
        "top":    (1, 0),
        "left":   (0, 1),
        "front":  (1, 1),
        "right":  (2, 1),
        "back":   (3, 1),
        "bottom": (1, 2),
    }

    # Paste each face
    for face, (col, row) in positions.items():
        x = col * face_size
        y = row * face_size
        # Convert to RGBA if needed
        img = images[face].convert("RGBA")
        cubemap.paste(img, (x, y))
        
    # Save output
    output_path = input_dir / output_name
    cubemap.save(output_path, "PNG")
    print(f"\nCubemap saved: {output_path}")
    print(f"Size: {canvas_width}x{canvas_height}")

    return output_path


def select_directory():
    """Open a GUI dialog to select a directory."""
    if HAS_TKINTER:
        root = tk.Tk()
        root.withdraw()  # Hide the main window
        print("Opening folder selection dialog...")
        folder_selected = filedialog.askdirectory(title="Select Folder Containing Face Images")
        root.destroy()
        if folder_selected:
            return Path(folder_selected)
    return None


def main():
    # Parse arguments
    input_dir = None
    output_name = "cubemap_cross.png"

    if len(sys.argv) > 1:
        input_dir = Path(sys.argv[1])
        if len(sys.argv) > 2:
            output_name = sys.argv[2]
    else:
        # No arguments provided, try interactive mode
        print("No input directory provided.")
        input_dir = select_directory()
        
        if not input_dir:
            user_input = input("Enter path to image directory (or press Enter for current): ").strip()
            if user_input:
                input_dir = Path(user_input.strip('"').strip("'"))
            else:
                input_dir = Path.cwd()

    if not input_dir.exists():
        print(f"Error: Directory not found: {input_dir}")
        input("\nPress Enter to exit...")
        sys.exit(1)

    print("-" * 40)

    try:
        create_cubemap(input_dir, output_name)
        print("\nSuccess!")
    except Exception as e:
        print(f"\nError: {e}")
        input("\nPress Enter to exit...")
        sys.exit(1)

    # Keep window open
    if len(sys.argv) == 1:
        input("\nPress Enter to exit...")


if __name__ == "__main__":
    main()
