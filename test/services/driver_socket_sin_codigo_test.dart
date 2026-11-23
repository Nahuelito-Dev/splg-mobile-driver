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

  // Los avisos de código de entrega (errores, bloqueo) van al cliente: el
  // chofer recibe el resultado en la respuesta de confirm-delivery.
  test('no escucha los avisos de código de entrega (son del cliente)', () {
    expect(socket.handlers.keys, isNot(contains('order:delivery-code-failed')));
    expect(
        socket.handlers.keys, isNot(contains('order:delivery-code-blocked')));
  });
}
