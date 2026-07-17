#!/usr/bin/env python3

import datetime as _datetime
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import uuid
from collections import OrderedDict
from pathlib import Path

MAX_HASHED_FILE_BYTES = 100 * 1024 * 1024
CARTRIDGE_LABEL = "STEAM_CART"


def fail(message):
    print(f"Error: {message}", file=sys.stderr)
    raise SystemExit(1)


def run(command, **kwargs):
    return subprocess.run(command, check=True, text=True, **kwargs)


def run_capture(command):
    return run(command, stdout=subprocess.PIPE).stdout


def require_tool(name):
    if shutil.which(name) is None:
        fail(f"Missing required tool: {name}")


def real_user_context():
    username = os.environ.get("SUDO_USER") or os.environ.get("USER")

    if not username:
        fail("Cannot determine target user")

    uid = int(os.environ.get("SUDO_UID", os.getuid()))
    gid = int(os.environ.get("SUDO_GID", os.getgid()))
    home = Path(os.path.expanduser(f"~{username}"))

    if not home.is_dir():
        fail(f"Cannot determine home directory for {username}")

    return username, uid, gid, home


def tokenize_vdf(text):
    tokens = []
    index = 0

    while index < len(text):
        character = text[index]

        if character.isspace():
            index += 1
            continue

        if character == "/" and index + 1 < len(text) and text[index + 1] == "/":
            index += 2

            while index < len(text) and text[index] not in "\r\n":
                index += 1

            continue

        if character in "{}":
            tokens.append(character)
            index += 1
            continue

        if character == '"':
            index += 1
            value = []

            while index < len(text):
                character = text[index]

                if character == "\\" and index + 1 < len(text):
                    index += 1
                    value.append(text[index])
                    index += 1
                    continue

                if character == '"':
                    index += 1
                    break

                value.append(character)
                index += 1
            else:
                fail("VDF file contains an unterminated string")

            tokens.append("".join(value))
            continue

        start = index

        while index < len(text) and not text[index].isspace() and text[index] not in "{}":
            index += 1

        tokens.append(text[start:index])

    return tokens


def parse_vdf(text):
    tokens = tokenize_vdf(text)
    index = 0

    def parse_object(expect_closing_brace):
        nonlocal index
        result = OrderedDict()

        while index < len(tokens):
            token = tokens[index]

            if token == "}":
                if not expect_closing_brace:
                    fail("VDF file contains an unexpected closing brace")

                index += 1
                return result

            if token == "{":
                fail("VDF file contains an unexpected opening brace")

            key = token
            index += 1

            if index >= len(tokens):
                fail("VDF file is missing a value")

            token = tokens[index]

            if token == "{":
                index += 1
                value = parse_object(True)
            elif token == "}":
                fail("VDF file is missing a value")
            else:
                value = token
                index += 1

            result[key] = value

        if expect_closing_brace:
            fail("VDF file is missing a closing brace")

        return result

    return parse_object(False)


def get_key(mapping, key):
    for candidate, value in mapping.items():
        if candidate.lower() == key.lower():
            return value

    return None


def read_vdf(path):
    with open(path, "r", encoding="utf-8", errors="replace") as input_file:
        return parse_vdf(input_file.read())


def steam_libraryfolders_candidates(home):
    return [
        home / ".steam/steam/steamapps/libraryfolders.vdf",
        home / ".local/share/Steam/steamapps/libraryfolders.vdf",
        home / ".var/app/com.valvesoftware.Steam/data/Steam/steamapps/libraryfolders.vdf",
    ]


def discover_steam_libraries(home):
    libraries = []

    for libraryfolders_path in steam_libraryfolders_candidates(home):
        if not libraryfolders_path.is_file():
            continue

        base_library = libraryfolders_path.parent.parent
        libraries.append(base_library)

        parsed = read_vdf(libraryfolders_path)
        folders = get_key(parsed, "libraryfolders")

        if not isinstance(folders, dict):
            continue

        for value in folders.values():
            library_path = None

            if isinstance(value, dict):
                path_value = get_key(value, "path")

                if isinstance(path_value, str):
                    library_path = Path(path_value)
            elif isinstance(value, str):
                library_path = Path(value)

            if library_path and library_path.is_dir():
                libraries.append(library_path)

    unique = []
    seen = set()

    for library in libraries:
        resolved = str(library.resolve())

        if resolved not in seen:
            seen.add(resolved)
            unique.append(library)

    return unique


