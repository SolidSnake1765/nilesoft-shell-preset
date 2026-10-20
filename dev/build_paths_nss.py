"""Build imports/paths.nss: where the menu looks for ffmpeg, Everything and LosslessCut.

Usage: python -I build_paths_nss.py <output> [ffmpeg bin dir] [Everything.exe] [LosslessCut.exe]

Empty values mean "search the usual install places". BS stands for a backslash, so no
backslashes pass through tools that might treat them as escapes. The installer
(install.ps1) fills the three *_user lines with the same format.
"""
import sys

out = sys.argv[1]
user = (sys.argv[2:] + ['', '', ''])[:3]
BSL = chr(92)


def chain(name, user_var, check, candidates):
    """Variables name_1..name_N: keep the previous value when check(prev) exists, else take the next candidate.

    The last one becomes $name. If nothing exists, $name ends up as the last candidate,
    path.exists() on it is false and the menu that needs it stays hidden.
    """
    lines = []
    prev = user_var
    for i, cand in enumerate(candidates, 1):
        var = f'{name}_{i}' if i < len(candidates) else name
        lines.append(f'${var} = eval(if(path.exists({check(prev)}), {prev}, {cand}))')
        prev = var
    return lines


ff_check = lambda v: f"path.combine({v}, 'ffmpeg.exe')"
ev_check = lambda v: v
lc_check = lambda v: v
local = "path.combine(user.dir, 'AppData', 'Local')"

ff = chain('ff_bin', 'ff_bin_user', ff_check, [
    f"path.combine({local}, 'Microsoft', 'WinGet', 'Links')",          # winget install Gyan.FFmpeg
    "path.combine(sys.prog, 'WinGet', 'Links')",                        # winget --scope machine
    "path.combine(user.dir, 'scoop', 'apps', 'ffmpeg', 'current', 'bin')",
    "path.combine(sys.programdata, 'chocolatey', 'lib', 'ffmpeg', 'tools', 'ffmpeg', 'bin')",
    "path.combine(sys.programdata, 'chocolatey', 'bin')",
    "path.combine(sys.prog, 'ffmpeg', 'bin')",
    "'C:BSffmpegBSbin'",
])
ev = chain('ev_exe', 'ev_exe_user', ev_check, [
    "path.combine(sys.prog, 'Everything', 'Everything.exe')",           # обычный установщик, winget voidtools.Everything
    "path.combine(sys.prog32, 'Everything', 'Everything.exe')",
    "path.combine(sys.prog, 'Everything 1.5a', 'Everything64.exe')",    # Everything 1.5 (бета)
    "path.combine(user.dir, 'scoop', 'apps', 'everything', 'current', 'Everything.exe')",
])
lc = chain('lc_exe', 'lc_exe_user', lc_check, [
    "path.combine(sys.prog, 'LosslessCut', 'LosslessCut.exe')",
    f"path.combine({local}, 'Programs', 'LosslessCut', 'LosslessCut.exe')",
    "path.combine(user.dir, 'scoop', 'apps', 'losslesscut', 'current', 'LosslessCut.exe')",
])


def q(v):
    return "'" + v.replace(BSL, 'BS') + "'"


text = f"""// Пути к программам, которые использует меню.
// Пустые кавычки = искать в обычных местах установки (список ниже). Если программа стоит
// в другом месте — впиши путь в кавычки. Установщик (Install.cmd) заполняет эти строки сам.
// Если программа не найдена, её пункты просто не показываются в меню.
$ff_bin_user = {q(user[0])}    // папка, где лежит ffmpeg.exe (обычно ...BSbin)
$ev_exe_user = {q(user[1])}    // полный путь к Everything.exe
$lc_exe_user = {q(user[2])}    // полный путь к LosslessCut.exe

// ---------- дальше трогать не нужно ----------
// Каждая строка: если предыдущий вариант существует — оставить его, иначе взять следующий.

// FFmpeg: winget, scoop, chocolatey, Program Files, C:BSffmpeg
""" + '\n'.join(ff) + """

// Everything
""" + '\n'.join(ev) + """

// LosslessCut
""" + '\n'.join(lc) + """

// Подсказка, есть ли видеокарта для кодирования видео, пока FFmpeg её не проверил:
// драйвер NVIDIA кладёт в System32 nvidia-smi.exe, драйвер AMD — amfrt64.dll.
// Встроенную графику Intel так не узнать — для неё «FFmpeg → Настройки → Проверить видеокарту».
$has_gpu_hint = path.exists(path.combine(sys.bin, 'nvidia-smi.exe')) or path.exists(path.combine(sys.bin, 'amfrt64.dll'))
"""
text = text.replace('BS', BSL)
open(out, 'w', encoding='utf-8', newline='\r\n').write(text)
print('written', out)
