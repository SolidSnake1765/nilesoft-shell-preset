# Инструменты для контекстного меню Nilesoft Shell (imports/tools.nss):
# хэш, переименование, выделение, ссылка на файл, образы дисков, питание, поиск в Everything.
#
# Пример: powershell -File tools-run.ps1 -Action hash-copy -Value SHA256 <файлы...>

# PositionalBinding off: otherwise the first file would land in -Value when it is omitted
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true)][string]$Action,
    [string]$Value = '',
    [string]$Hwnd = '',          # окно проводника — для выделения
    [string]$Folder = '',        # папка этого окна (по ней выбирается нужная вкладка)
    [string]$Everything = '',    # путь к everything.exe
    [switch]$NoPause,            # for tests: do not wait at the end
    [string]$Answer = '',        # for tests: ответ вместо ввода с клавиатуры
    [string]$TestUploadUrl = '', # for tests: адрес поддельного сервера вместо temp.sh/uguu.se
    [int]$TestPopupSeconds = 0,  # for tests: окно подтверждения само закроется через N секунд
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Files
)

Set-Location -LiteralPath $env:TEMP
# Корень диска приходит как «D:\"» и обратная черта съедает кавычку — чиним: «D:» -> «D:\»
$Files = @($Files | Where-Object { $_ } | ForEach-Object { $x = $_.TrimEnd('"'); if ($x -match '^[A-Za-z]:$') { $x += [string][char]92 }; $x })
[Console]::OutputEncoding = [Text.Encoding]::UTF8
try { $Host.UI.RawUI.WindowTitle = "Инструменты: $Action" } catch { }
$bs = [string][char]92
$undoFile = Join-Path $env:LOCALAPPDATA 'Nilesoft-tools-rename-undo.json'

function Done([bool]$ok, [int]$delay = 2) {
    if ($NoPause) { return }
    if ($ok) { Start-Sleep -Seconds $delay } else { Read-Host 'Нажми Enter, чтобы закрыть' | Out-Null }
}

# Ввод с клавиатуры (в тестах ответ приходит в -Answer)
function Ask([string]$label) {
    if ($Answer) { Write-Host "$label`: $Answer"; return $Answer }
    return Read-Host $label
}

# Окно-вопрос «Да / Нет» (для действий из меню без консоли): поверх всех окон, по умолчанию «Нет».
# Флаги MessageBox: 4 — Да/Нет, 48 — значок «!», 256 — кнопка по умолчанию вторая, 262144 — поверх всех окон
function Confirm-Box([string]$text, [string]$title) {
    if ($Answer) { return ($Answer -eq 'yes') }
    $r = (New-Object -ComObject WScript.Shell).Popup($text, $TestPopupSeconds, $title, 4 + 48 + 256 + 262144)
    return ($r -eq 6)   # 6 — «Да», 7 — «Нет», -1 — окно закрылось по тайм-ауту
}

# Окно ввода текста (для выделения по маске — там консоль скрыта)
function Ask-Box([string]$text, [string]$title, [string]$default) {
    if ($Answer) { return $Answer }
    Add-Type -AssemblyName Microsoft.VisualBasic
    return [Microsoft.VisualBasic.Interaction]::InputBox($text, $title, $default)
}

# Все файлы из выбора: файлы как есть, папки — со всем содержимым
function Expand-Files([string[]]$paths) {
    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p -PathType Container) { Get-ChildItem -LiteralPath $p -File -Recurse | ForEach-Object FullName }
        elseif (Test-Path -LiteralPath $p) { $p }
    }
}

function Get-Hash([string]$path, [string]$alg) {
    return (Get-FileHash -LiteralPath $path -Algorithm $alg).Hash.ToLower()
}

