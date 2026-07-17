# Steam Game Cartridge Installer

$ErrorActionPreference = "Stop"


Write-Host ""
Write-Host "Installing Steam Game Cartridge launcher..."
Write-Host ""


########################################
# Paths
########################################

$InstallFolder = Join-Path $env:LOCALAPPDATA "SteamGameCartridge"

$MonitorSource = Join-Path $PSScriptRoot "windows\cartridge-monitoring.ps1"

$MonitorTarget = Join-Path $InstallFolder "cartridge-monitoring.ps1"


########################################
# Check source file
########################################

if (-not (Test-Path $MonitorSource)) {

    Write-Error "Missing file:"
    Write-Error $MonitorSource

    exit 1
}


########################################
# Create install folder
########################################

Write-Host "Creating install directory..."

New-Item `
    -ItemType Directory `
    -Path $InstallFolder `
    -Force | Out-Null


########################################
# Install monitor
########################################

Write-Host "Installing cartridge monitor..."

Copy-Item `
    -Path $MonitorSource `
    -Destination $MonitorTarget `
    -Force


########################################
# Create scheduled task
########################################

$TaskName = "Steam Game Cartridge Monitor"


Write-Host "Creating scheduled task..."


# Remove old task if it exists

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {

    Unregister-ScheduledTask `
        -TaskName $TaskName `
        -Confirm:$false

}


$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument (
        "-NoProfile " +
        "-ExecutionPolicy Bypass " +
        "-WindowStyle Hidden " +
        "-File `"$MonitorTarget`""
    )


$Trigger = New-ScheduledTaskTrigger `
    -AtLogOn


$Settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Days 3650) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)


Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -Description "Monitors inserted Steam Game Cartridges"


########################################
# Start monitor immediately
########################################

Write-Host "Starting monitor..."

Start-ScheduledTask `
    -TaskName $TaskName


########################################
# Done
########################################

Write-Host ""
Write-Host "=========================================="
Write-Host " Steam Game Cartridge installed"
Write-Host "=========================================="
Write-Host ""

Write-Host "Create cartridges with:"
Write-Host ""

Write-Host "  cartridge.json"
Write-Host ""

Write-Host "Example:"
Write-Host ""

Write-Host '  {'
Write-Host '    "version": 1,'
Write-Host '    "name": "Cyberpunk 2077",'
Write-Host '    "action": "run",'
Write-Host '    "steamAppId": "1091500",'
Write-Host '    "hashValidationEnabled": false'
Write-Host '  }'

Write-Host ""

Write-Host "The cartridge SSD must contain:"
Write-Host ""

Write-Host "  cartridge.json"
Write-Host "  SteamLibrary\steamapps\appmanifest_<steamAppId>.acf"

Write-Host ""

Write-Host "Insert a cartridge SSD to test."
Write-Host ""

Write-Host "Monitor location:"
Write-Host $MonitorTarget

Write-Host ""
