:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Configures COSMOS after an offline installation where the 
:: entire COSMOS directory has been manually copied to another
:: machine. This will setup the environment variables to allow
:: proper COSMOS operations.
:: Usage: OFFLINE_CONFIG_COSMOS
:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

@echo off
SETLOCAL ENABLEEXTENSIONS ENABLEDELAYEDEXPANSION

:: Update this version if making any changes to this script
set INSTALLER_VERSION=1.0
:: This should be run from the install directory
set COSMOS_INSTALL=%~dp0

::::::::::::::::::::::::::
:: Desktop Icon
::::::::::::::::::::::::::

@echo Set oWS = WScript.CreateObject("WScript.Shell") > !COSMOS_INSTALL!\tmp\makeshortcut.vbs
@echo sLinkFile = "!USERPROFILE!\Desktop\COSMOS.lnk" >> !COSMOS_INSTALL!\tmp\makeshortcut.vbs
@echo Set oLink = oWS.CreateShortcut(sLinkFile) >> !COSMOS_INSTALL!\tmp\makeshortcut.vbs
@echo oLink.TargetPath = "!COSMOS_INSTALL!\LAUNCH_DEMO.bat" >> !COSMOS_INSTALL!\tmp\makeshortcut.vbs
@echo oLink.IconLocation = "!COSMOS_INSTALL!\cosmos_icon.ico" >> !COSMOS_INSTALL!\tmp\makeshortcut.vbs
@echo oLink.Save >> !COSMOS_INSTALL!\tmp\makeshortcut.vbs
set /p COSMOS_CONTINUE="Create Desktop Shortcut? [Y/n]: "
IF NOT "!COSMOS_CONTINUE!"=="n" (
  cscript //B !COSMOS_INSTALL!\tmp\makeshortcut.vbs
  if errorlevel 1 (
    echo ERROR: Problem creating desktop shortcut
    @echo ERROR: Problem creating desktop shortcut >> !COSMOS_INSTALL!\INSTALL.log
    pause
  ) else (
    @echo Successfully created desktop shortcut >> !COSMOS_INSTALL!\INSTALL.log
  )
)

::::::::::::::::::::::::::
:: Environment Variables
::::::::::::::::::::::::::

set /p COSMOS_CONTINUE="Set COSMOS_DIR Environment Variable? [Y/n]: "
IF NOT "!COSMOS_CONTINUE!"=="n" (
  setx COSMOS_DIR "!COSMOS_INSTALL!"
  if errorlevel 1 (
    echo ERROR: Problem creating COSMOS_DIR environment variable
    @echo ERROR: Problem creating COSMOS_DIR environment variable >> !COSMOS_INSTALL!\INSTALL.log
    pause
  ) else (
    echo COSMOS_DIR set for Current User.
    echo Add System Environment Variable if desired for all users.
    @echo Successfully created COSMOS_DIR environment variable >> !COSMOS_INSTALL!\INSTALL.log
  )
)

::::::::::::::::::::::::::::::::::::::::::
:: Test Installation by Launching COSMOS
::::::::::::::::::::::::::::::::::::::::::

pushd !COSMOS_INSTALL!
SET COSMOS_DEVEL=
start !COSMOS_INSTALL!\Launch_Demo.bat
echo Add !COSMOS_INSTALL!\Vendor\Ruby\bin to your PATH to make Ruby available
echo COSMOS Launcher should start if installation was successful
echo INSTALLATION COMPLETE

ENDLOCAL
