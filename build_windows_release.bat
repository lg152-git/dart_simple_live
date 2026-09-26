@echo off
rem ============================================================
rem  Simple Live - Windows Release ??????
rem  ??: ????, ?? cmd ???:
rem      D:\project\dart_simple_live-master\build_windows_release.bat
rem  ??: simple_live_app\build\windows\x64\SimpleLive_Windows_Release.zip
rem ============================================================
setlocal
set "ROOT=D:\project\dart_simple_live-master"
set "FLUTTER=D:\flutter\bin\flutter.bat"
set "APP=%ROOT%\simple_live_app"
set "OUTDIR=%APP%\build\windows\x64\runner\Release"
set "ZIP=%APP%\build\windows\x64\SimpleLive_Windows_Release.zip"
set "ZIPPS1=%ROOT%\tools\make_zip.ps1"

echo ==== 1/3 ???? ====
cd /d "%APP%"
call "%FLUTTER%" pub get
if errorlevel 1 goto :fail

echo ==== 2/3 ?? Release ====
call "%FLUTTER%" build windows --release
if errorlevel 1 goto :fail

echo ==== 3/3 ??? zip ====
if exist "%ZIP%" del /f /q "%ZIP%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%ZIPPS1%" -OutDir "%OUTDIR%" -ZipPath "%ZIP%"
if errorlevel 1 goto :fail

echo.
echo ============================================================
echo  ????!
echo  ???: %ZIP%
echo  ????: %OUTDIR%\simple_live_app.exe
echo ============================================================
pause
exit /b 0

:fail
echo.
echo [??] ??????, ???????
pause
exit /b 1