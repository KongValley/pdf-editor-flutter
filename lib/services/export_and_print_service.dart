import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/annotation_model.dart';
import '../models/document_models.dart';
import '../rendering/annotation_painter.dart';
import '../services/native_bridge.dart';
import '../services/pdf_engine_service.dart';
import '../services/recent_and_log_service.dart';

class ExportImagesResult {
  const ExportImagesResult({
    required this.ok,
    this.savedPaths = const [],
    this.error,
    this.downscalePercent,
  });

  final bool ok;
  final List<String> savedPaths;
  final String? error;
  final int? downscalePercent;
}

class ExportAndPrintService {
  ExportAndPrintService._();

  static const int _maxLongSide = 65535;
  static const int _longImageBudgetBytes = 256 * 1024 * 1024;

  static Future<ui.Image> _bgraToUiImage(
      Uint8List bgra, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bgra,
      width,
      height,
      ui.PixelFormat.bgra8888,
      completer.complete,
    );
    return completer.future;
  }

  /// 渲染单页（含可选批注）并输出编码后的 PNG 字节及像素尺寸
  static Future<({Uint8List pngBytes, int width, int height})?>
      renderPagePng({
    required String filePath,
    required int pageIndex,
    required double scale,
    required int viewRotationDeg,
    required int pageRotationDeg,
    required double pageDisplayWidthPt,
    required double pageDisplayHeightPt,
    required bool includeAnnotations,
    required List<PdfAnnotationItem> pageAnnotations,
    required Map<String, ui.Image> loadedImages,
    String? password,
  }) async {
    final rotSteps = ((viewRotationDeg ~/ 90) % 4 + 4) % 4;
    final rendered = await PdfEngineService.renderPageBgra(
      filePath: filePath,
      pageIndexZeroBased: pageIndex,
      maxSideOrScale: scale,
      byScale: true,
      rotationSteps: rotSteps,
      includePdfAnnotations: includeAnnotations,
      skipPdEditorAnnots: includeAnnotations,
      password: password,
    );
    if (rendered == null) return null;

    final baseImg =
        await _bgraToUiImage(rendered.bgra, rendered.width, rendered.height);
    try {
      if (!includeAnnotations || pageAnnotations.isEmpty) {
        final byteData =
            await baseImg.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) return null;
        return (
          pngBytes: byteData.buffer.asUint8List(),
          width: rendered.width,
          height: rendered.height,
        );
      }

      final pageRotSteps = ((pageRotationDeg ~/ 90) % 4 + 4) % 4;
      final rawWidthPt =
          pageRotSteps.isOdd ? pageDisplayHeightPt : pageDisplayWidthPt;
      final rawHeightPt =
          pageRotSteps.isOdd ? pageDisplayWidthPt : pageDisplayHeightPt;
      final totalRotDeg = (pageRotationDeg + viewRotationDeg) % 360;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(baseImg, Offset.zero, Paint());
      final transform = PdfScreenTransform(
        rawWidthPt: rawWidthPt,
        rawHeightPt: rawHeightPt,
        scale: scale,
        viewRotationDeg: totalRotDeg,
      );
      for (final ann in pageAnnotations) {
        paintAnnotationOnCanvas(
          canvas: canvas,
          transform: transform,
          ann: ann,
          loadedImages: loadedImages,
        );
      }
      final picture = recorder.endRecording();
      final composed =
          await picture.toImage(rendered.width, rendered.height);
      picture.dispose();
      try {
        final byteData =
            await composed.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) return null;
        return (
          pngBytes: byteData.buffer.asUint8List(),
          width: rendered.width,
          height: rendered.height,
        );
      } finally {
        composed.dispose();
      }
    } finally {
      baseImg.dispose();
    }
  }

  /// 渲染单页带批注合成的原始 BGRA 字节（给 Win32 GDI 原生打印）
  static Future<({Uint8List bgra, int width, int height})?>
      renderPageBgraWithAnnotations({
    required String filePath,
    required int pageIndex,
    required double scale,
    required int viewRotationDeg,
    required int pageRotationDeg,
    required double pageDisplayWidthPt,
    required double pageDisplayHeightPt,
    required bool includeAnnotations,
    required List<PdfAnnotationItem> pageAnnotations,
    required Map<String, ui.Image> loadedImages,
    String? password,
  }) async {
    final rotSteps = ((viewRotationDeg ~/ 90) % 4 + 4) % 4;
    final rendered = await PdfEngineService.renderPageBgra(
      filePath: filePath,
      pageIndexZeroBased: pageIndex,
      maxSideOrScale: scale,
      byScale: true,
      rotationSteps: rotSteps,
      includePdfAnnotations: includeAnnotations,
      skipPdEditorAnnots: includeAnnotations,
      password: password,
    );
    if (rendered == null) return null;
    if (!includeAnnotations || pageAnnotations.isEmpty) {
      return rendered;
    }

    final baseImg =
        await _bgraToUiImage(rendered.bgra, rendered.width, rendered.height);
    try {
      final pageRotSteps = ((pageRotationDeg ~/ 90) % 4 + 4) % 4;
      final rawWidthPt =
          pageRotSteps.isOdd ? pageDisplayHeightPt : pageDisplayWidthPt;
      final rawHeightPt =
          pageRotSteps.isOdd ? pageDisplayWidthPt : pageDisplayHeightPt;
      final totalRotDeg = (pageRotationDeg + viewRotationDeg) % 360;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawImage(baseImg, Offset.zero, Paint());
      final transform = PdfScreenTransform(
        rawWidthPt: rawWidthPt,
        rawHeightPt: rawHeightPt,
        scale: scale,
        viewRotationDeg: totalRotDeg,
      );
      for (final ann in pageAnnotations) {
        paintAnnotationOnCanvas(
          canvas: canvas,
          transform: transform,
          ann: ann,
          loadedImages: loadedImages,
        );
      }
      final picture = recorder.endRecording();
      final composed =
          await picture.toImage(rendered.width, rendered.height);
      picture.dispose();
      try {
        final byteData =
            await composed.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (byteData == null) return null;
        final rgba = byteData.buffer.asUint8List();
        // RGBA -> BGRA（StretchDIBits BI_RGB 32bpp 需要 BGRA）
        final bgra = Uint8List(rgba.length);
        for (var i = 0; i < rgba.length; i += 4) {
          bgra[i] = rgba[i + 2];
          bgra[i + 1] = rgba[i + 1];
          bgra[i + 2] = rgba[i];
          bgra[i + 3] = rgba[i + 3];
        }
        return (bgra: bgra, width: rendered.width, height: rendered.height);
      } finally {
        composed.dispose();
      }
    } finally {
      baseImg.dispose();
    }
  }

  /// 逐页导出多张 PNG 到指定目录
  static Future<ExportImagesResult> exportEachPng({
    required String filePath,
    required String targetDir,
    required String stem,
    required List<int> pagesZeroBased,
    required List<({double w, double h})> pageSizes,
    required List<int> pageRotations,
    required int viewRotationDeg,
    required bool includeAnnotations,
    required List<PdfAnnotationItem> allAnnotations,
    required Map<String, ui.Image> loadedImages,
    String? password,
    void Function(int done, int total)? onProgress,
  }) async {
    final written = <String>[];
    final dir = Directory(targetDir);
    if (!dir.existsSync()) dir.createSync(recursive: true);

    for (var i = 0; i < pagesZeroBased.length; i++) {
      final pi = pagesZeroBased[i];
      onProgress?.call(i, pagesZeroBased.length);
      final sz = pageSizes[pi];
      final pageRot = pi < pageRotations.length ? pageRotations[pi] : 0;
      final pageAnnots =
          allAnnotations.where((a) => a.page == pi).toList(growable: false);
      final res = await renderPagePng(
        filePath: filePath,
        pageIndex: pi,
        scale: 2.0,
        viewRotationDeg: viewRotationDeg,
        pageRotationDeg: pageRot,
        pageDisplayWidthPt: sz.w,
        pageDisplayHeightPt: sz.h,
        includeAnnotations: includeAnnotations,
        pageAnnotations: pageAnnots,
        loadedImages: loadedImages,
        password: password,
      );
      if (res == null) {
        return ExportImagesResult(
          ok: false,
          savedPaths: written,
          error: '第 ${pi + 1} 页渲染失败',
        );
      }
      final outPath =
          PdfEngineService.uniquePath(targetDir, '$stem-p${pi + 1}.png');
      await AppDataService.atomicWriteBytes(outPath, res.pngBytes);
      written.add(outPath);
      onProgress?.call(i + 1, pagesZeroBased.length);
    }
    return ExportImagesResult(ok: true, savedPaths: written);
  }

  /// 导出拼接长图（支持纵向/横向 + 自动内存降档）
  static Future<ExportImagesResult> exportLongPng({
    required String filePath,
    required String targetPath,
    required List<int> pagesZeroBased,
    required List<({double w, double h})> pageSizes,
    required List<int> pageRotations,
    required int viewRotationDeg,
    required bool vertical,
    required bool includeAnnotations,
    required List<PdfAnnotationItem> allAnnotations,
    required Map<String, ui.Image> loadedImages,
    String? password,
    void Function(int done, int total)? onProgress,
  }) async {
    if (pagesZeroBased.isEmpty) {
      return const ExportImagesResult(ok: false, error: '未选择页面');
    }
    final rotSteps = ((viewRotationDeg ~/ 90) % 4 + 4) % 4;
    var totalSpanPt = 0.0;
    var maxCrossPt = 0.0;
    for (final pi in pagesZeroBased) {
      final sz = pageSizes[pi];
      final dispW = rotSteps.isOdd ? sz.h : sz.w;
      final dispH = rotSteps.isOdd ? sz.w : sz.h;
      totalSpanPt += vertical ? dispH : dispW;
      maxCrossPt = math.max(maxCrossPt, vertical ? dispW : dispH);
    }

    double chosenScale = 0;
    for (var s = 2.0; s >= 0.25; s /= 2.0) {
      final span = totalSpanPt * s;
      final other = maxCrossPt * s;
      if (span <= _maxLongSide &&
          other <= _maxLongSide &&
          span * other * 4 <= _longImageBudgetBytes) {
        chosenScale = s;
        break;
      }
    }
    if (chosenScale == 0) {
      return const ExportImagesResult(
        ok: false,
        error: '长图超出 $_maxLongSide 像素或内存上限，请缩小页码范围',
      );
    }

    final pageImages = <ui.Image>[];
    try {
      for (var i = 0; i < pagesZeroBased.length; i++) {
        final pi = pagesZeroBased[i];
        onProgress?.call(i, pagesZeroBased.length);
        final sz = pageSizes[pi];
        final pageRot = pi < pageRotations.length ? pageRotations[pi] : 0;
        final pageAnnots =
            allAnnotations.where((a) => a.page == pi).toList(growable: false);
        final png = await renderPagePng(
          filePath: filePath,
          pageIndex: pi,
          scale: chosenScale,
          viewRotationDeg: viewRotationDeg,
          pageRotationDeg: pageRot,
          pageDisplayWidthPt: sz.w,
          pageDisplayHeightPt: sz.h,
          includeAnnotations: includeAnnotations,
          pageAnnotations: pageAnnots,
          loadedImages: loadedImages,
          password: password,
        );
        if (png == null) {
          return ExportImagesResult(ok: false, error: '第 ${pi + 1} 页渲染失败');
        }
        final codec = await ui.instantiateImageCodec(png.pngBytes);
        final frame = await codec.getNextFrame();
        pageImages.add(frame.image);
        codec.dispose();
      }

      final totalW = vertical
          ? pageImages.fold<int>(0, (m, im) => math.max(m, im.width))
          : pageImages.fold<int>(0, (s, im) => s + im.width);
      final totalH = vertical
          ? pageImages.fold<int>(0, (s, im) => s + im.height)
          : pageImages.fold<int>(0, (m, im) => math.max(m, im.height));
      if (totalW > _maxLongSide || totalH > _maxLongSide) {
        return const ExportImagesResult(
          ok: false,
          error: '长图尺寸超出 $_maxLongSide 像素上限，请缩小页码范围',
        );
      }

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, totalW.toDouble(), totalH.toDouble()),
        Paint()..color = Colors.white,
      );
      var offset = 0.0;
      for (final im in pageImages) {
        final dx = vertical ? (totalW - im.width) / 2.0 : offset;
        final dy = vertical ? offset : (totalH - im.height) / 2.0;
        canvas.drawImage(im, Offset(dx, dy), Paint());
        offset += vertical ? im.height : im.width;
      }
      final picture = recorder.endRecording();
      final stitched = await picture.toImage(totalW, totalH);
      picture.dispose();
      try {
        final bytes =
            await stitched.toByteData(format: ui.ImageByteFormat.png);
        if (bytes == null) {
          return const ExportImagesResult(ok: false, error: '长图编码失败');
        }
        await AppDataService.atomicWriteBytes(
          targetPath,
          bytes.buffer.asUint8List(),
        );
        return ExportImagesResult(
          ok: true,
          savedPaths: [targetPath],
          downscalePercent:
              chosenScale < 2.0 ? (chosenScale * 100).round() : null,
        );
      } finally {
        stitched.dispose();
      }
    } finally {
      for (final im in pageImages) {
        im.dispose();
      }
    }
  }

  /// 调用 Win32 GDI 打印（每次只保留单页位图在临时文件，峰值内存极低）
  static Future<NativePrintResult> printPages({
    required String filePath,
    required String jobName,
    required List<int> pagesZeroBased,
    required List<({double w, double h})> pageSizes,
    required List<int> pageRotations,
    required int viewRotationDeg,
    required PrintQuality quality,
    required bool includeAnnotations,
    required List<PdfAnnotationItem> allAnnotations,
    required Map<String, ui.Image> loadedImages,
    String? password,
    void Function(int done, int total)? onProgress,
  }) async {
    final jobId = await NativeBridge.printPrepare(jobName);
    if (jobId == null) {
      return const NativePrintResult(ok: false, error: '无法初始化打印任务');
    }
    final scale = quality.dpi / 72.0;
    final tmpDir = Directory(
      p.join(
        Directory.systemTemp.path,
        'pdf_ed_print_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    tmpDir.createSync(recursive: true);

    try {
      for (var i = 0; i < pagesZeroBased.length; i++) {
        final pi = pagesZeroBased[i];
        onProgress?.call(i, pagesZeroBased.length);
        final sz = pageSizes[pi];
        final pageRot = pi < pageRotations.length ? pageRotations[pi] : 0;
        final pageAnnots =
            allAnnotations.where((a) => a.page == pi).toList(growable: false);
        final rendered = await renderPageBgraWithAnnotations(
          filePath: filePath,
          pageIndex: pi,
          scale: scale,
          viewRotationDeg: viewRotationDeg,
          pageRotationDeg: pageRot,
          pageDisplayWidthPt: sz.w,
          pageDisplayHeightPt: sz.h,
          includeAnnotations: includeAnnotations,
          pageAnnotations: pageAnnots,
          loadedImages: loadedImages,
          password: password,
        );
        if (rendered == null) {
          await NativeBridge.printAbort(jobId);
          return NativePrintResult(ok: false, error: '第 ${pi + 1} 页渲染失败');
        }
        final rawPath = p.join(tmpDir.path, 'page_${i + 1}.raw');
        final hdr = ByteData(8)
          ..setInt32(0, rendered.width, Endian.little)
          ..setInt32(4, rendered.height, Endian.little);
        final file = await File(rawPath).open(mode: FileMode.write);
        await file.writeFrom(hdr.buffer.asUint8List());
        await file.writeFrom(rendered.bgra);
        await file.close();

        final rotSteps = ((viewRotationDeg ~/ 90) % 4 + 4) % 4;
        final wPt = rotSteps.isOdd ? sz.h : sz.w;
        final hPt = rotSteps.isOdd ? sz.w : sz.h;
        await NativeBridge.printAddPage(
          jobId: jobId,
          rawPath: rawPath,
          widthPt: wPt,
          heightPt: hPt,
        );
        onProgress?.call(i + 1, pagesZeroBased.length);
      }

      return await NativeBridge.printCommit(jobId);
    } catch (e) {
      await NativeBridge.printAbort(jobId);
      return NativePrintResult(ok: false, error: '$e');
    } finally {
      await tmpDir.delete(recursive: true).catchError((_) => tmpDir);
    }
  }
}
