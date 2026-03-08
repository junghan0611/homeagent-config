import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeagent/matter/btp_codec.dart';

void main() {
  group('BTP Handshake', () {
    test('encode request — version 4, MTU 247, window 6', () {
      final req = encodeBtpHandshakeRequest(attMtu: 247, clientWindowSize: 6);
      expect(req[0], 0x65); // header
      expect(req[1], 0x6C); // opcode
      expect(req[2], 0x04); // version 4 in lower nibble
      // ATT MTU 247 = 0xF7
      expect(req[6], 0xF7);
      expect(req[7], 0x00);
      // window size
      expect(req[8], 6);
      expect(req.length, 9);
    });

    test('decode response', () {
      // version=4, attMtu=244, windowSize=6
      final resp = Uint8List.fromList([0x65, 0x6C, 0x04, 0xF4, 0x00, 0x06]);
      final decoded = decodeBtpHandshakeResponse(resp);
      expect(decoded.version, 4);
      expect(decoded.attMtu, 244);
      expect(decoded.windowSize, 6);
    });

    test('decode response — invalid header throws', () {
      final bad = Uint8List.fromList([0x00, 0x6C, 0x04, 0xF4, 0x00, 0x06]);
      expect(() => decodeBtpHandshakeResponse(bad), throwsFormatException);
    });
  });

  group('BTP Data Packet', () {
    test('encode single-segment packet (begin+end)', () {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5]);
      final pkt = BtpPacket(
        header: const BtpPacketHeader(isBegin: true, isEnd: true),
        sequenceNumber: 1,
        messageLength: 5,
        segmentPayload: payload,
      );
      final encoded = encodeBtpPacket(pkt);
      // flags: begin(1) | end(4) = 0x05
      expect(encoded[0], 0x05);
      // seq
      expect(encoded[1], 1);
      // message length LE
      expect(encoded[2], 5);
      expect(encoded[3], 0);
      // payload
      expect(encoded.sublist(4), payload);
    });

    test('encode with ack', () {
      final pkt = BtpPacket(
        header: const BtpPacketHeader(hasAck: true, isBegin: true, isEnd: true),
        ackNumber: 3,
        sequenceNumber: 4,
        messageLength: 2,
        segmentPayload: Uint8List.fromList([0xAA, 0xBB]),
      );
      final encoded = encodeBtpPacket(pkt);
      // flags: ack(8) | begin(1) | end(4) = 0x0D
      expect(encoded[0], 0x0D);
      expect(encoded[1], 3); // ack
      expect(encoded[2], 4); // seq
      expect(encoded[3], 2); // msgLen lo
      expect(encoded[4], 0); // msgLen hi
      expect(encoded[5], 0xAA);
      expect(encoded[6], 0xBB);
    });

    test('decode roundtrip', () {
      final original = BtpPacket(
        header: const BtpPacketHeader(
          hasAck: true, isBegin: true, isEnd: true,
        ),
        ackNumber: 7,
        sequenceNumber: 12,
        messageLength: 3,
        segmentPayload: Uint8List.fromList([10, 20, 30]),
      );
      final encoded = encodeBtpPacket(original);
      final decoded = decodeBtpPacket(encoded);

      expect(decoded.header.hasAck, true);
      expect(decoded.header.isBegin, true);
      expect(decoded.header.isEnd, true);
      expect(decoded.ackNumber, 7);
      expect(decoded.sequenceNumber, 12);
      expect(decoded.messageLength, 3);
      expect(decoded.segmentPayload, Uint8List.fromList([10, 20, 30]));
    });

    test('continuing segment — no messageLength', () {
      final pkt = BtpPacket(
        header: const BtpPacketHeader(isContinuing: true),
        sequenceNumber: 5,
        segmentPayload: Uint8List.fromList([0xFF]),
      );
      final encoded = encodeBtpPacket(pkt);
      final decoded = decodeBtpPacket(encoded);
      expect(decoded.header.isContinuing, true);
      expect(decoded.header.isBegin, false);
      expect(decoded.messageLength, isNull);
      expect(decoded.sequenceNumber, 5);
    });
  });
}
