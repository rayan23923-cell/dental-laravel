@echo off
rem Run once: lets devices on the local network reach the system (web and DNS).
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)
netsh advfirewall firewall delete rule name="DentalClinic Web" >nul 2>&1
netsh advfirewall firewall delete rule name="DentalClinic DNS" >nul 2>&1
netsh advfirewall firewall add rule name="DentalClinic Web" dir=in action=allow protocol=TCP localport=80 remoteip=localsubnet profile=any
netsh advfirewall firewall add rule name="DentalClinic DNS" dir=in action=allow protocol=UDP localport=53 remoteip=localsubnet profile=any
echo Done. Devices on this network can now reach the system.
pause
