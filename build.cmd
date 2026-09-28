@echo off
rem Build SleepGuard.exe (needs MinGW-w64 gcc and windres on PATH)
rem
rem MinGW's gcc links its own default-manifest.o, which clashes with ours
rem (two RT_MANIFEST #1). An empty default-manifest.o found first via -B
rem replaces it, so only sleepguard.manifest ends up in the exe.
setlocal
cd /d "%~dp0"
if not exist build mkdir build
echo.> build\empty.c
gcc -c build\empty.c -o build\default-manifest.o || exit /b 1
windres sleepguard.rc -O coff -o build\sleepguard.res.o || exit /b 1
gcc -Bbuild/ -O2 -Wall -Wextra -municode -mwindows -static -s -o SleepGuard.exe sleepguard.c build\sleepguard.res.o -lcomctl32 -lshell32 || exit /b 1
echo built SleepGuard.exe
