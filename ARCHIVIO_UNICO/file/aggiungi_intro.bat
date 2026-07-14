@echo off
setlocal EnableExtensions EnableDelayedExpansion

rem Run this BAT inside a language folder (IT, EN, FR, SP, DE, ...).
rem It creates intro clips, rebuilds mp4/mp3 with intro+silence, and archives originals.

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%.") do set "LANG_DIR=%%~nxI"
for %%I in ("%SCRIPT_DIR%..") do set "ROOT_DIR=%%~fI"
set "ORIGINAL_DIR=%ROOT_DIR%\%LANG_DIR%_ORIGINALI"
set "LOGO_PATH=%SCRIPT_DIR%logo.jpg"
set "FONT_FILE=C\:/Windows/Fonts/arial.ttf"

where ffmpeg >nul 2>&1
if errorlevel 1 (
  echo ERRORE: ffmpeg non trovato nel PATH.
  pause
  exit /b 1
)

if not exist "%SCRIPT_DIR%*.mp3" (
  echo Nessun mp3 trovato in questa cartella.
  pause
  exit /b 1
)

if not exist "%SCRIPT_DIR%*.mp4" (
  echo Nessun mp4 trovato in questa cartella.
  pause
  exit /b 1
)

if not exist "%ORIGINAL_DIR%" mkdir "%ORIGINAL_DIR%"
set "TMP_DIR=%TEMP%\intro_build_%RANDOM%_%RANDOM%"
mkdir "%TMP_DIR%" >nul 2>&1

echo.
echo Cartella lingua: %LANG_DIR%
echo Archivio originali: %ORIGINAL_DIR%
echo.

pushd "%SCRIPT_DIR%"

for %%F in (*.mp3) do (
  set "BASE=%%~nF"
  set "AUDIO_IN=%%~fF"
  set "VIDEO_IN=%SCRIPT_DIR%!BASE!.mp4"

  if not exist "!VIDEO_IN!" (
    echo [SALTO] Manca video per !BASE!
  ) else (
    set "INTRO_DUR=2"
    set "SHOW_LOGO=0"
    if /I "!BASE!"=="0001" (
      set "INTRO_DUR=5"
      set "SHOW_LOGO=1"
    )

    set "NUM_TEXT=!BASE!"
    for /f "tokens=* delims=0" %%N in ("!NUM_TEXT!") do set "NUM_TEXT=%%N"
    if "!NUM_TEXT!"=="" set "NUM_TEXT=0"

    set "ORIG_AUDIO=%ORIGINAL_DIR%\!BASE!ORIG.mp3"
    set "ORIG_VIDEO=%ORIGINAL_DIR%\!BASE!ORIG.mp4"
    set "INTRO_FILE=%ORIGINAL_DIR%\!BASE!intro.mpeg"
    set "NUM_CLIP=%TMP_DIR%\!BASE!_num.mp4"
    set "LOGO_CLIP=%TMP_DIR%\!BASE!_logo.mp4"
    set "LIST_FILE=%TMP_DIR%\!BASE!_list.txt"
    set "OUT_VIDEO=%SCRIPT_DIR%!BASE!.mp4"
    set "OUT_AUDIO=%SCRIPT_DIR%!BASE!.mp3"

    if exist "!ORIG_AUDIO!" del /f /q "!ORIG_AUDIO!" >nul 2>&1
    if exist "!ORIG_VIDEO!" del /f /q "!ORIG_VIDEO!" >nul 2>&1
    if exist "!INTRO_FILE!" del /f /q "!INTRO_FILE!" >nul 2>&1

    move /y "!AUDIO_IN!" "!ORIG_AUDIO!" >nul
    move /y "!VIDEO_IN!" "!ORIG_VIDEO!" >nul

    rem 2s number panel with fade in/out.
    ffmpeg -y -f lavfi -i "color=c=black:s=240x320:r=25:d=2" ^
      -vf "drawtext=fontfile='!FONT_FILE!':text='●':fontcolor=0x2FBF71:fontsize=230:x=(w-text_w)/2:y=(h-text_h)/2-8,drawtext=fontfile='!FONT_FILE!':text='!NUM_TEXT!':fontcolor=black:fontsize=92:x=(w-text_w)/2:y=(h-text_h)/2,fade=t=in:st=0:d=0.4,fade=t=out:st=1.6:d=0.4" ^
      -an -c:v libx264 -pix_fmt yuv420p -profile:v baseline -level 3.0 -r 25 "!NUM_CLIP!" >nul

    if "!SHOW_LOGO!"=="1" (
      if not exist "%LOGO_PATH%" (
        echo ERRORE: logo.jpg non trovato in "%SCRIPT_DIR%"
        echo Copia logo.jpg nella cartella della lingua e rilancia.
        exit /b 1
      )

      rem 3s logo panel with fade in/out.
      ffmpeg -y -loop 1 -i "%LOGO_PATH%" -f lavfi -i "color=c=black:s=240x320:r=25:d=3" ^
        -filter_complex "[0:v]scale=240:320:force_original_aspect_ratio=decrease[lg];[1:v][lg]overlay=(W-w)/2:(H-h)/2,fade=t=in:st=0:d=0.4,fade=t=out:st=2.6:d=0.4" ^
        -t 3 -an -c:v libx264 -pix_fmt yuv420p -profile:v baseline -level 3.0 -r 25 "!LOGO_CLIP!" >nul

      >"!LIST_FILE!" echo file '!LOGO_CLIP:\=\\!'
      >>"!LIST_FILE!" echo file '!NUM_CLIP:\=\\!'
    ) else (
      >"!LIST_FILE!" echo file '!NUM_CLIP:\=\\!'
    )

    rem Intro-only mpeg (requested output).
    ffmpeg -y -f concat -safe 0 -i "!LIST_FILE!" -c:v mpeg2video -pix_fmt yuv420p -r 25 -an "!INTRO_FILE!" >nul

    rem Build final video: intro + original muted video.
    >"!LIST_FILE!" echo file '!INTRO_FILE:\=\\!'
    >>"!LIST_FILE!" echo file '!ORIG_VIDEO:\=\\!'
    ffmpeg -y -f concat -safe 0 -i "!LIST_FILE!" -c:v libx264 -pix_fmt yuv420p -profile:v baseline -level 3.0 -r 25 -an "!OUT_VIDEO!" >nul

    rem Build final audio: prepend silence equal to intro duration.
    ffmpeg -y -f lavfi -t !INTRO_DUR! -i anullsrc=r=44100:cl=mono -i "!ORIG_AUDIO!" ^
      -filter_complex "[0:a][1:a]concat=n=2:v=0:a=1[a]" -map "[a]" -c:a libmp3lame "!OUT_AUDIO!" >nul

    echo [OK] !BASE! completato (intro !INTRO_DUR!s)
  )
)

popd

if exist "%SCRIPT_DIR%srt" (
  if exist "%ORIGINAL_DIR%\srt" (
    move /y "%SCRIPT_DIR%srt\*" "%ORIGINAL_DIR%\srt\" >nul 2>&1
    rmdir "%SCRIPT_DIR%srt" >nul 2>&1
  ) else (
    move /y "%SCRIPT_DIR%srt" "%ORIGINAL_DIR%\srt" >nul
  )
)

rmdir /s /q "%TMP_DIR%" >nul 2>&1

echo.
echo Completato.
echo Originali, intro e srt spostati in: %ORIGINAL_DIR%
pause
exit /b 0