# ---------- Хэш ----------
function Invoke-Hash {
    $algs = @{ 32 = 'MD5'; 40 = 'SHA1'; 64 = 'SHA256'; 96 = 'SHA384'; 128 = 'SHA512' }
    switch ($Action) {
        'hash-show' {
            $last = @{}
            foreach ($f in $Files) {
                Write-Host ''
                Write-Host ([IO.Path]::GetFileName($f)) -ForegroundColor White
                foreach ($a in 'MD5', 'SHA1', 'SHA256') {
                    $h = Get-Hash $f $a
                    $last[$a] = $h
                    Write-Host ('  {0,-7} {1}' -f $a, $h)
                }
            }
            if ($Files.Count -eq 1 -and -not $NoPause) {
                Write-Host ''
                Write-Host '1 — скопировать MD5, 2 — SHA1, 3 — SHA256, любая другая клавиша — закрыть' -ForegroundColor DarkGray
                $k = [Console]::ReadKey($true).KeyChar
                $pick = @{ '1' = 'MD5'; '2' = 'SHA1'; '3' = 'SHA256' }["$k"]
                if ($pick) { Set-Clipboard -Value $last[$pick]; Write-Host "$pick скопирован" -ForegroundColor Green; Start-Sleep -Seconds 1 }
                return $true
            }
            return $true
        }
        'hash-copy' {
            $f = $Files[0]
            Write-Host "Считаю $Value для $([IO.Path]::GetFileName($f))…"
            $h = Get-Hash $f $Value
            Set-Clipboard -Value $h
            Write-Host $h
            Write-Host 'Скопировано в буфер обмена' -ForegroundColor Green
            return $true
        }
        'hash-verify' {
            $f = $Files[0]
            $expected = ''
            $clip = "$(Get-Clipboard -ErrorAction SilentlyContinue)".Trim()
            if (-not $Answer -and $clip -match '^[0-9a-fA-F]+$' -and $algs.ContainsKey($clip.Length)) {
                $expected = $clip
                Write-Host "В буфере обмена найден хэш $($algs[$clip.Length]) — сверяю с ним"
            } else {
                $expected = (Ask 'Вставь эталонный хэш (MD5, SHA1, SHA256, SHA384 или SHA512)').Trim()
            }
            $expected = $expected.Replace(' ', '')
            if ($expected -notmatch '^[0-9a-fA-F]+$' -or -not $algs.ContainsKey($expected.Length)) {
                Write-Host 'Это не похоже на хэш: нужно 32, 40, 64, 96 или 128 шестнадцатеричных символов' -ForegroundColor Red
                return $false
            }
            $alg = $algs[$expected.Length]
            Write-Host "Считаю $alg для $([IO.Path]::GetFileName($f))…"
            $h = Get-Hash $f $alg
            Write-Host "  файл:    $h"
            Write-Host "  эталон:  $($expected.ToLower())"
            if ($h -eq $expected.ToLower()) { Write-Host 'СОВПАДАЕТ — файл целый и именно тот' -ForegroundColor Green; return $true }
            Write-Host 'НЕ СОВПАДАЕТ — файл повреждён или это другой файл' -ForegroundColor Red
            return $false
        }
        'hash-compare' {
            Write-Host 'Сравниваю по SHA256…'
            $a = Get-Hash $Files[0] 'SHA256'
            $b = Get-Hash $Files[1] 'SHA256'
            Write-Host "  $([IO.Path]::GetFileName($Files[0])):  $a"
            Write-Host "  $([IO.Path]::GetFileName($Files[1])):  $b"
            if ($a -eq $b) { Write-Host 'Файлы ОДИНАКОВЫЕ' -ForegroundColor Green; return $true }
            Write-Host 'Файлы РАЗНЫЕ' -ForegroundColor Yellow
            return $true
        }
        'hash-create' {
            # Файл в формате sha256sum: «хэш *относительный_путь», рядом с первым выбранным
            $first = $Files[0]
            $root = [IO.Path]::GetDirectoryName($first)
            $out = Join-Path $root 'checksums.sha256'
            $k = 2
            while (Test-Path -LiteralPath $out) { $out = Join-Path $root "checksums ($k).sha256"; $k++ }
            $list = @(Expand-Files $Files | Where-Object { $_ -ne $out } | Sort-Object)
            $lines = @()
            $i = 0
            foreach ($f in $list) {
                $i++
                Write-Host ("[{0}/{1}] {2}" -f $i, $list.Count, $f.Substring($root.Length + 1))
                $lines += (Get-Hash $f 'SHA256') + ' *' + $f.Substring($root.Length + 1)
            }
            [IO.File]::WriteAllLines($out, [string[]]$lines, (New-Object Text.UTF8Encoding $false))
            Write-Host "Готово: $($list.Count) файлов  ->  $([IO.Path]::GetFileName($out))" -ForegroundColor Green
            return $true
        }
        'hash-check' {
            $sumFile = $Files[0]
            $alg = @{ '.md5' = 'MD5'; '.sha1' = 'SHA1'; '.sha256' = 'SHA256'; '.sha384' = 'SHA384'; '.sha512' = 'SHA512' }[[IO.Path]::GetExtension($sumFile).ToLower()]
            $root = [IO.Path]::GetDirectoryName($sumFile)
            $good = 0; $bad = 0; $missing = 0
            foreach ($line in [IO.File]::ReadAllLines($sumFile)) {
                $m = [regex]::Match($line, '^([0-9a-fA-F]{32,128})\s+\*?(.+)$')
                if (-not $m.Success) { continue }
                $name = $m.Groups[2].Value.Trim().Replace('/', $bs)
                $path = $name
                if (-not [IO.Path]::IsPathRooted($name)) { $path = Join-Path $root $name }
                $a = $alg
                if (-not $a) { $a = $algs[$m.Groups[1].Value.Length] }
                if (-not (Test-Path -LiteralPath $path)) { Write-Host "  НЕТ ФАЙЛА   $name" -ForegroundColor Yellow; $missing++; continue }
                if ((Get-Hash $path $a) -eq $m.Groups[1].Value.ToLower()) { Write-Host "  OK          $name" -ForegroundColor Green; $good++ }
                else { Write-Host "  ПОВРЕЖДЁН   $name" -ForegroundColor Red; $bad++ }
            }
            Write-Host ''
            Write-Host "Целых: $good, повреждённых: $bad, не найдено: $missing"
            return ($bad -eq 0 -and $missing -eq 0)
        }
    }
}

