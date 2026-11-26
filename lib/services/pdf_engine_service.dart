import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium;
import 'package:pdfrx_engine/pdfrx_engine.dart' show PdfrxEntryFunctions;

import '../models/annotation_model.dart';
import '../models/document_models.dart';
import '../utils/page_range.dart';
import 'recent_and_log_service.dart';
import 'system_fonts_service.dart';

typedef _NativeFileWriteCallable = NativeCallable<
    Int Function(Pointer<pdfium.FPDF_FILEWRITE>, Pointer<Void>, UnsignedLong)>;

class PdfInspectResult {
  const PdfInspectResult({
    required this.ok,
    this.passwordRequired = false,
    this.error,
    this.pageCount = 0,
    this.pageSizes = const [],
    this.pageRotations = const [],
    this.annotations = const [],
  });

  final bool ok;
  final bool passwordRequired;
  final String? error;
  final int pageCount;
  final List<({double w, double h})> pageSizes;
  final List<int> pageRotations;
  final List<PdfAnnotationItem> annotations;
}

class PdfOpSaveResult {
  const PdfOpSaveResult({
    required this.ok,
    this.error,
    this.warnings = const [],
    this.pageCount = 0,
  });

  final bool ok;
  final String? error;
  final List<String> warnings;
  final int pageCount;
}

class SplitTaskInput {
  const SplitTaskInput({
    required this.path,
    required this.chunks,
    this.password,
    this.annotations,
    this.isCurrentDoc = false,
    this.outputStem,
  });

  final String path;
  final List<List<int>> chunks; // each chunk is list of 0-based pages
  final String? password;
  final List<PdfAnnotationItem>? annotations;
  final bool isCurrentDoc;
  final String? outputStem;
}

class SplitTaskOutcome {
  const SplitTaskOutcome({
    required this.path,
    required this.ok,
    this.outputs = const [],
    this.error,
  });

  final String path;
  final bool ok;
  final List<String> outputs;
  final String? error;
}

class PdfEngineService {
  PdfEngineService._();

  static pdfium.PDFium? _workerPdfium;
  static pdfium.PDFium _getPdfium() => _workerPdfium ??= pdfium.getPdfium();

  static Future<PdfInspectResult> inspectDocument(
    String filePath, {
    String? password,
  }) {
    return PdfrxEntryFunctions.instance.compute(
      (msg) => _inspectDocumentSync(msg.path, msg.password),
      (path: filePath, password: password),
    );
  }

  static PdfInspectResult _inspectDocumentSync(String filePath, String? password) {
    final fp = _getPdfium();
    return using((arena) {
      final pathPtr = filePath.toNativeUtf8(allocator: arena).cast<Char>();
      final pwPtr = password == null
          ? nullptr.cast<Char>()
          : password.toNativeUtf8(allocator: arena).cast<Char>();
      final doc = fp.FPDF_LoadDocument(pathPtr, pwPtr);
      if (doc == nullptr) {
        final err = fp.FPDF_GetLastError();
        if (err == pdfium.FPDF_ERR_PASSWORD) {
          return const PdfInspectResult(
            ok: false,
            passwordRequired: true,
            error: '文档已加密，需要输入密码',
          );
        }
        return PdfInspectResult(
          ok: false,
          error: '无法打开 PDF（错误码 $err）',
        );
      }
      try {
        final count = fp.FPDF_GetPageCount(doc);
        final sizes = <({double w, double h})>[];
        final rotations = <int>[];
        final annots = <PdfAnnotationItem>[];
        final wPtr = arena<Double>();
        final hPtr = arena<Double>();

        for (var i = 0; i < count; i++) {
          if (fp.FPDF_GetPageSizeByIndex(doc, i, wPtr, hPtr) != 0) {
            sizes.add((w: wPtr.value, h: hPtr.value));
          } else {
            sizes.add((w: 595.28, h: 841.89));
          }

          final page = fp.FPDF_LoadPage(doc, i);
          if (page == nullptr) {
            rotations.add(0);
            continue;
          }
          try {
            final rawRot = fp.FPDFPage_GetRotation(page);
            rotations.add((rawRot < 0 ? 0 : rawRot % 4) * 90);
            final annotCount = fp.FPDFPage_GetAnnotCount(page);
            for (var ai = 0; ai < annotCount; ai++) {
              final annot = fp.FPDFPage_GetAnnot(page, ai);
              if (annot == nullptr) continue;
              try {
                final keyPtr = 'PdEditorData'.toNativeUtf8(allocator: arena).cast<Char>();
                if (fp.FPDFAnnot_HasKey(annot, keyPtr) == 0) continue;
                final rawBytes = _readAnnotRawWchars(fp, annot, keyPtr);
                final parsed = _decodePdEditorData(rawBytes, i);
                if (parsed != null) annots.add(parsed);
              } finally {
                fp.FPDFPage_CloseAnnot(annot);
              }
            }
          } finally {
            fp.FPDF_ClosePage(page);
          }
        }
        return PdfInspectResult(
          ok: true,
          pageCount: count,
          pageSizes: sizes,
          pageRotations: rotations,
          annotations: annots,
        );
      } finally {
        fp.FPDF_CloseDocument(doc);
      }
    });
  }

  /// 读取 PDFium 注解字符串字段原始 UTF-16 code units
  static List<int> _readAnnotRawWchars(
    pdfium.PDFium fp,
    pdfium.FPDF_ANNOTATION annot,
    Pointer<Char> keyPtr,
  ) {
    final lenBytes = fp.FPDFAnnot_GetStringValue(annot, keyPtr, nullptr, 0);
    if (lenBytes <= 2) return const [];
    return using((arena) {
      final buf = arena<Uint16>(lenBytes ~/ 2);
      final actual = fp.FPDFAnnot_GetStringValue(
        annot,
        keyPtr,
        buf.cast<pdfium.FPDF_WCHAR>(),
        lenBytes,
      );
      if (actual <= 2) return const [];
      final count = (actual ~/ 2) - 1; // 去掉末尾 NUL
      return List<int>.generate(count, (i) => buf[i]);
    });
  }

  static const Map<int, int> _pdfDocUnicodeToByte = {
    0x02D8: 0x18,
    0x02C7: 0x19,
    0x02C6: 0x1A,
    0x02D9: 0x1B,
    0x02DD: 0x1C,
    0x02DB: 0x1D,
    0x02DA: 0x1E,
    0x02DC: 0x1F,
    0x2022: 0x80,
    0x2020: 0x81,
    0x2021: 0x82,
    0x2026: 0x83,
    0x2014: 0x84,
    0x2013: 0x85,
    0x0192: 0x86,
    0x2044: 0x87,
    0x2039: 0x88,
    0x203A: 0x89,
    0x2212: 0x8A,
    0x2030: 0x8B,
    0x201E: 0x8C,
    0x201C: 0x8D,
    0x201D: 0x8E,
    0x2018: 0x8F,
    0x2019: 0x90,
    0x201A: 0x91,
    0x2122: 0x92,
    0xFB01: 0x93,
    0xFB02: 0x94,
    0x0141: 0x95,
    0x0152: 0x96,
    0x0160: 0x97,
    0x0178: 0x98,
    0x017D: 0x99,
    0x0131: 0x9A,
    0x0142: 0x9B,
    0x0153: 0x9C,
    0x0161: 0x9D,
    0x017E: 0x9E,
    0x20AC: 0xA0,
  };

  static List<int>? _tryPdfDocUnitsToBytes(List<int> units) {
    final bytes = <int>[];
    for (final u in units) {
      if (u >= 0 && u <= 0xFF) {
        bytes.add(u);
      } else {
        final mapped = _pdfDocUnicodeToByte[u];
        if (mapped == null) return null;
        bytes.add(mapped);
      }
    }
    return bytes;
  }

  /// 解码 Electron/Flutter 写入的 `/PdEditorData` 内容（供测试与内部解析共用）
  static PdfAnnotationItem? decodePdEditorDataUnits(
    List<int> units,
    int pageIndex,
  ) =>
      _decodePdEditorData(units, pageIndex);

  static PdfAnnotationItem? _decodePdEditorData(List<int> units, int pageIndex) {
    if (units.isEmpty) return null;
    try {
      String jsonText;
      final str = String.fromCharCodes(units).trim();
      final docBytes = _tryPdfDocUnitsToBytes(units);
      if (str.startsWith('{')) {
        jsonText = str;
        // Electron 以无 BOM UTF-8 写入时，PDFium 会按 PDFDocEncoding 逐字节解成单字节码位。
        // 仅当所有码位都在 PDFDocEncoding 范围内、存在高位字节且严格 UTF-8 解码成功时优先还原为 UTF-8。
        if (docBytes != null && docBytes.any((b) => b >= 0x80)) {
          try {
            final recovered = utf8.decode(docBytes, allowMalformed: false).trim();
            if (recovered.startsWith('{')) {
              jsonText = recovered;
            }
          } catch (_) {}
        }
      } else {
        final rawBytes = Uint8List.fromList(
          docBytes ?? units.map((u) => u & 0xFF).toList(),
        );
        if (rawBytes.length >= 2 && rawBytes[0] == 0xFE && rawBytes[1] == 0xFF) {
          final u16 = <int>[];
          for (var i = 2; i + 1 < rawBytes.length; i += 2) {
            u16.add((rawBytes[i] << 8) | rawBytes[i + 1]);
          }
          jsonText = String.fromCharCodes(u16);
        } else if (rawBytes.length >= 3 &&
            rawBytes[0] == 0xEF &&
            rawBytes[1] == 0xBB &&
            rawBytes[2] == 0xBF) {
          jsonText = utf8.decode(rawBytes.sublist(3), allowMalformed: true);
        } else {
          jsonText = utf8.decode(rawBytes, allowMalformed: true);
        }
      }
      final decoded = jsonDecode(jsonText);
      final item = PdfAnnotationItem.tryFromJson(decoded);
      return item?.copyWith(page: pageIndex);
    } catch (_) {
      return null;
    }
  }

