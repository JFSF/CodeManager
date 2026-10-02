@echo off
rem Compila o CodeManager com o MSBuild + CodeManager.dproj (Delphi 13).
rem   build.bat [Release|Debug] [Win64|Win32]      (por omissao: Release Win64)
rem A configuracao Debug activa o modo de desenvolvimento (--dev "guiao").
setlocal
set CFG=%1
if "%CFG%"=="" set CFG=Release
set PLAT=%2
if "%PLAT%"=="" set PLAT=Win64
rem CM_RSVARS permite indicar outro rsvars.bat (outra versao/instalacao do Delphi)
if not defined CM_RSVARS set "CM_RSVARS=C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
call "%CM_RSVARS%"
rem Regenera os recursos dos modelos HTML (o templates.res ja vem incluido)
if exist "%BDS%\bin\brcc32.exe" (
  pushd res
  "%BDS%\bin\brcc32.exe" templates.rc -fo..\templates.res >nul
  popd
)
"%FrameworkDir%\msbuild.exe" "%~dp0CodeManager.dproj" /t:Build /p:Config=%CFG% /p:Platform=%PLAT% /nologo /v:m
endlocal
