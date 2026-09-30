import 'package:sqflite/sqflite.dart';

import '../models/calibration_log_entry.dart';
import '../models/calibration_reading.dart';
import '../models/virtual_battery_slot.dart';

class CalibrationDatabase {
  CalibrationDatabase._();
  static final CalibrationDatabase instance = CalibrationDatabase._();
  Database? _database;

  Future<Database> get _db async => _database ??= await openDatabase(
    'calibration_history.db',
    version: 2,
    onCreate: (db, _) async {
      await db.execute('''
      CREATE TABLE calibration_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        deviceId TEXT NOT NULL,
        action TEXT NOT NULL,
        value TEXT,
        timestamp TEXT NOT NULL,
        direction TEXT NOT NULL,
        status TEXT NOT NULL
      )
    ''');
      await _createVirtualBatterySlotsTable(db);
    },
    onUpgrade: (db, oldVersion, _) async {
      if (oldVersion < 2) await _createVirtualBatterySlotsTable(db);
    },
  );

  Future<void> _createVirtualBatterySlotsTable(Database db) => db.execute('''
    CREATE TABLE IF NOT EXISTS virtual_battery_slots(
      position INTEGER PRIMARY KEY,
      name TEXT NOT NULL,
      role TEXT NOT NULL,
      serial TEXT,
      matchedDeviceId TEXT,
      matchedDeviceName TEXT
    )
  ''');

  Future<void> insert(String deviceId, CalibrationReading reading) async {
    final db = await _db;
    await db.insert('calibration_log', reading.toLogMap(deviceId));
  }

  Future<List<CalibrationLogEntry>> entriesFor(String deviceId) async {
    final db = await _db;
    final rows = await db.query(
      'calibration_log',
      where: 'deviceId = ?',
      whereArgs: [deviceId],
      orderBy: 'timestamp DESC',
    );
    return rows.map(CalibrationLogEntry.fromMap).toList();
  }

  Future<List<VirtualBatterySlot>> virtualBatterySlots() async {
    final db = await _db;
    final rows = await db.query(
      'virtual_battery_slots',
      orderBy: 'position ASC',
    );
    return rows
        .map(
          (row) => VirtualBatterySlot.fromMap(Map<String, Object?>.from(row)),
        )
        .toList();
  }

  Future<void> saveVirtualBatterySlot(VirtualBatterySlot slot) async {
    final db = await _db;
    await db.insert(
      'virtual_battery_slots',
      slot.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> deleteVirtualBatterySlot(int position) async {
    final db = await _db;
    await db.delete(
      'virtual_battery_slots',
      where: 'position = ?',
      whereArgs: [position],
    );
  }
}
