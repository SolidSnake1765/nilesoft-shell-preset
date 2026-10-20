**English** | [Русский](README.ru.md)

# Context menu preset for Nilesoft Shell

A ready-made right-click menu for Windows Explorer: a clean translucent theme, an FFmpeg menu
(convert and compress video, audio and images in a couple of clicks, including on the graphics card),
Everything search, hashes, batch rename, share-as-link, disk images, power options and more.
The menu comes in English and Russian. What every item does: [MENU.md](MENU.md).

Made and tested on **Windows 11** with **Nilesoft Shell 1.9.18**.

---

## What is inside

| What | Why |
|---|---|
| `Install.cmd` | Automatic setup: run it and it does everything |
| `config/en`, `config/ru` | The menu itself (`shell.nss` and the `imports` folder) in English and Russian |
| `setup/install.ps1` | The setup script that `Install.cmd` starts |
| `MENU.md`, `MENU.ru.md` | Description of every menu item |
| `dev/` | For those who want to change the menu: file generators, the translation dictionary and a checker |

Download: the green **Code → Download ZIP** button on GitHub (or the Releases section),
then extract the **whole** archive to any folder.

---

## Step 0. Install Nilesoft Shell

There is no menu without it. Download it from <https://nilesoft.org/download> and install it like any program,
or run `winget install Nilesoft.Shell` in a terminal.

