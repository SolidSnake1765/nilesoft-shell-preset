# Tools for the Nilesoft Shell context menu (imports/tools.nss):
# hash, rename, select, file link, disk images, power, Everything search.
#
# Example: powershell -File tools-run.ps1 -Action hash-copy -Value SHA256 <files...>

# PositionalBinding off: otherwise the first file would land in -Value when it is omitted
[CmdletBinding(PositionalBinding = $false)]
param(
    [Parameter(Mandatory = $true)][string]$Action,
    [string]$Value = '',
    [string]$Hwnd = '',          # Explorer window - for selecting
    [string]$Folder = '',        # folder of that window (used to pick the right tab)
    [string]$Everything = '',    # path to everything.exe
    [switch]$NoPause,            # for tests: do not wait at the end
    [string]$Answer = '',        # for tests: answer instead of keyboard input
    [string]$TestUploadUrl = '', # for tests: address of a fake server instead of temp.sh/uguu.se
    [int]$TestPopupSeconds = 0,  # for tests: the confirmation window closes itself after N seconds
    [Parameter(ValueFromRemainingArguments = $true)][string[]]$Files
)

Set-Location -LiteralPath $env:TEMP
# A drive root arrives as ‹D:\"› and the backslash eats the quote - fix it: ‹D:› -> ‹D:\›
$Files = @($Files | Where-Object { $_ } | ForEach-Object { $x = $_.TrimEnd('"'); if ($x -match '^[A-Za-z]:$') { $x += [string][char]92 }; $x })
[Console]::OutputEncoding = [Text.Encoding]::UTF8
try { $Host.UI.RawUI.WindowTitle = "Tools: $Action" } catch { }
$bs = [string][char]92
$undoFile = Join-Path $env:LOCALAPPDATA 'Nilesoft-tools-rename-undo.json'

function Done([bool]$ok, [int]$delay = 2) {
    if ($NoPause) { return }
    if ($ok) { Start-Sleep -Seconds $delay } else { Read-Host 'Press Enter to close' | Out-Null }
}

# Keyboard input (in tests the answer comes in -Answer)
function Ask([string]$label) {
    if ($Answer) { Write-Host "$label`: $Answer"; return $Answer }
    return Read-Host $label
}

# A Yes / No question window (for menu actions without a console): on top of all windows, ‹No› by default.
# MessageBox flags: 4 = Yes/No, 48 = ‹!› icon, 256 = second button is the default, 262144 = on top of all windows
function Confirm-Box([string]$text, [string]$title) {
    if ($Answer) { return ($Answer -eq 'yes') }
    $r = (New-Object -ComObject WScript.Shell).Popup($text, $TestPopupSeconds, $title, 4 + 48 + 256 + 262144)
    return ($r -eq 6)   # 6 — ‹Yes›, 7 = ‹No›, -1 = the window closed on timeout
}

# Text input window (for selecting by mask - the console is hidden there)
function Ask-Box([string]$text, [string]$title, [string]$default) {
    if ($Answer) { return $Answer }
    Add-Type -AssemblyName Microsoft.VisualBasic
    return [Microsoft.VisualBasic.Interaction]::InputBox($text, $title, $default)
}

# All files of the selection: files as is, folders with all their contents
function Expand-Files([string[]]$paths) {
    foreach ($p in $paths) {
        if (Test-Path -LiteralPath $p -PathType Container) { Get-ChildItem -LiteralPath $p -File -Recurse | ForEach-Object FullName }
        elseif (Test-Path -LiteralPath $p) { $p }
    }
}

function Get-Hash([string]$path, [string]$alg) {
    return (Get-FileHash -LiteralPath $path -Algorithm $alg).Hash.ToLower()
}

