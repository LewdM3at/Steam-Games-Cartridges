<div align="center">

<img src="docs/icon.png" width="96" alt="" />


<a href="https://ko-fi.com/harrybma">Support my work!</a>


# NVMe Game Cartridges

**Turn M.2 2230 NVMe drives into physical game cartridges.**
Plug one in and a launcher appears with the game's cover art and two buttons.

<img width="420" alt="The cartridge launcher: cover art filling the window, the game title, and Play and Eject buttons" src="docs/launcher.png" />

</div>

---

## The idea

A cartridge is a small NVMe drive in a pocketable enclosure with one game on it.
Push it into a USB-C port; the launcher opens showing what's on it. Press **Play**
to start the game, or **Eject** to power the drive down and pull it out.

It's the console-cartridge feeling, using hardware that already exists — and it
genuinely offloads a game off your internal disk, which is the practical half of
the appeal.

Each cartridge is just a drive with a `cartridge.conf` text file at its root.
There are no scripts to write and nothing to allowlist.

## Hardware

Built around **M.2 2230 NVMe drives** — the short ones from Steam Decks and
Surface tablets — in compact aluminium USB enclosures.

| | |
|---|---|
| **Drives** | 10 × 128 GB M.2 2230 NVMe |
| **Enclosures** | ITGZ aluminium compact M.2 2230 case, USB 3.2 Gen 2 (10 Gbps), passive auto-cooling |
| **Filesystem** | exFAT, so a cartridge works on both Windows and Linux |

2230 is the right form factor for this: the drive plus enclosure is roughly the
size of a USB stick, so a shelf of ten cartridges takes almost no room. 128 GB
holds most single games, and the whole point of a cartridge is that it carries
one thing.

10 Gbps over USB 3.2 Gen 2 is around 1 GB/s in practice — fast enough to play
directly off the cartridge rather than treating it as cold storage. The aluminium
body doubles as the heatsink, which matters when a game is streaming assets off
it for hours.

Nothing here is specific to NVMe or to 2230. Any removable storage your OS will
automount works: 2.5" SATA SSDs in a dock, SD cards, USB sticks, external HDDs.
The form factor is a comfort choice, not a technical one.

> **Photos of the physical cartridges are not in the repository yet.** Drop them
> in `docs/` and link them here — the screenshots below are the software.

## How it works

```
drive plugged in
      │
      ├─ Linux    udev rule ──▶ systemd unit ──▶ helper waits for the mount
      └─ Windows  watcher (resident, ~2 MB) sees the volume arrive
      │
      ▼
is there a cartridge.conf at the root?   ──no──▶  nothing happens
      │ yes
      ▼
launcher opens with the cover art
      │
      ├─ Play   ──▶ starts what cartridge.conf names, then closes
      └─ Eject  ──▶ flushes, unmounts, powers the drive down
```

**Nothing on a cartridge is executed automatically.** The launcher shows you what
it found and waits — pressing Play is the gate. That is the whole security model,
and it is why there is no trust list or allowlist to maintain.

### Idle cost

The point of a thing that waits all day for a drive is that it costs nothing
while it waits.

| | Idle |
|---|---|
| **Linux** | **Nothing resident.** udev is already part of the OS; the rule adds no process. |
| **Windows** | **One process, ~2 MB, 0% CPU.** `pc-cartridge-watcher.exe` blocks on the Windows message queue — no polling, no timer. |

The launcher is a webview, so it is not small *while it is on screen* — expect
around 100 MB for the few seconds it is up, then it exits and gives all of it
back. There is no tray icon and no background service for the UI.

## The launcher

The window is 420 × 560 — the 3:4 of a cover — and the artwork fills it. Only
three things sit on top: what the cartridge is, Play, and Eject.

<img width="420" alt="The launcher showing Cinder &amp; Salt with Play and Eject" src="docs/launcher.png" />
<img width="420" alt="The details sheet, showing mount point, launch target and cover path" src="docs/launcher-details.png" />

The accent colour is sampled from the cover art at load, so the Play button
belongs to whatever game is in the dock. Everything the launcher knows beyond
the title lives behind the gear, because you rarely need it.

| Key | Action |
|-----|--------|
| `Enter` | Play |
| `E` | Eject |
| `I` | Details |
| `Esc` | Close details, or dismiss |

## Making a cartridge

Run the installer menu and choose **Create a cartridge**, or start it directly:

