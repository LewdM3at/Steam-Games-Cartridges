# Steam Game Cartridge Trust Script
# Finds launch.ps1 on removable drives and adds its SHA256 hash to trusted scripts.


$TrustDir = Join-Path $env:LOCALAPPDATA "SteamGameCartridge"
$TrustFile = Join-Path $TrustDir "trusted_scripts.sha256"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir


Write-Host "Scanning for script on Cartridge..."
Write-Host ""


if (-not (Test-Path $TrustDir)) {
    New-Item -ItemType Directory -Path $TrustDir -Force | Out-Null
}


if (-not (Test-Path $TrustFile)) {
    New-Item -ItemType File -Path $TrustFile -Force | Out-Null
}



$FoundScript = $null
$FoundDrive = $null



# Get all mounted drives
$Drives = Get-PSDrive -PSProvider FileSystem



foreach ($Drive in $Drives) {

    # Skip system drives without a root
    if (-not $Drive.Root) {
        continue
    }


    $Candidate = Join-Path $Drive.Root "launch.ps1"


    if (Test-Path $Candidate) {

        $FoundScript = $Candidate
        $FoundDrive = $Drive.Root

        break
    }
}



if (-not $FoundScript) {

    Write-Host "No cartridge with launch.ps1 found."

    exit 0
}



$DriveInfo = Get-Volume -DriveLetter $FoundDrive.Substring(0,1)

$Label = $DriveInfo.FileSystemLabel

if ([string]::IsNullOrWhiteSpace($Label)) {
    $Label = "Unknown"
}



Write-Host "Found launch.ps1"
Write-Host "Drive:  $FoundDrive"
Write-Host "Path:   $FoundScript"
Write-Host "Label:  $Label"
Write-Host ""



$Confirm = Read-Host "Do you want to add this script to trusted scripts? (Y/n)"

if ([string]::IsNullOrWhiteSpace($Confirm)) {
    $Confirm = "Y"
}



switch ($Confirm.ToLower()) {

    "y" {}
    "yes" {}

    default {

        Write-Host "Skipped."

        exit 0
    }
}



$Hash = (
    Get-FileHash `
        -Path $FoundScript `
        -Algorithm SHA256
).Hash.ToLower()



$TrustedLines = Get-Content $TrustFile

$AlreadyTrusted = $false

foreach ($Line in $TrustedLines) {

    if ([string]::IsNullOrWhiteSpace($Line)) {
        continue
    }

    $EntryHash = if ($Line -match '\|') { ($Line -split '\|')[0].Trim() } else { $Line.Trim() }

    if ($EntryHash -eq $Hash) {
        $AlreadyTrusted = $true
        break
    }
}



if ($AlreadyTrusted) {

    Write-Host "Already trusted."

}

else {

    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $SafeLabel = $Label -replace '\|', '/'

    Add-Content `
        -Path $TrustFile `
        -Value "$Hash|$SafeLabel|$Timestamp|$FoundScript"

    Write-Host "Added to trusted scripts."
    Write-Host "If you modify the script later, you will need to run this script again to trust the new version."
    Write-Host "Now the script will be executed automatically when you reconnect the Cartridge."

}



Write-Host ""
Write-Host "SHA256:"
Write-Host $Hash

Write-Host ""
Write-Host "Going back to menu..."
Start-Sleep -Seconds 1
Clear-Host

& "$RootDir\cartridge-windows.ps1"
exit 0