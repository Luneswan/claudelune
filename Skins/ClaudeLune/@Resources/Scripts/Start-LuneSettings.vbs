' ClaudeLune - opens the settings window with no console flash.
' Lunez (luneswan). MIT licence - see LICENSE.txt.
'
' "cmd /c start powershell" detaches the window from the calling measure, which is
' required - Apply refreshes the skin, and a RunCommand measure kills the process
' it owns - but it flashes a console for as long as cmd lives.
'
' WScript.Shell.Run takes a window style directly: 0 hides it, and False returns
' immediately rather than waiting, so the PowerShell process is orphaned and
' survives the refresh. One launcher, both properties, nothing on screen.

Option Explicit

Dim shell, fso, here, target, command
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

here = fso.GetParentFolderName(WScript.ScriptFullName)
target = fso.BuildPath(here, "Show-LuneSettings.ps1")

If Not fso.FileExists(target) Then
    ' Nothing is listening for an exit code here, so say it plainly rather than
    ' failing silently and leaving the menu entry looking dead.
    MsgBox "ClaudeLune: Show-LuneSettings.ps1 was not found next to this launcher.", _
           vbExclamation, "ClaudeLune"
    WScript.Quit 1
End If

' -STA is required: WPF will not start in a multi-threaded apartment.
' powershell.exe is named rather than pwsh.exe because PowerShell 7 defaults to
' MTA and is absent from a stock Windows install.
command = "powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File """ & target & """"

shell.Run command, 0, False
