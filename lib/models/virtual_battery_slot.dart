class VirtualBatterySlot {
  const VirtualBatterySlot({
    required this.position,
    required this.name,
    required this.role,
    this.serial,
    this.matchedDeviceId,
    this.matchedDeviceName,
  });

  final int position;
  final String name;
  final String role;
  final String? serial;
  final String? matchedDeviceId;
  final String? matchedDeviceName;

  bool get isMatched => matchedDeviceId != null;

  VirtualBatterySlot copyWith({
    String? name,
    String? role,
    String? serial,
    bool clearSerial = false,
    String? matchedDeviceId,
    String? matchedDeviceName,
    bool clearMatch = false,
  }) => VirtualBatterySlot(
    position: position,
    name: name ?? this.name,
    role: role ?? this.role,
    serial: clearSerial ? null : serial ?? this.serial,
    matchedDeviceId: clearMatch
        ? null
        : matchedDeviceId ?? this.matchedDeviceId,
    matchedDeviceName: clearMatch
        ? null
        : matchedDeviceName ?? this.matchedDeviceName,
  );

  factory VirtualBatterySlot.fromMap(Map<String, Object?> map) =>
      VirtualBatterySlot(
        position: map['position'] as int,
        name: map['name'] as String,
        role: map['role'] as String,
        serial: map['serial'] as String?,
        matchedDeviceId: map['matchedDeviceId'] as String?,
        matchedDeviceName: map['matchedDeviceName'] as String?,
      );

  Map<String, Object?> toMap() => {
    'position': position,
    'name': name,
    'role': role,
    'serial': serial,
    'matchedDeviceId': matchedDeviceId,
    'matchedDeviceName': matchedDeviceName,
  };
}
