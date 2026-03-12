import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/log_entry.dart';
import '../theme.dart';

class LogsTable extends StatelessWidget {
  final List<LogEntry> logs;
  final VoidCallback onRefresh;

  const LogsTable({super.key, required this.logs, required this.onRefresh});

  static Color _severityColor(String severity) {
    switch (severity) {
      case 'LOW':
        return AppTheme.green;
      case 'MEDIUM':
        return AppTheme.accent;
      case 'HIGH':
        return AppTheme.red;
      case 'CRITICAL':
        return const Color(0xFF8B0000);
      default:
        return AppTheme.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                const Icon(LucideIcons.list, size: 11, color: AppTheme.muted),
                const SizedBox(width: 6),
                const Text(
                  'DETECTION LOGS',
                  style: TextStyle(
                    fontSize: 9,
                    color: AppTheme.muted,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: onRefresh,
                  child: const Row(
                    children: [
                      Icon(
                        LucideIcons.refreshCw,
                        size: 9,
                        color: AppTheme.muted,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'REFRESH',
                        style: TextStyle(
                          fontSize: 9,
                          color: AppTheme.muted,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child:
                logs.isEmpty
                    ? const Center(
                      child: Text(
                        'NO LOCAL LOGS YET',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.muted,
                          letterSpacing: 3,
                        ),
                      ),
                    )
                    : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SingleChildScrollView(
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(
                            AppTheme.panelAlt,
                          ),
                          dataRowColor: WidgetStateProperty.resolveWith(
                            (states) => AppTheme.bg,
                          ),
                          headingTextStyle: const TextStyle(
                            fontSize: 9,
                            color: AppTheme.muted,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w700,
                          ),
                          dataTextStyle: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.text,
                          ),
                          columns: const [
                            DataColumn(label: Text('DATE')),
                            DataColumn(label: Text('SEV')),
                            DataColumn(label: Text('GPS (LAT, LNG)')),
                            DataColumn(label: Text('DEPTH')),
                            DataColumn(label: Text('VOL')),
                            DataColumn(label: Text('CONF')),
                          ],
                          rows:
                              logs.map((l) {
                                final date =
                                    DateTime.fromMillisecondsSinceEpoch(
                                      (l.timestamp * 1000).toInt(),
                                    );
                                final dateStr =
                                    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                                final gpsStr =
                                    l.lat != null && l.lng != null
                                        ? '${l.lat!.toStringAsFixed(4)}, ${l.lng!.toStringAsFixed(4)}'
                                        : '--';

                                return DataRow(
                                  cells: [
                                    DataCell(Text(dateStr)),
                                    DataCell(
                                      Text(
                                        l.severity,
                                        style: TextStyle(
                                          color: _severityColor(l.severity),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                    DataCell(Text(gpsStr)),
                                    DataCell(Text('${l.depthM} m')),
                                    DataCell(Text('${l.volumeLiters} L')),
                                    DataCell(
                                      Text(
                                        '${(l.confidence * 100).toStringAsFixed(0)}%',
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                        ),
                      ),
                    ),
          ),
        ],
      ),
    );
  }
}
