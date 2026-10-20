**English** | [Русский](CHANGELOG.md)

# Changelog

All notable changes to the preset. Newest versions first.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versions follow [SemVer](https://semver.org/):
`MAJOR.MINOR.PATCH` (minor = new features, patch = fixes).

## [Unreleased]

### Changed
- Comments in `dev/` and the header comments of the menu files (`ffmpeg.nss`, `tools.nss`) are in English.
  The hints in `paths.nss`, which users edit, stay in the menu language.

## [1.0.0] - 2026-10-20

First release.

### Added
- **FFmpeg menu** for video, audio and images: MP4 without quality loss (including for Telegram), H.264 / H.265 compression,
  "Fit into a size limit" (Discord 20 and 10 MB, Catbox 200 MB, custom size), downscale, trim, speed, frame rate,
  rotation (including without re-encoding), enhancements (stabilization, denoise, sharpen, black bars,
  deinterlace, 60 fps), remux, join, split, metadata, subtitles, audio tracks, GIF, 9:16,
  frames, thumbnails, "Video + music", file error check.
- **Copy / replace** modes (the source goes to the Recycle Bin), settings right in the menu.
- Processing window with a progress bar, time left and CPU, memory and GPU load; Esc cancels.
- **GPU encoding**: NVIDIA NVENC, AMD AMF, Intel Quick Sync, detected automatically
  ("Check graphics card" item). AMD and Intel are not yet tested on real hardware.
- **Tools**: hashes (MD5 / SHA-1 / SHA-256, verify, checksum file), batch rename
  with preview and undo, share as a link (temp.sh / uguu.se), disk image mounting.
- **Find in Everything**, **smart select** in the Explorer window, **Power** menu with a shutdown timer,
  drive maintenance, terminals, quick access to system folders and settings.
- Theme based on modern: translucent acrylic background, rounded corners, shadow, Windows accent color.
- Menu in **English and Russian**.
- **Installer** `Install.cmd`: finds Nilesoft Shell (installed or portable), backs up the old menu,
  looks for ffmpeg, Everything and LosslessCut on all drives, checks the ffmpeg version and the graphics card, registers Nilesoft.
- Manual setup, a portability section and a description of every item in the README.
- Items of programs that are not installed are hidden instead of showing greyed out.

[Unreleased]: https://github.com/SolidSnake1765/nilesoft-shell-preset/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/SolidSnake1765/nilesoft-shell-preset/releases/tag/v1.0.0
