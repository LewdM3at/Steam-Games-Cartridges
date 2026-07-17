# Steam Game Cartridge Monitor
# Watches for inserted drives and launches validated Steam actions from cartridge.json.

$InstallFolder = Join-Path $env:LOCALAPPDATA "SteamGameCartridge"
$LogFile = Join-Path $InstallFolder "monitor.log"

$DebounceSeconds = 5
$ConfigFileName = "cartridge.json"

function ConvertTo-SafeLogText {
    param(
        [object]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    return ([string]$Value) -replace '[\p{Cc}\p{Cf}]', " "
}

function Write-Log {
    param(
        [string]$Message
    )

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $safeMessage = ConvertTo-SafeLogText $Message

    Add-Content `
        -Path $LogFile `
        -Value "[$timestamp] $safeMessage"
}

$ConvertToLogText = {
    param(
        [object]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    return ([string]$Value) -replace '[\p{Cc}\p{Cf}]', " "
}

$ReadCartridgeConfig = {
    param(
        [string]$ConfigPath
    )

    $maxConfigBytes = 16KB

    $allowedProperties = @(
        "version",
        "name",
        "action",
        "steamAppId",
        "hashValidationEnabled",
        "hashManifestId"
    )

    $allowedActions = @(
        "run",
        "details"
    )

    $steamUriTemplates = @{
        run     = "steam://run/{0}"
        details = "steam://nav/games/details/{0}"
    }

    function Get-ConfigProperty {
        param(
            [object]$Config,
            [string]$Name
        )

        return $Config.PSObject.Properties |
            Where-Object { $_.Name -ceq $Name } |
            Select-Object -First 1
    }

    function ConvertTo-SafeText {
        param(
            [object]$Value
        )

        if ($null -eq $Value) {
            return ""
        }

        return ([string]$Value) -replace '[\p{Cc}\p{Cf}]', " "
    }

    if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
        throw "Missing cartridge.json"
    }

    $configItem = Get-Item `
        -LiteralPath $ConfigPath `
        -ErrorAction Stop

    if (($configItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "cartridge.json must not be a reparse point"
    }

    if ($configItem.Length -gt $maxConfigBytes) {
        throw "cartridge.json is too large"
    }

    $rawConfig = Get-Content `
        -LiteralPath $ConfigPath `
        -Raw `
        -Encoding UTF8 `
        -ErrorAction Stop

    if ([string]::IsNullOrWhiteSpace($rawConfig)) {
        throw "cartridge.json is empty"
    }

    try {
        $config = $rawConfig | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "cartridge.json is not valid JSON"
    }

    if ($null -eq $config -or -not ($config -is [pscustomobject])) {
        throw "cartridge.json must contain a JSON object"
    }

    foreach ($property in $config.PSObject.Properties) {
        if ($allowedProperties -cnotcontains $property.Name) {
            $propertyName = ConvertTo-SafeText $property.Name
            throw "Unsupported cartridge.json property: $propertyName"
        }
    }

    $versionProperty = Get-ConfigProperty -Config $config -Name "version"

    if ($null -eq $versionProperty) {
        throw "Missing version"
    }

    if (-not (
            ($versionProperty.Value -is [int]) -or
            ($versionProperty.Value -is [long])
        ) -or [long]$versionProperty.Value -ne 1) {
        throw "Unsupported cartridge.json version"
    }

    $steamAppIdProperty = Get-ConfigProperty -Config $config -Name "steamAppId"

    if ($null -eq $steamAppIdProperty) {
        throw "Missing steamAppId"
    }

    if ($steamAppIdProperty.Value -is [string]) {
        $steamAppId = $steamAppIdProperty.Value.Trim()
    }
    elseif (
        ($steamAppIdProperty.Value -is [int]) -or
        ($steamAppIdProperty.Value -is [long])
    ) {
        $steamAppId = [string]$steamAppIdProperty.Value
    }
    else {
        throw "steamAppId must be a positive numeric Steam app id"
    }

    if ($steamAppId -notmatch "^[1-9][0-9]{0,19}$") {
        throw "steamAppId must be a positive numeric Steam app id"
    }

    $action = "run"
    $actionProperty = Get-ConfigProperty -Config $config -Name "action"

    if ($null -ne $actionProperty) {
        if (-not ($actionProperty.Value -is [string])) {
            throw "action must be a string"
        }

        $action = $actionProperty.Value.Trim().ToLowerInvariant()
    }

    if ($allowedActions -cnotcontains $action) {
        throw "Unsupported Steam action"
    }

    $name = $steamAppId
    $nameProperty = Get-ConfigProperty -Config $config -Name "name"

    if ($null -ne $nameProperty) {
        if (-not ($nameProperty.Value -is [string])) {
            throw "name must be a string"
        }

        $name = $nameProperty.Value.Trim()

        if ($name.Length -gt 80) {
            throw "name must be 80 characters or less"
        }

        if ($name -match '[\p{Cc}\p{Cf}]') {
            throw "name must not contain control or format characters"
        }
    }

    $hashValidationEnabled = $false
    $hashValidationProperty = Get-ConfigProperty -Config $config -Name "hashValidationEnabled"

    if ($null -ne $hashValidationProperty) {
        if (-not ($hashValidationProperty.Value -is [bool])) {
            throw "hashValidationEnabled must be a boolean"
        }

        $hashValidationEnabled = $hashValidationProperty.Value
    }

    $hashManifestId = $null
    $hashManifestProperty = Get-ConfigProperty -Config $config -Name "hashManifestId"

    if ($null -ne $hashManifestProperty) {
        if (-not ($hashManifestProperty.Value -is [string])) {
            throw "hashManifestId must be a string"
        }

        $hashManifestId = $hashManifestProperty.Value.Trim().ToLowerInvariant()

        if ($hashManifestId -notmatch "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$") {
            throw "hashManifestId must be a UUID"
        }
    }

    if ($hashValidationEnabled -and [string]::IsNullOrWhiteSpace($hashManifestId)) {
        throw "hashManifestId is required when hashValidationEnabled is true"
    }

    $steamUri = [string]::Format(
        $steamUriTemplates[$action],
        $steamAppId
    )

    return [pscustomobject]@{
        Name       = $name
        Action     = $action
        SteamAppId = $steamAppId
        SteamUri   = $steamUri
        HashValidationEnabled = $hashValidationEnabled
        HashManifestId = $hashManifestId
    }
}

$PrepareCartridgeLibrary = {
    param(
        [string]$DriveRoot,
        [string]$SteamAppId
    )

    function ConvertTo-SafeText {
        param(
            [object]$Value
        )

        if ($null -eq $Value) {
            return ""
        }

        return ([string]$Value) -replace '[\p{Cc}\p{Cf}]', " "
    }

    function ConvertTo-VdfString {
        param(
            [string]$Value
        )

        return $Value.Replace("\", "\\").Replace('"', '\"')
    }

    function ConvertFrom-VdfString {
        param(
            [string]$Value
        )

        $builder = [System.Text.StringBuilder]::new()

        for ($index = 0; $index -lt $Value.Length; $index++) {
            $character = $Value[$index]

            if ($character -eq "\" -and $index + 1 -lt $Value.Length) {
                $index++
                [void]$builder.Append($Value[$index])
            }
            else {
                [void]$builder.Append($character)
            }
        }

        return $builder.ToString()
    }

    function ConvertTo-ComparablePath {
        param(
            [string]$Path
        )

        $fullPath = [IO.Path]::GetFullPath($Path)
        $trimmedPath = $fullPath -replace '[\\/]+$', ''

        return $trimmedPath.ToUpperInvariant()
    }

    function Test-RegularDirectory {
        param(
            [string]$Path,
            [string]$Description
        )

        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            throw "$Description not found"
        }

        $item = Get-Item `
            -LiteralPath $Path `
            -ErrorAction Stop

        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Description must not be a reparse point"
        }

        return $item.FullName
    }

    function Test-RegularFile {
        param(
            [string]$Path,
            [string]$Description,
            [long]$MaxBytes
        )

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "$Description not found"
        }

        $item = Get-Item `
            -LiteralPath $Path `
            -ErrorAction Stop

        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Description must not be a reparse point"
        }

        if ($item.Length -gt $MaxBytes) {
            throw "$Description is too large"
        }

        return $item.FullName
    }

    function Get-SteamLibraryFoldersPath {
        $candidateRoots = [System.Collections.Generic.List[string]]::new()

        foreach ($registryPath in @(
                "HKCU:\Software\Valve\Steam",
                "HKLM:\SOFTWARE\WOW6432Node\Valve\Steam",
                "HKLM:\SOFTWARE\Valve\Steam"
            )) {
            try {
                $steamPath = (Get-ItemProperty `
                        -Path $registryPath `
                        -ErrorAction Stop).SteamPath

                if (-not [string]::IsNullOrWhiteSpace($steamPath)) {
                    $candidateRoots.Add($steamPath)
                }
            }
            catch {
            }
        }

        foreach ($programFilesRoot in @(
                ${env:ProgramFiles(x86)},
                $env:ProgramFiles
            )) {
            if (-not [string]::IsNullOrWhiteSpace($programFilesRoot)) {
                $candidateRoots.Add((Join-Path $programFilesRoot "Steam"))
            }
        }

        foreach ($root in $candidateRoots) {
            $normalizedRoot = $root -replace '/', '\'
            $candidate = Join-Path $normalizedRoot "steamapps\libraryfolders.vdf"

            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return $candidate
            }
        }

        throw "Steam libraryfolders.vdf not found"
    }

    function Test-CartridgeSteamLibrary {
        param(
            [string]$Root,
            [string]$AppId
        )

        $libraryPath = Test-RegularDirectory `
            -Path (Join-Path $Root "SteamLibrary") `
            -Description "Cartridge SteamLibrary"

        if ($libraryPath -match '[\p{Cc}\p{Cf}]') {
            throw "Cartridge SteamLibrary path contains unsupported characters"
        }

        $steamappsPath = Test-RegularDirectory `
            -Path (Join-Path $libraryPath "steamapps") `
            -Description "Cartridge steamapps directory"

        $manifestPath = Test-RegularFile `
            -Path (Join-Path $steamappsPath "appmanifest_$AppId.acf") `
            -Description "Cartridge app manifest" `
            -MaxBytes (1MB)

        $manifestRaw = Get-Content `
            -LiteralPath $manifestPath `
            -Raw `
            -Encoding UTF8 `
            -ErrorAction Stop

        $appidMatches = [regex]::Matches(
            $manifestRaw,
            '(?m)^\s*"appid"\s*"([0-9]+)"\s*$'
        )

        if ($appidMatches.Count -ne 1 -or $appidMatches[0].Groups[1].Value -ne $AppId) {
            throw "Cartridge app manifest does not match steamAppId"
        }

        $installDirMatches = [regex]::Matches(
            $manifestRaw,
            '(?m)^\s*"installdir"\s*"((?:\\.|[^"\\])*)"\s*$'
        )

        if ($installDirMatches.Count -ne 1) {
            throw "Cartridge app manifest must contain exactly one installdir"
        }

        $installDir = ConvertFrom-VdfString $installDirMatches[0].Groups[1].Value

        if (
            [string]::IsNullOrWhiteSpace($installDir) -or
            $installDir -eq "." -or
            $installDir -eq ".." -or
            [IO.Path]::IsPathRooted($installDir) -or
            $installDir -match '[\\/:\p{Cc}\p{Cf}]'
        ) {
            throw "Cartridge app manifest contains an unsafe installdir"
        }

        $commonPath = Test-RegularDirectory `
            -Path (Join-Path $steamappsPath "common") `
            -Description "Cartridge common directory"

        [void](Test-RegularDirectory `
                -Path (Join-Path $commonPath $installDir) `
                -Description "Cartridge game directory")

        return [pscustomobject]@{
            LibraryPath = $libraryPath
            InstallDir  = $installDir
        }
    }

    function Register-SteamLibraryFolder {
        param(
            [string]$LibraryPath,
            [string]$AppId
        )

        $libraryFoldersPath = Get-SteamLibraryFoldersPath
        [void](Test-RegularFile `
                -Path $libraryFoldersPath `
                -Description "Steam libraryfolders.vdf" `
                -MaxBytes (4MB))

        $libraryFoldersContent = Get-Content `
            -LiteralPath $libraryFoldersPath `
            -Raw `
            -Encoding UTF8 `
            -ErrorAction Stop

        if ([string]::IsNullOrWhiteSpace($libraryFoldersContent)) {
            throw "Steam libraryfolders.vdf is empty"
        }

        $libraryPathFull = [IO.Path]::GetFullPath($LibraryPath)
        $libraryPathComparable = ConvertTo-ComparablePath $libraryPathFull
        $pathPattern = '(?m)^\s*"path"\s*"((?:\\.|[^"\\])*)"\s*$'

        foreach ($match in [regex]::Matches($libraryFoldersContent, $pathPattern)) {
            $existingPath = ConvertFrom-VdfString $match.Groups[1].Value

            if ((ConvertTo-ComparablePath $existingPath) -eq $libraryPathComparable) {
                return [pscustomobject]@{
                    LibraryPath        = $libraryPathFull
                    LibraryFoldersPath = $libraryFoldersPath
                    Registered         = $false
                }
            }
        }

        $numericKeyMatches = [regex]::Matches(
            $libraryFoldersContent,
            '(?m)^\s*"([0-9]+)"\s*(?:\{|")'
        )
        $nextIndex = 0

        foreach ($match in $numericKeyMatches) {
            $key = [int]$match.Groups[1].Value

            if ($key -ge $nextIndex) {
                $nextIndex = $key + 1
            }
        }

        $insertAt = $libraryFoldersContent.LastIndexOf("}")

        if ($insertAt -lt 0) {
            throw "Steam libraryfolders.vdf is not a valid VDF file"
        }

        $escapedLibraryPath = ConvertTo-VdfString $libraryPathFull
        $escapedAppId = ConvertTo-VdfString $AppId
        $newEntry = @"
    "$nextIndex"
    {
        "path" "$escapedLibraryPath"
        "label" ""
        "contentid" "0"
        "totalsize" "0"
        "update_clean_bytes_tally" "0"
        "time_last_update_corruption" "0"
        "apps"
        {
            "$escapedAppId" "0"
        }
    }

