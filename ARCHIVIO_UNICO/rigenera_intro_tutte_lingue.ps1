param(
    [switch]$RefreshOriginals,
    [string]$OnlyFromList = ""
)

$ErrorActionPreference = "Stop"

$root = "c:\Users\SM\Desktop\audioguida_ghivine\FILE OK - Copia"
$introDir = Join-Path $root "intro"
$tmpDir = Join-Path $env:TEMP ("intro_rebuild_all_" + [guid]::NewGuid().ToString("N"))
$logoCandidates = @(
    (Join-Path $root "file\logo.jpg"),
    (Join-Path $root "italiano\logo.jpg")
)
$logoPath = $logoCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
# Cartelle lingua (nomi a word: italiano, english, …)
$langDirs  = @("italiano", "english", "french", "spanish", "german")
$langCodes = @("IT",      "EN",      "FR",     "SP",     "DE")
$targetsByLang = @{}

if ($OnlyFromList -and (Test-Path $OnlyFromList)) {
    foreach ($line in (Get-Content -Path $OnlyFromList -Encoding UTF8)) {
        $item = $line.Trim()
        if (-not $item) { continue }
        $parts = $item -split "[/\\]"
        if ($parts.Count -lt 3) { continue }
        $folder = $parts[0].ToUpper()
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($parts[-1])
        if ($stem.EndsWith("ORIG")) {
            $stem = $stem.Substring(0, $stem.Length - 4)
        }
        if ($folder.EndsWith("_ORIGINALI")) {
            $folder = $folder.Substring(0, $folder.Length - 10)
        }
        if ($stem -notmatch "^\d{4}$") { continue }
        if (-not $targetsByLang.ContainsKey($folder)) {
            $targetsByLang[$folder] = New-Object System.Collections.Generic.HashSet[string]
        }
        [void]$targetsByLang[$folder].Add($stem)
    }
}

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    throw "ffmpeg non trovato nel PATH."
}
if (-not $logoPath) {
    throw "Logo non trovato (attesi: file\logo.jpg o italiano\logo.jpg)."
}

New-Item -ItemType Directory -Path $introDir -Force | Out-Null
New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null

$fontBold = "C\:/Windows/Fonts/arialbd.ttf"

function New-NumberClip {
    param(
        [int]$Number,
        [double]$DurationSec,
        [string]$OutPath
    )

    & ffmpeg -y `
        -f lavfi -i "color=c=black:s=240x320:r=25:d=$DurationSec" `
        -f lavfi -i "color=c=0x2FBF71:s=170x170:r=25:d=$DurationSec" `
        -filter_complex "[1:v]format=rgba,geq=r='r(X,Y)':g='g(X,Y)':b='b(X,Y)':a='if(lte((X-W/2)^2+(Y-H/2)^2,(W/2-2)^2),255,0)'[ball];[0:v][ball]overlay=(W-w)/2:(H-h)/2,drawtext=fontfile='$fontBold':text='$Number':fontcolor=black:fontsize=98:borderw=2:bordercolor=black:x=(w-text_w)/2:y=(h-text_h)/2-2,fade=t=in:st=0:d=0.35,fade=t=out:st=$(($DurationSec - 0.35)):d=0.35" `
        -an -c:v libx264 -pix_fmt yuv420p -profile:v baseline -level 3.0 -r 25 $OutPath | Out-Null
}

function New-LogoClip {
    param(
        [string]$OutPath
    )

    & ffmpeg -y `
        -loop 1 -i $logoPath `
        -f lavfi -i "color=c=black:s=240x320:r=25:d=3" `
        -filter_complex "[0:v]scale=240:320:force_original_aspect_ratio=decrease[lg];[1:v][lg]overlay=(W-w)/2:(H-h)/2,fade=t=in:st=0:d=0.4,fade=t=out:st=2.6:d=0.4" `
        -t 3 -an -c:v libx264 -pix_fmt yuv420p -profile:v baseline -level 3.0 -r 25 $OutPath | Out-Null
}