# ---------- Hash ----------
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
                Write-Host '1 — copy MD5, 2 = SHA1, 3 = SHA256, any other key = close' -ForegroundColor DarkGray
                $k = [Console]::ReadKey($true).KeyChar
                $pick = @{ '1' = 'MD5'; '2' = 'SHA1'; '3' = 'SHA256' }["$k"]
                if ($pick) { Set-Clipboard -Value $last[$pick]; Write-Host "$pick copied" -ForegroundColor Green; Start-Sleep -Seconds 1 }
                return $true
            }
            return $true
        }
        'hash-copy' {
            $f = $Files[0]
            Write-Host "Computing $Value for $([IO.Path]::GetFileName($f))…"
            $h = Get-Hash $f $Value
            Set-Clipboard -Value $h
            Write-Host $h
            Write-Host 'Copied to the clipboard' -ForegroundColor Green
            return $true
        }
        'hash-verify' {
            $f = $Files[0]
            $expected = ''
            $clip = "$(Get-Clipboard -ErrorAction SilentlyContinue)".Trim()
            if (-not $Answer -and $clip -match '^[0-9a-fA-F]+$' -and $algs.ContainsKey($clip.Length)) {
                $expected = $clip
                Write-Host "Found a $($algs[$clip.Length]) hash in the clipboard - comparing with it"
            } else {
                $expected = (Ask 'Paste the known hash (MD5, SHA1, SHA256, SHA384 or SHA512)').Trim()
            }
            $expected = $expected.Replace(' ', '')
            if ($expected -notmatch '^[0-9a-fA-F]+$' -or -not $algs.ContainsKey($expected.Length)) {
                Write-Host 'This does not look like a hash: 32, 40, 64, 96 or 128 hex characters are needed' -ForegroundColor Red
                return $false
            }
            $alg = $algs[$expected.Length]
            Write-Host "Computing $alg for $([IO.Path]::GetFileName($f))…"
            $h = Get-Hash $f $alg
            Write-Host "  file:      $h"
            Write-Host "  expected:  $($expected.ToLower())"
            if ($h -eq $expected.ToLower()) { Write-Host 'MATCH - the file is intact and the right one' -ForegroundColor Green; return $true }
            Write-Host 'NO MATCH - the file is damaged or it is a different file' -ForegroundColor Red
            return $false
        }
        'hash-compare' {
            Write-Host 'Comparing by SHA256…'
            $a = Get-Hash $Files[0] 'SHA256'
            $b = Get-Hash $Files[1] 'SHA256'
            Write-Host "  $([IO.Path]::GetFileName($Files[0])):  $a"
            Write-Host "  $([IO.Path]::GetFileName($Files[1])):  $b"
            if ($a -eq $b) { Write-Host 'The files are IDENTICAL' -ForegroundColor Green; return $true }
            Write-Host 'The files are DIFFERENT' -ForegroundColor Yellow
            return $true
        }
        'hash-create' {
            # A file in sha256sum format: ‹hash *relative_path›, next to the first selected one
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
            Write-Host "Done: $($list.Count) files  ->  $([IO.Path]::GetFileName($out))" -ForegroundColor Green
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
                if (-not (Test-Path -LiteralPath $path)) { Write-Host "  MISSING     $name" -ForegroundColor Yellow; $missing++; continue }
                if ((Get-Hash $path $a) -eq $m.Groups[1].Value.ToLower()) { Write-Host "  OK          $name" -ForegroundColor Green; $good++ }
                else { Write-Host "  DAMAGED     $name" -ForegroundColor Red; $bad++ }
            }
            Write-Host ''
            Write-Host "Intact: $good, damaged: $bad, missing: $missing"
            return ($bad -eq 0 -and $missing -eq 0)
        }
    }
}

# ---------- Rename ----------
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
        # case-insensitive: ‹IMG_› also finds ‹Img_›
        'replace'     { $base = [regex]::Replace($base, [regex]::Escape($script:text1), { param($m) $script:text2 }, 'IgnoreCase') }
        'number'      { $base = $script:text1 + ' ' + ([string]($index + 1)).PadLeft([math]::Max(2, ([string]$count).Length), '0') }
        'ext'         { if (-not $isDir) { $ext = '.' + $script:text1.TrimStart('.') } }
    }
    return $base + $ext
}

