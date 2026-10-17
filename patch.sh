#!/usr/bin/env bash
# Patch Bulanci (Steam appid 1732920) so it no longer quits when
# ISteamApps::GetFileDetails fails under Linux Steam + Proton.
#
# Usage: ./patch.sh [path/to/steamapps/common/Bulanci]
#        ./patch.sh --restore [path/to/steamapps/common/Bulanci]
set -euo pipefail

ORIG_SHA=bda74d762834642c9b3c8a26555391ec3dd970071ca5ceb7c37136de829680ef
PATCHED_SHA=6dfb236deacb85875189ffe13c61db2c6361ca31ef54578b515ed7632be85848
# file offset : original bytes (call qword [PostQuitMessage])
SITES=("0x19422:ff15f0e30500" "0x194d5:ff153de30500")
NOP6=660f1f440000
REL=Bulanci_Data/Plugins/x86_64/GfxPluginCombatPillowsNative.dll

restore=0
if [[ ${1:-} == --restore ]]; then restore=1; shift; fi

find_game() {
    local vdf p
    for vdf in ~/.local/share/Steam/steamapps/libraryfolders.vdf \
               ~/.steam/steam/steamapps/libraryfolders.vdf \
               ~/.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/libraryfolders.vdf; do
        [[ -f $vdf ]] || continue
        while read -r p; do
            [[ -f $p/steamapps/common/Bulanci/$REL ]] && { echo "$p/steamapps/common/Bulanci"; return; }
        done < <(sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"/\1/p' "$vdf")
    done
    return 1
}

game=${1:-$(find_game)} || { echo "Bulanci not found, pass the game directory as an argument." >&2; exit 1; }
dll=$game/$REL
[[ -f $dll ]] || { echo "Not found: $dll" >&2; exit 1; }

sha() { sha256sum "$1" | cut -d' ' -f1; }

if (( restore )); then
    [[ -f $dll.orig ]] || { echo "No backup $dll.orig, use Steam > Verify integrity of game files." >&2; exit 1; }
    cp "$dll.orig" "$dll"
    echo "Restored original: $dll"
    exit 0
fi

case $(sha "$dll") in
    "$PATCHED_SHA") echo "Already patched: $dll"; exit 0 ;;
    "$ORIG_SHA") ;;
    *) echo "Unknown version of $dll (game was updated?). Not patching." >&2; exit 1 ;;
esac

cp -n "$dll" "$dll.orig"
for site in "${SITES[@]}"; do
    off=${site%%:*} want=${site#*:}
    have=$(xxd -s "$off" -l 6 -p "$dll")
    [[ $have == "$want" ]] || { echo "Unexpected bytes at $off: $have" >&2; exit 1; }
    printf '%s' "$NOP6" | xxd -r -p | dd of="$dll" bs=1 seek=$((off)) conv=notrunc status=none
done

[[ $(sha "$dll") == "$PATCHED_SHA" ]] || { cp "$dll.orig" "$dll"; echo "Checksum mismatch after patch, reverted." >&2; exit 1; }
echo "Patched: $dll (backup: $dll.orig)"
