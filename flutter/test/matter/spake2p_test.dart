import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeagent/matter/spake2p.dart';

void main() {
  group('Spake2p', () {
    test('computeW0W1 produces consistent results for same inputs', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i + 1));
      const iterations = 100; // 적은 반복으로 테스트 속도 확보

      final result1 = await computeW0W1(
        iterations: iterations, salt: salt, pin: 20202021,
      );
      final result2 = await computeW0W1(
        iterations: iterations, salt: salt, pin: 20202021,
      );

      expect(result1.w0, equals(result2.w0));
      expect(result1.w1, equals(result2.w1));
    });

    test('different pins produce different w0/w1', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      const iterations = 100;

      final r1 = await computeW0W1(
        iterations: iterations, salt: salt, pin: 20202021,
      );
      final r2 = await computeW0W1(
        iterations: iterations, salt: salt, pin: 12345678,
      );

      expect(r1.w0, isNot(equals(r2.w0)));
    });

    test('w0 and w1 are less than curve order n', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final result = await computeW0W1(
        iterations: 100, salt: salt, pin: 20202021,
      );

      // P-256 curve order n
      final n = BigInt.parse(
        'FFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551',
        radix: 16,
      );

      expect(result.w0 < n, true);
      expect(result.w1 < n, true);
      expect(result.w0 > BigInt.zero, true);
      expect(result.w1 > BigInt.zero, true);
    });

    test('computeX produces 65-byte uncompressed point', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final w = await computeW0W1(
        iterations: 100, salt: salt, pin: 20202021,
      );

      final context = Uint8List.fromList('test context'.codeUnits);
      final client = Spake2pClient.create(context, w.w0);
      final x = client.computeX();

      // Uncompressed P-256 point: 0x04 + 32 bytes X + 32 bytes Y = 65
      expect(x.length, 65);
      expect(x[0], 0x04); // uncompressed prefix
    });
  });
}
