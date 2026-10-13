@echo off
rem Builds open.exe and open-setup.exe with the C# compiler that ships with Windows (.NET Framework 4). Nothing to install.
set csc="%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /optimize+
%csc% /r:System.Web.Extensions.dll /out:"%~dp0open.exe" "%~dp0open.cs" || exit /b 1
%csc% /target:winexe /r:System.Windows.Forms.dll /resource:"%~dp0open.exe",open.exe /out:"%~dp0open-setup.exe" "%~dp0setup.cs"
exit /b %errorlevel%
