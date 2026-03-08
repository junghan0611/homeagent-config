/// Matter 보안 세션 — AES-128-CCM 암호화/복호화
/// PASE 성공 후 Ke에서 세션 키 유도
library;

import 'dart:convert' show utf8;
import 'dart:typed_data';
import 'package:pointycastle/export.dart';

import 'message_codec.dart';

/// Interaction Model 프로토콜 ID
const int interactionProtocolId = 0x0001;

/// Interaction 메시지 타입
class InteractionMessageType {
  static const int invokeRequest = 8;
  static const int invokeResponse = 9;
}

/// PASE 세션 — Ke에서 encrypt/decrypt 키 유도
class SecureSession {
  final Uint8List encryptKey; // initiator→device (I2R)
  final Uint8List decryptKey; // device→initiator (R2I)
  final int sessionId;
  final int peerSessionId;
  final MessageCounter _counter = MessageCounter();

  SecureSession._({
    required this.encryptKey,
    required this.decryptKey,
    required this.sessionId,
    required this.peerSessionId,
  });

  /// Ke에서 세션 키 생성 (PASE 직후 호출)
  factory SecureSession.fromKe(
    Uint8List ke, {
    required int sessionId,
    required int peerSessionId,
  }) {
    // HKDF(Ke, salt="", info="SessionKeys", length=48)
    // → keys[0:16] = I2R key, keys[16:32] = R2I key, keys[32:48] = attestation
    final hkdf = HKDFKeyDerivator(SHA256Digest())
      ..init(HkdfParameters(ke, 48, Uint8List(0), _utf8('SessionKeys')));
    final keys = Uint8List(48);
    hkdf.deriveKey(null, 0, keys, 0);

    // initiator: encryptKey = I2R (0:16), decryptKey = R2I (16:32)
    return SecureSession._(
      encryptKey: Uint8List.fromList(keys.sublist(0, 16)),
      decryptKey: Uint8List.fromList(keys.sublist(16, 32)),
      sessionId: sessionId,
      peerSessionId: peerSessionId,
    );
  }

  /// 암호화된 Matter 메시지 생성
  Uint8List encryptMessage({
    required int exchangeId,
    required int messageType,
    required Uint8List payload,
    int protocolId = interactionProtocolId,
    int? ackedMessageId,
  }) {
    final messageId = _counter.next();

    // 패킷 헤더 (암호화되지 않음)
    final packetHeader = _encodePacketHeaderSecure(
      sessionId: peerSessionId,
      messageId: messageId,
    );

    // 페이로드 헤더 + 페이로드 (암호화 대상)
    final payloadHeader = PayloadHeader(
      exchangeId: exchangeId,
      messageType: messageType,
      protocolId: protocolId,
      isInitiatorMessage: true,
      requiresAck: true,
      ackedMessageId: ackedMessageId,
    );
    final payloadHeaderBytes = _encodePayloadHeaderBytes(payloadHeader);
    final plaintext = Uint8List.fromList([...payloadHeaderBytes, ...payload]);

    // Nonce: securityFlags(1) + messageId(4) + nodeId(8) = 13 bytes
    final nonce = _buildNonce(0x00, messageId, 0); // PASE: nodeId=0

    // AES-128-CCM encrypt
    // AAD = packetHeader
    final encrypted = _aes128CcmEncrypt(encryptKey, plaintext, nonce, packetHeader);

    return Uint8List.fromList([...packetHeader, ...encrypted]);
  }