# ---------- Переименование ----------
function Get-NewName([string]$path, [int]$index, [int]$count) {
    $isDir = Test-Path -LiteralPath $path -PathType Container
    $name = [IO.Path]::GetFileName($path)
    $base = $name; $ext = ''
    if (-not $isDir) { $base = [IO.Path]::GetFileNameWithoutExtension($path); $ext = [IO.Path]::GetExtension($path) }
    $ti = (Get-Culture).TextInfo
    switch ($Value) {
        'lower'       { $base = $base.ToLower(); $ext = $ext.ToLower() }
        'upper'       { $base = $base.ToUpper() }
        'sentence'    { $b = $base.ToLower(); if ($b) { $base = $b.Substring(0, 1).ToUpper() + $b.Substring(1) } }
        'title'       { $base = $ti.ToTitleCase($base.ToLower()) }
        'space2under' { $base = $base.Replace(' ', '_') }
        'under2space' { $base = $base.Replace('_', ' ') }
        'dot2space'   { $base = $base.Replace('.', ' ') }
        'spaces'      { $base = ([regex]::Replace($base, ' {2,}', ' ')).Trim() }
        'prefix'      { $base = $script:text1 + $base }
        'suffix'      { $base = $base + $script:text1 }
        # без учёта регистра: «IMG_» найдёт и «Img_»
        'replace'     { $base = [regex]::Replace($base, [regex]::Escape($script:text1), { param($m) $script:text2 }, 'IgnoreCase') }
        'number'      { $base = $script:text1 + ' ' + ([string]($index + 1)).PadLeft([math]::Max(2, ([string]$count).Length), '0') }
        'ext'         { if (-not $isDir) { $ext = '.' + $script:text1.TrimStart('.') } }
    }
    return $base + $ext
}

