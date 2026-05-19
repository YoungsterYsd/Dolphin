@echo off
chcp 65001 >nul
rem ============================================================
rem Dolphin Project - Godot Editor Start/Stop helper
rem   start  / s : Launch Godot editor with this project (default)
rem   stop   / k : Kill all Godot_v4.6.2-stable_win64.exe processes
rem   restart/ r : Stop then Start (commonly used to refresh GDScript cache)
rem   status / ? : Show Godot processes
rem
rem Examples:
rem   Tools\godot.bat              -> same as start
rem   Tools\godot.bat restart      -> one-click restart
rem   Tools\godot.bat stop
rem ============================================================
setlocal

set "GODOT_EXE=D:\Godot\CompileResult\Godot_v4.6.2-stable_win64.exe"
set "PROJECT_DIR=%~dp0.."
set "PROJECT_FILE=%PROJECT_DIR%\project.godot"
set "GODOT_PROC=Godot_v4.6.2-stable_win64.exe"

if not exist "%GODOT_EXE%" (
	echo [godot.bat] ERROR: Godot exe not found at %GODOT_EXE%
	echo [godot.bat] Please check path or edit GODOT_EXE in this script.
	exit /b 1
)
if not exist "%PROJECT_FILE%" (
	echo [godot.bat] ERROR: project.godot not found at %PROJECT_FILE%
	exit /b 1
)

set "ACTION=%~1"
if "%ACTION%"=="" set "ACTION=start"

if /i "%ACTION%"=="s"        set "ACTION=start"
if /i "%ACTION%"=="k"        set "ACTION=stop"
if /i "%ACTION%"=="r"        set "ACTION=restart"
if /i "%ACTION%"=="?"        set "ACTION=status"

if /i "%ACTION%"=="start"    goto :do_start
if /i "%ACTION%"=="stop"     goto :do_stop
if /i "%ACTION%"=="restart"  goto :do_restart
if /i "%ACTION%"=="status"   goto :do_status

echo [godot.bat] Unknown action: %ACTION%
echo Usage: godot.bat [start^|stop^|restart^|status]
exit /b 2

:do_status
echo [godot.bat] Querying Godot processes...
tasklist /FI "IMAGENAME eq %GODOT_PROC%" 2>nul | findstr /I "Godot" >nul
if errorlevel 1 (
	echo [godot.bat] No running Godot process.
) else (
	tasklist /FI "IMAGENAME eq %GODOT_PROC%"
)
exit /b 0

:do_stop
echo [godot.bat] Killing all %GODOT_PROC% processes...
taskkill /F /IM "%GODOT_PROC%" >nul 2>&1
if errorlevel 1 (
	echo [godot.bat] No process to kill.
) else (
	echo [godot.bat] Killed.
)
exit /b 0

:do_start
echo [godot.bat] Starting Godot editor ...
echo [godot.bat]   exe     = %GODOT_EXE%
echo [godot.bat]   project = %PROJECT_FILE%
start "" "%GODOT_EXE%" --editor --path "%PROJECT_DIR%"
echo [godot.bat] Launched (async).
exit /b 0

:do_restart
echo [godot.bat] === RESTART ===
call :do_stop
rem Wait ~1.5s for the process to fully exit and release file locks
ping 127.0.0.1 -n 2 -w 500 >nul
call :do_start
exit /b 0
