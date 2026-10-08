@echo off
cd /d "%~dp0"
echo Starting the Java, Eclipse, Tomcat, and Oracle setup.
echo Approve the Administrator prompt if Windows asks for it.
echo Leave the setup window open until it says you can close it.
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-dev-stack.ps1"
if errorlevel 1 (
  echo.
  echo Setup stopped. Read the messages above.
  pause
)
