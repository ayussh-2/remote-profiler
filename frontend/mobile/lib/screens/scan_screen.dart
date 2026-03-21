import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../theme.dart';

class ScanScreen extends StatefulWidget {
  final VoidCallback onDetectionComplete;
  const ScanScreen({super.key, required this.onDetectionComplete});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen>
    with SingleTickerProviderStateMixin {
  File? _selectedFile;
  String? _annotatedImg;
  bool _loading = false;
  String? _error;
  Map<String, dynamic>? _latest;

  final _depthController = TextEditingController(text: '80');

  // Auto-fetched GPS
  double? _autoLat;
  double? _autoLng;
  bool _gpsLoading = false;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _depthController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchGPS() async {
    setState(() => _gpsLoading = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _gpsLoading = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() => _gpsLoading = false);
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() => _gpsLoading = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (mounted) {
        setState(() {
          _autoLat = position.latitude;
          _autoLng = position.longitude;
          _gpsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _gpsLoading = false);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source);
    if (picked != null && mounted) {
      setState(() {
        _selectedFile = File(picked.path);
        _annotatedImg = null;
        _latest = null;
        _error = null;
      });
      // Auto-fetch GPS as soon as image is captured/selected
      _fetchGPS();
    }
  }

  Future<void> _handleDetect() async {
    if (_selectedFile == null) {
      setState(() => _error = "Capture or select an image first");
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final depthMm = double.tryParse(_depthController.text) ?? 80.0;
      final lat = _autoLat ?? 0.0;
      final lng = _autoLng ?? 0.0;

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
        widget.onDetectionComplete();
      }
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

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Image Preview (takes up most of the screen) ──
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            decoration: BoxDecoration(
              color: const Color(0xFF070A0D),
              border: Border.all(color: AppTheme.border),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_annotatedImg != null)
                  Image.memory(
                    base64Decode(_annotatedImg!),
                    fit: BoxFit.contain,
                  )
                else if (_selectedFile != null)
                  Image.file(_selectedFile!, fit: BoxFit.contain)
                else
                  Center(
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        return Opacity(
                          opacity: 0.3 + (_pulseController.value * 0.4),
                          child: child,
                        );
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            LucideIcons.scanLine,
                            size: 56,
                            color: AppTheme.accent.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'TAP CAMERA TO SCAN',
                            style: TextStyle(
                              fontSize: 11,
                              color: AppTheme.muted,
                              letterSpacing: 3,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // CAM_01 badge
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'CAM_01',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.accent,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                ),

                // GPS indicator
                Positioned(
                  top: 8,
                  left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (_autoLat != null)
                              ? AppTheme.green.withValues(alpha: 0.15)
                              : AppTheme.muted.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_gpsLoading)
                          const SizedBox(
                            width: 8,
                            height: 8,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppTheme.accent,
                            ),
                          )
                        else
                          Icon(
                            LucideIcons.mapPin,
                            size: 9,
                            color:
                                _autoLat != null
                                    ? AppTheme.green
                                    : AppTheme.muted,
                          ),
                        const SizedBox(width: 4),
                        Text(
                          _autoLat != null
                              ? '${_autoLat!.toStringAsFixed(4)}, ${_autoLng!.toStringAsFixed(4)}'
                              : 'NO GPS',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                            color:
                                _autoLat != null
                                    ? AppTheme.green
                                    : AppTheme.muted,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Loading overlay
                if (_loading)
                  Container(
                    color: Colors.black54,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.accent,
                            ),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'ANALYZING...',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppTheme.accent,
                              letterSpacing: 3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // ── Controls Area ──
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Column(
            children: [
              // Camera + Gallery buttons
              Row(
                children: [
                  Expanded(
                    child: _ActionButton(
                      icon: LucideIcons.camera,
                      label: 'CAMERA',
                      onTap: () => _pickImage(ImageSource.camera),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ActionButton(
                      icon: LucideIcons.image,
                      label: 'GALLERY',
                      onTap: () => _pickImage(ImageSource.gallery),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Depth input + Detect button
              Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: TextField(
                      controller: _depthController,
                      decoration: const InputDecoration(
                        labelText: 'Depth (mm)',
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
                      ),
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _handleDetect,
                        child:
                            _loading
                                ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                                : const Text('RUN DETECTION'),
                      ),
                    ),
                  ),
                ],
              ),

              // Error message
              if (_error != null) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.red.withValues(alpha: 0.1),
                    border: Border.all(
                      color: AppTheme.red.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: AppTheme.red,
                      fontSize: 10,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],

              if (_latest != null) ...[
                const SizedBox(height: 8),
                _buildResultCard(),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Color _severityColor(String severity) {
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

  Widget _buildResultCard() {
    final d = _latest!;
    final severity = d['severity'] ?? '';
    final sevColor = _severityColor(severity);
    final materials = d['materials'] as Map<String, dynamic>? ?? {};

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: sevColor.withValues(alpha: 0.06),
        border: Border.all(color: sevColor.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Severity + Confidence row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: sevColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  severity,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: sevColor,
                    letterSpacing: 2,
                  ),
                ),
              ),
              Text(
                '${((d['confidence'] ?? 0) * 100).toStringAsFixed(1)}% CONF',
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.green,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Volume
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${d['volume_liters']} L',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.accent,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '(${d['volume_min_liters']} - ${d['volume_max_liters']} L)',
                  style: const TextStyle(fontSize: 10, color: AppTheme.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Repair method
          Text(
            d['repair_method'] ?? '',
            style: TextStyle(
              fontSize: 10,
              color: sevColor,
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
            ),
          ),

          const Divider(color: AppTheme.border, height: 16),

          // Materials
          _materialRow('Hot-mix asphalt', '${materials['hotmix_kg'] ?? 0} kg'),
          _materialRow('Tack coat', '${materials['tack_coat_liters'] ?? 0} L'),
          if ((materials['aggregate_base_kg'] ?? 0) > 0)
            _materialRow(
              'Aggregate base',
              '${materials['aggregate_base_kg']} kg',
            ),
        ],
      ),
    );
  }

  Widget _materialRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 10, color: AppTheme.muted),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 10,
              color: AppTheme.text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Reusable action button ──
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: AppTheme.muted),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.muted,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