"@

        $updatedContent =
            $libraryFoldersContent.Substring(0, $insertAt) +
            $newEntry +
            $libraryFoldersContent.Substring($insertAt)

        $tempPath = "$libraryFoldersPath.tmp"

        Set-Content `
            -LiteralPath $tempPath `
            -Value $updatedContent `
            -Encoding UTF8 `
            -NoNewline

        Move-Item `
            -LiteralPath $tempPath `
            -Destination $libraryFoldersPath `
            -Force

        return [pscustomobject]@{
            LibraryPath        = $libraryPathFull
            LibraryFoldersPath = $libraryFoldersPath
            Registered         = $true
        }
    }

    $cartridgeLibrary = Test-CartridgeSteamLibrary `
        -Root $DriveRoot `
        -AppId $SteamAppId

    $registeredLibrary = Register-SteamLibraryFolder `
        -LibraryPath $cartridgeLibrary.LibraryPath `
        -AppId $SteamAppId

    return [pscustomobject]@{
        LibraryPath        = $registeredLibrary.LibraryPath
        LibraryFoldersPath = $registeredLibrary.LibraryFoldersPath
        Registered         = $registeredLibrary.Registered
        InstallDir         = $cartridgeLibrary.InstallDir
    }
}

$VerifyCartridgeHashes = {
    param(
        [string]$LibraryPath,
        [string]$InstallDir,
        [string]$SteamAppId,
        [string]$HashManifestId
    )

    $maxHashManifestBytes = 128MB
    $maxHashedFileBytes = 100MB

    function ConvertTo-SafeText {
        param(
            [object]$Value
        )

        if ($null -eq $Value) {
            return ""
        }

        return ([string]$Value) -replace '[\p{Cc}\p{Cf}]', " "
    }

    function Test-RegularFile {
        param(
            [string]$Path,
            [string]$Description,
            [long]$MaxBytes
        )

        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            throw "$Description not found"
        }

        $item = Get-Item `
            -LiteralPath $Path `
            -ErrorAction Stop

        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "$Description must not be a reparse point"
        }

        if ($item.Length -gt $MaxBytes) {
            throw "$Description is too large"
        }

        return $item
    }

    function Get-HashManifestPath {
        param(
            [string]$ManifestId
        )

        return Join-Path `
            (Join-Path $env:LOCALAPPDATA "SteamGameCartridge\hashes") `
            "$ManifestId.json"
    }

    function Test-HashRelativePath {
        param(
            [string]$RelativePath,
            [string]$AppId,
            [string]$GameInstallDir
        )

        if ([string]::IsNullOrWhiteSpace($RelativePath)) {
            throw "Hash manifest relativePath must not be empty"
        }

        if (
            $RelativePath.StartsWith("/") -or
            $RelativePath.StartsWith("~") -or
            $RelativePath.Contains("\") -or
            $RelativePath -match '[\p{Cc}\p{Cf}]'
        ) {
            throw "Hash manifest relativePath is unsafe"
        }

        $segments = $RelativePath.Split("/")

        foreach ($segment in $segments) {
            if ([string]::IsNullOrWhiteSpace($segment) -or $segment -eq "." -or $segment -eq "..") {
                throw "Hash manifest relativePath is unsafe"
            }
        }

        $manifestPath = "steamapps/appmanifest_$AppId.acf"
        $gamePrefix = "steamapps/common/$GameInstallDir/"

        if ($RelativePath -ne $manifestPath -and -not $RelativePath.StartsWith($gamePrefix, [StringComparison]::Ordinal)) {
            throw "Hash manifest contains a path outside the selected game"
        }
    }

    function Get-RelativeSteamPath {
        param(
            [string]$Root,
            [string]$Path
        )

        $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
        $pathFull = [IO.Path]::GetFullPath($Path)
        $prefix = "$rootFull\"

        if (-not $pathFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Game file is outside the Steam library"
        }

        return $pathFull.Substring($prefix.Length).Replace("\", "/")
    }

    function Get-Sha256 {
        param(
            [string]$Path
        )

        return (Get-FileHash `
                -LiteralPath $Path `
                -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    $hashManifestPath = Get-HashManifestPath $HashManifestId
    [void](Test-RegularFile `
            -Path $hashManifestPath `
            -Description "Local hash manifest" `
            -MaxBytes $maxHashManifestBytes)

    $rawManifest = Get-Content `
        -LiteralPath $hashManifestPath `
        -Raw `
        -Encoding UTF8 `
        -ErrorAction Stop

    try {
        $hashManifest = $rawManifest | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Local hash manifest is not valid JSON"
    }

    if ($null -eq $hashManifest -or -not ($hashManifest -is [pscustomobject])) {
        throw "Local hash manifest must contain a JSON object"
    }

    $allowedProperties = @(
        "version",
        "hashManifestId",
        "steamAppId",
        "gameName",
        "generatedAtUtc",
        "maxFileSizeBytes",
        "files"
    )

    foreach ($property in $hashManifest.PSObject.Properties) {
        if ($allowedProperties -cnotcontains $property.Name) {
            $propertyName = ConvertTo-SafeText $property.Name
            throw "Unsupported local hash manifest property: $propertyName"
        }
    }

    if ([long]$hashManifest.version -ne 1) {
        throw "Unsupported local hash manifest version"
    }

    if ([string]$hashManifest.hashManifestId -ne $HashManifestId) {
        throw "Local hash manifest id does not match cartridge.json"
    }

    if ([string]$hashManifest.steamAppId -ne $SteamAppId) {
        throw "Local hash manifest app id does not match cartridge.json"
    }

    if ([long]$hashManifest.maxFileSizeBytes -ne $maxHashedFileBytes) {
        throw "Local hash manifest has an unsupported maxFileSizeBytes value"
    }

    $expected = @{}

    foreach ($entry in @($hashManifest.files)) {
        if ($null -eq $entry -or -not ($entry -is [pscustomobject])) {
            throw "Local hash manifest file entries must be objects"
        }

        $entryProperties = @($entry.PSObject.Properties | ForEach-Object { $_.Name })

        foreach ($propertyName in $entryProperties) {
            if (@("relativePath", "size", "sha256") -cnotcontains $propertyName) {
                throw "Local hash manifest file entry has unsupported properties"
            }
        }

        foreach ($requiredProperty in @("relativePath", "size", "sha256")) {
            if ($entryProperties -cnotcontains $requiredProperty) {
                throw "Local hash manifest file entry is missing $requiredProperty"
            }
        }

        $relativePath = [string]$entry.relativePath
        Test-HashRelativePath `
            -RelativePath $relativePath `
            -AppId $SteamAppId `
            -GameInstallDir $InstallDir

        $entrySize = [long]$entry.size

        if ($entrySize -lt 0 -or $entrySize -ge $maxHashedFileBytes) {
            throw "Local hash manifest file size is invalid"
        }

        $sha256 = ([string]$entry.sha256).ToLowerInvariant()

        if ($sha256 -notmatch "^[a-f0-9]{64}$") {
            throw "Local hash manifest sha256 is invalid"
        }

        if ($expected.ContainsKey($relativePath)) {
            throw "Local hash manifest contains duplicate file paths"
        }

        $expected[$relativePath] = [pscustomobject]@{
            Size   = $entrySize
            Sha256 = $sha256
        }
    }

    $seen = @{}
    $pathsToCheck = [System.Collections.Generic.List[string]]::new()

    $pathsToCheck.Add((Join-Path (Join-Path $LibraryPath "steamapps") "appmanifest_$SteamAppId.acf"))

    $gamePath = Join-Path `
        (Join-Path (Join-Path $LibraryPath "steamapps") "common") `
        $InstallDir

    foreach ($file in Get-ChildItem `
            -LiteralPath $gamePath `
            -File `
            -Recurse `
            -Force `
            -ErrorAction Stop) {
        $pathsToCheck.Add($file.FullName)
    }

    foreach ($path in $pathsToCheck) {
        $fileItem = Get-Item `
            -LiteralPath $path `
            -ErrorAction Stop

        if (($fileItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Game files must not be reparse points"
        }

        if ($fileItem.Length -ge $maxHashedFileBytes) {
            continue
        }

        $relativePath = Get-RelativeSteamPath `
            -Root $LibraryPath `
            -Path $fileItem.FullName

        if (-not $expected.ContainsKey($relativePath)) {
            $safePath = ConvertTo-SafeText $relativePath
            throw "Unexpected hashable file on cartridge: $safePath"
        }

        $expectedEntry = $expected[$relativePath]

        if ($expectedEntry.Size -ne $fileItem.Length) {
            $safePath = ConvertTo-SafeText $relativePath
            throw "Hash size mismatch for: $safePath"
        }

        $actualSha256 = Get-Sha256 $fileItem.FullName

        if ($expectedEntry.Sha256 -ne $actualSha256) {
            $safePath = ConvertTo-SafeText $relativePath
            throw "Hash mismatch for: $safePath"
        }

        $seen[$relativePath] = $true
    }

    foreach ($expectedPath in $expected.Keys) {
        if (-not $seen.ContainsKey($expectedPath)) {
            $safePath = ConvertTo-SafeText $expectedPath
            throw "Missing hashable file on cartridge: $safePath"
        }
    }
}

