# Writes php.ini, Caddyfile and Corefile for the current folder and network,
# keeps APP_URL in app\.env in step with config.txt, and prints the
# computer's LAN address (the only stdout line).
param([string]$Root, [string]$ServerName, [int]$Workers, [string]$ServerIp, [int]$HttpPort = 80, [int]$HttpsPort = 443)
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
$ca = "$fwd/caddy-data/caddy/pki/authorities/local"
$httpsHost = if ($HttpsPort -eq 443) { '{host}' } else { "{host}:$HttpsPort" }
@"
{
	admin off
	http_port $HttpPort
	https_port $HttpsPort
	local_certs
	skip_install_trust
	# Our own http site below serves the certificate and setup page and does
	# the redirect for everything else, so Caddy must not redirect first.
	auto_https disable_redirects
	log {
		output file "$fwd/app/storage/logs/caddy.log"
		level ERROR
	}
}

(app) {
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

# HTTPS for every device on the network (the browser camera needs it).
# The certificate comes from this folder's own local authority; devices
# install its root once from http://$ServerName/setup.
https://${ServerName}:$HttpsPort, https://${ServerIp}:$HttpsPort {
	tls internal
	import app
}

# On this computer itself plain http works (localhost counts as secure).
http://127.0.0.1:$HttpPort, http://localhost:$HttpPort {
	import app
}

# Plain http on the network: the certificate and setup page, everything
# else goes to https.
http://:$HttpPort {
	handle /ca.crt {
		root * "$ca"
		rewrite * /root.crt
		header Content-Type application/x-x509-ca-cert
		header Content-Disposition "attachment; filename=clinic-ca.crt"
		file_server
	}
	handle /setup {
		root * "$fwd/setup"
		rewrite * /index.html
		file_server
	}
	handle {
		redir https://$httpsHost{uri} 302
	}
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
    $url = if ($HttpsPort -eq 443) { "https://$ServerName" } else { "https://${ServerName}:$HttpsPort" }
    $lines = Get-Content -LiteralPath $envFile | ForEach-Object { if ($_ -like 'APP_URL=*') { "APP_URL=$url" } else { $_ } }
    Set-Content -LiteralPath $envFile -Value $lines -Encoding UTF8
}

Set-Content -LiteralPath "$Root\lan-ip.txt" -Value $ServerIp -Encoding ASCII
Write-Output $ServerIp
