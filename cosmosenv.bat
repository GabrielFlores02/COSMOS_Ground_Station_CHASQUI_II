@ECHO OFF

SET "DESTINATION_DIR=%~dp0"

:: Convert DESTINATION_DIR to absolute path
pushd %DESTINATION_DIR%
SET "DESTINATION_DIR=%CD%\"
popd

:: Set environmental variables
for /f "delims=" %%a in ('dir "%DESTINATION_DIR%Vendor\Ruby\lib\ruby\gems\2*" /on /ad /b') do set RUBY_ABI=%%a
SET "GEM_HOME=%DESTINATION_DIR%Vendor\Ruby\lib\ruby\gems\%RUBY_ABI%"
SET "GEM_PATH=%GEM_HOME%"
SET "GEMRC=%DESTINATION_DIR%Vendor\Ruby\lib\ruby\gems\etc\gemrc"

:: Prepend embedded bin to PATH so we prefer those binaries
SET "RI_DEVKIT=%DESTINATION_DIR%Vendor\Devkit\"
SET "PATH=%DESTINATION_DIR%Vendor\Ruby\bin;%RI_DEVKIT%bin;%RI_DEVKIT%mingw\bin;%DESTINATION_DIR%Vendor\wkhtmltopdf;%PATH%"

:: Remove RUBYOPT and RUBYLIB, which can cause serious problems.
SET RUBYOPT=
SET RUBYLIB=
