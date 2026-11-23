$Factor = 25
$OutDir = "$PSScriptRoot\resized"

if (!(Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }

Get-ChildItem -Path $PSScriptRoot -Filter "*.tif" | ForEach-Object {
    $OutFile = "$OutDir\$($_.Name)"
    if (Test-Path $OutFile) {
        Write-Host "Skipping: $($_.Name) (already exists)"
        return
    }
    Write-Host "Resizing: $($_.Name) ($Factor%)"
    magick $_.FullName -resize "$Factor%" $OutFile
}

Write-Host "Done. Resized images saved to $OutDir\"
