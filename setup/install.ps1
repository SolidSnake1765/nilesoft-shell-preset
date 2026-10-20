# Installer for the Nilesoft Shell context menu preset. Started by Install.cmd.
# Установщик пресета контекстного меню для Nilesoft Shell. Запускается из Install.cmd.
#
#   1. finds the Nilesoft Shell folder (or asks for it);
#   2. backs up the current menu to <Nilesoft Shell>/backup/;
#   3. copies the preset (config/ru or config/en);
#   4. finds ffmpeg, Everything and LosslessCut and writes their paths to imports/paths.nss;
#   5. checks which graphics card can encode video;
#   6. registers Nilesoft Shell and restarts Explorer.
# Dry run: -Target <folder> -NoRegister -Yes -NoElevate [-Lang ru|en]

[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Target = '',     # Nilesoft Shell folder (where shell.exe is)
    [ValidateSet('', 'ru', 'en')][string]$Lang = '',   # menu language; empty = ask (default from Windows)
    [switch]$NoRegister,      # do not register / restart Explorer
    [switch]$Yes,             # no questions: take the first found option
    [switch]$NoElevate        # do not ask for administrator rights
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot

# Installer messages follow the Windows language; the menu language is chosen below
$script:ru = ((Get-UICulture).TwoLetterISOLanguageName -eq 'ru')
if ($Lang) { $script:ru = ($Lang -eq 'ru') }
function T([string]$ru, [string]$en) { if ($script:ru) { return $ru } else { return $en } }
function Say([string]$text, [string]$color = 'Gray') { Write-Host $text -ForegroundColor $color }
function Done([int]$code = 0) {
    if (-not $Yes) { Write-Host ''; Read-Host (T 'Нажми Enter, чтобы закрыть окно' 'Press Enter to close this window') | Out-Null }
    exit $code
}

# ---------- Administrator rights ----------
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $NoElevate) {
    $argLine = '-NoProfile -ExecutionPolicy Bypass -File "' + $PSCommandPath + '"'
    if ($Target) { $argLine += ' -Target "' + $Target + '"' }
    if ($Lang) { $argLine += ' -Lang ' + $Lang }
    if ($NoRegister) { $argLine += ' -NoRegister' }
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argLine -Verb RunAs
    } catch {
        Say (T 'Без прав администратора установить не получится: Nilesoft Shell лежит в Program Files и регистрируется в системе.' `
               'Administrator rights are required: Nilesoft Shell lives in Program Files and is registered in Windows.') Yellow
        Say (T 'Запусти Install.cmd ещё раз и нажми «Да».' 'Run Install.cmd again and click "Yes".') Yellow
        Done 1
    }
    exit 0
}

$Host.UI.RawUI.WindowTitle = T 'Установка пресета Nilesoft Shell' 'Nilesoft Shell preset setup'
Say ''
Say (T '  Пресет контекстного меню для Nilesoft Shell' '  Context menu preset for Nilesoft Shell') Cyan
Say '  -------------------------------------------' Cyan

# ---------- Menu language ----------
if (-not $Lang) {
    $Lang = $(if ($script:ru) { 'ru' } else { 'en' })
    if (-not $Yes) {
        Say ''
        Say (T 'Язык меню:  [1] Русский   [2] English' 'Menu language:  [1] Русский   [2] English') Cyan
        $def = $(if ($Lang -eq 'ru') { '1' } else { '2' })
        $a = (Read-Host (T "Enter — $def" "Enter = $def")).Trim()
        if ($a -eq '1') { $Lang = 'ru' } elseif ($a -eq '2') { $Lang = 'en' }
    }
}
$ConfigDir = Join-Path (Join-Path $Root 'config') $Lang
if (-not (Test-Path -LiteralPath (Join-Path $ConfigDir 'shell.nss'))) {
    Say (T "Не найдены файлы пресета: $ConfigDir. Распакуй архив целиком." "Preset files not found: $ConfigDir. Extract the whole archive.") Red
    Done 1
}

# ---------- Helpers ----------
function Get-SubDirs([string]$path) {
    try { return [IO.Directory]::GetDirectories($path) } catch { return @() }
}

# Link (winget puts links to programs into WinGet/Links) -> the real file
function Resolve-Link([string]$path) {
    try {
        $item = Get-Item -LiteralPath $path -Force
        if ($item.LinkType -and $item.Target) {
            $t = @($item.Target)[0]
            if (-not [IO.Path]::IsPathRooted($t)) { $t = Join-Path (Split-Path $path) $t }
            if (Test-Path -LiteralPath $t -PathType Leaf) { return (Resolve-Path -LiteralPath $t).Path }
        }
    } catch { }
    return $path
}

function Get-UninstallEntries {
    $base = 'SOFTWARE', 'Microsoft', 'Windows', 'CurrentVersion', 'Uninstall'
    $keys = @()
    foreach ($hive in 'HKLM:', 'HKCU:') { $keys += ($hive + [char]92 + ($base -join [char]92) + [char]92 + '*') }
    $keys += ('HKLM:' + [char]92 + 'SOFTWARE' + [char]92 + 'WOW6432Node' + [char]92 + (($base | Select-Object -Skip 1) -join [char]92) + [char]92 + '*')
    return @(Get-ItemProperty -Path $keys -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName })
}

# Looks for a program: PATH, running processes, installed programs, usual places and folders
# with a similar name on all drives (two levels deep). Returns paths to the exe.
function Find-Program([string[]]$Exe, [string]$Like, [string[]]$Known) {
    $hits = New-Object System.Collections.Generic.List[string]
    foreach ($e in $Exe) {
        foreach ($c in @(Get-Command $e -All -CommandType Application -ErrorAction SilentlyContinue)) { $hits.Add((Resolve-Link $c.Source)) }
    }
    foreach ($p in @(Get-Process -ErrorAction SilentlyContinue)) {
        try { if ($p.Path -and ($Exe -contains (Split-Path $p.Path -Leaf))) { $hits.Add($p.Path) } } catch { }
    }
    foreach ($u in (Get-UninstallEntries | Where-Object { $_.DisplayName -like $Like })) {
        if ($u.InstallLocation) { foreach ($e in $Exe) { $hits.Add((Join-Path $u.InstallLocation $e)) } }
        if ($u.DisplayIcon) {
            $icon = ($u.DisplayIcon -replace ',\s*-?\d+$', '').Trim('"', ' ')
            if ($Exe -contains (Split-Path $icon -Leaf)) { $hits.Add($icon) }
        }
    }
    foreach ($k in $Known) { $hits.Add($k) }

    # Drive scan: folders with a matching name on the first and second level
    $roots = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object { $_.RootDirectory.FullName })
    $roots += @('Downloads', 'Desktop', 'Documents' | ForEach-Object { Join-Path $env:USERPROFILE $_ })
    $skip = @('Windows', '$Recycle.Bin', 'System Volume Information')
    foreach ($r in $roots) {
        foreach ($d1 in (Get-SubDirs $r)) {
            if ($skip -contains (Split-Path $d1 -Leaf)) { continue }
            $dirs = @()
            if ((Split-Path $d1 -Leaf) -like $Like) { $dirs += $d1 }
            foreach ($d2 in (Get-SubDirs $d1)) { if ((Split-Path $d2 -Leaf) -like $Like) { $dirs += $d2 } }
            foreach ($d in $dirs) {
                # the folder, its subfolders and their subfolders (ffmpeg-x/bin/ffmpeg.exe)
                $level = @($d)
                for ($depth = 0; $depth -le 2; $depth++) {
                    $next = @()
                    foreach ($x in $level) {
                        foreach ($e in $Exe) { $hits.Add((Join-Path $x $e)) }
                        if ($depth -lt 2) { $next += Get-SubDirs $x }
                    }
                    $level = $next
                }
            }
        }
    }

    $seen = @{}
    $result = @()
    foreach ($h in $hits) {
        if (-not $h) { continue }
        try { if (-not (Test-Path -LiteralPath $h -PathType Leaf)) { continue } } catch { continue }
        try { $full = (Resolve-Path -LiteralPath $h).Path } catch { continue }
        if ($seen.ContainsKey($full.ToLowerInvariant())) { continue }
        $seen[$full.ToLowerInvariant()] = $true
        $result += $full
    }
    return $result
}

# Shows what was found and asks which one to use. Returns a path or ''.
function Select-Program([string]$Name, [string]$Why, [string[]]$Found, [scriptblock]$Check, [string]$HowToGet, [scriptblock]$Label = { param($p) $p }) {
    Say ''
    Say "== $Name — $Why" Cyan
    if ($Found.Count -eq 0) {
        Say (T '   Не найден. Пункты этой программы в меню будут скрыты.' '   Not found. Its menu items will be hidden.') Yellow
        Say "   $HowToGet" DarkGray
    } else {
        for ($i = 0; $i -lt $Found.Count; $i++) { Say ("   [{0}] {1}" -f ($i + 1), (& $Label $Found[$i])) White }
    }
    if ($Yes) { if ($Found.Count) { return $Found[0] } else { return '' } }
    while ($true) {
        if ($Found.Count) { $q = T '   Enter — вариант 1; номер — другой; свой путь; минус (-) — не использовать' '   Enter = option 1; a number = another one; or your own path; minus (-) = do not use' }
        else { $q = T '   Свой путь, если программа стоит в необычном месте; Enter — пропустить' '   Your own path if it is installed somewhere unusual; Enter = skip' }
        $a = (Read-Host $q).Trim().Trim('"')
        if ($a -eq '-') { return '' }
        if ($a -eq '') { if ($Found.Count) { return $Found[0] } else { return '' } }
        $n = 0
        if ([int]::TryParse($a, [ref]$n) -and $n -ge 1 -and $n -le $Found.Count) { return $Found[$n - 1] }
        $ok = & $Check $a
        if ($ok) { return $ok }
        Say (T '   Не нашёл там программу, попробуй ещё раз.' '   The program is not there, try again.') Yellow
    }
}

# ---------- 1. Nilesoft Shell folder ----------
function Test-Nilesoft([string]$dir) { return ($dir -and (Test-Path -LiteralPath (Join-Path $dir 'shell.exe') -PathType Leaf)) }

# Every Nilesoft Shell folder on this PC, installed and portable alike; the most reliable places go first
function Find-NilesoftDirs {
    $cands = @()
    # A registered Nilesoft (installed or portable) leaves the full path of its shell.dll in the registry
    foreach ($hive in 'HKLM:', 'HKCU:') {
        foreach ($n in 1..3) {
            $dll = (Get-ItemProperty -Path "$hive/SOFTWARE/Classes/CLSID/{BAE3934B-8A6A-4BFB-81BD-3FC599A1BAF$n}/InprocServer32" -ErrorAction SilentlyContinue).'(default)'
            if ($dll) { $cands += Split-Path $dll }
        }
    }
    # The shell.dll Explorer has loaded right now
    try {
        foreach ($m in @((Get-Process explorer -ErrorAction SilentlyContinue).Modules)) {
            if ($m.ModuleName -eq 'shell.dll') { $cands += Split-Path $m.FileName }
        }
    } catch { }
    foreach ($u in (Get-UninstallEntries | Where-Object { $_.DisplayName -like 'Nilesoft Shell*' })) {
        if ($u.InstallLocation) { $cands += $u.InstallLocation }
        if ($u.DisplayIcon) { $cands += Split-Path (($u.DisplayIcon -replace ',\s*-?\d+$', '').Trim('"', ' ')) }
    }
    $cands += Join-Path $env:ProgramFiles 'Nilesoft Shell'
    $cands += Join-Path $env:USERPROFILE 'scoop/apps/nilesoft-shell/current'   # scoop install nilesoft-shell
    # A portable copy that is not registered yet: folders named like Nilesoft on all drives
    $cands += @(Find-Program -Exe 'shell.exe' -Like '*nilesoft*' -Known @() | ForEach-Object { Split-Path $_ })

    $seen = @{}
    $found = @()
    foreach ($c in $cands) {
        if (-not (Test-Nilesoft $c) -or -not (Test-Path -LiteralPath (Join-Path $c 'shell.dll'))) { continue }
        $full = (Resolve-Path -LiteralPath $c).Path.TrimEnd([char]92)
        if ($seen.ContainsKey($full.ToLowerInvariant())) { continue }
        $seen[$full.ToLowerInvariant()] = $true
        $found += $full
    }
    return $found
}

if (-not $Target) {
    $found = @(Find-NilesoftDirs)
    if ($found.Count -eq 1) { $Target = $found[0] }
    elseif ($found.Count -gt 1) {
        $Target = Select-Program 'Nilesoft Shell' (T 'куда поставить меню' 'where to put the menu') $found `
            { param($p) if (Test-Nilesoft $p) { return (Resolve-Path -LiteralPath $p).Path }; return '' } ''
    }
}
if (-not (Test-Nilesoft $Target)) {
    Say ''
    Say (T 'Не нашёл Nilesoft Shell.' 'Nilesoft Shell was not found.') Yellow
    Say (T 'Сначала поставь его: https://nilesoft.org/download — установщик, winget install Nilesoft.Shell' `
           'Get it first: https://nilesoft.org/download - the installer, winget install Nilesoft.Shell')
    Say (T 'или портативную версию (архив): распакуй в любую папку, регистрацию сделает этот установщик.' `
           'or the portable version (archive): extract it to any folder, this setup will register it.')
    Say (T 'Потом запусти Install.cmd ещё раз.' 'Then run Install.cmd again.')
    if (-not $Yes) {
        $a = (Read-Host (T 'Или вставь путь к папке, где лежит shell.exe (Enter — выйти)' 'Or paste the folder that contains shell.exe (Enter = exit)')).Trim().Trim('"')
        if (Test-Nilesoft $a) { $Target = $a }
    }
    if (-not (Test-Nilesoft $Target)) { Done 1 }
}
$Target = (Resolve-Path -LiteralPath $Target).Path
$shellExe = Join-Path $Target 'shell.exe'
$ver = (Get-Item -LiteralPath $shellExe).VersionInfo.FileVersion
Say ''
Say ("Nilesoft Shell: $Target (" + (T 'версия' 'version') + " $ver)") Green
try {
    if ([version]($ver -replace '[^0-9.].*$', '') -lt [version]'1.9.18') {
        Say (T 'Пресет сделан для версии 1.9.18. На более старой что-то может не работать — лучше обновить Nilesoft Shell.' `
               'The preset is made for version 1.9.18. Older versions may not support everything; please update Nilesoft Shell.') Yellow
    }
} catch { }

# ---------- 2. Backup of the current menu ----------
$imports = Join-Path $Target 'imports'
$oldCfg = Join-Path $Target 'shell.nss'
if (Test-Path -LiteralPath $oldCfg) {
    $bk = Join-Path (Join-Path $Target 'backup') ('before-preset-' + (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
    New-Item -ItemType Directory -Force -Path $bk | Out-Null
    Copy-Item -LiteralPath $oldCfg -Destination $bk
    if (Test-Path -LiteralPath $imports) { Copy-Item -LiteralPath $imports -Destination $bk -Recurse }
    Say ((T 'Старое меню сохранено в: ' 'Your old menu is saved to: ') + $bk) Green
}

# ---------- 3. Copy the preset ----------
New-Item -ItemType Directory -Force -Path $imports | Out-Null
Copy-Item -LiteralPath (Join-Path $ConfigDir 'shell.nss') -Destination $Target -Force
Get-ChildItem -LiteralPath (Join-Path $ConfigDir 'imports') -File | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $imports -Force
}
# Files from the internet carry the "downloaded" mark; remove it
Get-ChildItem -LiteralPath $imports -File | Unblock-File -ErrorAction SilentlyContinue
Unblock-File -LiteralPath (Join-Path $Target 'shell.nss') -ErrorAction SilentlyContinue
Say ((T 'Файлы пресета скопированы, язык меню: ' 'Preset files copied, menu language: ') + $(if ($Lang -eq 'ru') { 'Русский' } else { 'English' })) Green

# ---------- 4. Programs ----------
$local = Join-Path $env:USERPROFILE 'AppData/Local'
$progX86 = ${env:ProgramFiles(x86)}

# ffmpeg needs a folder where ffmpeg.exe and ffprobe.exe are next to each other
$ffFound = @(Find-Program -Exe 'ffmpeg.exe' -Like '*ffmpeg*' -Known @(
        (Join-Path $env:ProgramFiles 'ffmpeg/bin/ffmpeg.exe'), 'C:/ffmpeg/bin/ffmpeg.exe') |
    Where-Object { Test-Path -LiteralPath (Join-Path (Split-Path $_) 'ffprobe.exe') } | ForEach-Object { Split-Path $_ })
# Version of every found build; the newest goes first
function Get-FFmpegVersion([string]$dir) {
    try {
        $line = "$(& (Join-Path $dir 'ffmpeg.exe') -hide_banner -version 2>$null | Select-Object -First 1)"
        if ($line -match 'version\s+n?(\d+(\.\d+)*)') { return [version]($matches[1] + $(if ($matches[1] -notmatch '\.') { '.0' })) }
    } catch { }
    return [version]'0.0'
}
$ffFound = @($ffFound | Sort-Object -Property @{ Expression = { Get-FFmpegVersion $_ }; Descending = $true })
$ffLabel = { param($p) $v = Get-FFmpegVersion $p; if ($v -gt [version]'0.0') { "$p  (" + (T 'версия' 'version') + " $v)" } else { $p } }
$ffCheck = {
    param($p)
    foreach ($d in @($p, (Split-Path $p), (Join-Path $p 'bin'))) {
        if ($d -and (Test-Path -LiteralPath (Join-Path $d 'ffmpeg.exe') -PathType Leaf)) { return (Resolve-Path -LiteralPath $d).Path }
    }
    return ''
}
$ff = Select-Program 'FFmpeg' (T 'меню FFmpeg (видео, звук, картинки)' 'FFmpeg menu (video, audio, images)') $ffFound $ffCheck `
    (T 'Скачать: https://www.gyan.dev/ffmpeg/builds/ или: winget install Gyan.FFmpeg' 'Get it: https://www.gyan.dev/ffmpeg/builds/ or: winget install Gyan.FFmpeg') $ffLabel
if ($ff) {
    # Version 7.0+ and a GPL build (with x264/x265) are needed
    $v = Get-FFmpegVersion $ff
    if ($v -gt [version]'0.0' -and $v -lt [version]'7.0') {
        Say (T "   Внимание: FFmpeg $v старый. Нужен 7.0 или новее, иначе часть пунктов не сработает." `
               "   Warning: FFmpeg $v is old. Version 7.0 or newer is needed, otherwise some items will fail.") Yellow
    }
    $encoders = "$(& (Join-Path $ff 'ffmpeg.exe') -hide_banner -encoders 2>$null)"
    if ($encoders -notmatch 'libx264' -or $encoders -notmatch 'libx265') {
        Say (T '   Внимание: в этой сборке нет x264/x265 (сборка LGPL). Возьми сборку с gyan.dev (essentials или full).' `
               '   Warning: this build has no x264/x265 (an LGPL build). Use a build from gyan.dev (essentials or full).') Yellow
    }
}

$evFound = @(Find-Program -Exe 'Everything.exe', 'Everything64.exe' -Like '*everything*' -Known @(
    (Join-Path $env:ProgramFiles 'Everything/Everything.exe'),
    (Join-Path $env:ProgramFiles 'Everything 1.5a/Everything64.exe'),
    $(if ($progX86) { Join-Path $progX86 'Everything/Everything.exe' })))
$exeCheck = { param($p) if ($p -and (Test-Path -LiteralPath $p -PathType Leaf) -and $p -like '*.exe') { return (Resolve-Path -LiteralPath $p).Path }; return '' }
$ev = Select-Program 'Everything' (T 'меню «Найти в Everything»' '"Find in Everything" menu') $evFound $exeCheck `
    (T 'Скачать: https://www.voidtools.com/ или: winget install voidtools.Everything' 'Get it: https://www.voidtools.com/ or: winget install voidtools.Everything')

$lcFound = @(Find-Program -Exe 'LosslessCut.exe' -Like '*losslesscut*' -Known @(
    (Join-Path $env:ProgramFiles 'LosslessCut/LosslessCut.exe'),
    (Join-Path $local 'Programs/LosslessCut/LosslessCut.exe')))
$lc = Select-Program 'LosslessCut' (T 'пункт «Открыть в LosslessCut»' '"Open in LosslessCut" item') $lcFound $exeCheck `
    (T 'Скачать: https://github.com/mifi/lossless-cut/releases (архив для Windows, распаковать куда угодно)' 'Get it: https://github.com/mifi/lossless-cut/releases (Windows archive, extract anywhere)')

# Write the paths to imports/paths.nss
$pathsFile = Join-Path $imports 'paths.nss'
$text = [IO.File]::ReadAllText($pathsFile)
foreach ($pair in @(@('ff_bin_user', $ff), @('ev_exe_user', $ev), @('lc_exe_user', $lc))) {
    $name, $value = $pair
    if ($value -like "*'*") {
        Say (T "Путь с апострофом не подходит для Nilesoft: $value — переименуй папку и запусти установку ещё раз." `
               "A path with an apostrophe does not work in Nilesoft: $value. Rename the folder and run the setup again.") Yellow
        $value = ''
    }
    $text = [regex]::Replace($text, '(?m)^(\$' + $name + " = )'[^']*'", { param($m) $m.Groups[1].Value + "'" + $value + "'" })
}
[IO.File]::WriteAllText($pathsFile, $text, (New-Object Text.UTF8Encoding $false))

# ---------- 5. Graphics card for video encoding ----------
$gpu = ''
if ($ff) {
    Say ''
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $imports 'ffmpeg-run.ps1') -FFmpeg (Join-Path $ff 'ffmpeg.exe') -Preset gpu-detect -NoPause
    $gpu = (Get-ItemProperty -Path 'HKCU:/Software/Nilesoft-FFmpeg-menu' -ErrorAction SilentlyContinue).GpuEnc
    if ($gpu -eq 'none') { $gpu = '' }
}

# ---------- Summary ----------
$appPaths = 'HKLM:' + [char]92 + 'SOFTWARE' + [char]92 + 'Microsoft' + [char]92 + 'Windows' + [char]92 + 'CurrentVersion' + [char]92 + 'App Paths' + [char]92 + 'WinRAR.exe'
$rar = (Get-ItemProperty -LiteralPath $appPaths -ErrorAction SilentlyContinue).'(default)'
if (-not $rar) { $rar = Join-Path (Join-Path $env:ProgramFiles 'WinRAR') 'WinRAR.exe' }
$hasRar = Test-Path -LiteralPath $rar -PathType Leaf
$gpuNames = @{ 'nvenc' = 'NVIDIA NVENC'; 'amf' = 'AMD AMF'; 'qsv' = 'Intel Quick Sync' }

Say ''
Say (T 'Что будет в меню:' 'What the menu will have:') Cyan
function Line([string]$what, [bool]$on, [string]$off) {
    if ($on) { Say "   + $what" Green } else { Say "   - $what — $off" DarkYellow }
}
Line 'FFmpeg' ([bool]$ff) (T 'скрыто: ffmpeg не найден' 'hidden: ffmpeg not found')
Line (T 'Найти в Everything' 'Find in Everything') ([bool]$ev) (T 'скрыто: Everything не найден' 'hidden: Everything not found')
Line (T 'Открыть в LosslessCut' 'Open in LosslessCut') ([bool]$lc) (T 'скрыто: LosslessCut не найден' 'hidden: LosslessCut not found')
Line 'WinRAR' $hasRar (T 'скрыто: WinRAR не установлен' 'hidden: WinRAR is not installed')
if ($ff) {
    Line ((T 'Кодирование на видеокарте' 'Encoding on the graphics card') + $(if ($gpu) { ' (' + $gpuNames[$gpu] + ')' })) ([bool]$gpu) `
        (T 'скрыто: видеокарта не умеет кодировать видео, всё делает процессор' 'hidden: no graphics card that can encode video, the CPU does everything')
    if ($gpu) { Say (T '     Включается в меню: FFmpeg → Настройки → Кодировать видео на видеокарте' '     Turn it on in the menu: FFmpeg > Settings > Encode video on the graphics card') DarkGray }
}
Say (T '   + Инструменты, Управление файлами, Терминал, Перейти, Питание, Диски — работают без других программ' `
       '   + Tools, File manage, Terminal, Go to, Power, Drives — work without other programs') Green
Say (T '   Пути к программам можно поменять потом в файле imports/paths.nss' '   Program paths can be changed later in imports/paths.nss') DarkGray

# ---------- 6. Registration ----------
if ($NoRegister) { Say ''; Say (T 'Регистрация пропущена (-NoRegister).' 'Registration skipped (-NoRegister).') DarkGray; Done 0 }
Say ''
$a = if ($Yes) { 'y' } else { Read-Host (T 'Зарегистрировать Nilesoft Shell и перезапустить Проводник сейчас? [Д/н]' 'Register Nilesoft Shell and restart Explorer now? [Y/n]') }
if ($a -match '^\s*(н|n)') {
    Say (T 'Хорошо. Меню обновится после перезапуска Проводника или перезагрузки.' 'OK. The menu will update after Explorer restarts or after a reboot.') DarkGray
} else {
    Start-Process -FilePath $shellExe -ArgumentList '-register', '-treat', '-restart' -Wait
    Say (T 'Готово! Кликни правой кнопкой по любому файлу.' 'Done! Right-click any file.') Green
}
Done 0
