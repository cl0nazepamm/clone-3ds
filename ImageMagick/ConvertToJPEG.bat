@echo off
setlocal enabledelayedexpansion

:: Image to JPEG Converter v1.1
:: Converts images to optimized JPEG with no visible quality loss
:: Optional resize by max dimension or percentage
::
:: Usage:
::   Drag image/folder onto batch file (no resize)
::   Or run from command line: ConvertToJPEG.bat "path" [maxSize or percent%]
::   Examples:
::     ConvertToJPEG.bat "C:\images" 2048      (max 2048px on longest side)
::     ConvertToJPEG.bat "C:\images" 50%       (resize to 50 percent)
::     ConvertToJPEG.bat "C:\images"           (no resize)

set "input=%~1"
set "resizeParam=%~2"
set "QUALITY=92"

if "%input%"=="" (
    set /p "input=Enter image file or folder path: "
    set /p "resizeParam=Resize (max pixels, or percent like 50%%, or leave empty): "
)

if not exist "%input%" (
    echo Input not found: %input%
    pause
    exit /b 1
)

:: Determine resize command
set "RESIZE_CMD="
if not "%resizeParam%"=="" (
    echo %resizeParam% | findstr /C:"%" >nul
    if !errorlevel!==0 (
        :: Percentage resize
        set "RESIZE_CMD=-resize %resizeParam%"
        echo Resize: %resizeParam%
    ) else (
        :: Max dimension resize (maintains aspect ratio)
        set "RESIZE_CMD=-resize %resizeParam%x%resizeParam%^>"
        echo Resize: max %resizeParam%px
    )
) else (
    echo Resize: none
)
echo.

:: Check if input is a file or folder
if exist "%input%\*" (
    :: It's a folder - process common image formats
    for %%f in ("%input%\*.png" "%input%\*.tga" "%input%\*.tif" "%input%\*.tiff" "%input%\*.bmp" "%input%\*.webp" "%input%\*.exr" "%input%\*.hdr") do (
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
set "outputFile=%~dpn1.jpg"

:: Skip if already a jpeg
if /i "%~x1"==".jpg" goto :eof
if /i "%~x1"==".jpeg" goto :eof

echo Converting: %~nx1
magick "%inputFile%" %RESIZE_CMD% -quality %QUALITY% -sampling-factor 4:2:0 -strip -interlace Plane "%outputFile%"

if %errorlevel%==0 (
    echo Saved: %outputFile%
) else (
    echo Error converting %~nx1
)
echo.
goto :eof
