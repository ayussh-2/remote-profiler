import 'package:flutter/material.dart';
import '../models/log_entry.dart';
import '../theme.dart';

class StatsStrip extends StatelessWidget {
  final List<LogEntry> logs;
  const StatsStrip({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    double totalVol = logs.fold(0, (sum, item) => sum + item.volumeLiters);
    double avgConf =
        logs.isNotEmpty
            ? (logs.fold(0.0, (sum, item) => sum + item.confidence) /
                    logs.length) *
                100
            : 0;
    double avgDepth =
        logs.isNotEmpty
            ? logs.fold(0.0, (sum, item) => sum + item.depthM) / logs.length
            : 0;

    final items = [
      {
        'label': 'Total Detections',
        'value': logs.length.toString(),
        'unit': '',
      },
      {
        'label': 'Total Volume',
        'value': totalVol.toStringAsFixed(2),
        'unit': 'L',
      },
      {
        'label': 'Avg Confidence',
        'value': avgConf.toStringAsFixed(1),
        'unit': '%',
      },
      {'label': 'Avg Depth', 'value': avgDepth.toStringAsFixed(3), 'unit': 'm'},
    ];

    return Container(
      color: AppTheme.panelAlt,
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children:
            items.map((item) {
              return Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border:
                        item != items.last
                            ? const Border(
                              right: BorderSide(color: AppTheme.border),
                            )
                            : null,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item['label']!.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 8,
                          color: AppTheme.muted,
                          letterSpacing: 2,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            item['value']!,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.accent,
                            ),
                          ),
                          if (item['unit']!.isNotEmpty) ...[
                            const SizedBox(width: 2),
                            Text(
                              item['unit']!,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppTheme.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
      ),
    );
  }
}
