# GHelper Companion

A Windows tray companion that asks your running [GHelper](https://github.com/seerge/g-helper) instance to stop ASUS services when they restart.

## Platform and release package

GHelper Companion is experimental and Windows x64-specific. It requires Windows x64, PowerShell 7 x64, administrator rights, and a running x64 GHelper instance. The tested compatibility baseline is **GHelper 0.288 with its English-language UI**. ARM64, 32-bit Windows/GHelper, Linux, and macOS are not supported by this build.

The launcher is a Windows .NET Framework AnyCPU executable, while the native hook DLL is compiled for Windows x64 and must match GHelper's architecture. The complete app is therefore Windows x64-specific, not platform-independent.

Download `GHelperCompanion-v0.1.1-win-x64.zip` from [Releases](https://github.com/ArmaanLeg3nd/GHelper-Companion/releases). It contains the launcher, required `runtime/` files, README, and MIT license. Extract the complete archive into one folder before launching the EXE.

## Run

Install PowerShell 7 (x64), keep `GHelperCompanion.exe` alongside `runtime/`, and launch the EXE. Accept the administrator prompt and make sure GHelper is running. If you downloaded the source instead of the release ZIP, follow the build instructions below first.

The tray menu provides **Auto-stop services**, **Scan now**, **Run at sign-in**, and **Exit**. Auto-stop checks every 15 seconds. Scan now is read-only when auto-stop is off and enforces the stop when auto-stop is on. Armoury Crate inclusion follows GHelper's own setting.

## Layout

```text
GHelperCompanion.exe       App launcher
runtime/                  Required scripts and hook DLL
source/                   C# launcher and C hook build source
docs/                     Validation notes
tests/                    Foreground policy regression checks
build/                    Temporary compiler output, when building from source
README.md                 Usage and build instructions
```

**The runnable build is the EXE plus `runtime/`.** The optional `build/` directory is only temporary compiler output and is not a complete installation.

The launcher supports PowerShell 7 installed normally or through its Microsoft Store app alias. An optional `runtime/powershell-path.txt` can override its executable location. Keep `runtime/` next to the launcher. `source/`, `docs/`, and `tests/` are optional once the app has been built and are not included in the release ZIP.

Settings and activity logs are stored in `%LOCALAPPDATA%\GHelperCompanion`. Run at sign-in starts the companion automatically for the current user.

## Tested GHelper version

Tested with **GHelper 0.288**, x64, English UI. Background stopping was verified with GHelper hidden in its system tray: Extra stayed hidden, services stopped, GHelper saved its startup-enforcement preference, and focus was preserved.

The installed executable reports:

- File version: `0.288`
- Product version: `1.0.0+e897b278bf809add90c904ba84aa2e451579dd0c`
- SHA-256: `AA94E40E1302A92458DF1C9D8E56C1FD6EF13ABADF318CBE88DB66FED0F3B4D8`

Other GHelper versions and languages have not been verified.

## Build and deploy

Requirements: x64 Windows, PowerShell 7, the .NET Framework C# compiler, and an x64 Windows C compiler. The hook was built with [Tiny C Compiler 0.9.27, win64](https://www.bellard.org/tcc/), linked against `user32`. Compilers are not bundled. There is no Visual Studio solution; the PowerShell scripts run as-is.

From the repository root in PowerShell 7, with `tcc.exe` available on PATH:

```powershell
New-Item -ItemType Directory -Path '.\build' -Force | Out-Null
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $csc /nologo /target:winexe /reference:System.Windows.Forms.dll /out:build\GHelperCompanion.exe source\Launcher.cs
if ($LASTEXITCODE -ne 0) { throw 'Launcher compilation failed' }
$tcc = (Get-Command tcc.exe -ErrorAction Stop).Source
& $tcc -shared -o build\ExtraNoActivate-v5.dll source\ExtraNoActivate.c -luser32
if ($LASTEXITCODE -ne 0) { throw 'Hook compilation failed' }
```

The outputs are `build/GHelperCompanion.exe` and `build/ExtraNoActivate-v5.dll`. TinyCC may also produce an optional `.def` file. Nothing in `build/` is required after deployment.

Exit the companion before replacing files. Deploy the binaries into the runnable layout:

```powershell
Copy-Item '.\build\GHelperCompanion.exe' '.\GHelperCompanion.exe' -Force
Copy-Item '.\build\ExtraNoActivate-v5.dll' '.\runtime\ExtraNoActivate-v5.dll' -Force
Join-Path $PSHOME 'pwsh.exe' | Set-Content '.\runtime\powershell-path.txt'
```

Deployment destinations are relative to the repository root: `./GHelperCompanion.exe` and `./runtime/ExtraNoActivate-v5.dll`. Building or deploying inside a protected installation folder requires administrator rights.

If Windows reports the hook DLL is in use, exit GHelper normally before replacing it; its inactive mapping can survive hook removal. Do not force-unload the module. Relaunch GHelper and the companion afterward. The EXE by itself, including the copy inside `build/`, is not a complete installation.

Before uninstalling, turn off **Run at sign-in** to remove the companion's scheduled task, then exit the companion.

## How it works

Service names are extracted read-only from the installed GHelper assembly. The companion sends a native command to GHelper's own Stop button and checks the resulting service states and saved enforcement preference.

When GHelper is hidden in the system tray and Extra is closed, two temporary, thread-scoped Windows hooks (CBT and call-window-return) create Extra with verified Desktop Window Manager cloaking before its first display. The companion closes its temporary window and removes the hook afterward. This loads native code into GHelper through Windows' hook mechanism; it does not patch GHelper's executable. The inactive DLL mapping may remain until GHelper exits.

The helper verifies that its temporary Extra window is hidden before sending Stop. An Extra window you already had open is left open. No keyboard or mouse hook is installed, and the app makes no network requests.

## Limits

- Experimental integration tested against one x64, English-language GHelper installation; future updates may require changes.
- GHelper's own stop action changes startup types: ordinary listed services become Disabled, while Armoury Crate entries become Manual.
- The companion checks for driver entries and unrelated active dependents before stopping. GHelper's toggle still has an inherent timing race; avoid manually toggling services during enforcement.
- Uncertain delivery or failed verification disables automatic enforcement. No visible-click or direct-stop fallback is used.
- This project is an independent companion, not an official GHelper component.

## License

Licensed under the [MIT License](LICENSE).

## Regression checks

From PowerShell 7, run `.\tests\ForegroundPolicy.Tests.ps1` to verify the foreground classification without changing windows or services. Live hook/service tests require the supported GHelper installation and administrator rights.
