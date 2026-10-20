// Paths to the programs the menu uses.
// Empty quotes = look in the usual install places (listed below). If a program is installed
// somewhere else, put its path in the quotes. The installer (Install.cmd) fills these lines itself.
// If a program is not found, its items are simply not shown in the menu.
$ff_bin_user = ''    // folder that contains ffmpeg.exe (usually ...\bin)
$ev_exe_user = ''    // full path to Everything.exe
$lc_exe_user = ''    // full path to LosslessCut.exe

// ---------- no need to touch anything below ----------
// Each line: if the previous candidate exists, keep it, otherwise take the next one.

// FFmpeg: winget, scoop, chocolatey, Program Files, C:\ffmpeg
$ff_bin_1 = eval(if(path.exists(path.combine(ff_bin_user, 'ffmpeg.exe')), ff_bin_user, path.combine(path.combine(user.dir, 'AppData', 'Local'), 'Microsoft', 'WinGet', 'Links')))
$ff_bin_2 = eval(if(path.exists(path.combine(ff_bin_1, 'ffmpeg.exe')), ff_bin_1, path.combine(sys.prog, 'WinGet', 'Links')))
$ff_bin_3 = eval(if(path.exists(path.combine(ff_bin_2, 'ffmpeg.exe')), ff_bin_2, path.combine(user.dir, 'scoop', 'apps', 'ffmpeg', 'current', 'bin')))
$ff_bin_4 = eval(if(path.exists(path.combine(ff_bin_3, 'ffmpeg.exe')), ff_bin_3, path.combine(sys.programdata, 'chocolatey', 'lib', 'ffmpeg', 'tools', 'ffmpeg', 'bin')))
$ff_bin_5 = eval(if(path.exists(path.combine(ff_bin_4, 'ffmpeg.exe')), ff_bin_4, path.combine(sys.programdata, 'chocolatey', 'bin')))
$ff_bin_6 = eval(if(path.exists(path.combine(ff_bin_5, 'ffmpeg.exe')), ff_bin_5, path.combine(sys.prog, 'ffmpeg', 'bin')))
$ff_bin = eval(if(path.exists(path.combine(ff_bin_6, 'ffmpeg.exe')), ff_bin_6, 'C:\ffmpeg\bin'))

// Everything
$ev_exe_1 = eval(if(path.exists(ev_exe_user), ev_exe_user, path.combine(sys.prog, 'Everything', 'Everything.exe')))
$ev_exe_2 = eval(if(path.exists(ev_exe_1), ev_exe_1, path.combine(sys.prog32, 'Everything', 'Everything.exe')))
$ev_exe_3 = eval(if(path.exists(ev_exe_2), ev_exe_2, path.combine(sys.prog, 'Everything 1.5a', 'Everything64.exe')))
$ev_exe = eval(if(path.exists(ev_exe_3), ev_exe_3, path.combine(user.dir, 'scoop', 'apps', 'everything', 'current', 'Everything.exe')))

// LosslessCut
$lc_exe_1 = eval(if(path.exists(lc_exe_user), lc_exe_user, path.combine(sys.prog, 'LosslessCut', 'LosslessCut.exe')))
$lc_exe_2 = eval(if(path.exists(lc_exe_1), lc_exe_1, path.combine(path.combine(user.dir, 'AppData', 'Local'), 'Programs', 'LosslessCut', 'LosslessCut.exe')))
$lc_exe = eval(if(path.exists(lc_exe_2), lc_exe_2, path.combine(user.dir, 'scoop', 'apps', 'losslesscut', 'current', 'LosslessCut.exe')))

// Hint whether there is a graphics card for video encoding, until FFmpeg has checked it:
// the NVIDIA driver puts nvidia-smi.exe into System32, the AMD driver puts amfrt64.dll there.
// Intel graphics cannot be detected this way - use "FFmpeg > Settings > Check graphics card" for it.
$has_gpu_hint = path.exists(path.combine(sys.bin, 'nvidia-smi.exe')) or path.exists(path.combine(sys.bin, 'amfrt64.dll'))
