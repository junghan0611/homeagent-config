/// Matter PASE 커미셔닝 — BLE over BTP
/// PaseClient.js + BtpSessionHandler.js 핵심 로직 통합
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:pointycastle/export.dart' show SHA256Digest;

import 'btp_codec.dart';
import 'message_codec.dart';
import 'spake2p.dart';
import 'tlv.dart';

const _matterServiceUuid = '0000fff6-0000-1000-8000-00805f9b34fb';
const _c1Uuid = '18ee2ef5-263d-4559-959f-4f9c429f9d11';
const _c2Uuid = '18ee2ef5-263d-4559-959f-4f9c429f9d12';

/// PASE 커미셔닝 상태
enum PaseState {
  idle,
  connecting,
  btpHandshake,
  pbkdfRequest,
  pake1,
  pake2,
  pake3,
  success,
  failed,
}

/// PASE 커미셔닝 결과
class PaseResult {
  final bool success;
  final String? error;
  final Uint8List? sessionKey; // Ke — PASE 세션 키
  PaseResult({required this.success, this.error, this.sessionKey});
}

/// BLE PASE 커미셔너
class BlePaseCommissioner {
  final BluetoothDevice device;
  final int setupPin;
  final void Function(PaseState state, String message)? onStateChange;

  BluetoothCharacteristic? _c1; // write (controller→device)
  BluetoothCharacteristic? _c2; // indicate (device→controller)
  StreamSubscription? _indicateSub;

  // BTP 상태
  int _btpFragmentSize = 20; // BLE_MINIMUM_ATT_MTU
  int _btpWindowSize = 6;
  int _btpSequenceNumber = 0; // 핸드셰이크에서 0, 다음부터 1
  int _btpPrevIncomingSeq = 0;
  int _btpPrevAckedSeq = -1;

  // 메시지 수신 버퍼
  Uint8List? _incomingPayload;
  int? _incomingMsgLength;
  final _messageCompleter = <Completer<Uint8List>>[];

  // Matter 메시지
  final _msgCounter = MessageCounter();
  int _exchangeId = 0;

  BlePaseCommissioner({
    required this.device,
    required this.setupPin,
    this.onStateChange,
  }) {
    _exchangeId = Random.secure().nextInt(0xFFFF);
  }

  void _setState(PaseState state, String message) {
    debugPrint('[PASE] $state: $message');
    onStateChange?.call(state, message);
  }

