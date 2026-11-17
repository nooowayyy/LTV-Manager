@echo off
chcp 65001 >nul
cd /d "%~dp0.."
if not exist "venv\Scripts\python.exe" (
  echo [ERRO] Ambiente virtual ausente. Execute primeiro scripts\preparar_ambiente.bat
  pause
  exit /b 1
)
echo Iniciando LTV Manager em http://127.0.0.1:8000/
venv\Scripts\python.exe manage.py migrate
if errorlevel 1 goto :error
venv\Scripts\python.exe manage.py runserver 127.0.0.1:8000
exit /b 0
:error
echo Falha ao aplicar migracoes.
pause
exit /b 1
