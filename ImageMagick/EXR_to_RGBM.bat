@echo off
setlocal enabledelayedexpansion

:: EXR to RGBM Converter v1.1
:: Converts HDR EXR files to RGBM-encoded PNG
:: Applies gamma 0.4545 (linear to sRGB) before encoding
:: MaxRange = 8 (can store values up to 8.0)
::
:: Usage: Drag EXR file or folder onto this batch file

set "input=%~1"
set "MAXRANGE=8"
set "GAMMA=0.4545"

if "%input%"=="" (
    set /p "input=Enter EXR file or folder path: "
)

if not exist "%input%" (
    echo Input not found: %input%
    pause
    exit /b 1
)

:: Check if input is a file or folder
if exist "%input%\*" (
    :: It's a folder
    for %%f in ("%input%\*.exr") do (
        call :ConvertFile "%%f"
    )
) else (
    :: Single file
    call :ConvertFile "%input%"
)

echo.
echo Done!
pause
exit /b 0

:ConvertFile
set "inputFile=%~1"
set "outputFile=%~dpn1_rgbm.png"
set "tempDir=%TEMP%\rgbm_%RANDOM%"

echo Converting: %~nx1

mkdir "%tempDir%" 2>nul

:: Step 1: Apply gamma correction (linear to sRGB)
magick "%inputFile%" -gamma %GAMMA% "%tempDir%\gamma.exr"

:: Step 2: Get max of RGB channels
magick "%tempDir%\gamma.exr" -channel RGB -separate -evaluate-sequence Max "%tempDir%\max.exr"

:: Step 3: Create M channel (max / MaxRange, clamped to 0-1)
magick "%tempDir%\max.exr" -evaluate Divide %MAXRANGE% -evaluate Min 1 -clamp "%tempDir%\m.exr"

:: Step 4: Create divisor = M * MaxRange, with minimum to avoid div by zero
magick "%tempDir%\m.exr" -evaluate Multiply %MAXRANGE% -evaluate Max 0.00001 "%tempDir%\divisor.exr"

:: Step 5: Divide RGB by divisor
magick "%tempDir%\gamma.exr" "%tempDir%\divisor.exr" -compose DivideSrc -composite -clamp "%tempDir%\rgb.png"

:: Step 6: Combine RGB with M as alpha channel
magick "%tempDir%\rgb.png" "%tempDir%\m.exr" -alpha off -compose CopyOpacity -composite "%outputFile%"

:: Cleanup temp files
rmdir /s /q "%tempDir%" 2>nul

echo Saved: %outputFile%
echo.
goto :eof
