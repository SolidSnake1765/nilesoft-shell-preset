# Запускает ffmpeg для пунктов меню FFmpeg в Nilesoft Shell (imports/ffmpeg.nss).
#
# Настройки хранятся в реестре (их переключают пункты меню):
#   Mode    = copy | replace — копия рядом / замена (исходник уходит в Корзину)
#   OutDir  = here | sub     — копии кладутся рядом или в подпапку «FFmpeg»
#   Encoder = cpu  | gpu     — видео кодирует процессор (x264) или видеокарта (NVIDIA, AMD или Intel)
#   GpuEnc  = nvenc | amf | qsv | none — какой кодировщик видеокарты работает (определяется сам)
#   Window  = auto | wait    — закрывать окно после успеха или всегда ждать Enter
# Исходник трогается только после успешной обработки. Операции, которые делают из файла
# что-то новое (GIF, звук, кадры, 9:16, склейка), всегда создают новый файл.
#
# Пример: powershell -File ffmpeg-run.ps1 -FFmpeg <путь к ffmpeg.exe> -Preset louder -Value 6 <файлы...>

# PositionalBinding off: otherwise the first file would land in -Value when it is omitted
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true)][string]$FFmpeg,
    [Parameter(Mandatory = $true)][string]$Preset,
    [string]$Value = '',
    [switch]$NoPause,   # for tests: do not wait at the end
    [double]$TestCancelAfter = 0,   # for tests: act as if Esc was pressed after N seconds
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Files
)

$RegKey = 'HKCU:\Software\Nilesoft-FFmpeg-menu'
$cfg = Get-ItemProperty -Path $RegKey -ErrorAction SilentlyContinue
$replaceMode = ($cfg.Mode -eq 'replace')
$toSubfolder = ($cfg.OutDir -eq 'sub')
$alwaysWait = ($cfg.Window -eq 'wait')
$beepAtEnd = ($cfg.Beep -eq 'on')
$revealAtEnd = ($cfg.Reveal -eq 'on')
$script:cancelled = $false   # нажали Esc / Q / Ctrl+C
$script:pickedTracks = $null   # номера дорожек для «Выбрать звуковые дорожки» — спрашиваются один раз
$Host.UI.RawUI.WindowTitle = "FFmpeg: $Preset $Value"
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # ffmpeg пишет имена файлов в UTF-8

$FFprobe = Join-Path (Split-Path $FFmpeg) 'ffprobe.exe'
# Рабочая папка — TEMP: временные файлы фильтров (стабилизация, субтитры) задаются относительным путём,
# потому что двоеточие в «C:» ломает параметры фильтров
# Set-Location обязателен: PowerShell запускает программы из своей текущей папки, а не из CurrentDirectory
Set-Location -LiteralPath $env:TEMP
[Environment]::CurrentDirectory = $env:TEMP
$inv = [Globalization.CultureInfo]::InvariantCulture
function Format-Num([double]$x) { return $x.ToString('0.######', $inv) }

# Длительность файла в секундах (через ffprobe)
function Get-Duration([string]$path) {
    $s = & $FFprobe -v error -show_entries format=duration -of csv=p=0 $path 2>$null
    $d = 0.0
    if (-not [double]::TryParse("$s".Trim(), [Globalization.NumberStyles]::Float, $inv, [ref]$d)) { throw "Не удалось узнать длительность: $path" }
    return $d
}

# Что внутри файла: кодек, формат пикселей и размер видео, кодек первой звуковой дорожки
function Get-StreamInfo([string]$path) {
    $info = @{ VCodec = ''; PixFmt = ''; W = 0; H = 0; ACodec = '' }
    foreach ($l in (& $FFprobe -v error -select_streams v:0 -show_entries stream=codec_name,pix_fmt,width,height -of default=nw=1 $path 2>$null)) {
        $k, $val = "$l".Split('=', 2)
        switch ($k) { 'codec_name' { $info.VCodec = $val } 'pix_fmt' { $info.PixFmt = $val } 'width' { $info.W = [int]$val } 'height' { $info.H = [int]$val } }
    }
    $info.ACodec = "$(& $FFprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 $path 2>$null)".Trim()
    return $info
}

# ---------- Видеокарта ----------
# Кодировщик видеокарты: nvenc (NVIDIA), amf (AMD), qsv (Intel, в том числе встроенная графика).
# Проверяется пробным кодированием полсекунды тестовой картинки и запоминается в реестре
# вместе с путём к ffmpeg. «Настройки → Проверить видеокарту» проверяет заново.
$gpuNames = @{ 'nvenc' = 'NVIDIA NVENC'; 'amf' = 'AMD AMF'; 'qsv' = 'Intel Quick Sync' }
function Test-Encoder([string]$enc) {
    & $FFmpeg -hide_banner -loglevel error -f lavfi -i 'testsrc2=s=640x360:d=0.3' -c:v $enc -f null - 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}
function Find-GpuEncoder([switch]$Force) {
    $c = Get-ItemProperty -Path $RegKey -ErrorAction SilentlyContinue
    if (-not $Force -and $c.GpuEnc -and $c.GpuFor -eq $FFmpeg) {
        return @{ Vendor = $(if ($c.GpuEnc -eq 'none') { '' } else { $c.GpuEnc }); Hevc = ($c.GpuHevc -eq '1') }
    }
    $found = @{ Vendor = ''; Hevc = $false }
    foreach ($v in 'nvenc', 'amf', 'qsv') {
        if (Test-Encoder "h264_$v") { $found = @{ Vendor = $v; Hevc = (Test-Encoder "hevc_$v") }; break }
    }
    if (-not (Test-Path $RegKey)) { New-Item -Path $RegKey -Force | Out-Null }
    Set-ItemProperty -Path $RegKey -Name GpuEnc -Value $(if ($found.Vendor) { $found.Vendor } else { 'none' })
    Set-ItemProperty -Path $RegKey -Name GpuHevc -Value $(if ($found.Hevc) { '1' } else { '0' })
    Set-ItemProperty -Path $RegKey -Name GpuFor -Value $FFmpeg
    return $found
}
$script:gpu = $null
function Get-Gpu { if ($null -eq $script:gpu) { $script:gpu = Find-GpuEncoder }; return $script:gpu }
# Пункты «на видеокарте» без подходящей видеокарты: понятная ошибка вместо ошибки ffmpeg
function Assert-Gpu([string]$codec) {
    $g = Get-Gpu
    if (-not $g.Vendor) { throw 'Видеокарта, умеющая кодировать видео, не найдена. Выбери вариант «на процессоре».' }
    if ($codec -eq 'h265' -and -not $g.Hevc) { throw "$($gpuNames[$g.Vendor]) не умеет кодировать H.265 на этой видеокарте. Выбери H.264 или процессор." }
}

# Аргументы кодировщика видеокарты. -Quality — по шкале NVENC CQ (меньше — лучше),
# -Kbps — целевой битрейт (для «Ужать под лимит»), -Best — самые медленные и качественные настройки
function Get-GpuArgs([string]$codec, [int]$Quality = 0, [int]$Kbps = 0, [switch]$Best) {
    $g = Get-Gpu
    $enc = $(if ($codec -eq 'h265') { 'hevc_' } else { 'h264_' }) + $g.Vendor
    $pix = 'yuv420p'
    switch ($g.Vendor) {
        'nvenc' {
            $a = @('-c:v', $enc, '-preset', $(if ($Best -or $Kbps) { 'p7' } else { 'p5' }), '-tune', 'hq')
            if ($Kbps) { $a += @('-multipass', 'fullres', '-rc', 'vbr', '-b:v', "${Kbps}k", '-maxrate', "$($Kbps * 2)k", '-bufsize', "$($Kbps * 2)k") }
            else { $a += @('-rc', 'vbr', '-cq', "$Quality", '-b:v', '0') }
            if ($Best -or $Kbps) { $a += @('-spatial-aq', '1', '-temporal-aq', '1') }
            if ($Best -and $codec -eq 'h264') { $a += @('-profile:v', 'high') }
        }
        'amf' {
            $a = @('-c:v', $enc, '-quality', 'quality')
            if ($Kbps) { $a += @('-rc', 'vbr_peak', '-b:v', "${Kbps}k", '-maxrate', "$($Kbps * 2)k", '-bufsize', "$($Kbps * 2)k") }
            else {
                $q = $Quality - 1
                $a += @('-rc', 'cqp', '-qp_i', "$q", '-qp_p', "$($q + 2)")
                if ($codec -eq 'h264') { $a += @('-qp_b', "$($q + 4)") }
            }
        }
        'qsv' {
            $a = @('-c:v', $enc, '-preset', $(if ($Best) { 'veryslow' } else { 'slow' }))
            if ($Kbps) { $a += @('-b:v', "${Kbps}k", '-maxrate', "$($Kbps * 2)k", '-bufsize', "$($Kbps * 2)k") }
            else { $a += @('-global_quality', "$Quality") }
            $pix = 'nv12'   # Quick Sync принимает только nv12
        }
    }
    if ($codec -eq 'h265') { $a += @('-tag:v', 'hvc1') }
    return $a + @('-pix_fmt', $pix)
}
# Видеокарта включена в настройках и найдена. Для H.265 нужна ещё его поддержка — иначе процессор
function Use-Gpu([string]$codec = 'h264') {
    if ($cfg.Encoder -ne 'gpu') { return $false }
    $g = Get-Gpu
    return ([bool]$g.Vendor -and ($codec -ne 'h265' -or $g.Hevc))
}

# Перекодирование «визуально без потерь»: разницу с оригиналом глазом не видно, файл больше обычного.
# Размер приводится к чётному — без этого H.264 в yuv420p не кодируется
$evenSize = 'scale=trunc(iw/2)*2:trunc(ih/2)*2'
$hqVideo = @{
    'h264'    = @('-vf', $evenSize, '-c:v', 'libx264', '-preset', 'slow', '-crf', '17', '-profile:v', 'high', '-pix_fmt', 'yuv420p')
    'h265'    = @('-vf', $evenSize, '-c:v', 'libx265', '-preset', 'slow', '-crf', '18', '-tag:v', 'hvc1', '-pix_fmt', 'yuv420p')
}
$hqName = @{ 'h264' = 'H.264'; 'h264gpu' = 'H.264 GPU'; 'h265' = 'H.265'; 'h265gpu' = 'H.265 GPU' }

# MP4 без потери качества. auto: видео H.264 копируется как есть, перекодируется только несовместимое
function Get-HqJob($j, [string]$src) {
    $info = Get-StreamInfo $src
    $notes = @()
    $kind = $Value
    if ($Value -eq 'auto') {
        $ok264 = ($info.VCodec -eq 'h264') -and ($info.PixFmt -in @('yuv420p', 'yuvj420p')) -and ($info.W % 2 -eq 0) -and ($info.H % 2 -eq 0)
        if ($ok264) { $kind = 'copy' } elseif (Use-Gpu) { $kind = 'h264gpu' } else { $kind = 'h264' }
        $j.Suffix = '(MP4)'
    } else {
        $j.Suffix = "($($hqName[$Value]) HQ)"
    }
    if ($kind -eq 'copy') {
        $v = @('-c:v', 'copy')
        $notes += 'видео уже в H.264 — копируется без перекодирования'
    } elseif ($kind -like '*gpu') {
        $codec = $kind.Substring(0, 4)
        Assert-Gpu $codec
        $v = @('-vf', $evenSize) + (Get-GpuArgs $codec -Quality $(if ($codec -eq 'h265') { 21 } else { 19 }) -Best)
        $notes += "видео: $($info.VCodec) -> $($hqName[$kind]) ($($gpuNames[(Get-Gpu).Vendor])), визуально без потерь"
    } else {
        $v = $hqVideo[$kind]
        $notes += "видео: $($info.VCodec) -> $($hqName[$kind]), визуально без потерь"
    }
    if ($info.ACodec -eq 'aac') { $a = @('-c:a', 'copy'); $notes += 'звук AAC копируется' }
    elseif ($info.ACodec) { $a = @('-c:a', 'aac', '-b:a', '256k'); $notes += "звук: $($info.ACodec) -> AAC 256 кбит/с" }
    else { $a = @() }
    $j.Args = @('-map', "0:$(Get-MainVideoIndex $src)", '-map', '0:a?') + $v + $a + @('-movflags', '+faststart')
    $j.Ext = 'mp4'
    $j.Note = $notes -join ' · '
    return $j
}

# Кодирование видео: качество задаётся по шкале CRF x264 (меньше — лучше)
function Get-VideoArgs([int]$crf, [string]$speed = 'medium') {
    if (Use-Gpu) { return Get-GpuArgs 'h264' -Quality ($crf + 3) }
    return @('-c:v', 'libx264', '-preset', $speed, '-crf', "$crf", '-pix_fmt', 'yuv420p')
}
$mp4Audio = @('-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart')

# Кодек звука под расширение файла: чтобы при обработке звука формат остался тем же
function Get-AudioArgs([string]$ext) {
    switch ($ext) {
        'mp3'  { return @('-c:a', 'libmp3lame', '-q:a', '0') }
        'opus' { return @('-c:a', 'libopus', '-b:a', '160k') }
        'ogg'  { return @('-c:a', 'libvorbis', '-q:a', '6') }
        'oga'  { return @('-c:a', 'libvorbis', '-q:a', '6') }
        'webm' { return @('-c:a', 'libopus', '-b:a', '160k') }
        'flac' { return @('-c:a', 'flac') }
        'wav'  { return @('-c:a', 'pcm_s16le') }
        'aiff' { return @('-c:a', 'pcm_s16be') }
        'aif'  { return @('-c:a', 'pcm_s16be') }
        'wma'  { return @('-c:a', 'wmav2', '-b:a', '192k') }
        'avi'  { return @('-c:a', 'libmp3lame', '-b:a', '192k') }
        'ac3'  { return @('-c:a', 'ac3', '-b:a', '448k') }
        default { return @('-c:a', 'aac', '-b:a', '256k') }
    }
}

