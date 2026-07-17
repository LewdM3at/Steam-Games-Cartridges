#!/bin/bash

set -euo pipefail

DEVICE="${1:-}"
CONFIG_FILE_NAME="cartridge.json"

echo "Game cartridge detected: $DEVICE"

if [[ ! "$DEVICE" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "Invalid device name."
    exit 0
fi

# Wait for desktop automounter.
MOUNT_POINT=""

for i in {1..60}; do
    MOUNT_POINT=$(findmnt -n -o TARGET "/dev/$DEVICE" 2>/dev/null || true)

    if [ -n "$MOUNT_POINT" ]; then
        break
    fi

    sleep 0.5
done

if [ -z "$MOUNT_POINT" ]; then
    echo "No mount point found for /dev/$DEVICE"
    exit 0
fi

echo "Mounted at: $MOUNT_POINT"

CONFIG_FILE="$MOUNT_POINT/$CONFIG_FILE_NAME"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "No cartridge.json found on cartridge"
    exit 0
fi

if [ -L "$CONFIG_FILE" ]; then
    echo "cartridge.json must not be a symlink"
    exit 0
fi

echo "Reading cartridge config..."

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is required to read cartridge.json"
    exit 1
fi

if ! CONFIG_DATA=$(python3 - "$CONFIG_FILE" <<'PY'
import json
import hashlib
import os
import re
import stat
import sys
import unicodedata
from collections import OrderedDict

MAX_CONFIG_BYTES = 16 * 1024
MAX_MANIFEST_BYTES = 1024 * 1024
MAX_LIBRARYFOLDERS_BYTES = 4 * 1024 * 1024
MAX_HASH_MANIFEST_BYTES = 128 * 1024 * 1024
MAX_HASHED_FILE_BYTES = 100 * 1024 * 1024

ALLOWED_PROPERTIES = {
    "version",
    "name",
    "action",
    "steamAppId",
    "hashValidationEnabled",
    "hashManifestId",
}

STEAM_URI_TEMPLATES = {
    "run": "steam://run/{steam_app_id}",
    "details": "steam://nav/games/details/{steam_app_id}",
}


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


def safe_text(value):
    return "".join(
        " " if unicodedata.category(character) in {"Cc", "Cf"} else character
        for character in str(value)
    )


def has_control_or_format(value):
    return any(
        unicodedata.category(character) in {"Cc", "Cf"}
        for character in value
    )


def validate_no_control_or_format(value, description):
    if has_control_or_format(value):
        fail(f"{description} contains unsupported characters")


def require_regular_directory(path, description):
    try:
        stat_result = os.lstat(path)
    except OSError as exc:
        fail(f"{description} not found: {exc}")

    if stat.S_ISLNK(stat_result.st_mode):
        fail(f"{description} must not be a symlink")

    if not stat.S_ISDIR(stat_result.st_mode):
        fail(f"{description} must be a directory")

    return os.path.abspath(path)


def require_regular_file(path, description, max_bytes):
    try:
        stat_result = os.lstat(path)
    except OSError as exc:
        fail(f"{description} not found: {exc}")

    if stat.S_ISLNK(stat_result.st_mode):
        fail(f"{description} must not be a symlink")

    if not stat.S_ISREG(stat_result.st_mode):
        fail(f"{description} must be a regular file")

    if stat_result.st_size > max_bytes:
        fail(f"{description} is too large")

    return os.path.abspath(path)


def read_text_file(path, description):
    try:
        with open(path, "r", encoding="utf-8") as text_file:
            return text_file.read()
    except UnicodeDecodeError:
        fail(f"{description} must be UTF-8")
    except OSError as exc:
        fail(f"Cannot read {description}: {exc}")


def tokenize_vdf(text, description):
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
                fail(f"{description} contains an unterminated string")

            tokens.append("".join(value))
            continue

        start = index

        while index < len(text) and not text[index].isspace() and text[index] not in "{}":
            index += 1

        tokens.append(text[start:index])

    return tokens


def parse_vdf(text, description):
    tokens = tokenize_vdf(text, description)
    index = 0

    def parse_object(expect_closing_brace):
        nonlocal index
        result = OrderedDict()

        while index < len(tokens):
            token = tokens[index]

            if token == "}":
                if not expect_closing_brace:
                    fail(f"{description} contains an unexpected closing brace")

                index += 1
                return result

            if token == "{":
                fail(f"{description} contains an unexpected opening brace")

            key = token
            index += 1

            if index >= len(tokens):
                fail(f"{description} is missing a value")

            token = tokens[index]

            if token == "{":
                index += 1
                value = parse_object(True)
            elif token == "}":
                fail(f"{description} is missing a value")
            else:
                value = token
                index += 1

            if key in result:
                fail(f"{description} contains duplicate key: {safe_text(key)}")

            result[key] = value

        if expect_closing_brace:
            fail(f"{description} is missing a closing brace")

        return result

    parsed = parse_object(False)

    if index != len(tokens):
        fail(f"{description} contains trailing data")

    return parsed


def find_case_insensitive_key(mapping, key, description):
    matches = [
        candidate
        for candidate in mapping
        if candidate.lower() == key.lower()
    ]

    if len(matches) != 1:
        fail(f"{description} must contain exactly one {key} entry")

    return matches[0]


def vdf_escape(value):
    return str(value).replace("\\", "\\\\").replace('"', '\\"')


def dump_vdf_object(mapping, indent=0):
    lines = []
    padding = "\t" * indent

    for key, value in mapping.items():
        escaped_key = vdf_escape(key)

        if isinstance(value, dict):
            lines.append(f'{padding}"{escaped_key}"')
            lines.append(f"{padding}{{")
            lines.extend(dump_vdf_object(value, indent + 1))
            lines.append(f"{padding}}}")
        else:
            lines.append(f'{padding}"{escaped_key}"\t\t"{vdf_escape(value)}"')

    return lines


def comparable_path(path):
    return os.path.normcase(os.path.abspath(path).rstrip(os.sep))


def find_steam_libraryfolders_path():
    candidates = [
        os.path.expanduser("~/.steam/steam/steamapps/libraryfolders.vdf"),
        os.path.expanduser("~/.local/share/Steam/steamapps/libraryfolders.vdf"),
        os.path.expanduser("~/.var/app/com.valvesoftware.Steam/data/Steam/steamapps/libraryfolders.vdf"),
    ]

    for candidate in candidates:
        if os.path.isfile(candidate):
            return candidate

    fail("Steam libraryfolders.vdf not found")


def normalize_hash_relative_path(relative_path):
    if not isinstance(relative_path, str):
        fail("Hash manifest relativePath must be a string")

    if has_control_or_format(relative_path):
        fail("Hash manifest relativePath contains unsupported characters")

    if "\\" in relative_path or relative_path.startswith("/") or relative_path.startswith("~"):
        fail("Hash manifest relativePath is unsafe")

    parts = relative_path.split("/")

    if not parts or any(part in {"", ".", ".."} for part in parts):
        fail("Hash manifest relativePath is unsafe")

    return "/".join(parts)


def ensure_hash_path_scope(relative_path, steam_app_id, install_dir):
    manifest_path = f"steamapps/appmanifest_{steam_app_id}.acf"
    game_prefix = f"steamapps/common/{install_dir}/"

    if relative_path != manifest_path and not relative_path.startswith(game_prefix):
        fail("Hash manifest contains a path outside the selected game")


def hash_manifest_path(hash_manifest_id):
    data_home = os.environ.get("XDG_DATA_HOME")

    if not data_home:
        data_home = os.path.join(os.path.expanduser("~"), ".local", "share")

    return os.path.join(
        data_home,
        "SteamGameCartridge",
        "hashes",
        f"{hash_manifest_id}.json",
    )


def sha256_file(path):
    digest = hashlib.sha256()

    with open(path, "rb") as input_file:
        for chunk in iter(lambda: input_file.read(1024 * 1024), b""):
            digest.update(chunk)

    return digest.hexdigest()


def relative_library_path(library_path, path):
    return os.path.relpath(path, library_path).replace(os.sep, "/")


def iter_game_files_for_hashing(library_path, steam_app_id, install_dir):
    manifest_path = os.path.join(
        library_path,
        "steamapps",
        f"appmanifest_{steam_app_id}.acf",
    )

    yield manifest_path

    game_path = os.path.join(
        library_path,
        "steamapps",
        "common",
        install_dir,
    )

    for current_root, directory_names, file_names in os.walk(game_path):
        for directory_name in list(directory_names):
            directory_path = os.path.join(current_root, directory_name)

            try:
                directory_stat = os.lstat(directory_path)
            except OSError as exc:
                fail(f"Cannot inspect game directory: {exc}")

            if stat.S_ISLNK(directory_stat.st_mode):
                fail("Game directory must not contain symlinked directories")

        for file_name in file_names:
            yield os.path.join(current_root, file_name)


def load_hash_manifest(hash_manifest_id, steam_app_id, install_dir):
    manifest_path = require_regular_file(
        hash_manifest_path(hash_manifest_id),
        "Local hash manifest",
        MAX_HASH_MANIFEST_BYTES,
    )

    try:
        with open(manifest_path, "r", encoding="utf-8") as manifest_file:
            manifest = json.load(manifest_file, object_pairs_hook=no_duplicate_keys)
    except UnicodeDecodeError:
        fail("Local hash manifest must be UTF-8")
    except json.JSONDecodeError as exc:
        fail(f"Local hash manifest is not valid JSON: {exc}")
    except OSError as exc:
        fail(f"Cannot read local hash manifest: {exc}")

    if not isinstance(manifest, dict):
        fail("Local hash manifest must contain a JSON object")

    allowed_keys = {
        "version",
        "hashManifestId",
        "steamAppId",
        "gameName",
        "generatedAtUtc",
        "maxFileSizeBytes",
        "files",
    }
    unknown_keys = sorted(set(manifest) - allowed_keys)

    if unknown_keys:
        fail(f"Unsupported local hash manifest property: {safe_text(unknown_keys[0])}")

    if manifest.get("version") != 1:
        fail("Unsupported local hash manifest version")

    if manifest.get("hashManifestId") != hash_manifest_id:
        fail("Local hash manifest id does not match cartridge.json")

    if str(manifest.get("steamAppId", "")).strip() != steam_app_id:
        fail("Local hash manifest app id does not match cartridge.json")

    max_file_size = manifest.get("maxFileSizeBytes")

    if (
        not isinstance(max_file_size, int)
        or isinstance(max_file_size, bool)
        or max_file_size != MAX_HASHED_FILE_BYTES
    ):
        fail("Local hash manifest has an unsupported maxFileSizeBytes value")

    files = manifest.get("files")

    if not isinstance(files, list):
        fail("Local hash manifest files must be a list")

    expected = {}

    for entry in files:
        if not isinstance(entry, dict):
            fail("Local hash manifest file entries must be objects")

        if set(entry) != {"relativePath", "size", "sha256"}:
            fail("Local hash manifest file entry has unsupported properties")

        relative_path = normalize_hash_relative_path(entry["relativePath"])
        ensure_hash_path_scope(relative_path, steam_app_id, install_dir)

        size = entry["size"]

        if not isinstance(size, int) or isinstance(size, bool) or size < 0 or size >= MAX_HASHED_FILE_BYTES:
            fail("Local hash manifest file size is invalid")

        sha256 = entry["sha256"]

        if not isinstance(sha256, str) or not re.fullmatch(r"[a-f0-9]{64}", sha256):
            fail("Local hash manifest sha256 is invalid")

        if relative_path in expected:
            fail("Local hash manifest contains duplicate file paths")

        expected[relative_path] = {
            "size": size,
            "sha256": sha256,
        }

    return expected


def verify_cartridge_hashes(library_path, install_dir, steam_app_id, hash_manifest_id):
    expected = load_hash_manifest(hash_manifest_id, steam_app_id, install_dir)
    seen = set()

    for path in iter_game_files_for_hashing(library_path, steam_app_id, install_dir):
        try:
            file_stat = os.lstat(path)
        except OSError as exc:
            fail(f"Cannot inspect game file: {exc}")

        if stat.S_ISLNK(file_stat.st_mode):
            fail("Game files must not be symlinks")

        if not stat.S_ISREG(file_stat.st_mode):
            fail("Game path contains a non-regular file")

        if file_stat.st_size >= MAX_HASHED_FILE_BYTES:
            continue

        relative_path = relative_library_path(library_path, path)
        expected_entry = expected.get(relative_path)

        if expected_entry is None:
            fail(f"Unexpected hashable file on cartridge: {safe_text(relative_path)}")

        if expected_entry["size"] != file_stat.st_size:
            fail(f"Hash size mismatch for: {safe_text(relative_path)}")

        actual_sha256 = sha256_file(path)

        if expected_entry["sha256"] != actual_sha256:
            fail(f"Hash mismatch for: {safe_text(relative_path)}")

        seen.add(relative_path)

    missing = sorted(set(expected) - seen)

    if missing:
        fail(f"Missing hashable file on cartridge: {safe_text(missing[0])}")


def validate_cartridge_steam_library(cartridge_root, steam_app_id):
    library_path = require_regular_directory(
        os.path.join(cartridge_root, "SteamLibrary"),
        "Cartridge SteamLibrary",
    )
    validate_no_control_or_format(library_path, "Cartridge SteamLibrary path")

    steamapps_path = require_regular_directory(
        os.path.join(library_path, "steamapps"),
        "Cartridge steamapps directory",
    )

    manifest_path = require_regular_file(
        os.path.join(steamapps_path, f"appmanifest_{steam_app_id}.acf"),
        "Cartridge app manifest",
        MAX_MANIFEST_BYTES,
    )
    manifest = parse_vdf(
        read_text_file(manifest_path, "Cartridge app manifest"),
        "Cartridge app manifest",
    )
    app_state_key = find_case_insensitive_key(
        manifest,
        "AppState",
        "Cartridge app manifest",
    )
    app_state = manifest[app_state_key]

    if not isinstance(app_state, dict):
        fail("Cartridge app manifest AppState must be an object")

    appid_key = find_case_insensitive_key(
        app_state,
        "appid",
        "Cartridge app manifest AppState",
    )

    if app_state[appid_key] != steam_app_id:
        fail("Cartridge app manifest does not match steamAppId")

    installdir_key = find_case_insensitive_key(
        app_state,
        "installdir",
        "Cartridge app manifest AppState",
    )
    install_dir = app_state[installdir_key]

    if not isinstance(install_dir, str):
        fail("Cartridge app manifest installdir must be a string")

    if (
        not install_dir.strip()
        or install_dir in {".", ".."}
        or os.path.isabs(install_dir)
        or "/" in install_dir
        or "\\" in install_dir
        or ":" in install_dir
    ):
        fail("Cartridge app manifest contains an unsafe installdir")

    validate_no_control_or_format(
        install_dir,
        "Cartridge app manifest installdir",
    )

    common_path = require_regular_directory(
        os.path.join(steamapps_path, "common"),
        "Cartridge common directory",
    )
    require_regular_directory(
        os.path.join(common_path, install_dir),
        "Cartridge game directory",
    )

    return library_path, install_dir


def register_steam_library(library_path, steam_app_id):
    libraryfolders_path = require_regular_file(
        find_steam_libraryfolders_path(),
        "Steam libraryfolders.vdf",
        MAX_LIBRARYFOLDERS_BYTES,
    )
    libraryfolders = parse_vdf(
        read_text_file(libraryfolders_path, "Steam libraryfolders.vdf"),
        "Steam libraryfolders.vdf",
    )
    root_key = find_case_insensitive_key(
        libraryfolders,
        "libraryfolders",
        "Steam libraryfolders.vdf",
    )
    folders = libraryfolders[root_key]

    if not isinstance(folders, dict):
        fail("Steam libraryfolders.vdf libraryfolders entry must be an object")

    library_path = os.path.abspath(library_path)
    library_path_comparable = comparable_path(library_path)
    next_index = 0
    changed = False

    for key, value in folders.items():
        if key.isdigit():
            next_index = max(next_index, int(key) + 1)

        existing_path = None

        if isinstance(value, dict):
            path_value = value.get("path")

            if isinstance(path_value, str):
                existing_path = path_value
        elif isinstance(value, str) and key.isdigit():
            existing_path = value

        if existing_path and comparable_path(existing_path) == library_path_comparable:
            if isinstance(value, dict):
                apps = value.get("apps")

                if not isinstance(apps, dict):
                    value["apps"] = OrderedDict()
                    apps = value["apps"]
                    changed = True

                if steam_app_id not in apps:
                    apps[steam_app_id] = "0"
                    changed = True

            if changed:
                write_steam_libraryfolders(libraryfolders_path, libraryfolders)

            return

    folders[str(next_index)] = OrderedDict(
        [
            ("path", library_path),
            ("label", ""),
            ("contentid", "0"),
            ("totalsize", "0"),
            ("update_clean_bytes_tally", "0"),
            ("time_last_update_corruption", "0"),
            ("apps", OrderedDict([(steam_app_id, "0")])),
        ]
    )
    write_steam_libraryfolders(libraryfolders_path, libraryfolders)


def write_steam_libraryfolders(path, libraryfolders):
    content = "\n".join(dump_vdf_object(libraryfolders)) + "\n"
    temp_path = f"{path}.tmp"

    try:
        original_stat = os.stat(path)

        with open(temp_path, "w", encoding="utf-8") as output_file:
            output_file.write(content)

        os.chmod(temp_path, stat.S_IMODE(original_stat.st_mode))
        os.replace(temp_path, path)
    except OSError as exc:
        fail(f"Cannot update Steam libraryfolders.vdf: {exc}")


def no_duplicate_keys(pairs):
    result = {}

    for key, value in pairs:
        if key in result:
            fail(f"Duplicate JSON key: {safe_text(key)}")

        result[key] = value

    return result


config_path = sys.argv[1]

try:
    stat_result = os.lstat(config_path)
except OSError as exc:
    fail(f"Cannot read cartridge.json: {exc}")

if stat.S_ISLNK(stat_result.st_mode):
    fail("cartridge.json must not be a symlink")

if not stat.S_ISREG(stat_result.st_mode):
    fail("cartridge.json must be a regular file")

if stat_result.st_size > MAX_CONFIG_BYTES:
    fail("cartridge.json is too large")

try:
    with open(config_path, "r", encoding="utf-8") as config_file:
        config = json.load(config_file, object_pairs_hook=no_duplicate_keys)
except UnicodeDecodeError:
    fail("cartridge.json must be UTF-8")
except json.JSONDecodeError as exc:
    fail(f"cartridge.json is not valid JSON: {exc}")
except OSError as exc:
    fail(f"Cannot read cartridge.json: {exc}")

if not isinstance(config, dict):
    fail("cartridge.json must contain a JSON object")

unknown_properties = sorted(set(config) - ALLOWED_PROPERTIES)

if unknown_properties:
    fail(f"Unsupported cartridge.json property: {safe_text(unknown_properties[0])}")

if "version" not in config:
    fail("Missing version")

version = config["version"]

if not isinstance(version, int) or isinstance(version, bool) or version != 1:
    fail("Unsupported cartridge.json version")

steam_app_id = config.get("steamAppId")

if isinstance(steam_app_id, int) and not isinstance(steam_app_id, bool):
    steam_app_id = str(steam_app_id)
elif isinstance(steam_app_id, str):
    steam_app_id = steam_app_id.strip()
else:
    fail("steamAppId must be a positive numeric Steam app id")

if not re.fullmatch(r"[1-9][0-9]{0,19}", steam_app_id):
    fail("steamAppId must be a positive numeric Steam app id")

action = config.get("action", "run")

if not isinstance(action, str):
    fail("action must be a string")

action = action.strip().lower()

if action not in STEAM_URI_TEMPLATES:
    fail("Unsupported Steam action")

name = config.get("name", steam_app_id)

if not isinstance(name, str):
    fail("name must be a string")

name = name.strip()

if len(name) > 80:
    fail("name must be 80 characters or less")

if has_control_or_format(name):
    fail("name must not contain control or format characters")

hash_validation_enabled = config.get("hashValidationEnabled", False)

if not isinstance(hash_validation_enabled, bool):
    fail("hashValidationEnabled must be a boolean")

hash_manifest_id = config.get("hashManifestId")

if hash_manifest_id is not None:
    if not isinstance(hash_manifest_id, str):
        fail("hashManifestId must be a string")

    hash_manifest_id = hash_manifest_id.strip().lower()

    if not re.fullmatch(
        r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}",
        hash_manifest_id,
    ):
        fail("hashManifestId must be a UUID")

if hash_validation_enabled and not hash_manifest_id:
    fail("hashManifestId is required when hashValidationEnabled is true")

steam_uri = STEAM_URI_TEMPLATES[action].format(steam_app_id=steam_app_id)
cartridge_root = os.path.dirname(os.path.abspath(config_path))
library_path, install_dir = validate_cartridge_steam_library(cartridge_root, steam_app_id)

if hash_validation_enabled:
    verify_cartridge_hashes(
        library_path,
        install_dir,
        steam_app_id,
        hash_manifest_id,
    )

register_steam_library(library_path, steam_app_id)

print(f"{action}\t{steam_app_id}\t{steam_uri}\t{name}")
PY
); then
    echo "Invalid cartridge.json"
    exit 0
fi

IFS=$'\t' read -r ACTION STEAM_APP_ID STEAM_URI NAME <<< "$CONFIG_DATA"

echo "Launching Steam action: $ACTION $STEAM_APP_ID"

if command -v steam >/dev/null 2>&1; then
    steam "$STEAM_URI"
elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$STEAM_URI"
else
    echo "Neither steam nor xdg-open was found."
    exit 1
fi
