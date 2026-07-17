using Microsoft.Win32;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Security.Cryptography;
using System.Security.Principal;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using System.Windows;

namespace CartridgeCreator;

public partial class MainWindow : Window, INotifyPropertyChanged
{
    private const long MaxHashedFileBytes = 100L * 1024L * 1024L;

    public ObservableCollection<SteamGame> Games { get; } = new();

    public ObservableCollection<UsbDisk> Disks { get; } = new();

    public event PropertyChangedEventHandler? PropertyChanged;

    public MainWindow()
    {
        InitializeComponent();
        DataContext = this;
        Loaded += MainWindow_Loaded;
    }

    private async void MainWindow_Loaded(object sender, RoutedEventArgs e)
    {
        if (!IsAdministrator())
        {
            MessageBox.Show(
                this,
                "This tool must run as administrator to repartition and format USB disks.",
                "Administrator privileges required",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }

        await RefreshAsync();
    }

    private async void RefreshButton_Click(object sender, RoutedEventArgs e)
    {
        await RefreshAsync();
    }

    private async void CreateButton_Click(object sender, RoutedEventArgs e)
    {
        if (GamesList.SelectedItem is not SteamGame game)
        {
            MessageBox.Show(this, "Select a Steam game first.", "Missing game", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        if (DisksList.SelectedItem is not UsbDisk disk)
        {
            MessageBox.Show(this, "Select a USB target disk first.", "Missing target disk", MessageBoxButton.OK, MessageBoxImage.Warning);
            return;
        }

        var confirmation = MessageBox.Show(
            this,
            $"This will delete all partitions on USB disk {disk.Number}: {disk.FriendlyName}.\n\nContinue?",
            "Erase USB disk",
            MessageBoxButton.YesNo,
            MessageBoxImage.Warning,
            MessageBoxResult.No);

        if (confirmation != MessageBoxResult.Yes)
        {
            return;
        }

        await CreateCartridgeAsync(game, disk, HashCheckBox.IsChecked == true);
    }

    private async Task RefreshAsync()
    {
        await RunUiTaskAsync(
            "Refreshing Steam games and USB disks...",
            async () =>
            {
                var games = await Task.Run(SteamScanner.FindInstalledGames);
                var disks = await DiskManager.FindUsbDisksAsync();

                Games.Clear();
                Disks.Clear();

                foreach (var game in games)
                {
                    Games.Add(game);
                }

                foreach (var disk in disks)
                {
                    Disks.Add(disk);
                }

                Log($"Found {Games.Count} Steam games and {Disks.Count} USB disks.");
            });
    }

    private async Task CreateCartridgeAsync(SteamGame game, UsbDisk disk, bool hashValidationEnabled)
    {
        await RunUiTaskAsync(
            "Creating cartridge...",
            async () =>
            {
                Log($"Formatting USB disk {disk.Number}...");
                var driveRoot = await DiskManager.FormatUsbDiskAsync(disk.Number);

                Log($"USB disk mounted as {driveRoot}");
                var libraryRoot = Path.Combine(driveRoot, "SteamLibrary");
                var steamappsPath = Path.Combine(libraryRoot, "steamapps");
                var commonPath = Path.Combine(steamappsPath, "common");
                var targetGamePath = Path.Combine(commonPath, game.InstallDir);

                Directory.CreateDirectory(steamappsPath);
                Directory.CreateDirectory(commonPath);

                Log("Copying Steam app manifest...");
                File.Copy(
                    game.ManifestPath,
                    Path.Combine(steamappsPath, $"appmanifest_{game.AppId}.acf"),
                    overwrite: true);

                Log("Copying game files...");
                await Task.Run(() => CopyDirectory(game.GamePath, targetGamePath));

                string? hashManifestId = null;

                if (hashValidationEnabled)
                {
                    hashManifestId = Guid.NewGuid().ToString("D", CultureInfo.InvariantCulture);
                    Log("Creating local SHA256 hash manifest...");
                    var manifest = await Task.Run(() => CreateHashManifest(libraryRoot, game, hashManifestId));
                    var manifestPath = WriteHashManifest(manifest);
                    Log($"Hash manifest written: {manifestPath}");
                }

                var cartridgeConfig = new CartridgeConfig
                {
                    Version = 1,
                    Name = game.Name,
                    Action = "run",
                    SteamAppId = game.AppId,
                    HashValidationEnabled = hashValidationEnabled,
                    HashManifestId = hashManifestId,
                };

                var jsonOptions = JsonOptions();
                var configPath = Path.Combine(driveRoot, "cartridge.json");
                await File.WriteAllTextAsync(configPath, JsonSerializer.Serialize(cartridgeConfig, jsonOptions) + Environment.NewLine, Encoding.UTF8);

                Log("Cartridge created successfully.");
            });
    }

    private async Task RunUiTaskAsync(string startMessage, Func<Task> action)
    {
        SetBusy(true);
        Log(startMessage);

        try
        {
            await action();
        }
        catch (Exception ex)
        {
            Log($"Error: {ex.Message}");
            MessageBox.Show(this, ex.Message, "Operation failed", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            SetBusy(false);
        }
    }

    private void SetBusy(bool isBusy)
    {
        RefreshButton.IsEnabled = !isBusy;
        CreateButton.IsEnabled = !isBusy;
        ProgressBar.IsIndeterminate = isBusy;
    }

    private void Log(string message)
    {
        var timestamp = DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.InvariantCulture);
        LogBox.AppendText($"[{timestamp}] {message}{Environment.NewLine}");
        LogBox.ScrollToEnd();
    }

    private static bool IsAdministrator()
    {
        using var identity = WindowsIdentity.GetCurrent();
        var principal = new WindowsPrincipal(identity);

        return principal.IsInRole(WindowsBuiltInRole.Administrator);
    }

    private static JsonSerializerOptions JsonOptions()
    {
        return new JsonSerializerOptions
        {
            WriteIndented = true,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        };
    }

    private static void CopyDirectory(string sourceDirectory, string targetDirectory)
    {
        var sourceInfo = new DirectoryInfo(sourceDirectory);

        if ((sourceInfo.Attributes & FileAttributes.ReparsePoint) != 0)
        {
            throw new InvalidOperationException($"Refusing to copy reparse point directory: {sourceDirectory}");
        }

        Directory.CreateDirectory(targetDirectory);

        foreach (var directory in sourceInfo.EnumerateDirectories())
        {
            if ((directory.Attributes & FileAttributes.ReparsePoint) != 0)
            {
                throw new InvalidOperationException($"Refusing to copy reparse point directory: {directory.FullName}");
            }

            CopyDirectory(directory.FullName, Path.Combine(targetDirectory, directory.Name));
        }

        foreach (var file in sourceInfo.EnumerateFiles())
        {
            if ((file.Attributes & FileAttributes.ReparsePoint) != 0)
            {
                throw new InvalidOperationException($"Refusing to copy reparse point file: {file.FullName}");
            }

            file.CopyTo(Path.Combine(targetDirectory, file.Name), overwrite: true);
        }
    }

    private static HashManifest CreateHashManifest(string libraryRoot, SteamGame game, string hashManifestId)
    {
        var files = new List<HashFileEntry>();

        foreach (var filePath in EnumerateHashableFiles(libraryRoot, game))
        {
            var fileInfo = new FileInfo(filePath);

            if ((fileInfo.Attributes & FileAttributes.ReparsePoint) != 0)
            {
                throw new InvalidOperationException($"Refusing to hash reparse point file: {filePath}");
            }

            if (fileInfo.Length >= MaxHashedFileBytes)
            {
                continue;
            }

            files.Add(
                new HashFileEntry
                {
                    RelativePath = Path.GetRelativePath(libraryRoot, filePath).Replace('\\', '/'),
                    Size = fileInfo.Length,
                    Sha256 = ComputeSha256(filePath),
                });
        }

        return new HashManifest
        {
            Version = 1,
            HashManifestId = hashManifestId,
            SteamAppId = game.AppId,
            GameName = game.Name,
            GeneratedAtUtc = DateTimeOffset.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ", CultureInfo.InvariantCulture),
            MaxFileSizeBytes = MaxHashedFileBytes,
            Files = files,
        };
    }

    private static IEnumerable<string> EnumerateHashableFiles(string libraryRoot, SteamGame game)
    {
        yield return Path.Combine(libraryRoot, "steamapps", $"appmanifest_{game.AppId}.acf");

        var gameRoot = Path.Combine(libraryRoot, "steamapps", "common", game.InstallDir);

        foreach (var file in Directory.EnumerateFiles(gameRoot, "*", SearchOption.AllDirectories))
        {
            yield return file;
        }
    }

    private static string ComputeSha256(string filePath)
    {
        using var stream = File.OpenRead(filePath);
        using var sha256 = SHA256.Create();

        return Convert.ToHexString(sha256.ComputeHash(stream)).ToLowerInvariant();
    }

    private static string WriteHashManifest(HashManifest manifest)
    {
        var hashDirectory = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "SteamGameCartridge",
            "hashes");
        Directory.CreateDirectory(hashDirectory);

        var manifestPath = Path.Combine(hashDirectory, $"{manifest.HashManifestId}.json");
        File.WriteAllText(manifestPath, JsonSerializer.Serialize(manifest, JsonOptions()) + Environment.NewLine, Encoding.UTF8);

        return manifestPath;
    }
}

public sealed class SteamGame
{
    public required string AppId { get; init; }

    public required string Name { get; init; }

    public required string InstallDir { get; init; }

    public required string LibraryPath { get; init; }

    public required string ManifestPath { get; init; }

    public required string GamePath { get; init; }

    public string DisplayName => $"{Name} ({AppId}) [{LibraryPath}]";
}

public sealed class UsbDisk
{
    public int Number { get; init; }

    public required string FriendlyName { get; init; }

    public long Size { get; init; }

    public string DisplayName => $"Disk {Number}: {FriendlyName} ({FormatBytes(Size)})";

    private static string FormatBytes(long size)
    {
        var value = (double)size;
        var units = new[] { "B", "KiB", "MiB", "GiB", "TiB" };

        foreach (var unit in units)
        {
            if (value < 1024 || unit == units[^1])
            {
                return $"{value:0.0} {unit}";
            }

            value /= 1024;
        }

        return $"{size} B";
    }
}

public sealed class CartridgeConfig
{
    [JsonPropertyName("version")]
    public int Version { get; init; }

    [JsonPropertyName("name")]
    public required string Name { get; init; }

    [JsonPropertyName("action")]
    public required string Action { get; init; }

    [JsonPropertyName("steamAppId")]
    public required string SteamAppId { get; init; }

    [JsonPropertyName("hashValidationEnabled")]
    public bool HashValidationEnabled { get; init; }

    [JsonPropertyName("hashManifestId")]
    public string? HashManifestId { get; init; }
}

public sealed class HashManifest
{
    [JsonPropertyName("version")]
    public int Version { get; init; }

    [JsonPropertyName("hashManifestId")]
    public required string HashManifestId { get; init; }

    [JsonPropertyName("steamAppId")]
    public required string SteamAppId { get; init; }

    [JsonPropertyName("gameName")]
    public required string GameName { get; init; }

    [JsonPropertyName("generatedAtUtc")]
    public required string GeneratedAtUtc { get; init; }

    [JsonPropertyName("maxFileSizeBytes")]
    public long MaxFileSizeBytes { get; init; }

    [JsonPropertyName("files")]
    public required List<HashFileEntry> Files { get; init; }
}

public sealed class HashFileEntry
{
    [JsonPropertyName("relativePath")]
    public required string RelativePath { get; init; }

    [JsonPropertyName("size")]
    public long Size { get; init; }

    [JsonPropertyName("sha256")]
    public required string Sha256 { get; init; }
}

public static class SteamScanner
{
    public static IReadOnlyList<SteamGame> FindInstalledGames()
    {
        var games = new List<SteamGame>();

        foreach (var libraryPath in FindSteamLibraries())
        {
            var steamappsPath = Path.Combine(libraryPath, "steamapps");

            if (!Directory.Exists(steamappsPath))
            {
                continue;
            }

            foreach (var manifestPath in Directory.EnumerateFiles(steamappsPath, "appmanifest_*.acf"))
            {
                Dictionary<string, object?> manifest;

                try
                {
                    manifest = VdfParser.ParseFile(manifestPath);
                }
                catch
                {
                    continue;
                }

                if (VdfParser.GetObject(manifest, "AppState") is not { } appState)
                {
                    continue;
                }

                var appId = VdfParser.GetString(appState, "appid");
                var name = VdfParser.GetString(appState, "name");
                var installDir = VdfParser.GetString(appState, "installdir");

                if (
                    string.IsNullOrWhiteSpace(appId) ||
                    !Regex.IsMatch(appId, "^[1-9][0-9]{0,19}$") ||
                    string.IsNullOrWhiteSpace(name) ||
                    string.IsNullOrWhiteSpace(installDir) ||
                    Path.IsPathRooted(installDir) ||
                    installDir.Contains('/') ||
                    installDir.Contains('\\') ||
                    installDir.Contains(':'))
                {
                    continue;
                }

                var gamePath = Path.Combine(steamappsPath, "common", installDir);

                if (!Directory.Exists(gamePath))
                {
                    continue;
                }

                games.Add(
                    new SteamGame
                    {
                        AppId = appId,
                        Name = name.Trim(),
                        InstallDir = installDir,
                        LibraryPath = libraryPath,
                        ManifestPath = manifestPath,
                        GamePath = gamePath,
                    });
            }
        }

        return games
            .OrderBy(game => game.Name, StringComparer.CurrentCultureIgnoreCase)
            .ToList();
    }

    private static IEnumerable<string> FindSteamLibraries()
    {
        var libraries = new List<string>();

        foreach (var steamRoot in FindSteamRoots())
        {
            var libraryFoldersPath = Path.Combine(steamRoot, "steamapps", "libraryfolders.vdf");

            if (!File.Exists(libraryFoldersPath))
            {
                continue;
            }

            libraries.Add(steamRoot);

            Dictionary<string, object?> parsed;

            try
            {
                parsed = VdfParser.ParseFile(libraryFoldersPath);
            }
            catch
            {
                continue;
            }

            if (VdfParser.GetObject(parsed, "libraryfolders") is not { } folders)
            {
                continue;
            }

            foreach (var value in folders.Values)
            {
                string? libraryPath = null;

                if (value is Dictionary<string, object?> folderObject)
                {
                    libraryPath = VdfParser.GetString(folderObject, "path");
                }
                else if (value is string folderPath)
                {
                    libraryPath = folderPath;
                }

                if (!string.IsNullOrWhiteSpace(libraryPath) && Directory.Exists(libraryPath))
                {
                    libraries.Add(libraryPath);
                }
            }
        }

        return libraries
            .Select(path => Path.GetFullPath(path))
            .Distinct(StringComparer.OrdinalIgnoreCase);
    }

    private static IEnumerable<string> FindSteamRoots()
    {
        var candidates = new List<string>();

        AddRegistryPath(candidates, Registry.CurrentUser, @"Software\Valve\Steam");
        AddRegistryPath(candidates, Registry.LocalMachine, @"SOFTWARE\WOW6432Node\Valve\Steam");
        AddRegistryPath(candidates, Registry.LocalMachine, @"SOFTWARE\Valve\Steam");

        var programFilesX86 = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86);
        var programFiles = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);

        if (!string.IsNullOrWhiteSpace(programFilesX86))
        {
            candidates.Add(Path.Combine(programFilesX86, "Steam"));
        }

        if (!string.IsNullOrWhiteSpace(programFiles))
        {
            candidates.Add(Path.Combine(programFiles, "Steam"));
        }

        return candidates
            .Where(path => !string.IsNullOrWhiteSpace(path))
            .Select(path => path.Replace('/', '\\'))
            .Where(Directory.Exists)
            .Distinct(StringComparer.OrdinalIgnoreCase);
    }

