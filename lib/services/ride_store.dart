import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/acceleration_run.dart';
import '../models/acceleration_sample.dart';
import '../models/ride_sample.dart';
import '../models/ride_session.dart';
import '../services/demo_ride.dart';
import '../utils/geo.dart';

/// 本地存储：行程（sessions/samples）与零百成绩（acceleration_runs/samples）。
///
/// SQLite 与内存两套实现，Web 预览用内存、手机用 SQLite，接口完全一致。
class RideStore {
  RideStore({bool? useMemory}) : _useMemory = useMemory ?? kIsWeb;

  /// 数据库版本。v2 新增零百成绩两张表。
  static const int schemaVersion = 2;

  final bool _useMemory;
  final List<RideSession> _memorySessions = [];
  final Map<int, List<RideSample>> _memorySamples = {};
  int _nextMemoryId = 1;

  final List<AccelerationRun> _memoryAccelRuns = [];
  final Map<int, List<AccelerationSample>> _memoryAccelSamples = {};
  int _nextAccelRunId = 1;

  Database? _db;

  Database get _database {
    final db = _db;
    if (db == null) {
      throw StateError('RideStore.init() has not completed');
    }
    return db;
  }

  Future<void> init() async {
    if (_useMemory || _db != null) {
      return;
    }
    final directory = await getDatabasesPath();
    _db = await openDatabase(
      p.join(directory, 'motolean.db'),
      version: schemaVersion,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
        // 新装用户与升级用户必须得到完全一致的表结构，因此建表 SQL 共用。
        await _createRideTables(db);
        await _createAccelerationTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _createAccelerationTables(db);
        }
      },
    );
    await _finalizeOrphanSessions();
  }

  static Future<void> _createRideTables(Database db) async {
    await db.execute('''
      CREATE TABLE sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at INTEGER NOT NULL,
        ended_at INTEGER,
        distance_m REAL NOT NULL DEFAULT 0,
        duration_s INTEGER NOT NULL DEFAULT 0,
        moving_s INTEGER NOT NULL DEFAULT 0,
        max_speed_mps REAL NOT NULL DEFAULT 0,
        avg_speed_mps REAL NOT NULL DEFAULT 0,
        max_lean_left_deg REAL NOT NULL DEFAULT 0,
        max_lean_right_deg REAL NOT NULL DEFAULT 0,
        elevation_gain_m REAL NOT NULL DEFAULT 0,
        sample_count INTEGER NOT NULL DEFAULT 0,
        is_demo INTEGER NOT NULL DEFAULT 0,
        note TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE samples (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id INTEGER NOT NULL,
        t_ms INTEGER NOT NULL,
        lean_deg REAL NOT NULL,
        lat REAL,
        lon REAL,
        alt_m REAL,
        speed_mps REAL,
        accuracy_m REAL,
        FOREIGN KEY (session_id) REFERENCES sessions (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_samples_session ON samples (session_id, t_ms)',
    );
  }

  static Future<void> _createAccelerationTables(Database db) async {
    await db.execute('''
      CREATE TABLE acceleration_runs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        started_at INTEGER NOT NULL,
        target_speed_kmh REAL NOT NULL,
        result_ms INTEGER NOT NULL,
        rollout INTEGER NOT NULL DEFAULT 0,
        result_60_ms INTEGER,
        result_130_ms INTEGER,
        result_200_ms INTEGER,
        distance_m REAL,
        max_speed_kmh REAL,
        grade_percent REAL,
        gps_accuracy_m REAL,
        start_lat REAL,
        start_lon REAL,
        valid INTEGER NOT NULL DEFAULT 1,
        invalid_reason TEXT,
        is_demo INTEGER NOT NULL DEFAULT 0,
        note TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE acceleration_samples (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        run_id INTEGER NOT NULL,
        t_ms INTEGER NOT NULL,
        speed_kmh REAL NOT NULL,
        accuracy_m REAL,
        lat REAL,
        lon REAL,
        FOREIGN KEY (run_id) REFERENCES acceleration_runs (id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_accel_samples_run ON acceleration_samples (run_id, t_ms)',
    );
  }

  // ---------------------------------------------------------------------------
  // 行程
  // ---------------------------------------------------------------------------

  Future<int> createSession(RideSession session) async {
    if (_useMemory) {
      final id = _nextMemoryId++;
      _memorySessions.add(session.copyWith(id: id));
      return id;
    }
    return _database.insert('sessions', session.toMap());
  }

  Future<void> updateSession(RideSession session) async {
    final id = session.id;
    if (id == null) {
      return;
    }
    if (_useMemory) {
      final index = _memorySessions.indexWhere((item) => item.id == id);
      if (index >= 0) {
        _memorySessions[index] = session;
      }
      return;
    }
    await _database.update(
      'sessions',
      session.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> insertSample(RideSample sample) async {
    if (_useMemory) {
      _memorySamples.putIfAbsent(sample.sessionId, () => []).add(sample);
      return;
    }
    await _database.insert('samples', sample.toMap());
  }

  Future<int> insertSampleCount(int sessionId, List<RideSample> samples) async {
    if (_useMemory) {
      _memorySamples.putIfAbsent(sessionId, () => []).addAll(samples);
      final index =
          _memorySessions.indexWhere((session) => session.id == sessionId);
      if (index >= 0) {
        _memorySessions[index] = _memorySessions[index].copyWith(
          sampleCount: samples.length,
        );
      }
      return samples.length;
    }
    final batch = _database.batch();
    for (final sample in samples) {
      batch.insert('samples', sample.toMap());
    }
    await batch.commit(noResult: true);
    await _database.update(
      'sessions',
      {'sample_count': samples.length},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
    return samples.length;
  }

  Future<List<RideSession>> loadSessions() async {
    if (_useMemory) {
      final sessions = List<RideSession>.of(_memorySessions);
      sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return sessions;
    }
    final rows = await _database.query(
      'sessions',
      orderBy: 'started_at DESC',
    );
    return rows.map(RideSession.fromMap).toList();
  }

  Future<RideSession?> loadSession(int id) async {
    if (_useMemory) {
      for (final session in _memorySessions) {
        if (session.id == id) {
          return session;
        }
      }
      return null;
    }
    final rows = await _database.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : RideSession.fromMap(rows.first);
  }

  Future<List<RideSample>> loadSamples(int sessionId) async {
    if (_useMemory) {
      final samples = List<RideSample>.of(
        _memorySamples[sessionId] ?? const [],
      );
      samples.sort((a, b) => a.tMs.compareTo(b.tMs));
      return samples;
    }
    final rows = await _database.query(
      'samples',
      where: 'session_id = ?',
      whereArgs: [sessionId],
      orderBy: 't_ms ASC',
    );
    return rows.map(RideSample.fromMap).toList();
  }

  Future<void> deleteSession(int id) async {
    if (_useMemory) {
      _memorySessions.removeWhere((session) => session.id == id);
      _memorySamples.remove(id);
      return;
    }
    await _database.transaction((txn) async {
      await txn.delete('samples', where: 'session_id = ?', whereArgs: [id]);
      await txn.delete('sessions', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// 删除全部骑行行程（设置页的危险操作）。
  Future<void> deleteAllRides() async {
    if (_useMemory) {
      _memorySessions.clear();
      _memorySamples.clear();
      return;
    }
    await _database.transaction((txn) async {
      await txn.delete('samples');
      await txn.delete('sessions');
    });
  }

  /// 删除全部演示数据（演示行程 + 演示成绩）。
  Future<void> deleteDemoData() async {
    if (_useMemory) {
      final demoSessionIds = _memorySessions
          .where((session) => session.isDemo)
          .map((session) => session.id)
          .whereType<int>()
          .toList();
      for (final id in demoSessionIds) {
        _memorySamples.remove(id);
      }
      _memorySessions.removeWhere((session) => session.isDemo);
      final demoRunIds = _memoryAccelRuns
          .where((run) => run.isDemo)
          .map((run) => run.id)
          .whereType<int>()
          .toList();
      for (final id in demoRunIds) {
        _memoryAccelSamples.remove(id);
      }
      _memoryAccelRuns.removeWhere((run) => run.isDemo);
      return;
    }
    await _database.transaction((txn) async {
      final demoSessionRows = await txn.query(
        'sessions',
        columns: ['id'],
        where: 'is_demo = ?',
        whereArgs: [1],
      );
      for (final row in demoSessionRows) {
        final id = row['id'] as int;
        await txn.delete('samples', where: 'session_id = ?', whereArgs: [id]);
        await txn.delete('sessions', where: 'id = ?', whereArgs: [id]);
      }
      final demoRunRows = await txn.query(
        'acceleration_runs',
        columns: ['id'],
        where: 'is_demo = ?',
        whereArgs: [1],
      );
      for (final row in demoRunRows) {
        final id = row['id'] as int;
        await txn.delete('acceleration_samples', where: 'run_id = ?',
            whereArgs: [id]);
        await txn.delete('acceleration_runs', where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  Future<int> importDemoRide(DemoRide ride) async {
    final sessionId = await createSession(ride.session);
    final samples = [
      for (final sample in ride.samples)
        RideSample(
          sessionId: sessionId,
          tMs: sample.tMs,
          leanDeg: sample.leanDeg,
          lat: sample.lat,
          lon: sample.lon,
          altitudeM: sample.altitudeM,
          speedMps: sample.speedMps,
          accuracyM: sample.accuracyM,
        ),
    ];
    await insertSampleCount(sessionId, samples);
    return sessionId;
  }

  // ---------------------------------------------------------------------------
  // 零百成绩
  // ---------------------------------------------------------------------------

  Future<int> createAccelerationRun(AccelerationRun run) async {
    if (_useMemory) {
      final id = _nextAccelRunId++;
      _memoryAccelRuns.add(run.copyWith(id: id));
      return id;
    }
    return _database.insert('acceleration_runs', run.toMap());
  }

  Future<void> updateAccelerationRun(AccelerationRun run) async {
    final id = run.id;
    if (id == null) {
      return;
    }
    if (_useMemory) {
      final index = _memoryAccelRuns.indexWhere((item) => item.id == id);
      if (index >= 0) {
        _memoryAccelRuns[index] = run;
      }
      return;
    }
    await _database.update(
      'acceleration_runs',
      run.toMap()..remove('id'),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<int> insertAccelerationSamples(
    int runId,
    List<AccelerationSample> samples,
  ) async {
    if (samples.isEmpty) {
      return 0;
    }
    if (_useMemory) {
      _memoryAccelSamples
          .putIfAbsent(runId, () => [])
          .addAll(samples.map((sample) => _withRunId(sample, runId)));
      return samples.length;
    }
    final batch = _database.batch();
    for (final sample in samples) {
      batch.insert('acceleration_samples', _withRunId(sample, runId).toMap());
    }
    await batch.commit(noResult: true);
    return samples.length;
  }

  Future<List<AccelerationRun>> loadAccelerationRuns({int limit = 200}) async {
    if (_useMemory) {
      final runs = List<AccelerationRun>.of(_memoryAccelRuns);
      runs.sort((a, b) => b.startedAt.compareTo(a.startedAt));
      return runs.take(limit).toList();
    }
    final rows = await _database.query(
      'acceleration_runs',
      orderBy: 'started_at DESC',
      limit: limit,
    );
    return rows.map(AccelerationRun.fromMap).toList();
  }

  Future<AccelerationRun?> loadAccelerationRun(int id) async {
    if (_useMemory) {
      for (final run in _memoryAccelRuns) {
        if (run.id == id) {
          return run;
        }
      }
      return null;
    }
    final rows = await _database.query(
      'acceleration_runs',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : AccelerationRun.fromMap(rows.first);
  }

  Future<List<AccelerationSample>> loadAccelerationSamples(int runId) async {
    if (_useMemory) {
      final samples = List<AccelerationSample>.of(
        _memoryAccelSamples[runId] ?? const [],
      );
      samples.sort((a, b) => a.tMs.compareTo(b.tMs));
      return samples;
    }
    final rows = await _database.query(
      'acceleration_samples',
      where: 'run_id = ?',
      whereArgs: [runId],
      orderBy: 't_ms ASC',
    );
    return rows.map(AccelerationSample.fromMap).toList();
  }

  Future<void> deleteAccelerationRun(int id) async {
    if (_useMemory) {
      _memoryAccelRuns.removeWhere((run) => run.id == id);
      _memoryAccelSamples.remove(id);
      return;
    }
    await _database.transaction((txn) async {
      await txn.delete(
        'acceleration_samples',
        where: 'run_id = ?',
        whereArgs: [id],
      );
      await txn.delete('acceleration_runs', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> deleteAllAccelerationRuns() async {
    if (_useMemory) {
      _memoryAccelRuns.clear();
      _memoryAccelSamples.clear();
      return;
    }
    await _database.transaction((txn) async {
      await txn.delete('acceleration_samples');
      await txn.delete('acceleration_runs');
    });
  }

  static AccelerationSample _withRunId(AccelerationSample sample, int runId) =>
      AccelerationSample(
        runId: runId,
        tMs: sample.tMs,
        speedKmh: sample.speedKmh,
        accuracyM: sample.accuracyM,
        lat: sample.lat,
        lon: sample.lon,
      );

  /// If the app was killed mid-ride, the session row has no end time.
  /// Rebuild its summary from whatever samples were already persisted.
  Future<void> _finalizeOrphanSessions() async {
    final rows = await _database.query(
      'sessions',
      where: 'ended_at IS NULL',
    );
    for (final row in rows) {
      final session = RideSession.fromMap(row);
      final id = session.id;
      if (id == null) {
        continue;
      }
      final samples = await loadSamples(id);
      if (samples.isEmpty) {
        await _database.delete('sessions', where: 'id = ?', whereArgs: [id]);
        continue;
      }
      var distance = 0.0;
      var elevationGain = 0.0;
      var maxSpeed = 0.0;
      var maxLeft = 0.0;
      var maxRight = 0.0;
      var movingS = 0;
      double? lastLat;
      double? lastLon;
      double? lastAlt;
      for (final sample in samples) {
        if (sample.leanDeg < -4) {
          maxLeft = maxLeft > -sample.leanDeg ? maxLeft : -sample.leanDeg;
        }
        if (sample.leanDeg > 4) {
          maxRight = maxRight > sample.leanDeg ? maxRight : sample.leanDeg;
        }
        final speed = sample.speedMps;
        if (speed != null) {
          maxSpeed = maxSpeed > speed ? maxSpeed : speed;
          if (speed > 1) {
            movingS++;
          }
        }
        if (!sample.hasPosition) {
          continue;
        }
        if (lastLat != null && lastLon != null) {
          distance += distanceMeters(
            lastLat,
            lastLon,
            sample.lat!,
            sample.lon!,
          );
        }
        lastLat = sample.lat;
        lastLon = sample.lon;
        final altitude = sample.altitudeM;
        if (altitude != null && lastAlt != null && altitude > lastAlt) {
          elevationGain += altitude - lastAlt;
        }
        if (altitude != null) {
          lastAlt = altitude;
        }
      }
      final lastTMs = samples.last.tMs;
      await updateSession(
        session.copyWith(
          endedAt: session.startedAt.add(Duration(milliseconds: lastTMs)),
          distanceM: distance,
          durationS: lastTMs ~/ 1000,
          movingS: movingS,
          maxSpeedMps: maxSpeed,
          avgSpeedMps: movingS == 0 ? 0.0 : distance / movingS,
          maxLeanLeftDeg: maxLeft,
          maxLeanRightDeg: maxRight,
          elevationGainM: elevationGain,
          sampleCount: samples.length,
        ),
      );
    }
  }
}
