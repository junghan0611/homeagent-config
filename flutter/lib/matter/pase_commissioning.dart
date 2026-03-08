/// Matter PASE 커미셔닝 엔진 — 순수 Dart, Flutter 의존성 없음
/// BLE 전송은 BtpSession 콜백으로 주입됨
library;

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:pointycastle/export.dart' show SHA256Digest;

import 'btp_session.dart';
import 'message_codec.dart';
import 'spake2p.dart';
import 'tlv.dart';

/// PASE 상태 (UI에 전달)
enum PaseState {
  idle,
  btpHandshake,
  pbkdfRequest,
  pake1,
  pake2,
  pake3,
  success,
  failed,
}

/// PASE 결과
class PaseResult {
  final bool success;
  final String? error;
  final Uint8List? sessionKey;
  PaseResult({required this.success, this.error, this.sessionKey});
}

/// PASE 상태 리스너
typedef PaseStateListener = void Function(PaseState state, String message);

/// PASE 엔진 — BLE 독립, BtpSession 위에서 동작
class PaseEngine {
  final BtpSession btp;
  final int setupPin;
  final PaseStateListener? onStateChange;

  final _msgCounter = MessageCounter();
  int _exchangeId = 0;

  PaseEngine({
    required this.btp,
    required this.setupPin,
    this.onStateChange,
  }) {
    _exchangeId = Random.secure().nextInt(0xFFFF);
  }

  void _setState(PaseState state, String msg) {
    onStateChange?.call(state, msg);
  }

  /// PASE 교환 실행 (BTP 세션이 이미 수립된 상태에서 호출)
  Future<PaseResult> run() async {
    try {
      final ke = await _paseExchange();
      _setState(PaseState.success, 'PASE 성공');
      return PaseResult(success: true, sessionKey: ke);
    } catch (e) {
      _setState(PaseState.failed, e.toString());
      return PaseResult(success: false, error: e.toString());
    }
  }

  Future<Uint8List> _paseExchange() async {
    // 1. PbkdfParamRequest
    _setState(PaseState.pbkdfRequest, 'PBKDF 파라미터 요청...');
    final initiatorRandom = _secureRandom(32);
    final initiatorSessionId = Random.secure().nextInt(0xFFFF);

    final reqTlv = TlvEncoder();
    reqTlv.startStructure();
    reqTlv.writeBytes(1, initiatorRandom);
    reqTlv.writeUInt16(2, initiatorSessionId);
    reqTlv.writeUInt16(3, 0); // passcodeId default
    reqTlv.writeBool(4, false); // hasPbkdfParameters
    reqTlv.endContainer();
    final requestPayload = reqTlv.toBytes();

    final respMsg = await _sendAndWait(
      requestPayload,
      SecureMessageType.pbkdfParamRequest,
      SecureMessageType.pbkdfParamResponse,
    );

    // 2. PbkdfParamResponse 파싱
    final responsePayload = respMsg.payload;
    final respFields = TlvDecoder(responsePayload).decodeStructure();
    final pbkdfParams = respFields[4]?.structValue;
    if (pbkdfParams == null) {
      throw Exception('PBKDF 파라미터가 응답에 없습니다');
    }
    final iterations = pbkdfParams[1]!.intValue!;
    final salt = pbkdfParams[2]!.bytesValue!;

    // 3. Spake2+
    _setState(PaseState.pake1, 'PAKE1 계산...');
    final wResult = await computeW0W1(
      iterations: iterations,
      salt: salt,
      pin: setupPin,
    );

    final spakeContextInput = BytesBuilder();
    spakeContextInput.add('CHIP PAKE V1 Commissioning'.codeUnits);
    spakeContextInput.add(requestPayload);
    spakeContextInput.add(responsePayload);
    final context = Uint8List.fromList(
        SHA256Digest().process(spakeContextInput.toBytes()));

    final spake = Spake2pClient.create(context, wResult.w0);
    final x = spake.computeX();

    // 4. PAKE1
    final pake1Tlv = TlvEncoder();
    pake1Tlv.startStructure();
    pake1Tlv.writeBytes(1, x);
    pake1Tlv.endContainer();

    _setState(PaseState.pake2, 'PAKE2 대기...');
    final pake2Msg = await _sendAndWait(
      pake1Tlv.toBytes(),
      SecureMessageType.pasePake1,
      SecureMessageType.pasePake2,
      ackedMessageId: respMsg.packetHeader.messageId,
    );

    // 5. PAKE2 검증
    final pake2Fields = TlvDecoder(pake2Msg.payload).decodeStructure();
    final y = pake2Fields[1]!.bytesValue!;
    final verifier = pake2Fields[2]!.bytesValue!;

    final secrets = await spake.computeSecretAndVerifiersFromY(
        wResult.w1, x, y);

    if (!_bytesEqual(secrets.hBX, verifier)) {
      throw Exception('PAKE2 verifier 불일치 — passcode가 틀렸을 수 있습니다');
    }

    // 6. PAKE3
    _setState(PaseState.pake3, 'PAKE3 전송...');
    final pake3Tlv = TlvEncoder();
    pake3Tlv.startStructure();
    pake3Tlv.writeBytes(1, secrets.hAY);
    pake3Tlv.endContainer();

    final statusMsg = await _sendAndWait(
      pake3Tlv.toBytes(),
      SecureMessageType.pasePake3,
      SecureMessageType.statusReport,
      ackedMessageId: pake2Msg.packetHeader.messageId,
    );

    // StatusReport: generalCode(uint16) == 0 → 성공
    if (statusMsg.payload.length >= 2) {
      final generalCode = statusMsg.payload[0] | (statusMsg.payload[1] << 8);
      if (generalCode != 0) {
        throw Exception('PASE 실패: StatusReport code=$generalCode');
      }
    }

    return secrets.ke;
  }

  Future<MatterMessage> _sendAndWait(
    Uint8List tlvPayload,
    int sendType,
    int expectType, {
    int? ackedMessageId,
  }) async {
    final msg = MatterMessage(
      packetHeader: PacketHeader(messageId: _msgCounter.next()),
      payloadHeader: PayloadHeader(
        exchangeId: _exchangeId,
        messageType: sendType,
        ackedMessageId: ackedMessageId,
      ),
      payload: tlvPayload,
    );

    final encoded = encodeMatterMessage(msg);
    await btp.sendMessage(encoded);
    final responseBytes = await btp.waitForMessage();
    final response = decodeMatterMessage(responseBytes);

    if (response.payloadHeader.messageType != expectType) {
      throw Exception(
        '예상 타입 $expectType, 실제: ${response.payloadHeader.messageType}');
    }
    return response;
  }
}

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
