# Runs ffmpeg for the FFmpeg menu items in Nilesoft Shell (imports/ffmpeg.nss).
#
# Settings live in the registry (menu items toggle them):
#   Mode    = copy | replace — copy next to the source / replace (the source goes to the Recycle Bin)
#   OutDir  = here | sub     — copies go next to the source or into the ‹FFmpeg› subfolder
#   Encoder = cpu  | gpu     — video is encoded by the CPU (x264) or the graphics card (NVIDIA, AMD or Intel)
#   GpuEnc  = nvenc | amf | qsv | none — which graphics card encoder works (detected automatically)
#   Window  = auto | wait    — close the window after success or always wait for Enter
# The source is touched only after a successful run. Operations that make something new
# from a file (GIF, audio, frames, 9:16, joining) always create a new file.
#
# Example: powershell -File ffmpeg-run.ps1 -FFmpeg <path to ffmpeg.exe> -Preset louder -Value 6 <files...>

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
$script:cancelled = $false   # Esc / Q / Ctrl+C was pressed
$script:pickedTracks = $null   # track numbers for ‹Pick audio tracks› - asked once
$Host.UI.RawUI.WindowTitle = "FFmpeg: $Preset $Value"
[Console]::OutputEncoding = [Text.Encoding]::UTF8   # ffmpeg writes file names in UTF-8

$FFprobe = Join-Path (Split-Path $FFmpeg) 'ffprobe.exe'
# Working folder is TEMP: temporary filter files (stabilization, subtitles) use relative paths,
# because the colon in ‹C:› breaks filter options
# Set-Location is required: PowerShell starts programs from its own location, not from CurrentDirectory
Set-Location -LiteralPath $env:TEMP
[Environment]::CurrentDirectory = $env:TEMP
$inv = [Globalization.CultureInfo]::InvariantCulture
function Format-Num([double]$x) { return $x.ToString('0.######', $inv) }

# File duration in seconds (via ffprobe)
function Get-Duration([string]$path) {
    $s = & $FFprobe -v error -show_entries format=duration -of csv=p=0 $path 2>$null
    $d = 0.0
    if (-not [double]::TryParse("$s".Trim(), [Globalization.NumberStyles]::Float, $inv, [ref]$d)) { throw "Could not get the duration: $path" }
    return $d
}

# What is inside the file: video codec, pixel format and size, codec of the first audio track
function Get-StreamInfo([string]$path) {
    $info = @{ VCodec = ''; PixFmt = ''; W = 0; H = 0; ACodec = '' }
    foreach ($l in (& $FFprobe -v error -select_streams v:0 -show_entries stream=codec_name,pix_fmt,width,height -of default=nw=1 $path 2>$null)) {
        $k, $val = "$l".Split('=', 2)
        switch ($k) { 'codec_name' { $info.VCodec = $val } 'pix_fmt' { $info.PixFmt = $val } 'width' { $info.W = [int]$val } 'height' { $info.H = [int]$val } }
    }
    $info.ACodec = "$(& $FFprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 $path 2>$null)".Trim()
    return $info
}

# ---------- Graphics card ----------
# Graphics card encoder: nvenc (NVIDIA), amf (AMD), qsv (Intel, including integrated graphics).
# Checked by encoding half a second of a test picture and remembered in the registry
# together with the ffmpeg path. ‹Settings > Check graphics card› checks again.
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
# ‹On the graphics card› items without a suitable card: a clear message instead of an ffmpeg error
function Assert-Gpu([string]$codec) {
    $g = Get-Gpu
    if (-not $g.Vendor) { throw 'No graphics card that can encode video was found. Choose the ‹on the CPU› option.' }
    if ($codec -eq 'h265' -and -not $g.Hevc) { throw "$($gpuNames[$g.Vendor]) cannot encode H.265 on this graphics card. Choose H.264 or the CPU." }
}

# Graphics card encoder arguments. -Quality is on the NVENC CQ scale (lower = better),
# -Kbps — target bitrate (for ‹Fit into a size limit›), -Best = slowest, highest quality settings
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
            $pix = 'nv12'   # Quick Sync accepts only nv12
        }
    }
    if ($codec -eq 'h265') { $a += @('-tag:v', 'hvc1') }
    return $a + @('-pix_fmt', $pix)
}
# The graphics card is enabled in the settings and found. H.265 also needs support for it, otherwise the CPU is used
function Use-Gpu([string]$codec = 'h264') {
    if ($cfg.Encoder -ne 'gpu') { return $false }
    $g = Get-Gpu
    return ([bool]$g.Vendor -and ($codec -ne 'h265' -or $g.Hevc))
}

# ‹Visually lossless› re-encoding: the difference from the original is invisible, the file is bigger than usual.
# The size is made even - H.264 in yuv420p cannot be encoded otherwise
$evenSize = 'scale=trunc(iw/2)*2:trunc(ih/2)*2'
$hqVideo = @{
    'h264'    = @('-vf', $evenSize, '-c:v', 'libx264', '-preset', 'slow', '-crf', '17', '-profile:v', 'high', '-pix_fmt', 'yuv420p')
    'h265'    = @('-vf', $evenSize, '-c:v', 'libx265', '-preset', 'slow', '-crf', '18', '-tag:v', 'hvc1', '-pix_fmt', 'yuv420p')
}
$hqName = @{ 'h264' = 'H.264'; 'h264gpu' = 'H.264 GPU'; 'h265' = 'H.265'; 'h265gpu' = 'H.265 GPU' }

# MP4 without quality loss. auto: H.264 video is copied as is, only incompatible streams are re-encoded
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
        $notes += 'video is already H.264 - copied without re-encoding'
    } elseif ($kind -like '*gpu') {
        $codec = $kind.Substring(0, 4)
        Assert-Gpu $codec
        $v = @('-vf', $evenSize) + (Get-GpuArgs $codec -Quality $(if ($codec -eq 'h265') { 21 } else { 19 }) -Best)
        $notes += "video: $($info.VCodec) -> $($hqName[$kind]) ($($gpuNames[(Get-Gpu).Vendor])), visually lossless"
    } else {
        $v = $hqVideo[$kind]
        $notes += "video: $($info.VCodec) -> $($hqName[$kind]), visually lossless"
    }
    if ($info.ACodec -eq 'aac') { $a = @('-c:a', 'copy'); $notes += 'AAC audio is copied' }
    elseif ($info.ACodec) { $a = @('-c:a', 'aac', '-b:a', '256k'); $notes += "audio: $($info.ACodec) -> AAC 256 kbps" }
    else { $a = @() }
    $j.Args = @('-map', "0:$(Get-MainVideoIndex $src)", '-map', '0:a?') + $v + $a + @('-movflags', '+faststart')
    $j.Ext = 'mp4'
    $j.Note = $notes -join ' · '
    return $j
}

# Video encoding: quality on the x264 CRF scale (lower = better)
function Get-VideoArgs([int]$crf, [string]$speed = 'medium') {
    if (Use-Gpu) { return Get-GpuArgs 'h264' -Quality ($crf + 3) }
    return @('-c:v', 'libx264', '-preset', $speed, '-crf', "$crf", '-pix_fmt', 'yuv420p')
}
$mp4Audio = @('-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart')

# Audio codec for the file extension: so the format stays the same when audio is processed
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

