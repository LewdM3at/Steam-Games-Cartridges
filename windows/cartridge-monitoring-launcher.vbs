' Launches cartridge-monitoring.ps1 with no console window at all.
' Used instead of "powershell.exe -WindowStyle Hidden" because that flag
' still creates a console under the hood before hiding it, which can crash
' the process with STATUS_CONTROL_C_EXIT (0xC000013A) when run from Task
' Scheduler. WScript.Shell.Run with window style 0 never creates one.
'
' The final "True" makes this launcher wait for the monitor to exit instead
' of detaching it. Task Scheduler only tracks THIS process (wscript.exe) -
' if it exited immediately, the monitor would keep running as an orphan
' that Task Scheduler can no longer stop or restart, and reinstalling would
' pile up duplicate monitors instead of replacing the old one.

Dim shell, fso, scriptDir, target

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

scriptDir = fso.GetParentFolderName(WScript.ScriptFullName)
target = scriptDir & "\cartridge-monitoring.ps1"

shell.Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & target & """", 0, True
