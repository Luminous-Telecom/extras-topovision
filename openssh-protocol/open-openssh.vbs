' Launcher silencioso — sem janela do PowerShell.
' Uso: wscript.exe //B //Nologo open-openssh.vbs "openssh://open?h=10.0.0.1"

If WScript.Arguments.Count < 1 Then
  WScript.Quit 1
End If

Dim uri, fso, folder, ps1, cmd, sh
uri = WScript.Arguments(0)

Set fso = CreateObject("Scripting.FileSystemObject")
folder = fso.GetParentFolderName(WScript.ScriptFullName)
ps1 = folder & "\open-openssh.ps1"

If Not fso.FileExists(ps1) Then
  WScript.Quit 2
End If

Set sh = CreateObject("WScript.Shell")
cmd = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ & ps1 & """ """ & Replace(uri, """", "") & """"
sh.Run cmd, 0, False
