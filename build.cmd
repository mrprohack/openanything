@echo off
rem Builds open.exe with the C# compiler that ships with Windows (.NET Framework 4). Nothing to install.
"%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe" /nologo /optimize+ /r:System.Web.Extensions.dll /out:"%~dp0open.exe" "%~dp0open.cs"
exit /b %errorlevel%
