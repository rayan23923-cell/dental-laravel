@echo off
setlocal
set "ROOT=%~dp0"
echo Stopping Dental Clinic offline...
taskkill /FI "WINDOWTITLE eq DentalClinic-Workers*" /T /F >nul 2>&1
taskkill /FI "WINDOWTITLE eq DentalClinic-Scheduler*" /T /F >nul 2>&1
taskkill /FI "WINDOWTITLE eq DentalClinic-DNS*" /T /F >nul 2>&1
taskkill /FI "WINDOWTITLE eq DentalClinic Offline*" /T /F >nul 2>&1
powershell -NoProfile -Command "Get-Process php-cgi,caddy,coredns -ErrorAction SilentlyContinue | Where-Object { $_.Path -like '%ROOT%*' } | Stop-Process -Force"
"%ROOT%mariadb\bin\mariadb-admin.exe" --user=root --host=127.0.0.1 --port=3307 shutdown >nul 2>&1
echo Stopped.
timeout /t 2 /nobreak >nul