$EventData = @{
    LogFile             = $LogFile
    ConfigFileName      = $ConfigFileName
    DebounceSeconds     = $DebounceSeconds
    LastLaunches        = [hashtable]::Synchronized(@{})
    ReadCartridgeConfig = $ReadCartridgeConfig
    PrepareCartridgeLibrary = $PrepareCartridgeLibrary
    VerifyCartridgeHashes = $VerifyCartridgeHashes
    ConvertToLogText    = $ConvertToLogText
}

Write-Log "Steam Game Cartridge monitor started."

Register-WmiEvent `
    -Class Win32_VolumeChangeEvent `
    -SourceIdentifier "SteamGameCartridge" `
    -MessageData $EventData `
    -Action {

        $eventData = $EventSubscriber.MessageData

        function Write-EventLog {
            param(
                [string]$Message
            )

            $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $safeMessage = ([string]$Message) -replace '[\p{Cc}\p{Cf}]', " "

            Add-Content `
                -Path ($eventData["LogFile"]) `
                -Value "[$timestamp] $safeMessage"
        }

        $eventType = $Event.SourceEventArgs.NewEvent.EventType

        # 2 = drive inserted
        if ($eventType -ne 2) {
            return
        }

        $drive = $Event.SourceEventArgs.NewEvent.DriveName

        if ([string]::IsNullOrWhiteSpace($drive)) {
            return
        }

        if ($drive -match "^[A-Za-z]:$") {
            $driveRoot = "$drive\"
        }
        else {
            $driveRoot = $drive
        }

        $configFileName = $eventData["ConfigFileName"]
        $configFile = Join-Path $driveRoot $configFileName

        if (-not (Test-Path -LiteralPath $configFile -PathType Leaf)) {
            return
        }

        # Debounce
        $now = Get-Date
        $lastLaunches = $eventData["LastLaunches"]
        $debounceSeconds = $eventData["DebounceSeconds"]

        if ($lastLaunches.ContainsKey($drive)) {
            $elapsed = ($now - $lastLaunches[$drive]).TotalSeconds

            if ($elapsed -lt $debounceSeconds) {
                Write-EventLog "Ignoring duplicate event for $drive"

                return
            }
        }

        $lastLaunches[$drive] = $now

        Write-EventLog "Cartridge detected: $drive"

        try {
            $readCartridgeConfig = $eventData["ReadCartridgeConfig"]
            $prepareCartridgeLibrary = $eventData["PrepareCartridgeLibrary"]
            $verifyCartridgeHashes = $eventData["VerifyCartridgeHashes"]
            $convertToLogText = $eventData["ConvertToLogText"]
            $cartridge = & $readCartridgeConfig $configFile
            $steamLibrary = & $prepareCartridgeLibrary $driveRoot $cartridge.SteamAppId

            if ($cartridge.HashValidationEnabled) {
                & $verifyCartridgeHashes `
                    $steamLibrary.LibraryPath `
                    $steamLibrary.InstallDir `
                    $cartridge.SteamAppId `
                    $cartridge.HashManifestId
            }

            Start-Process `
                -FilePath $cartridge.SteamUri

            $safeName = & $convertToLogText $cartridge.Name

            Write-EventLog (
                "Launched cartridge: name={0}, action={1}, steamAppId={2}, library={3}" -f `
                    $safeName,
                    $cartridge.Action,
                    $cartridge.SteamAppId,
                    (& $convertToLogText $steamLibrary.LibraryPath)
            )
        }
        catch {
            Write-EventLog "Failed launching cartridge config: $configFile"
            Write-EventLog $_.Exception.Message
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
        -SourceIdentifier "SteamGameCartridge"

    Remove-Job `
        -Name "SteamGameCartridge" `
        -Force `
        -ErrorAction SilentlyContinue

    Write-Log "Monitor stopped."
}
