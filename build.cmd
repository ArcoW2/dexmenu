@echo off
rem Builds DexmenuShell.dll (src\shell) and the test host DexmenuTest.exe (tests\host) into bin, x64, with Visual
rem Studio's C++ tools; intermediate files in obj. Explorer keeps a DLL it loaded open: then the old one is renamed
rem (that is allowed) and the new one takes its name, as LexPen's build does.
setlocal
set "ROOT=%~dp0"
set "OUT=%ROOT%bin"
set "OBJ=%ROOT%obj"
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
set "VS="
if exist "%VSWHERE%" for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VS=%%i"
if not defined VS (
  echo error: Visual Studio's C++ tools ^(Desktop development with C++^) are not installed.
  exit /b 1
)
if not exist "%OUT%" mkdir "%OUT%"
if not exist "%OBJ%\shell" mkdir "%OBJ%\shell"
if not exist "%OBJ%\minhook" mkdir "%OBJ%\minhook"
if not exist "%OBJ%\host" mkdir "%OBJ%\host"
call "%VS%\VC\Auxiliary\Build\vcvars64.bat" >nul 2>nul || exit /b 1

set "MH=%ROOT%src\vendor\minhook\src"
cl /nologo /c /O2 /MT /W3 /Fo"%OBJ%\minhook\\" "%MH%\buffer.c" "%MH%\hook.c" "%MH%\trampoline.c" "%MH%\hde\hde64.c" || exit /b 1
cl /nologo /O2 /EHsc /std:c++20 /W4 /WX /wd4324 /MT /LD /Fo"%OBJ%\shell\\" "%ROOT%src\shell\DexmenuShell.cpp" "%OBJ%\minhook\*.obj" ^
  /link /DEF:"%ROOT%src\shell\DexmenuShell.def" /OUT:"%OBJ%\shell\DexmenuShell.dll" /IMPLIB:"%OBJ%\shell\DexmenuShell.lib" ^
  shell32.lib ole32.lib runtimeobject.lib advapi32.lib user32.lib || exit /b 1
cl /nologo /O2 /EHsc /std:c++20 /W4 /WX /MT /Fo"%OBJ%\host\\" "%ROOT%tests\host\DexmenuTest.cpp" ^
  /link /OUT:"%OUT%\DexmenuTest.exe" shell32.lib ole32.lib user32.lib shlwapi.lib || exit /b 1

del /q "%OUT%\DexmenuShell.*.old" 2>nul
copy /y "%OBJ%\shell\DexmenuShell.dll" "%OUT%\DexmenuShell.dll" >nul 2>nul && exit /b 0
ren "%OUT%\DexmenuShell.dll" "DexmenuShell.%RANDOM%%RANDOM%.old" || exit /b 1
copy /y "%OBJ%\shell\DexmenuShell.dll" "%OUT%\DexmenuShell.dll" >nul || exit /b 1
