@echo off
rem Builds DexmenuShell.dll (src\dll, Delphi's dcc64) and the test host DexmenuTest.exe (tests\host, Visual Studio's
rem C++ tools) into bin, 64-bit; intermediate files in obj. Explorer keeps a DLL it loaded open: then the old one is
rem renamed (that is allowed) and the new one takes its name, as LexPen's build does.
rem Delphi: DELPHI_ROOT, else the newest RootDir under HKLM\SOFTWARE\WOW6432Node\Embarcadero\BDS.
setlocal
set "ROOT=%~dp0"
set "OUT=%ROOT%bin"
set "OBJ=%ROOT%obj"
if not exist "%OUT%" mkdir "%OUT%"
if not exist "%OBJ%\dll" mkdir "%OBJ%\dll"
if not exist "%OBJ%\host" mkdir "%OBJ%\host"

if not defined DELPHI_ROOT for /f "tokens=2,*" %%a in ('reg query "HKLM\SOFTWARE\WOW6432Node\Embarcadero\BDS" /s /v RootDir 2^>nul ^| findstr RootDir') do set "DELPHI_ROOT=%%b"
if not exist "%DELPHI_ROOT%bin\dcc64.exe" (
  echo error: Delphi's dcc64 not found ^(set DELPHI_ROOT to the Studio folder^).
  exit /b 1
)
"%DELPHI_ROOT%bin\dcc64.exe" -Q -B -W- "-NSSystem;Winapi;System.Win" "-U%ROOT%src\vendor\DDetours;%DELPHI_ROOT%lib\win64\release" ^
  "-I%ROOT%src\vendor\DDetours" "-E%OBJ%\dll" "-NU%OBJ%\dll" "%ROOT%src\dll\DexmenuShell.dpr" || exit /b 1

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
set "VS="
if exist "%VSWHERE%" for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS=%%i"
if not defined VS (
  echo error: Visual Studio's C++ tools ^(Desktop development with C++^) are not installed.
  exit /b 1
)
call "%VS%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>nul || exit /b 1
cl /nologo /O2 /EHsc /std:c++20 /W4 /WX /MT /Fo"%OBJ%\host\\" "%ROOT%tests\host\DexmenuTest.cpp" ^
  /link /OUT:"%OUT%\DexmenuTest.exe" shell32.lib ole32.lib user32.lib shlwapi.lib || exit /b 1

del /q "%OUT%\DexmenuShell.*.old" 2>nul
copy /y "%OBJ%\dll\DexmenuShell.dll" "%OUT%\DexmenuShell.dll" >nul 2>nul && exit /b 0
ren "%OUT%\DexmenuShell.dll" "DexmenuShell.%RANDOM%%RANDOM%.old" || exit /b 1
copy /y "%OBJ%\dll\DexmenuShell.dll" "%OUT%\DexmenuShell.dll" >nul || exit /b 1