# Arguments for audio changes: video picture is copied, music keeps its cover
# -Src: for a video with several audio tracks asks which ones to change; the others are copied as is.
# -Extra — audio encoding options (for example -ar 48000). For the result name: $script:soundNote (‹, tracks 1, 3›)
function Get-SoundJobArgs([string]$ext, [string[]]$filter, [string]$Src = '', [string[]]$Extra = @()) {
    $script:soundNote = ''
    if ($videoExt -contains $ext) {
        $tracks = @()
        if ($Src) {
            $tracks = @(Get-Streams $Src 'a')
            if ($tracks.Count -eq 0) { throw 'The video has no audio - nothing to change' }
        }
        if ($tracks.Count -gt 1) {
            $keep = @(Request-Tracks $Src $tracks 'Only the picked tracks change, the others stay as they are. You can type ‹1 3› or ‹2-4›, Enter = all.' 'Which tracks to change (numbers)')
            foreach ($k in $keep) { if ($k -gt $tracks.Count) { throw "There is no track number $k" } }
            if ($keep.Count -lt $tracks.Count) {
                $a = @('-map', '0', '-c', 'copy')
                foreach ($k in $keep) {
                    $i = $k - 1
                    # audio options for this track only: -c:a -> -c:a:N, -ar -> -ar:a:N
                    $opts = @(Get-AudioArgs $ext) + $Extra
                    for ($o = 0; $o -lt $opts.Count - 1; $o += 2) {
                        $name = $opts[$o]
                        if ($name -like '*:a') { $name += ":$i" } else { $name += ":a:$i" }
                        $a += @($name, $opts[$o + 1])
                    }
                    $a += @("-filter:a:$i", ($filter -join ','))
                }
                if ($keep.Count -eq 1) { $script:soundNote = ", track $($keep[0])" } else { $script:soundNote = ", tracks $($keep -join ', ')" }
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

# Quality settings for images
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
$rotateName = @{ 'right' = 'rotated right'; 'left' = 'rotated left'; '180' = 'rotated 180'; 'hflip' = 'flipped horizontally'; 'vflip' = 'flipped vertically' }

$gif = @{
    '1' = @('small', 'fps=10,scale=320:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=64:stats_mode=diff[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3')
    '2' = @('medium', 'fps=12,scale=400:-1:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=full[p];[s1][p]paletteuse=dither=bayer:bayer_scale=4')
    '3' = @('high quality', 'fps=15,scale=480:-1:flags=lanczos,split[s0][s1];[s0]palettegen=stats_mode=full:reserve_transparent=0[p];[s1][p]paletteuse=dither=floyd_steinberg')
}

# Audio to a separate file: format -> (extension, arguments)
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

# 9:16 for Shorts/TikTok: the video centered over a blurred, stretched copy
$vertical = '[0:v]split=2[bg][fg];[bg]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=20:2[b];[fg]scale=1080:1920:force_original_aspect_ratio=decrease[f];[b][f]overlay=(W-w)/2:(H-h)/2,setsar=1[v]'

# 1:1 for Instagram and avatars: the video centered over a blurred copy
$square = $vertical.Replace('1080:1920', '1080:1080')

# Sample rate of the first audio track (for effects that change the pitch)
function Get-SampleRate([string]$src) {
    $sr = 0
    $s = @(Get-Streams $src 'a') | Select-Object -First 1
    if ($s -and "$($s.sample_rate)" -match '^[0-9]+$') { $sr = [int]$s.sample_rate }
    if ($sr -le 0) { $sr = 44100 }
    return $sr
}

$silence = 'silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.1,areverse,silenceremove=start_periods=1:start_threshold=-50dB:start_silence=0.1,areverse'

# ‹Settings > Check graphics card› and the installer: check again and show the result
if ($Preset -eq 'gpu-detect') {
    Write-Host 'Checking whether the graphics card can encode video...' -ForegroundColor Cyan
    $g = Find-GpuEncoder -Force
    if ($g.Vendor) {
        Write-Host ("Found: {0} (H.264{1})" -f $gpuNames[$g.Vendor], $(if ($g.Hevc) { ' and H.265' } else { '' })) -ForegroundColor Green
        if ($cfg.Encoder -ne 'gpu') { Write-Host 'To encode on it, turn on ‹Settings > Encode video on the graphics card›.' }
    } else {
        Write-Host 'No graphics card for encoding was found - the CPU will encode everything.' -ForegroundColor Yellow
        Write-Host 'If you do have a graphics card, update its driver and check again.'
    }
    if (-not $NoPause) { Write-Host ''; Read-Host 'Press Enter to close' | Out-Null }
    exit 0
}

$encName = 'CPU'
if ($cfg.Encoder -eq 'gpu') {
    if (Use-Gpu) { $encName = 'graphics card (' + $gpuNames[(Get-Gpu).Vendor] + ')' }
    else { $encName = 'CPU (no graphics card for encoding found)' }
}
if ($replaceMode) { Write-Host "Mode: replace (sources go to the Recycle Bin) · video: $encName" -ForegroundColor Yellow }
else { Write-Host "Mode: copy (sources stay untouched) · video: $encName" -ForegroundColor Cyan }
if (-not [Console]::IsOutputRedirected -and $Preset -notin @('image', 'ico', 'gray', 'upscale', 'downscale', 'irotate', 'frame', 'sheet', 'spectrum', 'web', 'squarecrop', 'collage')) {
    Write-Host 'Esc or Q = cancel' -ForegroundColor DarkGray
}

# Trim: the time is asked once for all files (or comes in -Value as ‹start~end›)

# ‹45›, ‹1:30›, ‹1:02:30›, ‹1:30.5› or ‹1:30,5› -> seconds; $null if written wrong
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

# Seconds -> ‹1:02:30.5› / ‹2:30›
function Format-Time([double]$s) {
    $t = [TimeSpan]::FromSeconds($s)
    $frac = ''
    if ($t.Milliseconds) { $frac = '.' + ([string]$t.Milliseconds).PadLeft(3, '0').TrimEnd('0') }
    if ($t.Hours -or $t.Days) { return ('{0}:{1:00}:{2:00}' -f [int][math]::Floor($t.TotalHours), $t.Minutes, $t.Seconds) + $frac }
    return ('{0}:{1:00}' -f $t.Minutes, $t.Seconds) + $frac
}

# Asks for a time until it is entered correctly. Empty = $null (from the start / to the end)
function Read-Time([string]$label, [double]$min, [double]$max, [bool]$maxAllowed) {
    while ($true) {
        $answer = Read-Host $label
        if (-not $answer.Trim()) { return $null }
        $s = ConvertTo-Seconds $answer
        if ($null -eq $s) { Write-Host '  Could not read the time. Write it like the examples: 45, 1:30 or 1:02:30' -ForegroundColor Red; continue }
        if ($s -le $min) { Write-Host "  Must be after $(Format-Time $min)" -ForegroundColor Red; continue }
        if ($s -gt $max -or ($s -eq $max -and -not $maxAllowed)) { Write-Host "  Must be before $(Format-Time $max) - that is the end of the file" -ForegroundColor Red; continue }
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
        if ($Preset -eq 'trim') { Write-Host 'Trimming without re-encoding: instant, but the start moves to the nearest keyframe (usually 1-5 seconds earlier).' }
        else { Write-Host 'Exact trimming: cuts exactly at the given time, the video is re-encoded.' }
        Write-Host ''
        $durText = "File length: $(Format-Time $dur)"
        if ($Files.Count -gt 1) { $durText += "  (of the first of $($Files.Count); the time applies to all)" }
        Write-Host $durText -ForegroundColor Cyan
        Write-Host ''
        Write-Host 'How to write the time:'
        Write-Host '  45        — 45th second'
        Write-Host '  1:30      — 1 minute 30 seconds'
        Write-Host '  1:02:30   — 1 hour 2 minutes 30 seconds'
        Write-Host '  1:30.5    — fractions of a second are fine'
        Write-Host '  (empty)   - just press Enter: from the very start / to the very end'
        Write-Host ''
        $trimStart = Read-Time 'Keep from' -1 $dur $false
        $from = 0.0
        if ($null -ne $trimStart) { $from = $trimStart }
        $trimEnd = Read-Time 'Keep until' $from $dur $true
        $to = $dur
        if ($null -ne $trimEnd) { $to = $trimEnd }
        if ($null -eq $trimStart -and $null -eq $trimEnd) {
            Write-Host 'Nothing entered - nothing to trim.' -ForegroundColor Yellow
            if (-not $NoPause) { Read-Host 'Press Enter to close' }
            return
        }
        Write-Host ''
        Write-Host "Keeping $(Format-Time $from) to $(Format-Time $to) (length $(Format-Time ($to - $from)))" -ForegroundColor Green
    }
    if ($null -ne $trimStart) { $trimIn += @('-ss', (Format-Num $trimStart)) }
    if ($null -ne $trimEnd) { $trimIn += @('-to', (Format-Num $trimEnd)) }
}

# Operation description: InArgs = before -i, Args = after; Ext = result extension (empty = same as
# the source); Suffix = name suffix in copy mode; Replace = whether the source may be replaced;
# Pass1 — first pass arguments (for compressing to a size)
function Get-Job([string]$src, [string]$srcExt) {
    $j = @{ InArgs = @(); Args = @(); Ext = ''; Suffix = ''; Replace = $true; Pass1 = $null; Note = ''; Custom = ''; OutLabel = '' }
    switch ($Preset) {
        'hq'       { $j = Get-HqJob $j $src }
        'lrotate' {
            # Rotation without re-encoding: only the rotation flag changes (MP4/MOV), the picture is untouched
            $delta = @{ 'right' = -90; 'left' = 90; '180' = 180 }[$Value]
            $rot = (Get-Rotation $src) + $delta
            while ($rot -gt 180) { $rot -= 360 }
            while ($rot -le -180) { $rot += 360 }
            $j.InArgs = @('-display_rotation', "$rot")
            $j.Args = @('-map', '0', '-c', 'copy')
            $j.Suffix = "($($rotateName[$Value]))"
        }
        'stab' {
            $trf = "ffmpeg-vidstab-$PID.trf"   # relative path: the working folder is TEMP
            $j.Pass1 = @('-vf', "vidstabdetect=shakiness=6:accuracy=15:result=$trf", '-an', '-f', 'null')
            $j.Args = @('-vf', "vidstabtransform=input=${trf}:smoothing=30:optzoom=1:interpol=bicubic,unsharp=5:5:0.6:3:3:0.3") + (Get-VideoArgs 18) + (Get-KeepAudioArgs $src)
            $j.Ext = 'mp4'; $j.Suffix = '(stabilized)'
        }
        'denoise'  { $j.Args = @('-vf', 'hqdn3d=4:3:6:4.5') + (Get-VideoArgs 18) + (Get-KeepAudioArgs $src); $j.Ext = 'mp4'; $j.Suffix = '(denoised)' }
        'sharpen'  { $j.Args = @('-vf', 'cas=strength=0.7') + (Get-VideoArgs 18) + (Get-KeepAudioArgs $src); $j.Ext = 'mp4'; $j.Suffix = '(sharpened)' }
        'deint'    { $j.Args = @('-vf', 'bwdif=mode=send_frame') + (Get-VideoArgs 18) + (Get-KeepAudioArgs $src); $j.Ext = 'mp4'; $j.Suffix = '(deinterlaced)' }
        'interp'   { $j.Args = @('-vf', 'minterpolate=fps=60:mi_mode=mci:mc_mode=aobmc:me_mode=bidir:vsbmc=1') + (Get-VideoArgs 18) + (Get-KeepAudioArgs $src); $j.Ext = 'mp4'; $j.Suffix = '(60 fps smooth)' }
        'crop' {
            $c = Get-CropFilter $src
            $j.Args = @('-vf', "crop=$c") + (Get-VideoArgs 18) + (Get-KeepAudioArgs $src)
            $j.Ext = 'mp4'; $j.Suffix = '(no bars)'
            $j.Note = "found crop $($c.Split(':')[0])×$($c.Split(':')[1])"
        }
        'pickaudio' {
            $tracks = Get-Streams $src 'a'
            if ($tracks.Count -lt 2) { throw 'The file has only one audio track - nothing to choose from' }
            # Track numbers are asked once for all selected files (or come in -Value: ‹1,3›)
            if ($null -eq $script:pickedTracks) {
                if ($Value) { $script:pickedTracks = @(ConvertTo-TrackList $Value $tracks.Count) }
                else {
                    Write-Host ''
                    Write-Host "Audio tracks in ‹$([IO.Path]::GetFileName($src))›:" -ForegroundColor White
                    for ($t = 0; $t -lt $tracks.Count; $t++) { Write-Host "  $(Format-Stream $tracks[$t] ($t + 1))" }
                    Write-Host '  Several are fine: ‹1 3›, ‹1,3› or ‹2-4›. The first one becomes the default track.' -ForegroundColor DarkGray
                    $script:pickedTracks = @(Read-TrackList 'Which ones to keep (numbers)' $tracks.Count)
                }
            }
            $keep = @($script:pickedTracks)
            if (-not $keep.Count) { throw "Could not read the track numbers: the file has tracks 1 to $($tracks.Count), for example ‹1 3› or ‹2-4›" }
            foreach ($k in $keep) { if ($k -gt $tracks.Count) { throw "There is no track number $k" } }
            $j.Args = @('-map', '0:v?')
            foreach ($k in $keep) { $j.Args += @('-map', "0:a:$($k - 1)") }
            if ($srcExt -ne 'mp4') { $j.Args += @('-map', '0:s?') }
            # the first kept track is the default, the others are regular
            $j.Args += @('-c', 'copy', '-disposition:a', '0', '-disposition:a:0', 'default') + (Get-TrackNameArgs $src $keep)
            if ($keep.Count -eq 1) { $j.Suffix = "(track $($keep[0]))" } else { $j.Suffix = "(tracks $($keep -join ', '))" }
            $j.Note = 'tracks kept: ' + (($keep | ForEach-Object { Format-Stream $tracks[$_ - 1] $_ }) -join '; ')
        }
        'voice'     { $j.Args = Get-SoundJobArgs $srcExt @('highpass=f=80,afftdn=nf=-25:tn=1') $src; $j.Suffix = "(clean audio$($script:soundNote))" }
        'stripmeta' { $j.Args = @('-map', '0', '-map_metadata', '-1', '-map_chapters', '-1', '-c', 'copy', '-fflags', '+bitexact'); $j.Suffix = '(no metadata)' }
        'teaser' {
            $dur = Get-Duration $src
            if ($dur -lt 20) { throw 'The video is shorter than 20 seconds - a teaser makes no sense' }
            $sel = Get-TeaserFilter $dur
            $j.Args = @('-vf', "select='$sel',setpts=N/FRAME_RATE/TB", '-af', "aselect='$sel',asetpts=N/SR/TB") + (Get-VideoArgs 20) + $mp4Audio
            $j.Ext = 'mp4'; $j.Suffix = '(teaser)'; $j.Replace = $false
        }
        'subs-add' {
            $sub = Find-SubSidecar $src
            if (-not $sub) { throw 'There is no subtitle file with the same name next to it (name.srt, name.en.srt, .ass, .vtt)' }
            $j.Args = @('-i', $sub, '-map', '0', '-map', '1', '-c', 'copy')
            $j.Ext = 'mkv'; $j.Suffix = '(with subtitles)'; $j.Replace = $false
            $j.Note = "adding ‹$([IO.Path]::GetFileName($sub))›"
        }
        'subs-burn' {
            # Subtitles are copied to a temporary file in TEMP: a path with ‹C:› would need escaping in the filter
            $sub = Find-SubSidecar $src
            if ($sub) {
                $tmp = "ffmpeg-sub-$PID" + [IO.Path]::GetExtension($sub).ToLower()
                Copy-Item -LiteralPath $sub -Destination (Join-Path $env:TEMP $tmp) -Force
                $j.Note = "burning in ‹$([IO.Path]::GetFileName($sub))›"
            } else {
                $text = Get-Streams $src 's' | Where-Object { $_.codec_name -in @('subrip', 'ass', 'ssa', 'mov_text', 'webvtt') } | Select-Object -First 1
                if (-not $text) { throw 'There is neither a subtitle file next to it nor text subtitles inside the video' }
                $tmp = "ffmpeg-sub-$PID.ass"
                & $FFmpeg -hide_banner -v error -nostdin -y -i $src -map "0:$($text.index)" (Join-Path $env:TEMP $tmp)
                $j.Note = "burning in embedded subtitles: $(Format-Stream $text 1)"
            }
            $j.Args = @('-vf', "subtitles=$tmp") + (Get-VideoArgs 18) + (Get-KeepAudioArgs $src)
            $j.Ext = 'mp4'; $j.Suffix = '(with burned-in subtitles)'; $j.Replace = $false
        }
        'subs-extract' { $j.Custom = 'subsx'; $j.OutLabel = 'subtitles to separate files'; $j.Replace = $false }
        'split'     { $j.Custom = 'split'; $j.OutLabel = "parts of $(Format-Num $splitMin) min"; $j.Replace = $false }
        'frames'    { $j.Custom = 'frames'; $j.OutLabel = "a frame every $(Format-Num $framesSec) s to a folder"; $j.Replace = $false }
        'check'     { $j.Custom = 'check'; $j.OutLabel = 'error check'; $j.Replace = $false }
        'spectrum'  { $j.Args = @('-lavfi', 'showspectrumpic=s=1600x900:legend=1', '-frames:v', '1', '-update', '1'); $j.Ext = 'png'; $j.Suffix = '(spectrum)'; $j.Replace = $false }
        'musicvideo' {
            # Video from music: the cover from the file (if any) or a waveform
            $cover = Join-Path $env:TEMP "ffmpeg-cover-$PID.png"
            Remove-Item -LiteralPath $cover -ErrorAction SilentlyContinue
            & $FFmpeg -hide_banner -v error -nostdin -y -i $src -an -map '0:v:0?' -frames:v 1 -update 1 $cover 2>$null
            if ((Test-Path -LiteralPath $cover) -and (Get-Item -LiteralPath $cover).Length -gt 0) {
                $j.InArgs = @('-loop', '1', '-framerate', '2', '-i', $cover)
                $j.Args = @('-map', '0:v', '-map', '1:a', '-vf', "scale='min(1920,iw)':'min(1080,ih)':force_original_aspect_ratio=decrease,pad=ceil(iw/2)*2:ceil(ih/2)*2,format=yuv420p",
                    '-c:v', 'libx264', '-tune', 'stillimage', '-preset', 'medium', '-crf', '20', '-r', '2', '-c:a', 'aac', '-b:a', '192k', '-shortest', '-movflags', '+faststart')
                $j.Note = 'picture: the cover from the file'
            } else {
                $j.Args = @('-filter_complex', '[0:a]showwaves=s=1280x720:mode=cline:rate=30:colors=0x4FC3F7,format=yuv420p[v]', '-map', '[v]', '-map', '0:a',
                    '-c:v', 'libx264', '-preset', 'fast', '-crf', '23', '-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart')
                $j.Note = 'no cover - using a waveform'
            }
            $j.Ext = 'mp4'; $j.Suffix = '(video)'; $j.Replace = $false
        }
        'web' { $j.Args = @('-frames:v', '1', '-update', '1', '-vf', "scale='min(2560,iw)':'min(2560,ih)':force_original_aspect_ratio=decrease", '-c:v', 'libwebp', '-quality', '80'); $j.Ext = 'webp'; $j.Suffix = '(for web)'; $j.Replace = $false }
        'fit'      { $j.Custom = 'fit'; $j.Ext = 'mp4'; $j.Suffix = "($fitLabel)"; $j.Replace = $false }
        'mp4'      { $j.Args = (Get-VideoArgs 20) + $mp4Audio; $j.Ext = 'mp4'; $j.Suffix = '(H.264)' }
        'compress' { $j.Args = (Get-VideoArgs 26 'slow') + @('-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart'); $j.Ext = 'mp4'; $j.Suffix = '(compressed)' }
        'h265'     { $j.Args = @('-c:v', 'libx265', '-preset', 'medium', '-crf', '26', '-tag:v', 'hvc1', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart'); $j.Ext = 'mp4'; $j.Suffix = '(H.265)' }
        'gpu265'   { Assert-Gpu 'h265'; $j.Args = (Get-GpuArgs 'h265' -Quality 28) + @('-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart'); $j.Ext = 'mp4'; $j.Suffix = '(H.265 GPU)' }
        'size' {
            # Bitrate for a size: (megabytes * 8192 * 0.96 margin) / duration - 128 kbps for audio
            $dur = Get-Duration $src
            $mb = [double]::Parse($Value, $inv)   # the string must be turned into a number explicitly: "10" * 8192 — is string repetition
            $kbps = [math]::Floor($mb * 8192 * 0.96 / $dur) - 128
            if ($kbps -lt 100) { throw "The video is too long to fit into $Value MB" }
            if (Use-Gpu) {
                $j.Args = Get-GpuArgs 'h264' -Kbps $kbps
            } else {
                $log = Join-Path $env:TEMP "ffmpeg-2pass-$PID"
                $base2 = @('-c:v', 'libx264', '-preset', 'medium', '-b:v', "${kbps}k", '-pix_fmt', 'yuv420p', '-passlogfile', $log)
                $j.Pass1 = $base2 + @('-pass', '1', '-an', '-f', 'null')
                $j.Args = $base2 + @('-pass', '2')
            }
            $j.Args += @('-c:a', 'aac', '-b:a', '128k', '-movflags', '+faststart')
            $j.Ext = 'mp4'; $j.Suffix = "(up to $Value MB)"
        }
        'height'   { $j.Args = @('-vf', "scale=-2:'min($Value,ih)'") + (Get-VideoArgs 22) + $mp4Audio; $j.Ext = 'mp4'; $j.Suffix = "(${Value}p)" }
        'fps'      { $j.Args = @('-vf', "fps=$Value") + (Get-VideoArgs 20) + $mp4Audio; $j.Ext = 'mp4'; $j.Suffix = "($Value fps)" }
        'remux-mp4' { $j.Args = @('-map', '0:v', '-map', '0:a?', '-c', 'copy', '-movflags', '+faststart'); $j.Ext = 'mp4'; $j.Suffix = '(remux)' }
        'remux-mkv' { $j.Args = @('-map', '0', '-c', 'copy'); $j.Ext = 'mkv'; $j.Suffix = '(remux)' }
        'trim'     { $j.InArgs = $trimIn; $j.Args = @('-map', '0:v?', '-map', '0:a?', '-map', '0:s?', '-c', 'copy', '-avoid_negative_ts', 'make_zero'); $j.Suffix = '(trimmed)' }
        'trim-exact' { $j.InArgs = $trimIn; $j.Args = (Get-VideoArgs 18) + $mp4Audio; $j.Ext = 'mp4'; $j.Suffix = '(trimmed)' }
        'speed' {
            if ($videoExt -contains $srcExt) {
                $j.Args = @('-vf', "setpts=PTS/$Value", '-af', "atempo=$Value") + (Get-VideoArgs 20) + $mp4Audio; $j.Ext = 'mp4'
            } else {
                $j.Args = Get-SoundJobArgs $srcExt @("atempo=$Value")
            }
            $j.Suffix = "(speed ${Value}x)"
        }
        'reverse'  { $j.Args = @('-vf', 'reverse', '-af', 'areverse') + (Get-VideoArgs 20) + $mp4Audio; $j.Ext = 'mp4'; $j.Suffix = '(reversed)'; $j.Replace = $false }
        'square'   { $j.Args = @('-filter_complex', $square.Replace('[0:v]', "[0:$(Get-MainVideoIndex $src)]"), '-map', '[v]', '-map', '0:a?') + (Get-VideoArgs 21) + $mp4Audio; $j.Ext = 'mp4'; $j.Suffix = '(1x1)'; $j.Replace = $false }
        'boomerang' {
            # Forward and back from the first 4 seconds, no audio
            $m = Get-MainVideoIndex $src
            $j.InArgs = @('-t', '4')
            $j.Args = @('-filter_complex', "[0:$m]split[a][b];[b]reverse[r];[a][r]concat=n=2:v=1:a=0,$evenSize[v]", '-map', '[v]', '-an') + (Get-VideoArgs 20) + @('-movflags', '+faststart')
            $j.Ext = 'mp4'; $j.Suffix = '(boomerang)'; $j.Replace = $false
        }
        'gif2mp4' {
            # Like Telegram does it: the GIF is stored as a regular H.264 video - many times smaller and smoother
            $j.Args = @('-vf', $evenSize, '-c:v', 'libx264', '-preset', 'slow', '-crf', '20', '-pix_fmt', 'yuv420p', '-an', '-movflags', '+faststart')
            $j.Ext = 'mp4'
        }
        'tgsticker' {
            # Telegram video sticker: WEBM (VP9), one side 512 px, up to 3 seconds, no audio, transparency is kept
            $j.Args = @('-t', '3', '-vf', 'scale=512:512:force_original_aspect_ratio=decrease,fps=30', '-c:v', 'libvpx-vp9', '-pix_fmt', 'yuva420p', '-b:v', '400k', '-crf', '30', '-deadline', 'good', '-row-mt', '1', '-an')
            $j.Ext = 'webm'; $j.Suffix = '(sticker)'; $j.Replace = $false
            if ((Get-Duration $src) -gt 3) { $j.Note = 'a sticker can be at most 3 seconds long - the first 3 are used' }
        }
        'vertical' { $j.Args = @('-filter_complex', $vertical.Replace('[0:v]', "[0:$(Get-MainVideoIndex $src)]"), '-map', '[v]', '-map', '0:a?') + (Get-VideoArgs 21) + $mp4Audio; $j.Ext = 'mp4'; $j.Suffix = '(9x16)'; $j.Replace = $false }
        'frame'    { $j.InArgs = @('-ss', (Format-Num ((Get-Duration $src) / 2))); $j.Args = @('-frames:v', '1', '-update', '1', '-q:v', '2'); $j.Ext = 'jpg'; $j.Suffix = '(frame)'; $j.Replace = $false }
        'sheet' {
            $rate = Format-Num (16 / (Get-Duration $src))
            $j.Args = @('-vf', "fps=$rate,scale=480:-2,tile=4x4:padding=4:margin=4", '-frames:v', '1', '-update', '1', '-q:v', '3')
            $j.Ext = 'jpg'; $j.Suffix = '(thumbnails)'; $j.Replace = $false
        }
        'vrotate'  { $j.Args = @('-vf', $rotate[$Value]) + (Get-VideoArgs 18) + $mp4Audio; $j.Ext = 'mp4'; $j.Suffix = "($($rotateName[$Value]))" }
        'mute'     { $j.Args = @('-an', '-c', 'copy'); $j.Suffix = '(no audio)' }
        'gif'      { $j.Args = @('-vf', $gif[$Value][1], '-loop', '0'); $j.Ext = 'gif'; $j.Suffix = "(GIF $($gif[$Value][0]))"; $j.Replace = $false }
        'extract'  {
            $f = $audioFormats[$Value]; $j.Ext = $f[0]; $j.Replace = $false
            # MP3, WAV, FLAC and others hold one track: if there are several, each picked one goes to its own file (MKA holds them all)
            $tracks = @(Get-Streams $src 'a')
            if ($tracks.Count -eq 0) { throw 'The file has no audio' }
            if ($Value -ne 'mka' -and $tracks.Count -gt 1) { $j.Custom = 'audiox'; $j.OutLabel = 'audio tracks to separate files' }
            elseif ($Value -eq 'mka' -and $tracks.Count -gt 1) {
                # MKA holds all tracks: the picked ones go into one file, the first one is the default
                $keep = @(Request-Tracks $src $tracks 'The picked tracks go into one MKA file. You can type ‹1 3› or ‹2-4›, Enter = all.' 'Which ones to extract (numbers)')
                foreach ($k in $keep) { if ($k -gt $tracks.Count) { throw "There is no track number $k" } }
                $j.Args = @('-vn')
                foreach ($k in $keep) { $j.Args += @('-map', "0:a:$($k - 1)") }
                $j.Args += $f[1] + @('-disposition:a', '0', '-disposition:a:0', 'default') + (Get-TrackNameArgs $src $keep)
                if ($keep.Count -lt $tracks.Count) {
                    if ($keep.Count -eq 1) { $j.Suffix = "(track $($keep[0]))" } else { $j.Suffix = "(tracks $($keep -join ', '))" }
                }
            }
            else { $j.Args = @('-vn', '-map', '0:a') + $f[1] }
        }
        'audio'    {
            $f = $audioFormats[$Value]; $j.Ext = $f[0]; if ($Value -eq 'mp3vbr') { $j.Suffix = '(VBR)' }
            # MP3, M4A and FLAC hold a cover - it is carried over as is, other formats get audio only
            if (@('mp3', 'm4a', 'flac') -contains $f[0]) { $j.Args = @('-map', '0:a', '-map', '0:v?', '-c:v', 'copy', '-disposition:v', 'attached_pic') + $f[1] }
            else { $j.Args = @('-vn') + $f[1] }
        }
        'louder'   { $j.Args = Get-SoundJobArgs $srcExt @("volume=${Value}dB") $src; $j.Suffix = "(louder +$Value dB$($script:soundNote))" }
        'quieter'  { $j.Args = Get-SoundJobArgs $srcExt @("volume=-${Value}dB") $src; $j.Suffix = "(quieter -$Value dB$($script:soundNote))" }
        'normalize' { $j.Args = Get-SoundJobArgs $srcExt @('loudnorm=I=-16:TP=-1.5:LRA=11') $src @('-ar', '48000'); $j.Suffix = "(loudness$($script:soundNote))" }
        'fade' {
            $d = Get-Duration $src
            $in = [math]::Min(2, $d / 4); $out = [math]::Min(3, $d / 4)
            $j.Args = Get-SoundJobArgs $srcExt @("afade=t=in:st=0:d=$(Format-Num $in),afade=t=out:st=$(Format-Num ($d - $out)):d=$(Format-Num $out)") $src
            $j.Suffix = "(fade$($script:soundNote))"
        }
        'mono'      { $j.Args = Get-SoundJobArgs $srcExt @('aformat=channel_layouts=mono') $src; $j.Suffix = "(mono$($script:soundNote))" }
        'slowed' {
            if ($videoExt -contains $srcExt) { throw 'This effect changes the audio length - for audio files only, in a video the sound would drift away from the picture' }
            $sr = Get-SampleRate $src
            $j.Args = Get-SoundJobArgs $srcExt @("asetrate=$([int]($sr * 0.85)),aresample=$sr,aecho=0.8:0.88:60:0.4") $src
            $j.Suffix = "(slowed + reverb$($script:soundNote))"
        }
        'nightcore' {
            if ($videoExt -contains $srcExt) { throw 'This effect changes the audio length - for audio files only, in a video the sound would drift away from the picture' }
            $sr = Get-SampleRate $src
            $j.Args = Get-SoundJobArgs $srcExt @("asetrate=$([int]($sr * 1.25)),aresample=$sr") $src
            $j.Suffix = "(nightcore$($script:soundNote))"
        }
        'ringtone' {
            # iPhone ringtone: M4R (AAC), the first 30 seconds, fade-out at the end
            $d = [math]::Min((Get-Duration $src), 30)
            $j.Args = @('-t', '30', '-vn', '-c:a', 'aac', '-b:a', '256k', '-af', "afade=t=out:st=$(Format-Num ([math]::Max(0, $d - 2))):d=2", '-f', 'ipod')
            $j.Ext = 'm4r'; $j.Suffix = '(ringtone)'; $j.Replace = $false
        }
        'silence'  { $j.Args = Get-SoundJobArgs $srcExt @($silence); $j.Suffix = '(no silence)' }
        'image'    {
            $j.Ext = $Value; $j.Args = Get-ImageArgs $Value
            # JPG has no transparency: transparent areas are filled with white instead of turning black
            if (@('jpg', 'jpeg') -contains $Value -and (Test-HasAlpha $src)) {
                $j.Args = @('-filter_complex', '[0:v]format=rgba,split[a][b];[a]drawbox=c=white:t=fill[w];[w][b]overlay=format=auto') + $j.Args
            }
        }
        'ico'      { $j.Ext = 'ico'; $j.Args = @('-frames:v', '1', '-update', '1', '-vf', 'scale=256:256:force_original_aspect_ratio=decrease,format=rgba,pad=256:256:(ow-iw)/2:(oh-ih)/2:color=black@0', '-c:v', 'png'); $j.Replace = $false }
        'squarecrop' { $j.Args = @('-vf', "crop='min(iw,ih)':'min(iw,ih)'") + (Get-ImageArgs $srcExt); $j.Suffix = '(square)' }
        'gray'     { $j.Args = @('-vf', 'hue=s=0') + (Get-ImageArgs $srcExt); $j.Suffix = '(b-w)' }
        'upscale'  { $j.Args = @('-vf', "scale=iw*${Value}:ih*${Value}:flags=lanczos") + (Get-ImageArgs $srcExt); $j.Suffix = "(x$Value)" }
        'downscale' { $j.Args = @('-vf', "scale=iw/${Value}:-1:flags=lanczos") + (Get-ImageArgs $srcExt); $j.Suffix = "(downscaled $Value times)" }
        'irotate'  { $j.Args = @('-vf', $rotate[$Value]) + (Get-ImageArgs $srcExt); $j.Suffix = "($($rotateName[$Value]))" }
        default    { throw "Unknown operation: $Preset" }
    }
    return $j
}

# A free name: ‹name.ext›, or if taken ‹name (2).ext›, ‹name (3).ext›…
function Get-FreePath([string]$dir, [string]$name, [string]$ext) {
    $p = Join-Path $dir "$name.$ext"
    $k = 2
    while (Test-Path -LiteralPath $p) { $p = Join-Path $dir "$name ($k).$ext"; $k++ }
    return $p
}

# Folder for copies: next to the source or in the ‹FFmpeg› subfolder
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
        Write-Host "Cancelled. Processed before that: $ok of $n" -ForegroundColor Yellow
        if (-not $NoPause) { Read-Host 'Press Enter to close' }
        return
    }
    if ($failed.Count -eq 0) {
        Write-Host "Done: $ok of $n" -ForegroundColor Green
        if ($NoPause) { return }
        if ($alwaysWait) { Read-Host 'Press Enter to close' } else { Start-Sleep -Seconds 3 }
    } else {
        Write-Host "Done: $ok of $n. Failed: $($failed.Count)" -ForegroundColor Yellow
        foreach ($f in $failed) { Write-Host "  $f" }
        if (-not $NoPause) { Read-Host 'Press Enter to close' }
    }
}

# Progress bar: [████████░░░░]  58%  1:45 / 3:00  ·  2.4x  ·  left ~0:52
function Get-ProgressText([double]$cur, [double]$total, [string]$spd, [double]$elapsed) {
    $w = 24
    if ($total -gt 0) {
        $p = [math]::Min(1.0, [math]::Max(0.0, $cur / $total))
        $fill = [int][math]::Round($p * $w)
        $bar = ([string][char]0x2588 * $fill) + ([string][char]0x2591 * ($w - $fill))
        $text = '  [{0}] {1,3}%  {2} / {3}' -f $bar, [int][math]::Floor($p * 100), (Format-Time ([math]::Floor($cur))), (Format-Time ([math]::Floor($total)))
        if ($spd) { $text += "  ·  $spd" }
        if ($p -gt 0.02 -and $p -lt 1) { $text += '  ·  left ~' + (Format-Time ([math]::Ceiling($elapsed * (1 - $p) / $p))) }
    } else {
        $text = '  processed {0}' -f (Format-Time ([math]::Floor($cur)))
        if ($spd) { $text += "  ·  $spd" }
    }
    return $text
}

# Computer load: CPU and memory of ffmpeg itself, the graphics card via nvidia-smi
$nvidiaSmi = (Get-Command nvidia-smi -ErrorAction SilentlyContinue).Source
$cores = [Environment]::ProcessorCount

function Format-Size([double]$bytes) {
    if ($bytes -ge 1GB) { return ($bytes / 1GB).ToString('0.0', $inv) + ' GB' }
    return [string][int]($bytes / 1MB) + ' MB'
}

function Update-Resources($state, [double]$now) {
    if (-not $state.Proc) {
        # ffmpeg — is a child process of this window; look it up once
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
        if ($v.Count -ge 3) { $state.Gpu = '   │   GPU {0}% · encoder {1}% · VRAM {2}' -f $v[0], $v[1], (Format-Size ([double]$v[2] * 1MB)) }
    }
    $text = '  CPU {0}% · RAM {1}' -f $state.Cpu, (Format-Size $state.Ram)
    return $text + $state.Gpu
}

# Two lines, redrawn in place. If the output is redirected (tests), one line via `r
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

# Esc, Q or Ctrl+C (Ctrl+C arrives as a key while TreatControlCAsInput is on)
function Test-CancelKey {
    if ($plainOut) { return $false }
    while ([Console]::KeyAvailable) {
        $k = [Console]::ReadKey($true)
        if ($k.Key -eq [ConsoleKey]::Escape -or $k.Key -eq [ConsoleKey]::Q) { return $true }
        if ($k.Key -eq [ConsoleKey]::C -and ($k.Modifiers -band [ConsoleModifiers]::Control)) { return $true }
    }
    return $false
}

# Runs ffmpeg with a progress bar. $total is the expected result length in seconds
# (0 — unknown, then only the processed time is shown). Returns the exit code.
function Invoke-FFmpeg([string[]]$ffArgs, [double]$total) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $state = @{ Cur = 0.0; Spd = ''; Shown = $false; Top = -1; Proc = $null; LastCpu = 0.0; LastWall = 0.0; Cpu = 0; Ram = 0; Gpu = ''; GpuAt = -10.0 }
    # Ctrl+C does not kill the window but arrives as a key; -nostdin keeps ffmpeg from grabbing key presses
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
            # ‹2.41x› -> ‹2.4x›, ‹1.85e+03x› -> ‹1850x›
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
                Write-Host '  Stopping…' -ForegroundColor Yellow
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

# Expected result length: for speed and trimming it differs from the source
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

# Images and frames need no progress bar: they take a fraction of a second
$noProgress = @('image', 'ico', 'gray', 'upscale', 'downscale', 'irotate', 'frame', 'sheet', 'spectrum', 'web', 'squarecrop')

# ---------- Extra operations ----------
$audioExt = @('mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus', 'wma', 'ac3', 'dts', 'aiff', 'ape', 'wv', 'mka')
$script:lastOutput = ''        # the last created file/folder - for ‹Show in Explorer›
$script:ffErrorCount = 0       # how many error lines ffmpeg printed (for the file check)

# Audio without re-encoding if all tracks are already AAC (MP4 holds it as is), otherwise AAC 192 kbps
function Get-KeepAudioArgs([string]$src) {
    $codecs = @(Get-Streams $src 'a' | ForEach-Object { "$($_.codec_name)" })
    if ($codecs.Count -and -not ($codecs | Where-Object { $_ -ne 'aac' })) { return @('-c:a', 'copy', '-movflags', '+faststart') }
    return @('-c:a', 'aac', '-b:a', '192k', '-movflags', '+faststart')
}

# Stream number of the main video: the first video that is not a cover (attached_pic). $null = no video
function Get-MainVideoIndex([string]$src) {
    $json = (& $FFprobe -v error -select_streams v -show_entries 'stream=index:stream_disposition=attached_pic' -of json $src 2>$null) -join ''
    if (-not $json) { return $null }
    foreach ($s in @(($json | ConvertFrom-Json).streams)) { if ($s.disposition.attached_pic -ne 1) { return [int]$s.index } }
    return $null
}

# If an operation re-encodes the video and does not pick streams itself, ffmpeg would take one audio track,
# and for a video with a cover sometimes the cover itself. So explicitly: the main video and all audio tracks
# (if the result format holds audio and the audio is not removed)
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

# H.264 and H.265 (and GPU encoders) do not accept an odd frame size (for example 641×361):
# when re-encoding, the size is rounded to even - a scale is appended to the operation filters
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

# Whether the image has transparency (alpha channel or palette)
function Test-HasAlpha([string]$src) {
    $pf = "$(& $FFprobe -v error -select_streams v:0 -show_entries stream=pix_fmt -of csv=p=0 $src 2>$null)".Trim()
    return ($pf -match '^(rgba|bgra|argb|abgr|ya8|ya16|yuva|gbrap|pal8|rgba64|bgra64)')
}

# Current rotation from the metadata (degrees counterclockwise; phones write, for example, -90)
function Get-Rotation([string]$src) {
    $r = "$(& $FFprobe -v error -select_streams v:0 -show_entries stream_side_data=rotation -of csv=p=0 $src 2>$null)".Trim()
    $x = 0.0
    if ([double]::TryParse(($r -split '[,\s]')[0], [Globalization.NumberStyles]::Float, $inv, [ref]$x)) { return [int]$x }
    return 0
}

# Looks for black bars: runs up to a minute of video through cropdetect and takes the final crop
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
    if (-not $last) { throw 'Could not detect the crop' }
    $p = $last.Split(':')
    if ([int]$p[0] -ge $info.W - 4 -and [int]$p[1] -ge $info.H - 4) { throw 'No black bars found' }
    return $last
}

# Subtitle file next to the video: ‹name.srt› or ‹name.en.srt› (srt, ass, ssa, vtt)
function Find-SubSidecar([string]$src) {
    $dir = [IO.Path]::GetDirectoryName($src)
    $base = [IO.Path]::GetFileNameWithoutExtension($src)
    Get-ChildItem -LiteralPath $dir -File | Where-Object {
        $_.Extension.ToLower() -in @('.srt', '.ass', '.ssa', '.vtt') -and ($_.BaseName -eq $base -or $_.BaseName.StartsWith("$base."))
    } | Sort-Object Name | Select-Object -First 1 -ExpandProperty FullName
}

# File streams of one type (a = audio, s = subtitles) with language and title
function Get-Streams([string]$src, [string]$type) {
    $json = (& $FFprobe -v error -select_streams $type -show_entries 'stream=index,codec_name,channels,sample_rate,bit_rate:stream_tags=language,title,name,handler_name' -of json $src 2>$null) -join ''
    if (-not $json) { return @() }
    return @(($json | ConvertFrom-Json).streams)
}

$langNames = @{ 'rus' = 'Russian'; 'ru' = 'Russian'; 'eng' = 'English'; 'en' = 'English'; 'jpn' = 'Japanese'; 'ja' = 'Japanese'; 'ukr' = 'Ukrainian'; 'deu' = 'German'; 'ger' = 'German'; 'fra' = 'French'; 'fre' = 'French'; 'spa' = 'Spanish'; 'ita' = 'Italian'; 'kor' = 'Korean'; 'chi' = 'Chinese'; 'zho' = 'Chinese'; 'und' = 'language not set' }
# Track name: title (MKV and others), name (MP4 from OBS - the udta/name box) or handler_name.
# Service names like ‹SoundHandler› do not count as a name
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
    if ($s.sample_rate) { $tech += "$($s.sample_rate) Hz" }
    switch ("$($s.channels)") { '' { } '1' { $tech += 'mono' } '2' { $tech += 'stereo' } '6' { $tech += '5.1' } '8' { $tech += '7.1' } default { $tech += "$($s.channels) ch." } }
    if ($s.bit_rate -and "$($s.bit_rate)" -match '^[0-9]+$') { $tech += "$([math]::Round([double]$s.bit_rate / 1000)) kbps" }
    $parts += ($tech -join ', ')
    if ($lang) { $parts += $lang }
    return ($parts -join ' · ')
}

# When copying, ffmpeg loses the names of MP4 audio tracks, so every track of the result gets its name
# written explicitly (ffmpeg puts it into the same name box). $order = source track numbers (from 1) in output order
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
# Whether all audio tracks go to the result in their original order (-map 0 or -map 0:a?)
function Test-KeepsAllAudio($a) {
    $a = @($a)
    for ($i = 0; $i -lt $a.Count - 1; $i++) { if ($a[$i] -eq '-map' -and @('0', '0:a', '0:a?') -contains $a[$i + 1]) { return $true } }
    return $false
}

# ‹1 3›, ‹1,3›, ‹2-4› -> track numbers in the order entered, without repeats; empty if written wrong
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
# Asks for track numbers until they are entered correctly. -AllowEmpty: an empty answer = all tracks (returns an empty list)
function Read-TrackList([string]$label, [int]$max, [switch]$AllowEmpty) {
    while ($true) {
        $answer = (Read-Host $label).Trim()
        if ($AllowEmpty -and -not $answer) { return @() }
        $list = @(ConvertTo-TrackList $answer $max)
        if ($list.Count) { return $list }
        Write-Host "  Numbers from 1 to $max are needed, for example ‹1 3› or ‹2-4›" -ForegroundColor Red
    }
}

# Which audio tracks to take: a list with names, one answer for all selected files. An empty answer = all tracks
function Request-Tracks([string]$src, $tracks, [string]$hint, [string]$label) {
    if ($null -eq $script:pickedTracks) {
        Write-Host ''
        Write-Host "Audio tracks in ‹$([IO.Path]::GetFileName($src))›:" -ForegroundColor White
        for ($t = 0; $t -lt $tracks.Count; $t++) { Write-Host "  $(Format-Stream $tracks[$t] ($t + 1))" }
        Write-Host "  $hint" -ForegroundColor DarkGray
        $script:pickedTracks = @(Read-TrackList $label $tracks.Count -AllowEmpty)
    }
    $keep = @($script:pickedTracks)
    if (-not $keep.Count) { $keep = @(1..$tracks.Count) }
    return $keep
}

# Audio from a file with several audio tracks: each picked track becomes its own file ‹name (track name).ext›.
# The numbers are asked once for all selected files
function Invoke-AudioExtract([string]$src) {
    $tracks = @(Get-Streams $src 'a')
    $f = $audioFormats[$Value]
    $keep = @(Request-Tracks $src $tracks 'Each picked track becomes its own file. You can type ‹1 3› or ‹2-4›, Enter = all.' 'Which ones to extract (numbers)')
    $dir = Get-OutDir ([IO.Path]::GetDirectoryName($src))
    $base = [IO.Path]::GetFileNameWithoutExtension($src)
    $dur = Get-Duration $src
    $made = 0
    foreach ($k in $keep) {
        if ($k -gt $tracks.Count) { Write-Host "  There is no track number $k - skipping" -ForegroundColor Yellow; continue }
        $s = $tracks[$k - 1]
        $name = Get-StreamName $s
        $label = $name
        if (-not $label) { $label = "track $k" }
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

# Extract all subtitles to separate files next to the video
function Invoke-SubsExtract([string]$src) {
    $subs = Get-Streams $src 's'
    if ($subs.Count -eq 0) { Write-Host '  The file has no subtitles' -ForegroundColor Yellow; return 1 }
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
        if (-not $ext) { Write-Host "  $(Format-Stream $s $k) — this format cannot be extracted, skipping" -ForegroundColor Yellow; continue }
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

# Split into N-minute parts without re-encoding
function Invoke-Split([string]$src) {
    $dir = Get-OutDir ([IO.Path]::GetDirectoryName($src))
    $base = [IO.Path]::GetFileNameWithoutExtension($src)
    $ext = [IO.Path]::GetExtension($src).TrimStart('.').ToLower()
    $prefix = "$base (part"
    $k = 2
    while (Test-Path -LiteralPath (Join-Path $dir "$prefix 01).$ext")) { $prefix = "$base ($k) (part"; $k++ }
    $pattern = Join-Path $dir "$prefix %02d).$ext"
    $before = @(Get-ChildItem -LiteralPath $dir -File | ForEach-Object FullName)
    $code = Invoke-FFmpeg (@('-n', '-i', $src, '-map', '0', '-c', 'copy') + @(Get-TrackNameArgs $src) + @('-f', 'segment', '-segment_time', (Format-Num ($splitMin * 60)), '-reset_timestamps', '1', '-segment_start_number', '1', $pattern)) (Get-Duration $src)
    $new = @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $before -notcontains $_.FullName -and $_.Name.StartsWith($prefix) } | Sort-Object Name)
    if ($script:cancelled -or $code -ne 0) {
        Start-Sleep -Milliseconds 300
        $new | Remove-Item -ErrorAction SilentlyContinue
        return 1
    }
    Write-Host "  Parts made: $($new.Count)" -ForegroundColor Green
    if ($new.Count) { $script:lastOutput = $new[0].FullName }
    return 0
}

# Frames every N seconds - to a separate folder
function Invoke-Frames([string]$src) {
    $dir = Get-OutDir ([IO.Path]::GetDirectoryName($src))
    $base = [IO.Path]::GetFileNameWithoutExtension($src)
    $folder = Join-Path $dir "$base (frames)"
    $k = 2
    while (Test-Path -LiteralPath $folder) { $folder = Join-Path $dir "$base (frames $k)"; $k++ }
    New-Item -ItemType Directory -Path $folder | Out-Null
    $code = Invoke-FFmpeg @('-n', '-i', $src, '-vf', "fps=1/$(Format-Num $framesSec)", '-q:v', '2', (Join-Path $folder 'frame %04d.jpg')) (Get-Duration $src)
    if ($script:cancelled -or $code -ne 0) {
        Start-Sleep -Milliseconds 300
        Remove-Item -LiteralPath $folder -Recurse -ErrorAction SilentlyContinue
        return 1
    }
    $count = @(Get-ChildItem -LiteralPath $folder -File).Count
    Write-Host "  Frames saved: $count  ->  folder ‹$([IO.Path]::GetFileName($folder))›" -ForegroundColor Green
    $script:lastOutput = $folder
    return 0
}

# File check: full decode, every error is printed
function Invoke-Check([string]$src) {
    $script:ffErrorCount = 0
    $code = Invoke-FFmpeg @('-i', $src, '-map', '0:v?', '-map', '0:a?', '-f', 'null', '-') (Get-Duration $src)
    if ($script:cancelled) { return 1 }
    if ($code -eq 0 -and $script:ffErrorCount -eq 0) { Write-Host '  No errors found - the file is intact' -ForegroundColor Green; return 0 }
    Write-Host "  Errors found: $($script:ffErrorCount) - the file is damaged (some parts may not play)" -ForegroundColor Red
    return 1
}

# Short teaser: 6 clips of 2 seconds, evenly spread over the whole video
function Get-TeaserFilter([double]$dur) {
    $parts = @()
    for ($k = 0; $k -lt 6; $k++) {
        $t = $dur * (0.08 + 0.84 * $k / 5) - 1
        $parts += "between(t,$(Format-Num $t),$(Format-Num ($t + 2)))"
    }
    return ($parts -join '+')
}

# ---------- Fit into a size limit (Discord, Catbox, custom size) ----------
# Value = ‹target:mode:codec›, for example discord20:auto:h264.
#   target - discord20 | discord10 | catbox | custom (ask) | a number of megabytes
#   mode   - auto (balanced) | smooth (keep 60 fps) | sharp (30 fps, higher resolution)
#   codec  - h264 | h265; CPU or graphics card by the Encoder setting
$fitTargets = @{ 'discord20' = @(20, 'Discord 20 MB'); 'discord10' = @(10, 'Discord 10 MB'); 'catbox' = @(200, 'Catbox 200 MB') }
# How many bits per pixel a frame needs to look decent (H.265 is more efficient)
$fitBpp = @{ 'h264' = 0.05; 'h265' = 0.035 }
# Steps: short side of the frame and frame rate
$fitLadder = @(@(2160, 60), @(2160, 30), @(1440, 60), @(1440, 30), @(1080, 60), @(1080, 30), @(720, 60), @(720, 30),
               @(540, 60), @(540, 30), @(480, 60), @(480, 30), @(360, 60), @(360, 30), @(240, 30))

$fitMB = 0.0
$fitLabel = ''
if ($Preset -eq 'fit') {
    $fitTarget, $fitMode, $fitCodec = $Value.Split(':')
    if ($fitTargets.ContainsKey($fitTarget)) { $fitMB = $fitTargets[$fitTarget][0]; $fitLabel = $fitTargets[$fitTarget][1] }
    elseif ($fitTarget -ne 'custom') { $fitMB = [double]::Parse($fitTarget, $inv); $fitLabel = "up to $fitTarget MB" }
    else {
        while ($true) {
            $answer = (Read-Host 'How many megabytes the result should be (for example 25 or 49.5)').Trim().Replace(',', '.')
            $mb = 0.0
            if ([double]::TryParse($answer, [Globalization.NumberStyles]::Float, $inv, [ref]$mb) -and $mb -ge 1) { break }
            Write-Host '  A number of 1 or more is needed' -ForegroundColor Red
        }
        $fitMB = $mb
        $fitLabel = "up to $(Format-Num $mb) MB"
    }
}

# Source frame rate: ‹60000/1001› -> 59.94
function Get-Fps([string]$path) {
    $r = "$(& $FFprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of csv=p=0 $path 2>$null)".Trim()
    $a, $b = $r.Split('/')
    $x = 0.0; $y = 1.0
    if ([double]::TryParse($a, [Globalization.NumberStyles]::Float, $inv, [ref]$x) -and $b -and [double]::TryParse($b, [Globalization.NumberStyles]::Float, $inv, [ref]$y) -and $x -gt 0 -and $y -gt 0) { return $x / $y }
    return 30.0
}

# Picks resolution and frame rate: the best step the bitrate is enough for
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

# File size in the same megabytes as the limits (1 MB = 1 000 000 bytes), one decimal
function Format-MB([double]$bytes) { return ($bytes / 1000000).ToString('0.0', $inv) + ' MB' }

function Remove-PassLogs {
    Remove-Item -Path (Join-Path $env:TEMP "ffmpeg-2pass-$PID*") -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $env:TEMP "ffmpeg-x265-$PID*") -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $env:TEMP "ffmpeg-vidstab-$PID*") -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $env:TEMP "ffmpeg-sub-$PID*") -ErrorAction SilentlyContinue
    Remove-Item -Path (Join-Path $env:TEMP "ffmpeg-cover-$PID*") -ErrorAction SilentlyContinue
}