```bash
pc-cartridge-launcher --create
```

<img width="760" alt="The create-cartridge wizard: searchable game list on the left, cover preview, drive picker and options on the right" src="docs/wizard.png" />

The wizard lists everything installed. **Playnite** is read first when present —
one list covering Steam, GOG, Epic, Xbox, Ubisoft, itch and emulators — and
Steam's own manifests are read too, which is the only source on Linux. Cover art
comes from whichever cache the game came from, so **nothing is fetched**; the
wizard works with no network at all.

Pick a game, pick the drive, choose what goes on it, press Write.

### What it can put on the cartridge

**The launcher files** — `cartridge.conf` and the cover art. Always written.

**The drive's name and icon** — an `autorun.inf` with `label=`, so Explorer shows
*HOLLOW KNIGHT* rather than *Removable Disk (D:)*. The `icon=` key is written
when a usable `.ico` can be produced; Explorer will not take a JPEG, so a
Steam-sourced cover usually leaves the default icon in place.

**The game itself**, by whichever route suits where it came from:

<img width="760" alt="The wizard copying a GOG game, with a dropdown choosing which executable Play should start" src="docs/wizard-portable.png" />

- *Steam games* go to `steamapps/` and the drive is registered in Steam's
  `libraryfolders.vdf`, so Steam plays **from the cartridge** rather than your
  internal copy. Close Steam first — it rewrites that file when it exits.
- *Everything else* — GOG, itch, emulator builds, anything Playnite records an
  install folder for — is copied to `Games/<title>/` and Play is pointed at a
  file inside it. No launcher in the middle. The wizard ranks the executables it
  finds (Playnite's own play action first, then a binary named after the game;
  uninstallers and redistributables sink) and offers the best guess, which you
  can change.

**Games in no library at all** can be entered by hand with any supported URI or a
path on the cartridge.

### Formatting erases the drive

<img width="760" alt="The wizard with formatting enabled: a field asking you to type the drive's current name, with Write disabled until it matches" src="docs/wizard-format.png" />

Formatting to exFAT is opt-in per cartridge and gated four ways: the target must
be on the removable-drive allowlist the wizard re-derives itself, it must not be
the system drive, you must type the drive's **current** name back exactly, and
Write stays disabled until you have. The backend re-checks all of it — it never
trusts the window's idea of where to write.

## Cartridge format

A cartridge is a text file and some art, so you can make one by hand. Copy
`cartridge.conf.example` to the root of the drive as `cartridge.conf`:

```ini
executable=steam://rungameid/1091500
title=Cyberpunk 2077
cover=cover.jpg
```

Portrait art at 3:4 fills the launcher window exactly. A finished cartridge:

```
CARTRIDGE/
├── cartridge.conf
├── cover.jpg
├── autorun.inf          drive name and icon in Explorer
├── Games/               a copied non-Steam game
│   └── Tunic/
│       └── TUNIC.exe
└── steamapps/           a copied Steam game
    ├── appmanifest_367520.acf
    └── common/Hollow Knight/
```

`executable=` takes any URI the OS can handle — `steam://`, `heroic://`, `gog://`,
`epic://`, `playnite://`, `lutris://`, `http://`, `https://` — or a path to a file
on the cartridge. See `cartridge.conf.example` for every key.

A classic `autorun.inf` is also read, for `label` and `icon` only. Its `open=`
and `shellexecute=` keys are deliberately ignored: Windows has ignored them on
non-optical media since Windows 7, and they are the oldest autorun malware vector
there is.

## Setup

### Prerequisites

Rust (stable) and Node 18+, plus a C toolchain.

```bash
# Linux
sudo apt install libgtk-3-dev libwebkit2gtk-4.1-dev librsvg2-dev libssl-dev

# Windows: Visual Studio Build Tools, "Desktop development with C++"
```

### Build and install

```bash
git clone https://github.com/HarryBMa/nvme-cartridge.git
cd nvme-cartridge
cd tauri-ui && npm install && npm run build && cd ..
```

**Linux**

```bash
./cartridge-linux.sh          # → 1) Install
```

Installs the udev rule, the systemd template unit, the mount helper and the
launcher binary.

**Windows**

```powershell
cd watcher; cargo build --release; cd ..
# Right-click cartridge-windows.ps1 → Run with PowerShell → 1) Install
```

Installs the watcher and launcher to `%LOCALAPPDATA%\PC-Cartridge-System` and
registers a logon task.