function Invoke-Rename {
    if ($Action -eq 'rename-undo') {
        if (-not (Test-Path -LiteralPath $undoFile)) { Write-Host 'Отменять нечего: последнее переименование уже отменено или его не было' -ForegroundColor Yellow; return $false }
        # без @(): Windows PowerShell отдаёт JSON-массив одним объектом, и @() обернул бы его ещё раз
        $pairs = Get-Content -LiteralPath $undoFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $n = 0
        foreach ($p in $pairs) {
            if (-not (Test-Path -LiteralPath $p.to)) { Write-Host "  уже нет: $([IO.Path]::GetFileName($p.to))" -ForegroundColor Yellow; continue }
            try {
                Rename-Safe $p.to ([IO.Path]::GetFileName($p.from))
                Write-Host "  $([IO.Path]::GetFileName($p.to))  ->  $([IO.Path]::GetFileName($p.from))"
                $n++
            } catch { Write-Host "  Не удалось: $([IO.Path]::GetFileName($p.to)) — $($_.Exception.Message)" -ForegroundColor Red }
        }
        Remove-Item -LiteralPath $undoFile
        Write-Host "Возвращено имён: $n" -ForegroundColor Green
        return $true
    }
    # Нужный текст спрашиваем один раз до предпросмотра
    $script:text1 = ''; $script:text2 = ''
    switch ($Value) {
        'prefix'  { $script:text1 = Ask 'Что добавить в начало имени' }
        'suffix'  { $script:text1 = Ask 'Что добавить в конец имени (перед расширением)' }
        'replace' {
            $parts = (Ask 'Что заменить и на что, через |  (например: IMG_|Фото )') -split '\|', 2
            $script:text1 = $parts[0]; $script:text2 = ''
            if ($parts.Count -gt 1) { $script:text2 = $parts[1] }
            if (-not $script:text1) { Write-Host 'Не указано, что заменять' -ForegroundColor Red; return $false }
        }
        'number'  { $script:text1 = Ask 'Общее имя (получится «Имя 01», «Имя 02»…)' }
        'ext'     { $script:text1 = Ask 'Новое расширение (например jpg)' }
    }
    if ($Value -in @('prefix', 'suffix', 'number', 'ext') -and -not $script:text1) { Write-Host 'Ничего не введено' -ForegroundColor Red; return $false }

    $list = @($Files | Sort-Object)
    $plan = @()
    $taken = @{}
    for ($i = 0; $i -lt $list.Count; $i++) {
        $src = $list[$i]
        $new = Get-NewName $src $i $list.Count
        $dst = Join-Path ([IO.Path]::GetDirectoryName($src)) $new
        if ($new -ceq [IO.Path]::GetFileName($src)) { continue }
        $problem = ''
        if ($new.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) { $problem = 'недопустимые символы' }
        elseif ($taken.ContainsKey($dst.ToLower())) { $problem = 'имя повторяется' }
        elseif ((Test-Path -LiteralPath $dst) -and ($dst.ToLower() -ne $src.ToLower())) { $problem = 'такой файл уже есть' }
        $taken[$dst.ToLower()] = $true
        $plan += [pscustomobject]@{ From = $src; To = $dst; Problem = $problem }
    }
    if ($plan.Count -eq 0) { Write-Host 'Имена уже такие — менять нечего' -ForegroundColor Yellow; return $true }

    Write-Host ''
    $shown = 0
    foreach ($p in $plan) {
        if ($shown -ge 40) { Write-Host "  …и ещё $($plan.Count - $shown)"; break }
        $line = "  $([IO.Path]::GetFileName($p.From))  ->  $([IO.Path]::GetFileName($p.To))"
        if ($p.Problem) { Write-Host "$line   (пропущу: $($p.Problem))" -ForegroundColor Yellow } else { Write-Host $line }
        $shown++
    }
    $ok = @($plan | Where-Object { -not $_.Problem })
    Write-Host ''
    if ($ok.Count -eq 0) { Write-Host 'Переименовать нечего' -ForegroundColor Red; return $false }
    if (-not $NoPause -or $Answer) {
        $go = $true
        if ($Answer) { $go = $true }
        else {
            Write-Host "Enter — переименовать ($($ok.Count)), Esc — отмена" -ForegroundColor Cyan
            while ($true) {
                $k = [Console]::ReadKey($true).Key
                if ($k -eq 'Enter') { break }
                if ($k -eq 'Escape') { $go = $false; break }
            }
        }
        if (-not $go) { Write-Host 'Отменено, ничего не переименовано' -ForegroundColor Yellow; return $true }
    }
    $done = @()
    foreach ($p in $ok) {
        try { Rename-Safe $p.From ([IO.Path]::GetFileName($p.To)); $done += @{ from = $p.From; to = $p.To } }
        catch { Write-Host "  Не удалось: $([IO.Path]::GetFileName($p.From)) — $($_.Exception.Message)" -ForegroundColor Red }
    }
    ConvertTo-Json -InputObject @($done) | Set-Content -LiteralPath $undoFile -Encoding UTF8
    Write-Host "Переименовано: $($done.Count). Отменить можно пунктом «Отменить последнее переименование»" -ForegroundColor Green
    return ($done.Count -eq $ok.Count)
}

