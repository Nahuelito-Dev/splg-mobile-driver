import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

import 'package:splg_driver/core/config/app_config.dart';

class ApiClient {
  static final instance = ApiClient._();

  factory ApiClient() {
    return instance;
  }

  ApiClient._();

  // URL base del backend centralizada en AppConfig (configurable por
  // --dart-define=API_BASE_URL para dispositivo físico / producción).
  final dio = Dio(
    BaseOptions(
      baseUrl: AppConfig.apiUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  )..interceptors.add(buildLogger());

  /// Log de las llamadas, sólo en debug. Nunca imprime los encabezados: ahí va
  /// el `Authorization: Bearer <token de Firebase>`. En release no loguea nada
  /// (ni cuerpos con datos de clientes).
  @visibleForTesting
  static PrettyDioLogger buildLogger({bool debug = kDebugMode}) =>
      PrettyDioLogger(
        enabled: debug,
        requestHeader: false,
        requestBody: true,
        responseBody: false,
        responseHeader: false,
        error: true,
        compact: true,
      );

  Future<Response> get(String path, [String? token]) async {
    try {
      final response = await dio.get(
        path,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-Client-Source': 'driver-app',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  Future<Response> post(
    String path,
    Map<String, dynamic> body, [
    String? token,
    Map<String, String>? extraHeaders,
  ]) async {
    try {
      final response = await dio.post(
        path,
        data: jsonEncode(body),
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-Client-Source': 'driver-app',
            if (token != null) 'Authorization': 'Bearer $token',
            if (extraHeaders != null) ...extraHeaders,
          },
        ),
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  Future<Response> patch(
    String path,
    Map<String, dynamic> body,
    String token, [
    Map<String, String>? extraHeaders,
  ]) async {
    try {
      final response = await dio.patch(
        path,
        data: body,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-Client-Source': 'driver-app',
            'Authorization': 'Bearer $token',
            if (extraHeaders != null) ...extraHeaders,
          },
        ),
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  /// `PUT` multipart con un archivo en el campo [field] (fotos).
  Future<Response> putFile(
    String path, {
    required List<int> bytes,
    required String filename,
    required String contentType,
    required String token,
    String field = 'file',
  }) {
    return dio.put(
      path,
      data: FormData.fromMap({
        field: MultipartFile.fromBytes(bytes,
            filename: filename, contentType: DioMediaType.parse(contentType)),
      }),
      options: Options(headers: {
        'Accept': 'application/json',
        'X-Client-Source': 'driver-app',
        'Authorization': 'Bearer $token',
      }),
    );
  }

  Future<Response> put(
    String path,
    Map<String, dynamic> body,
    String token,
  ) async {
    try {
      final response = await dio.put(
        path,
        data: body,
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-Client-Source': 'driver-app',
            'Authorization': 'Bearer $token',
          },
        ),
      );
      return response;
    } catch (e) {
      rethrow;
    }
  }

  /// `GET` binario (PDF). [path] puede ser absoluto (otra versión de la API).
  /// Si el back rechaza, el cuerpo del error llega como bytes: se decodifica a
  /// JSON para que [ApiErrorText] lea su mensaje igual que en el resto.
  Future<Uint8List> getBytes(String path, String token) async {
    try {
      final response = await dio.get<List<int>>(
        path,
        options: Options(
          responseType: ResponseType.bytes,
          // Armar un PDF tarda más que una consulta: el tope general de 10 s lo cortaría.
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'Accept': 'application/pdf',
            'X-Client-Source': 'driver-app',
            'Authorization': 'Bearer $token',
          },
        ),
      );
      return Uint8List.fromList(response.data ?? const []);
    } on DioException catch (e) {
      throw decodeBytesError(e);
    }
  }

  /// Reemplaza un cuerpo de error en bytes por su JSON decodificado.
  @visibleForTesting
  static DioException decodeBytesError(DioException e) {
    final res = e.response;
    final data = res?.data;
    if (res == null || data is! List) return e;
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(data.cast<int>()));
    } catch (_) {
      decoded = null;
    }
    res.data = decoded;
    return e;
  }
}
