import 'package:flutter/material.dart';

import '../data/patient_registration_repository.dart';

/// "الربط بالنماذج" filter for the payments screen (2026-11-04, by
/// request): the link status, then the linked case's stage and
/// department, each with its count, as the web LinkFacetPanel.
typedef LinkFilterValue = ({String? link, int? stageId, int? departmentId});

const _linkStatuses = [
  ('', 'patientRegFlutter.linkFilterAll', Icons.select_all),
  ('linked', 'patientRegFlutter.linkFilterLinked', Icons.link),
  ('unlinked', 'patientRegFlutter.linkFilterUnlinked', Icons.link_off),
  ('suspicious', 'patientRegFlutter.linkFilterSuspicious', Icons.gpp_maybe_outlined),
  ('attempts', 'patientRegFlutter.linkFilterAttempts', Icons.block),
];

bool linkFilterActive(LinkFilterValue v) => v.link != null || v.stageId != null || v.departmentId != null;

/// What the button says, e.g. "مربوط بنموذج · المرحلة الرابعة · الحشوات".
String linkFilterSummary(Map<String, String> t, LinkFilterValue v, LinkFacets? facets) {
  final parts = <String>[
    if (v.link != null) t[_linkStatuses.firstWhere((s) => s.$1 == v.link, orElse: () => _linkStatuses.first).$2]!,
    if (v.stageId != null) facets?.stages.where((s) => s.id == v.stageId).firstOrNull?.name ?? '…',
    if (v.departmentId != null) facets?.departments.where((d) => d.id == v.departmentId).firstOrNull?.name ?? '…',
  ];
  return parts.isEmpty ? t['patientRegFlutter.linkFilterAll']! : parts.join(' · ');
}

/// The choices in a sheet; a tap applies one and closes it. Returns the
/// new value, or null when dismissed.
Future<LinkFilterValue?> showLinkFilterSheet(
  BuildContext context,
  Map<String, String> t,
  LinkFacets facets,
  LinkFilterValue current,
) {
  return showModalBottomSheet<LinkFilterValue>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      void pick(LinkFilterValue v) => Navigator.of(sheetContext).pop(v);
      // Choosing a stage or department leaves "غير مربوط".
      String? linkFor(String? link) => link == 'unlinked' ? null : link;

      Widget section(String title, List<Widget> chips) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(sheetContext).textTheme.labelLarge?.copyWith(color: Colors.grey.shade600)),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 8, children: chips),
              ],
            ),
          );

      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.8),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(t['patientRegFlutter.linkFilter']!, style: Theme.of(sheetContext).textTheme.titleMedium),
              const SizedBox(height: 16),
              section(t['patientRegFlutter.linkStatus']!, [
                for (final (key, label, icon) in _linkStatuses)
                  ChoiceChip(
                    avatar: Icon(icon, size: 16, color: key == 'suspicious' ? Colors.red.shade700 : null),
                    label: Text('${t[label]!} (${facets.statuses[key.isEmpty ? 'all' : key] ?? 0})'),
                    selected: (current.link ?? '') == key,
                    onSelected: (_) => pick(key == 'unlinked'
                        ? (link: key, stageId: null, departmentId: null)
                        : (link: key.isEmpty ? null : key, stageId: current.stageId, departmentId: current.departmentId)),
                  ),
              ]),
              if (facets.stages.isNotEmpty)
                section(t['patientRegFlutter.linkStage']!, [
                  for (final st in facets.stages)
                    ChoiceChip(
                      avatar: const Icon(Icons.school_outlined, size: 16),
                      selectedColor: Colors.green.shade100,
                      label: Text('${st.name} (${st.count})'),
                      selected: current.stageId == st.id,
                      onSelected: (_) => pick((
                        link: linkFor(current.link),
                        stageId: current.stageId == st.id ? null : st.id,
                        departmentId: current.departmentId,
                      )),
                    ),
                ]),
              if (facets.departments.isNotEmpty)
                section(t['patientRegFlutter.linkDepartment']!, [
                  for (final d in facets.departments)
                    ChoiceChip(
                      avatar: const Icon(Icons.apartment, size: 16),
                      selectedColor: Colors.blue.shade100,
                      label: Text('${d.name} (${d.count})'),
                      selected: current.departmentId == d.id,
                      onSelected: (_) => pick((
                        link: linkFor(current.link),
                        stageId: current.stageId,
                        departmentId: current.departmentId == d.id ? null : d.id,
                      )),
                    ),
                ]),
            ],
          ),
        ),
      );
    },
  );
}

/// The "الربط بالنماذج" button: what is chosen now, and a red count when
/// other doctors tried linked receipts.
class LinkFilterButton extends StatelessWidget {
  const LinkFilterButton({super.key, required this.summary, required this.active, required this.suspicious, required this.onPressed});

  final String summary;
  final bool active;
  final int suspicious;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size.fromHeight(44),
        backgroundColor: active ? scheme.primaryContainer : null,
      ),
      child: Row(
        children: [
          const Icon(Icons.account_tree_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(summary, overflow: TextOverflow.ellipsis)),
          if (suspicious > 0) ...[
            Icon(Icons.gpp_maybe_outlined, size: 18, color: Colors.red.shade700),
            Text(' $suspicious', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold)),
            const SizedBox(width: 4),
          ],
          const Icon(Icons.expand_more, size: 18),
        ],
      ),
    );
  }
}
