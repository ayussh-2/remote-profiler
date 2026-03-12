import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../models/log_entry.dart';
import '../services/api_service.dart';
import '../theme.dart';
import 'scan_screen.dart';
import 'map_screen.dart';
import 'logs_screen.dart';
import 'settings_screen.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;
  List<LogEntry> _logs = [];
  bool _apiOk = false;
  bool _logsLoading = false;

  // Target coordinates to zoom to on the map (set when navigating from logs)
  double? _targetLat;
  double? _targetLng;

  @override
  void initState() {
    super.initState();
    _fetchLogs();
  }

  Future<void> _fetchLogs() async {
    setState(() => _logsLoading = true);
    try {
      final logs = await ApiService.fetchLogs();
      if (mounted) {
        setState(() {
          _logs = logs;
          _apiOk = true;
          _logsLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _apiOk = false;
          _logsLoading = false;
        });
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

  /// Called from LogsScreen when user taps "View on Map"
  void _showOnMap(double lat, double lng) {
    setState(() {
      _targetLat = lat;
      _targetLng = lng;
      _currentIndex = 1; // Switch to Map tab
    });
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
      body: IndexedStack(
        index: _currentIndex,
        children: [
          ScanScreen(onDetectionComplete: _fetchLogs),
          MapScreen(
            logs: _logs,
            targetLat: _targetLat,
            targetLng: _targetLng,
            onTargetConsumed: () {
              // Clear target so it doesn't re-zoom on rebuild
              _targetLat = null;
              _targetLng = null;
            },
          ),
          LogsScreen(
            logs: _logs,
            loading: _logsLoading,
            onRefresh: _fetchLogs,
            onShowOnMap: _showOnMap,
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() => _currentIndex = index);
            // Auto-refresh logs when switching to logs tab
            if (index == 2) _fetchLogs();
          },
          backgroundColor: AppTheme.panel,
          selectedItemColor: AppTheme.accent,
          unselectedItemColor: AppTheme.muted,
          type: BottomNavigationBarType.fixed,
          selectedFontSize: 9,
          unselectedFontSize: 9,
          selectedLabelStyle: const TextStyle(
            letterSpacing: 2,
            fontWeight: FontWeight.w700,
          ),
          unselectedLabelStyle: const TextStyle(letterSpacing: 2),
          items: const [
            BottomNavigationBarItem(
              icon: Icon(LucideIcons.scanLine),
              activeIcon: Icon(LucideIcons.scanLine),
              label: 'SCAN',
            ),
            BottomNavigationBarItem(
              icon: Icon(LucideIcons.map),
              activeIcon: Icon(LucideIcons.map),
              label: 'MAP',
            ),
            BottomNavigationBarItem(
              icon: Icon(LucideIcons.list),
              activeIcon: Icon(LucideIcons.list),
              label: 'LOGS',
            ),
          ],
        ),
      ),
    );
  }
}
