import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/log_entry.dart';
import '../theme.dart';

class LogsScreen extends StatelessWidget {
  final List<LogEntry> logs;
  final bool loading;
  final VoidCallback onRefresh;
  final Function(double lat, double lng) onShowOnMap;

  const LogsScreen({
    super.key,
    required this.logs,
    required this.loading,
    required this.onRefresh,
    required this.onShowOnMap,
  });

  @override
  Widget build(BuildContext context) {
    if (loading && logs.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppTheme.accent,
              ),
            ),
            SizedBox(height: 16),
            Text(
              'LOADING LOGS...',
              style: TextStyle(
                fontSize: 10,
                color: AppTheme.muted,
                letterSpacing: 3,
              ),
            ),
          ],
        ),
      );
    }

    if (logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              LucideIcons.inbox,
              size: 48,
              color: AppTheme.muted.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            const Text(
              'NO DETECTION LOGS',
              style: TextStyle(
                fontSize: 11,
                color: AppTheme.muted,
                letterSpacing: 3,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Scan a pothole to see results here',
              style: TextStyle(fontSize: 11, color: AppTheme.muted),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(LucideIcons.refreshCw, size: 14),
              label: const Text('REFRESH'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      color: AppTheme.accent,
      backgroundColor: AppTheme.panel,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                const Icon(LucideIcons.list, size: 12, color: AppTheme.muted),
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
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${logs.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Log entries list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[logs.length - 1 - index]; // newest first
                return _LogCard(log: log, onShowOnMap: onShowOnMap);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LogCard extends StatefulWidget {
  final LogEntry log;
  final Function(double lat, double lng) onShowOnMap;

  const _LogCard({required this.log, required this.onShowOnMap});

  @override
  State<_LogCard> createState() => _LogCardState();
}

class _LogCardState extends State<_LogCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final log = widget.log;
    final date = DateTime.fromMillisecondsSinceEpoch(
      (log.timestamp * 1000).toInt(),
    );
    final dateStr =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final timeStr =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final hasGps =
        log.lat != null && log.lng != null && (log.lat != 0 || log.lng != 0);
    final gpsStr =
        hasGps
            ? '${log.lat!.toStringAsFixed(4)}, ${log.lng!.toStringAsFixed(4)}'
            : 'No GPS data';

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _expanded ? AppTheme.panel : AppTheme.panelAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                _expanded
                    ? AppTheme.accent.withValues(alpha: 0.3)
                    : AppTheme.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary row (always visible)
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppTheme.accent,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: AppTheme.accent, blurRadius: 6),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$dateStr  $timeStr',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        gpsStr,
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppTheme.muted,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${log.volumeLiters} L',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.accent,
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(
                    LucideIcons.chevronDown,
                    size: 16,
                    color: AppTheme.muted,
                  ),
                ),
              ],
            ),

            // Expanded details
            if (_expanded) ...[
              const SizedBox(height: 12),
              Container(height: 1, color: AppTheme.border),
              const SizedBox(height: 12),
              _DetailRow(label: 'DEPTH', value: '${log.depthM} m'),
              const SizedBox(height: 6),
              _DetailRow(label: 'VOLUME', value: '${log.volumeLiters} liters'),
              const SizedBox(height: 6),
              _DetailRow(
                label: 'CONFIDENCE',
                value: '${(log.confidence * 100).toStringAsFixed(1)}%',
              ),
              const SizedBox(height: 6),
              _DetailRow(
                label: 'GPS LAT',
                value: log.lat?.toStringAsFixed(6) ?? '--',
              ),
              const SizedBox(height: 6),
              _DetailRow(
                label: 'GPS LNG',
                value: log.lng?.toStringAsFixed(6) ?? '--',
              ),
              const SizedBox(height: 6),
              _DetailRow(label: 'TIMESTAMP', value: '${log.timestamp}'),

              // View on Map button
              if (hasGps) ...[
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      widget.onShowOnMap(log.lat!, log.lng!);
                    },
                    icon: const Icon(LucideIcons.mapPin, size: 14),
                    label: const Text('VIEW ON MAP'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.accent,
                      side: BorderSide(
                        color: AppTheme.accent.withValues(alpha: 0.4),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9,
            color: AppTheme.muted,
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
          ),
        ),
        Text(value, style: const TextStyle(fontSize: 12, color: AppTheme.text)),
      ],
    );
  }
}
