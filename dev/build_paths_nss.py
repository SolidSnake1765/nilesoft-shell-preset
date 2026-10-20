"""Build imports/paths.nss: where the menu looks for ffmpeg, Everything and LosslessCut.

Usage: python -I build_paths_nss.py <output> [ffmpeg bin dir] [Everything.exe] [LosslessCut.exe] [--lang ru|en]

Empty values mean "search the usual install places". BS stands for a backslash, so no
backslashes pass through tools that might treat them as escapes. The installer
(install.ps1) fills the three *_user lines with the same format.
Users edit this file by hand, so its comments come in the menu language (see NOTES).
"""
import sys

args = sys.argv[1:]
lang = 'ru'
if '--lang' in args:
    i = args.index('--lang')
    lang = args[i + 1]
    del args[i:i + 2]
out = args[0]
user = (args[1:] + ['', '', ''])[:3]
BSL = chr(92)

# Comments of the generated file, in the language of the menu
NOTES = {
    'en': {
        'head': [
            'Paths to the programs the menu uses.',
            'Empty quotes = look in the usual install places (listed below). If a program is installed',
            'somewhere else, put its path in the quotes. The installer (Install.cmd) fills these lines itself.',
            'If a program is not found, its items are simply not shown in the menu.',
        ],
        'ff': 'folder that contains ffmpeg.exe (usually ...BSbin)',
        'ev': 'full path to Everything.exe',
        'lc': 'full path to LosslessCut.exe',
        'below': '---------- no need to touch anything below ----------',
        'chain': 'Each line: if the previous candidate exists, keep it, otherwise take the next one.',
        'gpu': [
            'Hint whether there is a graphics card for video encoding, until FFmpeg has checked it:',
            'the NVIDIA driver puts nvidia-smi.exe into System32, the AMD driver puts amfrt64.dll there.',
            'Intel graphics cannot be detected this way - use "FFmpeg > Settings > Check graphics card" for it.',
        ],
    },
    'ru': {
        'head': [
            'Пути к программам, которые использует меню.',
            'Пустые кавычки = искать в обычных местах установки (список ниже). Если программа стоит',
            'в другом месте — впиши путь в кавычки. Установщик (Install.cmd) заполняет эти строки сам.',
            'Если программа не найдена, её пункты просто не показываются в меню.',
        ],
        'ff': 'папка, где лежит ffmpeg.exe (обычно ...BSbin)',
        'ev': 'полный путь к Everything.exe',
        'lc': 'полный путь к LosslessCut.exe',
        'below': '---------- дальше трогать не нужно ----------',
        'chain': 'Каждая строка: если предыдущий вариант существует — оставить его, иначе взять следующий.',
        'gpu': [
            'Подсказка, есть ли видеокарта для кодирования видео, пока FFmpeg её не проверил:',
            'драйвер NVIDIA кладёт в System32 nvidia-smi.exe, драйвер AMD — amfrt64.dll.',
            'Встроенную графику Intel так не узнать — для неё «FFmpeg → Настройки → Проверить видеокарту».',
        ],
    },
}[lang]


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
    "path.combine(sys.prog, 'Everything', 'Everything.exe')",           # regular installer, winget voidtools.Everything
    "path.combine(sys.prog32, 'Everything', 'Everything.exe')",
    "path.combine(sys.prog, 'Everything 1.5a', 'Everything64.exe')",    # Everything 1.5 (beta)
    "path.combine(user.dir, 'scoop', 'apps', 'everything', 'current', 'Everything.exe')",
])
lc = chain('lc_exe', 'lc_exe_user', lc_check, [
    "path.combine(sys.prog, 'LosslessCut', 'LosslessCut.exe')",
    f"path.combine({local}, 'Programs', 'LosslessCut', 'LosslessCut.exe')",
    "path.combine(user.dir, 'scoop', 'apps', 'losslesscut', 'current', 'LosslessCut.exe')",
])


def q(v):
    return "'" + v.replace(BSL, 'BS') + "'"


def comments(lines):
    return '\n'.join('// ' + line for line in lines)


text = comments(NOTES['head']) + f"""
$ff_bin_user = {q(user[0])}    // {NOTES['ff']}
$ev_exe_user = {q(user[1])}    // {NOTES['ev']}
$lc_exe_user = {q(user[2])}    // {NOTES['lc']}

// {NOTES['below']}
// {NOTES['chain']}

// FFmpeg: winget, scoop, chocolatey, Program Files, C:BSffmpeg
""" + '\n'.join(ff) + """

// Everything
""" + '\n'.join(ev) + """

// LosslessCut
""" + '\n'.join(lc) + """

""" + comments(NOTES['gpu']) + """
$has_gpu_hint = path.exists(path.combine(sys.bin, 'nvidia-smi.exe')) or path.exists(path.combine(sys.bin, 'amfrt64.dll'))
"""
text = text.replace('BS', BSL)
open(out, 'w', encoding='utf-8', newline='\r\n').write(text)
print('written', out)
