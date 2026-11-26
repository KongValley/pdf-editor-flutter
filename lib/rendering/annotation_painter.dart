import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/annotation_model.dart';
import '../utils/page_range.dart';

/// 将 PDF 用户空间坐标（原点左下，Y 向上，未经视图旋转）映射到当前显示页面屏幕坐标。
/// [pageSizePt] 为 PDF 页面在视图旋转后的显示宽高（单位 pt）；
/// [rawPageSizePt] 为未经视图旋转的 PDF 页面宽高（含页面自身 /Rotate，或统一按 PDF 原始空间换算）。
class PdfScreenTransform {
  const PdfScreenTransform({
    required this.rawWidthPt,
    required this.rawHeightPt,
    required this.scale,
    required this.viewRotationDeg,
  });

  final double rawWidthPt;
  final double rawHeightPt;
  final double scale;
  final int viewRotationDeg; // 0, 90, 180, 270 clockwise

  int get _rot => ((viewRotationDeg ~/ 90) % 4 + 4) % 4;

  double get displayWidthPx => (_rot.isOdd ? rawHeightPt : rawWidthPt) * scale;
  double get displayHeightPx => (_rot.isOdd ? rawWidthPt : rawHeightPt) * scale;

  /// PDF 用户空间点 (x, y) -> 屏幕坐标 Offset (dx, dy)
  Offset pdfToScreen(PdfPoint p) {
    final sx = p.x * scale;
    final sy = (rawHeightPt - p.y) * scale;
    final w = rawWidthPt * scale;
    final h = rawHeightPt * scale;
    return switch (_rot) {
      1 => Offset(h - sy, sx),
      2 => Offset(w - sx, h - sy),
      3 => Offset(sy, w - sx),
      _ => Offset(sx, sy),
    };
  }

  /// 屏幕坐标 Offset -> PDF 用户空间点
  PdfPoint screenToPdf(Offset o) {
    final w = rawWidthPt * scale;
    final h = rawHeightPt * scale;
    late final double sx;
    late final double sy;
    switch (_rot) {
      case 1:
        sx = o.dy;
        sy = h - o.dx;
        break;
      case 2:
        sx = w - o.dx;
        sy = h - o.dy;
        break;
      case 3:
        sx = w - o.dy;
        sy = o.dx;
        break;
      default:
        sx = o.dx;
        sy = o.dy;
    }
    return PdfPoint(sx / scale, rawHeightPt - (sy / scale));
  }

  Rect pdfRectToScreen(PdfRectBox box) {
    final p1 = pdfToScreen(PdfPoint(box.x, box.y));
    final p2 = pdfToScreen(PdfPoint(box.right, box.top));
    return Rect.fromLTRB(
      math.min(p1.dx, p2.dx),
      math.min(p1.dy, p2.dy),
      math.max(p1.dx, p2.dx),
      math.max(p1.dy, p2.dy),
    );
  }
}