$videoExt = @('mp4', 'mkv', 'mov', 'avi', 'webm', 'm4v', 'ts', 'mts', 'm2ts', 'flv', 'wmv', 'mpg', 'mpeg', '3gp', 'vob', 'ogv')
$coverExt = @('mp3', 'm4a', 'flac')

# Аргументы для изменения звука: у видео картинка копируется, у музыки сохраняется обложка
# -Src: у видео с несколькими звуковыми дорожками спрашивает, какие менять; остальные копируются как есть.
# -Extra — параметры кодирования звука (например, -ar 48000). Для имени результата — $script:soundNote («, дорожки 1, 3»)
function Get-SoundJobArgs([string]$ext, [string[]]$filter, [string]$Src = '', [string[]]$Extra = @()) {
    $script:soundNote = ''
    if ($videoExt -contains $ext) {
        $tracks = @()
        if ($Src) {
            $tracks = @(Get-Streams $Src 'a')
            if ($tracks.Count -eq 0) { throw 'В видео нет звука — менять нечего' }
        }
        if ($tracks.Count -gt 1) {
            $keep = @(Request-Tracks $Src $tracks 'Изменятся только выбранные дорожки, остальные останутся как есть. Можно «1 3» или «2-4», Enter — все.' 'Какие дорожки менять (номера)')
            foreach ($k in $keep) { if ($k -gt $tracks.Count) { throw "Нет дорожки номер $k" } }
            if ($keep.Count -lt $tracks.Count) {
                $a = @('-map', '0', '-c', 'copy')
                foreach ($k in $keep) {
                    $i = $k - 1
                    # параметры звука — только для этой дорожки: -c:a -> -c:a:N, -ar -> -ar:a:N
                    $opts = @(Get-AudioArgs $ext) + $Extra
                    for ($o = 0; $o -lt $opts.Count - 1; $o += 2) {
                        $name = $opts[$o]
                        if ($name -like '*:a') { $name += ":$i" } else { $name += ":a:$i" }
                        $a += @($name, $opts[$o + 1])
                    }
                    $a += @("-filter:a:$i", ($filter -join ','))
                }
                if ($keep.Count -eq 1) { $script:soundNote = ", дорожка $($keep[0])" } else { $script:soundNote = ", дорожки $($keep -join ', ')" }
                return $a
            }
        }
        return @('-map', '0', '-c', 'copy') + (Get-AudioArgs $ext) + $Extra + @('-af') + $filter
    }
    if ($coverExt -contains $ext) {
        return @('-map', '0:a', '-map', '0:v?', '-c:v', 'copy') + (Get-AudioArgs $ext) + $Extra + @('-af') + $filter
    }
    return @('-map', '0:a') + (Get-AudioArgs $ext) + $Extra + @('-af') + $filter
}

# Параметры качества для картинок
function Get-ImageArgs([string]$ext) {
    $a = @()
    if ($ext -ne 'gif') { $a += @('-frames:v', '1', '-update', '1') }
    switch ($ext) {
        'jpg'  { $a += @('-q:v', '2') }
        'jpeg' { $a += @('-q:v', '2') }
        'webp' { $a += @('-c:v', 'libwebp', '-quality', '90') }
        'avif' { $a += @('-c:v', 'libaom-av1', '-still-picture', '1', '-crf', '28', '-cpu-used', '6') }
    }
    return $a
}

$rotate = @{ 'right' = 'transpose=1'; 'left' = 'transpose=2'; '180' = 'transpose=1,transpose=1'; 'hflip' = 'hflip'; 'vflip' = 'vflip' }
$rotateName = @{ 'right' = 'поворот вправо'; 'left' = 'поворот влево'; '180' = 'поворот 180'; 'hflip' = 'отражено по горизонтали'; 'vflip' = 'отражено по вертикали' }

$gif = @{
    '1' = @('маленький', 'fps=10,scale=320:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=64:stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3')
    '2' = @('средний', 'fps=12,scale=400:-1:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=full[p];[s1][p]paletteuse=dither=bayer:bayer_scale=4')
    '3' = @('качественный', 'fps=15,scale=480:-1:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=full:reserve_transparent=0[p];[s1][p]paletteuse=dither=floyd_steinberg')
}

# Звук в отдельный файл: формат -> (расширение, аргументы)
$audioFormats = @{
    'mp3'    = @('mp3', @('-c:a', 'libmp3lame', '-b:a', '320k'))
    'mp3vbr' = @('mp3', @('-c:a', 'libmp3lame', '-q:a', '2'))
    'm4a'    = @('m4a', @('-c:a', 'aac', '-b:a', '256k'))
    'aac'    = @('aac', @('-c:a', 'aac', '-b:a', '256k'))
    'opus'   = @('opus', @('-c:a', 'libopus', '-b:a', '160k'))
    'ogg'    = @('ogg', @('-c:a', 'libvorbis', '-q:a', '6'))
    'flac'   = @('flac', @('-c:a', 'flac', '-compression_level', '8'))
    'wav'    = @('wav', @('-c:a', 'pcm_s16le'))
    'aiff'   = @('aiff', @('-c:a', 'pcm_s16be'))
    'mka'    = @('mka', @('-c:a', 'copy'))
}

# 9:16 для Shorts/TikTok: видео по центру поверх размытой и растянутой копии
$vertical = '[0:v]split=2[bg][fg];[bg]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=20:2[b];[fg]scale=1080:1920:force_original_aspect_ratio=decrease[f];[b][f]overlay=(W-w)/2:(H-h)/2,setsar=1[v]'

# 1:1 для Instagram и аватарок: видео по центру поверх размытой копии
$square = $vertical.Replace('1080:1920', '1080:1080')

# Частота дискретизации первой звуковой дорожки (для эффектов, меняющих высоту звука)
function Get-SampleRate([string]$src) {
    $sr = 0
    $s = @(Get-Streams $src 'a') | Select-Object -First 1
    if ($s -and "$($s.sample_rate)" -match '^[0-9]+$') { $sr = [int]$s.sample_rate }
    if ($sr -le 0) { $sr = 44100 }
    return $sr
}

$silence = 'silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.1,areverse,silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.1,areverse'

# «Настройки → Проверить видеокарту» и установщик: проверить заново и показать результат
if ($Preset -eq 'gpu-detect') {
    Write-Host 'Проверяю, умеет ли видеокарта кодировать видео...' -ForegroundColor Cyan
    $g = Find-GpuEncoder -Force
    if ($g.Vendor) {
        Write-Host ("Найдено: {0} (H.264{1})" -f $gpuNames[$g.Vendor], $(if ($g.Hevc) { ' и H.265' } else { '' })) -ForegroundColor Green
        if ($cfg.Encoder -ne 'gpu') { Write-Host 'Чтобы кодировать на ней, включи «Настройки → Кодировать видео на видеокарте».' }
    } else {
        Write-Host 'Видеокарта для кодирования не найдена — всё будет кодировать процессор.' -ForegroundColor Yellow
        Write-Host 'Если видеокарта есть, обнови её драйвер и проверь ещё раз.'
    }
    if (-not $NoPause) { Write-Host ''; Read-Host 'Нажми Enter, чтобы закрыть' | Out-Null }
    exit 0
}

$encName = 'процессор'
if ($cfg.Encoder -eq 'gpu') {
    if (Use-Gpu) { $encName = 'видеокарта (' + $gpuNames[(Get-Gpu).Vendor] + ')' }
    else { $encName = 'процессор (видеокарта для кодирования не найдена)' }
}
if ($replaceMode) { Write-Host "Режим: замена (исходники уходят в Корзину) · видео: $encName" -ForegroundColor Yellow }
else { Write-Host "Режим: копия (исходники не трогаются) · видео: $encName" -ForegroundColor Cyan }
if (-not [Console]::IsOutputRedirected -and $Preset -notin @('image', 'ico', 'gray', 'upscale', 'downscale', 'irotate', 'frame', 'sheet', 'spectrum', 'web', 'squarecrop', 'collage')) {
    Write-Host 'Esc или Q — отменить' -ForegroundColor DarkGray
}

# Обрезка: время спрашивается один раз для всех файлов (или приходит в -Value как «начало~конец»)

# «45», «1:30», «1:02:30», «1:30.5» или «1:30,5» -> секунды; $null, если записано неправильно
function ConvertTo-Seconds([string]$text) {
    $parts = $text.Trim().Replace(',', '.').Split(':')
    if ($parts.Count -gt 3) { return $null }
    $total = 0.0
    foreach ($p in $parts) {
        $x = 0.0
        if (-not [double]::TryParse($p, [Globalization.NumberStyles]::Float, $inv, [ref]$x) -or $x -lt 0) { return $null }
        $total = $total * 60 + $x
    }
    return $total
}

# Секунды -> «1:02:30.5» / «2:30»
function Format-Time([double]$s) {
    $t = [TimeSpan]::FromSeconds($s)
    $frac = ''
    if ($t.Milliseconds) { $frac = '.' + ([string]$t.Milliseconds).PadLeft(3, '0').TrimEnd('0') }
    if ($t.Hours -or $t.Days) { return ('{0}:{1:00}:{2:00}' -f [int][math]::Floor($t.TotalHours), $t.Minutes, $t.Seconds) + $frac }
    return ('{0}:{1:00}' -f $t.Minutes, $t.Seconds) + $frac
}

# Спрашивает время, пока не введут правильно. Пусто — $null (с начала / до конца)
function Read-Time([string]$label, [double]$min, [double]$max, [bool]$maxAllowed) {
    while ($true) {
        $answer = Read-Host $label
        if (-not $answer.Trim()) { return $null }
        $s = ConvertTo-Seconds $answer
        if ($null -eq $s) { Write-Host '  Не понял время. Пиши как в примерах: 45, 1:30 или 1:02:30' -ForegroundColor Red; continue }
        if ($s -le $min) { Write-Host "  Должно быть позже $(Format-Time $min)" -ForegroundColor Red; continue }
        if ($s -gt $max -or ($s -eq $max -and -not $maxAllowed)) { Write-Host "  Должно быть раньше $(Format-Time $max) — это конец файла" -ForegroundColor Red; continue }
        return $s
    }
}

$trimIn = @()
if ($Preset -like 'trim*') {
    if ($Value -like '*~*') {
        $a, $b = $Value.Split('~')
        $trimStart = if ($a) { ConvertTo-Seconds $a } else { $null }
        $trimEnd = if ($b) { ConvertTo-Seconds $b } else { $null }
    } else {
        $dur = Get-Duration $Files[0]
        if ($Preset -eq 'trim') { Write-Host 'Обрезка без перекодирования: мгновенно, но начало сдвигается к ближайшему ключевому кадру (обычно на 1–5 секунд раньше).' }
        else { Write-Host 'Точная обрезка: режет ровно по указанному времени, видео перекодируется.' }
        Write-Host ''
        $durText = "Длина файла: $(Format-Time $dur)"
        if ($Files.Count -gt 1) { $durText += "  (у первого из $($Files.Count); время применится ко всем)" }
        Write-Host $durText -ForegroundColor Cyan
        Write-Host ''
        Write-Host 'Как писать время:'
        Write-Host '  45        — 45-я секунда'
        Write-Host '  1:30      — 1 минута 30 секунд'
        Write-Host '  1:02:30   — 1 час 2 минуты 30 секунд'
        Write-Host '  1:30.5    — можно с долями секунды'
        Write-Host '  (пусто)   — просто нажми Enter: с самого начала / до самого конца'
        Write-Host ''
        $trimStart = Read-Time 'С какого момента оставить' -1 $dur $false
        $from = 0.0
        if ($null -ne $trimStart) { $from = $trimStart }
        $trimEnd = Read-Time 'До какого момента оставить' $from $dur $true
        $to = $dur
        if ($null -ne $trimEnd) { $to = $trimEnd }
        if ($null -eq $trimStart -and $null -eq $trimEnd) {
            Write-Host 'Ничего не указано — обрезать нечего.' -ForegroundColor Yellow
            if (-not $NoPause) { Read-Host 'Нажми Enter, чтобы закрыть' }
            return
        }
        Write-Host ''
        Write-Host "Оставляю кусок с $(Format-Time $from) по $(Format-Time $to) (длина $(Format-Time ($to - $from)))" -ForegroundColor Green
    }
    if ($null -ne $trimStart) { $trimIn += @('-ss', (Format-Num $trimStart)) }
    if ($null -ne $trimEnd) { $trimIn += @('-to', (Format-Num $trimEnd)) }
}

