class CalibrationReading {
  const CalibrationReading({
    required this.key,
    required this.value,
    required this.timestamp,
    required this.direction,
    required this.status,
  });

  final String key;
  final dynamic value;
  final DateTime timestamp;
  final String direction;
  final String status;

  factory CalibrationReading.fromJson(
    Map<String, dynamic> json, {
    required String key,
    String direction = 'read',
  }) => CalibrationReading(
    key: (json['key'] as String?) ?? key,
    value: json['value'],
    timestamp:
        DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
        DateTime.now(),
    direction: direction,
    status: (json['status'] as String?) ?? 'success',
  );

  Map<String, dynamic> toLogMap(String deviceId) => {
    'deviceId': deviceId,
    'action': key,
    'value': value?.toString(),
    'timestamp': timestamp.toIso8601String(),
    'direction': direction,
    'status': status,
  };
}