# Returns 0 = success, 'skip' — the file is already under the limit, otherwise an error code
function Invoke-Fit([string]$src, [string]$out) {
    $limit = $fitMB * 1000000
    $dur = Get-Duration $src
    $info = Get-StreamInfo $src
    $srcSize = (Get-Item -LiteralPath $src).Length
    if ($srcSize -le $limit -and $src.ToLower().EndsWith('.mp4') -and $info.VCodec -eq 'h264') {
        Write-Host "  The file is already $(Format-MB $srcSize) - under the limit, nothing to compress" -ForegroundColor Green
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
        Write-Host "  The video is too long ($(Format-Time ([math]::Floor($dur)))): even at the lowest quality it will not fit into $(Format-Num $fitMB) MB. Trim it first." -ForegroundColor Red
        return 1
    }
    $need = $fitBpp[$fitCodec]
    $fitGpu = Use-Gpu $fitCodec
    if ($fitGpu) { $need *= 1.2 }   # graphics card encoders are a bit less efficient than 2-pass x264/x265
    $plan = Get-FitPlan $info.W $info.H $fps $vKbps $fitMode $need

    $vf = "scale=-2:$($plan.Short)"
    if ($info.W -lt $info.H) { $vf = "scale=$($plan.Short):-2" }
    if ($plan.Fps -lt $fps - 0.5) { $vf += ",fps=$(Format-Num $plan.Fps)" }
    $codecName = 'H.264'
    if ($fitCodec -eq 'h265') { $codecName = 'H.265' }
    $how = '2 passes, CPU'
    if ($fitGpu) { $how = 'graphics card' }
    Write-Host ("  Length {0} · limit {1} MB  ->  {2}p {3} fps · video {4} kbps · audio {5} kbps · {6} ({7})" -f (Format-Time ([math]::Floor($dur))), (Format-Num $fitMB), $plan.Short, [math]::Round($plan.Fps), $vKbps, $aKbps, $codecName, $how) -ForegroundColor DarkGray
    if ($plan.Bpp -lt $need / 2) { Write-Host '  The video is long for this limit - the quality will be low. If the picture matters, better trim it.' -ForegroundColor Yellow }

    $preset = 'medium'
    if ($fitMB -le 50) { $preset = 'slow' }   # small limits mean short clips, so time can be spent on quality
    $audio = @('-an')
    if ($aKbps -gt 0) { $audio = @('-c:a', 'aac', '-b:a', "${aKbps}k", '-ac', '2') }
    $common = @('-map', "0:$(Get-MainVideoIndex $src)", '-map', '0:a:0?', '-sn', '-dn', '-vf', $vf)

    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $passes = @()
        if ($fitGpu) {
            $v = Get-GpuArgs $fitCodec -Kbps $vKbps
            $passes += , @(@('-y', '-i', $src) + $common + $v + $audio + @('-movflags', '+faststart', $out))
        } elseif ($fitCodec -eq 'h265') {
            # x265 writes its stats to a relative path (the colon in a ‹C:› path breaks the options)
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
                    $what = 'analysis'
                    if ($p -eq 1) { $what = 'encoding' }
                    Write-Host "  Pass $($p + 1) of $($passes.Count) ($what)" -ForegroundColor DarkGray
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
            Write-Host "  Result: $(Format-MB $size) of $(Format-Num $fitMB) MB" -ForegroundColor Green
            return 0
        }
        # Did not fit (happens on very ‹heavy› scenes) - lower the bitrate proportionally and try again
        $newKbps = [math]::Floor($vKbps * ($limit * 0.95 / $size))
        $why = 'over the limit'
        if ($size -le $limit) { $why = 'right at the limit, but a small margin is needed' }
        Write-Host "  Got $(Format-MB $size) - $why. Re-encoding at $newKbps kbps (attempt $($attempt + 1) of 3)" -ForegroundColor Yellow
        $vKbps = [math]::Max(30, $newKbps)
    }
    Write-Host "  Could not fit into $(Format-Num $fitMB) MB in 3 attempts" -ForegroundColor Red
    return 1
}

