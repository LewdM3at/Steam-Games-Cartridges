# Disclaimer

This project is a hobby experiment and is not an official Steam product.

Automatic launching depends on your operating system settings and security policies. Some systems may require additional configuration for automounting drives or opening Steam URLs automatically.

The launcher does not execute scripts or executable files from cartridges. It only reads a validated `cartridge.json` file and starts a Steam URL that is built by the installed runner. This reduces the risk from untrusted removable storage, but it does not make removable drives generally safe. Operating-system autoplay settings, manually opened files, or unrelated software can still introduce risk.

# Steam Games Cartridges

<img width="970" height="546" alt="JTDUMcuDBav3BEspNBMw6A-970-80 jpg" src="https://github.com/user-attachments/assets/8c0a8d2b-ce5a-4aa5-9bac-5805016db31f" />

<br/><br/>
Physical game cartridges for your Steam library using 2.5" SATA SSDs.

Turn your digital Steam games into something that feels physical: insert a cartridge, and your PC automatically detects it and launches the configured Steam action.

Each cartridge is a simple storage device containing a small JSON configuration file. When inserted, the system detects the cartridge, validates the JSON, and opens the corresponding Steam game or details page.

## 3D-Print Files
STEP-Files are available over at MakerWorld: [MakerWorld](https://makerworld.com/en/models/3057977-2-5-ssd-dock-cartridge-system#profileId-3440827)

## Quickstart
### Linux

Clone the repository:

```bash
git clone https://github.com/LewdM3at/Steam-Games-Cartridges.git
```

Enter the project directory:

```bash
cd Steam-Games-Cartridges
```

Run the installer:

```bash
sudo ./setup-linux.sh
```

The installer will install the required udev rule, systemd service, and launcher helper. The Linux helper uses `python3` to parse and validate `cartridge.json`.

To remove the installation:

```bash
sudo ./uninstall-linux.sh
```

### Windows

Download the repo:
1. Click Code -> Download ZIP
2. Extract it

Open the extracted directory and keep going until you see this repo's files.

Copy the folder's full path.

Start PowerShell as Administrator.

Run:

```bash
cd <paste the full path here>
```

Run the installer:

```bash
.\setup-windows.ps1
```

The installer will create the background cartridge monitor using Windows Task Scheduler.

If PowerShell blocks script execution, run:

```bash
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

and run the installer again.

To remove the installation:

```bash
.\uninstall-windows.ps1
```

## Supported Storage

The project is designed around **2.5" SATA SSDs**.

However, the same concept may work with other storage devices such as:

- SD cards
- USB flash drives
- External HDDs
- Other removable storage

Compatibility with other storage types is **not guaranteed** and depends on your operating system, filesystem, automount configuration, and hardware.

## Cartridge Format

Each cartridge must contain `cartridge.json` and a Steam library folder named `SteamLibrary` at the root level:

```json
{
  "version": 1,
  "name": "Cyberpunk 2077",
  "action": "run",
  "steamAppId": "1091500",
  "hashValidationEnabled": false
}
```

Expected cartridge layout:

```text
SSD/
├── cartridge.json
└── SteamLibrary/
    └── steamapps/
        ├── appmanifest_1091500.acf
        └── common/
            └── Cyberpunk 2077/
```

Supported fields:

- `version`: required, must be `1`.
- `name`: optional display/logging name, max 80 characters, no control or Unicode format characters.
- `action`: optional Steam action. Allowed values are `run` and `details`. Defaults to `run`.
- `steamAppId`: required positive numeric Steam app id. Use a JSON string to preserve large IDs exactly.
- `hashValidationEnabled`: required boolean created by the cartridge tools. If `true`, the runner validates local SHA256 hashes before starting Steam.
- `hashManifestId`: required UUID when `hashValidationEnabled` is `true`. This identifies a local hash manifest stored on the user's system, not on the cartridge.

Security rules:

- The JSON file must be UTF-8 and no larger than 16 KiB.
- Unknown JSON fields are rejected.
- `steamAppId` may only contain digits and cannot start with `0`.
- The runner validates `SteamLibrary/steamapps/appmanifest_<steamAppId>.acf` before launching.
- The app manifest must contain the same `appid` and a safe single-directory `installdir`.
- The runner registers the cartridge's `SteamLibrary` in Steam's `libraryfolders.vdf` before launching.
- If hash validation is enabled, hashes are loaded from the user's local profile and compared before launch.
- Only files smaller than 100 MiB are hashed. Files at or above that size are copied but not hash-checked.
- Hash checking fails if a listed file is missing/changed or an unexpected file below 100 MiB appears in the selected game directory.
- The runners never directly execute `launch.sh`, `launch.ps1`, `.exe`, `.bat`, `.cmd`, or any other file from the cartridge.
- When `action` is `run`, Steam will launch the installed game from the registered cartridge library. A cartridge with modified game files can therefore still execute modified game code through Steam.
- The runners never read shell commands or arbitrary URLs from the cartridge.

The installed runner builds the Steam URL internally from the validated values:

- `run`: `steam://run/<steamAppId>`
- `details`: `steam://nav/games/details/<steamAppId>`

Steam still controls the actual launch. If the same app is installed in another Steam library, Steam may prefer that existing installation. For cartridge-only behavior, keep the cartridge copy as the installed copy Steam sees for that app.

## Cartridge Creation Tools

### Linux

Use the Linux creator script:

```bash
sudo ./linux/create-cartridge.sh
```

The script:

- Lists installed Steam games by the Steam display name from `appmanifest_*.acf`.
- Lists only USB disks reported by `lsblk` with transport `usb`.
- Deletes the selected USB disk's partition table.
- Creates one GPT exFAT partition and formats it as `STEAM_CART`.
- Copies only the selected game's app manifest and game directory into `SteamLibrary`.
- Optionally creates a local SHA256 hash manifest for files below 100 MiB.
- Writes `cartridge.json` with `hashValidationEnabled` matching the user's choice.

Required Linux tools: `python3`, `lsblk`, `wipefs`, `parted`, `partprobe`, `udevadm`, `mkfs.exfat`, `mount`, and `umount`.

Local hash manifests are stored under:

```text
~/.local/share/SteamGameCartridge/hashes/<hashManifestId>.json
```

### Windows

The Windows creator is a WPF/.NET project in:

```text
windows/CartridgeCreator/
```

Build it on Windows with:

```powershell
dotnet publish .\windows\CartridgeCreator\CartridgeCreator.csproj -c Release
```

The program requests administrator privileges and:

- Lists installed Steam games by the Steam display name from `appmanifest_*.acf`.
- Lists USB disks from Windows Storage.
- Deletes the selected USB disk's partition table.
- Creates one GPT exFAT partition and formats it as `STEAM_CART`.
- Copies only the selected game's app manifest and game directory into `SteamLibrary`.
- Provides a checkbox for local SHA256 hash manifest creation.
- Writes `cartridge.json` with `hashValidationEnabled` matching the checkbox.

Local hash manifests are stored under:

```text
%LOCALAPPDATA%\SteamGameCartridge\hashes\<hashManifestId>.json
```

## How It Works

### Linux

The Linux version uses three components:

- **udev rule**<br>
The udev rule detects when a new storage partition is connected.<br>
Its only job is to notify systemd that a game cartridge may have been inserted.<br>
It does not execute the cartridge directly.<br>

- **systemd service**<br>
A systemd template service is used to handle cartridge launches.<br>
The template allows the same service to work with any inserted device.<br>
The service starts the launcher helper and passes the detected device name.<br>

- **cartridge-launcher-helper**<br>
The helper script waits for the desktop environment to mount the drive, then searches the cartridge root for `cartridge.json` and `SteamLibrary`.<br>
If found, it validates the JSON, validates the Steam app manifest, registers the cartridge's Steam library, and opens the configured Steam action.<br>
Example cartridge:<br>
SSD<br>
└── cartridge.json<br>
└── SteamLibrary<br>

---

### Windows

The Windows version uses two components:

- **Task Scheduler**<br>
The installer creates a scheduled task that starts the cartridge monitor when the user logs in.<br>
The task keeps the monitor running silently in the background.<br>

- **cartridge-monitor.ps1**<br>
The PowerShell monitor watches for newly inserted storage devices.<br>
When a new drive is detected, it checks the root of the cartridge for `cartridge.json` and `SteamLibrary`.<br>
If found, it validates the JSON, validates the Steam app manifest, registers the cartridge's Steam library, and opens the configured Steam action.<br>
Example cartridge:<br>
SSD<br>
└── cartridge.json<br>
└── SteamLibrary<br>
