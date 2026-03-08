import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeagent/matter/secure_session.dart';

void main() {
  group('SecureSession', () {
    // 고정 Ke로 세션 키 유도 테스트
    final testKe = Uint8List.fromList(List.generate(32, (i) => i));

    test('fromKe produces 16-byte encrypt/decrypt keys', () {
      final session = SecureSession.fromKe(
        testKe,
        sessionId: 100,
        peerSessionId: 200,
      );
      expect(session.encryptKey.length, 16);
      expect(session.decryptKey.length, 16);
      // I2R ≠ R2I
      expect(session.encryptKey, isNot(equals(session.decryptKey)));
    });

    test('same Ke produces same keys (deterministic)', () {
      final s1 = SecureSession.fromKe(testKe, sessionId: 1, peerSessionId: 2);
      final s2 = SecureSession.fromKe(testKe, sessionId: 1, peerSessionId: 2);
      expect(s1.encryptKey, equals(s2.encryptKey));
      expect(s1.decryptKey, equals(s2.decryptKey));
    });

    test('different Ke produces different keys', () {
      final otherKe = Uint8List.fromList(List.generate(32, (i) => 255 - i));
      final s1 = SecureSession.fromKe(testKe, sessionId: 1, peerSessionId: 2);
      final s2 =
          SecureSession.fromKe(otherKe, sessionId: 1, peerSessionId: 2);
      expect(s1.encryptKey, isNot(equals(s2.encryptKey)));
    });

    test('encrypt-decrypt roundtrip', () {
      // Initiator encrypts with I2R, peer decrypts with same key
      final session = SecureSession.fromKe(
        testKe,
        sessionId: 100,
        peerSessionId: 200,
      );

      final payload = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final encrypted = session.encryptMessage(
        exchangeId: 42,
        messageType: 8,
        payload: payload,
      );

      // encrypted is: packetHeader(8B) + encrypted(payloadHeader + payload + MIC)
      expect(encrypted.length, greaterThan(payload.length + 8));

      // peer(responder) 관점에서 키 역전
      // initiator: encrypt=keys[0:16], decrypt=keys[16:32]
      // responder: encrypt=keys[16:32], decrypt=keys[0:16]
      // fromKe는 항상 initiator 관점이므로, responder는 키를 수동 교환
      final peerSession = SecureSession.fromKe(
        testKe,
        sessionId: 200,
        peerSessionId: 100,
      );
      // responder의 decrypt는 initiator의 encrypt와 같아야 함
      // fromKe가 항상 initiator 관점이므로 peerSession.encryptKey == session.encryptKey
      // → decrypt에는 encryptKey를 써야 함 → responder 용 별도 생성 필요
      // 대신 self-roundtrip: initiator가 보낸 걸 initiator가 decryptKey로 복호화할 수 없음
      // → 자체 검증 불가하므로, encryptKey로 직접 decrypt 테스트
      // 간단히: peer 세션을 키 반전해서 만들자
      final peerSession2 = SecureSession.createForTest(
        encryptKey: session.decryptKey, // peer encrypt = initiator decrypt
        decryptKey: session.encryptKey, // peer decrypt = initiator encrypt
        sessionId: 200,
        peerSessionId: 100,
      );

      final decrypted = peerSession2.decryptMessage(encrypted);
      expect(decrypted.payloadHeader.exchangeId, 42);
      expect(decrypted.payloadHeader.messageType, 8);
      expect(decrypted.payload, equals(payload));
    });

    test('message counter increments', () {
      final session = SecureSession.fromKe(
        testKe,
        sessionId: 1,
        peerSessionId: 2,
      );
      final payload = Uint8List.fromList([0xAA]);

      final enc1 = session.encryptMessage(
        exchangeId: 1,
        messageType: 8,
        payload: payload,
      );
      final enc2 = session.encryptMessage(
        exchangeId: 1,
        messageType: 8,
        payload: payload,
      );

      // 같은 payload지만 messageId가 다르므로 nonce 달라서 ciphertext 다름
      expect(enc1, isNot(equals(enc2)));
    });
  });
}
