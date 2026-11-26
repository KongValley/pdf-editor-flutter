import '../models/document_models.dart';
import 'ink_profile_service.dart';
import 'native_bridge.dart';
import 'pdf_engine_service.dart';

class OrientationService {
  OrientationService._();

  static const double _ocrMinConfidence = 10.0;

  static int _deltaFromTextAngle(int angle) {
    if (angle == 0) return 0;
    if (angle == 180) return 180;
    return angle == 90 ? 270 : 90;
  }

  static Future<OrientationPlanResult> analyzeDocument({
    required String filePath,
    required List<({double w, double h})> pageSizes,
    String? password,
    void Function(int current, int total)? onProgress,
  }) async {
    final orientations = pageSizes
        .map((s) => InkProfileAnalyzer.orientationOf(s.w, s.h))
        .toList();
    final base = InkProfileAnalyzer.pickBaseOrientation(orientations);
    if (base == null) {
      return const OrientationPlanResult(
        base: null,
        baseError: '横向页与纵向页数量相同，无法判定基准方向',
      );
    }

    final flipped = base == PageOrientationKind.portrait
        ? PageOrientationKind.landscape
        : PageOrientationKind.portrait;
    final items = <OrientationPlanItem>[];

    // 第 1 步：批量从 PDFium 读每页文字角度
    final textAngles = await PdfEngineService.detectAllPageTextAngles(
      filePath,
      password: password,
    );

    final inkCandidates = <({
      int page,
      PageOrientationKind from,
      bool? upright,
      List<double>? columns,
    })>[];
    final inkBasePages = <int>[];

    for (var i = 0; i < orientations.length; i++) {
      final page = i + 1;
      onProgress?.call(page, orientations.length);
      final from = orientations[i];
      if (from == PageOrientationKind.square) continue;
      final angle = i < textAngles.length ? textAngles[i] : null;

      if (from == base) {
        if (angle == 180) {
          items.add(OrientationPlanItem(
            page: page,
            from: from,
            to: base,
            delta: 180,
            reason: OrientationReason.textInverted,
          ));
        } else if (angle == 90 || angle == 270) {
          items.add(OrientationPlanItem(
            page: page,
            from: from,
            to: flipped,
            delta: _deltaFromTextAngle(angle!),
            reason: OrientationReason.textSideways,
          ));
        } else if (angle == null) {
          inkBasePages.add(page);
        }
        continue;
      }

      if (angle != null) {
        final reason = angle == 0
            ? OrientationReason.pageOnly
            : angle == 180
                ? OrientationReason.textInverted
                : OrientationReason.textSideways;
        items.add(OrientationPlanItem(
          page: page,
          from: from,
          to: base,
          delta: _deltaFromTextAngle(angle),
          reason: reason,
        ));
        continue;
      }

      final bmp = await PdfEngineService.renderPageBgra(
        filePath: filePath,
        pageIndexZeroBased: i,
        maxSideOrScale: 160,
        byScale: false,
        includePdfAnnotations: false,
        password: password,
      );
      final ink = bmp == null
          ? null
          : InkProfileAnalyzer.extractInkFromBgra(
              bmp.bgra,
              bmp.width,
              bmp.height,
            );
      inkCandidates.add((
        page: page,
        from: from,
        upright: ink == null ? null : InkProfileAnalyzer.uprightFromPixels(ink),
        columns: ink?.cols,
      ));
    }

    // 第 2 步：对纯图片页走 Windows.Media.Ocr + 全篇行墨迹剖面共识
    if (inkCandidates.isNotEmpty || inkBasePages.isNotEmpty) {
      final profiles = <RowProfile>[];
      final baseInk = <int, InkMap>{};
      final basePending = inkBasePages.toSet();

      for (var i = 0; i < orientations.length; i++) {
        if (orientations[i] != base) continue;
        final bmp = await PdfEngineService.renderPageBgra(
          filePath: filePath,
          pageIndexZeroBased: i,
          maxSideOrScale: 160,
          byScale: false,
          includePdfAnnotations: false,
          password: password,
        );
        if (bmp == null) continue;
        final ink = InkProfileAnalyzer.extractInkFromBgra(
          bmp.bgra,
          bmp.width,
          bmp.height,
        );
        profiles.add(RowProfile(page: i + 1, rows: ink.rows));
        if (basePending.contains(i + 1)) baseInk[i + 1] = ink;
      }

      final reference = InkProfileAnalyzer.consensusProfile(profiles);
      if (reference != null) {
        for (final p in InkProfileAnalyzer.invertedPages(profiles)) {
          if (!basePending.contains(p)) continue;
          final ink = baseInk[p];
          if (ink != null &&
              InkProfileAnalyzer.uprightFromPixels(ink) == false) {
            continue;
          }
          items.add(OrientationPlanItem(
            page: p,
            from: base,
            to: base,
            delta: 180,
            reason: OrientationReason.textInverted,
          ));
        }
      }

      Future<int?> ocrDelta(int page) async {
        final bmp = await PdfEngineService.renderPageBgra(
          filePath: filePath,
          pageIndexZeroBased: page - 1,
          maxSideOrScale: 1200,
          byScale: false,
          includePdfAnnotations: false,
          password: password,
        );
        if (bmp == null) return null;
        final res = await NativeBridge.detectOcrOrientation(
          bgraBytes: bmp.bgra,
          width: bmp.width,
          height: bmp.height,
        );
        if (!res.ok) return null;
        if (res.delta != 0 && res.confidence < _ocrMinConfidence) return null;
        return res.delta;
      }

      for (final page in inkBasePages) {
        final ink = baseInk[page];
        final upright =
            ink == null ? null : InkProfileAnalyzer.uprightFromPixels(ink);
        if (upright == false) {
          final fromOcr = await ocrDelta(page);
          final delta = (fromOcr == 90 || fromOcr == 270)
              ? fromOcr!
              : (ink != null
                  ? (InkProfileAnalyzer.sidewaysDirection(profiles, ink.cols) == 0
                      ? 90
                      : InkProfileAnalyzer.sidewaysDirection(profiles, ink.cols))
                  : 90);
          items.add(OrientationPlanItem(
            page: page,
            from: base,
            to: flipped,
            delta: delta,
            reason: OrientationReason.textSideways,
          ));
          continue;
        }
        if (reference != null) continue;
        final delta = await ocrDelta(page);
        if (delta == null || delta == 0) continue;
        items.add(OrientationPlanItem(
          page: page,
          from: base,
          to: delta == 180 ? base : flipped,
          delta: delta,
          reason: OrientationReason.ocr,
        ));
      }

      for (final cand in inkCandidates) {
        final delta = await ocrDelta(cand.page);
        if (delta != null) {
          items.add(OrientationPlanItem(
            page: cand.page,
            from: cand.from,
            to: base,
            delta: delta,
            reason:
                delta == 0 ? OrientationReason.pageOnly : OrientationReason.ocr,
          ));
          continue;
        }
        final cols = cand.upright == false ? cand.columns : null;
        final dir = cols != null && reference != null
            ? InkProfileAnalyzer.sidewaysDirection(profiles, cols)
            : 0;
        items.add(OrientationPlanItem(
          page: cand.page,
          from: cand.from,
          to: base,
          delta: cols != null ? (dir == 0 ? 90 : dir) : 0,
          reason: cols != null
              ? OrientationReason.textSideways
              : (cand.upright == true
                  ? OrientationReason.pageOnly
                  : OrientationReason.contentUnknown),
        ));
      }
    }

    items.sort((a, b) => a.page - b.page);
    return OrientationPlanResult(base: base, items: items);
  }
}
