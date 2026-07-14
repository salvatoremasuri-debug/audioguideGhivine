Obiettivo
- Creare video MP4 (sfondo nero) 240x320 con sottotitoli bianchi sincronizzati all'audio.
- I sottotitoli possono essere generati automaticamente con Whisper.

Prerequisiti
1) Installa ffmpeg e aggiungilo al PATH di Windows.
   Se usi winget:
   winget install --id Gyan.FFmpeg -e

2) Installa Whisper CLI (openai-whisper):
   py -m pip install -U openai-whisper

Struttura file
- Metti gli audio nelle sottocartelle lingua (IT, EN, FR, ...).
- Se c'e' gia' un .srt con stesso nome viene usato.
- Se manca, lo script lo genera con Whisper.

Uso base
1) Apri PowerShell nella cartella principale (questa cartella).
2) Esegui:
   powershell -ExecutionPolicy Bypass -File .\genera-video.ps1

Opzioni utili
- Rigenera sempre i sottotitoli:
  powershell -ExecutionPolicy Bypass -File .\genera-video.ps1 -ForceSubtitles

- Cambia modello Whisper (piu' preciso ma piu' lento):
  powershell -ExecutionPolicy Bypass -File .\genera-video.ps1 -WhisperModel medium

- Forza lingua Whisper (es. italiano):
  powershell -ExecutionPolicy Bypass -File .\genera-video.ps1 -WhisperLanguage it

Output
- Per ogni audio viene creato:
  <nomefile>.srt (se generato da Whisper)
  <nomefile>_240x320.mp4
  nella stessa cartella del file audio.

Nota sul file SRT (se vuoi farlo manualmente)
- Formato minimo esempio:

1
00:00:00,000 --> 00:00:03,000
Testo sottotitolo prima frase

2
00:00:03,000 --> 00:00:06,500
Seconda frase

