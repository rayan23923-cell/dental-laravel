import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'advanced_perio_chart_field.dart';

/// Multiple sessions/visits for the Advanced Periodontal Chart's 32-tooth
/// grid (2026-09-04, by request — mirrors the web's
/// `AdvancedPerioChartSessions.vue`, built the same way the same day).
/// `AdvancedPerioChartField` itself stays completely untouched — it's a
/// large, carefully tuned single-snapshot widget (see its own doc
/// comment) — this wrapper only adds what didn't exist: a doctor-addable,
/// dated list of sessions shown as chips, one worked on at a time.
/// Deliberately not the *regular* Periodontal Chart's fixed 3 sessions
/// (Initial/After Hygiene/Follow-up, hardcoded PHP with no way to add a
/// 4th) — confirmed with the user on the web side.
///
/// [value] is the whole of `chart_data.advancedChart`, same shape either
/// app reads/writes:
///   { sessions: [ {id, label, date, teeth: {...}}, ... ], activeSessionId }
/// Each session's own `teeth` is exactly `AdvancedPerioChartField`'s own
/// `value['teeth']` shape, unchanged — one copy per session instead of one
/// total. Backward compatible with the pre-session shape (bare
/// `{teeth: {...}}`, everything saved before 2026-09-04): `_normalize()`
/// wraps that into a single "Session 1" on first load rather than losing it.
class AdvancedPerioChartSessionsField extends StatefulWidget {
  const AdvancedPerioChartSessionsField({super.key, required this.value, required this.onChanged, required this.readOnly});

  final Map<String, dynamic> value;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final bool readOnly;

  @override
  State<AdvancedPerioChartSessionsField> createState() => _AdvancedPerioChartSessionsFieldState();
}

class _AdvancedPerioChartSessionsFieldState extends State<AdvancedPerioChartSessionsField> {
  late List<Map<String, dynamic>> _sessions;
  String? _activeId;

  @override
  void initState() {
    super.initState();
    _sessions = _normalize(widget.value);
    _activeId = widget.value['activeSessionId'] as String? ?? (_sessions.isNotEmpty ? _sessions.first['id'] as String? : null);
  }

  static List<Map<String, dynamic>> _normalize(Map<String, dynamic> value) {
    final sessionsRaw = value['sessions'];
    if (sessionsRaw is List && sessionsRaw.isNotEmpty) {
      return [
        for (final raw in sessionsRaw)
          if (raw is Map)
            {
              'id': raw['id'] ?? _genId(),
              'label': raw['label'] ?? '',
              'date': raw['date'] ?? '',
              'teeth': Map<String, dynamic>.from((raw['teeth'] as Map?) ?? {}),
            },
      ];
    }
    final teeth = value['teeth'];
    if (teeth is Map && teeth.isNotEmpty) {
      return [
        {'id': _genId(), 'label': 'Session 1', 'date': '', 'teeth': Map<String, dynamic>.from(teeth)},
      ];
    }
    return [];
  }

  static int _idCounter = 0;
  static String _genId() => 'sess_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}';

  Map<String, dynamic>? get _active {
    for (final s in _sessions) {
      if (s['id'] == _activeId) return s;
    }
    return null;
  }

  void _emit() => widget.onChanged({'sessions': _sessions, 'activeSessionId': _activeId});

  Future<void> _addSession() async {
    final controller = TextEditingController(text: 'Session ${_sessions.length + 1}');
    DateTime pickedDate = DateTime.now();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('New Session'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(controller: controller, decoration: const InputDecoration(labelText: 'Session name'), autofocus: true),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today, size: 18),
                label: Text(DateFormat('yyyy-MM-dd').format(pickedDate)),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: dialogContext,
                    initialDate: pickedDate,
                    firstDate: DateTime(1950),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setDialogState(() => pickedDate = picked);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Add')),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final s = {
      'id': _genId(),
      'label': controller.text.trim().isEmpty ? 'Session ${_sessions.length + 1}' : controller.text.trim(),
      'date': DateFormat('yyyy-MM-dd').format(pickedDate),
      'teeth': <String, dynamic>{},
    };
    setState(() {
      _sessions = [..._sessions, s];
      _activeId = s['id'] as String;
    });
    _emit();
  }

  Future<void> _deleteSession(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this session?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _sessions = _sessions.where((s) => s['id'] != id).toList();
      if (_activeId == id) {
        _activeId = _sessions.isNotEmpty ? _sessions.first['id'] as String? : null;
      }
    });
    _emit();
  }

  void _selectSession(String id) {
    setState(() => _activeId = id);
    _emit();
  }

  void _updateActiveTeeth(Map<String, dynamic> next) {
    final active = _active;
    if (active == null) return;
    setState(() => active['teeth'] = Map<String, dynamic>.from((next['teeth'] as Map?) ?? {}));
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final s in _sessions)
              InputChip(
                label: Text('${s['label']}${(s['date'] as String).isNotEmpty ? ' (${s['date']})' : ''}'),
                selected: s['id'] == _activeId,
                onSelected: (_) => _selectSession(s['id'] as String),
                onDeleted: widget.readOnly ? null : () => _deleteSession(s['id'] as String),
              ),
            if (!widget.readOnly)
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('New Session'),
                onPressed: _addSession,
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (active != null)
          AdvancedPerioChartField(
            value: {'teeth': active['teeth']},
            readOnly: widget.readOnly,
            onChanged: _updateActiveTeeth,
          )
        else
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: Text('No sessions yet — tap "New Session" to start.', style: TextStyle(color: Colors.grey))),
          ),
      ],
    );
  }
}
