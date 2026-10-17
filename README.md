# Bulanci on Linux (Steam + Proton) – game quits a few seconds after start

[Slovenská verzia nižšie](#slovensky)

## Symptoms

- Bulanci ([Steam appid 1732920](https://store.steampowered.com/app/1732920/Bulanci/), version 3.7) starts under Proton, shows the intro and **quits on its own after ~10 seconds**. No crash dialog.
- `Player.log` (in the Proton prefix:
  `steamapps/compatdata/1732920/pfx/drive_c/users/steamuser/AppData/LocalLow/Sleep Team/Bulanci/Player.log`)
  contains:

  ```
  [NATIVE] [SteamWorks SDK] RequestFileDetails - failed, 9
  ...
  GameManager quiting....
  ```

- Steam's `~/.local/share/Steam/logs/content_log.txt` contains, at every launch:

  ```
  Failed to initialize depots for EYieldingGetFileDetails app 1732920
  ```

## Cause

1. **The native Linux build is gone.** The app is now configured as Windows-only
   (`oslist: windows`, only launch option is `Bulanci.exe`). The Linux depot `1732922`
   (and macOS depot `1732923`) still exists, but its public manifest is **empty (size 0)**.
   So on Linux the game can only be run as the Windows build via Proton.

2. **Integrity check kills the game.** The native plugin
   `Bulanci_Data/Plugins/x86_64/GfxPluginCombatPillowsNative.dll` calls
   `ISteamApps::GetFileDetails()` at startup to get a file's SHA1 from Steam and compare it.
   On Linux Steam this call fails (`k_EResult` 9 = FileNotFound, earlier also 2 = Fail),
   apparently because Steam can't initialise the depot list for this app
   (see the content_log line above). On failure (and in a second branch, most likely hash mismatch) the plugin calls
   `PostQuitMessage(1)`, so the game exits.

   This is a Steam/app-configuration issue, not a Proton one; changing the Proton version
   doesn't help. It has been happening since at least October 2024 (update 3.7).

## Workaround

`patch.sh` replaces the two `call [PostQuitMessage]` instructions in the failure /
mismatch branches of the `GetFileDetails` callback with a 6-byte NOP. Nothing else is changed;
the failure is still logged, the game just keeps running.

| file offset | VA            | original                      | patched                 |
|-------------|---------------|-------------------------------|-------------------------|
| `0x19422`   | `0x18001a022` | `ff 15 f0 e3 05 00` (other branch, likely hash mismatch) | `66 0f 1f 44 00 00` |
| `0x194d5`   | `0x18001a0d5` | `ff 15 3d e3 05 00` (request failed) | `66 0f 1f 44 00 00` |

The `PostQuitMessage` call in `InitSteamworks` (Steam not running / not owned) is left intact.

```sh
git clone https://github.com/jose1711/bulanci-linux-fix
cd bulanci-linux-fix
./patch.sh                      # auto-detects the game in your Steam libraries
./patch.sh /path/to/steamapps/common/Bulanci   # or give the path explicitly
./patch.sh --restore            # put the original DLL back
```

The script only patches the exact known DLL
(sha256 `bda74d762834642c9b3c8a26555391ec3dd970071ca5ceb7c37136de829680ef`), keeps a backup
as `GfxPluginCombatPillowsNative.dll.orig` and verifies the result
(`6dfb236deacb85875189ffe13c61db2c6361ca31ef54578b515ed7632be85848`).
Requires `bash`, `xxd`, `dd`, `sha256sum`.

**A game update or "Verify integrity of game files" restores the original DLL** – just run
`./patch.sh` again. If the game gets updated and the script reports an unknown version,
the offsets need to be found again.

No game files are distributed in this repository.

## For the developers (SleepTeam)

- Linux depot 1732922 has an empty public manifest while the app is Windows-only – either
  publish the Linux build again or remove the depot.
- Please don't quit the game when `GetFileDetails` fails (only when the hash actually
  mismatches) – the call fails for every Linux/Proton (and likely Steam Deck) player.

---

<a name="slovensky"></a>
## Slovensky

**Problém:** Bulanci (Steam, verzia 3.7) sa pod Protonom spustí a asi po 10 sekundách sa sama
vypne. V `Player.log` je `RequestFileDetails - failed, 9` a hneď nato `GameManager quiting....`.

**Príčina:**
- Natívna linuxová verzia zo Steamu zmizla. Hra je teraz len pre Windows a linuxový depot
  `1732922` je prázdny. Na Linuxe teda beží iba cez Proton.
- Natívny plugin hry pri štarte kontroluje integritu súborov cez Steam API `GetFileDetails`.
  Na Linuxe to Steamu zlyhá (`Failed to initialize depots for EYieldingGetFileDetails`)
  a plugin pri akejkoľvek chybe zavolá `PostQuitMessage`. Zmena verzie Protonu nepomáha.

**Riešenie:** `./patch.sh` nahradí dve volania `PostQuitMessage` inštrukciou NOP. Hra potom pri
zlyhaní kontroly pokračuje. Skript zaplátá len presne známu verziu DLL, spraví zálohu
`.orig` a výsledok overí. Návrat: `./patch.sh --restore`. Po update hry alebo overení súborov
v Steame treba skript spustiť znova.