**Platforms:** Windows and Linux. macOS is not supported — there is no watcher,
no installer and no icon set for it, so rather than ship something half-working
the macOS branches were removed.

## Security

Nothing on a cartridge runs without a click. That is the model. Earlier versions
of this idea auto-executed a `launch.sh` on insert, which needed a SHA-256
allowlist to be safe at all; removing the auto-execution removed the need for the
allowlist along with it.

- **Play runs what `cartridge.conf` says.** If `executable=` names a binary on the
  drive, Play runs that binary. On your own cartridges that is the feature. On a
  drive someone hands you, read the conf first — or keep to `steam://`-style URIs,
  where the argument goes to a program you already trust.
- **The launcher window cannot read your disk.** The webview has no filesystem
  access and no command that takes a path. The cover is read in Rust, from a path
  confined to the cartridge, and passed in as a `data:` URI.
- **Nothing is fetched.** Fonts are bundled, the cover is inlined, and the
  content-security policy is `default-src 'self'`.
- **Titles are text, never markup.** They come off an untrusted volume and are
  inserted with `textContent`.
- **Eject asks twice** when the game lives on the cartridge, since pulling a drive
  a running game is reading from is a different mistake to pulling one that holds
  only a text file.

### Cartridges in Steam's library list

A cartridge you copied a Steam game onto is registered in `libraryfolders.vdf`,
labelled `PC Cartridge`. Those entries are never removed automatically: a
cartridge is *meant* to spend most of its life unplugged, so a missing folder is
the normal state rather than stale cruft. When you reformat or repurpose one, the
wizard offers **Remove this drive from Steam's library list**. Steam must be
closed.

## Working on it

The logic lives in `core/` (crate `cartridge-core`), deliberately free of any UI
dependency, so the tests run anywhere:

```bash
cargo test --manifest-path core/Cargo.toml
```

That split is the point: the Tauri binary cannot be compiled without webkit2gtk
and a display, so tests living inside it could not run in CI or on a
contributor's machine.

CI runs that suite plus clippy and rustfmt, compiles the watcher on Linux and
Windows, `cargo check`s the launcher on both, parses the frontend JavaScript, and
verifies every element the scripts reach for exists in the HTML — the UI ships
unbundled, so a missing id is a runtime crash rather than a build error.

```
cartridge-linux.sh          installer menu (Linux)
cartridge-windows.ps1       installer menu (Windows)
cartridge.conf.example      the one file a cartridge needs
core/                       cartridge logic, no UI — this is where the tests are
linux/                      udev rule, systemd units, mount + eject helpers
windows/                    install / uninstall / eject scripts
watcher/                    resident volume watcher (Windows only, Rust)
tauri-ui/                   one binary, two windows (Tauri 2 + Rust, no framework)
tools/                      icon generation, DOM-id check
docs/                       screenshots
```

When a cartridge does not open the launcher, the logs are the first place to
look: `%LOCALAPPDATA%\PC-Cartridge-System\watcher.log` on Windows,
`~/.local/state/pc-cartridge-system/helper.log` on Linux.

## Uninstall

Run the installer menu and choose Uninstall. It removes the udev rule and systemd
units on Linux, or the logon task and install folder on Windows.

## Thanks

This project began as a fork of
**[LewdM3at/PC-Cartridge-System](https://github.com/LewdM3at/PC-Cartridge-System)**,
which had the original idea and the first working implementation: the udev rule,
the systemd template unit and the Windows monitor that make insert-detection work
at all. The shape of the Linux side is still recognisably theirs.

That project is built around 2.5" SATA SSDs and has 3D-printable cartridge shells
on [MakerWorld](https://makerworld.com/en/models/3057977-2-5-ssd-dock-cartridge-system) — worth a look if you
want the full physical-cartridge build rather than a pocket enclosure.

This fork diverges in a few ways: 2230 NVMe rather than 2.5" SATA, a Tauri
launcher and a create-cartridge wizard instead of per-game shell scripts, and a
click-to-play model in place of the auto-execute-plus-allowlist one.

## Licence

MIT, inherited from the upstream project. See [`LICENSE`](LICENSE) — the original
copyright notice is retained as the licence requires.

## Disclaimer

A hobby project, not affiliated with Valve, Steam, Playnite or ITGZ.

Auto-detection depends on your OS automounting removable drives. Some setups need
that configured before any of this works.

Use at your own risk.
