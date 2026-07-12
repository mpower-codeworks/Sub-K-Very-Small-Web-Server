cls
@echo off
setlocal

echo Building Sub-K regular MASM/LINK build...

ml /nologo /c /coff /Cp sbk.asm
if errorlevel 1 goto build_failed

REM ------------------------------------------------------------------
REM Crinkler tiny build disabled for regular MASM/LINK testing.
REM ------------------------------------------------------------------
REM crinkler sbk.obj ^
REM  /OUT:sbk.exe ^
REM  /ENTRY:start ^
REM  /SUBSYSTEM:CONSOLE ^
REM  /NOINITIALIZERS ^
REM  /TINYIMPORT ^
REM  /HASHSIZE:1 ^
REM  /ORDERTRIES:2000 ^
REM  /LIBPATH:"C:\Program Files (x86)\Windows Kits\10\Lib\10.0.20348.0\um\x86" ^
REM  kernel32.lib ws2_32.lib
REM if errorlevel 1 goto build_failed

link /nologo ^
 /OUT:sbk.exe ^
 /ENTRY:start ^
 /SUBSYSTEM:CONSOLE ^
 /MACHINE:X86 ^
 /NODEFAULTLIB ^
 /LIBPATH:"C:\Program Files (x86)\Windows Kits\10\Lib\10.0.20348.0\um\x86" ^
 sbk.obj kernel32.lib ws2_32.lib
if errorlevel 1 goto build_failed

del sbk.obj 2>nul

echo.
echo Build complete: sbk.exe
echo Run sbk.exe, then open http://localhost:8080/
goto done

:build_failed
echo.
echo Build failed.

:done
endlocal