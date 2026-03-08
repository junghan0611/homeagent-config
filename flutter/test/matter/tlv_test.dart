import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeagent/matter/tlv.dart';

void main() {
  group('TLV Encoder', () {
    test('encode structure with bytes field', () {
      final enc = TlvEncoder();
      enc.startStructure();
      enc.writeBytes(1, Uint8List.fromList([0xAA, 0xBB, 0xCC]));
      enc.endContainer();
      final bytes = enc.toBytes();

      // structure open
      expect(bytes[0], TlvType.structure); // 0x15
      // context-specific byte string: 0x30 = 0x20 | 0x10
      expect(bytes[1], 0x30);
      // tag = 1
      expect(bytes[2], 1);
      // length = 3
      expect(bytes[3], 3);
      // data
      expect(bytes[4], 0xAA);
      expect(bytes[5], 0xBB);
      expect(bytes[6], 0xCC);
      // end of container
      expect(bytes[7], TlvType.endOfContainer); // 0x18
    });

    test('encode uint16', () {
      final enc = TlvEncoder();
      enc.startStructure();
      enc.writeUInt16(2, 0x1234);
      enc.endContainer();
      final bytes = enc.toBytes();

      // 0x25 = context-specific(0x20) | unsignedInt(0x04) | 2-byte(0x01)
      expect(bytes[1], 0x25);
      expect(bytes[2], 2); // tag
      expect(bytes[3], 0x34); // LE low
      expect(bytes[4], 0x12); // LE high
    });

    test('encode bool', () {
      final enc = TlvEncoder();
      enc.startStructure();
      enc.writeBool(4, false);
      enc.writeBool(5, true);
      enc.endContainer();
      final bytes = enc.toBytes();

      // false: 0x28 = context-specific(0x20) | boolean(0x08) | 0x00
      expect(bytes[1], 0x28);
      expect(bytes[2], 4);
      // true: 0x29 = context-specific(0x20) | boolean(0x08) | 0x01
      expect(bytes[3], 0x29);
      expect(bytes[4], 5);
    });

    test('encode uint32', () {
      final enc = TlvEncoder();
      enc.startStructure();
      enc.writeUInt32(1, 1000);
      enc.endContainer();
      final bytes = enc.toBytes();

      // 0x26 = context-specific(0x20) | unsignedInt(0x04) | 4-byte(0x02)
      expect(bytes[1], 0x26);
      expect(bytes[2], 1);
      // 1000 = 0x000003E8
      expect(bytes[3], 0xE8);
      expect(bytes[4], 0x03);
      expect(bytes[5], 0x00);
      expect(bytes[6], 0x00);
    });
  });

  group('TLV Decoder', () {
    test('decode structure with bytes and uint16', () {
      // Hand-crafted TLV: {1: bytes([0xAA]), 2: uint16(42)}
      final data = Uint8List.fromList([
        0x15, // structure
        0x30, 1, 1, 0xAA, // context byte string, tag=1, len=1, data=0xAA
        0x25, 2, 42, 0, // context uint16, tag=2, value=42
        0x18, // end
      ]);

      final fields = TlvDecoder(data).decodeStructure();
      expect(fields[1]!.bytesValue, Uint8List.fromList([0xAA]));
      expect(fields[2]!.intValue, 42);
    });

    test('decode bool fields', () {
      final data = Uint8List.fromList([
        0x15, // structure
        0x28, 4, // false, tag=4
        0x29, 5, // true, tag=5
        0x18, // end
      ]);

      final fields = TlvDecoder(data).decodeStructure();
      expect(fields[4]!.boolValue, false);
      expect(fields[5]!.boolValue, true);
    });

    test('decode nested structure (pbkdfParameters)', () {
      // Simulates PbkdfParamResponse.pbkdfParameters = {1: uint32(1000), 2: bytes(salt)}
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final data = Uint8List.fromList([
        0x15, // outer structure
        0x35, 4, // context-specific structure, tag=4
          0x26, 1, 0xE8, 0x03, 0x00, 0x00, // uint32 tag=1, value=1000
          0x30, 2, 16, ...salt, // byte string tag=2, len=16
        0x18, // end inner
        0x18, // end outer
      ]);

      final fields = TlvDecoder(data).decodeStructure();
      final nested = fields[4]!.structValue!;
      expect(nested[1]!.intValue, 1000);
      expect(nested[2]!.bytesValue, salt);
    });

    test('encode-decode roundtrip', () {
      final enc = TlvEncoder();
      enc.startStructure();
      enc.writeBytes(1, Uint8List.fromList([1, 2, 3, 4, 5]));
      enc.writeUInt16(2, 1234);
      enc.writeBool(4, false);
      enc.endContainer();

      final decoded = TlvDecoder(enc.toBytes()).decodeStructure();
      expect(decoded[1]!.bytesValue, Uint8List.fromList([1, 2, 3, 4, 5]));
      expect(decoded[2]!.intValue, 1234);
      expect(decoded[4]!.boolValue, false);
    });
  });
}
