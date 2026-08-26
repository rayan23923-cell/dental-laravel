import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `hide TextDirection` — intl's own bidi-detection enum collides with
// `dart:ui`'s, which `Directionality` below needs. See
// backup_admin/presentation/backup_screen.dart for the first instance of
// this fix.
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/network/api_exception.dart';
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

const _actionFilters = [
  (null, 'الكل'),
  ('create', 'إنشاء'),
  ('update', 'تعديل'),
  ('delete', 'حذف'),
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
      setState(() => _error = e is ApiException ? e.userMessage : 'تعذر التحميل.');
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
        final message = e is ApiException ? e.userMessage : 'تعذر تحميل المزيد.';
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
        return Colors.amber;
      case 'delete':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('yyyy-MM-dd HH:mm');

    return Scaffold(
      appBar: AppBar(title: const Text('سجل النشاط')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'ابحث بالمستخدم أو الوصف',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (v) {
                _search = v.trim().isEmpty ? null : v.trim();
                _load();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 8,
              children: [
                for (final (value, label) in _actionFilters)
                  ChoiceChip(
                    label: Text(label),
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
                        ? const Center(child: Text('لا يوجد نشاط مسجل بعد.'))
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.all(12),
                              itemCount: _entries.length + (_hasMore ? 1 : 0),
                              separatorBuilder: (_, __) => const SizedBox(height: 8),
                              itemBuilder: (context, i) {
                                if (i >= _entries.length) {
                                  return Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      child: _loadingMore
                                          ? const CircularProgressIndicator()
                                          : OutlinedButton(onPressed: _loadMore, child: const Text('تحميل المزيد')),
                                    ),
                                  );
                                }
                                final entry = _entries[i];
                                return Card(
                                  child: ListTile(
                                    title: Text('${entry.username} (${entry.userRole})'),
                                    // A chip + date in `trailing` overflowed the
                                    // tile's fixed trailing height by a few
                                    // pixels (confirmed live) — the date lives
                                    // in `subtitle` instead, which sizes to its
                                    // content rather than a fixed slot.
                                    subtitle: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('${entry.module} · ${entry.description}'),
                                        Directionality(
                                          textDirection: TextDirection.ltr,
                                          child: Text(
                                            dateFormat.format(entry.createdAt.toLocal()),
                                            style: Theme.of(context).textTheme.bodySmall,
                                          ),
                                        ),
                                      ],
                                    ),
                                    isThreeLine: true,
                                    trailing: Chip(
                                      label: Text(entry.action, style: TextStyle(color: _actionColor(entry.action))),
                                      visualDensity: VisualDensity.compact,
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