    private static void AddRegistryPath(ICollection<string> candidates, RegistryKey root, string subKey)
    {
        using var key = root.OpenSubKey(subKey);

        if (key is null)
        {
            return;
        }

        foreach (var valueName in new[] { "SteamPath", "InstallPath" })
        {
            if (key.GetValue(valueName) is string value && !string.IsNullOrWhiteSpace(value))
            {
                candidates.Add(value);
            }
        }
    }
}

public static class DiskManager
{
    public static async Task<IReadOnlyList<UsbDisk>> FindUsbDisksAsync()
    {
        const string command =
            "$ErrorActionPreference='Stop'; " +
            "Get-Disk | Where-Object { $_.BusType -eq 'USB' } | " +
            "Select-Object Number,FriendlyName,Size | ConvertTo-Json -Depth 3";
        var output = await RunPowerShellAsync(command);

        if (string.IsNullOrWhiteSpace(output))
        {
            return Array.Empty<UsbDisk>();
        }

        using var document = JsonDocument.Parse(output);
        var disks = new List<UsbDisk>();

        if (document.RootElement.ValueKind == JsonValueKind.Array)
        {
            foreach (var element in document.RootElement.EnumerateArray())
            {
                disks.Add(ParseDisk(element));
            }
        }
        else if (document.RootElement.ValueKind == JsonValueKind.Object)
        {
            disks.Add(ParseDisk(document.RootElement));
        }

        return disks.OrderBy(disk => disk.Number).ToList();
    }

