# Writes php.ini, Caddyfile and Corefile for the current folder and network,
# keeps APP_URL in app\.env in step with config.txt, and prints the
# computer's LAN address (the only stdout line).
param([string]$Root, [string]$ServerName, [int]$Workers, [string]$ServerIp, [int]$HttpPort = 80, [int]$HttpsPort = 443, [int]$AutoOpen = 1)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path $Root).Path.TrimEnd('\')
$fwd = $Root -replace '\\', '/'

(Get-Content -LiteralPath "$Root\php\php.ini.template") -replace '__EXT_DIR__', "$Root\php\ext" -replace '__CA_FILE__', "$Root\php\cacert.pem" |
    Set-Content -LiteralPath "$Root\php\php.ini" -Encoding ASCII

# Address detection is best effort: Get-NetIPConfiguration throws on some
# adapter setups (several virtual adapters), and under 'Stop' that would
# abort the script before the Caddyfile is written, so the server never
# starts. Fall through to the next method instead.
if (-not $ServerIp) {
    try {
        $cfgs = @(Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.IPv4DefaultGateway -and $_.NetAdapter.Status -eq 'Up' })
        # Prefer a network whose router answers: a cable with a static
        # address but no live router (2026-10-13) was picked first and the
        # phones on the Wi-Fi could not reach the system.
        $cfg = $cfgs | Where-Object {
            try { Test-Connection -ComputerName $_.IPv4DefaultGateway[0].NextHop -Count 1 -Quiet -ErrorAction Stop } catch { $false }
        } | Select-Object -First 1
        if (-not $cfg) { $cfg = $cfgs | Select-Object -First 1 }
        if ($cfg) { $ServerIp = $cfg.IPv4Address[0].IPAddress }
    } catch { $ServerIp = $null }
}
if (-not $ServerIp) {
    try {
        $ServerIp = (Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1).IPAddress
    } catch { $ServerIp = $null }
}
if (-not $ServerIp) { $ServerIp = '127.0.0.1' }

# "Is there internet?" addresses devices check on joining a Wi-Fi. With
# AUTO_OPEN the DNS points them here and the app answers (see
# App\Http\Controllers\CaptivePortalController, same host list): the first check opens
# the setup page, later ones say "connected". Devices only probe port 80.
$captiveHosts = @(
    'connectivitycheck.gstatic.com', 'connectivitycheck.android.com', 'clients1.google.com', 'clients3.google.com',
    'connectivitycheck.samsung.com', 'connect.rom.miui.com', 'conn1.oppomobile.com', 'conn2.oppomobile.com',
    'connectivitycheck.platform.hicloud.com', 'cp.cloudflare.com',
    'captive.apple.com', 'www.appleiphonecell.com', 'www.itools.info', 'www.ibook.info', 'www.airport.us', 'www.thinkdifferent.us',
    'www.msftconnecttest.com', 'msftconnecttest.com', 'www.msftncsi.com', 'detectportal.firefox.com',
    'nmcheck.gnome.org', 'connectivity-check.ubuntu.com'
)
$captiveOn = $AutoOpen -eq 1
$captiveCaddy = if ($captiveOn) {
    @"
	@captive host $($captiveHosts -join ' ')
	handle @captive {
		import app
	}
	handle /portal {
		import app
	}
"@
} else { '' }
$captiveDns = if ($captiveOn) { ($captiveHosts | ForEach-Object { "`t`t$ServerIp $_" }) -join "`n" } else { '' }

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

# Files served over plain http, on the network and on this computer: the
# certificate, the setup page and the program for the other computers
# (client\, see offline/windows/client). The client downloads the
# certificate from here before it trusts https.
(lanfiles) {
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
	handle /client {
		redir * /client/ 302
	}
	handle /client/* {
		root * "$fwd"
		header Cache-Control no-cache
		file_server
	}
	handle /apps {
		redir * /apps/ 302
	}
	handle /apps/* {
		root * "$fwd"
		header Cache-Control no-cache
		file_server
	}
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
	import lanfiles
	handle {
		import app
	}
}

# Plain http on the network: the certificate and setup page, everything
# else goes to https.
http://:$HttpPort {
$captiveCaddy
	import lanfiles
	handle {
		redir https://$httpsHost{uri} 302
	}
}
"@ | Set-Content -LiteralPath "$Root\Caddyfile" -Encoding ASCII

@"
. {
	hosts {
		$ServerIp $ServerName
$captiveDns
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
