import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../data/waiting_screen_admin_repository.dart';

/// «نداء الأسماء بالصوت» (2026-11-17, by request) — the web settings page's
/// voice section in the app: on/off, engine, voice, the text before and
/// after the name for each call, repeats, volume, speed, a test button,
/// and (on the Windows server) downloading the voices it does not carry.
/// A downloaded voice joins the list at once and is picked (2026-11-18).
/// The screen reads the values through [VoiceSettingsSectionState.values].
class VoiceSettingsSection extends ConsumerStatefulWidget {
  const VoiceSettingsSection({super.key, required this.initial});

  final VoiceSettings initial;

  @override
  ConsumerState<VoiceSettingsSection> createState() => VoiceSettingsSectionState();
}

class VoiceSettingsSectionState extends ConsumerState<VoiceSettingsSection> {
  late bool _enabled = widget.initial.enabled;
  late String _engine = widget.initial.engine;
  late String _name = widget.initial.name;
  late bool _ready = widget.initial.ready;
  late bool _waiting = widget.initial.waiting;
  late final _readyBefore = TextEditingController(text: widget.initial.readyBefore);
  late final _readyAfter = TextEditingController(text: widget.initial.readyAfter);
  late final _waitingBefore = TextEditingController(text: widget.initial.waitingBefore);
  late final _waitingAfter = TextEditingController(text: widget.initial.waitingAfter);
  late int _repeat = widget.initial.repeat.clamp(1, 5).toInt();
  late double _volume = widget.initial.volume.toDouble();
  late double _rate = widget.initial.rate.clamp(50, 150).toDouble();
  late final List<String> _installed = [...widget.initial.installed];
  final _testName = TextEditingController();
  String _testKind = 'ready';
  bool _testing = false;
  String? _downloading;
  String? _downloadText;
  String? _error;
  final _player = AudioPlayer();

  @override
  void dispose() {
    for (final c in [_readyBefore, _readyAfter, _waitingBefore, _waitingAfter, _testName]) {
      c.dispose();
    }
    _player.dispose();
    super.dispose();
  }

  /// What the save call sends; null when the server has no voice settings.
  Map<String, dynamic>? values() {
    if (!widget.initial.supported) return null;
    return {
      'voice_enabled': _enabled,
      'voice_engine': _engine,
      'voice_name': _name,
      'voice_ready': _ready,
      'voice_ready_before': _readyBefore.text.trim(),
      'voice_ready_after': _readyAfter.text.trim(),
      'voice_waiting': _waiting,
      'voice_waiting_before': _waitingBefore.text.trim(),
      'voice_waiting_after': _waitingAfter.text.trim(),
      'voice_repeat': _repeat,
      'voice_volume': _volume.round(),
      'voice_rate': _rate.round(),
    };
  }

  String _label(Map<String, String> t, String name) => t['voiceCalls.voice_$name'] ?? name;

  String _sentence(String name) {
    final before = (_testKind == 'ready' ? _readyBefore : _waitingBefore).text.trim();
    final after = (_testKind == 'ready' ? _readyAfter : _waitingAfter).text.trim();
    var text = '$before ${name.trim()}'.trim();
    if (after.isNotEmpty) text += (RegExp(r'^[،,.؛:!؟?]').hasMatch(after) ? '' : '، ') + after;
    return text;
  }

