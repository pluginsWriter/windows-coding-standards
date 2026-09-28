@echo off
rem run-audit.cmd - Windows native launcher, no need to change ExecutionPolicy
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run-audit.ps1" %*