    public static async Task<string> FormatUsbDiskAsync(int diskNumber)
    {
        var command =
            "$ErrorActionPreference='Stop'; " +
            $"$disk=Get-Disk -Number {diskNumber.ToString(CultureInfo.InvariantCulture)}; " +
            "if($disk.BusType -ne 'USB'){ throw 'Selected disk is not a USB disk.' }; " +
            $"Set-Disk -Number {diskNumber.ToString(CultureInfo.InvariantCulture)} -IsReadOnly $false; " +
            $"Set-Disk -Number {diskNumber.ToString(CultureInfo.InvariantCulture)} -IsOffline $false; " +
            $"Clear-Disk -Number {diskNumber.ToString(CultureInfo.InvariantCulture)} -RemoveData -RemoveOEM -Confirm:$false; " +
            $"Initialize-Disk -Number {diskNumber.ToString(CultureInfo.InvariantCulture)} -PartitionStyle GPT; " +
            $"$partition=New-Partition -DiskNumber {diskNumber.ToString(CultureInfo.InvariantCulture)} -UseMaximumSize -AssignDriveLetter; " +
            "$partition | Format-Volume -FileSystem exFAT -NewFileSystemLabel 'STEAM_CART' -Force -Confirm:$false | Out-Null; " +
            "$volume=$partition | Get-Volume; " +
            "Write-Output ($volume.DriveLetter + ':\\')";
        var output = await RunPowerShellAsync(command);
        var driveRoot = output.Trim().Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries).LastOrDefault();

