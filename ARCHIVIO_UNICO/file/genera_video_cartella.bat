@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
for %%I in ("%SCRIPT_DIR%.") do set "LANG_DIR=%%~nxI"

set "WHISPER_LANG=auto"
if /I "%LANG_DIR%"=="IT" set "WHISPER_LANG=it"
if /I "%LANG_DIR%"=="EN" set "WHISPER_LANG=en"
if /I "%LANG_DIR%"=="FR" set "WHISPER_LANG=fr"
if /I "%LANG_DIR%"=="SP" set "WHISPER_LANG=es"
if /I "%LANG_DIR%"=="DE" set "WHISPER_LANG=de"

set "ROOT_PS=%SCRIPT_DIR%..\genera-video.ps1"

if not exist "%ROOT_PS%" (
    echo ERRORE: non trovo "%ROOT_PS%"
    echo Copia questo .bat dentro una cartella lingua sotto la root progetto.
    pause
    exit /b 1
)

echo Cartella lingua rilevata: %LANG_DIR%
echo Codice lingua Whisper: %WHISPER_LANG%
echo.
echo Avvio generazione video e sottotitoli per tutti gli audio nella cartella...
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT_PS%" -Root "%SCRIPT_DIR%" -WhisperLanguage "%WHISPER_LANG%" -WhisperModel tiny

if errorlevel 1 (
    echo.
    echo Operazione terminata con errori.
    pause
    exit /b 1
)

echo.
echo Completato con successo.
pause
