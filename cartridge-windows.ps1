$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path


# Config
$ConfigDir = Join-Path $env:LOCALAPPDATA "SteamGameCartridge"
$ConfigFile = Join-Path $ConfigDir "settings.conf"


if (-not (Test-Path $ConfigDir)) {
    New-Item -ItemType Directory -Path $ConfigDir -Force | Out-Null
}


if (-not (Test-Path $ConfigFile)) {
    "MODE=running" | Out-File $ConfigFile -Encoding UTF8
}



function Get-Mode {

    $ModeLine = Get-Content $ConfigFile | Where-Object { $_ -like "MODE=*" }

    if ($ModeLine) {
        $Mode = $ModeLine.Split("=")[1]
        if ($Mode -eq "stopped") {
            return "stopped"
        }
    }
    return "running"
}



function Toggle-Mode {
    $CurrentMode = Get-Mode
    if ($CurrentMode -eq "running") {
        "MODE=stopped" | Out-File $ConfigFile -Encoding UTF8
    }
    else {
        "MODE=running" | Out-File $ConfigFile -Encoding UTF8
    }
}

function Show-Menu {
    $Mode = Get-Mode
    if ($Mode -eq "running") {
        $ModeText = "Yes"
        $ModeColor = "Green"
    }
    else {
        $ModeText = "No "
        $ModeColor = "Red"
    }

    Clear-Host

    Write-Host ""
    Write-Host @"
    ██████╗ █████╗ ██████╗ ████████╗██████╗ ██╗██████╗  ██████╗ ███████╗███████╗
   ██╔════╝██╔══██╗██╔══██╗╚══██╔══╝██╔══██╗██║██╔══██╗██╔════╝ ██╔════╝██╔════╝
   ██║     ███████║██████╔╝   ██║   ██████╔╝██║██║  ██║██║  ███╗█████╗  ███████╗
   ██║     ██╔══██║██╔══██╗   ██║   ██╔══██╗██║██║  ██║██║   ██║██╔══╝  ╚════██║
   ╚██████╗██║  ██║██║  ██║   ██║   ██║  ██║██║██████╔╝╚██████╔╝███████╗███████║
    ╚═════╝╚═╝  ╚═╝╚═╝  ╚═╝   ╚═╝   ╚═╝  ╚═╝╚═╝╚═════╝  ╚═════╝ ╚══════╝╚══════╝
"@ -ForegroundColor Cyan


    Write-Host ""
    Write-Host "        ╭────────────────────────────────────────╮"
    Write-Host "        │      Menu                              │"
    Write-Host "        ├────────────────────────────────────────┤"
    Write-Host "        │   1) Install                           │"
    Write-Host "        │   2) Trust Scripts                     │"
    Write-Host "        │   3) View Trusted Scripts              │"

    Write-Host -NoNewline "        │   4) Auto-Launch scripts: "

    Write-Host -NoNewline $ModeText -ForegroundColor $ModeColor

    Write-Host "          │"

    Write-Host "        │   5) Uninstall                         │"
    Write-Host "        │   6) Exit                              │"
    Write-Host "        ╰────────────────────────────────────────╯"
    Write-Host ""

}


while ($true) {
    Show-Menu
    $Option = Read-Host "     Select option"

    switch ($Option) {
        "1" {
            Clear-Host
            Write-Host "Starting installation..."
            Start-Process `
                powershell.exe `
                -Verb RunAs `
                -ArgumentList "-ExecutionPolicy Bypass -File `"$ScriptDir\windows\install.ps1`"" `
                -Wait
        }

        "2" {
            Clear-Host
            Write-Host "Starting trust process..."
            powershell.exe `
                -ExecutionPolicy Bypass `
                -File "$ScriptDir\windows\trust-script.ps1"

            Pause
        }

        "3" {
            Clear-Host
            powershell.exe `
                -ExecutionPolicy Bypass `
                -File "$ScriptDir\windows\list-trusted-scripts.ps1"
        }

        "4" {
            Toggle-Mode
        }

        "5" {
            Clear-Host
            Write-Host "Starting uninstall..."
            Start-Process `
                powershell.exe `
                -Verb RunAs `
                -ArgumentList "-ExecutionPolicy Bypass -File `"$ScriptDir\windows\uninstall.ps1`"" `
                -Wait
        }

        "6" {
            Clear-Host
            exit
        }

        default {
            Write-Host "Invalid option."
            Start-Sleep -Seconds 1
        }
    }
}