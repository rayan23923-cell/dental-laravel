import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import '../storage/token_storage.dart';
import 'api_exception.dart';

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref.watch(tokenStorageProvider));
});

/// Thin wrapper around one [Dio] instance: attaches the bearer token to
/// every request, and — on a 401 — fires [onUnauthorized] so
/// `AuthController` can clear local session state, while still letting the
/// resulting [ApiException] propagate to whoever made the call.
///
/// Deliberately depends only on [TokenStorage], never on the auth
/// controller/provider, to avoid a provider cycle (the auth controller
/// needs this client via the auth repository; this client must not need the
/// auth controller back). The 401 hook is wired at runtime instead — see
/// `AuthController.build()`.
class ApiClient {
  ApiClient(this._tokenStorage)
      : _dio = Dio(
          BaseOptions(
            baseUrl: AppConfig.baseUrl,
            connectTimeout: AppConfig.connectTimeout,
            receiveTimeout: AppConfig.receiveTimeout,
            headers: const {'Accept': 'application/json'},
            // Real bug, found via a live case-sheet PUT that failed
            // Laravel validation on a field ({"patient_sex": ""}) that was
            // actually well-formed on the Dart side. Without an explicit
            // request `Content-Type`, Laravel's `Request::isJson()` isn't
            // guaranteed true, and it can fall back to treating the raw
            // JSON body as form data instead of decoding it — corrupting
            // fields in ways that surface as unrelated-looking validation
            // errors. Declaring the content type explicitly removes the
            // ambiguity for every request this client makes.
            contentType: Headers.jsonContentType,
          ),
        ) {
    _dio.interceptors.add(_authInterceptor());
    if (kDebugMode) {
      _dio.interceptors.add(LogInterceptor(requestBody: true, responseBody: true));
    }
  }

  final Dio _dio;
  final TokenStorage _tokenStorage;

  /// Set once by `AuthController.build()`.
  void Function()? onUnauthorized;

  Interceptor _authInterceptor() {
    return QueuedInterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _tokenStorage.readToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (err, handler) {
        if (err.response?.statusCode == 401) {
          onUnauthorized?.call();
        }
        handler.next(err);
      },
    );
  }

  Future<dynamic> getJson(String path, {Map<String, dynamic>? query}) async {
    try {
      final response = await _dio.get(path, queryParameters: query);
      return response.data;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// For binary responses (the QR code PNG) — same auth interceptor as
  /// every other request, so the caller never handles the bearer token.
  Future<List<int>> getBytes(String path, {Map<String, dynamic>? query}) async {
    try {
      final response = await _dio.get<List<int>>(
        path,
        queryParameters: query,
        options: Options(responseType: ResponseType.bytes),
      );
      return response.data!;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<dynamic> postJson(String path, {Object? body}) async {
    try {
      final response = await _dio.post(path, data: body);
      return response.data;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  Future<dynamic> putJson(String path, {Object? body}) async {
    try {
      final response = await _dio.put(path, data: body);
      return response.data;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// `body` is for the rare `DELETE` that carries a payload — e.g.
  /// `DELETE /groups/{group}/doctors` takes a `doctor_ids` array instead
  /// of the id being in the URL, since it removes several members at
  /// once.
  Future<void> deleteJson(String path, {Object? body}) async {
    try {
      await _dio.delete(path, data: body);
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }

  /// For endpoints that accept a file upload (only clinic settings' two
  /// logo fields, currently). Always POSTs with `_method` spoofing rather
  /// than a real HTTP `PUT`/`PATCH`, matching the web app's own
  /// `useForm().transform(...).post(...)` pattern — PHP never populates
  /// `$_FILES` on a genuine PUT/PATCH request, only POST, so a real PUT
  /// with a multipart body would silently drop every file field.
  /// `FormData` always gets the correct
  /// `multipart/form-data; boundary=...` header from Dio itself
  /// (`dio_mixin.dart` sets it unconditionally whenever `data is
  /// FormData`), overriding this client's JSON default automatically —
  /// no extra `Options` needed here.
  Future<dynamic> postMultipart(String path, {required FormData formData, required String spoofedMethod}) async {
    formData.fields.add(MapEntry('_method', spoofedMethod));
    try {
      final response = await _dio.post(path, data: formData);
      return response.data;
    } on DioException catch (e) {
      throw ApiException.fromDioException(e);
    }
  }
}
