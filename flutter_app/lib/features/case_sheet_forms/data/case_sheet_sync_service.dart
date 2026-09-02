import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/offline/connectivity_service.dart';
import 'case_sheet_offline_store.dart';
import 'case_sheet_record_repository.dart';
import '../presentation/case_sheet_form_providers.dart';

final caseSheetSyncServiceProvider = Provider<CaseSheetSyncService>((ref) {
  final service = CaseSheetSyncService(ref);
  ref.onDispose(service._dispose);
  return service;
});

/// Drains the offline edit queue (`CaseSheetOfflineStore.listPendingEdits()`)
/// against the real network the moment connectivity looks like it's back —
/// see the "Offline mode for Flutter case sheets" plan. Three independent
/// triggers, since any one alone can miss a real reconnection: an
/// immediate attempt right when this service is created (an app cold
/// start, already online, with something left queued from a previous
/// session — `connectivity_plus`'s stream only fires on a *change*, so it
/// would otherwise never fire again until the next transition),
/// `connectivity_plus`'s own change stream (the common case), and app
/// foreground/resume (catches anything the OS-level connectivity event
/// missed while the app was backgrounded). `syncAll()` is safe to call
/// redundantly — an empty queue is a cheap no-op — so none of the three
/// need to de-duplicate against each other.
class CaseSheetSyncService with WidgetsBindingObserver {
  CaseSheetSyncService(this._ref) {
    WidgetsBinding.instance.addObserver(this);
    syncAll();
    _connectivitySub = _ref.listen(connectivityStreamProvider, (previous, next) {
      if (next.valueOrNull == true) syncAll();
    });
  }

  final Ref _ref;
  late final ProviderSubscription<AsyncValue<bool>> _connectivitySub;
  bool _syncing = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) syncAll();
  }

  /// Re-entrancy-guarded — a connectivity event and an app-resume firing
  /// within the same moment would otherwise race two overlapping drains of
  /// the same queue.
  Future<void> syncAll() async {
    if (_syncing) return;
    _syncing = true;
    try {
      final repository = _ref.read(caseSheetRecordRepositoryProvider);
      final offline = _ref.read(caseSheetOfflineStoreProvider);
      final pending = await offline.listPendingEdits();

      var anySynced = false;
      for (final edit in pending) {
        try {
          final record = await repository.updateRemote(edit.resource, edit.id, edit.payload);
          await offline.removePendingEdit(edit.resource, edit.id);
          await offline.cacheRecord(edit.resource, edit.id, record);
          anySynced = true;
        } on NetworkException {
          // Still offline (or the connectivity event was a false start) —
          // leave this one queued for the next trigger.
        } on ApiException catch (e) {
          // Reached the server, and it said no for a real reason (the
          // record changed ownership, a supervisor field conflict, etc.)
          // — surface it instead of retrying forever.
          await offline.markEditFailed(edit.resource, edit.id, e.userMessage);
        }
      }

      if (anySynced) {
        // Any open list/detail screen for a synced resource should drop
        // its now-stale data and re-fetch.
        for (final resource in pending.map((e) => e.resource).toSet()) {
          _ref.invalidate(caseSheetRecordListProvider(resource));
        }
        for (final edit in pending) {
          _ref.invalidate(caseSheetRecordProvider((edit.resource, edit.id)));
        }
      }
    } finally {
      _syncing = false;
    }
  }

  void _dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub.close();
  }
}
