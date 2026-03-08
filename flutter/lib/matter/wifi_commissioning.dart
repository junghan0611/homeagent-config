/// WiFi 커미셔닝 — 암호화 세션 위에서 NetworkCommissioning 명령 전송
/// PASE 성공 후 Ke로 SecureSession 생성 → WiFi credentials 전달
library;

import 'dart:convert' show utf8;
import 'dart:typed_data';

import 'btp_session.dart';
import 'secure_session.dart';
import 'tlv.dart';

/// NetworkCommissioning cluster
const int _networkCommCluster = 0x0031;

/// Command IDs
const int _addOrUpdateWiFiNetwork = 0x02;
const int _connectNetwork = 0x04;

/// Interaction Model protocol
const int _imProtocolId = 0x0001;
const int _invokeRequestType = 8;
const int _invokeResponseType = 9;

/// WiFi credentials 전달 (암호화 세션 사용)
class WifiCommissioner {
  final BtpSession btp;
  final SecureSession session;
  int _exchangeId;

  WifiCommissioner({
    required this.btp,
    required this.session,
    required int exchangeId,
  }) : _exchangeId = exchangeId;

  /// WiFi SSID + Password 전달 → 디바이스 WiFi 연결
  /// endpoint=0 (root endpoint의 NetworkCommissioning cluster)
  Future<bool> sendWifiCredentials(String ssid, String password) async {
    // 1. AddOrUpdateWiFiNetwork
    final addResult = await _invokeCommand(
      endpointId: 0,
      clusterId: _networkCommCluster,
      commandId: _addOrUpdateWiFiNetwork,
      commandFields: _encodeAddWiFiFields(ssid, password),
    );
    if (!addResult) return false;

    // 2. ConnectNetwork
    final connectResult = await _invokeCommand(
      endpointId: 0,
      clusterId: _networkCommCluster,
      commandId: _connectNetwork,
      commandFields: _encodeConnectFields(ssid),
    );
    return connectResult;
  }

  /// InvokeRequest TLV 인코딩
  Uint8List encodeInvokeRequest({
    required int endpointId,
    required int clusterId,
    required int commandId,
    required Uint8List commandFields,
  }) {
    final tlv = TlvEncoder();
    tlv.startStructure();
    tlv.writeBool(0, false); // suppressResponse
    tlv.writeBool(1, false); // timedRequest

    // invokeRequests: array (tag 2)
    tlv.startContextArray(2);

    // CommandDataIB (anonymous structure in array)
    tlv.startAnonymousStructure();

    // CommandPathIB (tag 0, list)
    tlv.startContextList(0);
    tlv.writeUInt16(0, endpointId);
    tlv.writeUInt32(1, clusterId);
    tlv.writeUInt32(2, commandId);
    tlv.endContainer(); // end list

    // commandFields (tag 1, structure)
    tlv.startContextStructure(1);
    tlv.writeRawBytes(commandFields);
    tlv.endContainer(); // end commandFields structure

    tlv.endContainer(); // end CommandDataIB
    tlv.endContainer(); // end array

    // interactionModelRevision (tag 255, uint8)
    tlv.writeUInt8(255, 11);

    tlv.endContainer(); // end InvokeRequest
    return tlv.toBytes();
  }

  /// InvokeRequest 전송 + InvokeResponse 수신
  Future<bool> _invokeCommand({
    required int endpointId,
    required int clusterId,
    required int commandId,
    required Uint8List commandFields,
  }) async {
    _exchangeId = (_exchangeId + 1) & 0xFFFF;

    final invokeReqPayload = encodeInvokeRequest(
      endpointId: endpointId,
      clusterId: clusterId,
      commandId: commandId,
      commandFields: commandFields,
    );

    // 암호화
    final encrypted = session.encryptMessage(
      exchangeId: _exchangeId,
      messageType: _invokeRequestType,
      payload: invokeReqPayload,
      protocolId: _imProtocolId,
    );

    // BTP 전송
    await btp.sendMessage(encrypted);

    // 응답 대기
    final responseBytes = await btp.waitForMessage(
      timeout: const Duration(seconds: 30),
    );

    // 복호화
    final response = session.decryptMessage(responseBytes);

    // InvokeResponse 확인
    if (response.payloadHeader.messageType == _invokeResponseType) {
      // TODO: InvokeResponse TLV에서 status 코드 파싱
      return true;
    }

    return false;
  }

  /// AddOrUpdateWiFiNetwork 필드: {0: ssid(bytes), 1: credentials(bytes)}
  Uint8List _encodeAddWiFiFields(String ssid, String password) {
    final enc = TlvEncoder();
    enc.writeBytes(0, Uint8List.fromList(utf8.encode(ssid)));
    enc.writeBytes(1, Uint8List.fromList(utf8.encode(password)));
    return enc.toBytes();
  }

  /// ConnectNetwork 필드: {0: networkId(bytes=ssid)}
  Uint8List _encodeConnectFields(String ssid) {
    final enc = TlvEncoder();
    enc.writeBytes(0, Uint8List.fromList(utf8.encode(ssid)));
    return enc.toBytes();
  }
}
