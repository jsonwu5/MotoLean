import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/ride_sample.dart';
import '../models/ride_session.dart';
import '../services/demo_ride.dart';
import '../utils/geo.dart';

class RideStore {
  RideStore({bool? useMemory}) : _useMemory = useMemory ?? kIsWeb;

  final bool _useMemory;
  final List<RideSession> _memorySessions = [];
  final Map<int, List<RideSample>> _memorySamples = {};
  int _nextMemoryId = 1;

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
      version: 1,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, version) async {
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
      },
    );
    await _finalizeOrphanSessions();
  }

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
