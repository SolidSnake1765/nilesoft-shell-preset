**English** | [Русский](MENU.md)

# What is in the menu

Items appear only where they make sense: the FFmpeg menu only on video, audio and images,
"Power" only on the desktop and the taskbar, and so on. Almost every item has a tooltip:
hover over it for a second.

How to make the menu yours: [README.en.md](README.en.md#make-it-yours).

---

## Files and folders

### FFmpeg
*(needs FFmpeg; on video, audio and images; works on several selected files at once)*

Processing opens in a window with a progress bar, time left and the load on the CPU,
memory and graphics card. **Esc** or **Q** cancels: the unfinished file is deleted, the source is untouched.

- **Mode: copy / replace** (the first item, click to switch).
  *Copy* saves the result next to the source under a new name. *Replace* gives the result the source name
  and moves the source to the Recycle Bin (it is not deleted for good). New files (GIF, audio from a video,
  frames) are always created separately.
- **Settings**: save copies to the "FFmpeg" subfolder; encode video on the graphics card (NVIDIA, AMD
  or Intel, shown only if your card can do it); always wait for Enter at the end; beep when done;
  show the result in Explorer; **check graphics card** (after changing the card or the driver).

**Video**
- **To MP4 without quality loss**: for files that Telegram and phones do not accept as video.
  "Automatic" copies a suitable video without re-encoding and re-encodes the rest almost losslessly.
  You can also choose H.264 / H.265 on the CPU or on the graphics card.
- **Compress**: H.264 (plays everywhere), H.265 (smaller but slower), on the graphics card (fast).
- **Fit into a size limit**: guaranteed to fit: Discord 20 MB / 10 MB, Catbox 200 MB
  or a custom size. Resolution and frame rate are picked for the video length.
  Options: balanced, smooth (60 fps), sharp (30 fps), H.265.
- **Downscale** to 1080p / 720p / 480p.
- **Trim**: fast without re-encoding (at keyframes) or exact; asks for start and end.
- **Speed**, **frame rate**, **rotate / flip** (including instant rotation without re-encoding).
- **Enhance**: stabilization, denoise, sharpen, remove black bars, deinterlace,
  smooth 60 fps by frame interpolation.
- **Remux** to MP4 / MKV without re-encoding.
- **Join the selected**, **split into parts** of N minutes, **strip metadata** (GPS, camera, dates).
- **Subtitles**: extract, add the `.srt` file next to the video, or burn into the picture.
- **Audio**: extract to MP3 / M4A / AAC / OPUS / OGG / FLAC / WAV / AIFF or as is; remove audio;
  pick a track; clean up voice noise; louder / quieter; normalize loudness.
- **Make from video**: GIF (three sizes), vertical 9:16 for Shorts / TikTok / Reels,
  frame from the middle, 4×4 thumbnail grid, reverse, frames every N seconds, teaser.

**Audio**: convert to MP3 / M4A / OPUS / OGG / FLAC / WAV / AIFF, louder / quieter, normalize loudness,
trim silence at both ends, trim, speed, join, split, clean up noise, make a video
(with the cover or a waveform), spectrogram, strip metadata.

**Images**: convert to JPG / PNG / WebP / AVIF / ICO, compress for websites, upscale ×2–×10,
downscale, rotate / flip, black and white, slideshow from the selected images.

**More**: "Video + music" (select one video and one audio file to replace the audio or add background music),
check a file for broken parts, file info, play in ffplay, FFmpeg version (hold Shift).

### Tools
- **Hash (checksum)**: show MD5 / SHA-1 / SHA-256, copy, verify against a hash from the clipboard,
  compare two files, create and verify a checksum file.
- **Rename** (many files at once): letter case, spaces and underscores, dots → spaces,
  add a prefix / suffix, find and replace, number, change extension.
  It shows a preview first and asks for confirmation. There is **undo last rename**.
- **Share as a link**: upload a file to temp.sh (up to 4 GB, 3 days) or uguu.se (up to 128 MB, 3 hours),
  the link is copied to the clipboard. **Warning:** anyone with the link can download the file.
  Do not upload anything private.
- **Disk image** (on `.iso` and `.img`): mount and open / unmount.

### Find in Everything
*(needs Everything)*: instant search in this folder, on the whole drive, only video / images / music /
documents / archives / programs / folders, large files, modified today or this week,
files with the same extension or the same name (finding copies).

### File manage
- **Copy path**: full path, folder, name, name without extension, extension; paths of several files at once.
- **Change extension**.
- **Select**: all, invert, none; **smart select** in the current folder: by type (video, images,
  music, documents, archives, folders only, files only), by size, by date, same extension,
  by mask (for example `*2024*.jpg`).
- **Take ownership**, **show / hide** system files and extensions,
  **attributes** (hidden, system, read-only), **register DLL**.
- **New folder** with the date or a random name, **new file** (TXT, XML, JSON, HTML).

### Open in LosslessCut
*(needs LosslessCut; on video and audio)*: fast trimming without re-encoding in a separate program.

### WinRar
*(needs WinRAR)*: extract here / to a folder / each archive to its own folder (with Shift, also delete the archive),
add to an archive, convert, test, repair archives.

### Terminal
Command Prompt, PowerShell or Windows Terminal in the current folder.
Hold **Shift** to run as administrator.

### Go to
Quick access to system folders (Windows, Program Files, AppData, Downloads, Temp…), Control Panel
and Settings pages.

### Submenus that collect other items
- **Pin/Unpin**: the "Pin to Start / taskbar" items.
- **More options** (a standard Nilesoft submenu, its name follows the Windows language): rarely used system
  items like Send to, Share, Create shortcut, Print.
- **Programs**: items of Git, VS Code, Compress Folder, Adobe Acrobat and media players (on folders).
- **Access**: Win 10 Tweaker items about ownership and internet access.

Without those programs these submenus simply do not appear.

### Develop
*(only with Shift held)*: open in VS Code or Notepad, `dotnet` commands (run, build, publish…).

---

## Drives
- **Drive maintenance**: Disk Cleanup, optimize (defragment / TRIM), check for errors,
  Disk Management.
- **Eject mounted image**: on a virtual drive with an ISO.

## Desktop and taskbar
- **Power**: lock, sleep, hibernate (if enabled in Windows), restart, shut down,
  shut down on a timer (15 minutes to 3 hours, can be cancelled), restart to BIOS/UEFI,
  advanced startup, sign out. Everything that turns the computer off
  asks for confirmation first ("No" is the default).
- **Taskbar**: apps (Paint, Edge, Calculator, Registry Editor), window arrangement,
  desktop, settings, Task Manager.
  With Shift: the Nilesoft Shell menu itself: configuration, program folder, documentation.
