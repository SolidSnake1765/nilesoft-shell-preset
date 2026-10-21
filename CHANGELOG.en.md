**English** | [Русский](CHANGELOG.md)

# Changelog

All notable changes to the preset. Newest versions first.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versions follow [SemVer](https://semver.org/):
`MAJOR.MINOR.PATCH` (minor = new features, patch = fixes).

## [1.1.0] - 2026-10-21

### Added
- **11 menu themes**: Acrylic (the old theme, default), Modern, Light, Neon, Dracula, Nord, Codec, Sunset,
  macOS, Turquoise glass, Fluent. Pick one in the setup and switch any time:
  Shift + right-click the taskbar > Nilesoft Shell > Theme, without restarting Explorer.
  Themes live in `imports/themes/` instead of `imports/theme.nss` (the setup removes the old file, a copy is in `backup`).
- **GIF → MP4 like Telegram**: a regular video instead of a GIF, many times smaller and smoother.
- **Telegram sticker** (WEBM, VP9, 512 px, up to 3 seconds, no audio) from a video or a GIF; transparency is kept.
- "Make from video": **square 1:1** (the video centered over a blurred copy) and **boomerang** (forward and back).
- Images: **crop to a square** from the center and a **collage** of the selected images, in a row or in a column.
- Audio: an **Effects** menu (fade in and out, mono, Slowed + reverb, Nightcore) and an **iPhone ringtone** (M4R, 30 seconds).

### Changed
- "Pick audio tracks" (was "Pick an audio track"): keep several tracks at once with
  "1 3", "1,3" or "2-4"; the first one becomes the default track. The numbers are asked once for all selected files.

- "Louder", "Quieter", "Normalize loudness" and "Clean up voice noise" ask which tracks to change for videos with
  several audio tracks (Enter = all). The others are copied unchanged, bit for bit.

### Fixed
- The track list shows the real track names like MPC-HC does (for example "Mic" or "Desktop audio" in OBS recordings),
  plus sample rate, mono/stereo and bitrate. It used to say only "language not set".
- "Extract audio" failed on videos with several audio tracks (OBS recordings, for example): MP3, WAV, FLAC and others
  hold one track. Now it asks which tracks to extract (Enter = all) and saves each to its own file
  named after the track: "video (Mic).mp3". "As is (MKA)" asks too, but puts the picked tracks into one file.
  With a single track nothing is asked.
- Audio track names are no longer lost by operations without re-encoding: picking tracks, remuxing
  to MP4 / MKV, fast trim, splitting into parts, volume, stripping metadata.
- Operations that re-encode the video (compress, downscale, trim, speed, enhancements and others) kept
  only one of several audio tracks. Now all of them are kept, with their names.
- Videos with a cover inside (common in downloaded MP4s): GIF, frames, speed and exact trim took the cover
  instead of the video itself.
- Videos with an odd frame size (for example 641×361) failed to encode to H.264 / H.265; the size is now rounded to even.
- Audio operations on a video without audio failed with a cryptic ffmpeg error; now they say "The video has no audio".
- Converting audio to M4A and FLAC lost the cover.
- An image with transparency got a black background in JPG; now it is white.
- H.265 from a 10-bit or 4:4:4 video came out the same and might not play on phones and TVs; now it is always 8-bit 4:2:0.

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
- A `dev/` folder for those who want to change the menu: file generators, the translation dictionary and a checker
  (comments in English; the hints in `paths.nss` are in the menu language).

[Unreleased]: https://github.com/SolidSnake1765/nilesoft-shell-preset/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/SolidSnake1765/nilesoft-shell-preset/releases/tag/v1.1.0
[1.0.0]: https://github.com/SolidSnake1765/nilesoft-shell-preset/releases/tag/v1.0.0
