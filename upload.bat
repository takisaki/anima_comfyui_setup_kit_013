@echo off
setlocal
cd /d "%~dp0"
echo ================================================
echo  ComfyUI cloud kit uploader
echo ================================================
set /p SRV=Server IP: 
if "%SRV%"=="" goto :eof
set /p PRT=SSH port [22]: 
if "%PRT%"=="" set PRT=22
set /p SUSER=SSH user [root]: 
if "%SUSER%"=="" set SUSER=root
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0upload_windows.ps1" -Server %SRV% -Port %PRT% -SshUser %SUSER%
echo.
pause
