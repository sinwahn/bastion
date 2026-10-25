@echo off
REM Bastion setup launcher. Self-elevating. Keeps the window open so you can read the log.
REM   run.cmd            run every module in order
REM   run.cmd firefox    run only modules whose name contains "firefox"
REM   run.cmd firefox nvidia lg-host   run several
net session >nul 2>&1
if %errorlevel% neq 0 (
  echo Requesting administrator rights...
  powershell -NoProfile -ExecutionPolicy Bypass -Command "Start-Process -FilePath cmd -ArgumentList '/c','\"%~f0\" %*' -Verb RunAs"
  exit /b
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
echo.
echo ==== done. Full log: C:\ProgramData\Bastion\setup.log ====
pause
