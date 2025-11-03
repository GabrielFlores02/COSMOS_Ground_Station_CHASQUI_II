Set oWS = WScript.CreateObject("WScript.Shell") 
sLinkFile = "C:\Users\mayur\Desktop\COSMOS.lnk" 
Set oLink = oWS.CreateShortcut(sLinkFile) 
oLink.TargetPath = "C:\Users\mayur\OneDrive\Documents\Github\Hex20-India\HEX20_FLATSAT_C3\COSMOS_C3\\LAUNCH_DEMO.bat" 
oLink.IconLocation = "C:\Users\mayur\OneDrive\Documents\Github\Hex20-India\HEX20_FLATSAT_C3\COSMOS_C3\\cosmos_icon.ico" 
oLink.Save 
