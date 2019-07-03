import 'dart:async';

import 'package:flutter_driver/flutter_driver.dart';
import 'package:test/test.dart';

void main() {
  group('cupertino test', () {
    FlutterDriver driver;

    setUpAll(() async {
      driver = await FlutterDriver.connect();
    });

    tearDownAll(() async {
      if (driver != null)
        driver.close();
    });

    test('shader compilation', () async {
      await driver.tap(find.text('Cupertino'));
      await driver.waitFor(find.text('Alerts'));
      await driver.tap(find.text('Alerts'));
      await driver.waitFor(find.text('Alert'));
      await driver.tap(find.text('Alert'));
      await Future<void>.delayed(const Duration(seconds: 3));
      await driver.tap(find.text('Discard'));
      await driver.tap(find.text('Alert with Title'));
      await Future<void>.delayed(const Duration(seconds: 3));
      await driver.tap(find.text('Allow'));
      await driver.tap(find.text('Alert with Buttons'));
      await Future<void>.delayed(const Duration(seconds: 3));
      await driver.tap(find.text('Cancel'));
      await driver.tap(find.text('Alert Buttons Only'));
      await Future<void>.delayed(const Duration(seconds: 3));
      await driver.tap(find.text('Cancel'));
    });
  });
}
