import 'package:dio/dio.dart';

/// Every failure a repository can throw, funneled through one mapping
/// function ([ApiException.fromDioException]) so no feature re-derives its
/// own error handling. `userMessage` gives every feature a ready Arabic
/// fallback string without knowing the exception subtype.
sealed class ApiException implements Exception {
  const ApiException();

  factory ApiException.fromDioException(DioException e) {
    final type = e.type;
    if (type == DioExceptionType.connectionError ||
        type == DioExceptionType.connectionTimeout ||
        type == DioExceptionType.receiveTimeout ||
        type == DioExceptionType.sendTimeout) {
      return NetworkException(e.message ?? 'Network error');
    }

    final response = e.response;
    final data = response?.data;
    final message = (data is Map && data['message'] is String) ? data['message'] as String : null;

    switch (response?.statusCode) {
      case 422:
        final rawErrors = (data is Map ? data['errors'] : null) as Map?;
        final errors = <String, List<String>>{
          for (final entry in (rawErrors ?? const {}).entries)
            entry.key as String: List<String>.from(entry.value as List),
        };
        return ValidationException(
          message ?? 'Validation failed',
          errors,
          duplicate: data is Map && data['duplicate'] == true,
        );
      case 401:
        return UnauthorizedException(message ?? 'Unauthorized');
      case 403:
        return ForbiddenException(message ?? 'Forbidden');
      case null:
        return UnknownApiException(e.message ?? 'Unknown error', e);
      default:
        return ServerException(response!.statusCode!, message ?? 'Server error');
    }
  }
}

/// 422 — always field-keyed for this API's validation errors (e.g.
/// `{"email": ["The provided credentials are incorrect."]}`).
final class ValidationException extends ApiException {
  const ValidationException(this.message, this.errors, {this.duplicate = false});
  final String message;
  final Map<String, List<String>> errors;

  /// The server's "already exists — send allow_duplicates to go ahead"
  /// refusal (e.g. `Api\TaskController::store`), so a form can ask first.
  final bool duplicate;

  /// First message for a given field, if any — what a form field's
  /// `errorText` wants.
  String? firstError(String field) => errors[field]?.firstOrNull;
}

/// 401 — an invalid/expired/revoked token.
final class UnauthorizedException extends ApiException {
  const UnauthorizedException(this.message);
  final String message;
}

/// 403 — a valid token without permission for this action (e.g. a staff
/// token calling a doctor-only endpoint).
final class ForbiddenException extends ApiException {
  const ForbiddenException(this.message);
  final String message;
}

/// Any other 4xx/5xx with a JSON body.
final class ServerException extends ApiException {
  const ServerException(this.statusCode, this.message);
  final int statusCode;
  final String message;
}

/// Connection refused / timeout / DNS failure / host unreachable — the
/// "wrong base URL" bucket during development.
final class NetworkException extends ApiException {
  const NetworkException(this.message);
  final String message;
}

/// Anything that doesn't fit the above.
final class UnknownApiException extends ApiException {
  const UnknownApiException(this.message, this.cause);
  final String message;
  final Object? cause;
}

extension ApiExceptionPresentation on ApiException {
  /// Arabic-first fallback message, safe to show directly in a SnackBar/banner.
  String get userMessage => switch (this) {
        ValidationException(:final message) => message,
        UnauthorizedException() => 'انتهت صلاحية الجلسة، الرجاء تسجيل الدخول من جديد.',
        ForbiddenException() => 'لا تملك صلاحية القيام بهذا الإجراء.',
        // The server's own Arabic reason for a 4xx (e.g. "التسجيل غير
        // موجود.") instead of a generic line (2026-10-18): a lab scan on
        // the offline server showed only "server error" for a ticket that
        // wasn't in its database. A 404 without one means the server
        // doesn't have this screen yet, i.e. it needs updating.
        ServerException(:final statusCode, :final message) when statusCode < 500 && _isArabic(message) => message,
        ServerException(statusCode: 404) => 'هذه الخدمة غير موجودة على الخادم، حدّث الخادم إلى آخر نسخة.',
        ServerException(:final statusCode) => 'حدث خطأ في الخادم ($statusCode)، حاول مرة أخرى.',
        NetworkException() => 'تعذر الاتصال بالخادم، تحقق من عنوان الخادم واتصال الشبكة.',
        UnknownApiException() => 'حدث خطأ غير متوقع.',
      };
}

bool _isArabic(String text) => RegExp(r'[\u0600-\u06FF]').hasMatch(text);
