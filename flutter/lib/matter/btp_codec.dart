/// BTP (Bluetooth Transport Protocol) 코덱
/// matter.js BtpCodec.js 포팅
library;

import 'dart:typed_data';

const int _handshakeHeader = 0x65;
const int _managementOpcode = 0x6C;

/// BTP 헤더 플래그 비트
class BtpHeaderBits {
  static const int handshake = 64;
  static const int management = 32;
  static const int ack = 8;
  static const int end = 4;
  static const int continuing = 2;
  static const int begin = 1;
}

/// BTP 핸드셰이크 요청 인코딩 (controller → device, C1에 write)
Uint8List encodeBtpHandshakeRequest({
  int attMtu = 247,
  int clientWindowSize = 6,
}) {
  // BTP version 4만 지원
  final buf = BytesBuilder();
  buf.addByte(_handshakeHeader);
  buf.addByte(_managementOpcode);
  // versions: nibble-packed, [4,0,0,0,0,0,0,0]
  buf.addByte(0x04); // ver[1]<<4 | ver[0] → 0<<4 | 4 = 0x04
  buf.addByte(0x00);
  buf.addByte(0x00);
  buf.addByte(0x00);
  // ATT MTU (uint16 LE)
  buf.addByte(attMtu & 0xFF);
  buf.addByte((attMtu >> 8) & 0xFF);
  // window size
  buf.addByte(clientWindowSize);
  return buf.toBytes();
}

/// BTP 핸드셰이크 응답 디코딩 (device → controller, C2에서 indicate)
({int version, int attMtu, int windowSize}) decodeBtpHandshakeResponse(
    Uint8List data) {
  if (data.length < 6) throw FormatException('BTP response too short: ${data.length}');
  if (data[0] != _handshakeHeader) {
    throw FormatException('Invalid BTP handshake header: 0x${data[0].toRadixString(16)}');
  }
  if (data[1] != _managementOpcode) {
    throw FormatException('Invalid BTP management opcode: 0x${data[1].toRadixString(16)}');
  }
  final version = data[2] & 0x0F;
  final attMtu = data[3] | (data[4] << 8);
  final windowSize = data[5];
  return (version: version, attMtu: attMtu, windowSize: windowSize);
}

/// BTP 데이터 패킷 헤더
class BtpPacketHeader {
  final bool hasAck;
  final bool isBegin;
  final bool isContinuing;
  final bool isEnd;

  const BtpPacketHeader({
    this.hasAck = false,
    this.isBegin = false,
    this.isContinuing = false,
    this.isEnd = false,
  });
}

/// BTP 데이터 패킷
class BtpPacket {
  final BtpPacketHeader header;
  final int? ackNumber;
  final int sequenceNumber;
  final int? messageLength;
  final Uint8List segmentPayload;

  BtpPacket({
    required this.header,
    this.ackNumber,
    required this.sequenceNumber,
    this.messageLength,
    required this.segmentPayload,
  });
}

/// BTP 데이터 패킷 인코딩
Uint8List encodeBtpPacket(BtpPacket pkt) {
  final buf = BytesBuilder();

  // Header flags byte
  int flags = 0;
  if (pkt.header.hasAck) flags |= BtpHeaderBits.ack;
  if (pkt.header.isEnd) flags |= BtpHeaderBits.end;
  if (pkt.header.isContinuing) flags |= BtpHeaderBits.continuing;
  if (pkt.header.isBegin) flags |= BtpHeaderBits.begin;
  buf.addByte(flags);

  // Ack number
  if (pkt.header.hasAck) {
    buf.addByte(pkt.ackNumber ?? 0);
  }

  // Sequence number
  buf.addByte(pkt.sequenceNumber);

  // Message length (only on beginning segment)
  if (pkt.header.isBegin && pkt.messageLength != null) {
    buf.addByte(pkt.messageLength! & 0xFF);
    buf.addByte((pkt.messageLength! >> 8) & 0xFF);
  }

  // Segment payload
  buf.add(pkt.segmentPayload);
  return buf.toBytes();
}

/// BTP 데이터 패킷 디코딩
BtpPacket decodeBtpPacket(Uint8List data) {
  int pos = 0;
  final flags = data[pos++];

  final header = BtpPacketHeader(
    hasAck: (flags & BtpHeaderBits.ack) != 0,
    isBegin: (flags & BtpHeaderBits.begin) != 0,
    isContinuing: (flags & BtpHeaderBits.continuing) != 0,
    isEnd: (flags & BtpHeaderBits.end) != 0,
  );

  int? ackNumber;
  if (header.hasAck) {
    ackNumber = data[pos++];
  }

  final sequenceNumber = data[pos++];

  int? messageLength;
  if (header.isBegin) {
    messageLength = data[pos] | (data[pos + 1] << 8);
    pos += 2;
  }

  final segmentPayload = Uint8List.sublistView(data, pos);

  return BtpPacket(
    header: header,
    ackNumber: ackNumber,
    sequenceNumber: sequenceNumber,
    messageLength: messageLength,
    segmentPayload: segmentPayload,
  );
}
