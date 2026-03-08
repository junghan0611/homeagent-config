import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeagent/matter/message_codec.dart';

void main() {
  group('MessageCodec', () {
    test('encode-decode roundtrip — PbkdfParamRequest', () {
      final payload = Uint8List.fromList([0x15, 0x30, 1, 3, 0xAA, 0xBB, 0xCC, 0x18]);
      final msg = MatterMessage(
        packetHeader: PacketHeader(messageId: 42),
        payloadHeader: PayloadHeader(
          exchangeId: 100,
          messageType: SecureMessageType.pbkdfParamRequest,
        ),
        payload: payload,
      );

      final encoded = encodeMatterMessage(msg);
      final decoded = decodeMatterMessage(encoded);

      expect(decoded.packetHeader.messageId, 42);
      expect(decoded.packetHeader.sessionId, 0);
      expect(decoded.payloadHeader.exchangeId, 100);
      expect(decoded.payloadHeader.messageType, SecureMessageType.pbkdfParamRequest);
      expect(decoded.payloadHeader.protocolId, secureChannelProtocolId);
      expect(decoded.payloadHeader.isInitiatorMessage, true);
      expect(decoded.payloadHeader.requiresAck, true);
      expect(decoded.payload, payload);
    });

    test('encode-decode with ackedMessageId', () {
      final msg = MatterMessage(
        packetHeader: PacketHeader(messageId: 99),
        payloadHeader: PayloadHeader(
          exchangeId: 200,
          messageType: SecureMessageType.pasePake1,
          ackedMessageId: 50,
        ),
        payload: Uint8List.fromList([1, 2, 3]),
      );

      final encoded = encodeMatterMessage(msg);
      final decoded = decodeMatterMessage(encoded);

      expect(decoded.payloadHeader.ackedMessageId, 50);
      expect(decoded.payloadHeader.messageType, SecureMessageType.pasePake1);
    });

    test('packet header — session ID and message counter', () {
      final msg = MatterMessage(
        packetHeader: PacketHeader(sessionId: 0, messageId: 0x12345678),
        payloadHeader: PayloadHeader(
          exchangeId: 1,
          messageType: SecureMessageType.statusReport,
          isInitiatorMessage: false,
          requiresAck: false,
        ),
        payload: Uint8List(0),
      );

      final encoded = encodeMatterMessage(msg);
      // Packet header: flags(1) + sessionId(2) + securityFlags(1) + messageId(4) = 8
      expect(encoded[0], 0x00); // flags
      expect(encoded[1], 0x00); // sessionId lo
      expect(encoded[2], 0x00); // sessionId hi
      expect(encoded[3], 0x00); // security flags
      expect(encoded[4], 0x78); // messageId LE
      expect(encoded[5], 0x56);
      expect(encoded[6], 0x34);
      expect(encoded[7], 0x12);
    });

    test('MessageCounter increments', () {
      final counter = MessageCounter();
      final a = counter.next();
      final b = counter.next();
      final c = counter.next();
      expect(b, a + 1);
      expect(c, b + 1);
    });
  });
}
