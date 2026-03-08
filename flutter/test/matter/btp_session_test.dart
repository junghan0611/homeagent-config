import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeagent/matter/btp_codec.dart';
import 'package:homeagent/matter/btp_session.dart';

void main() {
  group('BtpSession', () {
    test('single segment message send', () async {
      final written = <Uint8List>[];
      final session = BtpSession(
        writeToDevice: (data) async => written.add(Uint8List.fromList(data)),
        disconnect: () async {},
        fragmentSize: 100,
      );
      session.initFromHandshakeResponse(103, 6); // 103 - 3 = 100

      final msg = Uint8List.fromList([1, 2, 3, 4, 5]);
      await session.sendMessage(msg);

      expect(written.length, 1);
      final decoded = decodeBtpPacket(written[0]);
      expect(decoded.header.isBegin, true);
      expect(decoded.header.isEnd, true);
      expect(decoded.messageLength, 5);
    });

    test('multi-segment message send', () async {
      final written = <Uint8List>[];
      final session = BtpSession(
        writeToDevice: (data) async => written.add(Uint8List.fromList(data)),
        disconnect: () async {},
        fragmentSize: 10, // 작은 fragment로 강제 분할
      );
      session.initFromHandshakeResponse(13, 6); // 13 - 3 = 10

      // 20바이트 메시지 → 여러 세그먼트
      final msg = Uint8List.fromList(List.generate(20, (i) => i));
      await session.sendMessage(msg);

      expect(written.length, greaterThan(1));

      // 첫 번째는 begin
      final first = decodeBtpPacket(written[0]);
      expect(first.header.isBegin, true);
      expect(first.messageLength, 20);

      // 마지막은 end
      final last = decodeBtpPacket(written.last);
      expect(last.header.isEnd, true);
    });

    test('receive reassembly', () async {
      final session = BtpSession(
        writeToDevice: (data) async {},
        disconnect: () async {},
        fragmentSize: 100,
      );
      session.initFromHandshakeResponse(100, 6);

      // 2개 세그먼트로 분할된 메시지 수신 시뮬레이션
      final part1 = encodeBtpPacket(BtpPacket(
        header: const BtpPacketHeader(isBegin: true),
        sequenceNumber: 1,
        messageLength: 5,
        segmentPayload: Uint8List.fromList([1, 2, 3]),
      ));
      final part2 = encodeBtpPacket(BtpPacket(
        header: const BtpPacketHeader(isContinuing: true, isEnd: true),
        sequenceNumber: 2,
        segmentPayload: Uint8List.fromList([4, 5]),
      ));

      final msgFuture = session.waitForMessage();
      await session.handleIncomingData(part1);
      await session.handleIncomingData(part2);

      final result = await msgFuture;
      expect(result, Uint8List.fromList([1, 2, 3, 4, 5]));
    });

    test('close clears pending completers', () async {
      final session = BtpSession(
        writeToDevice: (data) async {},
        disconnect: () async {},
      );

      // waitForMessage 호출 → completer 등록
      Object? caughtError;
      final future = session.waitForMessage(
        timeout: const Duration(seconds: 10),
      ).catchError((e) {
        caughtError = e;
        return Uint8List(0);
      });

      await session.close();
      await future; // catchError가 처리

      expect(session.isActive, false);
      expect(caughtError, isA<StateError>());
    });

    test('send after close throws', () async {
      final session = BtpSession(
        writeToDevice: (data) async {},
        disconnect: () async {},
      );
      await session.close();

      expect(
        () => session.sendMessage(Uint8List.fromList([1])),
        throwsStateError,
      );
    });
  });
}