        if (string.IsNullOrWhiteSpace(driveRoot) || !Directory.Exists(driveRoot))
        {
            throw new InvalidOperationException("Formatted USB volume was not mounted with a drive letter.");
        }

        return driveRoot;
    }

    private static UsbDisk ParseDisk(JsonElement element)
    {
        return new UsbDisk
        {
            Number = element.GetProperty("Number").GetInt32(),
            FriendlyName = element.TryGetProperty("FriendlyName", out var friendlyName)
                ? friendlyName.GetString() ?? "USB disk"
                : "USB disk",
            Size = element.TryGetProperty("Size", out var size) ? size.GetInt64() : 0,
        };
    }

    private static async Task<string> RunPowerShellAsync(string command)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = "powershell.exe",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true,
        };
        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("Bypass");
        startInfo.ArgumentList.Add("-Command");
        startInfo.ArgumentList.Add(command);

        using var process = Process.Start(startInfo)
            ?? throw new InvalidOperationException("Failed to start PowerShell.");
        var output = await process.StandardOutput.ReadToEndAsync();
        var error = await process.StandardError.ReadToEndAsync();
        await process.WaitForExitAsync();

        if (process.ExitCode != 0)
        {
            throw new InvalidOperationException(string.IsNullOrWhiteSpace(error) ? output : error);
        }

        return output;
    }
}

