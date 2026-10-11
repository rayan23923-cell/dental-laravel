# Keeps a pool of php-cgi workers (one request each at a time) alive on
# 127.0.0.1:9100.. and restarts any that exit. Caddy spreads requests over them.
param([string]$Root, [int]$Count)
$Root = (Resolve-Path $Root).Path.TrimEnd('\')
$log = "$Root\app\storage\logs\workers.log"

function Write-Log([string]$msg) {
    Add-Content -LiteralPath $log -Value "$(Get-Date -Format s) $msg" -ErrorAction SilentlyContinue
}

function Start-Worker([int]$port) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "$Root\php\php-cgi.exe"
    $psi.Arguments = "-b 127.0.0.1:$port"
    $psi.WorkingDirectory = "$Root\app\public"
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.EnvironmentVariables['PHP_FCGI_MAX_REQUESTS'] = '0'
    $psi.EnvironmentVariables['PHPRC'] = "$Root\php"
    return [System.Diagnostics.Process]::Start($psi)
}

Write-Log "starting $Count workers"
$procs = @{}
while ($true) {
    for ($i = 0; $i -lt $Count; $i++) {
        $p = $procs[$i]
        if ($p -and $p.HasExited) {
            Write-Log "worker $(9100 + $i) exited with code $($p.ExitCode), restarting"
            $p = $null
        }
        if (-not $p) {
            try {
                $procs[$i] = Start-Worker (9100 + $i)
            } catch {
                Write-Log "worker $(9100 + $i) failed to start: $_"
            }
        }
    }
    Start-Sleep -Seconds 2
}
