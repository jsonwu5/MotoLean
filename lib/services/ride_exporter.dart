import '../models/ride_sample.dart';
import '../models/ride_session.dart';

class RideExporter {
  /// UTF-8 BOM so Excel opens Chinese content correctly.
  static String buildCsv(RideSession session, List<RideSample> samples) {
    final buffer = StringBuffer('\uFEFF');
    buffer.writeln(
      'time,elapsed_s,lat,lon,altitude_m,speed_kmh,lean_deg,accuracy_m',
    );
    for (final sample in samples) {
      final time = session.startedAt
          .add(Duration(milliseconds: sample.tMs))
          .toUtc()
          .toIso8601String();
      buffer.writeln([
        time,
        (sample.tMs / 1000).toStringAsFixed(0),
        sample.lat?.toStringAsFixed(7) ?? '',
        sample.lon?.toStringAsFixed(7) ?? '',
        sample.altitudeM?.toStringAsFixed(1) ?? '',
        sample.speedKmh?.toStringAsFixed(1) ?? '',
        sample.leanDeg.toStringAsFixed(1),
        sample.accuracyM?.toStringAsFixed(1) ?? '',
      ].join(','));
    }
    return buffer.toString();
  }

  static String buildGpx(RideSession session, List<RideSample> samples) {
    final name = session.isDemo
        ? 'MotoLean 演示行程'
        : 'MotoLean ${_dateLabel(session.startedAt)}';
    final buffer = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln(
        '<gpx version="1.1" creator="MotoLean" '
        'xmlns="http://www.topografix.com/GPX/1/1" '
        'xmlns:ml="https://motolean.app/gpx">',
      )
      ..writeln('  <metadata>')
      ..writeln('    <name>${_escape(name)}</name>')
      ..writeln(
        '    <time>${session.startedAt.toUtc().toIso8601String()}</time>',
      )
      ..writeln('  </metadata>')
      ..writeln('  <trk>')
      ..writeln('    <name>${_escape(name)}</name>')
      ..writeln('    <type>motorcycle</type>');

    var segmentOpen = false;
    int? previousTMs;
    for (final sample in samples.where((s) => s.hasPosition)) {
      final split = previousTMs != null && sample.tMs - previousTMs > 30000;
      if (!segmentOpen || split) {
        if (segmentOpen) {
          buffer.writeln('    </trkseg>');
        }
        buffer.writeln('    <trkseg>');
        segmentOpen = true;
      }
      previousTMs = sample.tMs;

      final time = session.startedAt
          .add(Duration(milliseconds: sample.tMs))
          .toUtc()
          .toIso8601String();
      buffer.writeln(
        '      <trkpt lat="${sample.lat!.toStringAsFixed(7)}" '
        'lon="${sample.lon!.toStringAsFixed(7)}">',
      );
      if (sample.altitudeM != null) {
        buffer.writeln(
          '        <ele>${sample.altitudeM!.toStringAsFixed(1)}</ele>',
        );
      }
      buffer.writeln('        <time>$time</time>');
      buffer.writeln('        <extensions>');
      if (sample.speedKmh != null) {
        buffer.writeln(
          '          <ml:speed_kmh>${sample.speedKmh!.toStringAsFixed(1)}</ml:speed_kmh>',
        );
      }
      buffer.writeln(
        '          <ml:lean_deg>${sample.leanDeg.toStringAsFixed(1)}</ml:lean_deg>',
      );
      buffer.writeln('        </extensions>');
      buffer.writeln('      </trkpt>');
    }
    if (segmentOpen) {
      buffer.writeln('    </trkseg>');
    }
    buffer
      ..writeln('  </trk>')
      ..writeln('</gpx>');
    return buffer.toString();
  }

  static String _dateLabel(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