public static class VdfParser
{
    public static Dictionary<string, object?> ParseFile(string path)
    {
        return Parse(File.ReadAllText(path, Encoding.UTF8));
    }

    public static string? GetString(Dictionary<string, object?> values, string key)
    {
        return values.TryGetValue(key, out var value) ? value as string : null;
    }

    public static Dictionary<string, object?>? GetObject(Dictionary<string, object?> values, string key)
    {
        return values.TryGetValue(key, out var value) ? value as Dictionary<string, object?> : null;
    }

    private static Dictionary<string, object?> Parse(string text)
    {
        var tokens = Tokenize(text);
        var index = 0;

        Dictionary<string, object?> ParseObject(bool expectClosingBrace)
        {
            var result = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);

            while (index < tokens.Count)
            {
                var token = tokens[index];

                if (token == "}")
                {
                    if (!expectClosingBrace)
                    {
                        throw new FormatException("Unexpected closing brace.");
                    }

                    index++;
                    return result;
                }

                if (token == "{")
                {
                    throw new FormatException("Unexpected opening brace.");
                }

                var key = token;
                index++;

                if (index >= tokens.Count)
                {
                    throw new FormatException("Missing VDF value.");
                }

                token = tokens[index];

                if (token == "{")
                {
                    index++;
                    result[key] = ParseObject(true);
                }
                else if (token == "}")
                {
                    throw new FormatException("Missing VDF value.");
                }
                else
                {
                    result[key] = token;
                    index++;
                }
            }

            if (expectClosingBrace)
            {
                throw new FormatException("Missing closing brace.");
            }

            return result;
        }