# Описание операции: InArgs — до -i, Args — после; Ext — расширение результата (пусто — как у
# исходника); Suffix — приписка к имени в режиме копии; Replace — можно ли заменять исходник;
# Pass1 — аргументы первого прохода (для сжатия до размера)
function Get-Job([string]$src, [string]$srcExt) {
    $j = @{ InArgs = @(); Args = @(); Ext = ''; Suffix = ''; Replace = $true; Pass1 = $null; Note = ''; Custom = ''; OutLabel = '' }
    switch ($Preset) {
        'hq'       { $j = Get-HqJob $j $src }
        'lrotate' {
            # Поворот без перекодирования: меняется только метка поворота (MP4/MOV), картинка не трогается
            $delta = @{ 'right' = -90; 'left' = 90; '180' = 180 }[$Value]
            $rot = (Get-Rotation $src) + $delta
            while ($rot -gt 180) { $rot -= 360 }
            while ($rot -le -180) { $rot += 360 }
            $j.InArgs = @('-display_rotation', "$rot")
            $j.Args = @('-map', '0', '-c', 'copy')
            $j.Suffix = "($($rotateName[$Value]))"
        }
        'stab' {
            $trf = "ffmpeg-vidstab-$PID.trf"   # относительный путь: рабочая папка — TEMP
            $j.Pass1 = @('-vf', "vidstabdetect=shakiness=6:accuracy=15:result=$trf", '-an', '-f', 'null')
            $j.Args = @('-vf', "vidstabtransform=input=${trf}:smoothing=30:optzoom=1:interpol=bicubic,unsharp=5:5:0.6:3:3:0.3") + (Get-VideoArgs 18) + (Get-KeepAudioArgs $src)
            $j.Ext = 'mp4'; $j.Suffix = '(стабилизировано)'
        }
        'denoise'  { $j.Args = @('-vf', 'hqdn3d=4:3:6:4.5') + (Get-VideoArgs 18) + (Get-KeepAudioArgs $src); $j.Ext = 'mp4'; $j.Suffix = '(без шума)' }
        'sharpen'  { $j.Args = @('-vf', 'cas=strength=0.7') + (Get-VideoArgs 18) + (Get-KeepAudioArgs $src); $j.Ext = 'mp4'; $j.Suffix = '(резкость)' }
        'deint'    { $j.Args = @('-vf', 'bwdif=mode=send_frame') + (Get-VideoArgs 18) + (Get-KeepAudioArgs $src); $j.Ext = 'mp4'; $j.Suffix = '(без чересстрочности)' }
        'interp'   { $j.Args = @('-vf', 'minterpolate=fps=60:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1') + (Get-VideoArgs 18) + (Get-KeepAudioArgs $src); $j.Ext = 'mp4'; $j.Suffix = '(60 fps плавно)' }
        'crop' {
            $c = Get-CropFilter $src
            $j.Args = @('-vf', "crop=$c") + (Get-VideoArgs 18) + (Get-KeepAudioArgs $src)
            $j.Ext = 'mp4'; $j.Suffix = '(без полос)'
            $j.Note = "найдена рамка $($c.Split(':')[0])×$($c.Split(':')[1])"
        }
        'pickaudio' {
            $tracks = Get-Streams $src 'a'
            if ($tracks.Count -lt 2) { throw 'В файле только одна звуковая дорожка — выбирать не из чего' }
            # Номера дорожек спрашиваются один раз для всех выбранных файлов (или приходят в -Value: «1,3»)
            if ($null -eq $script:pickedTracks) {
                if ($Value) { $script:pickedTracks = @(ConvertTo-TrackList $Value $tracks.Count) }
                else {
                    Write-Host ''
                    Write-Host "Звуковые дорожки в «$([IO.Path]::GetFileName($src))»:" -ForegroundColor White
                    for ($t = 0; $t -lt $tracks.Count; $t++) { Write-Host "  $(Format-Stream $tracks[$t] ($t + 1))" }
                    Write-Host '  Можно несколько: «1 3», «1,3» или «2-4». Первая станет дорожкой по умолчанию.' -ForegroundColor DarkGray
                    $script:pickedTracks = @(Read-TrackList 'Какие оставить (номера)' $tracks.Count)
                }
            }
            $keep = @($script:pickedTracks)
            if (-not $keep.Count) { throw "Не понял номера дорожек: в файле дорожки с 1 по $($tracks.Count), например «1 3» или «2-4»" }
            foreach ($k in $keep) { if ($k -gt $tracks.Count) { throw "Нет дорожки номер $k" } }
            $j.Args = @('-map', '0:v?')
            foreach ($k in $keep) { $j.Args += @('-map', "0:a:$($k - 1)") }
            if ($srcExt -ne 'mp4') { $j.Args += @('-map', '0:s?') }
            # первая из оставленных — по умолчанию, остальные — обычные
            $j.Args += @('-c', 'copy', '-disposition:a', '0', '-disposition:a:0', 'default') + (Get-TrackNameArgs $src $keep)
            if ($keep.Count -eq 1) { $j.Suffix = "(дорожка $($keep[0]))" } else { $j.Suffix = "(дорожки $($keep -join ', '))" }
            $j.Note = 'оставлены дорожки: ' + (($keep | ForEach-Object { Format-Stream $tracks[$_ - 1] $_ }) -join '; ')
        }
        'voice'     { $j.Args = Get-SoundJobArgs $srcExt @('highpass=f=80,afftdn=nf=-25:tn=1') $src; $j.Suffix = "(чистый звук$($script:soundNote))" }
        'stripmeta' { $j.Args = @('-map', '0', '-map_metadata', '-1', '-map_chapters', '-1', '-c', 'copy', '-fflags', '+bitexact'); $j.Suffix = '(без метаданных)' }
        'teaser' {
            $dur = Get-Duration $src
            if ($dur -lt 20) { throw 'Видео короче 20 секунд — превью из кусочков не имеет смысла' }
            $sel = Get-TeaserFilter $dur
            $j.Args = @('-vf', "select='$sel',setpts=N/FRAME_RATE/TB", '-af', "aselect='$sel',asetpts=N/SR/TB") + (Get-VideoArgs 20) + $mp4Audio
            $j.Ext = 'mp4'; $j.Suffix = '(нарезка)'; $j.Replace = $false
        }
        'subs-add' {
            $sub = Find-SubSidecar $src
            if (-not $sub) { throw 'Рядом нет файла субтитров с таким же именем (имя.srt, имя.ru.srt, .ass, .vtt)' }
            $j.Args = @('-i', $sub, '-map', '0', '-map', '1', '-c', 'copy')
            $j.Ext = 'mkv'; $j.Suffix = '(с субтитрами)'; $j.Replace = $false
            $j.Note = "добавляю «$([IO.Path]::GetFileName($sub))»"
        }
        'subs-burn' {
            # Субтитры копируются во временный файл в TEMP: путь с «C:» в фильтре пришлось бы экранировать
            $sub = Find-SubSidecar $src
            if ($sub) {
                $tmp = "ffmpeg-sub-$PID" + [IO.Path]::GetExtension($sub).ToLower()
                Copy-Item -LiteralPath $sub -Destination (Join-Path $env:TEMP $tmp) -Force
                $j.Note = "вшиваю «$([IO.Path]::GetFileName($sub))»"
            } else {
                $text = Get-Streams $src 's' | Where-Object { $_.codec_name -in @('subrip', 'ass', 'ssa', 'mov_text', 'webvtt') } | Select-Object -First 1
                if (-not $text) { throw 'Нет ни файла субтитров рядом, ни текстовых субтитров внутри видео' }
                $tmp = "ffmpeg-sub-$PID.ass"
                & $FFmpeg -hide_banner -v error -nostdin -y -i $src -map "0:$($text.index)" (Join-Path $env:TEMP $tmp)
                $j.Note = "вшиваю встроенные субтитры: $(Format-Stream $text 1)"
            }
            $j.Args = @('-vf', "subtitles=$tmp") + (Get-VideoArgs 18) + (Get-KeepAudioArgs $src)
            $j.Ext = 'mp4'; $j.Suffix = '(с вшитыми субтитрами)'; $j.Replace = $false
        }
        'subs-extract' { $j.Custom = 'subsx'; $j.OutLabel = 'субтитры в отдельные файлы'; $j.Replace = $false }
        'split'     { $j.Custom = 'split'; $j.OutLabel = "части по $(Format-Num $splitMin) мин"; $j.Replace = $false }
        'frames'    { $j.Custom = 'frames'; $j.OutLabel = "кадр каждые $(Format-Num $framesSec) с в папку"; $j.Replace = $false }
        'check'     { $j.Custom = 'check'; $j.OutLabel = 'проверка на ошибки'; $j.Replace = $false }
        'spectrum'  { $j.Args = @('-lavfi', 'showspectrumpic=s=1600x900:legend=1', '-frames:v', '1', '-update', '1'); $j.Ext = 'png'; $j.Suffix = '(спектр)'; $j.Replace = $false }
        'musicvideo' {
            # Видео из музыки: обложка из файла (если есть) или волна звука
            $cover = Join-Path $env:TEMP "ffmpeg-cover-$PID.png"
            Remove-Item -LiteralPath $cover -ErrorAction SilentlyContinue
            & $FFmpeg -hide_banner -v error -nostdin -y -i $src -an -map '0:v:0?' -frames:v 1 -update 1 $cover 2>$null
            if ((Test-Path -LiteralPath $cover) -and (Get-Item -LiteralPath $cover).Length -gt 0) {
                $j.InArgs = @('-loop', '1', '-framerate', '2', '-i', $cover)
                $j.Args = @('-map', '0:v', '-map', '1:a', '-vf', "scale='min(1920,iw)':'min(1080,ih)':force_original_aspect_ratio=decrease,pad=ceil(iw/2)*2:ceil(ih/2)*2,format=yuv420p",
                    '-c:v', 'libx264', '-tune', 'stillimage', '-preset', 'medium', '-crf', '20', '-r', '2', '-c:a', 'aac', '-b:a', '192k', '-shortest', '-movflags', '+faststart')
                $j.Note = 'картинка — обложка из файла'
            } else {
                $j.Args = @('-filter_complex', '[0:a]showwaves=s=1280x720:mode=cline:rate=30:colors=0x4FC3F7,format=yuv420p[v]', '-map', '[v]', '-map', '0:a',
                    '-c:v', 'libx264', '-preset', 'fast', '-crf', '23', '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart')
                $j.Note = 'обложки нет — будет волна звука'
            }
            $j.Ext = 'mp4'; $j.Suffix = '(видео)'; $j.Replace = $false
        }
        'web' { $j.Args = @('-frames:v', '1', '-update', '1', '-vf', "scale='min(2560,iw)':'min(2560,ih)':force_original_aspect_ratio=decrease", '-c:v', 'libwebp', '-quality', '80'); $j.Ext = 'webp'; $j.Suffix = '(для веба)'; $j.Replace = $false }
        'fit'      { $j.Custom = 'fit'; $j.Ext = 'mp4'; $j.Suffix = "($fitLabel)"; $j.Replace = $false }
        'mp4'      { $j.Args = (Get-VideoArgs 20) + $mp4Audio; $j.Ext = 'mp4'; $j.Suffix = '(H.264)' }
        'compress' { $j.Args = (Get-VideoArgs 26 'slow') + @('-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart'); $j.Ext = 'mp4'; $j.Suffix = '(сжато)' }
        'h265'     { $j.Args = @('-c:v', 'libx265', '-preset', 'medium', '-crf', '26', '-tag:v', 'hvc1', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart'); $j.Ext = 'mp4'; $j.Suffix = '(H.265)' }
        'gpu265'   { Assert-Gpu 'h265'; $j.Args = (Get-GpuArgs 'h265' -Quality 28) + @('-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart'); $j.Ext = 'mp4'; $j.Suffix = '(H.265 GPU)' }
        'size' {
            # Битрейт под размер: (мегабайты * 8192 * 0.96 запаса) / длительность - 128 кбит/с на звук
            $dur = Get-Duration $src
            $mb = [double]::Parse($Value, $inv)   # строку надо явно сделать числом: "10" * 8192 — это повтор строки
            $kbps = [math]::Floor($mb * 8192 * 0.96 / $dur) - 128
            if ($kbps -lt 100) { throw "Видео слишком длинное, чтобы уложиться в $Value МБ" }
            if (Use-Gpu) {
                $j.Args = Get-GpuArgs 'h264' -Kbps $kbps
            } else {
                $log = Join-Path $env:TEMP "ffmpeg-2pass-$PID"
                $base2 = @('-c:v', 'libx264', '-preset', 'medium', '-b:v', "${kbps}k", '-pix_fmt', 'yuv420p', '-passlogfile', $log)
                $j.Pass1 = $base2 + @('-pass', '1', '-an', '-f', 'null')
                $j.Args = $base2 + @('-pass', '2')
            }
            $j.Args += @('-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart')
            $j.Ext = 'mp4'; $j.Suffix = "(до $Value МБ)"
        }
        'height'   { $j.Args = @('-vf', "scale=-2:'min($Value,ih)'") + (Get-VideoArgs 22) + $mp4Audio; $j.Ext = 'mp4'; $j.Suffix = "(${Value}p)" }
        'fps'      { $j.Args = @('-vf', "fps=$Value") + (Get-VideoArgs 20) + $mp4Audio; $j.Ext = 'mp4'; $j.Suffix = "($Value fps)" }
        'remux-mp4' { $j.Args = @('-map', '0:v', '-map', '0:a?', '-c', 'copy', '-movflags', '+faststart'); $j.Ext = 'mp4'; $j.Suffix = '(remux)' }
        'remux-mkv' { $j.Args = @('-map', '0', '-c', 'copy'); $j.Ext = 'mkv'; $j.Suffix = '(remux)' }
        'trim'     { $j.InArgs = $trimIn; $j.Args = @('-map', '0:v?', '-map', '0:a?', '-map', '0:s?', '-c', 'copy', '-avoid_negative_ts', 'make_zero'); $j.Suffix = '(обрезано)' }
        'trim-exact' { $j.InArgs = $trimIn; $j.Args = (Get-VideoArgs 18) + $mp4Audio; $j.Ext = 'mp4'; $j.Suffix = '(обрезано)' }
        'speed' {
            if ($videoExt -contains $srcExt) {
                $j.Args = @('-vf', "setpts=PTS/$Value", '-af', "atempo=$Value") + (Get-VideoArgs 20) + $mp4Audio; $j.Ext = 'mp4'
            } else {
                $j.Args = Get-SoundJobArgs $srcExt @("atempo=$Value")
            }
            $j.Suffix = "(скорость ${Value}x)"
        }
        'reverse'  { $j.Args = @('-vf', 'reverse', '-af', 'areverse') + (Get-VideoArgs 20) + $mp4Audio; $j.Ext = 'mp4'; $j.Suffix = '(задом наперёд)'; $j.Replace = $false }
        'square'   { $j.Args = @('-filter_complex', $square.Replace('[0:v]', "[0:$(Get-MainVideoIndex $src)]"), '-map', '[v]', '-map', '0:a?') + (Get-VideoArgs 21) + $mp4Audio; $j.Ext = 'mp4'; $j.Suffix = '(1x1)'; $j.Replace = $false }
        'boomerang' {
            # Туда и обратно из первых 4 секунд, без звука
            $m = Get-MainVideoIndex $src
            $j.InArgs = @('-t', '4')
            $j.Args = @('-filter_complex', "[0:$m]split[a][b];[b]reverse[r];[a][r]concat=n=2:v=1:a=0,$evenSize[v]", '-map', '[v]', '-an') + (Get-VideoArgs 20) + @('-movflags', '+faststart')
            $j.Ext = 'mp4'; $j.Suffix = '(бумеранг)'; $j.Replace = $false
        }
        'gif2mp4' {
            # Как делает Telegram: GIF хранится как обычное видео H.264 — в разы меньше и плавнее
            $j.Args = @('-vf', $evenSize, '-c:v', 'libx264', '-preset', 'slow', '-crf', '20', '-pix_fmt', 'yuv420p', '-an', '-movflags', '+faststart')
            $j.Ext = 'mp4'
        }
        'tgsticker' {
            # Видеостикер Telegram: WEBM (VP9), одна сторона 512 px, до 3 секунд, без звука, прозрачность сохраняется
            $j.Args = @('-t', '3', '-vf', 'scale=512:512:force_original_aspect_ratio=decrease,fps=30', '-c:v', 'libvpx-vp9', '-pix_fmt', 'yuva420p', '-b:v', '400k', '-crf', '30', '-deadline', 'good', '-row-mt', '1', '-an')
            $j.Ext = 'webm'; $j.Suffix = '(стикер)'; $j.Replace = $false
            if ((Get-Duration $src) -gt 3) { $j.Note = 'стикер может длиться не больше 3 секунд — берутся первые 3' }
        }
        'vertical' { $j.Args = @('-filter_complex', $vertical.Replace('[0:v]', "[0:$(Get-MainVideoIndex $src)]"), '-map', '[v]', '-map', '0:a?') + (Get-VideoArgs 21) + $mp4Audio; $j.Ext = 'mp4'; $j.Suffix = '(9x16)'; $j.Replace = $false }
        'frame'    { $j.InArgs = @('-ss', (Format-Num ((Get-Duration $src) / 2))); $j.Args = @('-frames:v', '1', '-update', '1', '-q:v', '2'); $j.Ext = 'jpg'; $j.Suffix = '(кадр)'; $j.Replace = $false }
        'sheet' {
            $rate = Format-Num (16 / (Get-Duration $src))
            $j.Args = @('-vf', "fps=$rate,scale=480:-2,tile=4x4:padding=4:margin=4", '-frames:v', '1', '-update', '1', '-q:v', '3')
            $j.Ext = 'jpg'; $j.Suffix = '(превью)'; $j.Replace = $false
        }
        'vrotate'  { $j.Args = @('-vf', $rotate[$Value]) + (Get-VideoArgs 18) + $mp4Audio; $j.Ext = 'mp4'; $j.Suffix = "($($rotateName[$Value]))" }
        'mute'     { $j.Args = @('-an', '-c', 'copy'); $j.Suffix = '(без звука)' }
        'gif'      { $j.Args = @('-vf', $gif[$Value][1], '-loop', '0'); $j.Ext = 'gif'; $j.Suffix = "(GIF $($gif[$Value][0]))"; $j.Replace = $false }
        'extract'  {
            $f = $audioFormats[$Value]; $j.Ext = $f[0]; $j.Replace = $false
            # MP3, WAV, FLAC и др. вмещают одну дорожку: если их несколько — каждая выбранная в свой файл (MKA вмещает все)
            $tracks = @(Get-Streams $src 'a')
            if ($tracks.Count -eq 0) { throw 'В файле нет звука' }
            if ($Value -ne 'mka' -and $tracks.Count -gt 1) { $j.Custom = 'audiox'; $j.OutLabel = 'звуковые дорожки в отдельные файлы' }
            elseif ($Value -eq 'mka' -and $tracks.Count -gt 1) {
                # MKA вмещает все дорожки: выбранные кладутся в один файл, первая — по умолчанию
                $keep = @(Request-Tracks $src $tracks 'Выбранные дорожки лягут в один файл MKA. Можно «1 3» или «2-4», Enter — все.' 'Какие извлечь (номера)')
                foreach ($k in $keep) { if ($k -gt $tracks.Count) { throw "Нет дорожки номер $k" } }
                $j.Args = @('-vn')
                foreach ($k in $keep) { $j.Args += @('-map', "0:a:$($k - 1)") }
                $j.Args += $f[1] + @('-disposition:a', '0', '-disposition:a:0', 'default') + (Get-TrackNameArgs $src $keep)
                if ($keep.Count -lt $tracks.Count) {
                    if ($keep.Count -eq 1) { $j.Suffix = "(дорожка $($keep[0]))" } else { $j.Suffix = "(дорожки $($keep -join ', '))" }
                }
            }
            else { $j.Args = @('-vn', '-map', '0:a') + $f[1] }
        }
        'audio'    {
            $f = $audioFormats[$Value]; $j.Ext = $f[0]; if ($Value -eq 'mp3vbr') { $j.Suffix = '(VBR)' }
            # MP3, M4A и FLAC вмещают обложку — она переносится как есть, остальные форматы — только звук
            if (@('mp3', 'm4a', 'flac') -contains $f[0]) { $j.Args = @('-map', '0:a', '-map', '0:v?', '-c:v', 'copy', '-disposition:v', 'attached_pic') + $f[1] }
            else { $j.Args = @('-vn') + $f[1] }
        }
        'louder'   { $j.Args = Get-SoundJobArgs $srcExt @("volume=${Value}dB") $src; $j.Suffix = "(громче +$Value дБ$($script:soundNote))" }
        'quieter'  { $j.Args = Get-SoundJobArgs $srcExt @("volume=-${Value}dB") $src; $j.Suffix = "(тише -$Value дБ$($script:soundNote))" }
        'normalize' { $j.Args = Get-SoundJobArgs $srcExt @('loudnorm=I=-16:TP=-1.5:LRA=11') $src @('-ar', '48000'); $j.Suffix = "(громкость$($script:soundNote))" }
        'fade' {
            $d = Get-Duration $src
            $in = [math]::Min(2, $d / 4); $out = [math]::Min(3, $d / 4)
            $j.Args = Get-SoundJobArgs $srcExt @("afade=t=in:st=0:d=$(Format-Num $in),afade=t=out:st=$(Format-Num ($d - $out)):d=$(Format-Num $out)") $src
            $j.Suffix = "(плавно$($script:soundNote))"
        }
        'mono'      { $j.Args = Get-SoundJobArgs $srcExt @('aformat=channel_layouts=mono') $src; $j.Suffix = "(моно$($script:soundNote))" }
        'slowed' {
            if ($videoExt -contains $srcExt) { throw 'Этот эффект меняет длину звука — только для звуковых файлов, у видео звук разошёлся бы с картинкой' }
            $sr = Get-SampleRate $src
            $j.Args = Get-SoundJobArgs $srcExt @("asetrate=$([int]($sr * 0.85)),aresample=$sr,aecho=0.8:0.88:60:0.4") $src
            $j.Suffix = "(slowed + reverb$($script:soundNote))"
        }
        'nightcore' {
            if ($videoExt -contains $srcExt) { throw 'Этот эффект меняет длину звука — только для звуковых файлов, у видео звук разошёлся бы с картинкой' }
            $sr = Get-SampleRate $src
            $j.Args = Get-SoundJobArgs $srcExt @("asetrate=$([int]($sr * 1.25)),aresample=$sr") $src
            $j.Suffix = "(nightcore$($script:soundNote))"
        }
        'ringtone' {
            # Рингтон для iPhone: M4R (AAC), первые 30 секунд, затухание в конце
            $d = [math]::Min((Get-Duration $src), 30)
            $j.Args = @('-t', '30', '-vn', '-c:a', 'aac', '-b:a', '256k', '-af', "afade=t=out:st=$(Format-Num ([math]::Max(0, $d - 2))):d=2", '-f', 'ipod')
            $j.Ext = 'm4r'; $j.Suffix = '(рингтон)'; $j.Replace = $false
        }
        'silence'  { $j.Args = Get-SoundJobArgs $srcExt @($silence); $j.Suffix = '(без тишины)' }
        'image'    {
            $j.Ext = $Value; $j.Args = Get-ImageArgs $Value
            # В JPG нет прозрачности: прозрачные места заливаются белым, а не становятся чёрными
            if (@('jpg', 'jpeg') -contains $Value -and (Test-HasAlpha $src)) {
                $j.Args = @('-filter_complex', '[0:v]format=rgba,split[a][b];[a]drawbox=c=white:t=fill[w];[w][b]overlay=format=auto') + $j.Args
            }
        }
        'ico'      { $j.Ext = 'ico'; $j.Args = @('-frames:v', '1', '-update', '1', '-vf', 'scale=256:256:force_original_aspect_ratio=decrease,format=rgba,pad=256:256:(ow-iw)/2:(oh-ih)/2:color=black@0', '-c:v', 'png'); $j.Replace = $false }
        'squarecrop' { $j.Args = @('-vf', "crop='min(iw,ih)':'min(iw,ih)'") + (Get-ImageArgs $srcExt); $j.Suffix = '(квадрат)' }
        'gray'     { $j.Args = @('-vf', 'hue=s=0') + (Get-ImageArgs $srcExt); $j.Suffix = '(ч-б)' }
        'upscale'  { $j.Args = @('-vf', "scale=iw*${Value}:ih*${Value}:flags=lanczos") + (Get-ImageArgs $srcExt); $j.Suffix = "(x$Value)" }
        'downscale' { $j.Args = @('-vf', "scale=iw/${Value}:-1:flags=lanczos") + (Get-ImageArgs $srcExt); $j.Suffix = "(уменьшено в $Value раза)" }
        'irotate'  { $j.Args = @('-vf', $rotate[$Value]) + (Get-ImageArgs $srcExt); $j.Suffix = "($($rotateName[$Value]))" }
        default    { throw "Неизвестная операция: $Preset" }
    }
    return $j
}

# Свободное имя: «имя.ext», а если занято — «имя (2).ext», «имя (3).ext»…
function Get-FreePath([string]$dir, [string]$name, [string]$ext) {
    $p = Join-Path $dir "$name.$ext"
    $k = 2
    while (Test-Path -LiteralPath $p) { $p = Join-Path $dir "$name ($k).$ext"; $k++ }
    return $p
}

# Папка для копий: рядом с исходником или в подпапке «FFmpeg»
function Get-OutDir([string]$dir) {
    if (-not $toSubfolder) { return $dir }
    $d = Join-Path $dir 'FFmpeg'
    if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d | Out-Null }
    return $d
}

Add-Type -AssemblyName Microsoft.VisualBasic
function Send-ToRecycleBin([string]$path) {
    [Microsoft.VisualBasic.FileIO.FileSystem]::DeleteFile($path, 'OnlyErrorDialogs', 'SendToRecycleBin')
}

function Finish([int]$ok, [int]$n, [string[]]$failed) {
    Write-Host ''
    if ($beepAtEnd -and -not $NoPause) { [Media.SystemSounds]::Asterisk.Play() }
    if ($revealAtEnd -and -not $NoPause -and -not $script:cancelled -and $script:lastOutput -and (Test-Path -LiteralPath $script:lastOutput)) {
        Start-Process explorer.exe -ArgumentList ('/select,"' + $script:lastOutput + '"')
    }
    if ($script:cancelled) {
        Write-Host "Отменено. Успели обработать: $ok из $n" -ForegroundColor Yellow
        if (-not $NoPause) { Read-Host 'Нажми Enter, чтобы закрыть' }
        return
    }
    if ($failed.Count -eq 0) {
        Write-Host "Готово: $ok из $n" -ForegroundColor Green
        if ($NoPause) { return }
        if ($alwaysWait) { Read-Host 'Нажми Enter, чтобы закрыть' } else { Start-Sleep -Seconds 3 }
    } else {
        Write-Host "Готово: $ok из $n. Не получилось: $($failed.Count)" -ForegroundColor Yellow
        foreach ($f in $failed) { Write-Host "  $f" }
        if (-not $NoPause) { Read-Host 'Нажми Enter, чтобы закрыть' }
    }
}

# Полоса прогресса: [████████░░░░]  58%  1:45 / 3:00  ·  2.4x  ·  осталось ~0:52
function Get-ProgressText([double]$cur, [double]$total, [string]$spd, [double]$elapsed) {
    $w = 24
    if ($total -gt 0) {
        $p = [math]::Min(1.0, [math]::Max(0.0, $cur / $total))
        $fill = [int][math]::Round($p * $w)
        $bar = ([string][char]0x2588 * $fill) + ([string][char]0x2591 * ($w - $fill))
        $text = '  [{0}] {1,3}%  {2} / {3}' -f $bar, [int][math]::Floor($p * 100), (Format-Time ([math]::Floor($cur))), (Format-Time ([math]::Floor($total)))
        if ($spd) { $text += "  ·  $spd" }
        if ($p -gt 0.02 -and $p -lt 1) { $text += '  ·  осталось ~' + (Format-Time ([math]::Ceiling($elapsed * (1 - $p) / $p))) }
    } else {
        $text = '  обработано {0}' -f (Format-Time ([math]::Floor($cur)))
        if ($spd) { $text += "  ·  $spd" }
    }
    return $text
}

# Нагрузка на компьютер: ЦП и память самого ffmpeg, видеокарта — через nvidia-smi
$nvidiaSmi = (Get-Command nvidia-smi -ErrorAction SilentlyContinue).Source
$cores = [Environment]::ProcessorCount

function Format-Size([double]$bytes) {
    if ($bytes -ge 1GB) { return ($bytes / 1GB).ToString('0.0', $inv) + ' ГБ' }
    return [string][int]($bytes / 1MB) + ' МБ'
}

function Update-Resources($state, [double]$now) {
    if (-not $state.Proc) {
        # ffmpeg — дочерний процесс этого окна; ищем его один раз
        $child = Get-CimInstance Win32_Process -Filter "ParentProcessId=$PID AND Name='ffmpeg.exe'" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($child) { try { $state.Proc = [Diagnostics.Process]::GetProcessById([int]$child.ProcessId) } catch { } }
    }
    if ($state.Proc) {
        try {
            $state.Proc.Refresh()
            $cpuTime = $state.Proc.TotalProcessorTime.TotalSeconds
            if ($state.LastWall -gt 0 -and $now -gt $state.LastWall) {
                $state.Cpu = [int][math]::Min(100, ($cpuTime - $state.LastCpu) / ($now - $state.LastWall) / $cores * 100)
            }
            $state.LastCpu = $cpuTime
            $state.LastWall = $now
            $state.Ram = $state.Proc.WorkingSet64
        } catch { }
    }
    if ($nvidiaSmi -and ($now - $state.GpuAt) -ge 1) {
        $state.GpuAt = $now
        $r = & $nvidiaSmi --query-gpu=utilization.gpu,utilization.encoder,memory.used --format=csv,noheader,nounits 2>$null | Select-Object -First 1
        $v = "$r".Split(',') | ForEach-Object { $_.Trim() }
        if ($v.Count -ge 3) { $state.Gpu = '   │   видеокарта {0}% · кодировщик {1}% · видеопамять {2}' -f $v[0], $v[1], (Format-Size ([double]$v[2] * 1MB)) }
    }
    $text = '  ЦП {0}% · память {1}' -f $state.Cpu, (Format-Size $state.Ram)
    return $text + $state.Gpu
}

# Две строки, перерисовываются на месте. Если вывод перенаправлен (тесты) — одна строка через `r
$plainOut = [Console]::IsOutputRedirected
function Write-Block([string]$l1, [string]$l2, $state) {
    if ($plainOut) { Write-Host ("`r" + $l1.PadRight(80)) -NoNewline; return }
    $w = [math]::Max(40, $Host.UI.RawUI.BufferSize.Width - 1)
    if ($l1.Length -gt $w) { $l1 = $l1.Substring(0, $w) }
    if ($l2.Length -gt $w) { $l2 = $l2.Substring(0, $w) }
    if ($state.Top -ge 0) { $Host.UI.RawUI.CursorPosition = New-Object Management.Automation.Host.Coordinates 0, $state.Top }
    Write-Host $l1.PadRight($w)
    Write-Host $l2.PadRight($w) -NoNewline
    $state.Top = $Host.UI.RawUI.CursorPosition.Y - 1
}

# Esc, Q или Ctrl+C (Ctrl+C приходит клавишей, пока включён TreatControlCAsInput)
function Test-CancelKey {
    if ($plainOut) { return $false }
    while ([Console]::KeyAvailable) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq [ConsoleKey]::Escape -or $k.Key -eq [ConsoleKey]::Q) { return $true }
        if ($k.Key -eq [ConsoleKey]::C -and ($k.Modifiers -band [ConsoleModifiers]::Control)) { return $true }
    }
    return $false
}

