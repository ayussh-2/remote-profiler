import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/log_entry.dart';
import '../theme.dart';

class MapView extends StatefulWidget {
  final List<LogEntry> logs;
  const MapView({super.key, required this.logs});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final MapController _mapController = MapController();

  List<LogEntry> get validLogs =>
      widget.logs
          .where(
            (l) => l.lat != null && l.lng != null && (l.lat != 0 || l.lng != 0),
          )
          .toList();

  @override
  void didUpdateWidget(MapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (validLogs.isNotEmpty) {
      final last = validLogs.last;
      _mapController.move(LatLng(last.lat!, last.lng!), 14);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter:
                    validLogs.isNotEmpty
                        ? LatLng(validLogs.last.lat!, validLogs.last.lng!)
                        : const LatLng(20.5937, 78.9629),
                initialZoom: validLogs.isNotEmpty ? 14 : 5,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.profiler',
                ),
                MarkerLayer(
                  markers:
                      validLogs.map((log) {
                        return Marker(
                          point: LatLng(log.lat!, log.lng!),
                          width: 14,
                          height: 14,
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppTheme.accent,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.black, width: 2),
                              boxShadow: const [
                                BoxShadow(
                                  color: AppTheme.accent,
                                  blurRadius: 10,
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                ),
              ],
            ),
            if (validLogs.isEmpty)
              Container(
                color: const Color(0xCC0A0C0F),
                alignment: Alignment.center,
                child: const Text(
                  'NO DATA — AWAITING SCAN',
                  style: TextStyle(
                    fontSize: 10,
                    color: AppTheme.muted,
                    letterSpacing: 3,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
