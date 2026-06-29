# Test-Admin-Token.ps1 - diagnose whether the current Codex agent shell has an admin token.

$ErrorActionPreference = 'Continue'

function Write-Section {
    param([Parameter(Mandatory)][string]$Title)

    Write-Host ''
    Write-Host ('=== {0} ===' -f $Title)
}

function Test-IsAdmin {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Initialize-TokenElevationHelper {
    if ('ProcessTokenElevation' -as [type]) { return }

    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class ProcessTokenElevation {
    private const UInt32 PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    private const UInt32 TOKEN_QUERY = 0x0008;
    private const int TokenElevation = 20;

    [StructLayout(LayoutKind.Sequential)]
    private struct TOKEN_ELEVATION {
        public int TokenIsElevated;
    }

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr OpenProcess(UInt32 processAccess, bool inheritHandle, UInt32 processId);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr processHandle, UInt32 desiredAccess, out IntPtr tokenHandle);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool GetTokenInformation(IntPtr tokenHandle, int tokenInformationClass, IntPtr tokenInformation, int tokenInformationLength, out int returnLength);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    public static string GetElevation(UInt32 pid) {
        IntPtr processHandle = IntPtr.Zero;
        IntPtr tokenHandle = IntPtr.Zero;
        IntPtr elevationPtr = IntPtr.Zero;

        try {
            processHandle = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
            if (processHandle == IntPtr.Zero) {
                return "Unknown";
            }

            if (!OpenProcessToken(processHandle, TOKEN_QUERY, out tokenHandle)) {
                return "Unknown";
            }

            int size = Marshal.SizeOf(typeof(TOKEN_ELEVATION));
            elevationPtr = Marshal.AllocHGlobal(size);
            int returnLength;
            if (!GetTokenInformation(tokenHandle, TokenElevation, elevationPtr, size, out returnLength)) {
                return "Unknown";
            }

            TOKEN_ELEVATION elevation = (TOKEN_ELEVATION)Marshal.PtrToStructure(elevationPtr, typeof(TOKEN_ELEVATION));
            return elevation.TokenIsElevated != 0 ? "True" : "False";
        }
        finally {
            if (elevationPtr != IntPtr.Zero) {
                Marshal.FreeHGlobal(elevationPtr);
            }
            if (tokenHandle != IntPtr.Zero) {
                CloseHandle(tokenHandle);
            }
            if (processHandle != IntPtr.Zero) {
                CloseHandle(processHandle);
            }
        }
    }
}
'@
}

function Get-ProcessElevation {
    param([Parameter(Mandatory)][int]$ProcessId)

    try {
        Initialize-TokenElevationHelper
        return [ProcessTokenElevation]::GetElevation([uint32]$ProcessId)
    }
    catch {
        return 'Unknown'
    }
}

Write-Section 'Current Identity'
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
[pscustomobject]@{
    User = $identity.Name
    AuthenticationType = $identity.AuthenticationType
    IsSystem = $identity.IsSystem
    IsAuthenticated = $identity.IsAuthenticated
    IsInRoleAdministrator = Test-IsAdmin
    CurrentPowerShellPid = $PID
} | Format-List

Write-Section 'whoami /user'
& whoami /user
Write-Host ('ExitCode: {0}' -f $LASTEXITCODE)

Write-Section 'whoami /groups'
& whoami /groups
Write-Host ('ExitCode: {0}' -f $LASTEXITCODE)

Write-Section 'net session'
$netOutput = & cmd.exe /c 'net session 2>&1'
$netExitCode = $LASTEXITCODE
$netOutput | ForEach-Object { Write-Host $_ }
Write-Host ('ExitCode: {0}' -f $netExitCode)

Write-Section 'Parent Process Chain'
try {
    $processes = Get-CimInstance Win32_Process -ErrorAction Stop
    $byPid = @{}
    foreach ($proc in $processes) {
        $byPid[[int]$proc.ProcessId] = $proc
    }

    $chain = @()
    $currentPid = [int]$PID
    while ($byPid.ContainsKey($currentPid)) {
        $proc = $byPid[$currentPid]
        $chain += [pscustomobject]@{
            PID = [int]$proc.ProcessId
            ParentPID = [int]$proc.ParentProcessId
            Name = $proc.Name
            Elevated = Get-ProcessElevation -ProcessId ([int]$proc.ProcessId)
            CommandLine = $proc.CommandLine
        }

        if (-not $proc.ParentProcessId -or $proc.ParentProcessId -eq $currentPid) { break }
        $currentPid = [int]$proc.ParentProcessId
    }

    $chain | Format-List
}
catch {
    Write-Host ('Failed to read parent process chain: {0}' -f $_.Exception.Message)
}
