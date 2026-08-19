class CalibrationLogEntry {
  const CalibrationLogEntry({
    required this.id,
    required this.deviceId,
    required this.action,
    required this.value,
    required this.timestamp,
    required this.direction,
    required this.status,
  });
  final int id;
  final String deviceId;
  final String action;
  final String? value;
  final DateTime timestamp;
  final String direction;
  final String status;

  factory CalibrationLogEntry.fromMap(Map<String, Object?> map) =>
      CalibrationLogEntry(
        id: map['id']! as int,
        deviceId: map['deviceId']! as String,
        action: map['action']! as String,
        value: map['value'] as String?,
        timestamp: DateTime.parse(map['timestamp']! as String),
        direction: map['direction']! as String,
        status: map['status']! as String,
      );
}
