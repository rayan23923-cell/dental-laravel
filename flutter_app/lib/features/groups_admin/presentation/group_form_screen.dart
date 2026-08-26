import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/data/lookup_repository.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/cascading_dropdown.dart';
import '../data/groups_admin_repository.dart';
import '../domain/group_admin.dart';
import 'groups_admin_providers.dart';

/// `groupId == null` means create. `academic_session_id` is left out of
/// the form entirely — `Api\GroupController::store()` defaults it to the
/// current session when omitted, and `update()` never touches it at all,
/// matching the web form's own scope (a group's session isn't editable
/// after creation there either).
class GroupFormScreen extends ConsumerStatefulWidget {
  const GroupFormScreen({super.key, this.groupId});
  final int? groupId;

  @override
  ConsumerState<GroupFormScreen> createState() => _GroupFormScreenState();
}

class _GroupFormScreenState extends ConsumerState<GroupFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  int? _educationTypeId;
  int? _stageId;
  List<GroupSlot> _slots = [];
  bool _seeded = false;
  bool _educationTypeDerived = false;
  bool _submitting = false;

  bool get _isCreate => widget.groupId == null;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _seed(GroupAdmin group) {
    if (_seeded) return;
    _seeded = true;
    _nameController.text = group.name;
    _stageId = group.stageId;
    _slots = List.of(group.slots);
  }

  // `Group` doesn't store its education type (same reason
  // task_form_screen.dart derives one for `Task`, which also lacks the
  // column) — once stages have loaded, find the one matching this group's
  // stage and read its education type, so the cascade below doesn't open
  // looking reset.
  void _deriveEducationType(List<LookupItem> stages) {
    if (_educationTypeDerived || _isCreate) return;
    _educationTypeDerived = true;
    for (final s in stages) {
      if (s.id == _stageId) {
        _educationTypeId = s.educationTypeId;
        break;
      }
    }
  }

  void _addSlot() => setState(() => _slots = [..._slots, GroupSlot(day: kGroupDays[0], startTime: '', endTime: '')]);

  void _removeSlot(int index) => setState(() => _slots = [..._slots]..removeAt(index));

  void _updateSlot(int index, GroupSlot next) => setState(() => _slots = [..._slots]..[index] = next);

  Future<void> _pickTime(int index, {required bool isStart}) async {
    final picked = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (picked == null) return;
    final h = picked.hour.toString().padLeft(2, '0');
    final m = picked.minute.toString().padLeft(2, '0');
    final slot = _slots[index];
    _updateSlot(index, isStart ? slot.copyWith(startTime: '$h:$m') : slot.copyWith(endTime: '$h:$m'));
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? true)) return;
    if (_stageId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى اختيار المرحلة.')));
      return;
    }
    for (final slot in _slots) {
      if (slot.startTime.isEmpty || slot.endTime.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('يرجى تحديد وقت البداية والنهاية لكل موعد.')));
        return;
      }
    }
    setState(() => _submitting = true);

    final payload = {
      'name': _nameController.text.trim(),
      'stage_id': _stageId,
      'slots': _slots.map((s) => s.toJson()).toList(),
    };

    try {
      final repo = ref.read(groupsAdminRepositoryProvider);
      if (_isCreate) {
        await repo.create(payload);
      } else {
        await repo.update(widget.groupId!, payload);
        ref.invalidate(groupProvider(widget.groupId!));
      }
      ref.invalidate(groupListProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isCreate ? 'تم إضافة المجموعة.' : 'تم الحفظ.')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        final message = e is ApiException ? e.userMessage : 'تعذر الحفظ.';
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final educationTypesAsync = ref.watch(groupEducationTypesProvider);
    final stagesAsync = ref.watch(groupStagesProvider);
    final groupAsync = _isCreate ? null : ref.watch(groupProvider(widget.groupId!));

    if (groupAsync != null) {
      switch (groupAsync) {
        case AsyncError(:final error):
          return Scaffold(
            appBar: AppBar(title: const Text('مجموعة')),
            body: Center(child: Text(error is ApiException ? error.userMessage : 'تعذر التحميل.')),
          );
        case AsyncData(:final value):
          _seed(value);
        default:
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
    }
    final stageItems = stagesAsync.valueOrNull;
    if (stageItems != null) _deriveEducationType(stageItems);

    return Scaffold(
      appBar: AppBar(title: Text(_isCreate ? 'مجموعة جديدة' : 'تعديل المجموعة')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'الاسم', border: OutlineInputBorder()),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'هذا الحقل مطلوب' : null,
            ),
            const SizedBox(height: 16),
            // UI-only — `Group` has no `education_type_id` column, never
            // sent in the payload. Only narrows the stage picker below.
            CascadingDropdown(
              label: 'نوع التعليم',
              itemsAsync: educationTypesAsync,
              value: _educationTypeId,
              onChanged: (v) => setState(() {
                _educationTypeId = v;
                _stageId = null;
              }),
            ),
            const SizedBox(height: 16),
            CascadingDropdown(
              key: ValueKey('stage-$_educationTypeId'),
              label: 'المرحلة',
              itemsAsync: stagesAsync.whenData(
                (items) => _educationTypeId == null
                    ? items
                    : items.where((s) => s.educationTypeId == _educationTypeId).toList(),
              ),
              value: _stageId,
              enabled: _educationTypeId != null,
              onChanged: (v) => setState(() => _stageId = v),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Text('المواعيد الأسبوعية', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(onPressed: _addSlot, icon: const Icon(Icons.add), label: const Text('إضافة موعد')),
              ],
            ),
            for (var i = 0; i < _slots.length; i++) _SlotRow(
                  slot: _slots[i],
                  onDayChanged: (day) => _updateSlot(i, _slots[i].copyWith(day: day)),
                  onPickStart: () => _pickTime(i, isStart: true),
                  onPickEnd: () => _pickTime(i, isStart: false),
                  onRemove: () => _removeSlot(i),
                ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.slot,
    required this.onDayChanged,
    required this.onPickStart,
    required this.onPickEnd,
    required this.onRemove,
  });

  final GroupSlot slot;
  final ValueChanged<String> onDayChanged;
  final VoidCallback onPickStart;
  final VoidCallback onPickEnd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                initialValue: slot.day,
                decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
                items: [for (final d in kGroupDays) DropdownMenuItem(value: d, child: Text(d))],
                onChanged: (v) => onDayChanged(v ?? kGroupDays.first),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: onPickStart,
                child: Text(slot.startTime.isEmpty ? 'من' : slot.startTime),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: onPickEnd,
                child: Text(slot.endTime.isEmpty ? 'إلى' : slot.endTime),
              ),
            ),
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: onRemove),
          ],
        ),
      ),
    );
  }
}