        return ParseObject(false);
    }

    private static List<string> Tokenize(string text)
    {
        var tokens = new List<string>();
        var index = 0;

        while (index < text.Length)
        {
            var character = text[index];

            if (char.IsWhiteSpace(character))
            {
                index++;
                continue;
            }

            if (character == '/' && index + 1 < text.Length && text[index + 1] == '/')
            {
                index += 2;

                while (index < text.Length && text[index] is not '\r' and not '\n')
                {
                    index++;
                }

                continue;
            }

            if (character is '{' or '}')
            {
                tokens.Add(character.ToString());
                index++;
                continue;
            }

            if (character == '"')
            {
                index++;
                var value = new StringBuilder();

                while (index < text.Length)
                {
                    character = text[index];

                    if (character == '\\' && index + 1 < text.Length)
                    {
                        index++;
                        value.Append(text[index]);
                        index++;
                        continue;
                    }

                    if (character == '"')
                    {
                        index++;
                        break;
                    }

                    value.Append(character);
                    index++;
                }

                tokens.Add(value.ToString());
                continue;
            }

            var start = index;

            while (
                index < text.Length &&
                !char.IsWhiteSpace(text[index]) &&
                text[index] is not '{' and not '}')
            {
                index++;
            }

            tokens.Add(text[start..index]);
        }

        return tokens;
    }
}
