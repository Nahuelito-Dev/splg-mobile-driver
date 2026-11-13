import 'package:flutter_test/flutter_test.dart';
import 'package:splg_driver/ui/views/home/home_viewmodel.dart';

void main() {
  test('sin GPS el mapa del chofer arranca en Posadas, no en Buenos Aires', () {
    final target = HomeViewModel.initialPosition.target;
    expect(target.latitude, closeTo(-27.37, 0.05));
    expect(target.longitude, closeTo(-55.90, 0.05));
  });
}
