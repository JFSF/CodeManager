@echo off
rem Compila e executa os testes DUnitX (consola, Win64) com o dcc64 do Delphi 13.
rem   tests\run-tests.bat            compila e corre tudo
rem   tests\run-tests.bat --include:TScanProjectTests    (opcoes do DUnitX passam-se tal e qual)
rem O codigo de saida e 0 se tudo passou, 1 se algum teste falhou, 2 se o compilador falhou.
setlocal
rem CM_RSVARS permite indicar outro rsvars.bat (outra versao/instalacao do Delphi)
if not defined CM_RSVARS set "CM_RSVARS=C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
call "%CM_RSVARS%"
set HERE=%~dp0
rem o dcc64 resolve os caminhos relativos do .dpr a partir da pasta actual: fixa-a em tests
cd /d "%HERE%"
if not exist "%HERE%bin" mkdir "%HERE%bin"
if not exist "%HERE%obj" mkdir "%HERE%obj"
"%BDS%\bin\dcc64.exe" "%HERE%CodeManagerTests.dpr" -Q -B -W- ^
  -E"%HERE%bin" -N0"%HERE%obj" ^
  -NSSystem;Xml;Data;Datasnap;Web;Soap;Winapi;System.Win ^
  -U"%BDS%\lib\win64\release";"%BDS%\source\DunitX";"%HERE%..\src\Core";"%HERE%..\src\Infrastructure";"%HERE%..\src\Services" ^
  -I"%BDS%\source\DunitX" -R"%HERE%.."  ^
  -DDEBUG
if errorlevel 1 exit /b 2
"%HERE%bin\CodeManagerTests.exe" %*
exit /b %errorlevel%
