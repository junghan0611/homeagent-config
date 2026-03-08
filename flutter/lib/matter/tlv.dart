/// Matter TLV (Tag-Length-Value) 최소 구현
/// PASE 메시지용 context-specific 태그만 지원
library;

import 'dart:typed_data';

/// TLV 타입 (control byte의 하위 5비트)
class TlvType {
  static const int signedInt = 0x00; // 1-byte signed int
  static const int unsignedInt = 0x04; // 1-byte unsigned int
  static const int boolean = 0x08;
  static const int utf8String = 0x0C;
  static const int byteString = 0x10;
  static const int null_ = 0x14;
  static const int structure = 0x15;
  static const int array = 0x16;
  static const int endOfContainer = 0x18;
}

/// TLV 태그 형식 (control byte의 상위 3비트 중 2비트)
class TlvTagControl {
  static const int anonymous = 0x00;
  static const int contextSpecific = 0x20;
}

/// TLV 인코더 — PASE 메시지 전용
class TlvEncoder {
  final BytesBuilder buf = BytesBuilder();

  void startStructure() {
    buf.addByte(TlvType.structure); // anonymous structure
  }

  void endContainer() {
    buf.addByte(TlvType.endOfContainer);
  }

  void writeBytes(int tag, Uint8List value) {
    // context-specific tag + byte string
    final len = value.length;
    if (len <= 0xFF) {
      buf.addByte(TlvTagControl.contextSpecific | TlvType.byteString); // 0x30
      buf.addByte(tag);
      buf.addByte(len);
    } else if (len <= 0xFFFF) {
      buf.addByte(TlvTagControl.contextSpecific | TlvType.byteString | 0x01); // 0x31
      buf.addByte(tag);
      buf.addByte(len & 0xFF);
      buf.addByte((len >> 8) & 0xFF);
    } else {
      throw ArgumentError('byte string too long: $len');
    }
    buf.add(value);
  }

  void writeUInt16(int tag, int value) {
    buf.addByte(TlvTagControl.contextSpecific | TlvType.unsignedInt | 0x01); // 0x25
    buf.addByte(tag);
    buf.addByte(value & 0xFF);
    buf.addByte((value >> 8) & 0xFF);
  }

  void writeUInt32(int tag, int value) {
    buf.addByte(TlvTagControl.contextSpecific | TlvType.unsignedInt | 0x02); // 0x26
    buf.addByte(tag);
    buf.addByte(value & 0xFF);
    buf.addByte((value >> 8) & 0xFF);
    buf.addByte((value >> 16) & 0xFF);
    buf.addByte((value >> 24) & 0xFF);
  }

  void writeBool(int tag, bool value) {
    // true = 0x09, false = 0x08
    buf.addByte(TlvTagControl.contextSpecific | TlvType.boolean | (value ? 0x01 : 0x00));
    buf.addByte(tag);
  }

  /// Raw byte 직접 추가 (InvokeRequest 등 복합 구조용)
  void writeRawByte(int byte) => buf.addByte(byte);
  void writeRawBytes(Uint8List bytes) => buf.add(bytes);

  /// context-specific structure 시작 (tag 포함)
  void startContextStructure(int tag) {
    buf.addByte(0x35); // context-specific structure
    buf.addByte(tag);
  }

  /// context-specific array 시작 (tag 포함)
  void startContextArray(int tag) {
    buf.addByte(0x36); // context-specific array
    buf.addByte(tag);
  }

  /// context-specific list 시작 (tag 포함)
  void startContextList(int tag) {
    buf.addByte(0x37); // context-specific list
    buf.addByte(tag);
  }

  /// anonymous structure 시작 (배열 내 아이템용)
  void startAnonymousStructure() {
    buf.addByte(0x15); // anonymous structure
  }

  /// context-specific uint8 (tag 포함)
  void writeUInt8(int tag, int value) {
    buf.addByte(TlvTagControl.contextSpecific | TlvType.unsignedInt); // 0x24
    buf.addByte(tag);
    buf.addByte(value & 0xFF);
  }

  Uint8List toBytes() => buf.toBytes();
}

/// TLV 디코더 — 최소한 필요한 필드만 파싱
class TlvDecoder {
  final Uint8List data;
  int _pos = 0;

  TlvDecoder(this.data);

