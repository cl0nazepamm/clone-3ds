@echo off
setlocal enabledelayedexpansion

:: CombineMapsAdditive v1.0
:: Combines all images in a folder using additive blending (ImageMagick)
:: Usage: Drag folder onto this batch file, or run and enter path

set "inputFolder=%~1"

if "%inputFolder%"=="" (
    set /p "inputFolder=Enter folder path: "
)

if not exist "%inputFolder%" (
    echo Folder not found: %inputFolder%
    pause
    exit /b 1
)

:: Output file
set "outputFile=%inputFolder%\combined_additive.png"

:: Build list of image files
set "fileList="
set "count=0"

for %%f in ("%inputFolder%\*.png" "%inputFolder%\*.jpg" "%inputFolder%\*.jpeg" "%inputFolder%\*.tga" "%inputFolder%\*.tif" "%inputFolder%\*.exr" "%inputFolder%\*.bmp") do (
    :: Skip the output file if it exists
    if /i not "%%~nxf"=="combined_additive.png" (
        set /a count+=1
        set "fileList=!fileList! "%%f""
    )
)

if %count%==0 (
    echo No image files found in folder.
    pause
    exit /b 1
)

echo Found %count% images to combine...
echo Output: %outputFile%
echo.

:: Use ImageMagick to combine additively
:: First image as base, then composite each additional image with -compose plus
magick %fileList% -background black -compose plus -flatten "%outputFile%"

if %errorlevel%==0 (
    echo.
    echo Successfully combined %count% images additively.
    echo Output saved to: %outputFile%
) else (
    echo.
    echo Error occurred during image processing.
    echo Make sure ImageMagick is installed and in PATH.
)

pause
