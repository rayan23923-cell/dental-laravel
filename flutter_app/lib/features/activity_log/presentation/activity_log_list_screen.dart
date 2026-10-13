import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `hide TextDirection` — intl's own bidi-detection enum collides with
// `dart:ui`'s, which `Directionality` below needs. See
// backup_admin/presentation/backup_screen.dart for the first instance of
// this fix.
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/i18n/locale_controller.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/widgets/chat_list_tile.dart';
import '../data/activity_logs_repository.dart';
import '../domain/activity_log_entry.dart';

/// No `FutureProvider` here — pagination is accumulated local state (each
/// "load more" tap appends a page), which doesn't fit Riverpod's
/// single-value `AsyncValue` cleanly. First screen in the app to actually
/// exercise `Paginated.hasMore` — every other paginated list so far only
/// ever showed page 1 (see `doctors_admin`), acceptable there but not here:
/// 370 log rows across 13 pages in the live dev DB, confirmed via `curl`
/// before building this.
class ActivityLogListScreen extends ConsumerStatefulWidget {
  const ActivityLogListScreen({super.key});

  @override
  ConsumerState<ActivityLogListScreen> createState() => _ActivityLogListScreenState();
}

List<(String?, String)> _actionFilters(Map<String, String> t) => [
      (null, t['activityLogsAdmin.filterAll']!),
      ('create', t['activityLogsAdmin.filterCreate']!),
      ('update', t['activityLogsAdmin.filterUpdate']!),
      ('delete', t['activityLogsAdmin.filterDelete']!),
    ];

class _ActivityLogListScreenState extends ConsumerState<ActivityLogListScreen> {
  final _searchController = TextEditingController();
  String? _search;
  String? _action;

  List<ActivityLogEntry> _entries = [];
  int _currentPage = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await ref.read(activityLogsRepositoryProvider).fetch(search: _search, action: _action, page: 1);
      setState(() {
        _entries = page.items;
        _currentPage = page.currentPage;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      final t = ref.read(translationsProvider);
      setState(() => _error = e is ApiException ? e.userMessage : t['activityLogsAdmin.loadFailed']!);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final page = await ref
          .read(activityLogsRepositoryProvider)
          .fetch(search: _search, action: _action, page: _currentPage + 1);
      setState(() {
        _entries = [..._entries, ...page.items];
        _currentPage = page.currentPage;
        _hasMore = page.hasMore;
      });
    } catch (e) {
      if (mounted) {
        final t = ref.read(translationsProvider);
        final message = e is ApiException ? e.userMessage : t['activityLogsAdmin.loadMoreFailed']!;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Color _actionColor(String action) {
    switch (action) {
      case 'create':
        return Colors.green;
      case 'update':
        return Colors.amber.shade800;
      case 'delete':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _actionIcon(String action) {
    switch (action) {
      case 'create':
        return Icons.add_circle_outline;
      case 'update':
        return Icons.edit_outlined;
      case 'delete':
        return Icons.delete_outline;
      default:
        return Icons.history;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');
    final t = ref.watch(translationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t['activityLogsAdmin.title']!)),
      body: Column(
        children: [
          // Chat-list style (2026-10-13, by request): search pill + compact
          // action filter chips.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: ChatSearchField(
              controller: _searchController,
              hintText: t['activityLogsAdmin.searchHint']!,
              onSubmitted: (v) {
                _search = v.trim().isEmpty ? null : v.trim();
                _load();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Wrap(
              spacing: 8,
              children: [
                for (final (value, label) in _actionFilters(t))
                  ChoiceChip(
                    label: Text(label),
                    avatar: value == null ? null : Icon(_actionIcon(value), size: 16),
                    shape: const StadiumBorder(),
                    visualDensity: VisualDensity.compact,
                    selected: _action == value,
                    onSelected: (_) {
                      setState(() => _action = value);
                      _load();
                    },
                  ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!))
                    : _entries.isEmpty
                        ? Center(child: Text(t['activityLogsAdmin.emptyList']!))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.only(top: 4, bottom: 24),
                              itemCount: _entries.length + (_hasMore ? 1 : 0),
                              separatorBuilder: (_, __) => chatDivider,
                              itemBuilder: (context, i) {
                                if (i >= _entries.length) {
                                  return Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      child: _loadingMore
                                          ? const CircularProgressIndicator()
                                          : OutlinedButton(onPressed: _loadMore, child: Text(t['activityLogsAdmin.loadMore']!)),
                                    ),
                                  );
                                }
                                final entry = _entries[i];
                                // Chat-list row (2026-10-13, by request): the
                                // action as a coloured avatar + chip, the user
                                // as the title, the description below and
                                // module/role/date chips.
                                final color = _actionColor(entry.action);
                                final actionLabel = _actionFilters(t)
                                        .where((f) => f.$1 == entry.action)
                                        .map((f) => f.$2)
                                        .firstOrNull ??
                                    entry.action;
                                return ChatListTile(
                                  title: entry.username,
                                  color: color,
                                  icon: _actionIcon(entry.action),
                                  subtitle: entry.description,
                                  chips: [
                                    ChatChip(label: actionLabel, icon: _actionIcon(entry.action), color: color),
                                    ChatChip(label: entry.module, icon: Icons.widgets_outlined, color: Colors.indigo),
                                    ChatChip(label: entry.userRole, icon: Icons.badge_outlined, color: Colors.blueGrey),
                                    // LTR isolate: a date/time inside RTL text.
                                    ChatChip(
                                      label: '\u2066${dateFormat.format(entry.createdAt.toLocal())}\u2069',
                                      icon: Icons.schedule,
                                      color: Colors.blueGrey,
                                    ),
                                  ],
                                  // The subtitle is one line now; a tap shows
                                  // the full description.
                                  onTap: () => showDialog<void>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: Text(entry.username),
                                      content: Text('${entry.module} · ${entry.description}'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(t['common.close']!)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