  Future<void> _test() async {
    final t = ref.read(translationsProvider);
    final name = _testName.text.trim().isEmpty ? t['voiceCalls.testNameDefault']! : _testName.text.trim();
    setState(() {
      _testing = true;
      _error = null;
    });
    try {
      final bytes = await ref.read(waitingScreenAdminRepositoryProvider).previewVoice(name: name, kind: _testKind, voice: values()!);
      await _player.setVolume(_volume / 100);
      for (var i = 0; i < _repeat; i++) {
        await _player.play(BytesSource(Uint8List.fromList(bytes), mimeType: 'audio/wav'));
        await _player.onPlayerComplete.first;
        if (i < _repeat - 1) await Future<void>.delayed(const Duration(milliseconds: 900));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.userMessage : t['voiceCalls.testFailed']!);
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _download(String voice) async {
    final t = ref.read(translationsProvider);
    setState(() {
      _downloading = voice;
      _downloadText = null;
      _error = null;
    });
    try {
      final repo = ref.read(waitingScreenAdminRepositoryProvider);
      while (true) {
        final (received, total, done) = await repo.downloadVoiceStep(voice);
        if (!mounted) return;
        setState(() => _downloadText = t['voiceCalls.downloading']!
            .replaceAll('{done}', (received / 1048576).toStringAsFixed(1))
            .replaceAll('{total}', (total / 1048576).toStringAsFixed(1)));
        if (done) break;
      }
      setState(() {
        _installed.add(voice);
        _name = voice;
        _downloadText = t['voiceCalls.downloaded']!;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.userMessage : t['voiceCalls.downloadFailed']!);
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  Widget _kind(Map<String, String> t, String kind, bool on, ValueChanged<bool> onChanged, TextEditingController before,
      TextEditingController after) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t['voiceCalls.$kind']!),
              value: on,
              onChanged: onChanged,
            ),
            if (on) ...[
              TextField(
                controller: before,
                maxLength: 150,
                decoration: InputDecoration(labelText: t['voiceCalls.before'], border: const OutlineInputBorder(), isDense: true),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: after,
                maxLength: 150,
                decoration: InputDecoration(labelText: t['voiceCalls.after'], border: const OutlineInputBorder(), isDense: true),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(translationsProvider);
    final theme = Theme.of(context);
    final v = widget.initial;
    if (!v.supported) return const SizedBox.shrink();
    final names = v.names.isEmpty ? [_name] : v.names;
    final installedNames = names.where((n) => _installed.contains(n) || n == _name).toList();
    final missing = names.where((n) => !_installed.contains(n)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(t['voiceCalls.title']!, style: theme.textTheme.titleMedium),
        Text(t['voiceCalls.hint']!, style: theme.textTheme.bodySmall),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(t['voiceCalls.enabled']!),
          value: _enabled,
          onChanged: (x) => setState(() => _enabled = x),
        ),
        if (_enabled) ...[
          DropdownButtonFormField<String>(
            initialValue: _engine,
            isExpanded: true,
            decoration: InputDecoration(labelText: t['voiceCalls.engine'], border: const OutlineInputBorder()),
            items: [
              for (final e in const ['piper', 'windows'])
                DropdownMenuItem(
                  value: e,
                  child: Text('${t['voiceCalls.engine_$e']}${v.engines.contains(e) ? '' : ' — ${t['voiceCalls.missing']}'}'),
                ),
            ],
            onChanged: (x) => setState(() => _engine = x ?? 'piper'),
          ),
          if (_engine == 'piper') ...[
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: ValueKey('voice-${_installed.length}-$_name'),
              initialValue: _name,
              isExpanded: true,
              decoration: InputDecoration(labelText: t['voiceCalls.voice'], border: const OutlineInputBorder()),
              items: [
                for (final n in installedNames)
                  DropdownMenuItem(value: n, child: Text('${_label(t, n)}${_installed.contains(n) ? '' : ' — ${t['voiceCalls.missing']}'}')),
              ],
              onChanged: (x) => setState(() => _name = x ?? _name),
            ),
            if (v.downloadable && missing.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(top: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(t['voiceCalls.more']!, style: theme.textTheme.titleSmall),
                      Text(t['voiceCalls.moreHint']!, style: theme.textTheme.bodySmall),
                      for (final n in missing)
                        Row(
                          children: [
                            Expanded(child: Text(_label(t, n))),
                            TextButton.icon(
                              onPressed: _downloading == null ? () => _download(n) : null,
                              icon: _downloading == n
                                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.download_outlined),
                              label: Text(t['voiceCalls.download']!),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            if (_downloadText != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_downloadText!, style: theme.textTheme.bodySmall?.copyWith(color: Colors.green.shade800)),
              ),
          ],
          const SizedBox(height: 12),
          _kind(t, 'ready', _ready, (x) => setState(() => _ready = x), _readyBefore, _readyAfter),
          _kind(t, 'waiting', _waiting, (x) => setState(() => _waiting = x), _waitingBefore, _waitingAfter),
          Row(
            children: [
              Expanded(child: Text(t['voiceCalls.repeat']!)),
              DropdownButton<int>(
                value: _repeat,
                items: [for (var n = 1; n <= 5; n++) DropdownMenuItem(value: n, child: Text('$n'))],
                onChanged: (x) => setState(() => _repeat = x ?? _repeat),
              ),
            ],
          ),
          Text('${t['voiceCalls.volume']} (${_volume.round()}%)'),
          Slider(value: _volume, min: 0, max: 100, divisions: 20, onChanged: (x) => setState(() => _volume = x)),
          Text('${t['voiceCalls.rate']} (${_rate.round()}%)'),
          Slider(value: _rate, min: 50, max: 150, divisions: 20, onChanged: (x) => setState(() => _rate = x)),
          Text(t['voiceCalls.rateHint']!, style: theme.textTheme.bodySmall),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _testName,
                    decoration: InputDecoration(
                      labelText: t['voiceCalls.testName'],
                      hintText: t['voiceCalls.testNameDefault'],
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(value: 'ready', label: Text(t['voiceCalls.ready']!)),
                      ButtonSegment(value: 'waiting', label: Text(t['voiceCalls.waiting']!)),
                    ],
                    selected: {_testKind},
                    onSelectionChanged: (x) => setState(() => _testKind = x.first),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    t['voiceCalls.sentence']!.replaceAll(
                        '{text}', _sentence(_testName.text.trim().isEmpty ? t['voiceCalls.testNameDefault']! : _testName.text)),
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _testing ? null : _test,
                    icon: _testing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.play_arrow),
                    label: Text(_testing ? t['voiceCalls.testing']! : t['voiceCalls.test']!),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
          ),
      ],
    );
  }
}