  /// 전체 PASE 커미셔닝 실행
  Future<PaseResult> run() async {
    try {
      // 1. BLE 연결
      _setState(PaseState.connecting, 'BLE 연결 중...');
      await device.connect(timeout: const Duration(seconds: 15));
      await Future.delayed(const Duration(milliseconds: 500));

      // MTU 요청
      final mtu = await device.requestMtu(247);
      debugPrint('[PASE] MTU: $mtu');

      // 서비스/특성 발견
      final services = await device.discoverServices();
      final matterService = services.firstWhere(
        (s) => s.uuid.toString().toLowerCase().contains('fff6'),
        orElse: () => throw Exception('Matter BLE 서비스를 찾을 수 없습니다'),
      );

      _c1 = matterService.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() == _c1Uuid,
        orElse: () => throw Exception('C1 특성을 찾을 수 없습니다'),
      );
      _c2 = matterService.characteristics.firstWhere(
        (c) => c.uuid.toString().toLowerCase() == _c2Uuid,
        orElse: () => throw Exception('C2 특성을 찾을 수 없습니다'),
      );

      // C2 indicate 구독
      await _c2!.setNotifyValue(true);
      _indicateSub = _c2!.onValueReceived.listen(_onBleDataReceived);

      // 2. BTP 핸드셰이크
      _setState(PaseState.btpHandshake, 'BTP 핸드셰이크...');
      await _btpHandshake(mtu);

      // 3. PASE 교환
      final ke = await _paseExchange();

      _setState(PaseState.success, 'PASE 성공!');
      return PaseResult(success: true, sessionKey: ke);
    } catch (e) {
      _setState(PaseState.failed, e.toString());
      return PaseResult(success: false, error: e.toString());
    } finally {
      _indicateSub?.cancel();
      try {
        await device.disconnect();
      } catch (_) {}
    }
  }

  /// BTP 핸드셰이크
  Future<void> _btpHandshake(int mtu) async {
    final request = encodeBtpHandshakeRequest(
      attMtu: mtu,
      clientWindowSize: 6,
    );

    // C2로부터 응답 대기 준비
    final responseFuture = _waitForC2Data();

    // C1에 핸드셰이크 요청 write
    await _c1!.write(request, withoutResponse: false);

    // 응답 대기
    final responseData = await responseFuture.timeout(
      const Duration(seconds: 5),
      onTimeout: () => throw Exception('BTP 핸드셰이크 타임아웃'),
    );

    final response = decodeBtpHandshakeResponse(responseData);
    _btpFragmentSize = response.attMtu;
    _btpWindowSize = response.windowSize;
    debugPrint('[PASE] BTP: ver=${response.version} mtu=${response.attMtu} win=${response.windowSize}');
  }

  /// PASE 메시지 교환
  Future<Uint8List> _paseExchange() async {
    // Step 1: PbkdfParamRequest
    _setState(PaseState.pbkdfRequest, 'PBKDF 파라미터 요청...');
    final initiatorRandom = _secureRandom(32);
    final initiatorSessionId = Random.secure().nextInt(0xFFFF);

    final pbkdfReqTlv = TlvEncoder();
    pbkdfReqTlv.startStructure();
    pbkdfReqTlv.writeBytes(1, initiatorRandom); // initiatorRandom
    pbkdfReqTlv.writeUInt16(2, initiatorSessionId); // initiatorSessionId
    pbkdfReqTlv.writeUInt16(3, 0); // passcodeId = 0 (default)
    pbkdfReqTlv.writeBool(4, false); // hasPbkdfParameters
    pbkdfReqTlv.endContainer();

    final requestPayload = pbkdfReqTlv.toBytes();

    final pbkdfReqMsg = MatterMessage(
      packetHeader: PacketHeader(messageId: _msgCounter.next()),
      payloadHeader: PayloadHeader(
        exchangeId: _exchangeId,
        messageType: SecureMessageType.pbkdfParamRequest,
      ),
      payload: requestPayload,
    );

    final responseMsg = await _sendAndWaitForResponse(
      pbkdfReqMsg,
      SecureMessageType.pbkdfParamResponse,
    );

    // Step 2: PbkdfParamResponse 파싱
    final responsePayload = responseMsg.payload;
    final respFields = TlvDecoder(responsePayload).decodeStructure();

    final responderSessionId = respFields[3]!.intValue!;
    final pbkdfParams = respFields[4]?.structValue;
    if (pbkdfParams == null) {
      throw Exception('PBKDF 파라미터가 응답에 없습니다');
    }
    final iterations = pbkdfParams[1]!.intValue!;
    final salt = pbkdfParams[2]!.bytesValue!;
    debugPrint('[PASE] PBKDF: iterations=$iterations, salt=${salt.length}B');

    // Step 3: Spake2+ 계산
    _setState(PaseState.pake1, 'PAKE1 계산 중...');
    final wResult = await computeW0W1(
      iterations: iterations,
      salt: salt,
      pin: setupPin,
    );

    // context = SHA256(SPAKE_CONTEXT || pbkdfReqPayload || pbkdfRespPayload)
    final spakeContext = Uint8List.fromList(
      'CHIP PAKE V1 Commissioning'.codeUnits,
    );
    final contextData = BytesBuilder();
    contextData.add(spakeContext);
    contextData.add(requestPayload);
    contextData.add(responsePayload);
    final context = Uint8List.fromList(SHA256Digest().process(contextData.toBytes()));

    final spake = Spake2pClient.create(context, wResult.w0);
    final X = spake.computeX();

    // Step 4: PAKE1 전송
    final pake1Tlv = TlvEncoder();
    pake1Tlv.startStructure();
    pake1Tlv.writeBytes(1, X); // pA
    pake1Tlv.endContainer();

    final pake1Msg = MatterMessage(
      packetHeader: PacketHeader(messageId: _msgCounter.next()),
      payloadHeader: PayloadHeader(
        exchangeId: _exchangeId,
        messageType: SecureMessageType.pasePake1,
        ackedMessageId: responseMsg.packetHeader.messageId,
      ),
      payload: pake1Tlv.toBytes(),
    );

    _setState(PaseState.pake2, 'PAKE2 대기...');
    final pake2Msg = await _sendAndWaitForResponse(
      pake1Msg,
      SecureMessageType.pasePake2,
    );

    // Step 5: PAKE2 파싱 + 검증
    final pake2Fields = TlvDecoder(pake2Msg.payload).decodeStructure();
    final Y = pake2Fields[1]!.bytesValue!; // pB
    final verifier = pake2Fields[2]!.bytesValue!; // cB

    final secrets = await spake.computeSecretAndVerifiersFromY(wResult.w1, X, Y);

    // verifier 검증 (hBX == cB)
    if (!_bytesEqual(secrets.hBX, verifier)) {
      throw Exception('PAKE2 verifier 검증 실패 — 잘못된 passcode?');
    }
    debugPrint('[PASE] PAKE2 verifier 검증 성공!');

    // Step 6: PAKE3 전송
    _setState(PaseState.pake3, 'PAKE3 전송...');
    final pake3Tlv = TlvEncoder();
    pake3Tlv.startStructure();
    pake3Tlv.writeBytes(1, secrets.hAY); // cA
    pake3Tlv.endContainer();

    final pake3Msg = MatterMessage(
      packetHeader: PacketHeader(messageId: _msgCounter.next()),
      payloadHeader: PayloadHeader(
        exchangeId: _exchangeId,
        messageType: SecureMessageType.pasePake3,
        ackedMessageId: pake2Msg.packetHeader.messageId,
      ),
      payload: pake3Tlv.toBytes(),
    );

    // StatusReport 대기 (성공 시 StatusReport(0,0))
    final statusMsg = await _sendAndWaitForResponse(
      pake3Msg,
      SecureMessageType.statusReport,
    );

    // StatusReport 파싱: generalCode(uint16) + protocolId(uint32) + protocolCode(uint32)
    if (statusMsg.payload.length >= 8) {
      final generalCode = statusMsg.payload[0] | (statusMsg.payload[1] << 8);
      if (generalCode != 0) {
        throw Exception('PASE 실패: StatusReport generalCode=$generalCode');
      }
    }

    debugPrint('[PASE] 세션 수립 완료! Ke=${secrets.ke.length}B');
    return secrets.ke;
  }

  /// BTP를 통해 Matter 메시지 전송 + 응답 대기
  Future<MatterMessage> _sendAndWaitForResponse(
    MatterMessage msg,
    int expectedMessageType,
  ) async {
    final encoded = encodeMatterMessage(msg);

    // BTP 세그멘테이션
    await _btpSendMessage(encoded);

    // 응답 대기 (BTP 재조립)
    final responseBytes = await _waitForBtpMessage()
        .timeout(const Duration(seconds: 30));

    final response = decodeMatterMessage(responseBytes);
    if (response.payloadHeader.messageType != expectedMessageType) {
      throw Exception(
        '예상 메시지 타입 $expectedMessageType, '
        '실제: ${response.payloadHeader.messageType}',
      );
    }
    return response;
  }

  /// BTP를 통해 메시지 전송 (세그멘테이션)
  Future<void> _btpSendMessage(Uint8List data) async {
    int offset = 0;
    final totalLength = data.length;
    bool isFirst = true;

    while (offset < totalLength) {
      final hasAck = _btpPrevIncomingSeq != _btpPrevAckedSeq;
      if (hasAck) _btpPrevAckedSeq = _btpPrevIncomingSeq;

      // 헤더 오버헤드 계산
      final headerSize = 2 + (isFirst ? 2 : 0) + (hasAck ? 1 : 0);
      final maxPayload = _btpFragmentSize - headerSize;
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
        ackNumber: hasAck ? _btpPrevIncomingSeq : null,
        sequenceNumber: _nextBtpSeq(),
        messageLength: isFirst ? totalLength : null,
        segmentPayload: Uint8List.sublistView(data, offset, offset + chunkSize),
      );

      final encoded = encodeBtpPacket(pkt);
      await _c1!.write(encoded, withoutResponse: false);

      offset += chunkSize;
      isFirst = false;
    }
  }

  /// BTP 메시지 재조립 대기
  Future<Uint8List> _waitForBtpMessage() {
    final completer = Completer<Uint8List>();
    _messageCompleter.add(completer);
    return completer.future;
  }

  int _nextBtpSeq() {
    _btpSequenceNumber = (_btpSequenceNumber + 1) % 256;
    return _btpSequenceNumber;
  }

  // C2 데이터 큐
  final _c2DataQueue = <Uint8List>[];
  final _c2Waiters = <Completer<Uint8List>>[];

  Future<Uint8List> _waitForC2Data() {
    if (_c2DataQueue.isNotEmpty) {
      return Future.value(_c2DataQueue.removeAt(0));
    }
    final c = Completer<Uint8List>();
    _c2Waiters.add(c);
    return c.future;
  }

  /// C2 indicate 데이터 수신 콜백
  void _onBleDataReceived(List<int> data) {
    final bytes = Uint8List.fromList(data);
    debugPrint('[BLE] C2 data: ${bytes.length}B');

    // 핸드셰이크 응답인지 확인
    if (bytes.isNotEmpty && bytes[0] == 0x65) {
      // BTP 핸드셰이크 응답
      if (_c2Waiters.isNotEmpty) {
        _c2Waiters.removeAt(0).complete(bytes);
      } else {
        _c2DataQueue.add(bytes);
      }
      return;
    }

    // BTP 데이터 패킷
    _handleBtpData(bytes);
  }

  void _handleBtpData(Uint8List data) {
    try {
      final pkt = decodeBtpPacket(data);
      _btpPrevIncomingSeq = pkt.sequenceNumber;

      // 세그먼트 조립
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
        final completeMsg = _incomingPayload!;
        _incomingPayload = null;
        _incomingMsgLength = null;

        // ACK 전송
        _sendAck();

        // 완성된 메시지 전달
        if (_messageCompleter.isNotEmpty) {
          _messageCompleter.removeAt(0).complete(completeMsg);
        }
      }
    } catch (e) {
      debugPrint('[BTP] Error: $e');
    }
  }

  Future<void> _sendAck() async {
    final ackPkt = BtpPacket(
      header: const BtpPacketHeader(hasAck: true),
      ackNumber: _btpPrevIncomingSeq,
      sequenceNumber: _nextBtpSeq(),
      segmentPayload: Uint8List(0),
    );
    try {
      await _c1!.write(encodeBtpPacket(ackPkt), withoutResponse: false);
    } catch (e) {
      debugPrint('[BTP] ACK send failed: $e');
    }
  }
}

// --- Helpers ---

Uint8List _secureRandom(int len) {
  final rng = Random.secure();
  return Uint8List.fromList(List.generate(len, (_) => rng.nextInt(256)));
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (int i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
