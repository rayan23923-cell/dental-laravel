/// One care code (2026-11-01, by request): a one-time 5-digit code printed
/// on a card that makes a registration's service and lab test free.
class SupportCode {
  const SupportCode({
    required this.id,
    required this.code,
    required this.batch,
    this.note,
    required this.status,
    this.createdAt,
    this.usedAt,
    this.patientName,
  });

  factory SupportCode.fromJson(Map<String, dynamic> json) => SupportCode(
        id: json['id'] as int,
        code: json['code'] as String? ?? '',
        batch: (json['batch'] as num?)?.toInt() ?? 0,
        note: json['note'] as String?,
        status: json['status'] as String? ?? 'active',
        createdAt: json['created_at'] as String?,
        usedAt: json['used_at'] as String?,
        patientName: (json['patient'] as Map<String, dynamic>?)?['name'] as String?,
      );

  final int id;
  final String code;
  final int batch;
  final String? note;

  /// 'active' | 'used' | 'disabled'.
  final String status;
  final String? createdAt;
  final String? usedAt;
  final String? patientName;
}

/// A batch of codes made together, with how many are still active.
class SupportCodeBatch {
  const SupportCodeBatch({required this.batch, this.note, required this.total, required this.active, required this.used});

  factory SupportCodeBatch.fromJson(Map<String, dynamic> json) => SupportCodeBatch(
        batch: (json['batch'] as num).toInt(),
        note: json['note'] as String?,
        total: (json['total'] as num?)?.toInt() ?? 0,
        active: (json['active'] as num?)?.toInt() ?? 0,
        used: (json['used'] as num?)?.toInt() ?? 0,
      );

  final int batch;
  final String? note;
  final int total;
  final int active;
  final int used;
}

class SupportCodePage {
  const SupportCodePage({
    required this.codes,
    required this.counts,
    required this.batches,
    required this.enabled,
    required this.lastPage,
    required this.total,
  });

  factory SupportCodePage.fromJson(Map<String, dynamic> json) {
    final counts = (json['counts'] as Map<String, dynamic>?) ?? const {};
    final meta = (json['meta'] as Map<String, dynamic>?) ?? const {};
    return SupportCodePage(
      codes: [for (final e in (json['data'] as List<dynamic>? ?? const [])) SupportCode.fromJson(e as Map<String, dynamic>)],
      counts: {for (final e in counts.entries) e.key: (e.value as num).toInt()},
      batches: [for (final e in (json['batches'] as List<dynamic>? ?? const [])) SupportCodeBatch.fromJson(e as Map<String, dynamic>)],
      enabled: json['enabled'] == true,
      lastPage: (meta['last_page'] as num?)?.toInt() ?? 1,
      total: (meta['total'] as num?)?.toInt() ?? 0,
    );
  }

  final List<SupportCode> codes;
  final Map<String, int> counts;
  final List<SupportCodeBatch> batches;
  final bool enabled;
  final int lastPage;
  final int total;
}
