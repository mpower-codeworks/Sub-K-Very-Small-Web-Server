@echo off
setlocal

echo Building Tiny Web Server - TWS...

ml /nologo /c /coff /Cp tws.asm
if errorlevel 1 goto build_failed

crinkler tws.obj ^
  /OUT:tws.exe ^
  /ENTRY:start ^
  /SUBSYSTEM:CONSOLE ^
  /NOINITIALIZERS ^
  /TINYIMPORT ^
  /HASHSIZE:11 ^
  /ORDERTRIES:2000 ^
  /LIBPATH:"C:\Program Files (x86)\Windows Kits\10\Lib\10.0.20348.0\um\x86" ^
  kernel32.lib ws2_32.lib
if errorlevel 1 goto build_failed

del tws.obj

echo.
echo Build complete: tws.exe
echo Run tws.exe, then open http://localhost:8080/
goto done

:build_failed
echo.
echo Build failed.

:done
endlocal