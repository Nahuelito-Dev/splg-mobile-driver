import 'package:flutter_test/flutter_test.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/services/driver_socket_service.dart';

import '../helpers/test_helpers.dart';

/// Socket sin red que guarda los handlers para dispararlos a mano.
class _SocketGrabador extends io.Socket {
  _SocketGrabador(io.Socket base) : super(base.io, base.nsp, {});

  final handlers = <String, dynamic Function(dynamic)>{};

  @override
  io.Socket connect() => this;

  @override
  Function() on(String event, dynamic Function(dynamic) handler) {
    handlers[event] = handler;
    return super.on(event, handler);
  }
}

void main() {
  late _SocketGrabador socket;
  late DriverSocketService svc;

  setUp(() {
    registerServices();
    svc = DriverSocketService(
      socketFactory: (uri, opts) => socket = _SocketGrabador(io.io(
          'http://localhost:1',
          {...opts, 'autoConnect': false, 'forceNew': true})),
    );
    svc.connect('tok', 'chofer-1');
  });

  tearDown(() {
    svc.dispose();
    locator.reset();
  });

  test('escucha exactamente order:delivery-code-failed y -blocked', () {
    expect(socket.handlers.keys, contains('order:delivery-code-failed'));
    expect(socket.handlers.keys, contains('order:delivery-code-blocked'));
  });

  test('los dos eventos llegan al stream deliveryCodeFailed con su payload',
      () async {
    final got = <Map<String, dynamic>>[];
    svc.deliveryCodeFailed.listen(got.add);
    socket.handlers['order:delivery-code-failed']!(
        {'orderId': 'o1', 'attempts': 2, 'maxAttempts': 5, 'blocked': false});
    socket.handlers['order:delivery-code-blocked']!(
        {'orderId': 'o1', 'attempts': 5, 'maxAttempts': 5, 'blocked': true});
    await Future<void>.delayed(Duration.zero);
    expect(got.map((e) => e['attempts']), [2, 5]);
    expect(got.last['blocked'], isTrue);
  });

  test('un payload que no es un mapa se ignora', () async {
    final got = <Map<String, dynamic>>[];
    svc.deliveryCodeFailed.listen(got.add);
    socket.handlers['order:delivery-code-failed']!('basura');
    await Future<void>.delayed(Duration.zero);
    expect(got, isEmpty);
  });
}