def discover_games(home):
    games = []

    for library in discover_steam_libraries(home):
        steamapps = library / "steamapps"

        if not steamapps.is_dir():
            continue

        for manifest_path in sorted(steamapps.glob("appmanifest_*.acf")):
            parsed = read_vdf(manifest_path)
            app_state = get_key(parsed, "AppState")

            if not isinstance(app_state, dict):
                continue

            appid = get_key(app_state, "appid")
            name = get_key(app_state, "name")
            install_dir = get_key(app_state, "installdir")

            if not isinstance(appid, str) or not re.fullmatch(r"[1-9][0-9]{0,19}", appid):
                continue

            if not isinstance(name, str) or not name.strip():
                continue

            if not isinstance(install_dir, str) or not install_dir.strip():
                continue

            if os.path.isabs(install_dir) or "/" in install_dir or "\\" in install_dir or ":" in install_dir:
                continue

            game_path = steamapps / "common" / install_dir

            if not game_path.is_dir():
                continue

            games.append(
                {
                    "appid": appid,
                    "name": name.strip(),
                    "installDir": install_dir,
                    "library": library,
                    "manifest": manifest_path,
                    "gamePath": game_path,
                }
            )

    return sorted(games, key=lambda game: game["name"].lower())


def choose_from_list(items, title, label):
    if not items:
        fail(f"No {label} found")

    print()
    print(title)
    print("=" * len(title))

    for index, item in enumerate(items, start=1):
        print(f"{index:>3}. {item['display']}")

    while True:
        value = input(f"Select {label} [1-{len(items)}]: ").strip()

        if value.isdigit():
            index = int(value)

            if 1 <= index <= len(items):
                return items[index - 1]

        print("Invalid selection.")


def discover_usb_disks():
    output = run_capture(
        [
            "lsblk",
            "-J",
            "-b",
            "-o",
            "NAME,PATH,TYPE,SIZE,MODEL,TRAN,RM,MOUNTPOINTS",
        ]
    )
    data = json.loads(output)
    disks = []

    for device in data.get("blockdevices", []):
        if device.get("type") != "disk":
            continue

        if str(device.get("tran", "")).lower() != "usb":
            continue

        path = device.get("path")

        if not path:
            continue

        size = int(device.get("size") or 0)
        model = str(device.get("model") or "").strip()
        name = str(device.get("name") or "").strip()
        display = f"{path}  {format_bytes(size)}  {model or name}"
        disks.append(
            {
                "path": path,
                "size": size,
                "model": model,
                "display": display,
            }
        )

    return disks


def format_bytes(size):
    value = float(size)

    for unit in ["B", "KiB", "MiB", "GiB", "TiB"]:
        if value < 1024 or unit == "TiB":
            return f"{value:.1f} {unit}"

        value /= 1024

    return f"{size} B"


def unmount_children(device_path):
    output = run_capture(["lsblk", "-nrpo", "NAME,MOUNTPOINT", device_path])

    for line in output.splitlines():
        parts = line.split(maxsplit=1)

        if len(parts) != 2:
            continue

        path, mountpoint = parts

        if mountpoint:
            run(["umount", path])


def partition_and_format(device_path):
    unmount_children(device_path)
    run(["wipefs", "-a", device_path])
    run(["parted", "-s", device_path, "mklabel", "gpt"])
    run(["parted", "-s", device_path, "mkpart", "primary", "exfat", "1MiB", "100%"])
    run(["partprobe", device_path])
    run(["udevadm", "settle"])

    output = run_capture(["lsblk", "-nrpo", "NAME,TYPE", device_path])
    partition = None

    for line in output.splitlines():
        parts = line.split()

        if len(parts) == 2 and parts[1] == "part":
            partition = parts[0]
            break

    if partition is None:
        fail("Could not find newly created partition")

    run(["mkfs.exfat", "-n", CARTRIDGE_LABEL, partition])

    mountpoint = Path("/mnt") / f"steam-game-cartridge-{os.getpid()}"
    mountpoint.mkdir(mode=0o755, exist_ok=False)
    run(["mount", partition, str(mountpoint)])

    return partition, mountpoint


def safe_copytree(source, destination):
    source = Path(source)
    destination = Path(destination)
    destination.mkdir(parents=True, exist_ok=True)

    for current_root, directory_names, file_names in os.walk(source):
        current_root_path = Path(current_root)
        relative_root = current_root_path.relative_to(source)
        target_root = destination / relative_root
        target_root.mkdir(parents=True, exist_ok=True)

        for directory_name in list(directory_names):
            source_dir = current_root_path / directory_name

            if source_dir.is_symlink():
                fail(f"Refusing to copy symlinked directory: {source_dir}")

        for file_name in file_names:
            source_file = current_root_path / file_name

            if source_file.is_symlink():
                fail(f"Refusing to copy symlinked file: {source_file}")

            shutil.copy2(source_file, target_root / file_name)


def hash_file(path):
    digest = hashlib.sha256()

    with open(path, "rb") as input_file:
        for chunk in iter(lambda: input_file.read(1024 * 1024), b""):
            digest.update(chunk)

    return digest.hexdigest()


def hashable_files(library_root, appid, install_dir):
    steamapps = library_root / "steamapps"
    manifest = steamapps / f"appmanifest_{appid}.acf"

    yield manifest

    game_root = steamapps / "common" / install_dir

    for current_root, directory_names, file_names in os.walk(game_root):
        current_root_path = Path(current_root)

        for directory_name in list(directory_names):
            if (current_root_path / directory_name).is_symlink():
                fail(f"Refusing to hash symlinked directory: {current_root_path / directory_name}")

        for file_name in file_names:
            yield current_root_path / file_name


