import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:pretty_dio_logger/pretty_dio_logger.dart';

class ApiClient {
  static final instance = ApiClient._();

  factory ApiClient() {
    return instance;
  }

  ApiClient._();

  // Android emulator: 10.0.2.2 → host machine localhost
  final dio = Dio(
    BaseOptions(
      baseUrl: 'http://10.0.2.2:3000/api/',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  )..interceptors.add(PrettyDioLogger(
      requestHeader: true,
      requestBody: true,
      responseBody: false,
      responseHeader: false,
      error: true,
      compact: true,
    ));

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
    String token,
  ) async {
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
          },
        ),
      );
      return response;
    } catch (e) {
      rethrow;
    }
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
}
