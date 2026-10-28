import 'dart:convert';

import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splg_driver/core/network/action_error_text.dart';
import 'package:splg_driver/core/network/api_client.dart';

DioException _bytesError(int status, List<int> body) => DioException(
    requestOptions: RequestOptions(path: ''),
    type: DioExceptionType.badResponse,
    response: Response(
        requestOptions: RequestOptions(path: ''),
        statusCode: status,
        data: body));

void main() {
  test('el error en bytes se decodifica y el mensaje del back se muestra', () {
    final e = ApiClient.decodeBytesError(_bytesError(
        409, utf8.encode(jsonEncode({'message': 'Rendición de otro chofer'}))));
    expect(e.response!.data, {'message': 'Rendición de otro chofer'});
    expect(actionErrorText(e), contains('Rendición de otro chofer'));
  });

  test('un cuerpo que no es JSON queda en null sin romper', () {
    final e = ApiClient.decodeBytesError(_bytesError(500, [0, 1, 2]));
    expect(e.response!.data, isNull);
    expect(actionErrorText(e), isNotEmpty);
  });

  group('getBytes', () {
    late HttpClientAdapter original;
    setUp(() => original = ApiClient().dio.httpClientAdapter);
    tearDown(() => ApiClient().dio.httpClientAdapter = original);

    test('pide bytes con la sesión y devuelve el PDF', () async {
      final adaptador = _Adaptador(200, utf8.encode('%PDF-1.7'));
      ApiClient().dio.httpClientAdapter = adaptador;
      final bytes = await ApiClient().getBytes('http://api/x.pdf', 'tok');
      expect(utf8.decode(bytes), '%PDF-1.7');
      expect(adaptador.pedido!.headers['Authorization'], 'Bearer tok');
      expect(adaptador.pedido!.headers['X-Client-Source'], 'driver-app');
      expect(adaptador.pedido!.responseType, ResponseType.bytes);
    });

    test('un error del back llega con su mensaje', () async {
      ApiClient().dio.httpClientAdapter = _Adaptador(409,
          utf8.encode(jsonEncode({'message': 'Rendición de otro chofer'})));
      await expectLater(
        ApiClient().getBytes('http://api/x.pdf', 'tok'),
        throwsA(predicate((Object e) =>
            e is DioException &&
            actionErrorText(e).contains('Rendición de otro chofer'))),
      );
    });
  });
}

class _Adaptador implements HttpClientAdapter {
  _Adaptador(this.status, this.cuerpo);
  final int status;
  final List<int> cuerpo;
  RequestOptions? pedido;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    pedido = options;
    return ResponseBody.fromBytes(cuerpo, status, headers: {
      Headers.contentTypeHeader: [
        status == 200 ? 'application/pdf' : 'application/json'
      ],
    });
  }

  @override
  void close({bool force = false}) {}
}