# Запуск ffmpeg с полосой прогресса. $total — ожидаемая длина результата в секундах
# (0 — неизвестна, тогда показывается только обработанное время). Возвращает код выхода.
function Invoke-FFmpeg([string[]]$ffArgs, [double]$total) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $state = @{ Cur = 0.0; Spd = ''; Shown = $false; Top = -1; Proc = $null; LastCpu = 0.0; LastWall = 0.0; Cpu = 0; Ram = 0; Gpu = ''; GpuAt = -10.0 }
    # Ctrl+C не убивает окно, а приходит как клавиша; -nostdin — чтобы ffmpeg не забирал нажатия себе
    if (-not $plainOut) { [Console]::TreatControlCAsInput = $true }
    try {
    & $FFmpeg -hide_banner -v error -nostats -nostdin -progress pipe:1 -stats_period 0.5 @ffArgs 2>&1 | ForEach-Object {
        if ($_ -is [Management.Automation.ErrorRecord]) {
            $msg = "$_".Trim()
            if ($msg) {
                $script:ffErrorCount++
                if ($state.Shown) { Write-Host '' }
                Write-Host "  $msg" -ForegroundColor Red
                $state.Shown = $false
                $state.Top = -1
            }
            return
        }
        $line = "$_"
        if ($line.StartsWith('out_time_us=')) {
            $us = 0.0
            if ([double]::TryParse($line.Substring(12), [Globalization.NumberStyles]::Float, $inv, [ref]$us) -and $us -ge 0) { $state.Cur = $us / 1000000 }
        } elseif ($line.StartsWith('speed=')) {
            # «2.41x» -> «2.4x», «1.85e+03x» -> «1850x»
            $sv = 0.0
            if ([double]::TryParse($line.Substring(6).Trim().TrimEnd('x'), [Globalization.NumberStyles]::Float, $inv, [ref]$sv)) {
                $fmt = '0.0'
                if ($sv -ge 10) { $fmt = '0' }
                $state.Spd = $sv.ToString($fmt, $inv) + 'x'
            }
        } elseif ($line.StartsWith('progress=')) {
            if ($script:cancelled) { return }
            $wantCancel = Test-CancelKey
            if ($TestCancelAfter -gt 0 -and $sw.Elapsed.TotalSeconds -ge $TestCancelAfter) { $wantCancel = $true }
            if ($wantCancel) {
                $script:cancelled = $true
                if (-not $state.Proc) { [void](Update-Resources $state $sw.Elapsed.TotalSeconds) }
                if ($state.Proc) { try { $state.Proc.Kill() } catch { } }
                if ($state.Shown) { Write-Host '' }
                Write-Host '  Останавливаю…' -ForegroundColor Yellow
                $state.Shown = $false
                return
            }
            if ($line -eq 'progress=end' -and $total -gt 0) { $state.Cur = $total }
            $now = $sw.Elapsed.TotalSeconds
            $l1 = Get-ProgressText $state.Cur $total $state.Spd $now
            $l2 = Update-Resources $state $now
            Write-Block $l1 $l2 $state
            $state.Shown = $true
        }
    }
    $code = $LASTEXITCODE
    } finally {
        if (-not $plainOut) { [Console]::TreatControlCAsInput = $false }
    }
    if ($state.Shown) { Write-Host '' }
    return $code
}

