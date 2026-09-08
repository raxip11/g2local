@echo off
setlocal
cd /d "C:\Users\olamaman\.openclaw\workspace\projects\g2-voice\g2local"

echo ============================================================
echo   G2 LOCAL PUSH — 2 steps, zero typing
echo ============================================================
echo.
echo  1. On your phone/PC browser: github.com/signup (one-time only:
echo     email verify + captcha)
echo  2. Create a NEW REPO: name it  g2local  - mark it PRIVATE -
echo     leave it EMPTY (no README, no .gitignore).
echo  3. On that repo page, click the green "Code" button and
echo     COPY the URL (https://github.com/YOURNAME/g2local.git)
echo.
set /p URL=Paste that URL here, then press Enter: 
echo.
echo -- adding remote and pushing --
git remote remove origin 2>nul
git remote add origin %URL%
git push -u origin main
if %errorlevel%==0 (
  echo.
  echo ============================================================
  echo   DONE. Watch the build: github.com/YOURNAME/g2local/actions
  echo   First .ipa in ~20 min.
  echo ============================================================
) else (
  echo.
  echo  Push failed. Common fix: a browser window should have popped
  echo  up asking to let git access GitHub - click Authorize.
  echo  If nothing popped up, press Enter to retry once:
  pause
  git push -u origin main
)
echo.
pause
