param(
    [Parameter(Mandatory = $true)][int]$ExpectedProcessId,
    [int]$DurationSeconds = 120,
    [string]$OutputPath = 'output/overland-performance/foreground.json'
)
$ErrorActionPreference = 'Stop'
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class OverlandBenchmarkForeground {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr window, StringBuilder value, int size);
    [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr window, StringBuilder value, int size);
}
'@
$events = [System.Collections.Generic.List[object]]::new()
$watch = [System.Diagnostics.Stopwatch]::StartNew()
$lastWindow = [IntPtr]::Zero
$checks = 0
$otherProcessChecks = 0
while ($watch.Elapsed.TotalSeconds -lt $DurationSeconds) {
    $window = [OverlandBenchmarkForeground]::GetForegroundWindow()
    [uint32]$foregroundProcessId = 0
    [void][OverlandBenchmarkForeground]::GetWindowThreadProcessId($window, [ref]$foregroundProcessId)
    $checks++
    if ($foregroundProcessId -ne $ExpectedProcessId) { $otherProcessChecks++ }
    if ($window -ne $lastWindow) {
        $className = [Text.StringBuilder]::new(256)
        $title = [Text.StringBuilder]::new(512)
        [void][OverlandBenchmarkForeground]::GetClassName($window, $className, 256)
        [void][OverlandBenchmarkForeground]::GetWindowText($window, $title, 512)
        $events.Add([pscustomobject]@{utc = [DateTime]::UtcNow.ToString('o'); elapsedMs = $watch.ElapsedMilliseconds
            processId = $foregroundProcessId; className = $className.ToString(); title = $title.ToString()})
        $lastWindow = $window
    }
    Start-Sleep -Milliseconds 200
}
$result = [pscustomobject]@{expectedProcessId = $ExpectedProcessId; checks = $checks
    otherProcessChecks = $otherProcessChecks; elapsedMs = $watch.ElapsedMilliseconds; events = $events}
$parent = Split-Path -Parent $OutputPath
if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Output "Foreground observations saved to $OutputPath"
