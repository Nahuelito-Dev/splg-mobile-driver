import 'package:flutter_test/flutter_test.dart';
import 'package:splg_driver/app/app.locator.dart';
import 'package:splg_driver/ui/views/delivery/delivery_viewmodel.dart';

import '../helpers/test_helpers.dart';

void main() {
  DeliveryViewModel getModel() => DeliveryViewModel(orderId: 'order-1');

  group('DeliveryViewModelTest -', () {
    setUp(() => registerServices());
    tearDown(() => locator.reset());

    group('estado inicial -', () {
      test('sin datos cargados, todos los getters de estado son false', () {
        final model = getModel();
        expect(model.isAccepted, false);
        expect(model.isOnTheWay, false);
        expect(model.isDelivered, false);
        expect(model.addressText, 'Dirección no disponible');
        expect(model.hasCoordinates, false);
        expect(model.items, isEmpty);
        expect(model.total, 0);
      });
    });
  });
}