  /// 保存带注释的新 PDF 副本（在 worker isolate 执行）
  static Future<PdfOpSaveResult> saveWithAnnotations({
    required String sourcePath,
    required String targetPath,
    required List<PdfAnnotationItem> annotations,
    String? password,
    Map<String, Uint8List> resolvedImages = const {},
  }) async {
    // 主 isolate 预先解析所需系统字体字节与默认中文字体，避免 isolate 内跨静态缓存
    final fontBytesByFamily = <String, Uint8List>{};
    final warnings = <String>[];
    final needsTextFont = annotations.any((a) =>
        a.kind == AnnotationKind.measure ||
        (a.kind == AnnotationKind.stamp && a.label.trim().isNotEmpty) ||
        (a.kind == AnnotationKind.text && a.text.trim().isNotEmpty));

    Uint8List? defaultCjkBytes;
    if (needsTextFont) {
      defaultCjkBytes = await SystemFontsService.readDefaultCjkFontBytes();
      for (final ann in annotations) {
        final fam = ann.fontFamily?.trim() ?? '';
        if (fam.isEmpty) continue;
        final key = fam.toLowerCase();
        if (fontBytesByFamily.containsKey(key)) continue;
        final face = await SystemFontsService.findFont(fam);
        if (face == null) {
          warnings.add('未找到系统字体「$fam」，已回退默认字体');
          continue;
        }
        try {
          final bytes = await SystemFontsService.readFaceBytes(face);
          fontBytesByFamily[key] = bytes;
        } catch (e) {
          warnings.add('读取字体「$fam」失败，已回退默认字体：$e');
        }
      }
    }

    // 预解码图片注释为 BGRA 以便 PDFium FPDFImageObj_SetBitmap 直接写入
    final decodedImages = <String, ({int w, int h, Uint8List bgra})>{};
    for (final ann in annotations) {
      if (ann.kind != AnnotationKind.image) continue;
      final cacheKey = ann.imgId.isNotEmpty ? ann.imgId : ann.refPath;
      if (decodedImages.containsKey(cacheKey)) continue;
      Uint8List? raw = resolvedImages[ann.imgId];
      if (raw == null && ann.refPath.isNotEmpty) {
        final f = File(ann.refPath);
        if (f.existsSync()) {
          raw = await f.readAsBytes();
        }
      }
      if (raw == null) {
        warnings.add('图片注释丢失（找不到文件：${ann.refPath}）');
        continue;
      }
      final decoded = img.decodeImage(raw);
      if (decoded == null) {
        warnings.add('无法解码图片注释：${ann.refPath}');
        continue;
      }
      final rgba = decoded.convert(numChannels: 4);
      final bgra = Uint8List(rgba.width * rgba.height * 4);
      var idx = 0;
      for (final pixel in rgba) {
        bgra[idx++] = pixel.b.toInt();
        bgra[idx++] = pixel.g.toInt();
        bgra[idx++] = pixel.r.toInt();
        bgra[idx++] = pixel.a.toInt();
      }
      decodedImages[cacheKey] = (w: rgba.width, h: rgba.height, bgra: bgra);
    }

    // 读取源文件字节到临时备份（防止 sourcePath == targetPath 时源句柄与写冲突）
    final tmpDir = Directory.systemTemp;
    final tmpSource = p.join(
      tmpDir.path,
      'pdf_ed_src_${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    await File(sourcePath).copy(tmpSource);
    final tmpOut =
        '$targetPath.${DateTime.now().microsecondsSinceEpoch}.tmp';

    try {
      final result = await PdfrxEntryFunctions.instance.compute(
        (msg) => _saveWithAnnotationsSync(
          sourcePath: msg.sourcePath,
          tmpOutPath: msg.tmpOutPath,
          password: msg.password,
          annotations: msg.annotations,
          defaultCjkBytes: msg.defaultCjkBytes,
          fontBytesByFamily: msg.fontBytesByFamily,
          decodedImages: msg.decodedImages,
          initialWarnings: msg.warnings,
        ),
        (
          sourcePath: tmpSource,
          tmpOutPath: tmpOut,
          password: password,
          annotations: annotations,
          defaultCjkBytes: defaultCjkBytes,
          fontBytesByFamily: fontBytesByFamily,
          decodedImages: decodedImages,
          warnings: warnings,
        ),
      );
      if (!result.ok) {
        await File(tmpOut).delete().catchError((_) => File(tmpOut));
        return result;
      }
      final targetParent = File(targetPath).parent;
      if (!targetParent.existsSync()) {
        targetParent.createSync(recursive: true);
      }
      final outFile = File(tmpOut);
      try {
        await outFile.rename(targetPath);
      } catch (_) {
        await outFile.copy(targetPath);
        await outFile.delete().catchError((_) => outFile);
      }
      return result;
    } finally {
      await File(tmpSource).delete().catchError((_) => File(tmpSource));
      await File(tmpOut).delete().catchError((_) => File(tmpOut));
    }
  }

  static PdfOpSaveResult _saveWithAnnotationsSync({
    required String sourcePath,
    required String tmpOutPath,
    required String? password,
    required List<PdfAnnotationItem> annotations,
    required Uint8List? defaultCjkBytes,
    required Map<String, Uint8List> fontBytesByFamily,
    required Map<String, ({int w, int h, Uint8List bgra})> decodedImages,
    required List<String> initialWarnings,
  }) {
    final fp = _getPdfium();
    final warnings = [...initialWarnings];

    return using((arena) {
      final pathPtr = sourcePath.toNativeUtf8(allocator: arena).cast<Char>();
      final pwPtr = password == null
          ? nullptr.cast<Char>()
          : password.toNativeUtf8(allocator: arena).cast<Char>();
      final doc = fp.FPDF_LoadDocument(pathPtr, pwPtr);
      if (doc == nullptr) {
        return PdfOpSaveResult(
          ok: false,
          error: '加载 PDF 失败（错误码 ${fp.FPDF_GetLastError()}）',
        );
      }

      final loadedFonts = <pdfium.FPDF_FONT>[];
      var docClosed = false;
      try {
        final pageCount = fp.FPDF_GetPageCount(doc);
        // 加载字体供文字/图章/测量外观使用
        pdfium.FPDF_FONT? defaultFont;
        if (defaultCjkBytes != null) {
          defaultFont = _loadTtfFont(fp, doc, defaultCjkBytes, arena);
        }
        final helvFont = fp.FPDFText_LoadStandardFont(
          doc,
          'Helvetica'.toNativeUtf8(allocator: arena).cast<Char>(),
        );
        if (helvFont != nullptr) loadedFonts.add(helvFont);
        if (defaultFont != null) loadedFonts.add(defaultFont);

        final customFontHandles = <String, pdfium.FPDF_FONT>{};
        pdfium.FPDF_FONT? resolveDocFont(String? family, String text) {
          final hasNonAscii = RegExp(r'[^\x00-\x7F]').hasMatch(text);
          final famKey = (family ?? '').trim().toLowerCase();
          if (famKey.isNotEmpty) {
            final bytes = fontBytesByFamily[famKey];
            if (bytes != null) {
              if (SystemFontsService.fontCoversText(bytes, text)) {
                var handle = customFontHandles[famKey];
                if (handle == null) {
                  handle = _loadTtfFont(fp, doc, bytes, arena);
                  if (handle != null) {
                    customFontHandles[famKey] = handle;
                    loadedFonts.add(handle);
                  }
                }
                if (handle != null) return handle;
              } else {
                warnings.add('字体「$family」缺少部分字符，已自动改用默认字体');
              }
            }
          }
          if (defaultFont != null) return defaultFont;
          if (!hasNonAscii && helvFont != nullptr) return helvFont;
          return null;
        }

        // 检查是否有需要写中文但系统无中文字体的情况
        if (defaultFont == null) {
          for (final ann in annotations) {
            final text = ann.kind == AnnotationKind.text
                ? ann.text
                : ann.kind == AnnotationKind.stamp
                    ? ann.label
                    : '';
            if (RegExp(r'[^\x00-\x7F]').hasMatch(text)) {
              final fam = ann.fontFamily?.trim().toLowerCase();
              final customBytes = fam != null ? fontBytesByFamily[fam] : null;
              if (customBytes == null ||
                  !SystemFontsService.fontCoversText(customBytes, text)) {
                return const PdfOpSaveResult(
                  ok: false,
                  error: '系统缺少可嵌入的中文字体（黑体/楷体/雅黑），无法保存中文批注内容',
                );
              }
            }
          }
        }

        // 按页分组批注，并清理已有 /PdEditorData 批注
        final byPage = <int, List<PdfAnnotationItem>>{};
        for (final ann in annotations) {
          if (ann.page < 0 || ann.page >= pageCount) {
            warnings.add('注释所在页不存在（第 ${ann.page + 1} 页）');
            continue;
          }
          byPage.putIfAbsent(ann.page, () => []).add(ann);
        }

        final bboxPtr = arena<pdfium.FS_RECTF>();
        for (var pi = 0; pi < pageCount; pi++) {
          final page = fp.FPDF_LoadPage(doc, pi);
          if (page == nullptr) continue;
          try {
            var bbLeft = 0.0;
            var bbBottom = 0.0;
            if (fp.FPDF_GetPageBoundingBox(page, bboxPtr) != 0) {
              bbLeft = bboxPtr.ref.left;
              bbBottom = bboxPtr.ref.bottom;
            }
            // 剥离历史 /PdEditorData 批注（保留外来批注和表单 Widget）
            final keyPtr =
                'PdEditorData'.toNativeUtf8(allocator: arena).cast<Char>();
            final existingCount = fp.FPDFPage_GetAnnotCount(page);
            for (var ai = existingCount - 1; ai >= 0; ai--) {
              final annot = fp.FPDFPage_GetAnnot(page, ai);
              if (annot == nullptr) continue;
              final hasOwn = fp.FPDFAnnot_HasKey(annot, keyPtr) != 0;
              fp.FPDFPage_CloseAnnot(annot);
              if (hasOwn) {
                fp.FPDFPage_RemoveAnnot(page, ai);
              }
            }

            final pageAnnots = byPage[pi];
            if (pageAnnots != null) {
              for (final ann in pageAnnots) {
                _appendAnnotationToPage(
                  fp: fp,
                  doc: doc,
                  page: page,
                  ann: ann,
                  arena: arena,
                  resolveFont: resolveDocFont,
                  decodedImages: decodedImages,
                  warnings: warnings,
                  bbLeft: bbLeft,
                  bbBottom: bbBottom,
                );
              }
            }
            fp.FPDFPage_GenerateContent(page);
          } finally {
            fp.FPDF_ClosePage(page);
          }
        }

        final savedOk = _saveDocToFile(
          fp,
          doc,
          tmpOutPath,
          arena,
          beforeReplace: () {
            for (final f in loadedFonts) {
              fp.FPDFFont_Close(f);
            }
            loadedFonts.clear();
            if (!docClosed) {
              fp.FPDF_CloseDocument(doc);
              docClosed = true;
            }
          },
        );
        if (!savedOk) {
          return const PdfOpSaveResult(
            ok: false,
            error: 'PDF 写入磁盘失败',
          );
        }
        return PdfOpSaveResult(
          ok: true,
          warnings: warnings,
          pageCount: pageCount,
        );
      } finally {
        for (final f in loadedFonts) {
          fp.FPDFFont_Close(f);
        }
        if (!docClosed) {
          fp.FPDF_CloseDocument(doc);
        }
      }
    });
  }

  static pdfium.FPDF_FONT? _loadTtfFont(
    pdfium.PDFium fp,
    pdfium.FPDF_DOCUMENT doc,
    Uint8List fontBytes,
    Arena arena,
  ) {
    final buf = arena<Uint8>(fontBytes.length);
    buf.asTypedList(fontBytes.length).setAll(0, fontBytes);
    final handle = fp.FPDFText_LoadFont(
      doc,
      buf,
      fontBytes.length,
      pdfium.FPDF_FONT_TRUETYPE,
      1, // cid = true 支持 Unicode/CJK
    );
    return handle == nullptr ? null : handle;
  }

  static String _jsonEncodeAsciiSafe(Map<String, dynamic> map) {
    final raw = jsonEncode(map);
    final sb = StringBuffer();
    for (final unit in raw.codeUnits) {
      if (unit < 0x80) {
        sb.writeCharCode(unit);
      } else {
        sb.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
      }
    }
    return sb.toString();
  }

  static Pointer<Uint16> _toUtf16Ptr(String text, Arena arena) {
    final units = text.codeUnits;
    final ptr = arena<Uint16>(units.length + 1);
    for (var i = 0; i < units.length; i++) {
      ptr[i] = units[i];
    }
    ptr[units.length] = 0;
    return ptr;
  }

  static double _annotPadForKind(PdfAnnotationItem ann) {
    switch (ann.kind) {
      case AnnotationKind.arrow:
        final from = ann.from ?? PdfPoint(ann.bbox.x, ann.bbox.y);
        final to = ann.to ?? PdfPoint(ann.bbox.right, ann.bbox.top);
        final len = math.max(hypot(to.x - from.x, to.y - from.y), 1.0);
        final wing = math.max(4.0, len * 0.14);
        return math.max(6.0, wing + ann.thickness);
      case AnnotationKind.measure:
        return math.max(24.0, ann.thickness + 18.0);
      case AnnotationKind.ink:
      case AnnotationKind.rect:
      case AnnotationKind.ellipse:
        return math.max(3.0, ann.thickness);
      case AnnotationKind.stamp:
        return math.max(4.0, ann.thickness * 1.5);
      case AnnotationKind.highlight:
      case AnnotationKind.text:
      case AnnotationKind.note:
      case AnnotationKind.image:
        return 3.0;
    }
  }

  static void _setAnnotRect(
    pdfium.PDFium fp,
    pdfium.FPDF_ANNOTATION annot,
    PdfRectBox box,
    Arena arena, {
    double pad = 3.0,
    double bbLeft = 0.0,
    double bbBottom = 0.0,
  }) {
    final rect = arena<pdfium.FS_RECTF>();
    rect.ref.left = bbLeft + box.x - pad;
    rect.ref.bottom = bbBottom + box.y - pad;
    rect.ref.right = bbLeft + box.x + box.w + pad;
    rect.ref.top = bbBottom + box.y + box.h + pad;
    fp.FPDFAnnot_SetRect(annot, rect);
  }

  static void _appendAnnotationToPage({
    required pdfium.PDFium fp,
    required pdfium.FPDF_DOCUMENT doc,
    required pdfium.FPDF_PAGE page,
    required PdfAnnotationItem ann,
    required Arena arena,
    required pdfium.FPDF_FONT? Function(String? family, String text) resolveFont,
    required Map<String, ({int w, int h, Uint8List bgra})> decodedImages,
    required List<String> warnings,
    double bbLeft = 0.0,
    double bbBottom = 0.0,
  }) {
    final color = hexToColor(ann.color, opacity: ann.opacity);
    final r = (color.r * 255).round().clamp(0, 255);
    final g = (color.g * 255).round().clamp(0, 255);
    final b = (color.b * 255).round().clamp(0, 255);
    final a = (ann.opacity * 255).round().clamp(1, 255);

    final subtype = switch (ann.kind) {
      AnnotationKind.highlight => pdfium.FPDF_ANNOT_HIGHLIGHT,
      AnnotationKind.rect => pdfium.FPDF_ANNOT_SQUARE,
      AnnotationKind.ellipse => pdfium.FPDF_ANNOT_CIRCLE,
      AnnotationKind.ink => pdfium.FPDF_ANNOT_INK,
      AnnotationKind.note => pdfium.FPDF_ANNOT_TEXT,
      // arrow / measure / text / stamp / image 用 STAMP 承载矢量/文字/图片外观对象，
      // 确保所有 PDF 阅读器 100% 一致渲染，且通过 PdEditorData 完整还原语义。
      AnnotationKind.arrow ||
      AnnotationKind.measure ||
      AnnotationKind.text ||
      AnnotationKind.stamp ||
      AnnotationKind.image =>
        pdfium.FPDF_ANNOT_STAMP,
    };

    final annot = fp.FPDFPage_CreateAnnot(page, subtype);
    if (annot == nullptr) {
      warnings.add('创建批注对象失败：${ann.kind.label}');
      return;
    }

    try {
      fp.FPDFAnnot_SetFlags(annot, pdfium.FPDF_ANNOT_FLAG_PRINT);
      final bounds = ann.effectiveBounds;
      _setAnnotRect(
        fp,
        annot,
        bounds,
        arena,
        pad: _annotPadForKind(ann),
        bbLeft: bbLeft,
        bbBottom: bbBottom,
      );

      // 写入 NM 与 PdEditorData（纯 ASCII JSON，与原 Electron 互认）
      final nmKey = 'NM'.toNativeUtf8(allocator: arena).cast<Char>();
      fp.FPDFAnnot_SetStringValue(
        annot,
        nmKey,
        _toUtf16Ptr(ann.id, arena).cast<pdfium.FPDF_WCHAR>(),
      );
      final dataKey = 'PdEditorData'.toNativeUtf8(allocator: arena).cast<Char>();
      final asciiJson = _jsonEncodeAsciiSafe(ann.toJson());
      fp.FPDFAnnot_SetStringValue(
        annot,
        dataKey,
        _toUtf16Ptr(asciiJson, arena).cast<pdfium.FPDF_WCHAR>(),
      );

      switch (ann.kind) {
        case AnnotationKind.highlight:
          fp.FPDFAnnot_SetColor(
            annot,
            pdfium.FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color,
            r,
            g,
            b,
            a,
          );
          final qp = arena<pdfium.FS_QUADPOINTSF>();
          qp.ref.x1 = bbLeft + ann.bbox.x;
          qp.ref.y1 = bbBottom + ann.bbox.top;
          qp.ref.x2 = bbLeft + ann.bbox.right;
          qp.ref.y2 = bbBottom + ann.bbox.top;
          qp.ref.x3 = bbLeft + ann.bbox.x;
          qp.ref.y3 = bbBottom + ann.bbox.y;
          qp.ref.x4 = bbLeft + ann.bbox.right;
          qp.ref.y4 = bbBottom + ann.bbox.y;
          fp.FPDFAnnot_AppendAttachmentPoints(annot, qp);
          break;

        case AnnotationKind.rect:
        case AnnotationKind.ellipse:
          fp.FPDFAnnot_SetColor(
            annot,
            pdfium.FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color,
            r,
            g,
            b,
            a,
          );
          fp.FPDFAnnot_SetBorder(annot, 0, 0, ann.thickness);
          break;

        case AnnotationKind.ink:
          fp.FPDFAnnot_SetColor(
            annot,
            pdfium.FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color,
            r,
            g,
            b,
            a,
          );
          fp.FPDFAnnot_SetBorder(annot, 0, 0, ann.thickness);
          if (ann.points.isNotEmpty) {
            final ptsPtr = arena<pdfium.FS_POINTF>(ann.points.length);
            for (var i = 0; i < ann.points.length; i++) {
              ptsPtr[i].x = bbLeft + ann.points[i].x;
              ptsPtr[i].y = bbBottom + ann.points[i].y;
            }
            fp.FPDFAnnot_AddInkStroke(annot, ptsPtr, ann.points.length);
            if (ann.points.length >= 2) {
              final pathObj = fp.FPDFPageObj_CreateNewPath(
                bbLeft + ann.points.first.x,
                bbBottom + ann.points.first.y,
              );
              if (pathObj != nullptr) {
                for (var i = 1; i < ann.points.length; i++) {
                  fp.FPDFPath_LineTo(
                    pathObj,
                    bbLeft + ann.points[i].x,
                    bbBottom + ann.points[i].y,
                  );
                }
                fp.FPDFPageObj_SetStrokeColor(pathObj, r, g, b, a);
                fp.FPDFPageObj_SetStrokeWidth(pathObj, ann.thickness);
                fp.FPDFPageObj_SetLineCap(pathObj, pdfium.FPDF_LINECAP_ROUND);
                fp.FPDFPath_SetDrawMode(pathObj, pdfium.FPDF_FILLMODE_NONE, 1);
                if (fp.FPDFAnnot_AppendObject(annot, pathObj) == 0) {
                  fp.FPDFPageObj_Destroy(pathObj);
                }
              }
            }
          }
          break;

        case AnnotationKind.note:
          fp.FPDFAnnot_SetColor(
            annot,
            pdfium.FPDFANNOT_COLORTYPE.FPDFANNOT_COLORTYPE_Color,
            r,
            g,
            b,
            a,
          );
          fp.FPDFAnnot_SetStringValue(
            annot,
            'Name'.toNativeUtf8(allocator: arena).cast<Char>(),
            _toUtf16Ptr('Note', arena).cast<pdfium.FPDF_WCHAR>(),
          );
          fp.FPDFAnnot_SetStringValue(
            annot,
            'Contents'.toNativeUtf8(allocator: arena).cast<Char>(),
            _toUtf16Ptr(ann.text, arena).cast<pdfium.FPDF_WCHAR>(),
          );
          break;

        case AnnotationKind.arrow:
          final fromRaw = ann.from ?? PdfPoint(ann.bbox.x, ann.bbox.y);
          final toRaw = ann.to ?? PdfPoint(ann.bbox.right, ann.bbox.top);
          final fromX = bbLeft + fromRaw.x;
          final fromY = bbBottom + fromRaw.y;
          final toX = bbLeft + toRaw.x;
          final toY = bbBottom + toRaw.y;
          final shaft = fp.FPDFPageObj_CreateNewPath(fromX, fromY);
          if (shaft != nullptr) {
            fp.FPDFPath_LineTo(shaft, toX, toY);
            final dx = toX - fromX;
            final dy = toY - fromY;
            final length = math.max(hypot(dx, dy), 1.0);
            final wing = math.max(4.0, length * 0.14);
            final angle = math.atan2(dy, dx);
            const spread = 0.45;
            for (final sign in [1.0, -1.0]) {
              fp.FPDFPath_MoveTo(shaft, toX, toY);
              fp.FPDFPath_LineTo(
                shaft,
                toX - wing * math.cos(angle - sign * spread),
                toY - wing * math.sin(angle - sign * spread),
              );
            }
            fp.FPDFPageObj_SetStrokeColor(shaft, r, g, b, a);
            fp.FPDFPageObj_SetStrokeWidth(shaft, ann.thickness);
            fp.FPDFPageObj_SetLineCap(shaft, pdfium.FPDF_LINECAP_ROUND);
            fp.FPDFPath_SetDrawMode(shaft, pdfium.FPDF_FILLMODE_NONE, 1);
            if (fp.FPDFAnnot_AppendObject(annot, shaft) == 0) {
              fp.FPDFPageObj_Destroy(shaft);
            }
          }
          break;

        case AnnotationKind.measure:
          final fromRaw = ann.from ?? PdfPoint(ann.bbox.x, ann.bbox.y);
          final toRaw = ann.to ?? PdfPoint(ann.bbox.right, ann.bbox.top);
          final fromX = bbLeft + fromRaw.x;
          final fromY = bbBottom + fromRaw.y;
          final toX = bbLeft + toRaw.x;
          final toY = bbBottom + toRaw.y;
          final dx = toX - fromX;
          final dy = toY - fromY;
          final lineLen = hypot(dx, dy);
          final line = fp.FPDFPageObj_CreateNewPath(fromX, fromY);
          if (line != nullptr) {
            fp.FPDFPath_LineTo(line, toX, toY);
            if (lineLen > 1.0) {
              final nx = -dy / lineLen * 4.5;
              final ny = dx / lineLen * 4.5;
              fp.FPDFPath_MoveTo(line, fromX - nx, fromY - ny);
              fp.FPDFPath_LineTo(line, fromX + nx, fromY + ny);
              fp.FPDFPath_MoveTo(line, toX - nx, toY - ny);
              fp.FPDFPath_LineTo(line, toX + nx, toY + ny);
            }
            fp.FPDFPageObj_SetStrokeColor(line, r, g, b, a);
            fp.FPDFPageObj_SetStrokeWidth(line, ann.thickness);
            fp.FPDFPageObj_SetLineCap(line, pdfium.FPDF_LINECAP_ROUND);
            fp.FPDFPath_SetDrawMode(line, pdfium.FPDF_FILLMODE_NONE, 1);
            if (fp.FPDFAnnot_AppendObject(annot, line) == 0) {
              fp.FPDFPageObj_Destroy(line);
            }
          }
          final labelText = '${pointsToMm(lineLen).toStringAsFixed(1)} mm';
          final mFont = resolveFont(null, labelText);
          if (mFont != null) {
            final textObj = fp.FPDFPageObj_CreateTextObj(doc, mFont, 10.0);
            if (textObj != nullptr) {
              fp.FPDFText_SetText(
                textObj,
                _toUtf16Ptr(labelText, arena).cast<pdfium.FPDF_WCHAR>(),
              );
              fp.FPDFPageObj_SetFillColor(textObj, r, g, b, a);
              var labelW = labelText.length * 5.5;
              final l = arena<Float>();
              final b2 = arena<Float>();
              final r2 = arena<Float>();
              final t2 = arena<Float>();
              if (fp.FPDFPageObj_GetBounds(textObj, l, b2, r2, t2) != 0) {
                labelW = math.max(0, r2.value - l.value);
              }
              var angleRad = lineLen > 1e-3 ? math.atan2(dy, dx) : 0.0;
              if (angleRad > math.pi / 2 || angleRad < -math.pi / 2) {
                angleRad += math.pi;
              }
              final cosA = math.cos(angleRad);
              final sinA = math.sin(angleRad);
              final midX = (fromX + toX) / 2;
              final midY = (fromY + toY) / 2;
              const offsetPerp = 4.0;
              final originX =
                  midX - (labelW / 2) * cosA - offsetPerp * sinA;
              final originY =
                  midY - (labelW / 2) * sinA + offsetPerp * cosA;
              _setTextMatrix(
                fp,
                textObj,
                arena,
                x: originX,
                y: originY,
                deg: angleRad * 180.0 / math.pi,
              );
              if (fp.FPDFAnnot_AppendObject(annot, textObj) == 0) {
                fp.FPDFPageObj_Destroy(textObj);
              }
            }
          }
          break;

        case AnnotationKind.text:
          fp.FPDFAnnot_SetStringValue(
            annot,
            'Contents'.toNativeUtf8(allocator: arena).cast<Char>(),
            _toUtf16Ptr(ann.text, arena).cast<pdfium.FPDF_WCHAR>(),
          );
          if (ann.text.trim().isNotEmpty) {
            final tFont = resolveFont(ann.fontFamily, ann.text);
            if (tFont != null) {
              final frame = textBlockFrame(ann.bbox, ann.rotate);
              double measureWidth(String s) {
                if (s.isEmpty) return 0;
                final probe =
                    fp.FPDFPageObj_CreateTextObj(doc, tFont, ann.fontSize);
                if (probe == nullptr) return s.length * ann.fontSize * 0.6;
                try {
                  fp.FPDFText_SetText(
                    probe,
                    _toUtf16Ptr(s, arena).cast<pdfium.FPDF_WCHAR>(),
                  );
                  final l = arena<Float>();
                  final b2 = arena<Float>();
                  final r2 = arena<Float>();
                  final t2 = arena<Float>();
                  if (fp.FPDFPageObj_GetBounds(probe, l, b2, r2, t2) != 0) {
                    return math.max(0, r2.value - l.value);
                  }
                  return s.length * ann.fontSize * 0.6;
                } finally {
                  fp.FPDFPageObj_Destroy(probe);
                }
              }

              final lines = wrapText(
                ann.text,
                math.max(frame.run, 8),
                measureWidth,
              );
              final lineHeight = ann.fontSize * 1.2;
              for (var li = 0; li < lines.length; li++) {
                final lineStr = lines[li];
                if (lineStr.isEmpty) continue;
                final baseline = textLocalToPdf(
                  ann.bbox,
                  ann.rotate,
                  0,
                  ann.fontSize + li * lineHeight,
                );
                final textObj =
                    fp.FPDFPageObj_CreateTextObj(doc, tFont, ann.fontSize);
                if (textObj != nullptr) {
                  fp.FPDFText_SetText(
                    textObj,
                    _toUtf16Ptr(lineStr, arena).cast<pdfium.FPDF_WCHAR>(),
                  );
                  fp.FPDFPageObj_SetFillColor(textObj, r, g, b, a);
                  _setTextMatrix(
                    fp,
                    textObj,
                    arena,
                    x: bbLeft + baseline.x,
                    y: bbBottom + baseline.y,
                    deg: ann.rotate.toDouble(),
                  );
                  if (fp.FPDFAnnot_AppendObject(annot, textObj) == 0) {
                    fp.FPDFPageObj_Destroy(textObj);
                  }
                }
              }
            }
          }
          break;

        case AnnotationKind.stamp:
          final borderRect = fp.FPDFPageObj_CreateNewRect(
            bbLeft + ann.bbox.x,
            bbBottom + ann.bbox.y,
            ann.bbox.w,
            ann.bbox.h,
          );
          if (borderRect != nullptr) {
            fp.FPDFPageObj_SetStrokeColor(borderRect, r, g, b, a);
            fp.FPDFPageObj_SetStrokeWidth(borderRect, 2.0);
            fp.FPDFPageObj_SetFillColor(
              borderRect,
              r,
              g,
              b,
              (0.08 * a).round().clamp(1, 255),
            );
            fp.FPDFPath_SetDrawMode(
              borderRect,
              pdfium.FPDF_FILLMODE_WINDING,
              1,
            );
            if (fp.FPDFAnnot_AppendObject(annot, borderRect) == 0) {
              fp.FPDFPageObj_Destroy(borderRect);
            }
          }
          if (ann.label.trim().isNotEmpty) {
            final sFont = resolveFont(ann.fontFamily, ann.label);
            if (sFont != null) {
              final frame = textBlockFrame(ann.bbox, ann.rotate);
              double measureStamp(String s, double size) {
                final probe = fp.FPDFPageObj_CreateTextObj(doc, sFont, size);
                if (probe == nullptr) return s.length * size * 0.8;
                try {
                  fp.FPDFText_SetText(
                    probe,
                    _toUtf16Ptr(s, arena).cast<pdfium.FPDF_WCHAR>(),
                  );
                  final l = arena<Float>();
                  final b2 = arena<Float>();
                  final r2 = arena<Float>();
                  final t2 = arena<Float>();
                  if (fp.FPDFPageObj_GetBounds(probe, l, b2, r2, t2) != 0) {
                    return math.max(0, r2.value - l.value);
                  }
                  return s.length * size * 0.8;
                } finally {
                  fp.FPDFPageObj_Destroy(probe);
                }
              }

              final fontSize = fitStampFontSize(
                ann.label,
                frame.run,
                frame.stack,
                measureStamp,
              );
              final labelW = measureStamp(ann.label, fontSize);
              final baseline = textLocalToPdf(
                ann.bbox,
                ann.rotate,
                (frame.run - labelW) / 2,
                frame.stack / 2 + fontSize * 0.35,
              );
              final textObj = fp.FPDFPageObj_CreateTextObj(doc, sFont, fontSize);
              if (textObj != nullptr) {
                fp.FPDFText_SetText(
                  textObj,
                  _toUtf16Ptr(ann.label, arena).cast<pdfium.FPDF_WCHAR>(),
                );
                fp.FPDFPageObj_SetFillColor(textObj, r, g, b, a);
                _setTextMatrix(
                  fp,
                  textObj,
                  arena,
                  x: bbLeft + baseline.x,
                  y: bbBottom + baseline.y,
                  deg: ann.rotate.toDouble(),
                );
                if (fp.FPDFAnnot_AppendObject(annot, textObj) == 0) {
                  fp.FPDFPageObj_Destroy(textObj);
                }
              }
            }
          }
          break;

        case AnnotationKind.image:
          final cacheKey = ann.imgId.isNotEmpty ? ann.imgId : ann.refPath;
          final imgInfo = decodedImages[cacheKey];
          if (imgInfo == null) break;
          using((imgArena) {
            final imgObj = fp.FPDFPageObj_NewImageObj(doc);
            if (imgObj == nullptr) return;
            final pixelPtr = imgArena<Uint8>(imgInfo.bgra.length);
            pixelPtr.asTypedList(imgInfo.bgra.length).setAll(0, imgInfo.bgra);
            final bmp = fp.FPDFBitmap_CreateEx(
              imgInfo.w,
              imgInfo.h,
              pdfium.FPDFBitmap_BGRA,
              pixelPtr.cast<Void>(),
              imgInfo.w * 4,
            );
            if (bmp == nullptr) {
              fp.FPDFPageObj_Destroy(imgObj);
              return;
            }
            var attached = false;
            try {
              final pageArr = imgArena<pdfium.FPDF_PAGE>(1);
              pageArr[0] = page;
              if (fp.FPDFImageObj_SetBitmap(pageArr, 1, imgObj, bmp) == 0) {
                return;
              }
              final rotDeg = ((ann.rotate % 360) + 360) % 360;
              final swapped = rotDeg == 90 || rotDeg == 270;
              final drawW = swapped ? ann.bbox.h : ann.bbox.w;
              final drawH = swapped ? ann.bbox.w : ann.bbox.h;
              final rad = rotDeg * math.pi / 180.0;
              final cosA = math.cos(rad);
              final sinA = math.sin(rad);
              final aCoeff = drawW * cosA;
              final bCoeff = drawW * sinA;
              final cCoeff = -drawH * sinA;
              final dCoeff = drawH * cosA;
              final cx = bbLeft + ann.bbox.x + ann.bbox.w / 2.0;
              final cy = bbBottom + ann.bbox.y + ann.bbox.h / 2.0;
              final matrix = imgArena<pdfium.FS_MATRIX>();
              matrix.ref.a = aCoeff;
              matrix.ref.b = bCoeff;
              matrix.ref.c = cCoeff;
              matrix.ref.d = dCoeff;
              matrix.ref.e = cx - 0.5 * (aCoeff + cCoeff);
              matrix.ref.f = cy - 0.5 * (bCoeff + dCoeff);
              fp.FPDFPageObj_SetMatrix(imgObj, matrix);
              attached = fp.FPDFAnnot_AppendObject(annot, imgObj) != 0;
            } finally {
              fp.FPDFBitmap_Destroy(bmp);
              if (!attached) {
                fp.FPDFPageObj_Destroy(imgObj);
              }
            }
          });
          break;
      }
    } finally {
      fp.FPDFPage_CloseAnnot(annot);
    }
  }

  static void _setTextMatrix(
    pdfium.PDFium fp,
    pdfium.FPDF_PAGEOBJECT textObj,
    Arena arena, {
    required double x,
    required double y,
    required double deg,
  }) {
    final rad = deg * math.pi / 180.0;
    final cosA = math.cos(rad);
    final sinA = math.sin(rad);
    final matrix = arena<pdfium.FS_MATRIX>();
    matrix.ref.a = cosA;
    matrix.ref.b = sinA;
    matrix.ref.c = -sinA;
    matrix.ref.d = cosA;
    matrix.ref.e = x;
    matrix.ref.f = y;
    fp.FPDFPageObj_SetMatrix(textObj, matrix);
  }

  static int _saveTmpSeq = 0;

  static bool _saveDocToFile(
    pdfium.PDFium fp,
    pdfium.FPDF_DOCUMENT doc,
    String outputPath,
    Arena arena, {
    void Function()? beforeReplace,
  }) {
    final file = File(outputPath);
    if (!file.parent.existsSync()) file.parent.createSync(recursive: true);
    final tmpPath =
        '$outputPath.${pid}_${DateTime.now().microsecondsSinceEpoch}_${_saveTmpSeq++}.tmp';
    final tmpFile = File(tmpPath);
    RandomAccessFile? raf = tmpFile.openSync(mode: FileMode.writeOnly);
    int writeBlock(
      Pointer<pdfium.FPDF_FILEWRITE> pThis,
      Pointer<Void> pData,
      int size,
    ) {
      if (size <= 0) return 1;
      try {
        raf!.writeFromSync(pData.cast<Uint8>().asTypedList(size));
        return 1;
      } catch (_) {
        return 0;
      }
    }

    final callable = _NativeFileWriteCallable.isolateLocal(
      writeBlock,
      exceptionalReturn: 0,
    );
    var saved = false;
    try {
      final fw = arena<pdfium.FPDF_FILEWRITE>();
      fw.ref.version = 1;
      fw.ref.WriteBlock = callable.nativeFunction;
      saved = fp.FPDF_SaveAsCopy(doc, fw, pdfium.FPDF_NO_INCREMENTAL) != 0;
    } finally {
      callable.close();
      try {
        raf.closeSync();
      } catch (_) {}
      raf = null;
    }

    try {
      if (!saved) return false;
      beforeReplace?.call();
      try {
        tmpFile.renameSync(outputPath);
      } catch (_) {
        tmpFile.copySync(outputPath);
      }
      return true;
    } finally {
      if (tmpFile.existsSync()) {
        try {
          tmpFile.deleteSync();
        } catch (_) {}
      }
    }
  }

  // =========================================================================
  // 页面操作（全部在 PDFium worker isolate 执行，写入到 targetPath）
  // =========================================================================

  static Future<PdfOpSaveResult> deletePages({
    required String sourcePath,
    required String targetPath,
    required List<int> pagesZeroBased,
    String? password,
  }) {
    return PdfrxEntryFunctions.instance.compute(
      (msg) => _deletePagesSync(
        msg.sourcePath,
        msg.targetPath,
        msg.pages,
        msg.password,
      ),
      (
        sourcePath: sourcePath,
        targetPath: targetPath,
        pages: pagesZeroBased,
        password: password,
      ),
    );
  }

  static PdfOpSaveResult _deletePagesSync(
    String sourcePath,
    String targetPath,
    List<int> pages,
    String? password,
  ) {
    final fp = _getPdfium();
    return using((arena) {
      final doc = fp.FPDF_LoadDocument(
        sourcePath.toNativeUtf8(allocator: arena).cast<Char>(),
        password == null
            ? nullptr.cast<Char>()
            : password.toNativeUtf8(allocator: arena).cast<Char>(),
      );
      if (doc == nullptr) {
        return const PdfOpSaveResult(ok: false, error: '无法打开文档');
      }
      try {
        final count = fp.FPDF_GetPageCount(doc);
        final targets = pages.where((p) => p >= 0 && p < count).toSet().toList()
          ..sort((a, b) => b.compareTo(a));
        if (targets.isEmpty) {
          return const PdfOpSaveResult(ok: false, error: '未指定要删除的页面');
        }
        if (targets.length >= count) {
          return const PdfOpSaveResult(ok: false, error: '不能删除全部页面');
        }
        var docClosed = false;
        try {
          for (final idx in targets) {
            fp.FPDFPage_Delete(doc, idx);
          }
          final ok = _saveDocToFile(
            fp,
            doc,
            targetPath,
            arena,
            beforeReplace: () {
              if (!docClosed) {
                fp.FPDF_CloseDocument(doc);
                docClosed = true;
              }
            },
          );
          return PdfOpSaveResult(
            ok: ok,
            error: ok ? null : '写入失败',
            pageCount: ok ? count - targets.length : 0,
          );
        } finally {
          if (!docClosed) fp.FPDF_CloseDocument(doc);
        }
      } catch (_) {
        fp.FPDF_CloseDocument(doc);
        rethrow;
      }
    });
  }

  static Future<PdfOpSaveResult> rotatePages({
    required String sourcePath,
    required String targetPath,
    required Map<int, int> deltasByPage,
    String? password,
  }) {
    return PdfrxEntryFunctions.instance.compute(
      (msg) => _rotatePagesSync(
        msg.sourcePath,
        msg.targetPath,
        msg.deltas,
        msg.password,
      ),
      (
        sourcePath: sourcePath,
        targetPath: targetPath,
        deltas: deltasByPage,
        password: password,
      ),
    );
  }

  static PdfOpSaveResult _rotatePagesSync(
    String sourcePath,
    String targetPath,
    Map<int, int> deltas,
    String? password,
  ) {
    final fp = _getPdfium();
    return using((arena) {
      final doc = fp.FPDF_LoadDocument(
        sourcePath.toNativeUtf8(allocator: arena).cast<Char>(),
        password == null
            ? nullptr.cast<Char>()
            : password.toNativeUtf8(allocator: arena).cast<Char>(),
      );
      if (doc == nullptr) {
        return const PdfOpSaveResult(ok: false, error: '无法打开文档');
      }
      var docClosed = false;
      try {
        final count = fp.FPDF_GetPageCount(doc);
        for (final entry in deltas.entries) {
          if (entry.key < 0 || entry.key >= count) continue;
          final steps = ((entry.value ~/ 90) % 4 + 4) % 4;
          if (steps == 0) continue;
          final page = fp.FPDF_LoadPage(doc, entry.key);
          if (page == nullptr) continue;
          try {
            final rawRot = fp.FPDFPage_GetRotation(page);
            final cur = rawRot < 0 ? 0 : rawRot % 4;
            fp.FPDFPage_SetRotation(page, (cur + steps) % 4);
          } finally {
            fp.FPDF_ClosePage(page);
          }
        }
        final ok = _saveDocToFile(
          fp,
          doc,
          targetPath,
          arena,
          beforeReplace: () {
            if (!docClosed) {
              fp.FPDF_CloseDocument(doc);
              docClosed = true;
            }
          },
        );
        return PdfOpSaveResult(
          ok: ok,
          error: ok ? null : '写入失败',
          pageCount: count,
        );
      } finally {
        if (!docClosed) fp.FPDF_CloseDocument(doc);
      }
    });
  }

  static Future<PdfOpSaveResult> insertBlankPage({
    required String sourcePath,
    required String targetPath,
    required int afterIndex,
    String? password,
  }) {
    return PdfrxEntryFunctions.instance.compute(
      (msg) => _insertBlankSync(
        msg.sourcePath,
        msg.targetPath,
        msg.afterIndex,
        msg.password,
      ),
      (
        sourcePath: sourcePath,
        targetPath: targetPath,
        afterIndex: afterIndex,
        password: password,
      ),
    );
  }

  static PdfOpSaveResult _insertBlankSync(
    String sourcePath,
    String targetPath,
    int afterIndex,
    String? password,
  ) {
    final fp = _getPdfium();
    return using((arena) {
      final doc = fp.FPDF_LoadDocument(
        sourcePath.toNativeUtf8(allocator: arena).cast<Char>(),
        password == null
            ? nullptr.cast<Char>()
            : password.toNativeUtf8(allocator: arena).cast<Char>(),
      );
      if (doc == nullptr) {
        return const PdfOpSaveResult(ok: false, error: '无法打开文档');
      }
      var docClosed = false;
      try {
        final count = fp.FPDF_GetPageCount(doc);
        final insertAt = (afterIndex + 1).clamp(0, count);
        final refIndex =
            (insertAt - 1).clamp(0, math.max<int>(0, count - 1)).toInt();
        var width = 595.28;
        var height = 841.89;
        if (count > 0) {
          final wPtr = arena<Double>();
          final hPtr = arena<Double>();
          if (fp.FPDF_GetPageSizeByIndex(doc, refIndex, wPtr, hPtr) != 0) {
            width = wPtr.value;
            height = hPtr.value;
          }
        }
        final newPage = fp.FPDFPage_New(doc, insertAt, width, height);
        if (newPage == nullptr) {
          return const PdfOpSaveResult(ok: false, error: '新建空白页失败');
        }
        fp.FPDFPage_GenerateContent(newPage);
        fp.FPDF_ClosePage(newPage);
        final outCount = fp.FPDF_GetPageCount(doc);
        final ok = _saveDocToFile(
          fp,
          doc,
          targetPath,
          arena,
          beforeReplace: () {
            if (!docClosed) {
              fp.FPDF_CloseDocument(doc);
              docClosed = true;
            }
          },
        );
        return PdfOpSaveResult(
          ok: ok,
          error: ok ? null : '写入失败',
          pageCount: outCount,
        );
      } finally {
        if (!docClosed) fp.FPDF_CloseDocument(doc);
      }
    });
  }

  static Future<PdfOpSaveResult> movePage({
    required String sourcePath,
    required String targetPath,
    required int fromIndex,
    required int toIndex,
    String? password,
  }) {
    return PdfrxEntryFunctions.instance.compute(
      (msg) => _movePageSync(
        msg.sourcePath,
        msg.targetPath,
        msg.fromIndex,
        msg.toIndex,
        msg.password,
      ),
      (
        sourcePath: sourcePath,
        targetPath: targetPath,
        fromIndex: fromIndex,
        toIndex: toIndex,
        password: password,
      ),
    );
  }

  static PdfOpSaveResult _movePageSync(
    String sourcePath,
    String targetPath,
    int fromIndex,
    int toIndex,
    String? password,
  ) {
    final fp = _getPdfium();
    return using((arena) {
      final doc = fp.FPDF_LoadDocument(
        sourcePath.toNativeUtf8(allocator: arena).cast<Char>(),
        password == null
            ? nullptr.cast<Char>()
            : password.toNativeUtf8(allocator: arena).cast<Char>(),
      );
      if (doc == nullptr) {
        return const PdfOpSaveResult(ok: false, error: '无法打开文档');
      }
      var docClosed = false;
      try {
        final count = fp.FPDF_GetPageCount(doc);
        if (fromIndex < 0 ||
            fromIndex >= count ||
            toIndex < 0 ||
            toIndex >= count ||
            fromIndex == toIndex) {
          return const PdfOpSaveResult(ok: false, error: '目标页位置无效');
        }
        final dest = toIndex;
        final idxPtr = arena<Int>(1);
        idxPtr[0] = fromIndex;
        if (fp.FPDF_MovePages(doc, idxPtr, 1, dest) == 0) {
          return const PdfOpSaveResult(ok: false, error: '移动页面失败');
        }
        final ok = _saveDocToFile(
          fp,
          doc,
          targetPath,
          arena,
          beforeReplace: () {
            if (!docClosed) {
              fp.FPDF_CloseDocument(doc);
              docClosed = true;
            }
          },
        );
        return PdfOpSaveResult(
          ok: ok,
          error: ok ? null : '写入失败',
          pageCount: count,
        );
      } finally {
        if (!docClosed) fp.FPDF_CloseDocument(doc);
      }
    });
  }

  static Future<PdfOpSaveResult> mergePdfs({
    required List<({String path, List<int>? pages, String? password})> specs,
    required String targetPath,
  }) {
    return PdfrxEntryFunctions.instance.compute(
      (msg) => _mergePdfsSync(msg.specs, msg.targetPath),
      (specs: specs, targetPath: targetPath),
    );
  }

  static PdfOpSaveResult _mergePdfsSync(
    List<({String path, List<int>? pages, String? password})> specs,
    String targetPath,
  ) {
    final fp = _getPdfium();
    return using((arena) {
      final outDoc = fp.FPDF_CreateNewDocument();
      if (outDoc == nullptr) {
        return const PdfOpSaveResult(ok: false, error: '无法创建输出文档');
      }
      try {
        var insertAt = 0;
        for (final spec in specs) {
          final src = fp.FPDF_LoadDocument(
            spec.path.toNativeUtf8(allocator: arena).cast<Char>(),
            spec.password == null
                ? nullptr.cast<Char>()
                : spec.password!.toNativeUtf8(allocator: arena).cast<Char>(),
          );
          if (src == nullptr) {
            return PdfOpSaveResult(
              ok: false,
              error: '无法打开待合并文件：${p.basename(spec.path)}',
            );
          }
          try {
            final srcCount = fp.FPDF_GetPageCount(src);
            final pages = spec.pages ?? List<int>.generate(srcCount, (i) => i);
            final valid =
                pages.where((idx) => idx >= 0 && idx < srcCount).toList();
            if (valid.isNotEmpty) {
              final idxPtr = arena<Int>(valid.length);
              for (var i = 0; i < valid.length; i++) {
                idxPtr[i] = valid[i];
              }
              if (fp.FPDF_ImportPagesByIndex(
                    outDoc,
                    src,
                    idxPtr,
                    valid.length,
                    insertAt,
                  ) ==
                  0) {
                return PdfOpSaveResult(
                  ok: false,
                  error: '导入页面失败：${p.basename(spec.path)}',
                );
              }
              insertAt += valid.length;
            }
          } finally {
            fp.FPDF_CloseDocument(src);
          }
        }
        final ok = _saveDocToFile(fp, outDoc, targetPath, arena);
        return PdfOpSaveResult(
          ok: ok,
          error: ok ? null : '保存合并文件失败',
          pageCount: insertAt,
        );
      } finally {
        fp.FPDF_CloseDocument(outDoc);
      }
    });
  }

  /// 提取 / 导出指定页为新 PDF
  static Future<PdfOpSaveResult> exportPdfPages({
    required String sourcePath,
    required String targetPath,
    required List<int> pagesZeroBased,
    required bool includeAnnotations,
    List<PdfAnnotationItem> annotations = const [],
    String? password,
    Map<String, Uint8List> resolvedImages = const {},
  }) async {
    final tmpExtract = p.join(
      Directory.systemTemp.path,
      'pdf_ed_ext_${DateTime.now().microsecondsSinceEpoch}.pdf',
    );
    final extRes = await PdfrxEntryFunctions.instance.compute(
      (msg) => _extractPagesRawSync(
        msg.sourcePath,
        msg.tmpExtract,
        msg.pages,
        msg.includeAnnotations,
        msg.password,
      ),
      (
        sourcePath: sourcePath,
        tmpExtract: tmpExtract,
        pages: pagesZeroBased,
        includeAnnotations: includeAnnotations,
        password: password,
      ),
    );
    if (!extRes.ok) {
      await File(tmpExtract).delete().catchError((_) => File(tmpExtract));
      return extRes;
    }

    try {
      if (!includeAnnotations) {
        final outFile = File(tmpExtract);
        final parent = File(targetPath).parent;
        if (!parent.existsSync()) parent.createSync(recursive: true);
        try {
          try {
            await outFile.rename(targetPath);
          } catch (_) {
            await outFile.copy(targetPath);
          }
          return extRes;
        } catch (e) {
          return PdfOpSaveResult(ok: false, error: '写入导出文件失败: $e');
        }
      }

      // 将当前模型中的注释按输出页序映射后写入新文件
      final pageIndexMap = <int, int>{};
      for (var i = 0; i < pagesZeroBased.length; i++) {
        pageIndexMap[pagesZeroBased[i]] = i;
      }
      final mapped = <PdfAnnotationItem>[];
      for (final ann in annotations) {
        final newPage = pageIndexMap[ann.page];
        if (newPage != null) {
          mapped.add(ann.copyWith(page: newPage));
        }
      }
      return await saveWithAnnotations(
        sourcePath: tmpExtract,
        targetPath: targetPath,
        annotations: mapped,
        resolvedImages: resolvedImages,
      );
    } finally {
      await File(tmpExtract).delete().catchError((_) => File(tmpExtract));
    }
  }

  static PdfOpSaveResult _extractPagesRawSync(
    String sourcePath,
    String targetPath,
    List<int> pages,
    bool includeAnnotations,
    String? password,
  ) {
    final fp = _getPdfium();
    return using((arena) {
      final src = fp.FPDF_LoadDocument(
        sourcePath.toNativeUtf8(allocator: arena).cast<Char>(),
        password == null
            ? nullptr.cast<Char>()
            : password.toNativeUtf8(allocator: arena).cast<Char>(),
      );
      if (src == nullptr) {
        return const PdfOpSaveResult(ok: false, error: '无法打开源文件');
      }
      final outDoc = fp.FPDF_CreateNewDocument();
      if (outDoc == nullptr) {
        fp.FPDF_CloseDocument(src);
        return const PdfOpSaveResult(ok: false, error: '无法创建导出文档');
      }
      try {
        final count = fp.FPDF_GetPageCount(src);
        final valid = pages.where((i) => i >= 0 && i < count).toList();
        if (valid.isEmpty) {
          return const PdfOpSaveResult(ok: false, error: '导出页码为空');
        }
        final idxPtr = arena<Int>(valid.length);
        for (var i = 0; i < valid.length; i++) {
          idxPtr[i] = valid[i];
        }
        if (fp.FPDF_ImportPagesByIndex(outDoc, src, idxPtr, valid.length, 0) ==
            0) {
          return const PdfOpSaveResult(ok: false, error: '提取页面失败');
        }
        if (!includeAnnotations) {
          for (var i = 0; i < valid.length; i++) {
            final pHandle = fp.FPDF_LoadPage(outDoc, i);
            if (pHandle == nullptr) continue;
            try {
              final ac = fp.FPDFPage_GetAnnotCount(pHandle);
              for (var ai = ac - 1; ai >= 0; ai--) {
                fp.FPDFPage_RemoveAnnot(pHandle, ai);
              }
              fp.FPDFPage_GenerateContent(pHandle);
            } finally {
              fp.FPDF_ClosePage(pHandle);
            }
          }
        }
        final ok = _saveDocToFile(fp, outDoc, targetPath, arena);
        return PdfOpSaveResult(
          ok: ok,
          error: ok ? null : '导出写入失败',
          pageCount: valid.length,
        );
      } finally {
        fp.FPDF_CloseDocument(outDoc);
        fp.FPDF_CloseDocument(src);
      }
    });
  }

  static Future<PdfOpSaveResult> applyPageNumbers({
    required String sourcePath,
    required String targetPath,
    required List<int> pagesZeroBased,
    required PageNumberFormat format,
    required int startNumber,
    required PageNumberPosition position,
    required double fontSize,
    required double marginPt,
    String? password,
  }) async {
    Uint8List? cjkBytes;
    if (format.needsCjk) {
      cjkBytes = await SystemFontsService.readDefaultCjkFontBytes();
      if (cjkBytes == null) {
        return const PdfOpSaveResult(
          ok: false,
          error: '系统缺少可嵌入的中文字体，无法写入中文页码格式',
        );
      }
    }
    return PdfrxEntryFunctions.instance.compute(
      (msg) => _applyPageNumbersSync(msg),
      (
        sourcePath: sourcePath,
        targetPath: targetPath,
        pages: pagesZeroBased,
        format: format,
        startNumber: startNumber,
        position: position,
        fontSize: fontSize,
        marginPt: marginPt,
        password: password,
        cjkBytes: cjkBytes,
      ),
    );
  }

  static ({double x, double y}) _visualToPdfPoint({
    required double visX,
    required double visY,
    required double rawW,
    required double rawH,
    required int pageRotSteps,
    double bbLeft = 0.0,
    double bbBottom = 0.0,
  }) {
    final (ux, uy) = switch (pageRotSteps % 4) {
      1 => (rawW - visY, visX),
      2 => (rawW - visX, rawH - visY),
      3 => (visY, rawH - visX),
      _ => (visX, visY),
    };
    return (x: bbLeft + ux, y: bbBottom + uy);
  }

  /// 为非加密 PDF 剥离已有 /PdEditorData 批注到副本，防止实时画布叠加重影。
  static Future<PdfOpSaveResult> stripPdEditorAnnotations({
    required String sourcePath,
    required String targetPath,
    String? password,
  }) =>
      PdfrxEntryFunctions.instance.compute(
        (msg) => _stripPdEditorAnnotationsSync(
          msg.sourcePath,
          msg.targetPath,
          msg.password,
        ),
        (
          sourcePath: sourcePath,
          targetPath: targetPath,
          password: password,
        ),
      );

  static PdfOpSaveResult _stripPdEditorAnnotationsSync(
    String sourcePath,
    String targetPath,
    String? password,
  ) {
    final fp = _getPdfium();
    return using((arena) {
      final doc = fp.FPDF_LoadDocument(
        sourcePath.toNativeUtf8(allocator: arena).cast<Char>(),
        password == null
            ? nullptr.cast<Char>()
            : password.toNativeUtf8(allocator: arena).cast<Char>(),
      );
      if (doc == nullptr) {
        return const PdfOpSaveResult(ok: false, error: '无法打开文档');
      }
      var docClosed = false;
      try {
        final count = fp.FPDF_GetPageCount(doc);
        final keyPtr =
            'PdEditorData'.toNativeUtf8(allocator: arena).cast<Char>();
        for (var pi = 0; pi < count; pi++) {
          final page = fp.FPDF_LoadPage(doc, pi);
          if (page == nullptr) continue;
          try {
            var changed = false;
            final existingCount = fp.FPDFPage_GetAnnotCount(page);
            for (var ai = existingCount - 1; ai >= 0; ai--) {
              final annot = fp.FPDFPage_GetAnnot(page, ai);
              if (annot == nullptr) continue;
              final hasOwn = fp.FPDFAnnot_HasKey(annot, keyPtr) != 0;
              fp.FPDFPage_CloseAnnot(annot);
              if (hasOwn) {
                fp.FPDFPage_RemoveAnnot(page, ai);
                changed = true;
              }
            }
            if (changed) {
              fp.FPDFPage_GenerateContent(page);
            }
          } finally {
            fp.FPDF_ClosePage(page);
          }
        }
        final ok = _saveDocToFile(
          fp,
          doc,
          targetPath,
          arena,
          beforeReplace: () {
            if (!docClosed) {
              fp.FPDF_CloseDocument(doc);
              docClosed = true;
            }
          },
        );
        return PdfOpSaveResult(
          ok: ok,
          error: ok ? null : '剥离批注副本失败',
          pageCount: count,
        );
      } finally {
        if (!docClosed) fp.FPDF_CloseDocument(doc);
      }
    });
  }

  static PdfOpSaveResult _applyPageNumbersSync(
    ({
      String sourcePath,
      String targetPath,
      List<int> pages,
      PageNumberFormat format,
      int startNumber,
      PageNumberPosition position,
      double fontSize,
      double marginPt,
      String? password,
      Uint8List? cjkBytes,
    }) msg,
  ) {
    final fp = _getPdfium();
    return using((arena) {
      final doc = fp.FPDF_LoadDocument(
        msg.sourcePath.toNativeUtf8(allocator: arena).cast<Char>(),
        msg.password == null
            ? nullptr.cast<Char>()
            : msg.password!.toNativeUtf8(allocator: arena).cast<Char>(),
      );
      if (doc == nullptr) {
        return const PdfOpSaveResult(ok: false, error: '无法打开文档');
      }
      pdfium.FPDF_FONT? font;
      var docClosed = false;
      try {
        final count = fp.FPDF_GetPageCount(doc);
        font = msg.cjkBytes != null
            ? _loadTtfFont(fp, doc, msg.cjkBytes!, arena)
            : fp.FPDFText_LoadStandardFont(
                doc,
                'Helvetica'.toNativeUtf8(allocator: arena).cast<Char>(),
              );
        if (font == null || font == nullptr) {
          return const PdfOpSaveResult(ok: false, error: '加载页码字体失败');
        }
        final targetPages = msg.pages.isEmpty
            ? List<int>.generate(count, (i) => i)
            : msg.pages.where((i) => i >= 0 && i < count).toList();
        final totalLabel = msg.startNumber + targetPages.length - 1;
        final wPtr = arena<Double>();
        final hPtr = arena<Double>();
        final bboxPtr = arena<pdfium.FS_RECTF>();

        for (var idx = 0; idx < targetPages.length; idx++) {
          final pi = targetPages[idx];
          if (fp.FPDF_GetPageSizeByIndex(doc, pi, wPtr, hPtr) == 0) continue;
          final visW = wPtr.value;
          final visH = hPtr.value;
          final page = fp.FPDF_LoadPage(doc, pi);
          if (page == nullptr) continue;
          try {
            final rawRot = fp.FPDFPage_GetRotation(page);
            final pageRot = rawRot < 0 ? 0 : rawRot % 4;
            var bbLeft = 0.0;
            var bbBottom = 0.0;
            var rawW = pageRot.isOdd ? visH : visW;
            var rawH = pageRot.isOdd ? visW : visH;
            if (fp.FPDF_GetPageBoundingBox(page, bboxPtr) != 0) {
              bbLeft = bboxPtr.ref.left;
              bbBottom = bboxPtr.ref.bottom;
              final bw = bboxPtr.ref.right - bboxPtr.ref.left;
              final bh = bboxPtr.ref.top - bboxPtr.ref.bottom;
              if (bw > 0 && bh > 0) {
                rawW = bw;
                rawH = bh;
              }
            }
            final effVisW = pageRot.isOdd ? rawH : rawW;
            final effVisH = pageRot.isOdd ? rawW : rawH;
            final label =
                msg.format.format(msg.startNumber + idx, totalLabel);
            final textObj =
                fp.FPDFPageObj_CreateTextObj(doc, font, msg.fontSize);
            if (textObj == nullptr) continue;
            fp.FPDFText_SetText(
              textObj,
              _toUtf16Ptr(label, arena).cast<pdfium.FPDF_WCHAR>(),
            );
            fp.FPDFPageObj_SetFillColor(textObj, 33, 37, 41, 255);
            final l = arena<Float>();
            final b = arena<Float>();
            final r = arena<Float>();
            final t = arena<Float>();
            var textW = label.length * msg.fontSize * 0.55;
            if (fp.FPDFPageObj_GetBounds(textObj, l, b, r, t) != 0) {
              textW = math.max(0, r.value - l.value);
            }
            final vx = switch (msg.position) {
              PageNumberPosition.bottomCenter ||
              PageNumberPosition.topCenter =>
                (effVisW - textW) / 2,
              PageNumberPosition.bottomRight ||
              PageNumberPosition.topRight =>
                math.max(msg.marginPt, effVisW - msg.marginPt - textW),
            };
            final vy = switch (msg.position) {
              PageNumberPosition.bottomCenter ||
              PageNumberPosition.bottomRight =>
                msg.marginPt,
              PageNumberPosition.topCenter ||
              PageNumberPosition.topRight =>
                math.max(msg.marginPt, effVisH - msg.marginPt - msg.fontSize),
            };
            final pt = _visualToPdfPoint(
              visX: vx,
              visY: vy,
              rawW: rawW,
              rawH: rawH,
              pageRotSteps: pageRot,
              bbLeft: bbLeft,
              bbBottom: bbBottom,
            );
            _setTextMatrix(
              fp,
              textObj,
              arena,
              x: pt.x,
              y: pt.y,
              deg: pageRot * 90.0,
            );
            fp.FPDFPage_InsertObject(page, textObj);
            fp.FPDFPage_GenerateContent(page);
          } finally {
            fp.FPDF_ClosePage(page);
          }
        }
        final ok = _saveDocToFile(
          fp,
          doc,
          msg.targetPath,
          arena,
          beforeReplace: () {
            if (font != null && font != nullptr) {
              fp.FPDFFont_Close(font!);
              font = null;
            }
            if (!docClosed) {
              fp.FPDF_CloseDocument(doc);
              docClosed = true;
            }
          },
        );
        return PdfOpSaveResult(
          ok: ok,
          error: ok ? null : '写入页码失败',
          pageCount: count,
        );
      } finally {
        if (font != null && font != nullptr) fp.FPDFFont_Close(font!);
        if (!docClosed) fp.FPDF_CloseDocument(doc);
      }
    });
  }

  static Future<PdfOpSaveResult> applyWatermark({
    required String sourcePath,
    required String targetPath,
    required List<int> pagesZeroBased,
    required String text,
    required double fontSize,
    required double opacity,
    required double rotationDeg,
    required bool tile,
    required String colorHex,
    String? password,
  }) async {
    Uint8List? cjkBytes;
    if (RegExp(r'[^\x00-\x7F]').hasMatch(text)) {
      cjkBytes = await SystemFontsService.readDefaultCjkFontBytes();
      if (cjkBytes == null) {
        return const PdfOpSaveResult(
          ok: false,
          error: '系统缺少可嵌入的中文字体，无法写入中文水印',
        );
      }
    }
    return PdfrxEntryFunctions.instance.compute(
      (msg) => _applyWatermarkSync(msg),
      (
        sourcePath: sourcePath,
        targetPath: targetPath,
        pages: pagesZeroBased,
        text: text,
        fontSize: fontSize,
        opacity: opacity,
        rotationDeg: rotationDeg,
        tile: tile,
        colorHex: colorHex,
        password: password,
        cjkBytes: cjkBytes,
      ),
    );
  }

  static PdfOpSaveResult _applyWatermarkSync(
    ({
      String sourcePath,
      String targetPath,
      List<int> pages,
      String text,
      double fontSize,
      double opacity,
      double rotationDeg,
      bool tile,
      String colorHex,
      String? password,
      Uint8List? cjkBytes,
    }) msg,
  ) {
    final fp = _getPdfium();
    return using((arena) {
      final doc = fp.FPDF_LoadDocument(
        msg.sourcePath.toNativeUtf8(allocator: arena).cast<Char>(),
        msg.password == null
            ? nullptr.cast<Char>()
            : msg.password!.toNativeUtf8(allocator: arena).cast<Char>(),
      );
      if (doc == nullptr) {
        return const PdfOpSaveResult(ok: false, error: '无法打开文档');
      }
      pdfium.FPDF_FONT? font;
      try {
        final count = fp.FPDF_GetPageCount(doc);
        font = msg.cjkBytes != null
            ? _loadTtfFont(fp, doc, msg.cjkBytes!, arena)
            : fp.FPDFText_LoadStandardFont(
                doc,
                'Helvetica'.toNativeUtf8(allocator: arena).cast<Char>(),
              );
        if (font == null || font == nullptr) {
          return const PdfOpSaveResult(ok: false, error: '加载水印字体失败');
        }
        final col = hexToColor(msg.colorHex);
        final r = (col.r * 255).round().clamp(0, 255);
        final g = (col.g * 255).round().clamp(0, 255);
        final b = (col.b * 255).round().clamp(0, 255);
        final a = (msg.opacity * 255).round().clamp(1, 255);

        // 测量一次文字尺寸
        var textW = msg.text.length * msg.fontSize * 0.6;
        final probe = fp.FPDFPageObj_CreateTextObj(doc, font, msg.fontSize);
        if (probe != nullptr) {
          fp.FPDFText_SetText(
            probe,
            _toUtf16Ptr(msg.text, arena).cast<pdfium.FPDF_WCHAR>(),
          );
          final l = arena<Float>();
          final b2 = arena<Float>();
          final r2 = arena<Float>();
          final t2 = arena<Float>();
          if (fp.FPDFPageObj_GetBounds(probe, l, b2, r2, t2) != 0) {
            textW = math.max(8, r2.value - l.value);
          }
          fp.FPDFPageObj_Destroy(probe);
        }

        final targetPages = msg.pages.isEmpty
            ? List<int>.generate(count, (i) => i)
            : msg.pages.where((i) => i >= 0 && i < count).toList();
        final wPtr = arena<Double>();
        final hPtr = arena<Double>();
        final bboxPtr = arena<pdfium.FS_RECTF>();

        for (final pi in targetPages) {
          if (fp.FPDF_GetPageSizeByIndex(doc, pi, wPtr, hPtr) == 0) continue;
          final visW = wPtr.value;
          final visH = hPtr.value;
          final page = fp.FPDF_LoadPage(doc, pi);
          if (page == nullptr) continue;
          try {
            final rawRot = fp.FPDFPage_GetRotation(page);
            final pageRot = rawRot < 0 ? 0 : rawRot % 4;
            var bbLeft = 0.0;
            var bbBottom = 0.0;
            var rawW = pageRot.isOdd ? visH : visW;
            var rawH = pageRot.isOdd ? visW : visH;
            if (fp.FPDF_GetPageBoundingBox(page, bboxPtr) != 0) {
              bbLeft = bboxPtr.ref.left;
              bbBottom = bboxPtr.ref.bottom;
              final bw = bboxPtr.ref.right - bboxPtr.ref.left;
              final bh = bboxPtr.ref.top - bboxPtr.ref.bottom;
              if (bw > 0 && bh > 0) {
                rawW = bw;
                rawH = bh;
              }
            }
            final effVisW = pageRot.isOdd ? rawH : rawW;
            final effVisH = pageRot.isOdd ? rawW : rawH;
            final rad = (msg.rotationDeg + pageRot * 90.0) * math.pi / 180.0;
            final cosA = math.cos(rad);
            final sinA = math.sin(rad);
            final spots = watermarkPlacements(
              pageWidth: effVisW,
              pageHeight: effVisH,
              textWidth: textW,
              textHeight: msg.fontSize,
              tile: msg.tile,
            );
            for (final spot in spots) {
              final textObj =
                  fp.FPDFPageObj_CreateTextObj(doc, font, msg.fontSize);
              if (textObj == nullptr) continue;
              fp.FPDFText_SetText(
                textObj,
                _toUtf16Ptr(msg.text, arena).cast<pdfium.FPDF_WCHAR>(),
              );
              fp.FPDFPageObj_SetFillColor(textObj, r, g, b, a);
              final centerPdf = _visualToPdfPoint(
                visX: spot.x,
                visY: spot.y,
                rawW: rawW,
                rawH: rawH,
                pageRotSteps: pageRot,
                bbLeft: bbLeft,
                bbBottom: bbBottom,
              );
              // 围绕中心旋转再平移到映射后的 PDF 坐标
              final cx = textW / 2;
              final cy = msg.fontSize * 0.35;
              final e = centerPdf.x - (cx * cosA - cy * sinA);
              final f = centerPdf.y - (cx * sinA + cy * cosA);
              final matrix = arena<pdfium.FS_MATRIX>();
              matrix.ref.a = cosA;
              matrix.ref.b = sinA;
              matrix.ref.c = -sinA;
              matrix.ref.d = cosA;
              matrix.ref.e = e;
              matrix.ref.f = f;
              fp.FPDFPageObj_SetMatrix(textObj, matrix);
              fp.FPDFPage_InsertObject(page, textObj);
            }
            fp.FPDFPage_GenerateContent(page);
          } finally {
            fp.FPDF_ClosePage(page);
          }
        }
        final ok = _saveDocToFile(fp, doc, msg.targetPath, arena);
        return PdfOpSaveResult(
          ok: ok,
          error: ok ? null : '写入水印失败',
          pageCount: count,
        );
      } finally {
        if (font != null && font != nullptr) fp.FPDFFont_Close(font);
        fp.FPDF_CloseDocument(doc);
      }
    });
  }

  /// 批量拆分（在 chunk 边界检查 isCancelled）
  static Future<List<SplitTaskOutcome>> splitBatch({
    required List<SplitTaskInput> tasks,
    required String? outputDir,
    required bool includeAnnotations,
    Map<String, Uint8List> resolvedImages = const {},
    void Function(int processedFiles, int totalFiles, int outputCount)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final results = <SplitTaskOutcome>[];
    var processed = 0;
    var outputs = 0;
    for (final task in tasks) {
      if (isCancelled?.call() ?? false) break;
      final dir = outputDir ?? p.dirname(task.path);
      final rawStem =
          (task.outputStem != null && task.outputStem!.trim().isNotEmpty)
              ? task.outputStem!.trim()
              : p.basenameWithoutExtension(task.path);
      final stem = rawStem.isEmpty ? 'document' : rawStem;
      final written = <String>[];
      String? taskErr;

      var taskAnnotations = task.annotations ?? const <PdfAnnotationItem>[];
      if (includeAnnotations && !task.isCurrentDoc) {
        final inspected = await inspectDocument(
          task.path,
          password: task.password,
        );
        taskAnnotations = inspected.annotations;
      }

      for (var ci = 0; ci < task.chunks.length; ci++) {
        if (isCancelled?.call() ?? false) break;
        final chunk = task.chunks[ci];
        final target = _uniqueFilePath(dir, '$stem-${ci + 1}.pdf');
        final res = await exportPdfPages(
          sourcePath: task.path,
          targetPath: target,
          pagesZeroBased: chunk,
          includeAnnotations: includeAnnotations,
          annotations: taskAnnotations,
          password: task.password,
          resolvedImages: resolvedImages,
        );
        if (!res.ok) {
          taskErr = res.error ?? '拆分失败';
          break;
        }
        written.add(target);
        outputs++;
        onProgress?.call(processed + 1, tasks.length, outputs);
      }

      if (taskErr != null && written.isEmpty) {
        results.add(SplitTaskOutcome(path: task.path, ok: false, error: taskErr));
      } else {
        results.add(SplitTaskOutcome(
          path: task.path,
          ok: taskErr == null,
          outputs: written,
          error: taskErr,
        ));
      }
      processed++;
    }
    return results;
  }

  static String _uniqueFilePath(String dir, String baseFileName) {
    final ext = p.extension(baseFileName);
    final stem = p.basenameWithoutExtension(baseFileName);
    var candidate = p.join(dir, baseFileName);
    var idx = 1;
    while (File(candidate).existsSync()) {
      candidate = p.join(dir, '$stem-$idx$ext');
      idx++;
    }
    return candidate;
  }

  /// 为「统一页面方向」提取每页文字主方向角（0/90/180/270，或 null）
  static Future<List<int?>> detectAllPageTextAngles(
    String filePath, {
    String? password,
  }) {
    return PdfrxEntryFunctions.instance.compute(
      (msg) => _detectTextAnglesSync(msg.path, msg.password),
      (path: filePath, password: password),
    );
  }

  static List<int?> _detectTextAnglesSync(String filePath, String? password) {
    final fp = _getPdfium();
    return using((arena) {
      final doc = fp.FPDF_LoadDocument(
        filePath.toNativeUtf8(allocator: arena).cast<Char>(),
        password == null
            ? nullptr.cast<Char>()
            : password.toNativeUtf8(allocator: arena).cast<Char>(),
      );
      if (doc == nullptr) return const [];
      try {
        final count = fp.FPDF_GetPageCount(doc);
        final out = <int?>[];
        for (var i = 0; i < count; i++) {
          final page = fp.FPDF_LoadPage(doc, i);
          if (page == nullptr) {
            out.add(null);
            continue;
          }
          try {
            final pageRot = (fp.FPDFPage_GetRotation(page) % 4) * 90;
            final textPage = fp.FPDFText_LoadPage(page);
            if (textPage == nullptr) {
              out.add(null);
              continue;
            }
            try {
              final charCount = fp.FPDFText_CountChars(textPage);
              if (charCount < 2) {
                out.add(null);
                continue;
              }
              final tally = <int, int>{};
              final step = charCount > 400 ? (charCount ~/ 400) : 1;
              for (var ci = 0; ci < charCount; ci += step) {
                final ch = fp.FPDFText_GetUnicode(textPage, ci);
                if (ch <= 0x20) continue;
                final rad = fp.FPDFText_GetCharAngle(textPage, ci);
                // PDFium char angle 是逆时针弧度，转成顺时针页面方向
                final degCw = -(rad * 180.0 / math.pi);
                final snapped = _normalizeRightAngle(degCw);
                if (snapped == null) continue;
                tally[snapped] = (tally[snapped] ?? 0) + 1;
              }
              int? best;
              var bestCount = 0;
              var total = 0;
              for (final e in tally.entries) {
                total += e.value;
                if (e.value > bestCount) {
                  best = e.key;
                  bestCount = e.value;
                }
              }
              if (best == null || bestCount < 2 || bestCount / total < 0.6) {
                out.add(null);
              } else {
                out.add(((best + pageRot) % 360 + 360) % 360);
              }
            } finally {
              fp.FPDFText_ClosePage(textPage);
            }
          } finally {
            fp.FPDF_ClosePage(page);
          }
        }
        return out;
      } finally {
        fp.FPDF_CloseDocument(doc);
      }
    });
  }

  static int? _normalizeRightAngle(double deg) {
    final wrapped = (((deg / 90.0).round() * 90) % 360 + 360) % 360;
    final diff = (((wrapped - deg + 540.0) % 360.0) - 180.0).abs();
    return diff > 5.0 ? null : wrapped;
  }

  /// 直接渲染单页为 BGRA 位图（供打印、图片导出、方向分析使用）
  static Future<({int width, int height, Uint8List bgra})?> renderPageBgra({
    required String filePath,
    required int pageIndexZeroBased,
    required double maxSideOrScale,
    bool byScale = true,
    int rotationSteps = 0, // 顺时针 90° 步数
    bool includePdfAnnotations = true,
    bool skipPdEditorAnnots = false,
    String? password,
  }) {
    return PdfrxEntryFunctions.instance.compute(
      (msg) => _renderPageBgraSync(msg),
      (
        filePath: filePath,
        pageIndex: pageIndexZeroBased,
        val: maxSideOrScale,
        byScale: byScale,
        rotSteps: rotationSteps,
        includeAnnots: includePdfAnnotations,
        skipPdEditorAnnots: skipPdEditorAnnots,
        password: password,
      ),
    );
  }

  static ({int width, int height, Uint8List bgra})? _renderPageBgraSync(
    ({
      String filePath,
      int pageIndex,
      double val,
      bool byScale,
      int rotSteps,
      bool includeAnnots,
      bool skipPdEditorAnnots,
      String? password,
    }) msg,
  ) {
    final fp = _getPdfium();
    return using((arena) {
      final doc = fp.FPDF_LoadDocument(
        msg.filePath.toNativeUtf8(allocator: arena).cast<Char>(),
        msg.password == null
            ? nullptr.cast<Char>()
            : msg.password!.toNativeUtf8(allocator: arena).cast<Char>(),
      );
      if (doc == nullptr) return null;
      try {
        final page = fp.FPDF_LoadPage(doc, msg.pageIndex);
        if (page == nullptr) return null;
        try {
          if (msg.includeAnnots && msg.skipPdEditorAnnots) {
            final keyPtr =
                'PdEditorData'.toNativeUtf8(allocator: arena).cast<Char>();
            final annotCount = fp.FPDFPage_GetAnnotCount(page);
            for (var ai = 0; ai < annotCount; ai++) {
              final annot = fp.FPDFPage_GetAnnot(page, ai);
              if (annot == nullptr) continue;
              try {
                if (fp.FPDFAnnot_HasKey(annot, keyPtr) != 0) {
                  final oldFlags = fp.FPDFAnnot_GetFlags(annot);
                  fp.FPDFAnnot_SetFlags(
                    annot,
                    oldFlags |
                        pdfium.FPDF_ANNOT_FLAG_HIDDEN |
                        pdfium.FPDF_ANNOT_FLAG_NOVIEW,
                  );
                }
              } finally {
                fp.FPDFPage_CloseAnnot(annot);
              }
            }
          }
          final wPt = fp.FPDF_GetPageWidthF(page);
          final hPt = fp.FPDF_GetPageHeightF(page);
          final rot = (msg.rotSteps % 4 + 4) % 4;
          final baseW = rot.isOdd ? hPt : wPt;
          final baseH = rot.isOdd ? wPt : hPt;
          final scale = msg.byScale
              ? msg.val
              : math.min(
                  msg.val / math.max(baseW, 1.0),
                  msg.val / math.max(baseH, 1.0),
                );
          final pxW = math.max(1, (baseW * scale).floor());
          final pxH = math.max(1, (baseH * scale).floor());
          final byteCount = pxW * pxH * 4;
          final buf = arena<Uint8>(byteCount);
          final bmp = fp.FPDFBitmap_CreateEx(
            pxW,
            pxH,
            pdfium.FPDFBitmap_BGRA,
            buf.cast<Void>(),
            pxW * 4,
          );
          if (bmp == nullptr) return null;
          try {
            fp.FPDFBitmap_FillRect(bmp, 0, 0, pxW, pxH, 0xFFFFFFFF);
            final flags = msg.includeAnnots ? pdfium.FPDF_ANNOT : 0;
            fp.FPDF_RenderPageBitmap(bmp, page, 0, 0, pxW, pxH, rot, flags);
            final copy = Uint8List.fromList(buf.asTypedList(byteCount));
            return (width: pxW, height: pxH, bgra: copy);
          } finally {
            fp.FPDFBitmap_Destroy(bmp);
          }
        } finally {
          fp.FPDF_ClosePage(page);
        }
      } finally {
        fp.FPDF_CloseDocument(doc);
      }
    });
  }

  /// 生成安全输出路径（同目录避让重名）
  static String uniquePath(String dir, String fileName) =>
      _uniqueFilePath(dir, fileName);

  static Future<void> logSaved(String action, String path) =>
      AppDataService.log('info', 'pdf', action, {'file': p.basename(path)});
}
