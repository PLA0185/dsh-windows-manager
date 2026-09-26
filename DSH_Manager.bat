@echo off
setlocal
title DSH Manager
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0manager\DSH-Manager.ps1"
set "DSH_EXIT=%errorlevel%"
if not "%DSH_EXIT%"=="0" (
  echo DSH manager failed. See manager\logs.
  if not "%~1"=="--no-pause" pause
)
exit /b %DSH_EXIT%