# A number from the user answer (or from -Value); asks until it is entered correctly
function Read-Number([string]$label, [double]$min, [double]$max) {
    while ($true) {
        $answer = (Read-Host $label).Trim().Replace(',', '.')
        $x = 0.0
        if ([double]::TryParse($answer, [Globalization.NumberStyles]::Float, $inv, [ref]$x) -and $x -ge $min -and $x -le $max) { return $x }
        Write-Host "  A number from $(Format-Num $min) to $(Format-Num $max) is needed" -ForegroundColor Red
    }
}
function Get-NumberSetting([string]$label, [double]$min, [double]$max) {
    $x = 0.0
    if ($Value -and [double]::TryParse($Value, [Globalization.NumberStyles]::Float, $inv, [ref]$x)) { return $x }
    return Read-Number $label $min $max
}

$splitMin = 0.0
$framesSec = 0.0
if ($Preset -eq 'split') { $splitMin = Get-NumberSetting 'How many minutes per part (for example 10)' 0.1 10000 }
if ($Preset -eq 'frames') { $framesSec = Get-NumberSetting 'Save a frame every how many seconds (for example 10)' 0.04 100000 }

# Video + music: two selected files - replace the audio or mix the music in the background (it loops)
if ($Preset -eq 'addaudio') {
    $vid = $Files | Where-Object { $videoExt -contains [IO.Path]::GetExtension($_).TrimStart('.').ToLower() } | Select-Object -First 1
    $aud = $Files | Where-Object { $audioExt -contains [IO.Path]::GetExtension($_).TrimStart('.').ToLower() } | Select-Object -First 1
    if ($Files.Count -ne 2 -or -not $vid -or -not $aud) {
        Write-Host 'Select exactly two files: one video and one music or audio file.' -ForegroundColor Red
        Finish 0 1 @($Files)
        return
    }
    $info = Get-StreamInfo $vid
    $dur = Get-Duration $vid
    $ext = 'mkv'
    if ($info.VCodec -in @('h264', 'hevc', 'av1', 'vp9')) { $ext = 'mp4' }
    $suffix = '(new audio)'
    $audioMap = @('-map', '1:a:0')
    if ($Value -eq 'mix' -and $info.ACodec) {
        $suffix = '(with music)'
        $audioMap = @('-filter_complex', '[1:a]volume=0.35[m];[0:a][m]amix=inputs=2:duration=first:dropout_transition=0:normalize=0[a]', '-map', '[a]')
    }
    $vdir = [IO.Path]::GetDirectoryName($vid)
    $out = Get-FreePath (Get-OutDir $vdir) "$([IO.Path]::GetFileNameWithoutExtension($vid)) $suffix" $ext
    Write-Host ''
    Write-Host "$([IO.Path]::GetFileName($vid)) + $([IO.Path]::GetFileName($aud))  ->  $([IO.Path]::GetFileName($out))" -ForegroundColor White
    if ($Value -eq 'mix' -and -not $info.ACodec) { Write-Host '  The video has no audio of its own - just adding the music' -ForegroundColor DarkGray }
    $code = Invoke-FFmpeg (@('-n', '-i', $vid, '-stream_loop', '-1', '-i', $aud, '-map', '0:v:0') + $audioMap + @('-c:v', 'copy', '-c:a', 'aac', '-b:a', '192k', '-t', (Format-Num $dur), '-movflags', '+faststart', $out)) $dur
    if ($script:cancelled -or $code -ne 0 -or -not (Test-Path -LiteralPath $out)) {
        Start-Sleep -Milliseconds 300
        Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue
        if (-not $script:cancelled) { Write-Host 'Error - the sources are untouched' -ForegroundColor Red }
        Finish 0 1 @($vid)
    } else { $script:lastOutput = $out; Finish 1 1 @() }
    return
}