  /// 구조체의 context-specific 필드를 Map으로 추출
  /// key: tag number, value: TlvField
  Map<int, TlvField> decodeStructure() {
    final fields = <int, TlvField>{};

    // Skip structure open tag
    if (_pos < data.length && (data[_pos] & 0x1F) == TlvType.structure) {
      _pos++;
    }

    while (_pos < data.length) {
      final control = data[_pos];
      final type = control & 0x1F;
      final tagForm = control & 0xE0;

      if (type == TlvType.endOfContainer) {
        _pos++;
        break;
      }

      _pos++; // consume control byte

      // Read tag
      int? tag;
      if (tagForm == TlvTagControl.contextSpecific) {
        tag = data[_pos++];
      }

      // Read value based on type
      switch (type) {
        case TlvType.unsignedInt:
        case TlvType.unsignedInt | 0x01: // 2-byte
        case TlvType.unsignedInt | 0x02: // 4-byte
        case TlvType.unsignedInt | 0x03: // 8-byte
          final size = 1 << (control & 0x03);
          int value = 0;
          for (int i = 0; i < size; i++) {
            value |= data[_pos++] << (i * 8);
          }
          if (tag != null) fields[tag] = TlvField.integer(value);
          break;

        case TlvType.byteString:
        case TlvType.byteString | 0x01: // 2-byte length
        case TlvType.byteString | 0x02: // 4-byte length
          final lenSize = 1 << (control & 0x03);
          int len = 0;
          for (int i = 0; i < lenSize; i++) {
            len |= data[_pos++] << (i * 8);
          }
          final bytes = Uint8List.sublistView(data, _pos, _pos + len);
          _pos += len;
          if (tag != null) fields[tag] = TlvField.bytes(bytes);
          break;

        case TlvType.boolean:
        case TlvType.boolean | 0x01:
          if (tag != null) fields[tag] = TlvField.boolean((control & 0x01) == 1);
          break;

        case TlvType.structure:
          // 중첩 구조체 — 재귀 파싱
          final nested = _decodeNestedStructure();
          if (tag != null) fields[tag] = TlvField.structure(nested);
          break;

        case TlvType.null_:
          break;

        default:
          // 알 수 없는 타입은 skip 시도
          _skipUnknown(control);
      }
    }

    return fields;
  }

  Map<int, TlvField> _decodeNestedStructure() {
    final nested = <int, TlvField>{};
    while (_pos < data.length) {
      final control = data[_pos];
      final type = control & 0x1F;
      if (type == TlvType.endOfContainer) {
        _pos++;
        break;
      }
      _pos++;
      int? tag;
      if ((control & 0xE0) == TlvTagControl.contextSpecific) {
        tag = data[_pos++];
      }
      switch (type) {
        case TlvType.unsignedInt:
        case TlvType.unsignedInt | 0x01:
        case TlvType.unsignedInt | 0x02:
        case TlvType.unsignedInt | 0x03:
          final size = 1 << (control & 0x03);
          int value = 0;
          for (int i = 0; i < size; i++) {
            value |= data[_pos++] << (i * 8);
          }
          if (tag != null) nested[tag] = TlvField.integer(value);
          break;
        case TlvType.byteString:
        case TlvType.byteString | 0x01:
        case TlvType.byteString | 0x02:
          final lenSize = 1 << (control & 0x03);
          int len = 0;
          for (int i = 0; i < lenSize; i++) {
            len |= data[_pos++] << (i * 8);
          }
          final bytes = Uint8List.sublistView(data, _pos, _pos + len);
          _pos += len;
          if (tag != null) nested[tag] = TlvField.bytes(bytes);
          break;
        case TlvType.boolean:
        case TlvType.boolean | 0x01:
          if (tag != null) nested[tag] = TlvField.boolean((control & 0x01) == 1);
          break;
        default:
          _skipUnknown(control);
      }
    }
    return nested;
  }

  void _skipUnknown(int control) {
    // 최소한의 skip — 알 수 없는 타입은 에러
    throw FormatException('Unknown TLV type: 0x${control.toRadixString(16)} at pos $_pos');
  }
}

/// TLV 필드 값
class TlvField {
  final int? intValue;
  final Uint8List? bytesValue;
  final bool? boolValue;
  final Map<int, TlvField>? structValue;

  TlvField._({this.intValue, this.bytesValue, this.boolValue, this.structValue});

  factory TlvField.integer(int v) => TlvField._(intValue: v);
  factory TlvField.bytes(Uint8List v) => TlvField._(bytesValue: v);
  factory TlvField.boolean(bool v) => TlvField._(boolValue: v);
  factory TlvField.structure(Map<int, TlvField> v) => TlvField._(structValue: v);
}
