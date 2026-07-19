# Steam Game Cartridge - List / manage trusted scripts

$TrustDir = Join-Path $env:LOCALAPPDATA "SteamGameCartridge"
$TrustFile = Join-Path $TrustDir "trusted_scripts.sha256"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RootDir = Split-Path -Parent $ScriptDir


function Get-TrustEntries {

    if (-not (Test-Path $TrustFile)) {
        return @()
    }

    $Lines = Get-Content $TrustFile | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    $Entries = @()

    foreach ($Line in $Lines) {

        if ($Line -match '\|') {

            $Parts = $Line -split '\|'

            $Entries += [PSCustomObject]@{
                Hash  = $Parts[0].Trim()
                Label = if ($Parts.Count -ge 2) { $Parts[1] } else { "Unknown" }
                Date  = if ($Parts.Count -ge 3) { $Parts[2] } else { "" }
                Path  = if ($Parts.Count -ge 4) { $Parts[3] } else { "" }
            }
        }
        else {

            $Entries += [PSCustomObject]@{
                Hash  = $Line.Trim()
                Label = "(legacy entry)"
                Date  = ""
                Path  = ""
            }
        }
    }

    return $Entries
}


Clear-Host

$Entries = Get-TrustEntries

if ($Entries.Count -eq 0) {

    Write-Host "No trusted scripts yet."
    Write-Host ""
    Pause

    & "$RootDir\cartridge-windows.ps1"
    exit 0
}

Write-Host "Trusted scripts:"
Write-Host ""

for ($i = 0; $i -lt $Entries.Count; $i++) {

    $e = $Entries[$i]

    Write-Host ("[{0}] {1}" -f ($i + 1), $e.Label)
    Write-Host ("      Trusted: {0}" -f $e.Date)
    Write-Host ("      Path:    {0}" -f $e.Path)
    Write-Host ("      SHA256:  {0}" -f $e.Hash)
    Write-Host ""
}

$Choice = Read-Host "Enter a number to remove that entry, or press Enter to go back"

if (-not [string]::IsNullOrWhiteSpace($Choice)) {

    $Index = 0

    if ([int]::TryParse($Choice, [ref]$Index) -and $Index -ge 1 -and $Index -le $Entries.Count) {

        $ToRemove = $Entries[$Index - 1]

        $Confirm = Read-Host "Remove '$($ToRemove.Label)' from trusted scripts? (y/N)"

        if ($Confirm.ToLower() -eq "y") {

            $RemainingLines = Get-Content $TrustFile | Where-Object {

                if ([string]::IsNullOrWhiteSpace($_)) { return $false }

                $LineHash = if ($_ -match '\|') { ($_ -split '\|')[0].Trim() } else { $_.Trim() }

                return $LineHash -ne $ToRemove.Hash
            }

            Set-Content -Path $TrustFile -Value $RemainingLines

            Write-Host "Removed."
        }
        else {
            Write-Host "Cancelled."
        }
    }
    else {
        Write-Host "Invalid selection."
    }
}

Write-Host ""
Write-Host "Going back to menu..."
Start-Sleep -Seconds 1
Clear-Host

& "$RootDir\cartridge-windows.ps1"
exit 0
