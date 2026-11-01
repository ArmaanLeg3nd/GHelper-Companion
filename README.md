# GHelper Companion

A small Windows tray app that keeps ASUS services stopped through GHelper's own Stop action. Useful if Armoury Crate is still installed and its services restart.

**Experimental.** Tested with **GHelper 0.288, English UI**.

## Requirements

- Windows x64
- PowerShell 7 x64
- GHelper running
- Administrator permission

## Setup

1. Download `GHelperCompanion-v0.1.1-win-x64.zip` from [Releases](https://github.com/ArmaanLeg3nd/GHelper-Companion/releases).
2. Extract the ZIP. Keep `GHelperCompanion.exe` and the `runtime` folder together.
3. Start GHelper, then launch `GHelperCompanion.exe` and accept the administrator prompt.
4. Right-click the companion's tray icon and turn on **Auto-stop services**.

The tray icon may be in Windows' hidden-icons menu.

## Tray menu

- **Auto-stop services** — checks every 15 seconds and asks GHelper to stop restarted services. Turn it off to pause.
- **Scan now** — reports running services. If auto-stop is on, it also stops them through GHelper.
- **Run at sign-in** — starts the companion when you sign in. GHelper's startup setting is separate.
- **Exit** — closes the companion.

Armoury Crate service inclusion follows GHelper's `stop_ac` setting.

## Things to know

- Works while GHelper is hidden in its system tray.
- Uses temporary native hooks to open Extra invisibly, run its Stop action, and close the temporary window.
- GHelper's Stop action changes service startup types: ordinary listed services become **Disabled**, and Armoury Crate entries become **Manual**.
- Failed checks turn auto-stop off. Check the notification before enabling it again.
- Avoid manually starting or stopping services while the companion is enforcing a stop.
- Other GHelper versions, languages, and Windows architectures have not been verified.

Settings and activity logs are saved in `%LOCALAPPDATA%\GHelperCompanion`. The app makes no network requests.

Before uninstalling, turn off **Run at sign-in**, then exit the companion.

## Folder layout

```text
GHelperCompanion.exe   Start this
runtime/              Required app files
README.md             Instructions
LICENSE               MIT license
```

The source repository also includes `source/`, `docs/`, and `tests/`. These are not needed to run the built app.

## Build from source (optional)

Use PowerShell 7 with the .NET Framework C# compiler and [Tiny C Compiler, win64](https://www.bellard.org/tcc/) available. Run from the repository root, with `tcc.exe` on PATH:

```powershell
New-Item -ItemType Directory -Path build -Force | Out-Null
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $csc /nologo /target:winexe /reference:System.Windows.Forms.dll /out:build\GHelperCompanion.exe source\Launcher.cs
if ($LASTEXITCODE -ne 0) { throw 'Launcher build failed' }
& tcc.exe -shared -o build\ExtraNoActivate-v5.dll source\ExtraNoActivate.c -luser32
if ($LASTEXITCODE -ne 0) { throw 'Hook build failed' }
```

Exit the companion, then copy `build/GHelperCompanion.exe` to the root folder and `build/ExtraNoActivate-v5.dll` to `runtime/`. If the DLL is in use, exit GHelper normally before replacing it.

`build/` is temporary output. The complete app is the EXE plus `runtime/`.

## License

[MIT](LICENSE). Independent project; not an official GHelper component.
