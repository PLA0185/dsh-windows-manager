@echo off
"%SystemRoot%\System32\wscript.exe" "%~dp0DSH_Stop.vbs"
exit /b %errorlevel%