def create_hash_manifest(library_root, game, hash_manifest_id):
    entries = []

    for path in hashable_files(library_root, game["appid"], game["installDir"]):
        if path.is_symlink():
            fail(f"Refusing to hash symlinked file: {path}")

        file_stat = path.stat()

        if file_stat.st_size >= MAX_HASHED_FILE_BYTES:
            continue

        entries.append(
            {
                "relativePath": path.relative_to(library_root).as_posix(),
                "size": file_stat.st_size,
                "sha256": hash_file(path),
            }
        )

    return {
        "version": 1,
        "hashManifestId": hash_manifest_id,
        "steamAppId": game["appid"],
        "gameName": game["name"],
        "generatedAtUtc": _datetime.datetime.now(_datetime.timezone.utc)
        .replace(microsecond=0)
        .isoformat()
        .replace("+00:00", "Z"),
        "maxFileSizeBytes": MAX_HASHED_FILE_BYTES,
        "files": entries,
    }


def write_user_hash_manifest(home, uid, gid, manifest):
    hash_dir = home / ".local/share/SteamGameCartridge/hashes"
    hash_dir.mkdir(parents=True, exist_ok=True)
    hash_path = hash_dir / f"{manifest['hashManifestId']}.json"

    with open(hash_path, "w", encoding="utf-8") as output_file:
        json.dump(manifest, output_file, indent=2)
        output_file.write("\n")

    os.chown(hash_dir.parent, uid, gid)
    os.chown(hash_dir, uid, gid)
    os.chown(hash_path, uid, gid)

    return hash_path


def write_cartridge_json(mountpoint, game, hash_enabled, hash_manifest_id):
    config = {
        "version": 1,
        "name": game["name"],
        "action": "run",
        "steamAppId": game["appid"],
        "hashValidationEnabled": hash_enabled,
    }

    if hash_enabled:
        config["hashManifestId"] = hash_manifest_id

    with open(mountpoint / "cartridge.json", "w", encoding="utf-8") as output_file:
        json.dump(config, output_file, indent=2)
        output_file.write("\n")


def prepare_cartridge(mountpoint, game, hash_enabled, home, uid, gid):
    library_root = mountpoint / "SteamLibrary"
    steamapps = library_root / "steamapps"
    common = steamapps / "common"
    target_game_path = common / game["installDir"]

    steamapps.mkdir(parents=True, exist_ok=True)
    common.mkdir(parents=True, exist_ok=True)

    shutil.copy2(game["manifest"], steamapps / f"appmanifest_{game['appid']}.acf")
    safe_copytree(game["gamePath"], target_game_path)

    hash_manifest_id = None

    if hash_enabled:
        hash_manifest_id = str(uuid.uuid4())
        hash_manifest = create_hash_manifest(library_root, game, hash_manifest_id)
        hash_path = write_user_hash_manifest(home, uid, gid, hash_manifest)
        print(f"Hash manifest written: {hash_path}")

    write_cartridge_json(mountpoint, game, hash_enabled, hash_manifest_id)


def main():
    if os.geteuid() != 0:
        fail("Run this script with sudo. It must repartition and format the selected USB disk.")

    for tool in ["lsblk", "wipefs", "parted", "partprobe", "udevadm", "mkfs.exfat", "mount", "umount"]:
        require_tool(tool)

    username, uid, gid, home = real_user_context()
    games = discover_games(home)
    game_choices = [
        {
            **game,
            "display": f"{game['name']}  ({game['appid']})  [{game['library']}]",
        }
        for game in games
    ]
    selected_game = choose_from_list(game_choices, "Installed Steam Games", "game")
    disks = discover_usb_disks()
    selected_disk = choose_from_list(disks, "USB Target Disks", "USB disk")

    print()
    print(f"Selected game: {selected_game['name']} ({selected_game['appid']})")
    print(f"Target disk:   {selected_disk['path']} ({selected_disk['display']})")
    print()
    print("This will delete the target disk partition table and create a new exFAT partition.")
    confirmation = input(f'Type ERASE {selected_disk["path"]} to continue: ').strip()

    if confirmation != f"ERASE {selected_disk['path']}":
        fail("Confirmation did not match. Aborting.")

    hash_answer = input("Create local SHA256 manifest for files below 100 MiB? [y/N]: ").strip().lower()
    hash_enabled = hash_answer in {"y", "yes"}
    partition = None
    mountpoint = None

    try:
        partition, mountpoint = partition_and_format(selected_disk["path"])
        print(f"Formatted {partition} and mounted at {mountpoint}")
        prepare_cartridge(mountpoint, selected_game, hash_enabled, home, uid, gid)
        run(["sync"])
        print("Cartridge created successfully.")
    finally:
        if mountpoint and mountpoint.exists():
            try:
                run(["umount", str(mountpoint)])
            except subprocess.CalledProcessError:
                print(f"Warning: failed to unmount {mountpoint}", file=sys.stderr)

            try:
                mountpoint.rmdir()
            except OSError:
                pass


if __name__ == "__main__":
    main()
