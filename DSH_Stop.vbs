Option Explicit
Dim shell, fso, folder, command, result
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
folder = fso.GetParentFolderName(WScript.ScriptFullName)
command = Chr(34) & folder & "\manager\DSH-Launcher.exe" & Chr(34) & " stop"
result = shell.Run(command, 0, True)
WScript.Quit result
