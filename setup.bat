@echo off
echo [INFO] Iniciando instalacion del entorno Antigravity Embedded...
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Deploy-Environment.ps1" %*
if %errorlevel% neq 0 (
    echo [FAIL] La instalacion termino con errores. Revisa setup.log.
    pause
    exit /b %errorlevel%
)
echo [OK] Instalacion completada con exito.
pause