# Slideshow: the selected images in alphabetical order into an MP4 1920×1080, each shown for N seconds
# Collage: the selected images in alphabetical order into one - in a row (same height) or in a column (same width)
if ($Preset -eq 'collage') {
    $sorted = @($Files | Sort-Object)
    if ($sorted.Count -lt 2) { Write-Host 'Select at least two images' -ForegroundColor Red; Finish 0 1 @($Files); return }
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
    $label = $(if ($Value -eq 'v') { 'collage in a column' } else { 'collage in a row' })
    $out = Get-FreePath (Get-OutDir ([IO.Path]::GetDirectoryName($first))) "$([IO.Path]::GetFileNameWithoutExtension($first)) ($label)" $ext
    Write-Host ''
    Write-Host "Collage of $($sorted.Count) images  ->  $([IO.Path]::GetFileName($out))" -ForegroundColor White
    $a = @('-hide_banner', '-v', 'error', '-nostdin', '-n') + $inputs + @('-filter_complex', $graph, '-frames:v', '1', '-update', '1')
    if ($allJpg) { $a += @('-q:v', '2') }
    & $FFmpeg @a $out
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $out)) {
        Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue
        Write-Host 'Error - the sources are untouched' -ForegroundColor Red
        Finish 0 1 @($first)
    } else { $script:lastOutput = $out; Finish 1 1 @() }
    return
}