# Ожидаемая длина результата: для скорости и обрезки она отличается от исходной
function Get-OutputDuration([string]$src) {
    $d = 0.0
    try { $d = Get-Duration $src } catch { return 0.0 }
    if ($Preset -eq 'speed') { $d = $d / [double]::Parse($Value, $inv) }
    if ($Preset -eq 'teaser') { $d = 12 }
    if ($Preset -eq 'tgsticker') { $d = [math]::Min($d, 3) }
    if ($Preset -eq 'boomerang') { $d = 2 * [math]::Min($d, 4) }
    if ($Preset -eq 'ringtone') { $d = [math]::Min($d, 30) }
    if ($Preset -eq 'slowed') { $d = $d / 0.85 }
    if ($Preset -eq 'nightcore') { $d = $d / 1.25 }
    if ($Preset -like 'trim*') {
        $from = 0.0; $to = $d
        if ($null -ne $trimStart) { $from = $trimStart }
        if ($null -ne $trimEnd) { $to = [math]::Min($trimEnd, $d) }
        $d = [math]::Max(0.0, $to - $from)
    }
    return $d
}

# Картинкам и кадрам полоса не нужна: они обрабатываются за доли секунды
$noProgress = @('image', 'ico', 'gray', 'upscale', 'downscale', 'irotate', 'frame', 'sheet', 'spectrum', 'web', 'squarecrop')

# ---------- Дополнительные операции ----------
$audioExt = @('mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus', 'wma', 'ac3', 'dts', 'aiff', 'ape', 'wv', 'mka')
$script:lastOutput = ''        # последний созданный файл/папка — для «Показать в проводнике»
$script:ffErrorCount = 0       # сколько строк-ошибок напечатал ffmpeg (для проверки файла)

# Звук без перекодирования, если все дорожки уже AAC (MP4 вмещает его как есть), иначе AAC 192 кбит/с
function Get-KeepAudioArgs([string]$src) {
    $codecs = @(Get-Streams $src 'a' | ForEach-Object { "$($_.codec_name)" })
    if ($codecs.Count -and -not ($codecs | Where-Object { $_ -ne 'aac' })) { return @('-c:a', 'copy', '-movflags', '+faststart') }
    return @('-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart')
}

# Номер потока основного видео: первое видео, которое не обложка (attached_pic). $null — видео нет
function Get-MainVideoIndex([string]$src) {
    $json = (& $FFprobe -v error -select_streams v -show_entries 'stream=index:stream_disposition=attached_pic' -of json $src 2>$null) -join ''
    if (-not $json) { return $null }
    foreach ($s in @(($json | ConvertFrom-Json).streams)) { if ($s.disposition.attached_pic -ne 1) { return [int]$s.index } }
    return $null
}

# Если операция перекодирует видео и сама не выбирает потоки, ffmpeg взял бы одну звуковую дорожку,
# а у видео с обложкой — иногда саму обложку. Поэтому явно: основное видео и все звуковые дорожки
# (если формат результата вмещает звук и звук не убран)
function Add-StreamMaps($job, [string]$src) {
    $a = @($job.Args)
    if ($a -contains '-map' -or $a -contains '-filter_complex' -or $a -contains '-lavfi') { return $job }
    if (-not ($a -contains '-vf' -or $a -contains '-c:v' -or $a -contains '-frames:v')) { return $job }
    $main = Get-MainVideoIndex $src
    if ($null -eq $main) { return $job }
    $maps = @('-map', "0:$main")
    $ext = $job.Ext
    if (-not $ext) { $ext = $srcExt }
    if ($a -notcontains '-an' -and @('mp4', 'mkv', 'mov', 'm4v', 'webm', 'ts', 'avi') -contains $ext) { $maps += @('-map', '0:a?') }
    $job.Args = $maps + $a
    if ($job.Pass1) { $job.Pass1 = @('-map', "0:$main") + @($job.Pass1) }
    return $job
}

# H.264 и H.265 (и кодировщики видеокарт) не принимают нечётный размер кадра (например, 641×361):
# при перекодировании размер подгоняется до чётного — к фильтрам операции дописывается scale
function Add-EvenSize($job) {
    $a = @($job.Args)
    $encoders = @('libx264', 'libx265', 'h264_nvenc', 'hevc_nvenc', 'h264_amf', 'hevc_amf', 'h264_qsv', 'hevc_qsv')
    if (-not ($a | Where-Object { $encoders -contains $_ })) { return $job }
    $i = [array]::IndexOf($a, '-vf')
    if ($i -ge 0) {
        if ($a[$i + 1] -notlike '*trunc(iw/2)*') { $a[$i + 1] = $a[$i + 1] + ',' + $evenSize }
    } elseif ($a -notcontains '-filter_complex' -and $a -notcontains '-lavfi') {
        $a = @('-vf', $evenSize) + $a
    }
    $job.Args = $a
    return $job
}

# Есть ли у картинки прозрачность (альфа-канал или палитра)
function Test-HasAlpha([string]$src) {
    $pf = "$(& $FFprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of csv=p=0 $src 2>$null)".Trim()
    return ($pf -match '^(rgba|bgra|argb|abgr|ya8|ya16|yuva|gbrap|pal8|rgba64|bgra64)')
}

# Текущий поворот из метаданных (градусы против часовой; телефоны пишут, например, -90)
function Get-Rotation([string]$src) {
    $r = "$(& $FFprobe -v error -select_streams v:0 -show_entries stream_side_data=rotation -of csv=p=0 $src 2>$null)".Trim()
    $x = 0.0
    if ([double]::TryParse(($r -split '[,\s]')[0], [Globalization.NumberStyles]::Float, $inv, [ref]$x)) { return [int]$x }
    return 0
}

# Ищет чёрные полосы: прогоняет до минуты видео через cropdetect и берёт итоговую рамку
function Get-CropFilter([string]$src) {
    $dur = Get-Duration $src
    $from = Format-Num ([math]::Max(0, $dur * 0.1))
    $len = Format-Num ([math]::Min(60, [math]::Max(1, $dur * 0.8)))
    $last = ''
    & $FFmpeg -hide_banner -nostdin -ss $from -i $src -t $len -vf 'cropdetect=limit=24:round=2:reset=0' -an -sn -f null - 2>&1 | ForEach-Object {
        $m = [regex]::Match("$_", 'crop=(\d+:\d+:\d+:\d+)')
        if ($m.Success) { $last = $m.Groups[1].Value }
    }
    $info = Get-StreamInfo $src
    if (-not $last) { throw 'Не удалось определить рамку' }
    $p = $last.Split(':')
    if ([int]$p[0] -ge $info.W - 4 -and [int]$p[1] -ge $info.H - 4) { throw 'Чёрных полос не нашлось' }
    return $last
}

