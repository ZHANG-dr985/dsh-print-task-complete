<#
    print-done.ps1  -  sparse "task complete" receipt, scattered over one sheet.

    No grid, no cell borders: every run stamps ONE mark at a fresh RANDOM spot,
    remembering where it landed so marks never collide. After PerSheet stamps
    (default 30) the sheet is full and the next run asks for a new one, so one
    piece of paper still serves 30 completions.

    Occasionally a run prints an easter egg: a picture above the mark.

    WHY CODE POINTS INSTEAD OF STRING LITERALS
    ------------------------------------------
    Windows PowerShell 5.1 on a GB2312/936 host reads BOM-less .ps1 files as
    ANSI. A literal CJK string in this file is silently corrupted into mojibake
    before it reaches GDI+, and the printer then faithfully prints the garbage
    (U+5DF2 U+5B8C U+6210 becomes U+5BB8 U+63D2 U+756C U+93B4 U+003F).
    This file is therefore kept 100% ASCII and the payload is built from integer
    code points, which no source-file encoding can damage. Do not "simplify"
    this back into string literals.

    Exit codes: 0 = page handed to the printer port, 1 = failure.
#>
[CmdletBinding()]
param(
    [string] $PrinterName = '',
    [int[]]  $CodePoints  = @(0x5DF2, 0x5B8C, 0x6210),
    [int]    $PerSheet    = 30,
    [string] $FontFamily  = '',
    [int]    $FontSizePx  = 0,
    [string] $PreviewPath = '',
    [string] $StateDir    = '',
    [int]    $UseSlot     = 0,
    [double] $EasterEggChance = 0.1,
    [string] $EasterEggImage  = '',
    [int]    $EasterEggMm     = 22,
    [switch] $EasterEgg,
    [switch] $NoEasterEgg,
    [switch] $NoHeader,
    [int]    $RandomSeed  = 0,
    [double] $NudgeXmm    = [double]::NaN,
    [double] $NudgeYmm    = [double]::NaN,
    [switch] $ClearNudge,
    [switch] $DryRun,
    [switch] $Simulate,
    [switch] $Reset,
    [switch] $NoAdvance,
    [switch] $Status
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

function Fail([string] $Message) { Write-Host "[done-slip] ERROR: $Message"; exit 1 }
function Info([string] $Message) { Write-Host "[done-slip] $Message" }

# ============================================================ 1. persistent state
if (-not $StateDir) {
    $base = $env:LOCALAPPDATA
    if (-not $base) { $base = $env:TEMP }
    $StateDir = Join-Path $base 'dsh-print-task-complete'
}
if (-not (Test-Path $StateDir)) { New-Item -ItemType Directory -Path $StateDir -Force | Out-Null }
$stateFile = Join-Path $StateDir 'state.json'

if ($PerSheet -lt 1) { Fail "PerSheet must be >= 1 (got $PerSheet)." }

$state = [ordered]@{
    version  = 2
    printer  = ''
    perSheet = $PerSheet
    sheets   = @{}
    nudges   = @{}
}

if (Test-Path $stateFile) {
    try {
        $loaded = Get-Content $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($loaded.printer) { $state.printer = [string]$loaded.printer }
        if ($loaded.sheets) {
            $h = @{}
            foreach ($prop in $loaded.sheets.PSObject.Properties) { $h[$prop.Name] = $prop.Value }
            $state.sheets = $h
        }
        if ($loaded.nudges) {
            $o = @{}
            foreach ($prop in $loaded.nudges.PSObject.Properties) { $o[$prop.Name] = $prop.Value }
            $state.nudges = $o
        }
        # v1 kept a per-printer "offsets" table; carry it over as a nudge.
        if ($loaded.offsets) {
            foreach ($prop in $loaded.offsets.PSObject.Properties) {
                if (-not $state.nudges.ContainsKey($prop.Name)) { $state.nudges[$prop.Name] = $prop.Value }
            }
        }
    } catch {
        Info "WARN: state file unreadable, starting fresh ($stateFile): $($_.Exception.Message)"
    }
}

function Save-State {
    $json = $state | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($stateFile, $json, (New-Object System.Text.UTF8Encoding $false))
}

# =========================================================== 2. printer discovery
function Get-CandidatePrinters {
    $defaults = @()
    try {
        $defaults = @(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue |
                      Where-Object { $_.Default } | Select-Object -ExpandProperty Name)
    } catch { }

    $list = @()
    foreach ($p in @(Get-Printer -ErrorAction SilentlyContinue)) {
        # Skip software writers: they produce a file, not paper.
        if ($p.Name       -match '(?i)(pdf|xps|fax|onenote|print to file|\u865a\u62df)') { continue }
        if ($p.DriverName -match '(?i)(print to pdf|xps|virtual|kingsoft|acrobat)')       { continue }
        if ($p.PortName   -match '(?i)^(portprompt|file|nul|svchost)')                    { continue }
        $list += [pscustomobject]@{
            Name    = $p.Name
            Port    = $p.PortName
            Status  = $p.PrinterStatus
            Default = ($defaults -contains $p.Name)
        }
    }
    return @($list | Sort-Object @{ Expression = { -not $_.Default } }, Name)
}

$candidates = Get-CandidatePrinters

function Resolve-Printer {
    param([string] $Requested, [string] $Remembered)

    if ($Requested) {
        $hit = $candidates | Where-Object { $_.Name -eq $Requested } | Select-Object -First 1
        if ($hit) { return $hit.Name }
        $any = @(Get-Printer -ErrorAction SilentlyContinue) | Where-Object { $_.Name -eq $Requested }
        if ($any) { return $Requested }
        $names = ($candidates | Select-Object -ExpandProperty Name) -join ' | '
        Fail "printer '$Requested' not found. Physical printers available: $names"
    }
    if ($Remembered) {
        $hit = $candidates | Where-Object { $_.Name -eq $Remembered } | Select-Object -First 1
        if ($hit) { return $hit.Name }
        Info "WARN: remembered printer '$Remembered' is gone; re-detecting."
    }
    if ($candidates.Count -eq 0) {
        $all = (@(Get-Printer -ErrorAction SilentlyContinue) | Select-Object -ExpandProperty Name) -join ' | '
        Fail "no physical printer found. Installed printers: $all"
    }
    return $candidates[0].Name
}

$printer = Resolve-Printer -Requested $PrinterName -Remembered ([string]$state.printer)
$psArr = @(Get-Printer -Name $printer -ErrorAction SilentlyContinue)
if (-not $psArr) { Fail "printer '$printer' disappeared between detection and use." }
$psObj = $psArr[0]
if ($psObj.PrinterStatus -eq 'Offline') { Info "WARN: '$printer' reports Offline; the job may sit in the spooler." }

$mono = $true
try {
    $cfg = Get-PrintConfiguration -PrinterName $printer -ErrorAction Stop
    $mono = -not $cfg.Color
} catch { }

# ================================================== 2b. global nudge (cosmetic)
$storedNudge = $null
if ($state.nudges.ContainsKey($printer)) { $storedNudge = $state.nudges[$printer] }
$nudgeX = 0.0
$nudgeY = 0.0
if ($storedNudge) {
    if ($null -ne $storedNudge.x) { $nudgeX = [double]$storedNudge.x }
    if ($null -ne $storedNudge.y) { $nudgeY = [double]$storedNudge.y }
}
$nudgeGiven = $false
if ($PSBoundParameters.ContainsKey('NudgeXmm')) { $nudgeX = [double]$NudgeXmm; $nudgeGiven = $true }
if ($PSBoundParameters.ContainsKey('NudgeYmm')) { $nudgeY = [double]$NudgeYmm; $nudgeGiven = $true }
if ($ClearNudge) { $nudgeX = 0.0; $nudgeY = 0.0; $nudgeGiven = $true }

# ============================================================ 3. sheet bookkeeping
$sheetState = $null
if ($state.sheets.ContainsKey($printer)) { $sheetState = $state.sheets[$printer] }

$stamps   = @()
$curSheet = 1
$curIndex = 1
$hasState = $false
if ($sheetState) {
    $hasState = $true
    if ($sheetState.sheet) { $curSheet = [int]$sheetState.sheet }
    if ($sheetState.index) { $curIndex = [int]$sheetState.index }
    elseif ($sheetState.slot) { $curIndex = [int]$sheetState.slot }   # v1 migration
    if ($sheetState.stamps) { $stamps = @($sheetState.stamps) }
}

if ($Status) {
    Info "printer : $printer  [$($psObj.PortName)]  $(if ($mono) { 'mono' } else { 'color' })"
    Info "sheet   : #$curSheet, next stamp $curIndex/$PerSheet, $($stamps.Count) placed"
    Info "nudge   : X=$nudgeX mm  Y=$nudgeY mm"
    Info "egg     : chance $EasterEggChance"
    Info "state   : $stateFile"
    exit 0
}

$newSheet = $false
if (-not $hasState) {
    $newSheet = $true
    Info "first run for this printer: starting sheet 1."
} elseif ($Reset) {
    $curSheet++
    $stamps = @()
    $curIndex = 1
    $newSheet = $true
    Info "new sheet requested: starting sheet $curSheet."
} elseif ($curIndex -gt $PerSheet -or $stamps.Count -ge $PerSheet) {
    $curSheet++
    $stamps = @()
    $curIndex = 1
    $newSheet = $true
    Info "sheet is full ($PerSheet/$PerSheet). Starting a NEW sheet - load a fresh piece of paper."
}

# ================================================================== 4. payload
if (-not $CodePoints -or $CodePoints.Count -eq 0) { Fail 'CodePoints is empty.' }
$chars = foreach ($cp in $CodePoints) {
    if ($cp -lt 1 -or $cp -gt 0xFFFF) { Fail "code point must be in 1..0xFFFF (BMP): $cp" }
    [char]$cp
}
$Text = -join $chars
$cps = ($Text.ToCharArray() | ForEach-Object { 'U+{0:X4}' -f [int]$_ }) -join ' '
Info "payload : $cps  ($($Text.Length) chars)"

# ===================================================================== 5. font
$available = [System.Drawing.FontFamily]::Families | Select-Object -ExpandProperty Name
if ($FontFamily -ne '') {
    if ($available -notcontains $FontFamily) { Fail "font '$FontFamily' is not installed." }
    $chosen = $FontFamily
} else {
    $chosen = $null
    foreach ($cand in @('Microsoft YaHei UI', 'Microsoft YaHei', 'Noto Sans SC', 'Source Han Sans SC',
                        'SimSun', 'SimHei', 'MS Gothic', 'Yu Gothic', 'Malgun Gothic', 'Arial Unicode MS')) {
        if ($available -contains $cand) { $chosen = $cand; break }
    }
    if (-not $chosen) { Fail 'no CJK-capable font found. Pass -FontFamily with a font that has these glyphs.' }
}
Info "font    : $chosen"

# ---- ink probe: refuse to send a blank page --------------------------------
$probeBmp = [System.Drawing.Bitmap]::new(300, 100)
$pg = [System.Drawing.Graphics]::FromImage($probeBmp)
$pg.Clear([System.Drawing.Color]::White)
$probeFont = [System.Drawing.Font]::new($chosen, 60, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
$pg.DrawString($Text, $probeFont, [System.Drawing.Brushes]::Black, 4, 4)
$pg.Dispose()
$ink = 0
for ($y = 0; $y -lt $probeBmp.Height; $y += 2) {
    for ($x = 0; $x -lt $probeBmp.Width; $x += 2) {
        if ($probeBmp.GetPixel($x, $y).R -lt 128) { $ink++ }
    }
}
$probeBmp.Dispose()
if ($ink -lt 20) { Fail 'rendered text is blank - the chosen font cannot draw this payload.' }

# ============================================================ 6. page + metrics
$dpi = 300
function Mm([double] $v) { [int][Math]::Round($v * $dpi / 25.4) }

$pageW = Mm 210.0
$pageH = Mm 297.0
$padX  = Mm 15.0
$padY  = Mm 15.0

$mainSize  = if ($FontSizePx -gt 0) { $FontSizePx } else { Mm 7.5 }
$smallSize = [int][Math]::Max(18, (Mm 2.9))

$bmp = [System.Drawing.Bitmap]::new($pageW, $pageH)
$bmp.SetResolution($dpi, $dpi)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.Clear([System.Drawing.Color]::White)
$g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

$fmt = [System.Drawing.StringFormat]::new()
$fmt.Alignment     = [System.Drawing.StringAlignment]::Center
$fmt.LineAlignment = [System.Drawing.StringAlignment]::Center
$black = [System.Drawing.Brushes]::Black

$fontMain  = [System.Drawing.Font]::new($chosen, $mainSize,  [System.Drawing.FontStyle]::Bold,    [System.Drawing.GraphicsUnit]::Pixel)
$fontSmall = [System.Drawing.Font]::new($chosen, $smallSize, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)

$mainMeasured  = $g.MeasureString($Text, $fontMain, 1000000, $fmt)
$mainH  = [int][Math]::Ceiling($mainSize * 1.25)
$smallH = [int][Math]::Ceiling($smallSize * 1.7)
$smallMeasured = $g.MeasureString('#00/00  00:00:00', $fontSmall, 1000000, $fmt)

$padIn   = Mm 2.0
$blockW  = [int][Math]::Ceiling([Math]::Max($mainMeasured.Width, $smallMeasured.Width)) + 2 * $padIn
$blockH  = $padIn + $mainH + $smallH + $padIn

Info "mark    : $([int]($blockW / ($dpi / 25.4))) x $([int]($blockH / ($dpi / 25.4))) mm"

# ============================================================== 7. easter egg
$rng = if ($RandomSeed -ne 0) { [System.Random]::new($RandomSeed) } else { [System.Random]::new() }

$useEgg = $false
if ($EasterEgg) { $useEgg = $true }
elseif (-not $NoEasterEgg -and $EasterEggChance -gt 0) { $useEgg = ($rng.NextDouble() -lt $EasterEggChance) }

$eggImg = $null
$eggW = 0
$eggH = 0
if ($useEgg) {
    $eggPath = $EasterEggImage
    if (-not $eggPath) { $eggPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'assets\easter-egg.png' }
    if (-not (Test-Path $eggPath)) {
        Info "WARN: easter egg image not found at $eggPath - printing a plain mark."
        $useEgg = $false
    } else {
        try {
            $eggImg = [System.Drawing.Image]::FromFile($eggPath)
            $eggW = Mm ([double]$EasterEggMm)
            $eggH = [int][Math]::Round($eggW * $eggImg.Height / $eggImg.Width)
            if ($eggW -gt $blockW) { $blockW = $eggW }
            $blockH += $eggH + $padIn
            Info "egg     : YES - $eggPath"
        } catch {
            Info "WARN: could not load the easter egg image: $($_.Exception.Message)"
            $useEgg = $false
        }
    }
}
if (-not $useEgg) { Info "egg     : no" }

# ================================================================ 8. placement
if (-not $NoHeader) { $padY = [Math]::Max($padY, (Mm 22.0)) }
$areaX = $padX
$areaY = $padY
$areaW = $pageW - 2 * $padX
$areaH = $pageH - $padY - (Mm 15.0)
if ($areaW -le $blockW -or $areaH -le $blockH) { Fail 'the page is too small for this mark.' }

$nudgePxX = [int][Math]::Round($nudgeX * $dpi / 25.4)
$nudgePxY = [int][Math]::Round($nudgeY * $dpi / 25.4)

function Test-Fits([double] $x, [double] $y, [double] $gap) {
    $x0 = $x - $gap; $x1 = $x + $blockW + $gap
    $y0 = $y - $gap; $y1 = $y + $blockH + $gap
    foreach ($s in $stamps) {
        if ($x0 -lt $s.x1 -and $x1 -gt $s.x0 -and $y0 -lt $s.y1 -and $y1 -gt $s.y0) { return $false }
    }
    return $true
}

$maxX = [int]($areaW - $blockW)
$maxY = [int]($areaH - $blockH)
$spotX = -1.0
$spotY = -1.0
$reused = $false

# -UseSlot N reprints stamp N where it already landed (handy for calibrating).
if ($UseSlot -gt 0) {
    if ($UseSlot -gt $PerSheet) { Fail "-UseSlot $UseSlot is outside 1..$PerSheet." }
    if ($stamps.Count -ge $UseSlot) {
        $s = $stamps[$UseSlot - 1]
        $spotX = [double]$s.x0 + $nudgePxX
        $spotY = [double]$s.y0 + $nudgePxY
        $reused = $true
    }
}

if (-not $reused) {
    $placed = $false
    foreach ($gap in @((Mm 4.0), (Mm 2.0), 0)) {
        for ($try = 0; $try -lt 400; $try++) {
            $cx = $areaX + $rng.Next($maxX + 1)
            $cy = $areaY + $rng.Next($maxY + 1)
            if (Test-Fits $cx $cy $gap) { $spotX = $cx; $spotY = $cy; $placed = $true; break }
        }
        if ($placed) { break }
    }
    if (-not $placed) {
        # Random sequential placement jams well before the area is geometrically
        # full. Rather than overlap marks, fall back to a tidy lattice of slots
        # that are guaranteed to be clear, and take a random free one.
        $gapMin = Mm 2.0
        $gw = $blockW + $gapMin
        $gh = $blockH + $gapMin
        $fbCols = [Math]::Max(1, [int][Math]::Floor($areaW / $gw))
        $fbRows = [Math]::Max(1, [int][Math]::Floor($areaH / $gh))
        $free = @()
        for ($r = 0; $r -lt $fbRows; $r++) {
            for ($c = 0; $c -lt $fbCols; $c++) {
                $fx = $areaX + $c * $gw + ($gw - $blockW) / 2.0
                $fy = $areaY + $r * $gh + ($gh - $blockH) / 2.0
                if (Test-Fits $fx $fy 0) { $free += , @($fx, $fy) }
            }
        }
        if ($free.Count -gt 0) {
            $pick = $free[$rng.Next($free.Count)]
            $spotX = $pick[0]
            $spotY = $pick[1]
            $placed = $true
            Info "sheet is filling up: used a tidy slot instead of a random spot."
        }
    }
    if (-not $placed) {
        # Only reachable if the sheet is genuinely oversubscribed.
        $best = -1.0
        for ($try = 0; $try -lt 400; $try++) {
            $cx = $areaX + $rng.Next($maxX + 1)
            $cy = $areaY + $rng.Next($maxY + 1)
            $near = [double]::MaxValue
            foreach ($s in $stamps) {
                $dx = [Math]::Max($s.x0 - ($cx + $blockW), $cx - $s.x1)
                $dy = [Math]::Max($s.y0 - ($cy + $blockH), $cy - $s.y1)
                $d = [Math]::Max(0, [Math]::Max($dx, $dy))
                if ($d -lt $near) { $near = $d }
            }
            if ($near -gt $best) { $best = $near; $spotX = $cx; $spotY = $cy }
        }
        Info "WARN: sheet is oversubscribed; marks will touch. Lower -PerSheet or -FontSizePx."
    }
    $spotX += $nudgePxX
    $spotY += $nudgePxY
}

$spotX = [Math]::Max(0, [Math]::Min($spotX, $pageW - $blockW))
$spotY = [Math]::Max(0, [Math]::Min($spotY, $pageH - $blockH))
Info "spot    : X=$([int]($spotX / ($dpi / 25.4))) mm  Y=$([int]($spotY / ($dpi / 25.4))) mm  (stamp $($stamps.Count + 1) of sheet #$curSheet)"

# ================================================================== 9. render
if ($newSheet -and -not $NoHeader) {
    $short = $printer
    if ($short.Length -gt 48) { $short = $short.Substring(0, 48) + '...' }
    $line1 = "$((Get-Date).ToString('yyyy-MM-dd'))  dsh completion sheet #$curSheet   |   $PerSheet stamps   |   $short"
    $line2 = "Keep this sheet. Re-feed it in the SAME orientation - each run stamps a random free spot."
    $fontHead = [System.Drawing.Font]::new($chosen, (Mm 4.2), [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $g.DrawString($line1, $fontHead, $black, [System.Drawing.RectangleF]::new(0, (Mm 5.0), $pageW, (Mm 6.5)), $fmt)
    $g.DrawString($line2, $fontHead, $black, [System.Drawing.RectangleF]::new(0, (Mm 12.5), $pageW, (Mm 6.5)), $fmt)
    $fontHead.Dispose()
}

$cursor = $spotY + $padIn
if ($useEgg -and $eggImg) {
    $eggX = [int]($spotX + ($blockW - $eggW) / 2)
    $eggRect = [System.Drawing.Rectangle]::new([int]$eggX, [int]$cursor, [int]$eggW, [int]$eggH)
    if ($mono) {
        # A mono laser turns colour into mud; grey it and lift contrast instead.
        $ia = [System.Drawing.Imaging.ImageAttributes]::new()
        $cm = [System.Drawing.Imaging.ColorMatrix]::new()
        $k = 1.7
        $off = 0.5 - 0.5 * $k
        $cm.Matrix00 = 0.299 * $k; $cm.Matrix01 = 0.299 * $k; $cm.Matrix02 = 0.299 * $k; $cm.Matrix04 = $off
        $cm.Matrix10 = 0.587 * $k; $cm.Matrix11 = 0.587 * $k; $cm.Matrix12 = 0.587 * $k; $cm.Matrix14 = $off
        $cm.Matrix20 = 0.114 * $k; $cm.Matrix21 = 0.114 * $k; $cm.Matrix22 = 0.114 * $k; $cm.Matrix24 = $off
        $cm.Matrix33 = 1.0
        $cm.Matrix44 = 1.0
        $ia.SetColorMatrix($cm)
        $g.DrawImage($eggImg, $eggRect, 0, 0, $eggImg.Width, $eggImg.Height,
                     [System.Drawing.GraphicsUnit]::Pixel, $ia)
        $ia.Dispose()
    } else {
        $g.DrawImage($eggImg, $eggRect)
    }
    $cursor += $eggH + $padIn
}

$g.DrawString($Text, $fontMain, $black,
    [System.Drawing.RectangleF]::new([float]$spotX, [float]$cursor, [float]$blockW, [float]$mainH), $fmt)
$cursor += $mainH
$stamp = (Get-Date).ToString('HH:mm:ss')
$g.DrawString("#$curIndex/$PerSheet  $stamp", $fontSmall, $black,
    [System.Drawing.RectangleF]::new([float]$spotX, [float]$cursor, [float]$blockW, [float]$smallH), $fmt)

$g.Dispose()
$fontMain.Dispose()
$fontSmall.Dispose()
if ($eggImg) { $eggImg.Dispose() }

if ($PreviewPath -ne '') {
    $dir = Split-Path -Parent $PreviewPath
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $bmp.Save($PreviewPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Info "preview : $PreviewPath"
}

# ==================================================================== 10. print
if ($DryRun) {
    Info "dry run : sheet #$curSheet stamp $curIndex/$PerSheet - nothing printed, state unchanged."
    $bmp.Dispose()
    exit 0
}

if (-not $Simulate) {
$doc = [System.Drawing.Printing.PrintDocument]::new()
$doc.PrinterSettings.PrinterName = $printer
if (-not $doc.PrinterSettings.IsValid) {
    $bmp.Dispose()
    Fail "printer '$printer' is not valid for printing."
}

$queued = @(Get-PrintJob -PrinterName $printer -ErrorAction SilentlyContinue)
if ($queued.Count -gt 0) {
    Info "WARN: $($queued.Count) job(s) already queued - printer may be offline or out of paper."
}

$a4 = $doc.PrinterSettings.PaperSizes | Where-Object { $_.PaperName -eq 'A4' } | Select-Object -First 1
if ($a4) { $doc.DefaultPageSettings.PaperSize = $a4 }

$script:__slipBmp = $bmp
$handler = {
    param($sender, $e)
    $img = $script:__slipBmp
    $b = $e.MarginBounds
    $ratio = [Math]::Min($b.Width / $img.Width, $b.Height / $img.Height)
    $dw = [int]($img.Width  * $ratio)
    $dh = [int]($img.Height * $ratio)
    $dx = $b.Left + [int](($b.Width  - $dw) / 2)
    $dy = $b.Top  + [int](($b.Height - $dh) / 2)
    $e.Graphics.DrawImage($img, $dx, $dy, $dw, $dh)
    $e.HasMorePages = $false
}
$doc.add_PrintPage($handler)
$doc.DocumentName = 'DSH-Task-Complete'

Info "print   : sheet #$curSheet stamp $curIndex/$PerSheet -> '$printer' ..."
$doc.Print()

# ---- verify the spooler drained -------------------------------------------
$deadline = (Get-Date).AddSeconds(45)
do {
    Start-Sleep -Milliseconds 400
    $pending = @(Get-PrintJob -PrinterName $printer -ErrorAction SilentlyContinue |
                 Where-Object { $_.DocumentName -eq 'DSH-Task-Complete' })
} while ($pending.Count -gt 0 -and (Get-Date) -lt $deadline)

    $doc.Dispose()
    if ($pending.Count -gt 0) {
        $bmp.Dispose()
        Fail "job is still stuck in the spooler after 45s (sheet #$curSheet stamp $curIndex). Check power, paper and offline state. State NOT advanced - safe to re-run."
    }
} else {
    Info "simulate: spot recorded, nothing sent to the printer."
}
$bmp.Dispose()

# ====================================================== 11. remember and advance
if (-not $NoAdvance -and $UseSlot -le 0) {
    $stamps += [pscustomobject]@{
        x0  = [Math]::Round($spotX, 1)
        y0  = [Math]::Round($spotY, 1)
        x1  = [Math]::Round($spotX + $blockW, 1)
        y1  = [Math]::Round($spotY + $blockH, 1)
        egg = $useEgg
    }
    $sheets = $state.sheets
    $sheets[$printer] = [pscustomobject]@{
        sheet     = $curSheet
        index     = $curIndex + 1
        stamps    = $stamps
        updatedAt = (Get-Date).ToString('o')
    }
    $state.sheets  = $sheets
    $state.printer = $printer
    $state.perSheet = $PerSheet
    Save-State
    $nextTxt = "stamp $($curIndex + 1)/$PerSheet"
    if ($curIndex + 1 -gt $PerSheet) { $nextTxt = 'a fresh sheet (this one is full)' }
    Info "OK      : sheet #$curSheet stamp $curIndex/$PerSheet placed. Next run stamps $nextTxt."
} else {
    $reason = if ($UseSlot -gt 0) { '-UseSlot given' } else { '-NoAdvance given' }
    Info "OK      : sheet #$curSheet stamp $curIndex/$PerSheet placed. State NOT advanced ($reason)."
}

if ($nudgeGiven) {
    $nudges = $state.nudges
    $nudges[$printer] = [pscustomobject]@{ x = $nudgeX; y = $nudgeY }
    $state.nudges  = $nudges
    $state.printer = $printer
    Save-State
    Info "nudge   : remembered X=$nudgeX mm Y=$nudgeY mm for '$printer'."
}

Info "state   : $stateFile"
exit 0
