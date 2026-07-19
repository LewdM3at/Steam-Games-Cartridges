# Steam Game Cartridge Uninstaller

$ErrorActionPreference = "Stop"


Write-Host ""
Write-Host "Uninstalling Steam Game Cartridge launcher..."
Write-Host ""


########################################
# Paths
########################################

$InstallFolder = Join-Path $env:ProgramData "SteamGameCartridge"
$ConfigFolder = Join-Path $env:LOCALAPPDATA "SteamGameCartridge"

$TaskName = "Steam Game Cartridge Monitor"


########################################
# Remove scheduled task
########################################

Write-Host "Removing scheduled task..."


$Task = Get-ScheduledTask `
    -TaskName $TaskName `
    -ErrorAction SilentlyContinue


if ($null -ne $Task) {

    Write-Host "Stopping monitor..."

    Stop-ScheduledTask `
        -TaskName $TaskName `
        -ErrorAction SilentlyContinue


    Unregister-ScheduledTask `
        -TaskName $TaskName `
        -Confirm:$false

}
else {

    Write-Host "Scheduled task not found."

}


########################################
# Remove installed files
########################################

Write-Host "Removing installed files..."


if (Test-Path $InstallFolder) {

    Remove-Item `
        -Path $InstallFolder `
        -Recurse `
        -Force

}
else {

    Write-Host "Install directory not found."

}


########################################
# Remove config and trust data
########################################

Write-Host "Removing config and trust data..."


if (Test-Path $ConfigFolder) {

    Remove-Item `
        -Path $ConfigFolder `
        -Recurse `
        -Force

}
else {

    Write-Host "Config directory not found."

}


########################################
# Done
########################################

Write-Host ""
Write-Host "=========================================="
Write-Host " Steam Game Cartridge removed"
Write-Host "=========================================="
Write-Host ""