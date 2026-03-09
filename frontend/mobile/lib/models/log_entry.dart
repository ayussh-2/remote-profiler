class LogEntry {
  final double? lat;
  final double? lng;
  final double depthM;
  final double volumeLiters;
  final double confidence;
  final num timestamp;

  LogEntry({
    this.lat,
    this.lng,
    required this.depthM,
    required this.volumeLiters,
    required this.confidence,
    required this.timestamp,
  });

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      lat: _parseDouble(json['lat']),
      lng: _parseDouble(json['lng']),
      depthM: _parseDouble(json['depth_m']) ?? 0.0,
      volumeLiters: _parseDouble(json['volume_liters']) ?? 0.0,
      confidence: _parseDouble(json['confidence']) ?? 0.0,
      timestamp: json['timestamp'] ?? 0,
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }
}
