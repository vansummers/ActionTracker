' Start-ActionTracker.vbs
' Launches the Action Tracker widget with NO console window flash.
' Double-click this file to run the widget.
Dim sh, fso, scriptDir
Set sh  = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
sh.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File """ & scriptDir & "\ActionTracker.ps1""", 0, False
