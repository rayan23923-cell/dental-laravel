<?php

namespace App\Support;

use App\Models\OfflineLicense;

/**
 * Activation of the offline edition (2026-10-17, by request).
 *
 * The hosted system signs each activation with an Ed25519 key derived from
 * its APP_KEY, so the key needs no storage of its own. The offline copy keeps
 * the signed licence and the public key in storage/app/offline-license.json
 * and works only while the licence is genuine and names this computer.
 *
 * The machine id is a hash of Windows' MachineGuid, which the control panel
 * (offline/windows/panel/DentalClinic.cs) passes to PHP as DENTAL_MACHINE_GUID and
 * in storage/app/machine-guid.txt;
 * it stays the same when network cards change, unlike a MAC address.
 */
class OfflineLicensing
{
    /** Hosted side: this server's signing keypair. */
    private static function keypair(): string
    {
        return sodium_crypto_sign_seed_keypair(hash('sha256', 'offline-license|'.config('app.key'), true));
    }

    public static function publicKey(): string
    {
        return base64_encode(sodium_crypto_sign_publickey(self::keypair()));
    }

    /** Hosted side: the signed licence handed to the computer that activated. */
    public static function issue(OfflineLicense $license): array
    {
        $payload = json_encode([
            'code' => $license->code,
            'university' => $license->university,
            'machine_id' => $license->machine_id,
            'activated_at' => $license->activated_at?->toIso8601String(),
        ], JSON_UNESCAPED_UNICODE);

        return [
            'payload' => $payload,
            'signature' => base64_encode(sodium_crypto_sign_detached($payload, sodium_crypto_sign_secretkey(self::keypair()))),
            'public_key' => self::publicKey(),
        ];
    }

    /** The licence's details when it is genuine, else null. */
    public static function verify(?array $license): ?array
    {
        $payload = $license['payload'] ?? null;
        $signature = base64_decode((string) ($license['signature'] ?? ''), true);
        $key = base64_decode((string) ($license['public_key'] ?? ''), true);
        if (! is_string($payload) || ! $signature || ! $key || strlen($key) !== SODIUM_CRYPTO_SIGN_PUBLICKEYBYTES || strlen($signature) !== SODIUM_CRYPTO_SIGN_BYTES) {
            return null;
        }
        try {
            if (! sodium_crypto_sign_verify_detached($signature, $payload, $key)) {
                return null;
            }
        } catch (\SodiumException) {
            return null;
        }
        $data = json_decode($payload, true);

        return is_array($data) ? $data : null;
    }

    public static function path(): string
    {
        return storage_path('app/offline-license.json');
    }

    /** Offline side: the saved licence, when it is genuine and for this computer. */
    public static function current(): ?array
    {
        $file = self::path();
        $saved = is_file($file) ? json_decode((string) file_get_contents($file), true) : null;
        $data = self::verify(is_array($saved) ? $saved : null);

        return $data && hash_equals((string) ($data['machine_id'] ?? ''), self::machineId()) ? $data : null;
    }

    public static function save(array $license): void
    {
        file_put_contents(self::path(), json_encode($license, JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT));
    }

    /** Offline side: needs activating before it can be used. */
    public static function required(): bool
    {
        return config('offline.edition') && config('offline.activation');
    }

    private static ?string $machineId = null;

    /** This computer's id, shown on the activation page: XXXX-XXXX-XXXX-XXXX. */
    public static function machineId(): string
    {
        if (self::$machineId !== null) {
            return self::$machineId;
        }
        $guid = trim((string) getenv('DENTAL_MACHINE_GUID'));
        // Written by the panel on every start (PHP behind FastCGI may not see its environment).
        $file = storage_path('app/machine-guid.txt');
        if ($guid === '' && is_file($file)) {
            $guid = trim((string) file_get_contents($file));
        }
        if ($guid === '' && PHP_OS_FAMILY === 'Windows' && function_exists('shell_exec')) {
            $out = (string) @shell_exec('reg query "HKLM\SOFTWARE\Microsoft\Cryptography" /v MachineGuid /reg:64 2>NUL');
            $guid = preg_match('/MachineGuid\s+REG_SZ\s+(\S+)/i', $out, $m) ? $m[1] : '';
        }
        if ($guid === '') {
            $guid = is_file('/etc/machine-id') ? trim((string) file_get_contents('/etc/machine-id')) : (string) gethostname();
        }
        $hash = strtoupper(substr(hash('sha256', 'dental-clinic|'.strtolower($guid)), 0, 16));

        return self::$machineId = implode('-', str_split($hash, 4));
    }

    /** For tests, which switch DENTAL_MACHINE_GUID between computers. */
    public static function forgetMachineId(): void
    {
        self::$machineId = null;
    }

    public static function machineName(): string
    {
        return (string) (getenv('COMPUTERNAME') ?: gethostname());
    }

    /** Offline side: this package's build number (version.txt beside the app folder), if known. */
    public static function installedBuild(): ?int
    {
        $file = base_path('../version.txt');
        $build = is_file($file) ? trim((string) file_get_contents($file)) : '';

        return ctype_digit($build) ? (int) $build : null;
    }

    /** Hosted side: the newest offline build, from what the workflow uploaded. */
    public static function latestBuild(): ?array
    {
        $file = public_path('downloads/offline/latest.json');
        $data = is_file($file) ? json_decode((string) file_get_contents($file), true) : null;

        return is_array($data) && isset($data['build'], $data['url']) ? $data : null;
    }
}
