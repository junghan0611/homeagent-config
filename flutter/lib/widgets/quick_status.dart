import 'package:flutter/material.dart';

import '../api_client.dart';
import '../theme.dart';

/// 상단 상태 요약 바 — 켜진기기 / 전체 / 오프라인
class QuickStatus extends StatelessWidget {
  final List<Device> devices;

  const QuickStatus({super.key, required this.devices});

  @override
  Widget build(BuildContext context) {
    final onCount = devices.where((d) => d.available && d.isOn).length;
    final total = devices.length;
    final offline = devices.where((d) => !d.available).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _StatusChip(
            label: '켜짐',
            count: onCount,
            color: AppTheme.onColor,
          ),
          const SizedBox(width: 12),
          _StatusChip(
            label: '전체',
            count: total,
            color: AppTheme.blue,
          ),
          const SizedBox(width: 12),
          _StatusChip(
            label: '오프라인',
            count: offline,
            color: offline > 0 ? AppTheme.errorColor : AppTheme.offColor,
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _StatusChip({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withAlpha(25),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color.withAlpha(179),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