# Файл субтитров рядом с видео: «имя.srt» или «имя.ru.srt» (srt, ass, ssa, vtt)
function Find-SubSidecar([string]$src) {
    $dir = [IO.Path]::GetDirectoryName($src)
    $base = [IO.Path]::GetFileNameWithoutExtension($src)
    Get-ChildItem -LiteralPath $dir -File | Where-Object {
        $_.Extension.ToLower() -in @('.srt', '.ass', '.ssa', '.vtt') -and ($_.BaseName -eq $base -or $_.BaseName.StartsWith("$base."))
    } | Sort-Object Name | Select-Object -First 1 -ExpandProperty FullName
}

# Потоки файла одного типа (a — звук, s — субтитры) с языком и названием
function Get-Streams([string]$src, [string]$type) {
    $json = (& $FFprobe -v error -select_streams $type -show_entries 'stream=index,codec_name,channels,sample_rate,bit_rate:stream_tags=language,title,name,handler_name' -of json $src 2>$null) -join ''
    if (-not $json) { return @() }
    return @(($json | ConvertFrom-Json).streams)
}

$langNames = @{ 'rus' = 'русский'; 'ru' = 'русский'; 'eng' = 'английский'; 'en' = 'английский'; 'jpn' = 'японский'; 'ja' = 'японский'; 'ukr' = 'украинский'; 'deu' = 'немецкий'; 'ger' = 'немецкий'; 'fra' = 'французский'; 'fre' = 'французский'; 'spa' = 'испанский'; 'ita' = 'итальянский'; 'kor' = 'корейский'; 'chi' = 'китайский'; 'zho' = 'китайский'; 'und' = 'язык не указан' }
# Название дорожки: title (MKV и др.), name (MP4 от OBS — блок udta/name) или handler_name.
# Служебные имена вроде «SoundHandler» названием не считаются
function Get-StreamName($s) {
    $name = "$($s.tags.title)".Trim()
    if (-not $name) { $name = "$($s.tags.name)".Trim() }
    if (-not $name) { $name = "$($s.tags.handler_name)".Trim() }
    if ($name -match '(?i)sound ?handler|media handler|core media|iso media|audio handler|video handler|subtitle handler') { $name = '' }
    return $name
}
function Format-Stream($s, [int]$num) {
    $lang = "$($s.tags.language)"
    if ($lang -eq 'und') { $lang = '' }
    if ($langNames.ContainsKey($lang)) { $lang = $langNames[$lang] }
    $name = Get-StreamName $s
    $head = "$num)"
    if ($name) { $head += " $name" }
    $parts = @("$head")
    $tech = @($s.codec_name)
    if ($s.sample_rate) { $tech += "$($s.sample_rate) Гц" }
    switch ("$($s.channels)") { '' { } '1' { $tech += 'моно' } '2' { $tech += 'стерео' } '6' { $tech += '5.1' } '8' { $tech += '7.1' } default { $tech += "$($s.channels) кан." } }
    if ($s.bit_rate -and "$($s.bit_rate)" -match '^[0-9]+$') { $tech += "$([math]::Round([double]$s.bit_rate / 1000)) кбит/с" }
    $parts += ($tech -join ', ')
    if ($lang) { $parts += $lang }
    return ($parts -join ' · ')
}

# При копировании ffmpeg теряет названия звуковых дорожек MP4, поэтому каждой дорожке результата название
# вписывается явно (ffmpeg пишет его в тот же блок name). $order — номера исходных дорожек (с 1) в порядке результата
function Get-TrackNameArgs([string]$src, [int[]]$order) {
    $tracks = @(Get-Streams $src 'a')
    if (-not $order) { $order = @(1..$tracks.Count) }
    $a = @()
    for ($i = 0; $i -lt $order.Count; $i++) {
        $k = $order[$i]
        if ($k -lt 1 -or $k -gt $tracks.Count) { continue }
        $name = Get-StreamName $tracks[$k - 1]
        if ($name) { $a += @("-metadata:s:a:$i", "title=$name") }
    }
    return $a
}
# Идут ли все звуковые дорожки в результат в исходном порядке (-map 0 или -map 0:a?)
function Test-KeepsAllAudio($a) {
    $a = @($a)
    for ($i = 0; $i -lt $a.Count - 1; $i++) { if ($a[$i] -eq '-map' -and @('0', '0:a', '0:a?') -contains $a[$i + 1]) { return $true } }
    return $false
}

# «1 3», «1,3», «2-4» -> номера дорожек по порядку ввода, без повторов; пусто, если записано неправильно
function ConvertTo-TrackList([string]$text, [int]$max) {
    $list = New-Object System.Collections.Generic.List[int]
    foreach ($part in ($text -split '[ ,;]+')) {
        if (-not $part) { continue }
        if ($part -match '^([0-9]+)-([0-9]+)$') {
            $a = [int]$matches[1]; $b = [int]$matches[2]
            if ($a -gt $b) { $a, $b = $b, $a }
            for ($i = $a; $i -le $b; $i++) { if (-not $list.Contains($i)) { $list.Add($i) } }
        } elseif ($part -match '^[0-9]+$') {
            if (-not $list.Contains([int]$part)) { $list.Add([int]$part) }
        } else { return @() }
    }
    foreach ($i in $list) { if ($i -lt 1 -or $i -gt $max) { return @() } }
    return $list.ToArray()
}
# Спрашивает номера дорожек, пока не введут правильно. -AllowEmpty: пустой ответ = все дорожки (вернётся пустой список)
function Read-TrackList([string]$label, [int]$max, [switch]$AllowEmpty) {
    while ($true) {
        $answer = (Read-Host $label).Trim()
        if ($AllowEmpty -and -not $answer) { return @() }
        $list = @(ConvertTo-TrackList $answer $max)
        if ($list.Count) { return $list }
        Write-Host "  Нужны номера от 1 до $max, например «1 3» или «2-4»" -ForegroundColor Red
    }
}

# Какие звуковые дорожки взять: список с названиями, ответ один на все выбранные файлы. Пустой ответ — все дорожки
function Request-Tracks([string]$src, $tracks, [string]$hint, [string]$label) {
    if ($null -eq $script:pickedTracks) {
        Write-Host ''
        Write-Host "Звуковые дорожки в «$([IO.Path]::GetFileName($src))»:" -ForegroundColor White
        for ($t = 0; $t -lt $tracks.Count; $t++) { Write-Host "  $(Format-Stream $tracks[$t] ($t + 1))" }
        Write-Host "  $hint" -ForegroundColor DarkGray
        $script:pickedTracks = @(Read-TrackList $label $tracks.Count -AllowEmpty)
    }
    $keep = @($script:pickedTracks)
    if (-not $keep.Count) { $keep = @(1..$tracks.Count) }
    return $keep
}

# Звук из файла с несколькими звуковыми дорожками: каждая выбранная — отдельный файл «имя (название дорожки).ext».
# Номера спрашиваются один раз для всех выбранных файлов
function Invoke-AudioExtract([string]$src) {
    $tracks = @(Get-Streams $src 'a')
    $f = $audioFormats[$Value]
    $keep = @(Request-Tracks $src $tracks 'Каждая выбранная дорожка будет отдельным файлом. Можно «1 3» или «2-4», Enter — все.' 'Какие извлечь (номера)')
    $dir = Get-OutDir ([IO.Path]::GetDirectoryName($src))
    $base = [IO.Path]::GetFileNameWithoutExtension($src)
    $dur = Get-Duration $src
    $made = 0
    foreach ($k in $keep) {
        if ($k -gt $tracks.Count) { Write-Host "  Нет дорожки номер $k — пропускаю" -ForegroundColor Yellow; continue }
        $s = $tracks[$k - 1]
        $name = Get-StreamName $s
        $label = $name
        if (-not $label) { $label = "дорожка $k" }
        foreach ($c in [IO.Path]::GetInvalidFileNameChars()) { $label = $label.Replace([string]$c, '_') }
        $out = Get-FreePath $dir "$base ($label)" $f[0]
        Write-Host "  $(Format-Stream $s $k)  ->  $([IO.Path]::GetFileName($out))"
        $a = @('-n', '-i', $src, '-vn', '-map', "0:a:$($k - 1)") + $f[1]
        if ($name) { $a += @('-metadata', "title=$name") }
        $code = Invoke-FFmpeg ($a + @($out)) $dur
        if ($script:cancelled -or $code -ne 0) {
            if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue }
            if ($script:cancelled) { return 1 }
            continue
        }
        $script:lastOutput = $out
        $made++
    }
    if ($made -eq 0) { return 1 }
    return 0
}

# Извлечь все субтитры в отдельные файлы рядом с видео
function Invoke-SubsExtract([string]$src) {
    $subs = Get-Streams $src 's'
    if ($subs.Count -eq 0) { Write-Host '  Субтитров в файле нет' -ForegroundColor Yellow; return 1 }
    $dir = Get-OutDir ([IO.Path]::GetDirectoryName($src))
    $base = [IO.Path]::GetFileNameWithoutExtension($src)
    $made = 0
    $k = 0
    foreach ($s in $subs) {
        $k++
        $codec = "$($s.codec_name)"
        $ext = ''; $c = @('-c:s', 'copy')
        switch ($codec) {
            'subrip'            { $ext = 'srt' }
            'mov_text'          { $ext = 'srt'; $c = @('-c:s', 'srt') }
            'ass'               { $ext = 'ass' }
            'ssa'               { $ext = 'ass' }
            'webvtt'            { $ext = 'vtt' }
            'hdmv_pgs_subtitle' { $ext = 'sup' }
        }
        if (-not $ext) { Write-Host "  $(Format-Stream $s $k) — такой формат не извлекается, пропускаю" -ForegroundColor Yellow; continue }
        $tag = "$($s.tags.language)"
        if (-not $tag -or $tag -eq 'und') { $tag = "$k" }
        $out = Get-FreePath $dir "$base.$tag" $ext
        & $FFmpeg -hide_banner -v error -nostdin -n -i $src -map "0:$($s.index)" @c $out
        if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $out)) {
            Write-Host "  $(Format-Stream $s $k)  ->  $([IO.Path]::GetFileName($out))"
            $script:lastOutput = $out
            $made++
        }
    }
    if ($made -eq 0) { return 1 }
    return 0
}

# Разрезать на части по N минут без перекодирования
function Invoke-Split([string]$src) {
    $dir = Get-OutDir ([IO.Path]::GetDirectoryName($src))
    $base = [IO.Path]::GetFileNameWithoutExtension($src)
    $ext = [IO.Path]::GetExtension($src).TrimStart('.').ToLower()
    $prefix = "$base (часть"
    $k = 2
    while (Test-Path -LiteralPath (Join-Path $dir "$prefix 01).$ext")) { $prefix = "$base ($k) (часть"; $k++ }
    $pattern = Join-Path $dir "$prefix %02d).$ext"
    $before = @(Get-ChildItem -LiteralPath $dir -File | ForEach-Object FullName)
    $code = Invoke-FFmpeg (@('-n', '-i', $src, '-map', '0', '-c', 'copy') + @(Get-TrackNameArgs $src) + @('-f', 'segment', '-segment_time', (Format-Num ($splitMin * 60)), '-reset_timestamps', '1', '-segment_start_number', '1', $pattern)) (Get-Duration $src)
    $new = @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $before -notcontains $_.FullName -and $_.Name.StartsWith($prefix) } | Sort-Object Name)
    if ($script:cancelled -or $code -ne 0) {
        Start-Sleep -Milliseconds 300
        $new | Remove-Item -ErrorAction SilentlyContinue
        return 1
    }
    Write-Host "  Получилось частей: $($new.Count)" -ForegroundColor Green
    if ($new.Count) { $script:lastOutput = $new[0].FullName }
    return 0
}

# Кадры каждые N секунд — в отдельную папку
function Invoke-Frames([string]$src) {
    $dir = Get-OutDir ([IO.Path]::GetDirectoryName($src))
    $base = [IO.Path]::GetFileNameWithoutExtension($src)
    $folder = Join-Path $dir "$base (кадры)"
    $k = 2
    while (Test-Path -LiteralPath $folder) { $folder = Join-Path $dir "$base (кадры $k)"; $k++ }
    New-Item -ItemType Directory -Path $folder | Out-Null
    $code = Invoke-FFmpeg @('-n', '-i', $src, '-vf', "fps=1/$(Format-Num $framesSec)", '-q:v', '2', (Join-Path $folder 'кадр %04d.jpg')) (Get-Duration $src)
    if ($script:cancelled -or $code -ne 0) {
        Start-Sleep -Milliseconds 300
        Remove-Item -LiteralPath $folder -Recurse -ErrorAction SilentlyContinue
        return 1
    }
    $count = @(Get-ChildItem -LiteralPath $folder -File).Count
    Write-Host "  Сохранено кадров: $count  ->  папка «$([IO.Path]::GetFileName($folder))»" -ForegroundColor Green
    $script:lastOutput = $folder
    return 0
}

# Проверка файла: полное декодирование, все ошибки печатаются
function Invoke-Check([string]$src) {
    $script:ffErrorCount = 0
    $code = Invoke-FFmpeg @('-i', $src, '-map', '0:v?', '-map', '0:a?', '-f', 'null', '-') (Get-Duration $src)
    if ($script:cancelled) { return 1 }
    if ($code -eq 0 -and $script:ffErrorCount -eq 0) { Write-Host '  Ошибок не найдено — файл целый' -ForegroundColor Green; return 0 }
    Write-Host "  Найдено ошибок: $($script:ffErrorCount) — файл повреждён (местами может не воспроизводиться)" -ForegroundColor Red
    return 1
}

