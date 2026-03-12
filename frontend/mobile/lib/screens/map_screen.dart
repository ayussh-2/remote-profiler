import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/log_entry.dart';
import '../theme.dart';

class MapScreen extends StatefulWidget {
  final List<LogEntry> logs;
  final double? targetLat;
  final double? targetLng;
  final VoidCallback? onTargetConsumed;

  const MapScreen({
    super.key,
    required this.logs,
    this.targetLat,
    this.targetLng,
    this.onTargetConsumed,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapController _mapController = MapController();
  Position? _userPosition;
  bool _locationLoading = true;
  String? _locationError;
  bool _mapReady = false;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void didUpdateWidget(MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If new target coordinates were passed, zoom to them
    if (widget.targetLat != null &&
        widget.targetLng != null &&
        (widget.targetLat != oldWidget.targetLat ||
            widget.targetLng != oldWidget.targetLng)) {
      if (_mapReady) {
        _mapController.move(LatLng(widget.targetLat!, widget.targetLng!), 17);
      }
      widget.onTargetConsumed?.call();
    }
  }

  Future<void> _initLocation() async {
    setState(() {
      _locationLoading = true;
      _locationError = null;
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationError = 'Location services are disabled';
          _locationLoading = false;
        });
        if (mounted) {
          _showLocationDialog(
            'Location Services Disabled',
            'Please enable location services to see your position on the map.',
            onConfirm: () async {
              await Geolocator.openLocationSettings();
              Future.delayed(const Duration(seconds: 2), () {
                if (mounted) _initLocation();
              });
            },
          );
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _locationError = 'Location permission denied';
            _locationLoading = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationError = 'Location permission permanently denied';
          _locationLoading = false;
        });
        if (mounted) {
          _showLocationDialog(
            'Permission Required',
            'Location permission is permanently denied. Please enable it from app settings.',
            onConfirm: () async {
              await Geolocator.openAppSettings();
            },
          );
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (mounted) {
        setState(() {
          _userPosition = position;
          _locationLoading = false;
        });

        // Only zoom to user if there's no specific target
        if (widget.targetLat == null && _mapReady) {
          _mapController.move(
            LatLng(position.latitude, position.longitude),
            16,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _locationError = 'Could not get location';
          _locationLoading = false;
        });
      }
    }
  }

  void _showLocationDialog(
    String title,
    String message, {
    required VoidCallback onConfirm,
  }) {
    showDialog(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: AppTheme.panel,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.accent,
                letterSpacing: 1,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              message,
              style: const TextStyle(fontSize: 12, color: AppTheme.text),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'LATER',
                  style: TextStyle(color: AppTheme.muted, letterSpacing: 2),
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  onConfirm();
                },
                child: const Text('OPEN SETTINGS'),
              ),
            ],
          ),
    );
  }

  List<LogEntry> get validLogs =>
      widget.logs
          .where(
            (l) => l.lat != null && l.lng != null && (l.lat != 0 || l.lng != 0),
          )
          .toList();

  void _centerOnUser() {
    if (_userPosition != null) {
      _mapController.move(
        LatLng(_userPosition!.latitude, _userPosition!.longitude),
        16,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Determine initial center: target > user > last log > India default
    final LatLng initialCenter;
    final double initialZoom;

    if (widget.targetLat != null && widget.targetLng != null) {
      initialCenter = LatLng(widget.targetLat!, widget.targetLng!);
      initialZoom = 17;
    } else if (_userPosition != null) {
      initialCenter = LatLng(_userPosition!.latitude, _userPosition!.longitude);
      initialZoom = 16;
    } else if (validLogs.isNotEmpty) {
      initialCenter = LatLng(validLogs.last.lat!, validLogs.last.lng!);
      initialZoom = 14;
    } else {
      initialCenter = const LatLng(20.5937, 78.9629);
      initialZoom = 5;
    }

    return Stack(
      children: [
        // ── Map ──
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: initialZoom,
            onMapReady: () {
              _mapReady = true;
              // If we got target coords before map was ready, zoom now
              if (widget.targetLat != null && widget.targetLng != null) {
                _mapController.move(
                  LatLng(widget.targetLat!, widget.targetLng!),
                  17,
                );
                widget.onTargetConsumed?.call();
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.example.profiler',
            ),
            MarkerLayer(
              markers: [
                // User location marker (blue)
                if (_userPosition != null)
                  Marker(
                    point: LatLng(
                      _userPosition!.latitude,
                      _userPosition!.longitude,
                    ),
                    width: 24,
                    height: 24,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppTheme.blue.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: AppTheme.blue,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                            boxShadow: const [
                              BoxShadow(color: AppTheme.blue, blurRadius: 8),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                // Pothole markers (amber)
                ...validLogs.map((log) {
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
                          BoxShadow(color: AppTheme.accent, blurRadius: 10),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ],
        ),

        // ── Header overlay ──
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.bg.withValues(alpha: 0.9),
                  AppTheme.bg.withValues(alpha: 0.0),
                ],
              ),
            ),
            child: Row(
              children: [
                const Icon(LucideIcons.mapPin, size: 12, color: AppTheme.muted),
                const SizedBox(width: 6),
                const Text(
                  'DEFECT MAP',
                  style: TextStyle(
                    fontSize: 9,
                    color: AppTheme.muted,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  '${validLogs.length} POINTS',
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppTheme.muted,
                    letterSpacing: 2,
                  ),
                ),
              ],
            ),
          ),
        ),

        // ── Loading overlay ──
        if (_locationLoading)
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.panel.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accent,
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'ACQUIRING LOCATION...',
                    style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.muted,
                      letterSpacing: 2,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── Error overlay ──
        if (_locationError != null && !_locationLoading)
          Positioned(
            bottom: 20,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.panel.withValues(alpha: 0.95),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(
                    LucideIcons.alertCircle,
                    size: 14,
                    color: AppTheme.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _locationError!.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppTheme.red,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _initLocation,
                    child: const Text(
                      'RETRY',
                      style: TextStyle(
                        fontSize: 9,
                        color: AppTheme.accent,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // ── Center on User FAB ──
        if (_userPosition != null)
          Positioned(
            bottom: 20,
            right: 16,
            child: FloatingActionButton.small(
              backgroundColor: AppTheme.panel,
              onPressed: _centerOnUser,
              child: const Icon(
                LucideIcons.crosshair,
                size: 18,
                color: AppTheme.accent,
              ),
            ),
          ),
      ],
    );
  }
}
