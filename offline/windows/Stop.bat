@echo off
setlocal
set "ROOT=%~dp0"
echo Stopping Dental Clinic offline...
taskkill /FI "WINDOWTITLE eq DentalClinic-Scheduler*" /T /F >nul 2>&1
taskkill /FI "WINDOWTITLE eq DentalClinic Offline*" /T /F >nul 2>&1
"%ROOT%mariadb\bin\mariadb-admin.exe" -uroot -h127.0.0.1 -P3307 shutdown >nul 2>&1
echo Stopped.
timeout /t 2 /nobreak >nul
