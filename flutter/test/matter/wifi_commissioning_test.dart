import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:homeagent/matter/wifi_commissioning.dart';
import 'package:homeagent/matter/btp_session.dart';
import 'package:homeagent/matter/secure_session.dart';
import 'package:homeagent/matter/tlv.dart';

void main() {
  group('WifiCommissioner InvokeRequest TLV', () {
    test('encodeInvokeRequest produces valid TLV structure', () {
      final ke = Uint8List.fromList(List.generate(32, (i) => i));
      final session =
          SecureSession.fromKe(ke, sessionId: 1, peerSessionId: 2);
      final btp = BtpSession(
        writeToDevice: (_) async {},
        disconnect: () async {},
      );
      final comm = WifiCommissioner(
        btp: btp,
        session: session,
        exchangeId: 100,
      );

      // AddOrUpdateWiFiNetwork fields
      final fields = TlvEncoder();
      fields.writeBytes(0, Uint8List.fromList('TestSSID'.codeUnits));
      fields.writeBytes(1, Uint8List.fromList('password123'.codeUnits));

      final encoded = comm.encodeInvokeRequest(
        endpointId: 0,
        clusterId: 0x0031,
        commandId: 0x02,
        commandFields: fields.toBytes(),
      );

      // TLV 구조 검증:
      // [0x15] anonymous structure (InvokeRequest)
      //   [0x28/0x29] bool tag 0 (suppressResponse)
      //   [0x28/0x29] bool tag 1 (timedRequest)
      //   [0x36, 0x02] context array tag 2 (invokeRequests)
      //     [0x15] anonymous structure (CommandDataIB)
      //       [0x37, 0x00] context list tag 0 (CommandPathIB)
      //         ... endpoint, cluster, command
      //       [0x18] end list
      //       [0x35, 0x01] context structure tag 1 (commandFields)
      //         ... fields
      //       [0x18] end structure
      //     [0x18] end CommandDataIB
      //   [0x18] end array
      //   [0x24, 0xFF, 0x0B] uint8 tag 255 = 11 (interactionModelRevision)
      // [0x18] end InvokeRequest

      expect(encoded[0], 0x15); // structure open
      expect(encoded.last, 0x18); // structure close

      // interactionModelRevision은 끝에서 4바이트 앞
      // ..., 0x24, 0xFF, 0x0B, 0x18
      final len = encoded.length;
      expect(encoded[len - 4], 0x24); // context-specific uint8
      expect(encoded[len - 3], 0xFF); // tag 255
      expect(encoded[len - 2], 11); // revision 11
    });

    test('encodeInvokeRequest contains cluster ID and command ID', () {
      final ke = Uint8List.fromList(List.generate(32, (i) => i));
      final session =
          SecureSession.fromKe(ke, sessionId: 1, peerSessionId: 2);
      final btp = BtpSession(
        writeToDevice: (_) async {},
        disconnect: () async {},
      );
      final comm = WifiCommissioner(
        btp: btp,
        session: session,
        exchangeId: 1,
      );

      final encoded = comm.encodeInvokeRequest(
        endpointId: 0,
        clusterId: 0x0031,
        commandId: 0x04,
        commandFields: Uint8List(0),
      );

      // 바이트 스트림에서 cluster ID 0x0031 찾기 (LE uint32)
      final bytes = encoded;
      bool foundCluster = false;
      for (int i = 0; i < bytes.length - 3; i++) {
        if (bytes[i] == 0x31 && bytes[i + 1] == 0x00 &&
            bytes[i + 2] == 0x00 && bytes[i + 3] == 0x00) {
          foundCluster = true;
          break;
        }
      }
      expect(foundCluster, isTrue, reason: 'cluster 0x0031 should be in TLV');

      // command ID 0x04 찾기 (LE uint32)
      bool foundCommand = false;
      for (int i = 0; i < bytes.length - 3; i++) {
        if (bytes[i] == 0x04 && bytes[i + 1] == 0x00 &&
            bytes[i + 2] == 0x00 && bytes[i + 3] == 0x00) {
          foundCommand = true;
          break;
        }
      }
      expect(foundCommand, isTrue, reason: 'command 0x04 should be in TLV');
    });

    test('WiFi SSID and password encoded as byte strings', () {
      final ke = Uint8List.fromList(List.generate(32, (i) => i));
      final session =
          SecureSession.fromKe(ke, sessionId: 1, peerSessionId: 2);
      final btp = BtpSession(
        writeToDevice: (_) async {},
        disconnect: () async {},
      );
      final comm = WifiCommissioner(
        btp: btp,
        session: session,
        exchangeId: 1,
      );

      const ssid = 'MyWiFi';
      const pw = 'secret123';

      final fields = TlvEncoder();
      fields.writeBytes(0, Uint8List.fromList(ssid.codeUnits));
      fields.writeBytes(1, Uint8List.fromList(pw.codeUnits));

      final encoded = comm.encodeInvokeRequest(
        endpointId: 0,
        clusterId: 0x0031,
        commandId: 0x02,
        commandFields: fields.toBytes(),
      );

      // SSID bytes should appear in the encoded TLV
      final ssidBytes = ssid.codeUnits;
      bool foundSsid = false;
      for (int i = 0; i < encoded.length - ssidBytes.length; i++) {
        bool match = true;
        for (int j = 0; j < ssidBytes.length; j++) {
          if (encoded[i + j] != ssidBytes[j]) {
            match = false;
            break;
          }
        }
        if (match) {
          foundSsid = true;
          break;
        }
      }
      expect(foundSsid, isTrue, reason: 'SSID should appear in TLV payload');
    });
  });

  group('TlvEncoder new methods', () {
    test('writeUInt8 encodes correctly', () {
      final enc = TlvEncoder();
      enc.writeUInt8(5, 42);
      final bytes = enc.toBytes();
      expect(bytes, [0x24, 5, 42]);
    });

    test('startContextStructure/Array/List', () {
      final enc = TlvEncoder();
      enc.startContextStructure(3);
      enc.endContainer();
      final bytes = enc.toBytes();
      expect(bytes, [0x35, 3, 0x18]);
    });

    test('startAnonymousStructure', () {
      final enc = TlvEncoder();
      enc.startAnonymousStructure();
      enc.endContainer();
      final bytes = enc.toBytes();
      expect(bytes, [0x15, 0x18]);
    });
  });
}
