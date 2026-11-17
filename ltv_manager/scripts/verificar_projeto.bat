@echo off
chcp 65001 >nul
cd /d "%~dp0.."
if not exist "venv\Scripts\python.exe" (
  echo [ERRO] Ambiente virtual ausente. Execute scripts\preparar_ambiente.bat
  pause
  exit /b 1
)
echo [1/4] Checagem Django...
venv\Scripts\python.exe manage.py check
if errorlevel 1 goto :error
echo [2/4] Conferindo estado das migracoes...
venv\Scripts\python.exe manage.py makemigrations --check --dry-run
if errorlevel 1 goto :error
echo [3/4] Testes automatizados...
venv\Scripts\python.exe manage.py test ltv.tests
if errorlevel 1 goto :error
echo [4/4] Compilacao Python...
venv\Scripts\python.exe -m compileall -q config ltv manage.py
if errorlevel 1 goto :error
echo.
echo [OK] Verificacoes concluidas.
pause
exit /b 0
:error
echo.
echo [FALHA] Uma das verificacoes falhou. Leia a saida acima.
pause
exit /b 1
