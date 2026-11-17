@echo off
chcp 65001 >nul
cd /d "%~dp0.."
if not exist "venv\Scripts\python.exe" (
  echo [ERRO] Ambiente virtual ausente. Execute primeiro scripts\preparar_ambiente.bat
  pause
  exit /b 1
)
echo LTV Manager - manutencao automatica
echo Ative a opcao de automacao no painel antes de iniciar este processo.
echo O processo ficara aberto. Use CTRL+C para interromper.
venv\Scripts\python.exe manage.py run_automations --loop
pause