# Короткое превью: 6 фрагментов по 2 секунды, равномерно по всему видео
function Get-TeaserFilter([double]$dur) {
    $parts = @()
    for ($k = 0; $k -lt 6; $k++) {
        $t = $dur * (0.08 + 0.84 * $k / 5) - 1
        $parts += "between(t,$(Format-Num $t),$(Format-Num ($t + 2)))"
    }
    return ($parts -join '+')
}

# ---------- Ужать под лимит (Discord, Catbox, свой размер) ----------
# Value = «цель:режим:кодек», например discord20:auto:h264.
#   цель   — discord20 | discord10 | catbox | custom (спросить) | число мегабайт
#   режим  — auto (баланс) | smooth (держать 60 fps) | sharp (30 fps, выше разрешение)
#   кодек  — h264 | h265; процессор или видеокарта — по настройке Encoder
$fitTargets = @{ 'discord20' = @(20, 'Discord 20 МБ'); 'discord10' = @(10, 'Discord 10 МБ'); 'catbox' = @(200, 'Catbox 200 МБ') }
# Сколько бит нужно на пиксель кадра, чтобы картинка выглядела прилично (H.265 экономнее)
$fitBpp = @{ 'h264' = 0.05; 'h265' = 0.035 }
# Ступени: короткая сторона кадра и частота кадров
$fitLadder = @(@(2160, 60), @(2160, 30), @(1440, 60), @(1440, 30), @(1080, 60), @(1080, 30), @(720, 60), @(720, 30),
               @(540, 60), @(540, 30), @(480, 60), @(480, 30), @(360, 60), @(360, 30), @(240, 30))

$fitMB = 0.0
$fitLabel = ''
if ($Preset -eq 'fit') {
    $fitTarget, $fitMode, $fitCodec = $Value.Split(':')
    if ($fitTargets.ContainsKey($fitTarget)) { $fitMB = $fitTargets[$fitTarget][0]; $fitLabel = $fitTargets[$fitTarget][1] }
    elseif ($fitTarget -ne 'custom') { $fitMB = [double]::Parse($fitTarget, $inv); $fitLabel = "до $fitTarget МБ" }
    else {
        while ($true) {
            $answer = (Read-Host 'Сколько мегабайт должен весить результат (например 25 или 49.5)').Trim().Replace(',', '.')
            $mb = 0.0
            if ([double]::TryParse($answer, [Globalization.NumberStyles]::Float, $inv, [ref]$mb) -and $mb -ge 1) { break }
            Write-Host '  Нужно число от 1 и больше' -ForegroundColor Red
        }
        $fitMB = $mb
        $fitLabel = "до $(Format-Num $mb) МБ"
    }
}

# Частота кадров исходника: «60000/1001» -> 59.94
function Get-Fps([string]$path) {
    $r = "$(& $FFprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of csv=p=0 $path 2>$null)".Trim()
    $a, $b = $r.Split('/')
    $x = 0.0; $y = 1.0
    if ([double]::TryParse($a, [Globalization.NumberStyles]::Float, $inv, [ref]$x) -and $b -and [double]::TryParse($b, [Globalization.NumberStyles]::Float, $inv, [ref]$y) -and $x -gt 0 -and $y -gt 0) { return $x / $y }
    return 30.0
}

# Выбор разрешения и частоты: самая качественная ступень, которой хватает битрейта
function Get-FitPlan([int]$w, [int]$h, [double]$fps, [double]$vKbps, [string]$mode, [double]$bppNeed) {
    $short = [math]::Min($w, $h)
    $aspect = [math]::Max($w, $h) / [math]::Max(1, $short)
    $seen = @{}
    $rungs = @()
    foreach ($r in $fitLadder) {
        $s = [math]::Min($r[0], $short)
        $f = [math]::Min($r[1], $fps)
        if ($mode -eq 'sharp' -and $r[1] -gt 30) { continue }
        $k = "$s/$([math]::Round($f, 2))"
        if ($seen.ContainsKey($k)) { continue }
        $seen[$k] = $true
        $rate = $s * $s * $aspect * $f
        $rungs += [pscustomobject]@{ Short = $s; Fps = $f; Rate = $rate; Bpp = $vKbps * 1000 / $rate; High = ($r[1] -gt 30) }
    }
    if ($mode -eq 'smooth') { $rungs = @($rungs | Sort-Object @{ e = { $_.High }; Descending = $true }, @{ e = { $_.Rate }; Descending = $true }) }
    else { $rungs = @($rungs | Sort-Object Rate -Descending) }
    foreach ($r in $rungs) { if ($r.Bpp -ge $bppNeed) { return $r } }
    return ($rungs | Sort-Object Rate | Select-Object -First 1)
}

# Размер файла в тех же мегабайтах, что и лимиты (1 МБ = 1 000 000 байт), с одним знаком
function Format-MB([double]$bytes) { return ($bytes / 1000000).ToString('0.0', $inv) + ' МБ' }

function Remove-PassLogs {
    Remove-Item -Path (Join-Path $env:TEMP "ffmpeg-2pass-$PID*") -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $env:TEMP "ffmpeg-x265-$PID*") -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $env:TEMP "ffmpeg-vidstab-$PID*") -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $env:TEMP "ffmpeg-sub-$PID*") -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $env:TEMP "ffmpeg-cover-$PID*") -ErrorAction SilentlyContinue
}

# Возвращает 0 — успех, 'skip' — файл уже меньше лимита, иначе код ошибки
function Invoke-Fit([string]$src, [string]$out) {
    $limit = $fitMB * 1000000
    $dur = Get-Duration $src
    $info = Get-StreamInfo $src
    $srcSize = (Get-Item -LiteralPath $src).Length
    if ($srcSize -le $limit -and $src.ToLower().EndsWith('.mp4') -and $info.VCodec -eq 'h264') {
        Write-Host "  Файл уже весит $(Format-MB $srcSize) — это меньше лимита, сжимать не нужно" -ForegroundColor Green
        return 'skip'
    }
    $fps = Get-Fps $src
    $totalKbps = $limit * 0.97 * 8 / 1000 / $dur
    $aKbps = 0
    if ($info.ACodec) {
        if ($totalKbps -ge 4000) { $aKbps = 192 } elseif ($totalKbps -ge 1500) { $aKbps = 160 } elseif ($totalKbps -ge 600) { $aKbps = 128 } elseif ($totalKbps -ge 300) { $aKbps = 96 } else { $aKbps = 64 }
    }
    $vKbps = [math]::Floor($totalKbps - $aKbps)
    if ($vKbps -lt 40) {
        Write-Host "  Видео слишком длинное ($(Format-Time ([math]::Floor($dur)))): даже в минимальном качестве не влезет в $(Format-Num $fitMB) МБ. Сначала обрежь его." -ForegroundColor Red
        return 1
    }
    $need = $fitBpp[$fitCodec]
    $fitGpu = Use-Gpu $fitCodec
    if ($fitGpu) { $need *= 1.2 }   # кодировщик видеокарты чуть менее экономен, чем x264/x265 в 2 прохода
    $plan = Get-FitPlan $info.W $info.H $fps $vKbps $fitMode $need

    $vf = "scale=-2:$($plan.Short)"
    if ($info.W -lt $info.H) { $vf = "scale=$($plan.Short):-2" }
    if ($plan.Fps -lt $fps - 0.5) { $vf += ",fps=$(Format-Num $plan.Fps)" }
    $codecName = 'H.264'
    if ($fitCodec -eq 'h265') { $codecName = 'H.265' }
    $how = '2 прохода, процессор'
    if ($fitGpu) { $how = 'видеокарта' }
    Write-Host ("  Длина {0} · лимит {1} МБ  ->  {2}p {3} fps · видео {4} кбит/с · звук {5} кбит/с · {6} ({7})" -f (Format-Time ([math]::Floor($dur))), (Format-Num $fitMB), $plan.Short, [math]::Round($plan.Fps), $vKbps, $aKbps, $codecName, $how) -ForegroundColor DarkGray
    if ($plan.Bpp -lt $need / 2) { Write-Host '  Видео длинное для такого лимита — качество будет низким. Если важна картинка, лучше обрезать.' -ForegroundColor Yellow }

    $preset = 'medium'
    if ($fitMB -le 50) { $preset = 'slow' }   # мелкие лимиты — короткие ролики, можно потратить время на качество
    $audio = @('-an')
    if ($aKbps -gt 0) { $audio = @('-c:a', 'aac', '-b:a', "${aKbps}k", '-ac', '2') }
    $common = @('-map', "0:$(Get-MainVideoIndex $src)", '-map', '0:a:0?', '-sn', '-dn', '-vf', $vf)

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $passes = @()
        if ($fitGpu) {
            $v = Get-GpuArgs $fitCodec -Kbps $vKbps
            $passes += , @(@('-y', '-i', $src) + $common + $v + $audio + @('-movflags', '+faststart', $out))
        } elseif ($fitCodec -eq 'h265') {
            # x265 пишет статистику по относительному пути (в пути с «C:» двоеточие ломает параметры)
            $stats = "ffmpeg-x265-$PID.log"
            $v = @('-c:v', 'libx265', '-preset', $preset, '-b:v', "${vKbps}k", '-tag:v', 'hvc1', '-pix_fmt', 'yuv420p')
            $passes += , @(@('-y', '-i', $src) + $common + $v + @('-x265-params', "pass=1:stats=${stats}:log-level=error", '-an', '-f', 'null', '-'))
            $passes += , @(@('-y', '-i', $src) + $common + $v + @('-x265-params', "pass=2:stats=${stats}:log-level=error") + $audio + @('-movflags', '+faststart', $out))
        } else {
            $log = Join-Path $env:TEMP "ffmpeg-2pass-$PID"
            $v = @('-c:v', 'libx264', '-preset', $preset, '-b:v', "${vKbps}k", '-pix_fmt', 'yuv420p', '-passlogfile', $log)
            $passes += , @(@('-y', '-i', $src) + $common + $v + @('-pass', '1', '-an', '-f', 'null', '-'))
            $passes += , @(@('-y', '-i', $src) + $common + $v + @('-pass', '2') + $audio + @('-movflags', '+faststart', $out))
        }

        $code = 0
        $oldDir = [Environment]::CurrentDirectory
        [Environment]::CurrentDirectory = $env:TEMP
        try {
            for ($p = 0; $p -lt $passes.Count -and $code -eq 0; $p++) {
                if ($passes.Count -gt 1) {
                    $what = 'анализ'
                    if ($p -eq 1) { $what = 'кодирование' }
                    Write-Host "  Проход $($p + 1) из $($passes.Count) ($what)" -ForegroundColor DarkGray
                }
                $code = Invoke-FFmpeg $passes[$p] $dur
            }
        } finally {
            [Environment]::CurrentDirectory = $oldDir
            Remove-PassLogs
        }
        if ($code -ne 0 -or $script:cancelled) { return $code }

        $size = (Get-Item -LiteralPath $out).Length
        if ($size -le $limit * 0.985) {
            Write-Host "  Итог: $(Format-MB $size) из $(Format-Num $fitMB) МБ" -ForegroundColor Green
            return 0
        }
        # Не влезло (бывает на очень «тяжёлых» сценах) — снижаем битрейт пропорционально и пробуем снова
        $newKbps = [math]::Floor($vKbps * ($limit * 0.95 / $size))
        $why = 'больше лимита'
        if ($size -le $limit) { $why = 'впритык к лимиту, а нужен небольшой запас' }
        Write-Host "  Получилось $(Format-MB $size) — $why. Пересжимаю с битрейтом $newKbps кбит/с (попытка $($attempt + 1) из 3)" -ForegroundColor Yellow
        $vKbps = [math]::Max(30, $newKbps)
    }
    Write-Host "  Не удалось уложиться в $(Format-Num $fitMB) МБ за 3 попытки" -ForegroundColor Red
    return 1
}

# Число из ответа пользователя (или из -Value); спрашивает, пока не введут правильно
function Read-Number([string]$label, [double]$min, [double]$max) {
    while ($true) {
        $answer = (Read-Host $label).Trim().Replace(',', '.')
        $x = 0.0
        if ([double]::TryParse($answer, [Globalization.NumberStyles]::Float, $inv, [ref]$x) -and $x -ge $min -and $x -le $max) { return $x }
        Write-Host "  Нужно число от $(Format-Num $min) до $(Format-Num $max)" -ForegroundColor Red
    }
}
function Get-NumberSetting([string]$label, [double]$min, [double]$max) {
    $x = 0.0
    if ($Value -and [double]::TryParse($Value, [Globalization.NumberStyles]::Float, $inv, [ref]$x)) { return $x }
    return Read-Number $label $min $max
}

$splitMin = 0.0
$framesSec = 0.0
if ($Preset -eq 'split') { $splitMin = Get-NumberSetting 'По сколько минут резать (например 10)' 0.1 10000 }
if ($Preset -eq 'frames') { $framesSec = Get-NumberSetting 'Раз в сколько секунд сохранять кадр (например 10)' 0.04 100000 }