Then install the programs you want from the [list below](#required-programs). This is optional:
without a program you simply do not get its items. If you install one later, run the preset setup again.

## Option 1. Automatic setup (easier)

1. Run **`Install.cmd`** and click "Yes" when it asks for administrator rights.
2. Pick the menu language (the default is your Windows language).
3. The setup will:
   - find the Nilesoft Shell folder;
   - save your current menu to `Nilesoft Shell/backup/before-preset-<date>`;
   - copy the preset files;
   - find ffmpeg, Everything and LosslessCut and show what it found. Enter = accept;
     you can also type the number of another option or paste your own path;
   - check the ffmpeg version and whether your graphics card can encode video;
   - tell you which items will appear, which will be hidden and why;
   - register Nilesoft Shell and restart Explorer (the taskbar blinks, that is normal).
4. Right-click a file, a folder, the desktop or the taskbar.

> If Windows says "Windows protected your PC", click "More info" → "Run anyway".
> Windows does this for any downloaded `.cmd` file. The setup downloads nothing and sends nothing
> anywhere: it only copies files into the Nilesoft Shell folder and writes program paths there.

## Option 2. Manual setup

1. Open the Nilesoft Shell folder (usually `C:/Program Files/Nilesoft Shell`). Save its `shell.nss`
   file and `imports` folder somewhere: that is your current menu.
2. Copy the contents of **`config/en`** (or `config/ru` for the Russian menu) into the Nilesoft Shell folder:
   the `shell.nss` file and the `imports` folder, replacing the files. Windows asks for administrator rights, allow it.
3. If your programs are installed in unusual places, open `imports/paths.nss` in Notepad
   and put the paths in (see [Does it matter where programs are installed](#does-it-matter-where-programs-are-installed)).
   If they are installed the usual way, do nothing: the menu finds them itself.
4. Open a **terminal as administrator** in the Nilesoft Shell folder and run:
   ```
   shell.exe -register -treat -restart
   ```
   (`-treat` turns off the short Windows 11 menu, `-restart` restarts Explorer).
5. If you have Intel graphics (or GPU encoding did not show up), right-click any video →
   **FFmpeg → Settings → Check graphics card**.

---

## Required programs

| Program | For | Required? | Where to get it |
|---|---|---|---|
| **Nilesoft Shell** 1.9.18 or newer | The menu itself | **Yes** | <https://nilesoft.org/download> · `winget install Nilesoft.Shell` |
| **FFmpeg** 7.0 or newer | The "FFmpeg" menu: video, audio, images | No | <https://www.gyan.dev/ffmpeg/builds/> · `winget install Gyan.FFmpeg` |
| **Everything** | The "Find in Everything" menu | No | <https://www.voidtools.com/> · `winget install voidtools.Everything` |
| **LosslessCut** | The "Open in LosslessCut" item | No | <https://github.com/mifi/lossless-cut/releases> (Windows archive) |
| **WinRAR** | The "WinRar" menu (extract and archive) | No | <https://www.win-rar.com/> · `winget install RARLab.WinRAR` |
| **NVIDIA, AMD or Intel** graphics with a driver | Fast video encoding on the graphics card | No | Your normal graphics driver |
| VS Code, .NET SDK | The hidden "Develop" menu (Shift + right-click) | No | For programmers only |

Already part of Windows, nothing to install: PowerShell 5.1, curl, disk check, ISO mounting.

### Which FFmpeg version

- **FFmpeg 7.0 or newer.** Tested with 8.0.1 and 9.0.2. On 6.x and older some items may fail
  (lossless rotation, for example). The setup warns you if the version is old.
- You need a build **with x264 and x265** (a GPL build). Both builds from gyan.dev work,
  `essentials` and `full`: they have everything the menu uses (x264, x265, AV1, WebP, stabilization,
  GPU encoders). BtbN builds work too, but only the `gpl` variant, not `lgpl`.
  `winget install Gyan.FFmpeg` installs the full build.
- Manual way: download `ffmpeg-release-essentials.7z` (or `full`) and extract it anywhere
  (for example `C:/ffmpeg`). Inside there is a `bin` folder with `ffmpeg.exe`, `ffprobe.exe` and `ffplay.exe`.

### Encoding on the graphics card

The menu can encode video on the graphics card, which is many times faster than the CPU:

| Graphics | Technology | Needs |
|---|---|---|
| NVIDIA GeForce GTX 900 and newer | NVENC | A recent NVIDIA driver |
| AMD Radeon RX 400 and newer, Ryzen CPUs with integrated graphics | AMF | AMD Adrenalin driver |
| Intel integrated graphics (6th gen Core and newer), Intel Arc | Quick Sync | Intel driver |

The card is detected automatically: the menu tries to encode half a second of test video and remembers
what worked. Not every older card can do H.265; then the CPU handles H.265.
Without a suitable card the "on the graphics card" items are hidden and the CPU does everything
(slower, but even better quality per megabyte).

Turn it on in the menu: **FFmpeg → Settings → Encode video on the graphics card**.
After changing the card or the driver: **FFmpeg → Settings → Check graphics card**.

> To be honest: NVIDIA encoding is tested on a real card. For AMD and Intel the settings were checked
> against the documentation and ffmpeg itself, but the preset has not been run on real AMD or Intel graphics yet.
> If something is wrong, turn GPU encoding off and report it in Issues.

**About Everything.** The regular installer version is best: it installs a service and sees all drives.
The portable version needs administrator rights to index drives (turn on "Run as administrator"
in its settings or install the Everything service).

**About WinRAR.** If you use 7-Zip or another archiver, no problem: the WinRar menu just does not
appear, and your archiver keeps its own items.

---

## Does it matter where programs are installed?

**No.** Programs are found automatically:

1. The setup looks everywhere: in PATH, among installed and running programs and in folders
   with a similar name on all drives (for example `D:/Soft/ffmpeg-9.0/bin`). The paths it finds are
   written to `imports/paths.nss` in the Nilesoft Shell folder.
2. Even without the setup the menu checks the usual places itself: `Program Files`, winget, scoop
   and chocolatey folders, `C:/ffmpeg/bin`.

If you **moved a program** to another folder, run `Install.cmd` again or open
`imports/paths.nss` in the Nilesoft Shell folder and put the path into the top lines:

```
$ff_bin_user = 'D:\Soft\FFmpeg\bin'                    // folder that contains ffmpeg.exe
$ev_exe_user = 'C:\Program Files\Everything\Everything.exe'
$lc_exe_user = 'D:\Soft\LosslessCut\LosslessCut.exe'
```

Empty quotes `''` mean "find it yourself". The only limitation: the path must not contain an apostrophe `'`.

## Do I need to add anything to PATH?

**No.** The menu starts programs by their full path and does not need PATH.
Add FFmpeg to PATH only if you want to type `ffmpeg` in a terminal yourself:
Settings → System → About → Advanced system settings → Environment Variables →
`Path` → New → the path to the `bin` folder. Installing with winget adds it to PATH for you.
For the "Develop" menu the `code` command must work in a terminal; the VS Code installer sets that up.

---

## What happens if a program is missing

Nothing breaks: that program's items are simply **not shown**.

| Missing | In the menu |
|---|---|
| FFmpeg | No "FFmpeg" menu. Everything else works |
| Everything | No "Find in Everything" menu |
| LosslessCut | No "Open in LosslessCut" item |
| WinRAR | No "WinRar" menu |
| A graphics card that can encode video | No "on the graphics card" items and no GPU setting in the FFmpeg menu. The CPU encodes everything |
| VS Code / .NET | Items in the hidden "Develop" menu will not work (the menu itself only shows with Shift) |
| Hibernation turned off in Windows | No "Hibernate" item in the "Power" menu |

Rules for other programs (Win 10 Tweaker, VLC, MPC-HC, AIMP, Git, VS Code, Adobe Acrobat, NVIDIA)
gather their items into the "Programs" and "Access" submenus. Without those programs the rules find nothing,
and empty submenus are not shown.

---

## Troubleshooting

- **The menu did not change.** Restart Explorer or the computer. If that does not help, open a terminal
  as administrator in the Nilesoft Shell folder and run `shell.exe -register -treat -restart`.
- **All items are gone or the menu looks odd.** Nilesoft writes errors to `shell.log` in its folder.
  Usually it is a typo after editing a `.nss` file by hand. Restore the file from `backup` or run the setup again.
- **The FFmpeg window closed with an error.** FFmpeg → Settings → turn on "Always wait for Enter at the end",
  repeat and read the error message.
- **An error when encoding on the graphics card.** Turn off "FFmpeg → Settings → Encode video on the graphics card"
  and update the graphics driver. Then "Check graphics card" again.
- **The antivirus complains about scripts.** Menu items start the PowerShell scripts `ffmpeg-run.ps1` and
  `tools-run.ps1` from the `imports` folder. They are plain text files you can open and read.
- **Windows in another language.** Everything works, but a couple of system items may stay where they are:
  the rules that move them know the English and Russian names of system items.
- **Windows 10.** It should work, but the preset was only tested on Windows 11. Windows 10 does not have
  the theme font (Segoe UI Variable), so the menu uses the standard font.

## Uninstall

- Get your old menu back: copy `shell.nss` and `imports` from `Nilesoft Shell/backup/before-preset-<date>`
  back into the Nilesoft Shell folder and restart Explorer.
- Remove Nilesoft Shell completely: uninstall it in Settings → Apps (or in a terminal as
  administrator: `shell.exe -unregister -restart`, then delete the folder).
- FFmpeg menu settings live in the registry: `HKEY_CURRENT_USER/Software/Nilesoft-FFmpeg-menu`
  (you can delete that key). The rename undo file: `%LOCALAPPDATA%/Nilesoft-tools-rename-undo.json`.

---

## Make it yours

The menu is described by `.nss` text files (open them in Notepad or VS Code). Everything about the
configuration language, themes and icons is in the Nilesoft Shell documentation:

- Documentation: <https://nilesoft.org/docs>
- Icons (glyphs) for menu items: <https://nilesoft.org/glyphs>
- Nilesoft Shell source code: <https://github.com/moudey/Shell>
- Nilesoft Shell community on Discord (themes and ready-made snippets): <https://discord.gg/Mg3tum2sd8>
- A large library of ready-made snippets: <https://github.com/RubicBG/Nilesoft-Shell-Snippets>

A few quick tips:

- **Transparency and colors**: `imports/theme.nss` (`opacity`: lower = more transparent).
- **Program paths**: `imports/paths.nss`.
- **Remove a whole menu**: in `shell.nss` put `//` in front of its `import 'imports/...'` line.
- After an edit, save the file and restart Explorer (or the computer). Make a copy of the file before editing.
  If the menu disappears, look at `shell.log` in the Nilesoft Shell folder: it says which line is wrong.

## Credits and licenses

- This preset: MIT license, see [LICENSE](LICENSE).
- Nilesoft Shell and its default menu files (`images.nss`, the base of `goto`, `terminal`, `file-manage`, `taskbar`, `develop`, `modify`): © Moudey, MIT license.
- The WinRAR menu is based on a RubicBG snippet (CC0); the tools are rewritten after his library.
