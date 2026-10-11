@echo off
setlocal EnableExtensions
title DentalClinic Offline
set "ROOT=%~dp0"
set "PATH=%ROOT%php;%ROOT%mariadb\bin;%PATH%"
set "DBPORT=3307"
set "WEBPORT=8000"
cd /d "%ROOT%"

echo ============================================
echo   Dental Clinic - offline edition
echo ============================================

rem php.ini with absolute extension path (folder may be moved anywhere)
powershell -NoProfile -ExecutionPolicy Bypass -Command "(Get-Content -LiteralPath '%ROOT%php\php.ini.template') -replace '__EXT_DIR__', '%ROOT%php\ext' | Set-Content -LiteralPath '%ROOT%php\php.ini' -Encoding ASCII"

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
start "DentalClinic-DB" /min "%ROOT%mariadb\bin\mariadbd.exe" --datadir="%ROOT%data" --port=%DBPORT% --bind-address=127.0.0.1 --character-set-server=utf8mb4 --collation-server=utf8mb4_unicode_ci --console

set /a TRIES=0
:waitdb
"%ROOT%mariadb\bin\mariadb-admin.exe" -uroot -h127.0.0.1 -P%DBPORT% ping >nul 2>&1
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

"%ROOT%mariadb\bin\mariadb.exe" -uroot -h127.0.0.1 -P%DBPORT% -e "CREATE DATABASE IF NOT EXISTS dental CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci"

cd /d "%ROOT%app"
if not exist ".env" (
  copy /y ".env.offline" ".env" >nul
  php artisan key:generate --force
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

echo.
echo The system is running. Open in the browser:
echo   On this computer:   http://localhost:%WEBPORT%
echo   On other devices on the same network, use this computer's IP:
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /c:"IPv4"') do for /f "tokens=*" %%b in ("%%a") do echo     http://%%b:%WEBPORT%
echo.
echo Keep this window open. To stop everything run Stop.bat
echo.
start "" "http://localhost:%WEBPORT%"
php artisan serve --host=0.0.0.0 --port=%WEBPORT%