if ($Preset -eq 'slideshow') {
    $sec = Get-NumberSetting 'How many seconds to show each image (for example 3)' 0.1 3600
    $sorted = @($Files | Sort-Object)
    $first = $sorted[0]
    $out = Get-FreePath (Get-OutDir ([IO.Path]::GetDirectoryName($first))) "$([IO.Path]::GetFileNameWithoutExtension($first)) (slideshow)" 'mp4'
    $list = Join-Path $env:TEMP "ffmpeg-slides-$PID.txt"
    $bs = [string][char]92
    $lines = @()
    foreach ($f in $sorted) {
        $lines += "file '" + ($f.Replace($bs, '/').Replace("'", "'" + $bs + "''")) + "'"
        $lines += "duration $(Format-Num $sec)"
    }
    # concat needs the last image repeated, otherwise its duration is ignored
    $lines += "file '" + ($sorted[-1].Replace($bs, '/').Replace("'", "'" + $bs + "''")) + "'"
    [IO.File]::WriteAllLines($list, [string[]]$lines, (New-Object Text.UTF8Encoding $false))
    Write-Host ''
    Write-Host "Slideshow of $($sorted.Count) images, $(Format-Num $sec) s each  ->  $([IO.Path]::GetFileName($out))" -ForegroundColor White
    $vf = 'scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:(ow-iw)/2:(oh-ih)/2:color=black,setsar=1,fps=30,format=yuv420p'
    $code = Invoke-FFmpeg (@('-n', '-f', 'concat', '-safe', '0', '-i', $list, '-vf', $vf) + (Get-VideoArgs 20) + @('-movflags', '+faststart', $out)) ($sorted.Count * $sec)
    Remove-Item -LiteralPath $list -ErrorAction SilentlyContinue
    if ($script:cancelled -or $code -ne 0 -or -not (Test-Path -LiteralPath $out)) {
        Start-Sleep -Milliseconds 300
        Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue
        if (-not $script:cancelled) { Write-Host 'Error - the sources are untouched' -ForegroundColor Red }
        Finish 0 1 @($first)
    } else { $script:lastOutput = $out; Finish 1 1 @() }
    return
}

