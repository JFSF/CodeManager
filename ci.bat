@echo off
rem Integracao continua local: compila (Release/Win64), corre os testes e, se estiver configurado, o Sonar.
rem   ci.bat                  compila + testes
rem   ci.bat sonar            ... e depois analisa com o sonar-scanner
rem O Sonar precisa de SONAR_HOST_URL e SONAR_TOKEN definidos e do sonar-scanner no PATH
rem (ou de SONAR_SCANNER com o caminho do executavel).
rem Codigos de saida: 0 tudo bem · 1 falhou a compilacao · 2 falhou algum teste · 3 falhou o Sonar.
setlocal
set ROOT=%~dp0
echo === [1/3] Compilar ===
call "%ROOT%build.bat" Release Win64
if errorlevel 1 exit /b 1
echo === [2/3] Testes ===
call "%ROOT%tests\run-tests.bat"
if errorlevel 1 exit /b 2
if /i not "%1"=="sonar" goto :ok
echo === [3/3] Sonar ===
if not defined SONAR_HOST_URL (echo SONAR_HOST_URL nao definido & exit /b 3)
if not defined SONAR_TOKEN (echo SONAR_TOKEN nao definido & exit /b 3)
if not defined SONAR_SCANNER set SONAR_SCANNER=sonar-scanner
pushd "%ROOT%"
call %SONAR_SCANNER% -Dsonar.host.url=%SONAR_HOST_URL% -Dsonar.token=%SONAR_TOKEN%
set RC=%errorlevel%
popd
if not "%RC%"=="0" exit /b 3
:ok
echo === OK ===
exit /b 0
