import os
import subprocess
import sys

def convert_images():
    # settings
    resize_factor = "50%"
    quality = "90" # High quality to ensure no visible loss
    output_dir = "optimized_bakes"

    # Create output directory if it doesn't exist
    if not os.path.exists(output_dir):
        os.makedirs(output_dir)

    # Get all png files in current directory
    files = [f for f in os.listdir('.') if f.lower().endswith('.png')]

    if not files:
        print("No PNG files found in the current directory.")
        return

    print(f"Found {len(files)} files. Starting conversion...")

    for filename in files:
        name_without_ext = os.path.splitext(filename)[0]
        output_filename = f"{name_without_ext}.jpg"
        output_path = os.path.join(output_dir, output_filename)
        
        # ImageMagick command
        # using 'magick' command (v7+)
        cmd = [
            "magick",
            filename,
            "-quality", quality,
            output_path
        ]

        try:
            print(f"Converting: {filename} -> {output_path}")
            subprocess.run(cmd, check=True)
        except subprocess.CalledProcessError as e:
            print(f"Error converting {filename}: {e}")
        except FileNotFoundError:
            print("Error: 'magick' command not found. Please ensure ImageMagick is installed and in your PATH.")
            return

    print("\nConversion complete!")
    print(f"Optimized files are in the '{output_dir}' folder.")

if __name__ == "__main__":
    convert_images()
