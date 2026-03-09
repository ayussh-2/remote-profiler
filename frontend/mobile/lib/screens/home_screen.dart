import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:geolocator/geolocator.dart';
import '../models/log_entry.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/stats_strip.dart';
import '../widgets/control_panel.dart';
import '../widgets/map_view.dart';
import '../widgets/logs_table.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<LogEntry> _logs = [];
  Map<String, dynamic>? _latest;
  bool _loading = false;
  bool _apiOk = false;
  String? _error;

  File? _selectedFile;
  String? _annotatedImg;

  final _depthController = TextEditingController(text: '80');
  final _latController = TextEditingController();
  final _lngController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  @override
  void dispose() {
    _depthController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  Future<void> _fetchLogs() async {
    try {
      final logs = await ApiService.fetchLogs();
      if (mounted) {
        setState(() {
          _logs = logs;
          _apiOk = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _apiOk = false;
        });
      }
    }
  }

  Future<void> _getLocation() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Location services are disabled.')),
        );
      }
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('Location permissions are denied')),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(
            content: Text('Location permissions are permanently denied.'),
          ),
        );
      }
      return;
    }

    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('Fetching current location...')),
    );

    Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );

    if (mounted) {
      setState(() {
        _latController.text = position.latitude.toStringAsFixed(6);
        _lngController.text = position.longitude.toStringAsFixed(6);
      });
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Location updated.')),
      );
    }
  }

  Future<void> _handleDetect() async {
    if (_selectedFile == null) {
      setState(() => _error = "Select an image first");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final depthMm = double.tryParse(_depthController.text) ?? 80.0;
      final lat = double.tryParse(_latController.text) ?? 0.0;
      final lng = double.tryParse(_lngController.text) ?? 0.0;

      final data = await ApiService.detect(_selectedFile!, depthMm, lat, lng);

      if (mounted) {
        setState(() {
          if (data['status'] == 'no_pothole') {
            _error = "No pothole detected in image";
          } else {
            _latest = data;
            if (data['annotated_image'] != null) {
              _annotatedImg = data['annotated_image'];
            }
          }
        });
      }
      await _fetchLogs();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _navigateToSettings() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (result == true) {
      _fetchLogs();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(LucideIcons.hexagon, color: AppTheme.accent, size: 20),
            const SizedBox(width: 8),
            const Text('PAVEMENT PROFILER'),
            const Spacer(),
            if (_apiOk)
              const Icon(LucideIcons.wifi, size: 13, color: AppTheme.green)
            else
              const Icon(LucideIcons.wifiOff, size: 13, color: AppTheme.muted),
            const SizedBox(width: 4),
            Text(
              _apiOk ? 'ONLINE' : 'OFFLINE',
              style: TextStyle(
                fontSize: 9,
                color: _apiOk ? AppTheme.green : AppTheme.muted,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _apiOk ? AppTheme.green : AppTheme.muted,
                boxShadow:
                    _apiOk
                        ? const [
                          BoxShadow(color: AppTheme.green, blurRadius: 8),
                        ]
                        : null,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(LucideIcons.settings),
            onPressed: _navigateToSettings,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            StatsStrip(logs: _logs),
            const SizedBox(height: 1), // 1px separator effect via bg
            // Control Panel
            ControlPanel(
              imageFile: _selectedFile,
              annotatedImgBase64: _annotatedImg,
              depthController: _depthController,
              latController: _latController,
              lngController: _lngController,
              loading: _loading,
              error: _error,
              latest: _latest,
              onDetect: _handleDetect,
              onGetLocation: _getLocation,
              onImageSelected: (file) {
                setState(() {
                  _selectedFile = file;
                  _annotatedImg = null;
                  _latest = null;
                  _error = null;
                });
              },
            ),

            const SizedBox(height: 1),

            // Map View
            Container(
              color: AppTheme.panel,
              padding: const EdgeInsets.all(18),
              height: 300,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        LucideIcons.activity,
                        size: 11,
                        color: AppTheme.muted,
                      ),
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
                        '${_logs.where((l) => l.lat != null && l.lng != null).length} POINTS',
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppTheme.muted,
                          letterSpacing: 2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(child: MapView(logs: _logs)),
                ],
              ),
            ),

            const SizedBox(height: 1),

            // Logs Table
            SizedBox(
              height: 400,
              child: LogsTable(logs: _logs, onRefresh: _fetchLogs),
            ),
          ],
        ),
      ),
    );
  }
}
