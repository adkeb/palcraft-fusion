@echo off
setlocal
where py >nul 2>nul
if %errorlevel% equ 0 (
  py -3 "%~dp0palcraft.py" menu %*
) else (
  where python >nul 2>nul
  if errorlevel 1 (
    echo Python 3 is required. Install the Python version in the player guide.
    pause
    exit /b 2
  )
  python "%~dp0palcraft.py" menu %*
)
pause
