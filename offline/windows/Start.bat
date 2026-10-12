@echo off
setlocal EnableExtensions
title DentalClinic Offline
set "ROOT=%~dp0"
set "XDG_DATA_HOME=%ROOT%caddy-data"
set "XDG_CONFIG_HOME=%ROOT%caddy-data"
set "PATH=%ROOT%php;%ROOT%mariadb\bin;%PATH%"
set "DBPORT=3307"
set "SERVER_NAME=clinic.lan"
set "PHP_WORKERS=16"
set "SERVER_IP="
set "HTTP_PORT=80"
set "HTTPS_PORT=443"
for /f "usebackq eol=# tokens=1,* delims==" %%a in ("%ROOT%config.txt") do set "%%a=%%b"
cd /d "%ROOT%"

echo ============================================
echo   Dental Clinic - offline edition
echo ============================================

for /f "usebackq delims=" %%i in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%prepare.ps1" -Root "%ROOT%." -ServerName "%SERVER_NAME%" -Workers %PHP_WORKERS% -ServerIp "%SERVER_IP%" -HttpPort %HTTP_PORT% -HttpsPort %HTTPS_PORT%`) do set "LAN_IP=%%i"

php -v >nul 2>&1
if errorlevel 1 (
  echo Installing Microsoft Visual C++ runtime needed by PHP...
  start "" /wait "%ROOT%vc_redist.x64.exe" /install /passive /norestart
  php -v >nul 2>&1
  if errorlevel 1 (
    echo PHP could not start. Run vc_redist.x64.exe from this folder, then try again.
    pause
    exit /b 1
  )
)

if not exist "%ROOT%data\mysql" (
  echo First run: creating the database files...
  "%ROOT%mariadb\bin\mariadb-install-db.exe" --datadir="%ROOT%data" --port=%DBPORT% >nul
)

echo Starting the database...
start "DentalClinic-DB" /min "%ROOT%mariadb\bin\mariadbd.exe" --datadir="%ROOT%data" --port=%DBPORT% --bind-address=127.0.0.1 --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci --max-connections=500 --innodb-buffer-pool-size=512M --console

set /a TRIES=0
:waitdb
"%ROOT%mariadb\bin\mariadb-admin.exe" --user=root --host=127.0.0.1 --port=%DBPORT% ping >nul 2>&1
if not errorlevel 1 goto dbready
set /a TRIES+=1
if %TRIES% GEQ 60 (
  echo The database did not start. See data\*.err for details.
  pause
  exit /b 1
)
timeout /t 1 /nobreak >nul
goto waitdb
:dbready

"%ROOT%mariadb\bin\mariadb.exe" --user=root --host=127.0.0.1 --port=%DBPORT% -e "CREATE DATABASE IF NOT EXISTS dental CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"

cd /d "%ROOT%app"
if not exist ".env" (
  copy /y ".env.offline" ".env" >nul
  php artisan key:generate --force
  cd /d "%ROOT%"
  powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%prepare.ps1" -Root "%ROOT%." -ServerName "%SERVER_NAME%" -Workers %PHP_WORKERS% -ServerIp "%SERVER_IP%" -HttpPort %HTTP_PORT% -HttpsPort %HTTPS_PORT% >nul
  cd /d "%ROOT%app"
)

echo Updating the database tables...
php artisan migrate --force
if errorlevel 1 (
  echo Database update failed.
  pause
  exit /b 1
)
if not exist "%ROOT%data\.seeded" (
  php artisan db:seed --force && echo seeded> "%ROOT%data\.seeded"
)
if not exist "public\storage" php artisan storage:link >nul 2>&1
php artisan optimize >nul 2>&1

start "DentalClinic-Scheduler" /min php artisan schedule:work
cd /d "%ROOT%"
start "DentalClinic-Workers" /min powershell -NoProfile -ExecutionPolicy Bypass -File "%ROOT%workers.ps1" -Root "%ROOT%." -Count %PHP_WORKERS%
start "DentalClinic-DNS" /min "%ROOT%coredns\coredns.exe" -conf "%ROOT%Corefile"

set "WEBH="
set "WEBS="
if not "%HTTP_PORT%"=="80" set "WEBH=:%HTTP_PORT%"
if not "%HTTPS_PORT%"=="443" set "WEBS=:%HTTPS_PORT%"

echo.
echo The system is running.
echo   On every device:      https://%SERVER_NAME%%WEBS%
echo   Or by number:         https://%LAN_IP%%WEBS%
echo   On this computer:     http://localhost%WEBH%
echo.
echo   Once per device, open http://%SERVER_NAME%%WEBH%/setup and install the
echo   clinic certificate (needed for HTTPS and the QR camera).
echo   For the name to work, set the router (Deco) DNS server to %LAN_IP%.
echo   Run Setup-Firewall.bat once as administrator.
echo.
echo Keep this window open. To stop everything run Stop.bat
echo.
start "" "http://localhost%WEBH%"
"%ROOT%caddy\caddy.exe" run --config "%ROOT%Caddyfile" --adapter caddyfile
echo.
echo The web server stopped. If the message above says port %HTTP_PORT% or %HTTPS_PORT%
echo is in use, close the program using it (XAMPP, IIS, Skype) or change
echo HTTP_PORT / HTTPS_PORT in config.txt, then run Stop.bat and Start.bat again.
pause
