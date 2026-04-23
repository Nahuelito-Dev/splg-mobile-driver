import 'package:flutter_test/flutter_test.dart';
import 'package:driver_mobile/app/app.locator.dart';

import '../helpers/test_helpers.dart';

void main() {
  group('OrderServiceTest -', () {
    setUp(() => registerServices());
    tearDown(() => locator.reset());
  });
}
