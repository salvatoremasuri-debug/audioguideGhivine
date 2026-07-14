$ErrorActionPreference = "Stop"

$root = "c:\Users\SM\Desktop\audioguida_ghivine\FILE OK - Copia"
$introDir = Join-Path $root "intro"
$itDir = Join-Path $root "italiano"
$origDir = Join-Path $root "IT_ORIGINALI"
$logoPath = Join-Path $itDir "logo.jpg"
$tmpDir = Join-Path $env:TEMP ("intro_rebuild_" + [guid]::NewGuid().ToString("N"))

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    throw "ffmpeg non trovato nel PATH."
}
if (-not (Test-Path $logoPath)) {
    throw "Logo non trovato: $logoPath"
}
if (-not (Test-Path $origDir)) {
    throw "Cartella originali non trovata: $origDir"
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

    # True green circle via alpha mask + thick black number
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

# Build shared intro files 0001..0008 in root\intro
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

# Rebuild IT final audio/video from ORIG + shared intro clips
foreach ($i in 1..8) {
    $base = "{0:d4}" -f $i
    $intro = Join-Path $introDir ($base + "intro.mp4")
    $origVideo = Join-Path $origDir ($base + "ORIG.mp4")
    $origAudio = Join-Path $origDir ($base + "ORIG.mp3")
    $outVideo = Join-Path $itDir ($base + ".mp4")
    $outAudio = Join-Path $itDir ($base + ".mp3")
    $listTxt = Join-Path $tmpDir ($base + "_final_list.txt")
    $silenceSec = if ($i -eq 1) { 5 } else { 2 }

    if (-not (Test-Path $intro)) { throw "Intro mancante: $intro" }
    if (-not (Test-Path $origVideo)) { throw "Video ORIG mancante: $origVideo" }
    if (-not (Test-Path $origAudio)) { throw "Audio ORIG mancante: $origAudio" }

    @(
        "file '$($intro -replace '\\','/')'"
        "file '$($origVideo -replace '\\','/')'"
    ) | Set-Content -Path $listTxt -Encoding ascii

    & ffmpeg -y -f concat -safe 0 -i $listTxt `
        -c:v libx264 -pix_fmt yuv420p -profile:v baseline -level 3.0 -r 25 -an $outVideo | Out-Null

    & ffmpeg -y -f lavfi -t $silenceSec -i "anullsrc=r=44100:cl=mono" -i $origAudio `
        -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1[a]" -map "[a]" -c:a libmp3lame $outAudio | Out-Null

    Write-Host "OK $base"
}

Remove-Item -Recurse -Force $tmpDir
Write-Host "Completato: intro condivise in '$introDir' e IT rigenerata."
