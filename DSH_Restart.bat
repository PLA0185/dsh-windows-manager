@echo off
"%SystemRoot%\System32\wscript.exe" "%~dp0DSH_Restart.vbs"
exit /b %errorlevel%