# Join: all selected files in alphabetical order into one, without re-encoding
if ($Preset -eq 'concat') {
    $sorted = @($Files | Sort-Object)
    $first = $sorted[0]
    $ext = [IO.Path]::GetExtension($first).TrimStart('.').ToLower()
    $out = Get-FreePath (Get-OutDir ([IO.Path]::GetDirectoryName($first))) "$([IO.Path]::GetFileNameWithoutExtension($first)) (joined)" $ext
    $list = Join-Path $env:TEMP "ffmpeg-concat-$PID.txt"
    $bs = [string][char]92
    # In the ffmpeg list the path is in single quotes; an apostrophe inside is written as '\''
    $lines = $sorted | ForEach-Object { "file '" + ($_.Replace($bs, '/').Replace("'", "'" + $bs + "''")) + "'" }
    [IO.File]::WriteAllLines($list, [string[]]$lines, (New-Object Text.UTF8Encoding $false))
    Write-Host ''
    Write-Host "Joining $($sorted.Count) files  ->  $([IO.Path]::GetFileName($out))" -ForegroundColor White
    $sorted | ForEach-Object { Write-Host "  $([IO.Path]::GetFileName($_))" }
    $total = 0.0
    foreach ($f in $sorted) { try { $total += Get-Duration $f } catch { } }
    $code = Invoke-FFmpeg @('-n', '-f', 'concat', '-safe', '0', '-i', $list, '-map', '0', '-c', 'copy', $out) $total
    Remove-Item -LiteralPath $list -ErrorAction SilentlyContinue
    if ($script:cancelled) {
        Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue
        Write-Host 'The unfinished file is deleted, the sources are untouched.' -ForegroundColor Yellow
        Finish 0 1 @()
        return
    }
    if ($code -ne 0 -or -not (Test-Path -LiteralPath $out)) {
        Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue
        Write-Host 'Error: the files probably have different parameters (codec, resolution, frame rate). Convert them to one format first.' -ForegroundColor Red
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
            Write-Host "[$i/$n] $base.$srcExt — skipped: $base.$ext already exists next to it" -ForegroundColor Yellow
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
            # these operations create (and on cancel remove) their own files
            if ($script:cancelled) {
                Write-Host 'Cancelled, unfinished files deleted, the source is untouched.' -ForegroundColor Yellow
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
            Write-Host '  Pass 1 of 2 (analysis)' -ForegroundColor DarkGray
            $code = Invoke-FFmpeg (@('-y') + @($job.InArgs) + @('-i', $src) + @($job.Pass1) + @('-')) $total
            if ($code -eq 0) { Write-Host '  Pass 2 of 2 (encoding)' -ForegroundColor DarkGray }
        }
        if ($code -eq 0) {
            $code = Invoke-FFmpeg (@('-n') + @($job.InArgs) + @('-i', $src) + @($job.Args) + @($out)) $total
        }
    }
    Remove-PassLogs
    if ($script:cancelled) {
        Start-Sleep -Milliseconds 300   # let ffmpeg release the file
        Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue
        Write-Host 'The unfinished file is deleted, the source is untouched.' -ForegroundColor Yellow
        if ($i -lt $n) { Write-Host "The remaining files ($($n - $i)) were not processed." -ForegroundColor Yellow }
        break
    }
    if ($code -ne 0 -or -not (Test-Path -LiteralPath $out)) {
        Remove-Item -LiteralPath $out -ErrorAction SilentlyContinue
        Write-Host 'Error - the source is untouched' -ForegroundColor Red
        $failed += $src
        continue
    }
    if ($replace) {
        try { Send-ToRecycleBin $src }
        catch {
            # The source is busy (open in a player, for example) - the result keeps its temporary name
            Write-Host "Could not move the source to the Recycle Bin, the result is saved as $([IO.Path]::GetFileName($out))" -ForegroundColor Red
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
