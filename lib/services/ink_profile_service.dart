import 'dart:math' as math;
import 'dart:typed_data';

import '../models/document_models.dart';

const int kProfileBins = 128;

class RowProfile {
  const RowProfile({required this.page, required this.rows});
  final int page;
  final List<double> rows;
}

class InkMap {
  const InkMap({required this.rows, required this.cols});
  final List<double> rows;
  final List<double> cols;
}

class InkProfileAnalyzer {
  InkProfileAnalyzer._();

  static const double _minInk = 0.02;
  static const double _margin = 0.1;
  static const double _minCorrelation = 0.05;
  static const int _minSamples = 3;
  static const double _squareRatio = 0.02;

  static PageOrientationKind orientationOf(double w, double h) {
    final longest = math.max(w.abs(), h.abs());
    if (longest == 0) return PageOrientationKind.square;
    if ((w - h).abs() <= longest * _squareRatio) {
      return PageOrientationKind.square;
    }
    return w > h ? PageOrientationKind.landscape : PageOrientationKind.portrait;
  }

  static PageOrientationKind? pickBaseOrientation(
      List<PageOrientationKind> orientations) {
    var portrait = 0;
    var landscape = 0;
    for (final o in orientations) {
      if (o == PageOrientationKind.portrait) portrait++;
      if (o == PageOrientationKind.landscape) landscape++;
    }
    if (portrait == landscape) return null;
    return portrait > landscape
        ? PageOrientationKind.portrait
        : PageOrientationKind.landscape;
  }

  static InkMap extractInkFromBgra(Uint8List bgra, int width, int height) {
    final rows = List<double>.filled(height, 0);
    final cols = List<double>.filled(width, 0);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        final b = bgra[i];
        final g = bgra[i + 1];
        final r = bgra[i + 2];
        final dark = 255.0 - (r * 0.299 + g * 0.587 + b * 0.114);
        if (dark < 40) continue;
        rows[y] += dark;
        cols[x] += dark;
      }
    }
    return InkMap(rows: rows, cols: cols);
  }

  static double _variance(List<double> values) {
    if (values.isEmpty) return 0;
    var sum = 0.0;
    for (final v in values) {
      sum += v;
    }
    final mean = sum / values.length;
    var acc = 0.0;
    for (final v in values) {
      final d = v - mean;
      acc += d * d;
    }
    return acc / values.length;
  }

  /// 正立文字在行方向起伏更明显（score > 2），横躺则列方向起伏更明显（score < 0.5）
  static bool? uprightFromPixels(InkMap ink) {
    final rowVar = _variance(ink.rows);
    final colVar = _variance(ink.cols);
    if (rowVar == 0 && colVar == 0) return null;
    final score = rowVar / math.max(colVar, 1e-6);
    if (score > 2.0) return true;
    if (score < 0.5) return false;
    return null;
  }

  static double inkShare(List<double> rows) {
    if (rows.isEmpty) return 0;
    var maxVal = 0.0;
    var sum = 0.0;
    for (final v in rows) {
      if (v > maxVal) maxVal = v;
      sum += v;
    }
    return maxVal > 0 ? (sum / rows.length) / maxVal : 0;
  }

  static List<double> normalizeProfile(List<double> rows,
      [int bins = kProfileBins]) {
    final len = rows.length;
    if (len == 0) return List<double>.filled(bins, 0);
    final out = <double>[];
    for (var i = 0; i < bins; i++) {
      final from = (i * len) ~/ bins;
      final to = math.max(from + 1, ((i + 1) * len) ~/ bins);
      var sum = 0.0;
      for (var j = from; j < to && j < len; j++) {
        sum += rows[j];
      }
      out.add(sum / (to - from));
    }
    var sum = 0.0;
    for (final v in out) {
      sum += v;
    }
    final mean = sum / out.length;
    var acc = 0.0;
    for (final v in out) {
      acc += (v - mean) * (v - mean);
    }
    final std = math.sqrt(acc / out.length);
    final normStd = std == 0 ? 1.0 : std;
    return out.map((v) => (v - mean) / normStd).toList();
  }

  static double correlation(List<double> a, List<double> b) {
    final n = math.min(a.length, b.length);
    if (n == 0) return 0;
    var meanA = 0.0;
    var meanB = 0.0;
    for (var i = 0; i < n; i++) {
      meanA += a[i];
      meanB += b[i];
    }
    meanA /= n;
    meanB /= n;
    var dot = 0.0;
    var varA = 0.0;
    var varB = 0.0;
    for (var i = 0; i < n; i++) {
      final x = a[i] - meanA;
      final y = b[i] - meanB;
      dot += x * y;
      varA += x * x;
      varB += y * y;
    }
    final denom = math.sqrt(varA * varB);
    return denom > 0 ? dot / denom : 0;
  }

  static double _median(List<double> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length >> 1;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2.0;
  }

  static List<double>? consensusProfile(List<RowProfile> profiles) {
    final usable =
        profiles.where((p) => inkShare(p.rows) >= _minInk).toList();
    if (usable.length < _minSamples) return null;
    final normalized = usable.map((p) => normalizeProfile(p.rows)).toList();
    return List<double>.generate(
      kProfileBins,
      (idx) => _median(normalized.map((z) => z[idx]).toList()),
    );
  }

  static List<int> invertedPages(List<RowProfile> profiles) {
    final ref = consensusProfile(profiles);
    if (ref == null) return const [];
    final flagged = <int>[];
    for (final p in profiles) {
      if (inkShare(p.rows) < _minInk) continue;
      final z = normalizeProfile(p.rows);
      final asIs = correlation(z, ref);
      final mirrored = correlation(z.reversed.toList(), ref);
      if (mirrored - asIs >= _margin && mirrored > _minCorrelation) {
        flagged.add(p.page);
      }
    }
    return flagged;
  }

  static int sidewaysDirection(
      List<RowProfile> profiles, List<double> columns) {
    final ref = consensusProfile(profiles);
    if (ref == null) return 0;
    final z = normalizeProfile(columns);
    final cw = correlation(z, ref);
    final ccw = correlation(z.reversed.toList(), ref);
    if (cw - ccw >= _margin && cw > _minCorrelation) return 90;
    if (ccw - cw >= _margin && ccw > _minCorrelation) return 270;
    return 0;
  }
}
