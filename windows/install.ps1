# Steam Game Cartridge Installer

$ErrorActionPreference = "Stop"


Write-Host ""
Write-Host "Installing Steam Game Cartridge launcher..."
Write-Host ""


########################################
# Paths
########################################

$InstallFolder = Join-Path $env:ProgramData "SteamGameCartridge"

$MonitorSource = Join-Path $PSScriptRoot "cartridge-monitoring.ps1"

$MonitorTarget = Join-Path $InstallFolder "cartridge-monitoring.ps1"

$LauncherSource = Join-Path $PSScriptRoot "cartridge-monitoring-launcher.vbs"

$LauncherTarget = Join-Path $InstallFolder "cartridge-monitoring-launcher.vbs"


########################################
# Check source file
########################################

if (-not (Test-Path $MonitorSource)) {

    Write-Error "Missing file:"
    Write-Error $MonitorSource

    exit 1
}

if (-not (Test-Path $LauncherSource)) {

    Write-Error "Missing file:"
    Write-Error $LauncherSource

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
# Lock down install folder permissions
########################################
# The monitor script auto-runs at every logon, so it must not be writable
# by a standard (non-admin) user account - only Administrators/SYSTEM may
# modify it. Trust data and settings remain user-writable in LOCALAPPDATA.

Write-Host "Securing install directory..."

$Acl = Get-Acl $InstallFolder
$Acl.SetAccessRuleProtection($true, $false)

foreach ($Rule in @($Acl.Access)) {
    $Acl.RemoveAccessRule($Rule) | Out-Null
}

# Well-known SIDs are used instead of "BUILTIN\Administrators" / "BUILTIN\Users"
# because those account names are localized (e.g. "Administradores" on
# Spanish Windows) and fail to resolve on non-English systems. SIDs are
# language-independent.
$SidSystem = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-18")
$SidAdministrators = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
$SidUsers = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-545")

$Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
    $SidSystem, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
)))
$Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
    $SidAdministrators, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
)))
$Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
    $SidUsers, "ReadAndExecute", "ContainerInherit,ObjectInherit", "None", "Allow"
)))

Set-Acl -Path $InstallFolder -AclObject $Acl


########################################
# Install monitor
########################################

Write-Host "Installing cartridge monitor..."

Copy-Item `
    -Path $MonitorSource `
    -Destination $MonitorTarget `
    -Force

Copy-Item `
    -Path $LauncherSource `
    -Destination $LauncherTarget `
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


# The task runs the VBScript launcher (not powershell.exe directly). The
# launcher starts the monitor via WScript.Shell.Run with window style 0,
# which never creates a console window in the first place - unlike
# "powershell.exe -WindowStyle Hidden", which still spawns a console under
# the hood before hiding it and can crash the task with
# STATUS_CONTROL_C_EXIT (0xC000013A) when Task Scheduler tears it down.
$Action = New-ScheduledTaskAction `
    -Execute "wscript.exe" `
    -Argument "`"$LauncherTarget`""


$Trigger = New-ScheduledTaskTrigger `
    -AtLogOn


# -Hidden only hides the task from Task Scheduler's default UI listing;
# actual window suppression comes from the VBScript launcher above.
$Settings = New-ScheduledTaskSettingsSet `
    -Hidden `
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

Write-Host "  launch.ps1"
Write-Host ""

Write-Host "Example:"
Write-Host ""

Write-Host '  Start-Process "steam://rungameid/1091500"'

Write-Host ""

Write-Host "The cartridge SSD must contain:"
Write-Host ""

Write-Host "  launch.ps1"

Write-Host ""
Write-Host "Trust the script with 'trust-script-windows.ps1'"
Write-Host "Then re-insert the cartridge to test."
Write-Host ""

Write-Host "Monitor location:"
Write-Host $MonitorTarget

Write-Host ""
# PAUSE so Users can read the info
PAUSE