function Invoke-Rename {
    if ($Action -eq 'rename-undo') {
        if (-not (Test-Path -LiteralPath $undoFile)) { Write-Host 'Nothing to undo: the last rename was already undone or there was none' -ForegroundColor Yellow; return $false }
        # no @(): Windows PowerShell returns a JSON array as one object, and @() would wrap it again
        $pairs = Get-Content -LiteralPath $undoFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $n = 0
        foreach ($p in $pairs) {
            if (-not (Test-Path -LiteralPath $p.to)) { Write-Host "  gone: $([IO.Path]::GetFileName($p.to))" -ForegroundColor Yellow; continue }
            try {
                Rename-Safe $p.to ([IO.Path]::GetFileName($p.from))
                Write-Host "  $([IO.Path]::GetFileName($p.to))  ->  $([IO.Path]::GetFileName($p.from))"
                $n++
            } catch { Write-Host "  Failed: $([IO.Path]::GetFileName($p.to)) - $($_.Exception.Message)" -ForegroundColor Red }
        }
        Remove-Item -LiteralPath $undoFile
        Write-Host "Names restored: $n" -ForegroundColor Green
        return $true
    }
    # The needed text is asked once before the preview
    $script:text1 = ''; $script:text2 = ''
    switch ($Value) {
        'prefix'  { $script:text1 = Ask 'What to add to the start of the name' }
        'suffix'  { $script:text1 = Ask 'What to add to the end of the name (before the extension)' }
        'replace' {
            $parts = (Ask 'What to replace and with what, separated by |  (for example: IMG_|Photo )') -split '\|', 2
            $script:text1 = $parts[0]; $script:text2 = ''
            if ($parts.Count -gt 1) { $script:text2 = $parts[1] }
            if (-not $script:text1) { Write-Host 'Nothing to replace was given' -ForegroundColor Red; return $false }
        }
        'number'  { $script:text1 = Ask 'Common name (gives ‹Name 01›, ‹Name 02›…)' }
        'ext'     { $script:text1 = Ask 'New extension (for example jpg)' }
    }
    if ($Value -in @('prefix', 'suffix', 'number', 'ext') -and -not $script:text1) { Write-Host 'Nothing entered' -ForegroundColor Red; return $false }

    $list = @($Files | Sort-Object)
    $plan = @()
    $taken = @{}
    for ($i = 0; $i -lt $list.Count; $i++) {
        $src = $list[$i]
        $new = Get-NewName $src $i $list.Count
        $dst = Join-Path ([IO.Path]::GetDirectoryName($src)) $new
        if ($new -ceq [IO.Path]::GetFileName($src)) { continue }
        $problem = ''
        if ($new.IndexOfAny([IO.Path]::GetInvalidFileNameChars()) -ge 0) { $problem = 'invalid characters' }
        elseif ($taken.ContainsKey($dst.ToLower())) { $problem = 'duplicate name' }
        elseif ((Test-Path -LiteralPath $dst) -and ($dst.ToLower() -ne $src.ToLower())) { $problem = 'such a file already exists' }
        $taken[$dst.ToLower()] = $true
        $plan += [pscustomobject]@{ From = $src; To = $dst; Problem = $problem }
    }
    if ($plan.Count -eq 0) { Write-Host 'The names are already like that - nothing to change' -ForegroundColor Yellow; return $true }

    Write-Host ''
    $shown = 0
    foreach ($p in $plan) {
        if ($shown -ge 40) { Write-Host "  …and $($plan.Count - $shown) more"; break }
        $line = "  $([IO.Path]::GetFileName($p.From))  ->  $([IO.Path]::GetFileName($p.To))"
        if ($p.Problem) { Write-Host "$line   (will skip: $($p.Problem))" -ForegroundColor Yellow } else { Write-Host $line }
        $shown++
    }
    $ok = @($plan | Where-Object { -not $_.Problem })
    Write-Host ''
    if ($ok.Count -eq 0) { Write-Host 'Nothing to rename' -ForegroundColor Red; return $false }
    if (-not $NoPause -or $Answer) {
        $go = $true
        if ($Answer) { $go = $true }
        else {
            Write-Host "Enter — rename ($($ok.Count)), Esc = cancel" -ForegroundColor Cyan
            while ($true) {
                $k = [Console]::ReadKey($true).Key
                if ($k -eq 'Enter') { break }
                if ($k -eq 'Escape') { $go = $false; break }
            }
        }
        if (-not $go) { Write-Host 'Cancelled, nothing renamed' -ForegroundColor Yellow; return $true }
    }
    $done = @()
    foreach ($p in $ok) {
        try { Rename-Safe $p.From ([IO.Path]::GetFileName($p.To)); $done += @{ from = $p.From; to = $p.To } }
        catch { Write-Host "  Failed: $([IO.Path]::GetFileName($p.From)) - $($_.Exception.Message)" -ForegroundColor Red }
    }
    ConvertTo-Json -InputObject @($done) | Set-Content -LiteralPath $undoFile -Encoding UTF8
    Write-Host "Renamed: $($done.Count). Use ‹Undo last rename› to undo" -ForegroundColor Green
    return ($done.Count -eq $ok.Count)
}

