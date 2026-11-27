@echo off
rem rebuild-compile-db.cmd - one-command rebuild of compile_commands.json from MSBuild tlog
rem usage: rebuild-compile-db.cmd -Src D:\path\to\project  (any terminal; VS env auto-imported)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0rebuild-compile-db.ps1" %*
