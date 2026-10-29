import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../i18n/locale_controller.dart';
import '../network/clinic_network.dart';
import 'app_config.dart';
import 'server_settings.dart';
import 'server_settings_controller.dart';
import '../widgets/tg_spinner.dart';

/// Cloud server or the clinic's offline server on the LAN (2026-10-17) —
/// the app's counterpart of the Windows LAN client's "خادم العيادة"
/// settings. Reached from the login screen and the profile page.
class ServerSettingsScreen extends ConsumerStatefulWidget {
  const ServerSettingsScreen({super.key});

  @override
  ConsumerState<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends ConsumerState<ServerSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late ServerKind _kind;
  late final TextEditingController _host;
  late final TextEditingController _ip;
  late final TextEditingController _httpsPort;
  late final TextEditingController _httpPort;

  bool _busy = false;
  bool? _ok;
  String? _message;

  @override
  void initState() {
    super.initState();
    final s = ref.read(serverSettingsProvider);
    _kind = s.kind;
    _host = TextEditingController(text: s.host);
    _ip = TextEditingController(text: s.ip);
    _httpsPort = TextEditingController(text: '${s.httpsPort}');
    _httpPort = TextEditingController(text: '${s.httpPort}');
  }

  @override
  void dispose() {
    _host.dispose();
    _ip.dispose();
    _httpsPort.dispose();
    _httpPort.dispose();
    super.dispose();
  }

  ServerSettings _settings() => ServerSettings(
        kind: _kind,
        host: _host.text,
        ip: _ip.text,
        httpsPort: int.tryParse(_httpsPort.text.trim()) ?? 443,
        httpPort: int.tryParse(_httpPort.text.trim()) ?? 80,
      ).normalized();

  String _errorText(ClinicConnectionError e, ServerSettings s) {
    final t = ref.read(translationsProvider);
    return trf(t['server.err.${e.failure.name}']!, {'host': s.host});
  }

  /// Checks the server; for the clinic also downloads and checks its root
  /// certificate. Returns the certificate (clinic) or '' (cloud) on
  /// success, null on failure — the reason is shown on screen.
  Future<String?> _check(ServerSettings s) async {
    final t = ref.read(translationsProvider);
    setState(() {
      _busy = true;
      _ok = null;
      _message = null;
    });
    String? result;
    String message;
    try {
      if (s.isClinic) {
        final pem = await ClinicNetwork.downloadCa(s);
        final name = await ClinicNetwork.checkApi(s.apiBaseUrl, server: s, caPem: pem);
        result = pem;
        message = name.isEmpty ? t['server.testOkClinic']! : '${t['server.testOkClinic']!}\n$name';
      } else {
        final name = await ClinicNetwork.checkApi(AppConfig.cloudBaseUrl);
        result = '';
        message = name.isEmpty ? t['server.testOk']! : '${t['server.testOk']!}\n$name';
      }
    } catch (e) {
      message = _errorText(ClinicConnectionError.from(e), s);
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _ok = result != null;
        _message = message;
      });
    }
    return result;
  }

  Future<void> _test() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    await _check(_settings());
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final t = ref.read(translationsProvider);
    final next = await _settings().withPinnedIp();
    if (!mounted) return;
    if (next.ip != _ip.text.trim()) _ip.text = next.ip;
    final previous = ref.read(serverSettingsProvider);
    String? pem;
    if (next.isClinic) {
      pem = await _check(next);
      if (!mounted) return;
      if (pem == null) {
        final saveAnyway = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(t['server.saveFailedTitle']!),
            content: Text(_message ?? ''),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(t['server.cancel']!)),
              TextButton(onPressed: () => Navigator.of(context).pop(true), child: Text(t['server.saveAnyway']!)),
            ],
          ),
        );
        if (saveAnyway != true || !mounted) return;
      }
    }
    setState(() => _busy = true);
    await ref.read(serverSettingsProvider.notifier).apply(next, caPem: pem);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t['server.saved']!)));
    if (previous.id != next.id) {
      context.go('/login');
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final scheme = Theme.of(context).colorScheme;
    final clinic = _kind == ServerKind.clinic;

    String? portValidator(String? v) =>
        ServerSettings.validPort(int.tryParse((v ?? '').trim())) ? null : t['server.invalidPort'];

    return Scaffold(
      appBar: AppBar(title: Text(t['server.title']!)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  RadioGroup<ServerKind>(
                    groupValue: _kind,
                    onChanged: (v) {
                      if (_busy || v == null) return;
                      setState(() {
                        _kind = v;
                        _ok = null;
                        _message = null;
                      });
                    },
                    child: Column(
                      children: [
                        RadioListTile<ServerKind>(
                          value: ServerKind.cloud,
                          title: Text(t['server.cloud']!),
                          subtitle: Text(t['server.cloudHint']!),
                        ),
                        RadioListTile<ServerKind>(
                          value: ServerKind.clinic,
                          title: Text(t['server.clinic']!),
                          subtitle: Text(t['server.clinicHint']!),
                        ),
                      ],
                    ),
                  ),
                  if (clinic) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _host,
                      enabled: !_busy,
                      textDirection: TextDirection.ltr,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: InputDecoration(
                        labelText: t['server.host'],
                        helperText: t['server.hostHint'],
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _ip,
                      enabled: !_busy,
                      textDirection: TextDirection.ltr,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                      decoration: InputDecoration(
                        labelText: t['server.ip'],
                        helperText: t['server.ipHint'],
                        helperMaxLines: 3,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final ip = (v ?? '').trim();
                        return ip.isEmpty || ServerSettings.isIpv4(ip) ? null : t['server.invalidIp'];
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _httpsPort,
                            enabled: !_busy,
                            textDirection: TextDirection.ltr,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(labelText: t['server.httpsPort'], border: const OutlineInputBorder()),
                            validator: portValidator,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _httpPort,
                            enabled: !_busy,
                            textDirection: TextDirection.ltr,
                            keyboardType: TextInputType.number,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                            decoration: InputDecoration(labelText: t['server.httpPort'], border: const OutlineInputBorder()),
                            validator: portValidator,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  Text(t['server.switchNote']!, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _ok == true ? Colors.green.withValues(alpha: 0.12) : scheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _ok == true ? Icons.check_circle_outline : Icons.error_outline,
                            color: _ok == true ? Colors.green : scheme.onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _message!,
                              style: TextStyle(color: _ok == true ? null : scheme.onErrorContainer),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _test,
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: TgSpinner(strokeWidth: 2))
                        : const Icon(Icons.network_check),
                    label: Text(t['server.test']!),
                  ),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: _busy ? null : _save, child: Text(t['server.save']!)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
