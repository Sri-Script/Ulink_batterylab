import 'package:sqflite/sqflite.dart';

import '../models/calibration_log_entry.dart';
import '../models/calibration_reading.dart';

class CalibrationDatabase {
  CalibrationDatabase._();
  static final CalibrationDatabase instance = CalibrationDatabase._();
  Database? _database;

  Future<Database> get _db async => _database ??= await openDatabase(
    'calibration_history.db',
    version: 1,
    onCreate: (db, _) => db.execute('''
      CREATE TABLE calibration_log(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        deviceId TEXT NOT NULL,
        action TEXT NOT NULL,
        value TEXT,
        timestamp TEXT NOT NULL,
        direction TEXT NOT NULL,
        status TEXT NOT NULL
      )
    '''),
  );

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
}
