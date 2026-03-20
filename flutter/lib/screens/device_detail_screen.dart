import 'package:flutter/material.dart';

import '../api_client.dart';

/// 디바이스 상세 화면 — 속성 + 진단 + 액션
///
/// HA Frontend의 ha-device-info-matter.ts 참고:
/// - 기본 정보 (node_id, type, available)
/// - 연결 상태 (ping)
/// - 진단 정보 (diagnostics — network_type, ip, mac 등)
/// - 액션 (ping, interview, delete)
class DeviceDetailScreen extends StatefulWidget {
  final String serverUrl;
  final Device device;

  const DeviceDetailScreen({
    super.key,
    required this.serverUrl,
    required this.device,
  });

  @override
  State<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends State<DeviceDetailScreen> {
  late final ApiClient _api;
  Map<String, dynamic>? _diagnostics;
  Map<String, dynamic>? _pingResult;
  bool _loadingDiag = false;
  bool _loadingPing = false;
  bool _loadingInterview = false;

  @override
  void initState() {
    super.initState();
    _api = ApiClient(baseUrl: widget.serverUrl);
    _loadDiagnostics();
  }

  Future<void> _loadDiagnostics() async {
    setState(() => _loadingDiag = true);
    try {
      final diag = await _api.deviceDiagnostics(widget.device.nodeId);
      if (mounted) setState(() => _diagnostics = diag);
    } catch (e) {
      debugPrint('[DeviceDetail] diagnostics error: $e');
    }
    if (mounted) setState(() => _loadingDiag = false);
  }

  Future<void> _ping() async {
    setState(() {
      _loadingPing = true;
      _pingResult = null;
    });
    try {
      final result = await _api.pingDevice(widget.device.nodeId);
      if (mounted) setState(() => _pingResult = result);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('핑 실패: $e')),
        );
      }
    }
    if (mounted) setState(() => _loadingPing = false);
  }

  Future<void> _interview() async {
    setState(() => _loadingInterview = true);
    try {
      await _api.interviewDevice(widget.device.nodeId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('재인터뷰 완료')),
        );
        _loadDiagnostics(); // 진단 정보 갱신
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('재인터뷰 실패: $e')),
        );
      }
    }
    if (mounted) setState(() => _loadingInterview = false);
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('디바이스 삭제'),
        content: Text('${widget.device.name}을(를) 삭제하시겠습니까?\n삭제 후 복구할 수 없습니다.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _api.deleteDevice(widget.device.nodeId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('디바이스 삭제됨')),
        );
        Navigator.pop(context, true); // true = 삭제됨
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(d.name),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'delete') _delete();
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'delete', child: Text('삭제')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadDiagnostics,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ─── 기본 정보 ───
            _SectionCard(
              title: '기본 정보',
              children: [
                _InfoRow('Node ID', '${d.nodeId}'),
                _InfoRow('타입', d.type.isNotEmpty ? d.type : '알 수 없음'),
                _InfoRow('방', d.room.isNotEmpty ? d.room : '미설정'),
                _InfoRow(
                  '상태',
                  d.available ? '온라인' : '오프라인',
                  valueColor: d.available ? Colors.green : Colors.red,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // ─── 현재 상태 ───
            if (d.state.isNotEmpty)
              _SectionCard(
                title: '속성',
                children: d.state.entries
                    .map((e) => _InfoRow(e.key, '${e.value}'))
                    .toList(),
              ),

            const SizedBox(height: 12),

            // ─── 연결 상태 (ping) ───
            _SectionCard(
              title: '연결 상태',
              children: [
                if (_pingResult != null)
                  ..._pingResult!.entries.map((e) => _InfoRow(
                        'Endpoint ${e.key}',
                        e.value == true ? '응답' : '무응답',
                        valueColor: e.value == true ? Colors.green : Colors.red,
                      )),
                if (_pingResult == null && !_loadingPing)
                  const Text('핑을 눌러 연결 상태를 확인하세요.',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
                if (_loadingPing) const LinearProgressIndicator(),
              ],
            ),

            const SizedBox(height: 12),

            // ─── 진단 정보 ───
            _SectionCard(
              title: '진단 정보',
              children: [
                if (_loadingDiag) const LinearProgressIndicator(),
                if (_diagnostics != null) ...[
                  if (_diagnostics!['network_type'] != null)
                    _InfoRow('네트워크', '${_diagnostics!['network_type']}'),
                  if (_diagnostics!['node_type'] != null)
                    _InfoRow('노드 타입', '${_diagnostics!['node_type']}'),
                  if (_diagnostics!['network_name'] != null)
                    _InfoRow('네트워크 이름', '${_diagnostics!['network_name']}'),
                  if (_diagnostics!['mac_address'] != null)
                    _InfoRow('MAC', '${_diagnostics!['mac_address']}'),
                  if (_diagnostics!['ip_adresses'] != null)
                    _InfoRow('IP', (_diagnostics!['ip_adresses'] as List).join('\n')),
                ],
                if (!_loadingDiag && _diagnostics == null)
                  const Text('진단 정보를 불러올 수 없습니다.',
                      style: TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),

            const SizedBox(height: 24),

            // ─── 액션 버튼 ───
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: _loadingPing
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.network_ping),
                    label: const Text('핑'),
                    onPressed: _loadingPing ? null : _ping,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: _loadingInterview
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh),
                    label: const Text('재인터뷰'),
                    onPressed: _loadingInterview ? null : _interview,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 8),

            OutlinedButton.icon(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: const Text('디바이스 삭제', style: TextStyle(color: Colors.red)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.red)),
              onPressed: _delete,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 내부 위젯 ───

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                )),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _InfoRow(this.label, this.value, {this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(
              color: Colors.grey, fontSize: 13,
            )),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}
