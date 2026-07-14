$ErrorActionPreference = "Stop"

$root = "c:\Users\SM\Desktop\audioguida_ghivine\FILE OK - Copia"
$langDir = Join-Path $root "italiano"
$origDir = Join-Path $root "IT_ORIGINALI"
$logoPath = Join-Path $langDir "logo.jpg"
$tmpDir = Join-Path $env:TEMP ("it_intro_" + [guid]::NewGuid().ToString("N"))

if (-not (Test-Path $logoPath)) {
    throw "Logo non trovato: $logoPath"
}

if (-not (Get-Command ffmpeg -ErrorAction SilentlyContinue)) {
    throw "ffmpeg non trovato nel PATH."
}

if (Test-Path $origDir) {
    Remove-Item -Recurse -Force $origDir
}
New-Item -ItemType Directory -Path $origDir | Out-Null
New-Item -ItemType Directory -Path $tmpDir | Out-Null

$srtDir = Join-Path $langDir "srt"
if (Test-Path $srtDir) {
    $dstSrt = Join-Path $origDir "srt"
    Copy-Item -Path $srtDir -Destination $dstSrt -Recurse -Force
    Remove-Item -Path $srtDir -Recurse -Force
}

$audios = Get-ChildItem -Path $langDir -Filter "*.mp3" -File | Sort-Object Name

foreach ($audio in $audios) {
    $base = $audio.BaseName
    $video = Join-Path $langDir "$base.mp4"
    if (-not (Test-Path $video)) {
        Write-Warning "Video mancante per $base, salto."
        continue
    }

    $introSeconds = if ($base -eq "0001") { 5 } else { 2 }
    $showLogo = $base -eq "0001"
    $numberText = [int]$base

    $origAudio = Join-Path $origDir "$base`ORIG.mp3"
    $origVideo = Join-Path $origDir "$base`ORIG.mp4"
    $introOut = Join-Path $origDir "$base`intro.mp4"

    Copy-Item -Path $audio.FullName -Destination $origAudio -Force
    Copy-Item -Path $video -Destination $origVideo -Force

    $numClip = Join-Path $tmpDir "${base}_num.mp4"
    $logoClip = Join-Path $tmpDir "${base}_logo.mp4"
    $listFile = Join-Path $tmpDir "${base}_list.txt"

    & ffmpeg -y -f lavfi -i "color=c=black:s=240x320:r=25:d=2" `
        -vf "drawtext=fontfile='C\:/Windows/Fonts/arial.ttf':text='●':fontcolor=0x2FBF71:fontsize=230:x=(w-text_w)/2:y=(h-text_h)/2-8,drawtext=fontfile='C\:/Windows/Fonts/arial.ttf':text='$numberText':fontcolor=black:fontsize=92:x=(w-text_w)/2:y=(h-text_h)/2,fade=t=in:st=0:d=0.4,fade=t=out:st=1.6:d=0.4" `
        -an -c:v libx264 -pix_fmt yuv420p -profile:v baseline -level 3.0 -r 25 $numClip | Out-Null

    if ($showLogo) {
        & ffmpeg -y -loop 1 -i $logoPath -f lavfi -i "color=c=black:s=240x320:r=25:d=3" `
            -filter_complex "[0:v]scale=240:320:force_original_aspect_ratio=decrease[lg];[1:v][lg]overlay=(W-w)/2:(H-h)/2,fade=t=in:st=0:d=0.4,fade=t=out:st=2.6:d=0.4" `
            -t 3 -an -c:v libx264 -pix_fmt yuv420p -profile:v baseline -level 3.0 -r 25 $logoClip | Out-Null

        $logoLine = ($logoClip -replace "\\", "/")
        $numLine = ($numClip -replace "\\", "/")
        @(
            "file '$logoLine'"
            "file '$numLine'"
        ) | Set-Content -Path $listFile -Encoding ascii

        & ffmpeg -y -f concat -safe 0 -i $listFile `
            -c:v libx264 -pix_fmt yuv420p -profile:v baseline -level 3.0 -r 25 -an $introOut | Out-Null
    }
    else {
        Copy-Item -Path $numClip -Destination $introOut -Force
    }

    $introLine = ($introOut -replace "\\", "/")
    $origVideoLine = ($origVideo -replace "\\", "/")
    @(
        "file '$introLine'"
        "file '$origVideoLine'"
    ) | Set-Content -Path $listFile -Encoding ascii

    $newVideo = Join-Path $langDir "$base.mp4"
    & ffmpeg -y -f concat -safe 0 -i $listFile `
        -c:v libx264 -pix_fmt yuv420p -profile:v baseline -level 3.0 -r 25 -an $newVideo | Out-Null

    $newAudio = Join-Path $langDir "$base.mp3"
    & ffmpeg -y -f lavfi -t $introSeconds -i "anullsrc=r=44100:cl=mono" -i $origAudio `
        -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1[a]" -map "[a]" -c:a libmp3lame $newAudio | Out-Null

    Write-Host "OK $base (intro ${introSeconds}s)"
}

Remove-Item -Recurse -Force $tmpDir
Write-Host "Completato IT"
