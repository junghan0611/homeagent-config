/// BTP 세션 핸들러 — 순수 Dart, Flutter 의존성 없음
/// BLE 전송은 콜백으로 주입
library;

import 'dart:async';
import 'dart:typed_data';

import 'btp_codec.dart';

/// BLE 전송 콜백 인터페이스 (플랫폼 독립)
typedef BleWriteCallback = Future<void> Function(Uint8List data);
typedef BleDisconnectCallback = Future<void> Function();

/// BTP 세션 — 세그멘테이션 + ACK + 메시지 재조립
class BtpSession {
  final BleWriteCallback writeToDevice;
  final BleDisconnectCallback disconnect;

  int fragmentSize;
  int windowSize;
  int _seqNumber = 0;
  int _prevIncomingSeq = 0;
  int _prevAckedSeq = -1;

  // 수신 세그먼트 재조립
  Uint8List? _incomingPayload;
  int? _incomingMsgLength;

  // 완성된 메시지 전달
  final _messageCompleters = <Completer<Uint8List>>[];

  bool _isActive = true;

  BtpSession({
    required this.writeToDevice,
    required this.disconnect,
    this.fragmentSize = 20,
    this.windowSize = 6,
  });

  bool get isActive => _isActive;

  /// BTP 핸드셰이크 응답 처리 후 세션 초기화
  void initFromHandshakeResponse(int attMtu, int win) {
    fragmentSize = attMtu;
    windowSize = win;
    _prevIncomingSeq = 0;
    _prevAckedSeq = -1;
    _seqNumber = 0; // 핸드셰이크에서 0, 다음 1부터
  }

  /// Matter 메시지 전송 (BTP 세그멘테이션)
  Future<void> sendMessage(Uint8List data) async {
    if (!_isActive) throw StateError('BTP session closed');
    int offset = 0;
    final totalLength = data.length;
    bool isFirst = true;

    while (offset < totalLength) {
      final hasAck = _prevIncomingSeq != _prevAckedSeq;
      if (hasAck) _prevAckedSeq = _prevIncomingSeq;

      final headerSize = 2 + (isFirst ? 2 : 0) + (hasAck ? 1 : 0);
      final maxPayload = fragmentSize - headerSize;
      final remaining = totalLength - offset;
      final chunkSize = remaining > maxPayload ? maxPayload : remaining;
      final isLast = (offset + chunkSize) >= totalLength;

      final pkt = BtpPacket(
        header: BtpPacketHeader(
          hasAck: hasAck,
          isBegin: isFirst,
          isContinuing: !isFirst,
          isEnd: isLast,
        ),
        ackNumber: hasAck ? _prevIncomingSeq : null,
        sequenceNumber: _nextSeq(),
        messageLength: isFirst ? totalLength : null,
        segmentPayload: Uint8List.sublistView(data, offset, offset + chunkSize),
      );

      await writeToDevice(encodeBtpPacket(pkt));
      offset += chunkSize;
      isFirst = false;
    }
  }

  /// BLE에서 수신된 데이터 처리 (BTP 패킷 디코딩 + 재조립)
  Future<void> handleIncomingData(Uint8List data) async {
    if (!_isActive) return;
    try {
      final pkt = decodeBtpPacket(data);
      _prevIncomingSeq = pkt.sequenceNumber;

      if (pkt.header.isBegin) {
        _incomingMsgLength = pkt.messageLength;
        _incomingPayload = Uint8List.fromList(pkt.segmentPayload);
      } else if (pkt.header.isContinuing || pkt.header.isEnd) {
        if (_incomingPayload != null) {
          final combined = BytesBuilder();
          combined.add(_incomingPayload!);
          combined.add(pkt.segmentPayload);
          _incomingPayload = combined.toBytes();
        }
      }

      if (pkt.header.isEnd && _incomingPayload != null) {
        final complete = _incomingPayload!;
        _incomingPayload = null;
        _incomingMsgLength = null;

        // ACK 전송
        await _sendAck();

        // 완성된 메시지 전달
        if (_messageCompleters.isNotEmpty) {
          _messageCompleters.removeAt(0).complete(complete);
        }
      }
    } catch (e) {
      await close();
      rethrow;
    }
  }

  /// 다음 완성된 메시지 대기
  Future<Uint8List> waitForMessage({Duration timeout = const Duration(seconds: 30)}) {
    final c = Completer<Uint8List>();
    _messageCompleters.add(c);
    return c.future.timeout(timeout, onTimeout: () {
      _messageCompleters.remove(c);
      throw TimeoutException('BTP message timeout', timeout);
    });
  }

  /// 세션 종료 — 대기 중인 completer 전부 에러 처리
  Future<void> close() async {
    if (!_isActive) return;
    _isActive = false;

    // 대기 중인 모든 completer 에러 처리
    for (final c in _messageCompleters) {
      if (!c.isCompleted) {
        c.completeError(StateError('BTP session closed'));
      }
    }
    _messageCompleters.clear();
    _incomingPayload = null;
    _incomingMsgLength = null;

    await disconnect();
  }

  Future<void> _sendAck() async {
    final pkt = BtpPacket(
      header: const BtpPacketHeader(hasAck: true),
      ackNumber: _prevIncomingSeq,
      sequenceNumber: _nextSeq(),
      segmentPayload: Uint8List(0),
    );
    _prevAckedSeq = _prevIncomingSeq;
    try {
      await writeToDevice(encodeBtpPacket(pkt));
    } catch (_) {}
  }

  int _nextSeq() {
    _seqNumber = (_seqNumber + 1) % 256;
    return _seqNumber;
  }
}
