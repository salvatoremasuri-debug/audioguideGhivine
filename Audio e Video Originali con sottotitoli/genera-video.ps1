param(
    [string]$Root = ".",
    [string]$AudioFilter = "*",
    [string]$SrtSubfolder = "srt",
    [int]$Width = 240,
    [int]$Height = 320,
    [int]$Fps = 25,
    [switch]$Recurse = $true,
    [switch]$AutoSubtitles = $true,
    [switch]$NoAutoSubtitles = $false,
    [switch]$ForceSubtitles = $false,
    [string]$WhisperModel = "small",
    [string]$WhisperLanguage = "auto"
)

$ErrorActionPreference = "Stop"

function Test-Tool {
    param([string]$Name)
    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Resolve-FfmpegPath {
    $cmd = Get-Command "ffmpeg" -ErrorAction SilentlyContinue
    if ($null -ne $cmd) { return $cmd.Path }

    $wingetLinks = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\ffmpeg.exe"
    if (Test-Path $wingetLinks) { return $wingetLinks }

    return $null
}

function Resolve-FfprobePath {
    $cmd = Get-Command "ffprobe" -ErrorAction SilentlyContinue
    if ($null -ne $cmd) { return $cmd.Path }

    $wingetLinks = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Links\ffprobe.exe"
    if (Test-Path $wingetLinks) { return $wingetLinks }

    return $null
}

function Wrap-SubtitleText {
    param(
        [string]$Text,
        [int]$MaxCharsPerLine = 16
    )

    $clean = ($Text -replace "\s+", " ").Trim()
    if ([string]::IsNullOrWhiteSpace($clean)) {
        return $clean
    }

    $words = $clean.Split(" ")
    $lines = @()
    $current = ""

    foreach ($w in $words) {
        if ([string]::IsNullOrWhiteSpace($current)) {
            $current = $w
            continue
        }

        $candidate = "$current $w"
        if ($candidate.Length -le $MaxCharsPerLine) {
            $current = $candidate
        }
        else {
            $lines += $current
            $current = $w
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($current)) {
        $lines += $current
    }

    return ($lines -join "\N")
}

function New-StyledSrt {
    param(
        [string]$InputSrtPath,
        [string]$OutputSrtPath
    )

    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    try {
        $raw = [System.IO.File]::ReadAllText($InputSrtPath, $utf8)
    }
    catch {
        $raw = [System.IO.File]::ReadAllText($InputSrtPath, [System.Text.Encoding]::GetEncoding(1252))
    }
    $blocks = $raw -split "(\r?\n){2,}"
    $outBlocks = @()

    foreach ($b in $blocks) {
        $t = $b.Trim()
        if ([string]::IsNullOrWhiteSpace($t)) {
            continue
        }

        $lines = $t -split "\r?\n"
        if ($lines.Count -lt 3) {
            $outBlocks += $t
            continue
        }

        $idx = $lines[0]
        $timing = $lines[1]
        $textLines = $lines[2..($lines.Count - 1)] -join " "
        $wrapped = Wrap-SubtitleText -Text $textLines -MaxCharsPerLine 16
        $styledText = "{\an5}$wrapped"

        $outBlocks += @($idx, $timing, $styledText) -join [Environment]::NewLine
    }

    $final = ($outBlocks -join ([Environment]::NewLine + [Environment]::NewLine))
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [System.IO.File]::WriteAllText($OutputSrtPath, $final, $utf8Bom)
}

$ffmpegPath = Resolve-FfmpegPath
if ($null -eq $ffmpegPath) {
    throw "ffmpeg non trovato. Installa ffmpeg (es. winget) e riprova."
}
$ffprobePath = Resolve-FfprobePath
if ($null -eq $ffprobePath) {
    throw "ffprobe non trovato. Installa ffmpeg completo e riprova."
}

if ($AutoSubtitles -and -not (Test-Tool -Name "py")) {
    throw "Python launcher 'py' non trovato. Installa Python e riprova."
}

if ($NoAutoSubtitles) {
    $AutoSubtitles = $false
}

# Assicura che ffmpeg sia visibile ai processi figli (Whisper usa ffmpeg internamente)
$ffmpegDir = Split-Path -Parent $ffmpegPath
if ($env:PATH -notlike "*$ffmpegDir*") {
    $env:PATH = "$ffmpegDir;$env:PATH"
}

$rootPath = Resolve-Path $Root
$audioExt = @("*.mp3", "*.wav", "*.m4a", "*.aac", "*.flac", "*.ogg")
$audioFiles = @()

if ($Recurse) {
    foreach ($ext in $audioExt) {
        $audioFiles += Get-ChildItem -Path $rootPath -File -Recurse -Filter $ext
    }
}
else {
    foreach ($ext in $audioExt) {
        $audioFiles += Get-ChildItem -Path $rootPath -File -Filter $ext
    }
}

if ($audioFiles.Count -eq 0) {
    Write-Host "Nessun file audio trovato in $rootPath"
    exit 0
}

if ($AudioFilter -ne "*") {
    $audioFiles = $audioFiles | Where-Object { $_.BaseName -like $AudioFilter -or $_.Name -like $AudioFilter }
}

if ($audioFiles.Count -eq 0) {
    Write-Host "Nessun file audio corrisponde al filtro '$AudioFilter' in $rootPath"
    exit 0
}

foreach ($audio in $audioFiles) {
    $srtDir = Join-Path $audio.DirectoryName $SrtSubfolder
    if (-not (Test-Path $srtDir)) {
        New-Item -ItemType Directory -Path $srtDir | Out-Null
    }

    $srtPath = Join-Path $srtDir "$($audio.BaseName).srt"
    $legacySrtPath = [System.IO.Path]::ChangeExtension($audio.FullName, ".srt")
    if ((-not (Test-Path $srtPath)) -and (Test-Path $legacySrtPath)) {
        Move-Item -Path $legacySrtPath -Destination $srtPath -Force
    }
    $outputPath = [System.IO.Path]::Combine($audio.DirectoryName, "$($audio.BaseName).mp4")

    $needSubtitleGeneration = $AutoSubtitles -and ($ForceSubtitles -or -not (Test-Path $srtPath))

    if ($needSubtitleGeneration) {
        Write-Host "Genero sottotitoli con Whisper: $($audio.Name)"

        $whisperArgs = @(
            "-m", "whisper",
            $audio.FullName,
            "--model", $WhisperModel,
            "--output_format", "srt",
            "--output_dir", $srtDir,
            "--task", "transcribe",
            "--verbose", "False"
        )

        if ($WhisperLanguage -ne "auto") {
            $whisperArgs += @("--language", $WhisperLanguage)
        }

        $env:PYTHONUTF8 = "1"
        & py @whisperArgs

        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Whisper ha fallito su $($audio.Name) (salto file)."
            continue
        }
    }

    if (-not (Test-Path $srtPath)) {
        Write-Warning "Sottotitolo non disponibile: $srtPath (salto $($audio.Name))"
        continue
    }

    $styledSrtName = "$($audio.BaseName)__styled_tmp.srt"
    $styledSrtPath = Join-Path $srtDir $styledSrtName
    New-StyledSrt -InputSrtPath $srtPath -OutputSrtPath $styledSrtPath

    $subtitleFilter = "subtitles=${SrtSubfolder}/${styledSrtName}:charenc=UTF-8:force_style='FontName=Arial,FontSize=30,PrimaryColour=&HFFFFFF&,OutlineColour=&H000000&,BorderStyle=1,Outline=3,Shadow=0,Alignment=5,WrapStyle=0,MarginL=2,MarginR=2,MarginV=0'"
    $durationSecRaw = & $ffprobePath -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $audio.FullName
    $durationSec = [double]::Parse(($durationSecRaw.Trim()), [System.Globalization.CultureInfo]::InvariantCulture)

    Write-Host "Genero: $outputPath"

    Push-Location $audio.DirectoryName
    try {
        & $ffmpegPath -y `
            -f lavfi -i "color=c=black:s=${Width}x${Height}:r=$Fps" `
            -i $audio.Name `
            -t $durationSec `
            -vf $subtitleFilter `
            -c:v libx264 `
            -pix_fmt yuv420p `
            -profile:v baseline `
            -level 3.0 `
            -r $Fps `
            -an `
            (Split-Path -Leaf $outputPath)
    }
    finally {
        Pop-Location
        if (Test-Path $styledSrtPath) {
            Remove-Item $styledSrtPath -Force -ErrorAction SilentlyContinue
        }
    }
}

Write-Host "Completato."