# A rename that also works when only the letter case changes
function Rename-Safe([string]$path, [string]$newName) {
    if ([IO.Path]::GetFileName($path).ToLower() -eq $newName.ToLower()) {
        $tmp = "$newName.rename-tmp-$PID"
        Rename-Item -LiteralPath $path -NewName $tmp
        Rename-Item -LiteralPath (Join-Path ([IO.Path]::GetDirectoryName($path)) $tmp) -NewName $newName
    } else {
        Rename-Item -LiteralPath $path -NewName $newName
    }
}

# ---------- Selecting in the Explorer window ----------
$typeExt = @{
    'video'   = @('.mp4', '.mkv', '.mov', '.avi', '.webm', '.m4v', '.ts', '.mts', '.m2ts', '.flv', '.wmv', '.mpg', '.mpeg', '.3gp', '.vob', '.ogv')
    'audio'   = @('.mp3', '.m4a', '.aac', '.flac', '.wav', '.ogg', '.opus', '.wma', '.ac3', '.dts', '.aiff', '.ape', '.wv', '.mka')
    'image'   = @('.jpg', '.jpeg', '.png', '.webp', '.avif', '.bmp', '.gif', '.tif', '.tiff', '.heic', '.ico', '.svg', '.psd', '.raw', '.cr2', '.nef', '.dng')
    'doc'     = @('.pdf', '.doc', '.docx', '.xls', '.xlsx', '.ppt', '.pptx', '.odt', '.ods', '.odp', '.rtf', '.txt', '.md', '.csv', '.epub', '.fb2', '.djvu')
    'archive' = @('.zip', '.rar', '.7z', '.tar', '.gz', '.bz2', '.xz', '.zst', '.iso', '.cab')
}

# The Explorer window the menu was opened from. Nilesoft may pass either the main window or
# the inner file list pane - go up to the main one. Windows 11 tabs share one main
# window, so the right tab is picked by its folder.
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
        $mask = Ask-Box 'Name mask: * = any characters, ? = one character. For example *2024* or IMG_*.jpg' 'Select by mask' '*'
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
            # 1 — select; for the first one also 4 (deselect the rest) and 8 (focus)
            $flag = 1
            if ($first) { $flag = 1 + 4 + 8; $first = $false }
            $win.Document.SelectItem($it, $flag)
        }
    }
    if ($first) { foreach ($it in @($win.Document.SelectedItems())) { $win.Document.SelectItem($it, 0) } }
    return $true
}

