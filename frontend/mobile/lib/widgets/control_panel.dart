import 'dart:io';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:image_picker/image_picker.dart';
import '../theme.dart';

class ControlPanel extends StatelessWidget {
  final File? imageFile;
  final String? annotatedImgBase64;
  final TextEditingController depthController;
  final TextEditingController latController;
  final TextEditingController lngController;
  final bool loading;
  final String? error;
  final Map<String, dynamic>? latest;
  final VoidCallback onDetect;
  final VoidCallback onGetLocation;
  final Function(File) onImageSelected;

  const ControlPanel({
    super.key,
    required this.imageFile,
    required this.annotatedImgBase64,
    required this.depthController,
    required this.latController,
    required this.lngController,
    required this.loading,
    required this.error,
    required this.latest,
    required this.onDetect,
    required this.onGetLocation,
    required this.onImageSelected,
  });

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source);
    if (picked != null) {
      onImageSelected(File(picked.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.panel,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLabel(LucideIcons.camera, 'INPUT SENSORS'),
          const SizedBox(height: 8),

          // Image preview area
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF070A0D),
                border: Border.all(color: AppTheme.border),
                borderRadius: BorderRadius.circular(6),
              ),
              clipBehavior: Clip.hardEdge,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (annotatedImgBase64 != null)
                    Image.memory(
                      Uri.parse(
                        'data:image/jpeg;base64,$annotatedImgBase64',
                      ).data!.contentAsBytes(),
                      fit: BoxFit.contain,
                    )
                  else if (imageFile != null)
                    Image.file(imageFile!, fit: BoxFit.contain)
                  else
                    const Center(
                      child: Text(
                        'AWAITING IMAGE OVER MUX...',
                        style: TextStyle(
                          fontSize: 10,
                          color: AppTheme.muted,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(3),
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
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickImage(ImageSource.camera),
                  child: const Text('CAMERA'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _pickImage(ImageSource.gallery),
                  child: const Text('GALLERY'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildLabel(LucideIcons.radio, 'TELEMETRYOVERRIDE'),
              InkWell(
                onTap: onGetLocation,
                child: const Row(
                  children: [
                    Icon(LucideIcons.mapPin, size: 10, color: AppTheme.accent),
                    SizedBox(width: 4),
                    Text(
                      'GET GPS',
                      style: TextStyle(
                        fontSize: 9,
                        color: AppTheme.accent,
                        letterSpacing: 2,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          TextField(
            controller: depthController,
            decoration: const InputDecoration(labelText: 'Depth (mm)'),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 8),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: latController,
                  decoration: const InputDecoration(labelText: 'Lat'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: lngController,
                  decoration: const InputDecoration(labelText: 'Lng'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),
          if (error != null)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppTheme.red.withValues(alpha: 0.1),
                border: Border.all(color: AppTheme.red.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                error!,
                style: const TextStyle(
                  color: AppTheme.red,
                  fontSize: 10,
                  letterSpacing: 1,
                ),
              ),
            ),

          ElevatedButton(
            onPressed: loading ? null : onDetect,
            child:
                loading
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

          if (latest != null) ...[
            const SizedBox(height: 16),
            _buildLabel(LucideIcons.cpu, 'LATEST RESULT'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                border: Border.all(color: AppTheme.border),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'VOLUME',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accent,
                        ),
                      ),
                      Text(
                        '${latest!['volume_liters']} L',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.accent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'CONFIDENCE',
                        style: TextStyle(fontSize: 10, color: AppTheme.muted),
                      ),
                      Text(
                        '${(latest!['confidence'] * 100).toStringAsFixed(1)}%',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.text,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLabel(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 12, color: AppTheme.muted),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontSize: 9,
            color: AppTheme.muted,
            letterSpacing: 3,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
