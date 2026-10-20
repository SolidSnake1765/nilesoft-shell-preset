@echo off
rem Installs the Nilesoft Shell context menu preset (asks for administrator rights)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup\install.ps1"