# ---------- File link ----------
function Invoke-Upload {
    $f = $Files[0]
    $size = (Get-Item -LiteralPath $f).Length
    $svc = @{
        'tempsh' = @{ Url = 'https://temp.sh/upload'; Field = 'file'; Limit = 4GB; Name = 'temp.sh'; Keep = '3 days' }
        'uguu'   = @{ Url = 'https://uguu.se/upload'; Field = 'files[]'; Limit = 128MB; Name = 'uguu.se'; Keep = '3 hours' }
    }[$Value]
    if ($TestUploadUrl) { $svc.Url = $TestUploadUrl }
    if ($size -gt $svc.Limit) {
        Write-Host "The file is $([math]::Round($size / 1MB)) MB - over the $($svc.Name) limit" -ForegroundColor Red
        return $false
    }
    $sizeText = "$([math]::Round($size / 1MB, 1)) MB"
    if ($size -lt 1MB) { $sizeText = "$([math]::Ceiling($size / 1KB)) KB" }
    Write-Host "Uploading $([IO.Path]::GetFileName($f)) ($sizeText) to $($svc.Name), the file stays available for $($svc.Keep)…"
    # curl in -F does not understand ‹;› and ‹,› in a path, and PowerShell 5.1 passes quotes badly —
    # such files are temporarily copied under a safe name
    $send = $f
    $tmp = ''
    if ([IO.Path]::GetFileName($f).IndexOfAny([char[]]';,"') -ge 0) {
        $safe = [regex]::Replace([IO.Path]::GetFileName($f), '[;,"]', '_')
        # the copy is in its own temporary folder so the recipient sees the normal file name
        $tmp = Join-Path $env:TEMP "upload-$PID"
        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
        $send = Join-Path $tmp $safe
        Copy-Item -LiteralPath $f -Destination $send
    }
    try { $resp = & curl.exe --progress-bar --fail -F "$($svc.Field)=@$send" $svc.Url }
    finally { if ($tmp) { Remove-Item -LiteralPath $tmp -Recurse -ErrorAction SilentlyContinue } }
    if ($LASTEXITCODE -ne 0 -or -not $resp) { Write-Host 'Upload failed (no internet or the service is down)' -ForegroundColor Red; return $false }
    $text = ($resp -join '').Trim()
    $link = $text
    if ($text.StartsWith('{')) { try { $link = ($text | ConvertFrom-Json).files[0].url } catch { } }
    if ($link -notmatch '^https?://') { Write-Host "Unexpected answer from the service: $text" -ForegroundColor Red; return $false }
    Set-Clipboard -Value $link
    Write-Host ''
    Write-Host $link -ForegroundColor White
    Write-Host 'The link is copied to the clipboard' -ForegroundColor Green
    return $true
}

# ---------- Disk images ----------
function Invoke-Image {
    switch ($Action) {
        'iso-mount' {
            $img = Mount-DiskImage -ImagePath $Files[0] -PassThru
            $letter = ($img | Get-Volume).DriveLetter
            if ($letter) { Write-Host "Mounted as drive $letter`:" -ForegroundColor Green; if (-not $NoPause) { Start-Process explorer.exe "$letter`:$bs" } }
            return $true
        }
        'iso-unmount' { Dismount-DiskImage -ImagePath $Files[0] | Out-Null; Write-Host 'Image unmounted' -ForegroundColor Green; return $true }
        'iso-eject' {
            $img = Get-Volume -DriveLetter $Value | Get-DiskImage
            if (-not $img) { Write-Host 'This is not a mounted image' -ForegroundColor Red; return $false }
            Dismount-DiskImage -ImagePath $img.ImagePath | Out-Null
            Write-Host "Image $([IO.Path]::GetFileName($img.ImagePath)) unmounted" -ForegroundColor Green
            return $true
        }
    }
}

# ---------- Power ----------
function Invoke-Power {
    $ask = @{
        'restart'  = 'Restart the computer now? Unsaved work will be lost.'
        'shutdown' = 'Shut down the computer now? Unsaved work will be lost.'
        'bios'     = 'Restart straight into BIOS/UEFI?'
        'advanced' = 'Restart into advanced startup (recovery, safe mode)?'
        'logoff'   = 'Sign out? All programs will close.'
        'test'     = 'Confirmation window test: nothing happens after you answer.'   # for tests
    }
    if ($ask.ContainsKey($Value) -and -not (Confirm-Box $ask[$Value] 'Power')) { return $true }
    switch -Regex ($Value) {
        '^lock$'      { & rundll32.exe user32.dll, LockWorkStation }
        # SetSuspendState via .NET: rundll32 hibernates instead of sleeping when hibernation is on
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

# ---------- Everything search ----------
# Everything parses its command line its own way: quotes just open and close text,
# a backslash is a normal character. So the folder goes via -p "…", the filter via -search "…",
# and Everything builds a query like "D:\Video\" video:
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
        'samename'   { '-name-part "' + [IO.Path]::GetFileName($p) + '"' }   # nopath:wfn:"name"
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
        default      { Write-Host "Unknown action: $Action" -ForegroundColor Red }
    }
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    $result = $false
}
Done ([bool]$result)
