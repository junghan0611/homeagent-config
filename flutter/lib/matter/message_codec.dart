/// Matter 메시지 코덱 — 패킷/페이로드 헤더 인코딩/디코딩
/// matter.js MessageCodec.js 포팅 (PASE용 최소 구현)
library;

import 'dart:math';
import 'dart:typed_data';

/// Secure Channel 프로토콜 ID
const int secureChannelProtocolId = 0x0000;

/// Secure Channel 메시지 타입
class SecureMessageType {
  static const int standaloneAck = 16;
  static const int pbkdfParamRequest = 32;
  static const int pbkdfParamResponse = 33;
  static const int pasePake1 = 34;
  static const int pasePake2 = 35;
  static const int pasePake3 = 36;
  static const int statusReport = 64;
}

/// 패킷 헤더
class PacketHeader {
  final int sessionId;
  final int messageId;
  final int sessionType; // 0=Unicast

  PacketHeader({
    this.sessionId = 0,
    required this.messageId,
    this.sessionType = 0,
  });
}

/// 페이로드 헤더
class PayloadHeader {
  final int exchangeId;
  final int messageType;
  final int protocolId;
  final bool isInitiatorMessage;
  final bool requiresAck;
  final int? ackedMessageId;

  PayloadHeader({
    required this.exchangeId,
    required this.messageType,
    this.protocolId = secureChannelProtocolId,
    this.isInitiatorMessage = true,
    this.requiresAck = true,
    this.ackedMessageId,
  });
}

/// Matter 메시지 (패킷 + 페이로드)
class MatterMessage {
  final PacketHeader packetHeader;
  final PayloadHeader payloadHeader;
  final Uint8List payload;

  MatterMessage({
    required this.packetHeader,
    required this.payloadHeader,
    required this.payload,
  });
}

/// 메시지 → 바이트 인코딩
Uint8List encodeMatterMessage(MatterMessage msg) {
  final packetBytes = _encodePacketHeader(msg.packetHeader);
  final payloadHeaderBytes = _encodePayloadHeader(msg.payloadHeader);
  final buf = BytesBuilder();
  buf.add(packetBytes);
  buf.add(payloadHeaderBytes);
  buf.add(msg.payload);
  return buf.toBytes();
}

/// 바이트 → 메시지 디코딩
MatterMessage decodeMatterMessage(Uint8List data) {
  int pos = 0;

  // Packet header
  final flags = data[pos++];
  final sessionId = data[pos] | (data[pos + 1] << 8);
  pos += 2;
  final securityFlags = data[pos++];
  final messageId = data[pos] | (data[pos + 1] << 8) |
      (data[pos + 2] << 16) | (data[pos + 3] << 24);
  pos += 4;
  final sessionType = securityFlags & 0x03;

  // Source/Dest node IDs (conditional)
  if (flags & 0x04 != 0) pos += 8; // source node ID
  if (flags & 0x01 != 0) pos += 8; // dest node ID
  if (flags & 0x02 != 0) pos += 2; // dest group ID

  // Message extension
  if (securityFlags & 0x20 != 0) {
    final extLen = data[pos] | (data[pos + 1] << 8);
    pos += 2 + extLen;
  }

  final packetHeader = PacketHeader(
    sessionId: sessionId,
    messageId: messageId,
    sessionType: sessionType,
  );

  // Payload header
  final phFlags = data[pos++];
  final messageType = data[pos++];
  final exchangeId = data[pos] | (data[pos + 1] << 8);
  pos += 2;

  final hasVendorId = (phFlags & 0x10) != 0;
  int protocolId;
  if (hasVendorId) {
    protocolId = data[pos] | (data[pos + 1] << 8) |
        (data[pos + 2] << 16) | (data[pos + 3] << 24);
    pos += 4;
  } else {
    protocolId = data[pos] | (data[pos + 1] << 8);
    pos += 2;
  }

  int? ackedMessageId;
  if ((phFlags & 0x02) != 0) {
    ackedMessageId = data[pos] | (data[pos + 1] << 8) |
        (data[pos + 2] << 16) | (data[pos + 3] << 24);
    pos += 4;
  }

  final payloadHeader = PayloadHeader(
    exchangeId: exchangeId,
    messageType: messageType,
    protocolId: protocolId,
    isInitiatorMessage: (phFlags & 0x01) != 0,
    requiresAck: (phFlags & 0x04) != 0,
    ackedMessageId: ackedMessageId,
  );

  final payload = Uint8List.sublistView(data, pos);

  return MatterMessage(
    packetHeader: packetHeader,
    payloadHeader: payloadHeader,
    payload: payload,
  );
}

Uint8List _encodePacketHeader(PacketHeader h) {
  final buf = BytesBuilder();
  // flags: version=0, no source/dest node
  buf.addByte(0x00);
  // session ID (uint16 LE)
  buf.addByte(h.sessionId & 0xFF);
  buf.addByte((h.sessionId >> 8) & 0xFF);
  // security flags: session type
  buf.addByte(h.sessionType & 0x03);
  // message counter (uint32 LE)
  buf.addByte(h.messageId & 0xFF);
  buf.addByte((h.messageId >> 8) & 0xFF);
  buf.addByte((h.messageId >> 16) & 0xFF);
  buf.addByte((h.messageId >> 24) & 0xFF);
  return buf.toBytes();
}

Uint8List _encodePayloadHeader(PayloadHeader h) {
  final buf = BytesBuilder();
  int flags = 0;
  if (h.isInitiatorMessage) flags |= 0x01;
  if (h.ackedMessageId != null) flags |= 0x02;
  if (h.requiresAck) flags |= 0x04;
  buf.addByte(flags);
  buf.addByte(h.messageType);
  buf.addByte(h.exchangeId & 0xFF);
  buf.addByte((h.exchangeId >> 8) & 0xFF);
  // protocol ID (uint16 LE, no vendor)
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

/// 메시지 카운터 생성기
class MessageCounter {
  int _counter = Random.secure().nextInt(0xFFFFFF);
  int next() => ++_counter;
}
