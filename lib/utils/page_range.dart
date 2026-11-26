import 'dart:math' as math;
import 'dart:ui';

import '../models/annotation_model.dart';

/// 解析页码范围（1-based，含端点）为升序去重的 0-based 页索引列表。
/// 支持 `1-3,5,7-9`；支持逗号/中文逗号/空格分隔，`-`/`~`/`—` 作连字符。
/// 输入为空、格式错误、越界或倒序返回 null。
List<int>? parsePageRange(String input, int totalPages) {
  final normalized = input
      .trim()
      .replaceAllMapped(RegExp(r'\s*([-~\u2014\uff0d])\s*'), (m) => m.group(1)!);
  if (normalized.isEmpty || totalPages <= 0) return null;
  final pages = <int>{};
  for (final rawToken in normalized.split(RegExp(r'[,\uff0c\s]+'))) {
    if (rawToken.isEmpty) continue;
    final token = rawToken.replaceAll(RegExp(r'[~\u2014\uff0d]'), '-');
    final match = RegExp(r'^(\d+)(?:-(\d+))?$').firstMatch(token);
    if (match == null) return null;
    final from = int.tryParse(match.group(1)!);
    final to = match.group(2) == null ? from : int.tryParse(match.group(2)!);
    if (from == null || to == null) return null;
    if (from < 1 || to < from || to > totalPages) return null;
    for (var p = from; p <= to; p++) {
      pages.add(p - 1);
    }
  }
  if (pages.isEmpty) return null;
  final out = pages.toList()..sort();
  return out;
}

/// 升序页索引按连续段切分：[[0,1,2],[4,5]]
List<List<int>> splitPageSegments(List<int> pages) {
  final segments = <List<int>>[];
  for (final page in pages) {
    if (segments.isNotEmpty && segments.last.last == page - 1) {
      segments.last.add(page);
    } else {
      segments.add([page]);
    }
  }
  return segments;
}

/// 0-based 页索引 -> "1-3,5"
String formatPageRange(List<int> pages) {
  if (pages.isEmpty) return '';
  final sorted = pages.toSet().toList()..sort();
  return splitPageSegments(sorted)
      .map((seg) => seg.length == 1 ? '${seg.first + 1}' : '${seg.first + 1}-${seg.last + 1}')
      .join(',');
}

/// pt -> mm（保留一位小数）
double pointsToMm(double points) {
  return ((points * 25.4 / 72.0) * 10.0).roundToDouble() / 10.0;
}

/// 颜色转换
Color hexToColor(String hex, {double opacity = 1.0}) {
  var clean = hex.replaceAll('#', '').trim();
  if (clean.length == 3) {
    clean = clean.split('').map((c) => '$c$c').join();
  }
  final rgb = int.tryParse(clean, radix: 16) ?? 0xE03131;
  final alpha = (opacity.clamp(0.0, 1.0) * 255).round();
  return Color((alpha << 24) | (rgb & 0xFFFFFF));
}

String colorToHex(Color color) {
  final r = ((color.r * 255.0).round() & 0xFF).toRadixString(16).padLeft(2, '0');
  final g = ((color.g * 255.0).round() & 0xFF).toRadixString(16).padLeft(2, '0');
  final b = ((color.b * 255.0).round() & 0xFF).toRadixString(16).padLeft(2, '0');
  return '#$r$g$b';
}

/// Douglas-Peucker 笔迹抽稀
List<PdfPoint> simplifyPoints(List<PdfPoint> points, {double tolerance = 1.2}) {
  if (points.length <= 2) return points;
  var maxDist = 0.0;
  var index = 0;
  final first = points.first;
  final last = points.last;

  for (var i = 1; i < points.length - 1; i++) {
    final d = _perpDistance(points[i], first, last);
    if (d > maxDist) {
      maxDist = d;
      index = i;
    }
  }

  if (maxDist > tolerance) {
    final left = simplifyPoints(points.sublist(0, index + 1), tolerance: tolerance);
    final right = simplifyPoints(points.sublist(index), tolerance: tolerance);
    return [...left.sublist(0, left.length - 1), ...right];
  }
  return [first, last];
}

double _perpDistance(PdfPoint p, PdfPoint a, PdfPoint b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final lenSq = dx * dx + dy * dy;
  if (lenSq == 0) {
    return hypot(p.x - a.x, p.y - a.y);
  }
  final t = ((p.x - a.x) * dx + (p.y - a.y) * dy) / lenSq;
  final projX = a.x + t.clamp(0.0, 1.0) * dx;
  final projY = a.y + t.clamp(0.0, 1.0) * dy;
  return hypot(p.x - projX, p.y - projY);
}

