// Пути к программам, которые использует меню.
// Пустые кавычки = искать в обычных местах установки (список ниже). Если программа стоит
// в другом месте — впиши путь в кавычки. Установщик (Install.cmd) заполняет эти строки сам.
// Если программа не найдена, её пункты просто не показываются в меню.
$ff_bin_user = ''    // папка, где лежит ffmpeg.exe (обычно ...\bin)
$ev_exe_user = ''    // полный путь к Everything.exe
$lc_exe_user = ''    // полный путь к LosslessCut.exe

// ---------- дальше трогать не нужно ----------
// Каждая строка: если предыдущий вариант существует — оставить его, иначе взять следующий.

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

// Подсказка, есть ли видеокарта для кодирования видео, пока FFmpeg её не проверил:
// драйвер NVIDIA кладёт в System32 nvidia-smi.exe, драйвер AMD — amfrt64.dll.
// Встроенную графику Intel так не узнать — для неё «FFmpeg → Настройки → Проверить видеокарту».
$has_gpu_hint = path.exists(path.combine(sys.bin, 'nvidia-smi.exe')) or path.exists(path.combine(sys.bin, 'amfrt64.dll'))
