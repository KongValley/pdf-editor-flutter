import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'recent_and_log_service.dart';

class ImageToPdfResult {
  const ImageToPdfResult({
    required this.ok,
    this.savedPath,
    this.pageCount = 0,
    this.failedFiles = const [],
    this.error,
  });

  final bool ok;
  final String? savedPath;
  final int pageCount;
  final List<String> failedFiles;
  final String? error;
}

class ImageToPdfService {
  ImageToPdfService._();

  static const int maxImages = 200;

  static bool isSupportedImageHeader(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true; // PNG
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return true; // JPEG
    }
    return false;
  }

  static Future<ImageToPdfResult> convert({
    required List<String> imagePaths,
    required String targetPath,
    required bool useA4,
    void Function(int done, int total, String fileName)? onProgress,
  }) async {
    if (imagePaths.isEmpty) {
      return const ImageToPdfResult(ok: false, error: '请至少选择一张图片');
    }
    if (imagePaths.length > maxImages) {
      return const ImageToPdfResult(
        ok: false,
        error: '单次最多支持合并 $maxImages 张图片，请分批处理',
      );
    }

    final doc = pw.Document();
    final failed = <String>[];
    var added = 0;

    for (var i = 0; i < imagePaths.length; i++) {
      final path = imagePaths[i];
      final name = p.basename(path);
      onProgress?.call(i, imagePaths.length, name);

      try {
        final bytes = await File(path).readAsBytes();
        if (!isSupportedImageHeader(bytes)) {
          failed.add('$name（仅支持 PNG/JPEG）');
          continue;
        }
        final info = await compute(_probeImageSize, bytes);
        if (info == null) {
          failed.add('$name（图片解码失败）');
          continue;
        }
        final pwImg = pw.MemoryImage(bytes);
        if (!useA4) {
          // 96 DPI 像素换算成 pt（72 / 96 = 0.75），铺满整页无白边
          final pageW = info.width * 72.0 / 96.0;
          final pageH = info.height * 72.0 / 96.0;
          doc.addPage(
            pw.Page(
              pageFormat: PdfPageFormat(pageW, pageH, marginAll: 0),
              build: (_) => pw.FullPage(
                ignoreMargins: true,
                child: pw.Image(pwImg, fit: pw.BoxFit.fill),
              ),
            ),
          );
        } else {
          final landscape = info.width > info.height;
          final format = landscape
              ? PdfPageFormat.a4.landscape
              : PdfPageFormat.a4;
          doc.addPage(
            pw.Page(
              pageFormat: format,
              margin: const pw.EdgeInsets.all(16),
              build: (_) => pw.Center(
                child: pw.Image(pwImg, fit: pw.BoxFit.contain),
              ),
            ),
          );
        }
        added++;
      } catch (e) {
        failed.add('$name（$e）');
      }
      onProgress?.call(i + 1, imagePaths.length, name);
    }

    if (added == 0) {
      return ImageToPdfResult(
        ok: false,
        failedFiles: failed,
        error: '没有可转换的有效图片',
      );
    }

    final outBytes = await doc.save();
    await AppDataService.atomicWriteBytes(targetPath, outBytes);
    return ImageToPdfResult(
      ok: true,
      savedPath: targetPath,
      pageCount: added,
      failedFiles: failed,
    );
  }

  static ({int width, int height})? _probeImageSize(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      return null;
    }
    return (width: decoded.width, height: decoded.height);
  }
}