final RegExp _cjkRegex = RegExp(r'[\u2e80-\u9fff\u3000-\u303f\uff00-\uffef\uac00-\ud7af]');

bool isCjkChar(String char) => _cjkRegex.hasMatch(char);

/// 按可用宽度断行：CJK 逐字断行，拉丁文优先在空格处断行
List<String> wrapText(
  String text,
  double maxWidth,
  double Function(String s) measure,
) {
  if (maxWidth <= 0) return [text];
  final lines = <String>[];
  for (final paragraph in text.split('\n')) {
    var line = '';
    for (final rune in paragraph.runes) {
      final ch = String.fromCharCode(rune);
      if (line.isNotEmpty && measure('$line$ch') > maxWidth) {
        if (ch == ' ') {
          lines.add(line);
          line = '';
          continue;
        }
        final spaceAt = isCjkChar(ch) ? -1 : line.lastIndexOf(' ');
        if (spaceAt > 0) {
          lines.add(line.substring(0, spaceAt));
          line = '${line.substring(spaceAt + 1)}$ch';
        } else {
          lines.add(line);
          line = ch;
        }
      } else {
        line += ch;
      }
    }
    lines.add(line);
  }
  return lines;
}

class TextBlockFrame {
  const TextBlockFrame({
    required this.origin,
    required this.u,
    required this.v,
    required this.run,
    required this.stack,
  });

  final PdfPoint origin;
  final PdfPoint u;
  final PdfPoint v;
  final double run;
  final double stack;
}

TextBlockFrame textBlockFrame(PdfRectBox rect, int rotate) {
  final r = (((rotate / 90).round() * 90) % 360 + 360) % 360;
  final left = rect.x;
  final bottom = rect.y;
  final right = rect.x + rect.w;
  final top = rect.y + rect.h;
  switch (r) {
    case 90:
      return TextBlockFrame(
        origin: PdfPoint(left, bottom),
        u: const PdfPoint(0, 1),
        v: const PdfPoint(1, 0),
        run: rect.h,
        stack: rect.w,
      );
    case 180:
      return TextBlockFrame(
        origin: PdfPoint(right, bottom),
        u: const PdfPoint(-1, 0),
        v: const PdfPoint(0, 1),
        run: rect.w,
        stack: rect.h,
      );
    case 270:
      return TextBlockFrame(
        origin: PdfPoint(right, top),
        u: const PdfPoint(0, -1),
        v: const PdfPoint(-1, 0),
        run: rect.h,
        stack: rect.w,
      );
    default:
      return TextBlockFrame(
        origin: PdfPoint(left, top),
        u: const PdfPoint(1, 0),
        v: const PdfPoint(0, -1),
        run: rect.w,
        stack: rect.h,
      );
  }
}

PdfPoint textLocalToPdf(PdfRectBox rect, int rotate, double localX, double localY) {
  final f = textBlockFrame(rect, rotate);
  return PdfPoint(
    f.origin.x + f.u.x * localX + f.v.x * localY,
    f.origin.y + f.u.y * localX + f.v.y * localY,
  );
}

/// 二分求图章内最大可容纳字号
double fitStampFontSize(
  String label,
  double boxWidth,
  double boxHeight,
  double Function(String s, double size) measure,
) {
  final maxWidth = math.max(boxWidth - 8, 4.0);
  final maxHeight = math.max(boxHeight * 0.62, 4.0);
  var low = 4.0;
  var high = math.max(maxHeight, 4.0);
  for (var i = 0; i < 12; i++) {
    final mid = (low + high) / 2.0;
    if (measure(label, mid) <= maxWidth && mid <= maxHeight) {
      low = mid;
    } else {
      high = mid;
    }
  }
  return low;
}

/// 水印落点网格
List<PdfPoint> watermarkPlacements({
  required double pageWidth,
  required double pageHeight,
  required double textWidth,
  required double textHeight,
  required bool tile,
}) {
  if (!tile) return [PdfPoint(pageWidth / 2, pageHeight / 2)];
  final gapX = textWidth + 40;
  final gapY = textHeight + 40;
  final cols = math.max(1, (pageWidth / gapX).ceil());
  final rows = math.max(1, (pageHeight / gapY).ceil());
  final stepX = pageWidth / cols;
  final stepY = pageHeight / rows;
  final out = <PdfPoint>[];
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < cols; c++) {
      out.add(PdfPoint(stepX * (c + 0.5), stepY * (r + 0.5)));
    }
  }
  return out;
}

double hypot(double a, double b) => math.sqrt(a * a + b * b);
