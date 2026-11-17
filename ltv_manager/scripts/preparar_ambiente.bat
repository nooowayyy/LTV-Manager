@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0.."
echo =====================================================
echo             LTV MANAGER - INSTALACAO
echo =====================================================
where python >nul 2>nul
if errorlevel 1 (
  echo [ERRO] Python nao foi encontrado no PATH.
  echo Instale Python 3.12 ou superior e marque a opcao Add Python to PATH.
  pause
  exit /b 1
)
if not exist ".env" (
  copy ".env.example" ".env" >nul
  echo [INFO] Arquivo .env criado a partir do exemplo.
)
if not exist "venv\Scripts\python.exe" (
  echo [1/5] Criando ambiente virtual...
  python -m venv venv
  if errorlevel 1 goto :error
) else (
  echo [1/5] Ambiente virtual ja existe.
)
echo [2/5] Atualizando pip...
venv\Scripts\python.exe -m pip install --upgrade pip
if errorlevel 1 goto :error
echo [3/5] Instalando dependencias...
venv\Scripts\python.exe -m pip install -r requirements.txt
if errorlevel 1 goto :error
echo [4/5] Aplicando migracoes...
venv\Scripts\python.exe manage.py migrate
if errorlevel 1 goto :error
echo [5/5] Verificando configuracao Django...
venv\Scripts\python.exe manage.py check
if errorlevel 1 goto :error
echo.
echo [OK] Ambiente preparado.
echo Proximo passo: scripts\iniciar_servidor.bat
echo Para criar um administrador: venv\Scripts\python.exe manage.py createsuperuser
pause
exit /b 0
:error
echo.
echo [ERRO] A preparacao foi interrompida. Confira a mensagem acima.
echo Verifique sua conexao com a internet e a instalacao do Python.
pause
exit /b 1
