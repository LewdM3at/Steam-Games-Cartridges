# Steam Game Cartridge Monitor
# Watches for inserted drives and launches trusted launch.ps1 cartridges.

$InstallFolder = Join-Path $env:LOCALAPPDATA "SteamGameCartridge"

$LogFile = Join-Path $InstallFolder "monitor.log"
$TrustFile = Join-Path $InstallFolder "trusted_scripts.sha256"

$ConfigFile = Join-Path $InstallFolder "settings.conf"

$DebounceSeconds = 5


if (-not (Test-Path $InstallFolder)) {
    New-Item -ItemType Directory -Path $InstallFolder -Force | Out-Null
}

if (-not (Test-Path $TrustFile)) {
    New-Item -ItemType File -Path $TrustFile -Force | Out-Null
}

if (-not (Test-Path $ConfigFile)) {
    "MODE=running" | Out-File $ConfigFile -Encoding UTF8
}


$LastLaunches = @{}


function Write-Log {
    param(
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    Add-Content `
        -Path $LogFile `
        -Value "[$timestamp] $Message"
}


function Get-FileHashSHA256 {
    param(
        [string]$Path
    )

    return (Get-FileHash `
        -Path $Path `
        -Algorithm SHA256).Hash.ToLower()
}


function Get-TrustEntryHash {
    param(
        [string]$Line
    )

    # Trust entries look like "HASH|Label|Date|Path". Older installs may
    # still have bare-hash-only lines, so fall back to the whole line.
    if ($Line -match '\|') {
        return ($Line -split '\|')[0].Trim()
    }

    return $Line.Trim()
}

function Is-TrustedScript {
    param(
        [string]$Hash
    )

    if (-not (Test-Path $TrustFile)) {
        return $false
    }

    foreach ($Line in (Get-Content $TrustFile)) {

        if ([string]::IsNullOrWhiteSpace($Line)) {
            continue
        }

        if ((Get-TrustEntryHash $Line) -eq $Hash) {
            return $true
        }
    }

    return $false
}

function Add-TrustedScript {
    param(
        [string]$Hash,
        [string]$Label,
        [string]$Path
    )

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $SafeLabel = $Label -replace '\|', '/'

    Add-Content -Path $TrustFile -Value "$Hash|$SafeLabel|$Timestamp|$Path"
}

function Confirm-TrustPrompt {
    param(
        [string]$Drive,
        [string]$Label,
        [string]$Path,
        [string]$Hash
    )

    Add-Type -AssemblyName System.Windows.Forms | Out-Null

    $Message = "A new Steam Game Cartridge script was detected.`n`n" +
        "Drive:  $Drive ($Label)`n" +
        "Script: $Path`n" +
        "SHA256: $Hash`n`n" +
        "Do you want to trust and run this script?"

    $Result = [System.Windows.Forms.MessageBox]::Show(
        $Message,
        "Steam Game Cartridge - Untrusted script",
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning
    )

    return $Result -eq [System.Windows.Forms.DialogResult]::Yes
}

function Get-Mode {

    if (-not (Test-Path $ConfigFile)) {
        return "stopped"
    }


    $ModeLine = Get-Content $ConfigFile |
        Where-Object { $_ -like "MODE=*" }


    if ($ModeLine) {

        $Mode = $ModeLine.Split("=")[1]

        return $Mode.ToLower()

    }


    return "stopped"
}


Write-Log "Steam Game Cartridge monitor started."


$null = Register-WmiEvent `
    -Class Win32_VolumeChangeEvent `
    -SourceIdentifier "SteamGameCartridge" `
    -Action {


        $eventType = $Event.SourceEventArgs.NewEvent.EventType


        # 2 = drive inserted
        if ($eventType -ne 2) {
            return
        }


        $drive = $Event.SourceEventArgs.NewEvent.DriveName


        if ([string]::IsNullOrWhiteSpace($drive)) {
            return
        }


        $launcher = Join-Path $drive "launch.ps1"


        if (-not (Test-Path $launcher)) {
            return
        }


        # Debounce
        $now = Get-Date


        if ($LastLaunches.ContainsKey($drive)) {

            $elapsed = ($now - $LastLaunches[$drive]).TotalSeconds

            if ($elapsed -lt $DebounceSeconds) {

                Write-Log "Ignoring duplicate event for $drive"

                return
            }
        }


        $LastLaunches[$drive] = $now


        Write-Log "Cartridge detected: $drive"

        $Mode = Get-Mode


        if ($Mode -ne "running") {

            Write-Log "Cartridge execution disabled. Current mode: $Mode"

            return
        }


        try {

            $hash = Get-FileHashSHA256 $launcher


            Write-Log "SHA256: $hash"


            if (-not (Is-TrustedScript $hash)) {

                Write-Log "Untrusted cartridge detected. Prompting user."

                $label = "Unknown"
                try {
                    $vol = Get-Volume -DriveLetter $drive.Substring(0, 1) -ErrorAction Stop
                    if (-not [string]::IsNullOrWhiteSpace($vol.FileSystemLabel)) {
                        $label = $vol.FileSystemLabel
                    }
                }
                catch {}

                $trust = Confirm-TrustPrompt -Drive $drive -Label $label -Path $launcher -Hash $hash

                if (-not $trust) {

                    Write-Log "User declined to trust cartridge."

                    return
                }

                Add-TrustedScript -Hash $hash -Label $label -Path $launcher

                Write-Log "User trusted cartridge. Added to trust file."
            }


            Write-Log "Trusted cartridge."


            Start-Process `
                -FilePath "powershell.exe" `
                -ArgumentList @(
                    "-NoProfile",
                    "-ExecutionPolicy", "Bypass",
                    "-WindowStyle", "Hidden",
                    "-File", "`"$launcher`""
                ) `
                -WindowStyle Hidden


            Write-Log "Launched: $launcher"

        }

        catch {

            Write-Log "Failed launching $launcher"
            Write-Log $_.Exception.Message

        }

    }


Write-Log "Event watcher registered."


try {

    while ($true) {

        Wait-Event | Out-Null

    }

}

finally {

    Unregister-Event `
        -SourceIdentifier "SteamGameCartridge" `
        -ErrorAction SilentlyContinue

    Remove-Job `
        -Name "SteamGameCartridge" `
        -Force `
        -ErrorAction SilentlyContinue

    Write-Log "Monitor stopped."

}