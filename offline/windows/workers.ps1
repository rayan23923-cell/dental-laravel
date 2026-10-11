# Keeps a pool of php-cgi workers (one request each at a time) alive on
# 127.0.0.1:9100.. and restarts any that exit. Caddy spreads requests over them.
param([string]$Root, [int]$Count)
$Root = (Resolve-Path $Root).Path.TrimEnd('\')
$logDir = "$Root\app\storage\logs"
$log = "$logDir\workers.log"

function Write-Log([string]$msg) {
    Add-Content -LiteralPath $log -Value "$(Get-Date -Format s) $msg" -ErrorAction SilentlyContinue
}

# Each worker serves this many requests, then exits and is restarted fresh.
$env:PHP_FCGI_MAX_REQUESTS = '10000'
$env:PHPRC = "$Root\php"

function Start-Worker([int]$port) {
    # Started through cmd with its output sent to a file: php-cgi needs valid
    # standard handles, and launched bare from a hidden process it exits at once.
    # One log per worker (cmd cannot share one redirect file between processes),
    # and /s with outer quotes so cmd keeps the quoted paths intact.
    $cmd = "`"$Root\php\php-cgi.exe`" -b 127.0.0.1:$port >> `"$logDir\php-cgi-$port.log`" 2>&1"
    return Start-Process -FilePath cmd.exe -ArgumentList '/s', '/c', "`"$cmd`"" -WorkingDirectory "$Root\app\public" -WindowStyle Hidden -PassThru
}

Write-Log "starting $Count workers"
$procs = @{}
$restarts = 0
while ($true) {
    for ($i = 0; $i -lt $Count; $i++) {
        $p = $procs[$i]
        if ($p -and $p.HasExited) {
            $restarts++
            if ($restarts -le 50) { Write-Log "worker $(9100 + $i) exited, restarting" }
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
