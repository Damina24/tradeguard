import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:tradeguard/features/journal/data/trade_screenshot_service.dart';

void main() {
  group('TradeScreenshots.objectPath', () {
    test('scopes the first segment to the owner uid', () {
      final String path = TradeScreenshots.objectPath(
        ownerUid: 'uid-123',
        tradeId: 'trade-1',
        extension: 'JPG',
        now: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );
      expect(path, 'uid-123/trade-1/1700000000000.jpg');
    });
  });

  group('TradeScreenshots.validate', () {
    test('accepts jpg/png/webp under the limit', () {
      for (final String ext in <String>['jpg', 'jpeg', 'png', 'webp']) {
        TradeScreenshots.validate(
          fileName: 'chart.$ext',
          mimeType: ext == 'png' ? 'image/png' : 'image/jpeg',
          byteLength: 1024,
        );
      }
    });

    test('rejects unsupported extensions', () {
      expect(
        () => TradeScreenshots.validate(
          fileName: 'chart.gif',
          mimeType: 'image/gif',
          byteLength: 1024,
        ),
        throwsA(isA<TradeScreenshotFailure>()),
      );
    });

    test('rejects oversized images', () {
      expect(
        () => TradeScreenshots.validate(
          fileName: 'chart.png',
          mimeType: 'image/png',
          byteLength: TradeScreenshots.maxBytes + 1,
        ),
        throwsA(isA<TradeScreenshotFailure>()),
      );
    });
  });

  group('MockTradeScreenshotService', () {
    test('upload stores bytes and returns a path that downloads', () async {
      final MockTradeScreenshotService svc = MockTradeScreenshotService();
      final Uint8List bytes = Uint8List.fromList(<int>[1, 2, 3]);
      final String path = await svc.upload(
        tradeId: 't1',
        bytes: bytes,
        fileName: 'chart.png',
        mimeType: 'image/png',
      );
      expect(path.startsWith('mock-uid/t1/'), isTrue);
      expect(path.endsWith('.png'), isTrue);
      expect(await svc.download(path), bytes);
    });

    test('download returns null when nothing is linked', () async {
      final MockTradeScreenshotService svc = MockTradeScreenshotService();
      expect(await svc.download(null), isNull);
      expect(await svc.download(''), isNull);
      expect(await svc.download('missing/path.png'), isNull);
    });

    test('upload validates like the live service', () async {
      final MockTradeScreenshotService svc = MockTradeScreenshotService();
      await expectLater(
        svc.upload(
          tradeId: 't1',
          bytes: Uint8List.fromList(<int>[1]),
          fileName: 'chart.gif',
          mimeType: 'image/gif',
        ),
        throwsA(isA<TradeScreenshotFailure>()),
      );
    });
  });
}
