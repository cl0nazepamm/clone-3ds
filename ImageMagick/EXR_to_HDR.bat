@echo off
setlocal enabledelayedexpansion

:: EXR to HDR Converter v1.0
:: Converts EXR files to Radiance HDR format
::
:: Usage: Drag EXR file or folder onto this batch file

set "input=%~1"

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
set "outputFile=%~dpn1.hdr"

echo Converting: %~nx1
magick "%inputFile%" "%outputFile%"

if %errorlevel%==0 (
    echo Saved: %outputFile%
) else (
    echo Error converting %~nx1
)
echo.
goto :eof
