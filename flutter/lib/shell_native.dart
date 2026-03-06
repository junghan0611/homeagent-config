import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// Flutter 네이티브 Shell — Linux Desktop 개발용
/// Go 서버 API를 직접 호출하여 Flutter 위젯으로 렌더링
///
/// WebView 없이 동작 → Linux desktop에서 hot reload 가능
/// A2UI 네이티브 렌더러의 씨앗
class ShellNative extends StatefulWidget {
  final String serverUrl;
  const ShellNative({super.key, required this.serverUrl});

  @override
  State<ShellNative> createState() => _ShellNativeState();
}

class _ShellNativeState extends State<ShellNative> {
  List<dynamic> _devices = [];
  Map<String, dynamic>? _home;
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _fetchAll();
    // SSE 대신 폴링 (개발용, 5초 간격)
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchDevices());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchAll() async {
    await Future.wait([_fetchDevices(), _fetchHome()]);
    setState(() => _loading = false);
  }

  Future<void> _fetchDevices() async {
    try {
      final data = await _get('/api/devices');
      if (data is List) {
        setState(() { _devices = data; _error = null; });
      }
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _fetchHome() async {
    try {
      final data = await _get('/api/home');
      if (data is Map<String, dynamic>) {
        setState(() => _home = data);
      }
    } catch (_) {}
  }

  Future<dynamic> _get(String path) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
    final request = await client.getUrl(Uri.parse('${widget.serverUrl}$path'));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    return jsonDecode(body);
  }

  Future<void> _sendCommand(int nodeId, String command) async {
    try {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('${widget.serverUrl}/api/devices/command'),
      );
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'node_id': nodeId, 'command': command}));
      final response = await request.close();
      await response.drain();
      await _fetchDevices();
    } catch (e) {
      debugPrint('[native] command error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // 헤더 — A2UI Home Surface 요약
        _buildHeader(),

        // 에러 배너
        if (_error != null)
          MaterialBanner(
            content: Text(_error!, style: const TextStyle(color: Colors.white70)),
            backgroundColor: Colors.red.shade900,
            actions: [
              TextButton(
                onPressed: _fetchAll,
                child: const Text('재시도'),
              ),
            ],
          ),

        // 디바이스 목록
        Expanded(
          child: _devices.isEmpty
              ? const Center(
                  child: Text('디바이스 없음', style: TextStyle(color: Colors.grey)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _devices.length,
                  itemBuilder: (context, index) => _buildDeviceCard(_devices[index]),
                ),
        ),

        // 서버 정보
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            'Go 서버: ${widget.serverUrl} • ${_devices.length} devices',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final greeting = _home?['greeting'] ?? 'HomeAgent';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blueGrey.shade900, Colors.blueGrey.shade800],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$greeting',
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            '${_devices.length}개 디바이스 연결됨',
            style: const TextStyle(color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceCard(dynamic device) {
    final nodeId = device['node_id'] ?? 0;
    final name = device['name'] ?? 'Node $nodeId';
    final room = device['room'] ?? '';
    final type = device['type'] ?? '';
    final available = device['available'] ?? false;
    final isOn = device['is_on'] ?? false;
    final isContact = type == 'contact_sensor';
    final contactOpen = device['contact_open'] ?? false;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: Colors.blueGrey.shade800,
      child: ListTile(
        leading: Icon(
          isContact ? Icons.sensor_door : Icons.power,
          color: available ? (isContact ? (contactOpen ? Colors.orange : Colors.green) : (isOn ? Colors.amber : Colors.grey)) : Colors.red,
          size: 32,
        ),
        title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        subtitle: Text(
          '$room • ${isContact ? (contactOpen ? "열림" : "닫힘") : (isOn ? "켜짐" : "꺼짐")}',
          style: const TextStyle(color: Colors.white60),
        ),
        trailing: isContact
            ? null
            : Switch(
                value: isOn,
                onChanged: available
                    ? (value) => _sendCommand(nodeId, value ? 'on' : 'off')
                    : null,
              ),
      ),
    );
  }
}
