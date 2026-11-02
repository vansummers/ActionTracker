@echo off
REM Start-ActionTracker.bat
REM Simple double-click launcher. Shows a brief console flash; for no flash use Start-ActionTracker.vbs
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0ActionTracker.ps1"