# Shared intro clips 0001..0008 (same for all languages)
foreach ($i in 1..8) {
    $base = "{0:d4}" -f $i
    $introOut = Join-Path $introDir ($base + "intro.mp4")
    $numTmp = Join-Path $tmpDir ($base + "_num.mp4")

    if ($i -eq 1) {
        $logoTmp = Join-Path $tmpDir ($base + "_logo.mp4")
        $listTxt = Join-Path $tmpDir ($base + "_intro_list.txt")

        New-LogoClip -OutPath $logoTmp
        New-NumberClip -Number $i -DurationSec 2 -OutPath $numTmp

        @(
            "file '$($logoTmp -replace '\\','/')'"
            "file '$($numTmp -replace '\\','/')'"
        ) | Set-Content -Path $listTxt -Encoding ascii

        & ffmpeg -y -f concat -safe 0 -i $listTxt `
            -c:v libx264 -pix_fmt yuv420p -profile:v baseline -level 3.0 -r 25 -an $introOut | Out-Null
    }
    else {
        New-NumberClip -Number $i -DurationSec 2 -OutPath $introOut
    }
}

for ($li = 0; $li -lt $langDirs.Count; $li++) {
    $lang = $langDirs[$li]
    $code = $langCodes[$li]
    $langDir = Join-Path $root $lang
    $origDir = Join-Path $root ($code + "_ORIGINALI")
    $origSrtDir = Join-Path $origDir "srt"
    $langSrtDir = Join-Path $langDir "srt"

    if (-not (Test-Path $langDir)) { continue }

    New-Item -ItemType Directory -Path $origDir -Force | Out-Null
    if ((Test-Path $langSrtDir) -and -not (Test-Path $origSrtDir)) {
        Copy-Item -Path $langSrtDir -Destination $origSrtDir -Recurse -Force
    }

    foreach ($i in 1..8) {
        $base = "{0:d4}" -f $i
        if ($targetsByLang.Count -gt 0) {
            if (-not $targetsByLang.ContainsKey($lang)) { continue }
            if (-not $targetsByLang[$lang].Contains($base)) { continue }
        }
        $intro = Join-Path $introDir ($base + "intro.mp4")
        $langMp3 = Join-Path $langDir ($base + ".mp3")
        $langMp4 = Join-Path $langDir ($base + ".mp4")
        $origMp3 = Join-Path $origDir ($base + "ORIG.mp3")
        $origMp4 = Join-Path $origDir ($base + "ORIG.mp4")

        if (-not (Test-Path $intro)) { throw "Intro mancante: $intro" }
        if (-not (Test-Path $langMp3) -or -not (Test-Path $langMp4)) { continue }

        if (-not (Test-Path $origMp3)) {
            Copy-Item -Path $langMp3 -Destination $origMp3 -Force
        }
        if ($RefreshOriginals -or -not (Test-Path $origMp4)) {
            try {
                Copy-Item -Path $langMp4 -Destination $origMp4 -Force
            }
            catch {
                Write-Warning "Non riesco ad aggiornare $origMp4, uso il file esistente."
            }
        }

        $listTxt = Join-Path $tmpDir ($code + "_" + $base + "_list.txt")
        $outVideo = $langMp4
        $outAudio = $langMp3
        $silenceSec = if ($i -eq 1) { 5 } else { 2 }

        @(
            "file '$($intro -replace '\\','/')'"
            "file '$($origMp4 -replace '\\','/')'"
        ) | Set-Content -Path $listTxt -Encoding ascii

        & ffmpeg -y -f concat -safe 0 -i $listTxt `
            -c:v libx264 -pix_fmt yuv420p -profile:v baseline -level 3.0 -r 25 -an $outVideo | Out-Null

        & ffmpeg -y -f lavfi -t $silenceSec -i "anullsrc=r=44100:cl=mono" -i $origMp3 `
            -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1[a]" -map "[a]" -c:a libmp3lame $outAudio | Out-Null
    }

    Write-Host "Completata intro lingua $lang"
}

Remove-Item -Recurse -Force $tmpDir
Write-Host "Completato: intro applicata a tutte le lingue disponibili."