  /// 암호화된 메시지 복호화
  MatterMessage decryptMessage(Uint8List data) {
    // 패킷 헤더 파싱 (평문)
    int pos = 0;
    final flags = data[pos++];
    final sid = data[pos] | (data[pos + 1] << 8);
    pos += 2;
    final securityFlags = data[pos++];
    final messageId = data[pos] | (data[pos + 1] << 8) |
        (data[pos + 2] << 16) | (data[pos + 3] << 24);
    pos += 4;

    // Source/Dest NodeID (conditional)
    if (flags & 0x04 != 0) pos += 8;
    if (flags & 0x01 != 0) pos += 8;
    if (flags & 0x02 != 0) pos += 2;
    if (securityFlags & 0x20 != 0) {
      final extLen = data[pos] | (data[pos + 1] << 8);
      pos += 2 + extLen;
    }

    final headerBytes = Uint8List.sublistView(data, 0, pos);
    final ciphertext = Uint8List.sublistView(data, pos);

    // Nonce
    final nonce = _buildNonce(securityFlags, messageId, 0);

    // Decrypt
    final plaintext = _aes128CcmDecrypt(decryptKey, ciphertext, nonce, headerBytes);

    // 페이로드 헤더 + 페이로드 파싱
    int ppos = 0;
    final phFlags = plaintext[ppos++];
    final msgType = plaintext[ppos++];
    final exchangeId = plaintext[ppos] | (plaintext[ppos + 1] << 8);
    ppos += 2;

    final hasVendorId = (phFlags & 0x10) != 0;
    int protocolId;
    if (hasVendorId) {
      protocolId = plaintext[ppos] | (plaintext[ppos + 1] << 8) |
          (plaintext[ppos + 2] << 16) | (plaintext[ppos + 3] << 24);
      ppos += 4;
    } else {
      protocolId = plaintext[ppos] | (plaintext[ppos + 1] << 8);
      ppos += 2;
    }

    int? ackedMsgId;
    if ((phFlags & 0x02) != 0) {
      ackedMsgId = plaintext[ppos] | (plaintext[ppos + 1] << 8) |
          (plaintext[ppos + 2] << 16) | (plaintext[ppos + 3] << 24);
      ppos += 4;
    }

    return MatterMessage(
      packetHeader: PacketHeader(sessionId: sid, messageId: messageId),
      payloadHeader: PayloadHeader(
        exchangeId: exchangeId,
        messageType: msgType,
        protocolId: protocolId,
        ackedMessageId: ackedMsgId,
      ),
      payload: Uint8List.sublistView(plaintext, ppos),
    );
  }
}

// --- AES-128-CCM ---

const int _ccmTagLen = 16; // MIC length

Uint8List _aes128CcmEncrypt(
    Uint8List key, Uint8List plaintext, Uint8List nonce, Uint8List aad) {
  final cipher = CCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(
      KeyParameter(key), _ccmTagLen * 8, nonce, aad,
    ));
  final output = Uint8List(plaintext.length + _ccmTagLen);
  final len = cipher.processBytes(plaintext, 0, plaintext.length, output, 0);
  cipher.doFinal(output, len);
  return output;
}

Uint8List _aes128CcmDecrypt(
    Uint8List key, Uint8List ciphertext, Uint8List nonce, Uint8List aad) {
  final cipher = CCMBlockCipher(AESEngine())
    ..init(false, AEADParameters(
      KeyParameter(key), _ccmTagLen * 8, nonce, aad,
    ));
  final output = Uint8List(ciphertext.length - _ccmTagLen);
  final len = cipher.processBytes(ciphertext, 0, ciphertext.length, output, 0);
  cipher.doFinal(output, len);
  return output;
}

Uint8List _buildNonce(int securityFlags, int messageId, int nodeId) {
  // 13 bytes: securityFlags(1) + messageId(4 LE) + nodeId(8 LE)
  final nonce = Uint8List(13);
  nonce[0] = securityFlags;
  nonce[1] = messageId & 0xFF;
  nonce[2] = (messageId >> 8) & 0xFF;
  nonce[3] = (messageId >> 16) & 0xFF;
  nonce[4] = (messageId >> 24) & 0xFF;
  // nodeId bytes 5-12 (0 for PASE)
  final bd = ByteData.sublistView(nonce);
  bd.setUint64(5, nodeId, Endian.little);
  return nonce;
}

Uint8List _encodePacketHeaderSecure({
  required int sessionId,
  required int messageId,
}) {
  final buf = BytesBuilder();
  buf.addByte(0x00); // flags: no source/dest
  buf.addByte(sessionId & 0xFF);
  buf.addByte((sessionId >> 8) & 0xFF);
  buf.addByte(0x00); // security flags: unicast
  buf.addByte(messageId & 0xFF);
  buf.addByte((messageId >> 8) & 0xFF);
  buf.addByte((messageId >> 16) & 0xFF);
  buf.addByte((messageId >> 24) & 0xFF);
  return buf.toBytes();
}

Uint8List _encodePayloadHeaderBytes(PayloadHeader h) {
  final buf = BytesBuilder();
  int flags = 0;
  if (h.isInitiatorMessage) flags |= 0x01;
  if (h.ackedMessageId != null) flags |= 0x02;
  if (h.requiresAck) flags |= 0x04;
  buf.addByte(flags);
  buf.addByte(h.messageType);
  buf.addByte(h.exchangeId & 0xFF);
  buf.addByte((h.exchangeId >> 8) & 0xFF);
  buf.addByte(h.protocolId & 0xFF);
  buf.addByte((h.protocolId >> 8) & 0xFF);
  if (h.ackedMessageId != null) {
    buf.addByte(h.ackedMessageId! & 0xFF);
    buf.addByte((h.ackedMessageId! >> 8) & 0xFF);
    buf.addByte((h.ackedMessageId! >> 16) & 0xFF);
    buf.addByte((h.ackedMessageId! >> 24) & 0xFF);
  }
  return buf.toBytes();
}

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));
