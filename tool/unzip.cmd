@echo off
setlocal EnableDelayedExpansion
set "ZIP="
set "DEST="
:parse
if "%~1"=="" goto run
if /I "%~1"=="-o" (
  shift
  goto parse
)
if /I "%~1"=="-d" (
  set "DEST=%~2"
  shift
  shift
  goto parse
)
set "ZIP=%~1"
shift
goto parse
:run
if not exist "%DEST%" mkdir "%DEST%"
tar -xf "%ZIP%" -C "%DEST%"
exit /b %ERRORLEVEL%
