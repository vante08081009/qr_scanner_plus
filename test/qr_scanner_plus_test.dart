import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_scanner_plus/qr_scanner_plus.dart';

void main() {
  const MethodChannel channel = MethodChannel('qr_scanner_plus');

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      return '42';
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('getPlatformVersion', () async {
    expect(await QrScannerPlus.platformVersion, '42');
  });
}
