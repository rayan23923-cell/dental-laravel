# Writes php.ini, Caddyfile and Corefile for the current folder and network,
# keeps APP_URL in app\.env in step with config.txt, and prints the
# computer's LAN address (the only stdout line).
param([string]$Root, [string]$ServerName, [int]$Workers, [int]$WebPort, [string]$ServerIp)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path $Root).Path.TrimEnd('\')
$fwd = $Root -replace '\\', '/'

(Get-Content -LiteralPath "$Root\php\php.ini.template") -replace '__EXT_DIR__', "$Root\php\ext" |
    Set-Content -LiteralPath "$Root\php\php.ini" -Encoding ASCII

if (-not $ServerIp) {
    $cfg = Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' } | Select-Object -First 1
    if ($cfg) { $ServerIp = $cfg.IPv4Address[0].IPAddress }
}
if (-not $ServerIp) {
    $ServerIp = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1).IPAddress
}
if (-not $ServerIp) { $ServerIp = '127.0.0.1' }

$upstreams = (0..($Workers - 1) | ForEach-Object { "127.0.0.1:$(9100 + $_)" }) -join ' '
@"
{
	admin off
	auto_https off
	log {
		output file "$fwd/app/storage/logs/caddy.log"
		level ERROR
	}
}

:$WebPort {
	root * "$fwd/app/public"
	encode gzip
	request_body {
		max_size 64MB
	}
	php_fastcgi $upstreams {
		lb_policy least_conn
		lb_try_duration 10s
		dial_timeout 3s
		read_timeout 300s
	}
	file_server
}
"@ | Set-Content -LiteralPath "$Root\Caddyfile" -Encoding ASCII

@"
. {
	hosts {
		$ServerIp $ServerName
		ttl 60
		fallthrough
	}
	forward . 8.8.8.8 1.1.1.1
	cache 60
	errors
}
"@ | Set-Content -LiteralPath "$Root\Corefile" -Encoding ASCII

$envFile = "$Root\app\.env"
if (Test-Path $envFile) {
    $url = if ($WebPort -eq 80) { "http://$ServerName" } else { "http://${ServerName}:$WebPort" }
    $lines = Get-Content -LiteralPath $envFile | ForEach-Object { if ($_ -like 'APP_URL=*') { "APP_URL=$url" } else { $_ } }
    Set-Content -LiteralPath $envFile -Value $lines -Encoding UTF8
}

Write-Output $ServerIp