# Переименование, которое работает и когда меняется только регистр букв
function Rename-Safe([string]$path, [string]$newName) {
    if ([IO.Path]::GetFileName($path).ToLower() -eq $newName.ToLower()) {
        $tmp = "$newName.rename-tmp-$PID"
        Rename-Item -LiteralPath $path -NewName $tmp
        Rename-Item -LiteralPath (Join-Path ([IO.Path]::GetDirectoryName($path)) $tmp) -NewName $newName
    } else {
        Rename-Item -LiteralPath $path -NewName $newName
    }
}

# ---------- Выделение в окне проводника ----------
$typeExt = @{
    'video'   = @('.mp4', '.mkv', '.mov', '.avi', '.webm', '.m4v', '.ts', '.mts', '.m2ts', '.flv', '.wmv', '.mpg', '.mpeg', '.3gp', '.vob', '.ogv')
    'audio'   = @('.mp3', '.m4a', '.aac', '.flac', '.wav', '.ogg', '.opus', '.wma', '.ac3', '.dts', '.aiff', '.ape', '.wv', '.mka')
    'image'   = @('.jpg', '.jpeg', '.png', '.webp', '.avif', '.bmp', '.gif', '.tif', '.tiff', '.heic', '.ico', '.svg', '.psd', '.raw', '.cr2', '.nef', '.dng')
    'doc'     = @('.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.odt', '.ods', '.odp', '.rtf', '.txt', '.md', '.csv', '.epub', '.fb2', '.djvu')
    'archive' = @('.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz', '.zst', '.iso', '.cab')
}

