/// Whether a specific case-sheet record has an offline edit queued —
/// drives `SyncStatusBadge` and `CaseSheetFormScreen`'s post-save message.
/// Only three variants (mirrors `AuthState`'s own doc comment): "is a sync
/// attempt currently in flight" isn't modeled here, since `syncAll()` runs
/// quickly enough (a handful of small JSON PUTs) that a dedicated
/// in-progress UI state isn't worth the extra complexity.
sealed class CaseSheetSyncStatus {
  const CaseSheetSyncStatus();
}

/// No queued edit — either never edited offline, or already synced.
final class CaseSheetSynced extends CaseSheetSyncStatus {
  const CaseSheetSynced();
}

/// An edit is queued, waiting for connectivity or an in-progress sync.
final class CaseSheetSyncPending extends CaseSheetSyncStatus {
  const CaseSheetSyncPending();
}

/// A sync attempt reached the server and was rejected for a real reason
/// (not just "still offline") — surfaced distinctly so a genuine problem
/// isn't silently retried forever and hidden from the doctor.
final class CaseSheetSyncFailed extends CaseSheetSyncStatus {
  const CaseSheetSyncFailed(this.message);
  final String message;
}