# Видео + музыка: два выделенных файла — заменить звук или подмешать музыку фоном (она зацикливается)
if ($Preset -eq 'addaudio') {
    $vid = $Files | Where-Object { $videoExt -contains [IO.Path]::GetExtension($_).TrimStart('.').ToLower() } | Select-Object -First 1
    $aud = $Files | Where-Object { $audioExt -contains [IO.Path]::GetExtension($_).TrimStart('.').ToLower() } | Select-Object -First 1
    if ($Files.Count -ne 2 -or -not $vid -or -not $aud) {
        Write-Host 'Выдели ровно два файла: одно видео и один файл с музыкой или звуком.' -ForegroundColor Red
        Finish 0 1 @($Files)
        return
    }
    $info = Get-StreamInfo $vid
    $dur = Get-Duration $vid
    $ext = 'mkv'
    if ($info.VCodec -in @('h264', 'hevc', 'av1', 'vp9')) { $ext = 'mp4' }
    $suffix = '(новый звук)'
    $audioMap = @('-map', '1:a:0')
    if ($Value -eq 'mix' -and $info.ACodec) {
        $suffix = '(с музыкой)'
        $audioMap = @('-filter_complex', '[1:a]volume=0.35[m];[0:a][m]amix=inputs=2:duration=first:dropout_transition=0:normalize=0[a]', '-map', '[a]')
    }
    $vdir = [IO.Path]::GetDirectoryName($vid)
    $out = Get-FreePath (Get-OutDir $vdir) "$([IO.Path]::GetFileNameWithoutExtension($vid)) $suffix" $ext
    Write-Host ''
    Write-Host "$([IO.Path]::GetFileName($vid)) + $([IO.Path]::GetFileName($aud))  ->  $([IO.Path]::GetFileName($out))" -ForegroundColor White
    if ($Value -eq 'mix' -and -not $info.ACodec) { Write-Host '  В видео нет своего звука — просто ставлю музыку' -ForegroundColor DarkGray }
    $code = Invoke-FFmpeg (@('-n', '-i', $vid, '-stream_loop', '-1', '-i', $aud, '-map', '0:v:0') + $audioMap + @('-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-t', (Format-Num $dur), '-movflags', '+faststart', $out)) $dur
    if ($script:cancelled -or $code -ne 0 -or -not (Test-Path -LiteralPath $out)) {
        Start-Sleep -Milliseconds 300
        Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue
        if (-not $script:cancelled) { Write-Host 'Ошибка — исходники не тронуты' -ForegroundColor Red }
        Finish 0 1 @($vid)
    } else { $script:lastOutput = $out; Finish 1 1 @() }
    return
}

# Слайд-шоу: выбранные картинки по алфавиту в MP4 1920×1080, каждая показывается N секунд
# Коллаж: выбранные картинки по алфавиту в одну — в ряд (одинаковая высота) или в столбик (одинаковая ширина)
if ($Preset -eq 'collage') {
    $sorted = @($Files | Sort-Object)
    if ($sorted.Count -lt 2) { Write-Host 'Выдели хотя бы две картинки' -ForegroundColor Red; Finish 0 1 @($Files); return }
    $sizes = @()
    foreach ($f in $sorted) {
        $wh = "$(& $FFprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 $f 2>$null)".Trim().Split(',')
        $sizes += , @([int]$wh[0], [int]$wh[1])
    }
    $inputs = @(); $chain = ''; $labels = ''
    if ($Value -eq 'v') { $w = ($sizes | ForEach-Object { $_[0] } | Measure-Object -Minimum).Minimum; $fit = "scale=$([int]$w):-2" ; $stack = 'vstack' }
    else { $h = ($sizes | ForEach-Object { $_[1] } | Measure-Object -Minimum).Minimum; $fit = "scale=-2:$([int]$h)"; $stack = 'hstack' }
    for ($i = 0; $i -lt $sorted.Count; $i++) {
        $inputs += @('-i', $sorted[$i])
        $chain += "[$($i):v]$fit,setsar=1,format=rgba[v$i];"
        $labels += "[v$i]"
    }
    $allJpg = -not ($sorted | Where-Object { @('.jpg', '.jpeg') -notcontains [IO.Path]::GetExtension($_).ToLower() })
    $ext = $(if ($allJpg) { 'jpg' } else { 'png' })
    $graph = "$chain$($labels)$($stack)=inputs=$($sorted.Count)"
    if ($allJpg) { $graph += ',format=yuvj444p' }
    $first = $sorted[0]
    $label = $(if ($Value -eq 'v') { 'коллаж в столбик' } else { 'коллаж в ряд' })
    $out = Get-FreePath (Get-OutDir ([IO.Path]::GetDirectoryName($first))) "$([IO.Path]::GetFileNameWithoutExtension($first)) ($label)" $ext
    Write-Host ''
    Write-Host "Коллаж из $($sorted.Count) картинок  ->  $([IO.Path]::GetFileName($out))" -ForegroundColor White
    $a = @('-hide_banner', '-v', 'error', '-nostdin', '-n') + $inputs + @('-filter_complex', $graph, '-frames:v', '1', '-update', '1')
    if ($allJpg) { $a += @('-q:v', '2') }
    & $FFmpeg @a $out
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $out)) {
        Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue
        Write-Host 'Ошибка — исходники не тронуты' -ForegroundColor Red
        Finish 0 1 @($first)
    } else { $script:lastOutput = $out; Finish 1 1 @() }
    return
}

if ($Preset -eq 'slideshow') {
    $sec = Get-NumberSetting 'Сколько секунд показывать каждую картинку (например 3)' 0.1 3600
    $sorted = @($Files | Sort-Object)
    $first = $sorted[0]
    $out = Get-FreePath (Get-OutDir ([IO.Path]::GetDirectoryName($first))) "$([IO.Path]::GetFileNameWithoutExtension($first)) (слайд-шоу)" 'mp4'
    $list = Join-Path $env:TEMP "ffmpeg-slides-$PID.txt"
    $bs = [string][char]92
    $lines = @()
    foreach ($f in $sorted) {
        $lines += "file '" + ($f.Replace($bs, '/').Replace("'", "'" + $bs + "''")) + "'"
        $lines += "duration $(Format-Num $sec)"
    }
    # последнюю картинку concat требует повторить, иначе её длительность не учтётся
    $lines += "file '" + ($sorted[-1].Replace($bs, '/').Replace("'", "'" + $bs + "''")) + "'"
    [IO.File]::WriteAllLines($list, [string[]]$lines, (New-Object Text.UTF8Encoding $false))
    Write-Host ''
    Write-Host "Слайд-шоу из $($sorted.Count) картинок по $(Format-Num $sec) с  ->  $([IO.Path]::GetFileName($out))" -ForegroundColor White
    $vf = 'scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1,fps=30,format=yuv420p'
    $code = Invoke-FFmpeg (@('-n', '-f', 'concat', '-safe', '0', '-i', $list, '-vf', $vf) + (Get-VideoArgs 20) + @('-movflags', '+faststart', $out)) ($sorted.Count * $sec)
    Remove-Item -LiteralPath $list -ErrorAction SilentlyContinue
    if ($script:cancelled -or $code -ne 0 -or -not (Test-Path -LiteralPath $out)) {
        Start-Sleep -Milliseconds 300
        Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue
        if (-not $script:cancelled) { Write-Host 'Ошибка — исходники не тронуты' -ForegroundColor Red }
        Finish 0 1 @($first)
    } else { $script:lastOutput = $out; Finish 1 1 @() }
    return
}

# Склейка: все выбранные файлы по алфавиту в один, без перекодирования
if ($Preset -eq 'concat') {
    $sorted = @($Files | Sort-Object)
    $first = $sorted[0]
    $ext = [IO.Path]::GetExtension($first).TrimStart('.').ToLower()
    $out = Get-FreePath (Get-OutDir ([IO.Path]::GetDirectoryName($first))) "$([IO.Path]::GetFileNameWithoutExtension($first)) (склеено)" $ext
    $list = Join-Path $env:TEMP "ffmpeg-concat-$PID.txt"
    $bs = [string][char]92
    # В списке ffmpeg путь в одинарных кавычках; апостроф внутри пишется как '\''
    $lines = $sorted | ForEach-Object { "file '" + ($_.Replace($bs, '/').Replace("'", "'" + $bs + "''")) + "'" }
    [IO.File]::WriteAllLines($list, [string[]]$lines, (New-Object Text.UTF8Encoding $false))
    Write-Host ''
    Write-Host "Склеиваю $($sorted.Count) файлов  ->  $([IO.Path]::GetFileName($out))" -ForegroundColor White
    $sorted | ForEach-Object { Write-Host "  $([IO.Path]::GetFileName($_))" }
    $total = 0.0
    foreach ($f in $sorted) { try { $total += Get-Duration $f } catch { } }
    $code = Invoke-FFmpeg @('-n', '-f', 'concat', '-safe', '0', '-i', $list, '-map', '0', '-c', 'copy', $out) $total
    Remove-Item -LiteralPath $list -ErrorAction SilentlyContinue
    if ($script:cancelled) {
        Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue
        Write-Host 'Недоделанный файл удалён, исходники не тронуты.' -ForegroundColor Yellow
        Finish 0 1 @()
        return
    }
    if ($code -ne 0 -or -not (Test-Path -LiteralPath $out)) {
        Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue
        Write-Host 'Ошибка: видимо, у файлов разные параметры (кодек, разрешение, частота). Их надо сначала привести к одному формату.' -ForegroundColor Red
        Finish 0 1 @($first)
    } else { $script:lastOutput = $out; Finish 1 1 @() }
    return
}

$n = $Files.Count
$ok = 0
$failed = @()
$i = 0
foreach ($src in $Files) {
    $i++
    $dir = [IO.Path]::GetDirectoryName($src)
    $base = [IO.Path]::GetFileNameWithoutExtension($src)
    $srcExt = [IO.Path]::GetExtension($src).TrimStart('.').ToLower()
    try { $job = Get-Job $src $srcExt }
    catch {
        Write-Host ''
        Write-Host "[$i/$n] $base.$srcExt — $($_.Exception.Message)" -ForegroundColor Red
        $failed += $src
        continue
    }
    $ext = $job.Ext
    if (-not $ext) { $ext = $srcExt }

    $replace = $replaceMode -and $job.Replace
    if ($replace) {
        $final = Join-Path $dir "$base.$ext"
        if ((Test-Path -LiteralPath $final) -and ($final -ne $src)) {
            Write-Host ''
            Write-Host "[$i/$n] $base.$srcExt — пропущено: рядом уже есть $base.$ext" -ForegroundColor Yellow
            $failed += $src
            continue
        }
        $out = Join-Path $dir "$base.ffmpeg-tmp.$ext"
        Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue
    } else {
        $name = $base
        if ($job.Suffix) { $name = "$base $($job.Suffix)" }
        $out = Get-FreePath (Get-OutDir $dir) $name $ext
        $final = $out
    }

    Write-Host ''
    $label = [IO.Path]::GetFileName($final)
    if ($job.OutLabel) { $label = $job.OutLabel }
    Write-Host "[$i/$n] $base.$srcExt  ->  $label" -ForegroundColor White
    if ($job.Note) { Write-Host "  $($job.Note)" -ForegroundColor DarkGray }
    $code = 0
    if (-not $job.Custom -and $videoExt -contains $srcExt) { $job = Add-EvenSize (Add-StreamMaps $job $src) }
    if ($job.Custom) {
        switch ($job.Custom) {
            'fit'    { $r = Invoke-Fit $src $out }
            'subsx'  { $r = Invoke-SubsExtract $src }
            'audiox' { $r = Invoke-AudioExtract $src }
            'split'  { $r = Invoke-Split $src }
            'frames' { $r = Invoke-Frames $src }
            'check'  { $r = Invoke-Check $src }
        }
        if ("$r" -eq 'skip') { $ok++; continue }
        if ($job.Custom -ne 'fit') {
            # эти операции сами создают (и при отмене убирают) свои файлы
            if ($script:cancelled) {
                Write-Host 'Отменено, недоделанные файлы удалены, исходник не тронут.' -ForegroundColor Yellow
                break
            }
            if ("$r" -eq '0') { $ok++ } else { $failed += $src }
            continue
        }
        $code = [int]$r
    } elseif ($noProgress -contains $Preset) {
        & $FFmpeg -hide_banner -v error -nostdin -n @($job.InArgs) -i $src @($job.Args) $out
        $code = $LASTEXITCODE
    } else {
        if ($Preset -ne 'pickaudio' -and (Test-KeepsAllAudio $job.Args)) { $job.Args = @($job.Args) + @(Get-TrackNameArgs $src) }
        $total = Get-OutputDuration $src
        if ($job.Pass1) {
            Write-Host '  Проход 1 из 2 (анализ)' -ForegroundColor DarkGray
            $code = Invoke-FFmpeg (@('-y') + @($job.InArgs) + @('-i', $src) + @($job.Pass1) + @('-')) $total
            if ($code -eq 0) { Write-Host '  Проход 2 из 2 (кодирование)' -ForegroundColor DarkGray }
        }
        if ($code -eq 0) {
            $code = Invoke-FFmpeg (@('-n') + @($job.InArgs) + @('-i', $src) + @($job.Args) + @($out)) $total
        }
    }
    Remove-PassLogs
    if ($script:cancelled) {
        Start-Sleep -Milliseconds 300   # дать ffmpeg отпустить файл
        Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue
        Write-Host 'Недоделанный файл удалён, исходник не тронут.' -ForegroundColor Yellow
        if ($i -lt $n) { Write-Host "Остальные файлы ($($n - $i)) не обрабатывались." -ForegroundColor Yellow }
        break
    }
    if ($code -ne 0 -or -not (Test-Path -LiteralPath $out)) {
        Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue
        Write-Host 'Ошибка — исходник не тронут' -ForegroundColor Red
        $failed += $src
        continue
    }
    if ($replace) {
        try { Send-ToRecycleBin $src }
        catch {
            # Исходник занят (например, открыт в плеере) — результат остаётся под временным именем
            Write-Host "Не удалось убрать исходник в Корзину, результат сохранён как $([IO.Path]::GetFileName($out))" -ForegroundColor Red
            $failed += $src
            continue
        }
        Rename-Item -LiteralPath $out -NewName "$base.$ext"
        $final = Join-Path $dir "$base.$ext"
    }
    $script:lastOutput = $final
    $ok++
}

Finish $ok $n $failed