/// 统一绘制单条批注到 Canvas（用于实时页面叠加层、导出图片、打印渲染）
void paintAnnotationOnCanvas({
  required Canvas canvas,
  required PdfScreenTransform transform,
  required PdfAnnotationItem ann,
  Map<String, ui.Image> loadedImages = const {},
  Offset dragOffsetScreen = Offset.zero,
}) {
  canvas.save();
  if (dragOffsetScreen != Offset.zero) {
    canvas.translate(dragOffsetScreen.dx, dragOffsetScreen.dy);
  }

  final color = hexToColor(ann.color, opacity: ann.opacity);
  final scale = transform.scale;
  final rect = transform.pdfRectToScreen(ann.bbox);

  switch (ann.kind) {
    case AnnotationKind.highlight:
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.fill
        ..blendMode = BlendMode.multiply;
      canvas.drawRect(rect, paint);
      break;

    case AnnotationKind.rect:
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = ann.thickness * scale;
      canvas.drawRect(rect, paint);
      break;

    case AnnotationKind.ellipse:
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = ann.thickness * scale;
      canvas.drawOval(rect, paint);
      break;

    case AnnotationKind.ink:
      if (ann.points.length >= 2) {
        final path = Path();
        final p0 = transform.pdfToScreen(ann.points.first);
        path.moveTo(p0.dx, p0.dy);
        for (var i = 1; i < ann.points.length; i++) {
          final pi = transform.pdfToScreen(ann.points[i]);
          path.lineTo(pi.dx, pi.dy);
        }
        final paint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = ann.thickness * scale
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawPath(path, paint);
      }
      break;

    case AnnotationKind.arrow:
      final fromPt = ann.from ?? PdfPoint(ann.bbox.x, ann.bbox.y);
      final toPt = ann.to ?? PdfPoint(ann.bbox.right, ann.bbox.top);
      final from = transform.pdfToScreen(fromPt);
      final to = transform.pdfToScreen(toPt);
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = ann.thickness * scale
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(from, to, paint);

      final dx = to.dx - from.dx;
      final dy = to.dy - from.dy;
      final len = math.max(hypot(dx, dy), 1.0);
      final wing = math.max(6.0, len * 0.14);
      final angle = math.atan2(dy, dx);
      const spread = 0.45;
      final headPath = Path()
        ..moveTo(to.dx, to.dy)
        ..lineTo(
          to.dx - wing * math.cos(angle - spread),
          to.dy - wing * math.sin(angle - spread),
        )
        ..lineTo(
          to.dx - wing * math.cos(angle + spread),
          to.dy - wing * math.sin(angle + spread),
        )
        ..close();
      canvas.drawPath(
        headPath,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
      break;

    case AnnotationKind.measure:
      final fromPt = ann.from ?? PdfPoint(ann.bbox.x, ann.bbox.y);
      final toPt = ann.to ?? PdfPoint(ann.bbox.right, ann.bbox.top);
      final from = transform.pdfToScreen(fromPt);
      final to = transform.pdfToScreen(toPt);
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = ann.thickness * scale
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(from, to, paint);
      final dx = to.dx - from.dx;
      final dy = to.dy - from.dy;
      final lineLen = math.sqrt(dx * dx + dy * dy);
      if (lineLen > 1) {
        final nx = -dy / lineLen * 4.5 * scale;
        final ny = dx / lineLen * 4.5 * scale;
        canvas.drawLine(
          Offset(from.dx - nx, from.dy - ny),
          Offset(from.dx + nx, from.dy + ny),
          paint,
        );
        canvas.drawLine(
          Offset(to.dx - nx, to.dy - ny),
          Offset(to.dx + nx, to.dy + ny),
          paint,
        );
      }

      final distPt = hypot(toPt.x - fromPt.x, toPt.y - fromPt.y);
      final label = '${pointsToMm(distPt).toStringAsFixed(1)} mm';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: color,
            fontSize: math.max(9.0, 11.0 * scale),
            fontWeight: FontWeight.w600,
            backgroundColor: Colors.white.withValues(alpha: 0.78),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
      var angle = math.atan2(dy, dx);
      if (angle > math.pi / 2 || angle < -math.pi / 2) {
        angle += math.pi;
      }
      canvas.save();
      canvas.translate(mid.dx, mid.dy);
      canvas.rotate(angle);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height - 4));
      canvas.restore();
      break;

    case AnnotationKind.text:
      if (ann.text.isNotEmpty) {
        final frame = textBlockFrame(ann.bbox, ann.rotate);
        final fontFamily =
            (ann.fontFamily != null && ann.fontFamily!.isNotEmpty)
                ? ann.fontFamily
                : null;
        double measure(String s) {
          if (s.isEmpty) return 0;
          final tp = TextPainter(
            text: TextSpan(
              text: s,
              style: TextStyle(
                fontSize: ann.fontSize,
                fontFamily: fontFamily,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          return tp.width;
        }

        final lines = wrapText(ann.text, math.max(frame.run, 8), measure);
        final lineHeight = ann.fontSize * 1.2;
        final screenAngleDeg =
            ((transform.viewRotationDeg - ann.rotate) % 360 + 360) % 360;
        final rad = screenAngleDeg * math.pi / 180.0;

        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.isEmpty) continue;
          final topLeftPdf = textLocalToPdf(
            ann.bbox,
            ann.rotate,
            0,
            i * lineHeight,
          );
          final pos = transform.pdfToScreen(topLeftPdf);
          final tp = TextPainter(
            text: TextSpan(
              text: line,
              style: TextStyle(
                color: color,
                fontSize: ann.fontSize * scale,
                fontFamily: fontFamily,
                height: 1.2,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          canvas.save();
          canvas.translate(pos.dx, pos.dy);
          if (screenAngleDeg != 0) canvas.rotate(rad);
          tp.paint(canvas, Offset.zero);
          canvas.restore();
        }
      }
      break;

    case AnnotationKind.note:
      final noteFill = Paint()
        ..color = color
        ..style = PaintingStyle.fill;
      final noteBorder = Paint()
        ..color = const Color(0xFF8A6D1B).withValues(alpha: ann.opacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0, 1.2 * scale);
      final rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(3.0 * scale),
      );
      canvas.drawRRect(rrect, noteFill);
      canvas.drawRRect(rrect, noteBorder);
      // 小横线图标细节
      if (rect.width > 12 && rect.height > 12) {
        final linePaint = Paint()
          ..color = const Color(0xFF5C460E).withValues(alpha: ann.opacity)
          ..strokeWidth = math.max(1.0, 1.1 * scale);
        for (var k = 0; k < 3; k++) {
          final ly = rect.top + rect.height * (0.3 + k * 0.2);
          canvas.drawLine(
            Offset(rect.left + rect.width * 0.2, ly),
            Offset(rect.right - rect.width * 0.2, ly),
            linePaint,
          );
        }
      }
      break;

    case AnnotationKind.stamp:
      final bg = Paint()
        ..color = color.withValues(alpha: 0.08 * ann.opacity)
        ..style = PaintingStyle.fill;
      final border = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * scale;
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(4.0 * scale));
      canvas.drawRRect(rrect, bg);
      canvas.drawRRect(rrect, border);

      if (ann.label.isNotEmpty) {
        final frame = textBlockFrame(ann.bbox, ann.rotate);
        final fontFamily =
            (ann.fontFamily != null && ann.fontFamily!.isNotEmpty)
                ? ann.fontFamily
                : null;
        double measureStamp(String s, double size) {
          final tp = TextPainter(
            text: TextSpan(
              text: s,
              style: TextStyle(
                fontSize: size,
                fontFamily: fontFamily,
                fontWeight: FontWeight.w700,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          return tp.width;
        }

        final fontSizePt = fitStampFontSize(
          ann.label,
          frame.run,
          frame.stack,
          measureStamp,
        );
        final tp = TextPainter(
          text: TextSpan(
            text: ann.label,
            style: TextStyle(
              color: color,
              fontSize: fontSizePt * scale,
              fontFamily: fontFamily,
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final center = rect.center;
        final screenAngleDeg =
            ((transform.viewRotationDeg - ann.rotate) % 360 + 360) % 360;
        canvas.save();
        canvas.translate(center.dx, center.dy);
        if (screenAngleDeg != 0) {
          canvas.rotate(screenAngleDeg * math.pi / 180.0);
        }
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        canvas.restore();
      }
      break;

    case AnnotationKind.image:
      final uiImg = loadedImages[ann.imgId];
      final screenAngleDeg =
          ((transform.viewRotationDeg - ann.rotate) % 360 + 360) % 360;
      canvas.save();
      canvas.translate(rect.center.dx, rect.center.dy);
      if (screenAngleDeg != 0) {
        canvas.rotate(screenAngleDeg * math.pi / 180.0);
      }
      final swapped = screenAngleDeg == 90 || screenAngleDeg == 270;
      final drawW = swapped ? rect.height : rect.width;
      final drawH = swapped ? rect.width : rect.height;
      final localRect = Rect.fromCenter(
        center: Offset.zero,
        width: drawW,
        height: drawH,
      );
      if (uiImg != null) {
        final srcRect = Rect.fromLTWH(
          0,
          0,
          uiImg.width.toDouble(),
          uiImg.height.toDouble(),
        );
        final paint = Paint()
          ..color = Colors.white.withValues(alpha: ann.opacity)
          ..filterQuality = FilterQuality.medium;
        canvas.drawImageRect(uiImg, srcRect, localRect, paint);
      } else {
        canvas.drawRect(
          localRect,
          Paint()
            ..color = Colors.grey.withValues(alpha: 0.35)
            ..style = PaintingStyle.fill,
        );
        canvas.drawRect(
          localRect,
          Paint()
            ..color = Colors.grey
            ..style = PaintingStyle.stroke,
        );
      }
      canvas.restore();
      break;
  }

  canvas.restore();
}

enum ResizeHandle {
  none,
  topLeft,
  topCenter,
  topRight,
  middleLeft,
  middleRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
  endpointFrom,
  endpointTo,
}

List<({ResizeHandle handle, Offset center})> handlesForAnnotation(
  PdfAnnotationItem ann,
  PdfScreenTransform transform,
) {
  if (ann.kind == AnnotationKind.arrow || ann.kind == AnnotationKind.measure) {
    final from = transform.pdfToScreen(
      ann.from ?? PdfPoint(ann.bbox.x, ann.bbox.y),
    );
    final to = transform.pdfToScreen(
      ann.to ?? PdfPoint(ann.bbox.right, ann.bbox.top),
    );
    return [
      (handle: ResizeHandle.endpointFrom, center: from),
      (handle: ResizeHandle.endpointTo, center: to),
    ];
  }
  final r = transform.pdfRectToScreen(ann.effectiveBounds);
  return [
    (handle: ResizeHandle.topLeft, center: r.topLeft),
    (handle: ResizeHandle.topCenter, center: r.topCenter),
    (handle: ResizeHandle.topRight, center: r.topRight),
    (handle: ResizeHandle.middleLeft, center: r.centerLeft),
    (handle: ResizeHandle.middleRight, center: r.centerRight),
    (handle: ResizeHandle.bottomLeft, center: r.bottomLeft),
    (handle: ResizeHandle.bottomCenter, center: r.bottomCenter),
    (handle: ResizeHandle.bottomRight, center: r.bottomRight),
  ];
}

class AnnotationOverlayPainter extends CustomPainter {
  const AnnotationOverlayPainter({
    required this.transform,
    required this.annotations,
    required this.selectedIds,
    required this.loadedImages,
    this.movingIds = const {},
    this.moveOffsetScreen = Offset.zero,
    this.draftAnnotation,
    this.editingAnnotationId,
    this.searchHighlights = const [],
    this.activeSearchIndex = -1,
  });

  final PdfScreenTransform transform;
  final List<PdfAnnotationItem> annotations;
  final Set<String> selectedIds;
  final Map<String, ui.Image> loadedImages;
  final Set<String> movingIds;
  final Offset moveOffsetScreen;
  final PdfAnnotationItem? draftAnnotation;
  final String? editingAnnotationId;
  final List<({Rect rect, bool isCurrent})> searchHighlights;
  final int activeSearchIndex;

  @override
  void paint(Canvas canvas, Size size) {
    // 1. 搜索命中高亮
    for (final hit in searchHighlights) {
      final paint = Paint()
        ..color = hit.isCurrent
            ? const Color(0x88FF7A00)
            : const Color(0x66FFE033)
        ..style = PaintingStyle.fill;
      canvas.drawRect(hit.rect, paint);
    }

    // 2. 已提交批注
    for (final ann in annotations) {
      if (ann.id == editingAnnotationId) continue;
      final offset =
          movingIds.contains(ann.id) ? moveOffsetScreen : Offset.zero;
      paintAnnotationOnCanvas(
        canvas: canvas,
        transform: transform,
        ann: ann,
        loadedImages: loadedImages,
        dragOffsetScreen: offset,
      );
    }

    // 3. 正在绘制中的草稿批注
    if (draftAnnotation != null) {
      paintAnnotationOnCanvas(
        canvas: canvas,
        transform: transform,
        ann: draftAnnotation!,
        loadedImages: loadedImages,
      );
    }

    // 4. 选中框与控制手柄
    for (final ann in annotations) {
      if (!selectedIds.contains(ann.id)) continue;
      final offset =
          movingIds.contains(ann.id) ? moveOffsetScreen : Offset.zero;
      canvas.save();
      if (offset != Offset.zero) canvas.translate(offset.dx, offset.dy);

      final bounds = transform.pdfRectToScreen(ann.effectiveBounds);
      final selPaint = Paint()
        ..color = ann.locked ? const Color(0xFF94A3B8) : const Color(0xFF2563EB)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4;
      canvas.drawRect(bounds.inflate(2), selPaint);

      if (selectedIds.length == 1 && !ann.locked) {
        final handles = handlesForAnnotation(ann, transform);
        for (final h in handles) {
          final isEndpoint = h.handle == ResizeHandle.endpointFrom ||
              h.handle == ResizeHandle.endpointTo;
          if (isEndpoint) {
            canvas.drawCircle(
              h.center,
              5.0,
              Paint()..color = Colors.white,
            );
            canvas.drawCircle(
              h.center,
              5.0,
              Paint()
                ..color = const Color(0xFF2563EB)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.8,
            );
          } else {
            final hr = Rect.fromCenter(center: h.center, width: 8, height: 8);
            canvas.drawRect(hr, Paint()..color = Colors.white);
            canvas.drawRect(
              hr,
              Paint()
                ..color = const Color(0xFF2563EB)
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.5,
            );
          }
        }
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant AnnotationOverlayPainter oldDelegate) {
    return true;
  }
}