# Окно проводника, из которого вызвано меню. Nilesoft может передать как главное окно, так и
# внутреннюю панель со списком файлов — поднимаемся до главного. У вкладок Windows 11 главное
# окно общее, поэтому нужную вкладку выбираем по папке.
function Find-ExplorerWindow {
Add-Type -Namespace NsTools -Name Win -MemberDefinition @'
[DllImport("user32.dll")] public static extern System.IntPtr GetAncestor(System.IntPtr hwnd, uint flags);
[DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
'@ -ErrorAction SilentlyContinue
    $root = [IntPtr]::Zero
    $h = $Hwnd.Trim()
    $num = [int64]0
    if ($h -match '^0x[0-9a-fA-F]+$') { $num = [Convert]::ToInt64($h.Substring(2), 16) }
    elseif ($h -match '^[0-9]+$') { $num = [int64]$h }
    if ($num) { $root = [NsTools.Win]::GetAncestor([IntPtr]$num, 2) }          # 2 = GA_ROOT
    $fg = [NsTools.Win]::GetAncestor([NsTools.Win]::GetForegroundWindow(), 2)
    $want = ''
    if ($Folder) { try { $want = [IO.Path]::GetFullPath($Folder).TrimEnd([char]92).ToLower() } catch { } }
    $all = @()
    foreach ($w in (New-Object -ComObject Shell.Application).Windows()) {
        $path = ''
        try { $path = "$($w.Document.Folder.Self.Path)".TrimEnd([char]92).ToLower() } catch { continue }
        $all += [pscustomobject]@{ Win = $w; Hwnd = [int64]$w.HWND; Path = $path }
    }
    $byRoot = @($all | Where-Object { $_.Hwnd -eq [int64]$root })
    $pick = $byRoot | Where-Object { $want -and $_.Path -eq $want } | Select-Object -First 1
    if (-not $pick -and $byRoot.Count -eq 1) { $pick = $byRoot[0] }
    if (-not $pick) {
        $byPath = @($all | Where-Object { $want -and $_.Path -eq $want })
        $pick = $byPath | Where-Object { $_.Hwnd -eq [int64]$fg } | Select-Object -First 1
        if (-not $pick -and $byPath.Count) { $pick = $byPath[0] }
    }
    if ($pick) { return $pick.Win }
    return $null
}

function Invoke-Select {
    $win = Find-ExplorerWindow
    if (-not $win) { return $false }
    $mask = ''
    if ($Value -eq 'mask') {
        $mask = Ask-Box 'Маска имени: * — любые символы, ? — один символ. Например *2024* или IMG_*.jpg' 'Выделить по маске' '*'
        if (-not $mask) { return $true }
    }
    $sameExt = ''
    if ($Value -eq 'sameext' -and $Files.Count) { $sameExt = [IO.Path]::GetExtension($Files[0]).ToLower() }
    $now = Get-Date
    $first = $true
    foreach ($it in @($win.Document.Folder.Items())) {
        $ext = [IO.Path]::GetExtension("$($it.Path)").ToLower()
        $isDir = $it.IsFolder -and -not ($ext -in @('.zip', '.cab'))
        $hit = switch ($Value) {
            'folders' { $isDir }
            'files'   { -not $isDir }
            'big100'  { -not $isDir -and $it.Size -gt 100MB }
            'big1g'   { -not $isDir -and $it.Size -gt 1GB }
            'empty'   { -not $isDir -and $it.Size -eq 0 }
            'today'   { $it.ModifyDate.Date -eq $now.Date }
            'week'    { $it.ModifyDate -gt $now.AddDays(-7) }
            'old'     { $it.ModifyDate -lt $now.AddMonths(-6) }
            'sameext' { -not $isDir -and $ext -eq $sameExt }
            'mask'    { $it.Name -like $mask -or [IO.Path]::GetFileName("$($it.Path)") -like $mask }
            default   { -not $isDir -and $typeExt[$Value] -contains $ext }
        }
        if ($hit) {
            # 1 — выделить; для первого ещё 4 (снять остальное) и 8 (фокус)
            $flag = 1
            if ($first) { $flag = 1 + 4 + 8; $first = $false }
            $win.Document.SelectItem($it, $flag)
        }
    }
    if ($first) { foreach ($it in @($win.Document.SelectedItems())) { $win.Document.SelectItem($it, 0) } }
    return $true
}

# ---------- Ссылка на файл ----------
function Invoke-Upload {
    $f = $Files[0]
    $size = (Get-Item -LiteralPath $f).Length
    $svc = @{
        'tempsh' = @{ Url = 'https://temp.sh/upload'; Field = 'file'; Limit = 4GB; Name = 'temp.sh'; Keep = '3 дня' }
        'uguu'   = @{ Url = 'https://uguu.se/upload'; Field = 'files[]'; Limit = 128MB; Name = 'uguu.se'; Keep = '3 часа' }
    }[$Value]
    if ($TestUploadUrl) { $svc.Url = $TestUploadUrl }
    if ($size -gt $svc.Limit) {
        Write-Host "Файл весит $([math]::Round($size / 1MB)) МБ — это больше лимита $($svc.Name)" -ForegroundColor Red
        return $false
    }
    $sizeText = "$([math]::Round($size / 1MB, 1)) МБ"
    if ($size -lt 1MB) { $sizeText = "$([math]::Ceiling($size / 1KB)) КБ" }
    Write-Host "Загружаю $([IO.Path]::GetFileName($f)) ($sizeText) на $($svc.Name), файл будет доступен $($svc.Keep)…"
    # curl в -F не понимает «;» и «,» в пути, а кавычки PowerShell 5.1 передаёт криво —
    # такие файлы временно копируются под безопасным именем
    $send = $f
    $tmp = ''
    if ([IO.Path]::GetFileName($f).IndexOfAny([char[]]';,"') -ge 0) {
        $safe = [regex]::Replace([IO.Path]::GetFileName($f), '[;,"]', '_')
        # копия в отдельной временной папке, чтобы получатель видел обычное имя файла
        $tmp = Join-Path $env:TEMP "upload-$PID"
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $send = Join-Path $tmp $safe
        Copy-Item -LiteralPath $f -Destination $send
    }
    try { $resp = & curl.exe --progress-bar --fail -F "$($svc.Field)=@$send" $svc.Url }
    finally { if ($tmp) { Remove-Item -LiteralPath $tmp -Recurse -ErrorAction SilentlyContinue } }
    if ($LASTEXITCODE -ne 0 -or -not $resp) { Write-Host 'Не удалось загрузить (нет интернета или сервис недоступен)' -ForegroundColor Red; return $false }
    $text = ($resp -join '').Trim()
    $link = $text
    if ($text.StartsWith('{')) { try { $link = ($text | ConvertFrom-Json).files[0].url } catch { } }
    if ($link -notmatch '^https?://') { Write-Host "Сервис ответил неожиданно: $text" -ForegroundColor Red; return $false }
    Set-Clipboard -Value $link
    Write-Host ''
    Write-Host $link -ForegroundColor White
    Write-Host 'Ссылка скопирована в буфер обмена' -ForegroundColor Green
    return $true
}

# ---------- Образы дисков ----------
function Invoke-Image {
    switch ($Action) {
        'iso-mount' {
            $img = Mount-DiskImage -ImagePath $Files[0] -PassThru
            $letter = ($img | Get-Volume).DriveLetter
            if ($letter) { Write-Host "Подключено как диск $letter`:" -ForegroundColor Green; if (-not $NoPause) { Start-Process explorer.exe "$letter`:$bs" } }
            return $true
        }
        'iso-unmount' { Dismount-DiskImage -ImagePath $Files[0] | Out-Null; Write-Host 'Образ отключён' -ForegroundColor Green; return $true }
        'iso-eject' {
            $img = Get-Volume -DriveLetter $Value | Get-DiskImage
            if (-not $img) { Write-Host 'Это не подключённый образ' -ForegroundColor Red; return $false }
            Dismount-DiskImage -ImagePath $img.ImagePath | Out-Null
            Write-Host "Образ $([IO.Path]::GetFileName($img.ImagePath)) отключён" -ForegroundColor Green
            return $true
        }
    }
}

# ---------- Питание ----------
function Invoke-Power {
    $ask = @{
        'restart'  = 'Перезагрузить компьютер сейчас? Несохранённая работа пропадёт.'
        'shutdown' = 'Выключить компьютер сейчас? Несохранённая работа пропадёт.'
        'bios'     = 'Перезагрузиться сразу в BIOS/UEFI?'
        'advanced' = 'Перезагрузиться в особые варианты загрузки (восстановление, безопасный режим)?'
        'logoff'   = 'Выйти из учётной записи? Все программы закроются.'
        'test'     = 'Проверка окна подтверждения: после ответа ничего не произойдёт.'   # for tests
    }
    if ($ask.ContainsKey($Value) -and -not (Confirm-Box $ask[$Value] 'Питание')) { return $true }
    switch -Regex ($Value) {
        '^lock$'      { & rundll32.exe user32.dll, LockWorkStation }
        # SetSuspendState через .NET: rundll32 при включённой гибернации вместо сна гибернирует
        '^sleep$'     { Add-Type -AssemblyName System.Windows.Forms; [void][Windows.Forms.Application]::SetSuspendState('Suspend', $false, $false) }
        '^hibernate$' { & shutdown.exe /h }
        '^restart$'   { & shutdown.exe /r /t 0 }
        '^shutdown$'  { & shutdown.exe /s /t 0 }
        '^bios$'      { Start-Process shutdown.exe -ArgumentList '/r /fw /t 0' -Verb RunAs -WindowStyle Hidden }
        '^advanced$'  { Start-Process shutdown.exe -ArgumentList '/r /o /t 0' -Verb RunAs -WindowStyle Hidden }
        '^logoff$'    { & shutdown.exe /l }
        '^timer-cancel$' { & shutdown.exe /a 2>$null }
        '^timer-[0-9]+$' { & shutdown.exe /s /t ([int]$Value.Substring(6) * 60) }
    }
    return $true
}

# ---------- Поиск в Everything ----------
# У Everything свой разбор командной строки: кавычки просто открывают и закрывают текст,
# обратная черта — обычный символ. Поэтому папку передаём через -p "…", фильтр через -search "…",
# и Everything сам собирает запрос вида "D:\Видео\" video:
function Invoke-Everything {
    $p = $Files[0]
    $isDir = Test-Path -LiteralPath $p -PathType Container
    $folder = $p
    if (-not $isDir) { $folder = [IO.Path]::GetDirectoryName($p) }
    $here = '-p "' + $folder + '"'
    $ext = [IO.Path]::GetExtension($p).TrimStart('.')
    $argLine = switch ($Value) {
        'here'       { $here }
        'drive'      { '-p "' + [IO.Path]::GetPathRoot($p) + '"' }
        'sameext'    { $here + ' -search "ext:' + $ext + '"' }
        'sameextall' { '-search "ext:' + $ext + '"' }
        'samename'   { '-name-part "' + [IO.Path]::GetFileName($p) + '"' }   # nopath:wfn:"имя"
        'big100'     { $here + ' -search "size:>100mb"' }
        'big1g'      { $here + ' -search "size:>1gb"' }
        'big1gall'   { '-search "size:>1gb"' }
        'today'      { $here + ' -search "dm:today"' }
        'week'       { $here + ' -search "dm:last7days"' }
        default      { $here + ' -search "' + $Value + ':"' }   # video:, pic:, audio:, doc:, zip:, exe:, folder:
    }
    Start-Process -FilePath $Everything -ArgumentList $argLine
    return $true
}

$result = $false
try {
    switch -Wildcard ($Action) {
        'hash-*'     { $result = Invoke-Hash }
        'rename-*'   { $result = Invoke-Rename }
        'select'     { $result = Invoke-Select; return }
        'upload'     { $result = Invoke-Upload }
        'iso-*'      { $result = Invoke-Image }
        'power'      { $result = Invoke-Power; return }
        'everything' { $result = Invoke-Everything; return }
        default      { Write-Host "Неизвестное действие: $Action" -ForegroundColor Red }
    }
} catch {
    Write-Host "Ошибка: $($_.Exception.Message)" -ForegroundColor Red
    $result = $false
}
Done ([bool]$result)
