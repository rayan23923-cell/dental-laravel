# Keeps a pool of php-cgi workers (one request each at a time) alive on
# 127.0.0.1:9100.. and restarts any that exit. Caddy spreads requests over them.
param([string]$Root, [int]$Count)
$Root = (Resolve-Path $Root).Path.TrimEnd('\')
$env:PHP_FCGI_MAX_REQUESTS = '0'
$env:PHPRC = "$Root\php"
$procs = @{}
while ($true) {
    for ($i = 0; $i -lt $Count; $i++) {
        $p = $procs[$i]
        if (-not $p -or $p.HasExited) {
            $procs[$i] = Start-Process -FilePath "$Root\php\php-cgi.exe" -ArgumentList '-b', "127.0.0.1:$(9100 + $i)" `
                -WorkingDirectory "$Root\app\public" -WindowStyle Hidden -PassThru
        }
    }
    Start-Sleep -Seconds 2
}
