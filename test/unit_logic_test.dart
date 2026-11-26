import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pdf_editor_flutter/models/annotation_model.dart';
import 'package:pdf_editor_flutter/models/document_models.dart';
import 'package:pdf_editor_flutter/rendering/annotation_painter.dart';
import 'package:pdf_editor_flutter/services/ink_profile_service.dart';
import 'package:pdf_editor_flutter/services/pdf_engine_service.dart';
import 'package:pdf_editor_flutter/services/recent_and_log_service.dart';
import 'package:pdf_editor_flutter/services/system_fonts_service.dart';
import 'package:pdf_editor_flutter/utils/page_range.dart';

Uint8List _makeSyntheticTextLinesBgra({
  required int width,
  required int height,
  required bool horizontalBars,
  bool topHeavyBias = false,
}) {
  final bgra = Uint8List(width * height * 4);
  bgra.fillRange(0, bgra.length, 255); // white background
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      var dark = false;
      if (horizontalBars) {
        final inBand = (y >= 16 && y <= 24) ||
            (y >= 40 && y <= 48) ||
            (y >= 64 && y <= 72) ||
            (topHeavyBias && y >= 10 && y <= 14);
        if (inBand && x >= 10 && x <= width - 10) dark = true;
      } else {
        final inBand = (x >= 16 && x <= 24) ||
            (x >= 40 && x <= 48) ||
            (x >= 64 && x <= 72);
        if (inBand && y >= 10 && y <= height - 10) dark = true;
      }
      if (dark) {
        final idx = (y * width + x) * 4;
        bgra[idx] = 20;
        bgra[idx + 1] = 20;
        bgra[idx + 2] = 20;
        bgra[idx + 3] = 255;
      }
    }
  }
  return bgra;
}

void main() {
  group('page_range utilities', () {
    test('parsePageRange handles singles, ranges, deduplication and order', () {
      expect(parsePageRange('1, 3-5, 2, 4', 8), equals([0, 1, 2, 3, 4]));
      expect(parsePageRange(' 2 - 2 ', 5), equals([1]));
      expect(parsePageRange('5-3', 8), isNull);
      expect(parsePageRange('', 5), isNull);
      expect(parsePageRange('0-3', 5), isNull);
      expect(parsePageRange('1-9', 5), isNull);
      expect(parsePageRange('abc', 5), isNull);
    });

    test('splitPageSegments splits ascending indices into contiguous runs', () {
      expect(
        splitPageSegments([0, 1, 2, 4, 5]),
        equals([
          [0, 1, 2],
          [4, 5],
        ]),
      );
      expect(splitPageSegments([]), isEmpty);
    });

    test('formatPageRange merges consecutive 0-based indices', () {
      expect(formatPageRange([0, 1, 2, 4, 6, 7]), equals('1-3,5,7-8'));
      expect(formatPageRange([]), equals(''));
    });

    test('pointsToMm and color conversions round-trip accurately', () {
      expect(pointsToMm(72.0), closeTo(25.4, 1e-4));
      final c = hexToColor('#1971c2', opacity: 0.5);
      expect(colorToHex(c), equals('#1971c2'));
      expect((c.a * 255).round(), closeTo(128, 2));
    });

    test('simplifyPoints simplifies collinear points via Douglas-Peucker', () {
      final pts = [
        const PdfPoint(0, 0),
        const PdfPoint(5, 0.05),
        const PdfPoint(10, 0),
        const PdfPoint(20, 10),
      ];
      final out = simplifyPoints(pts, tolerance: 0.5);
      expect(out.length, equals(3));
      expect(out.first.x, equals(0));
      expect(out[1].x, equals(10));
      expect(out.last.x, equals(20));
    });

    test('wrapText wraps CJK characters and Latin words cleanly', () {
      double measure(String s) => s.length * 10.0;
      final wrapped = wrapText('你好世界测试\nhello world again', 50.0, measure);
      expect(wrapped, equals(['你好世界测', '试', 'hello', 'world', 'again']));
    });

    test('textLocalToPdf respects 0/90/180/270 rotations', () {
      const box = PdfRectBox(100, 200, 80, 40);
      final p0 = textLocalToPdf(box, 0, 10, 5);
      expect(p0.x, closeTo(110, 1e-6));
      expect(p0.y, closeTo(235, 1e-6));

      final p90 = textLocalToPdf(box, 90, 10, 5);
      expect(p90.x, closeTo(105, 1e-6));
      expect(p90.y, closeTo(210, 1e-6));

      final p180 = textLocalToPdf(box, 180, 10, 5);
      expect(p180.x, closeTo(170, 1e-6));
      expect(p180.y, closeTo(205, 1e-6));

      final p270 = textLocalToPdf(box, 270, 10, 5);
      expect(p270.x, closeTo(175, 1e-6));
      expect(p270.y, closeTo(230, 1e-6));
    });

    test('fitStampFontSize and watermarkPlacements stay within bounds', () {
      final size = fitStampFontSize('已批准', 120, 40, (s, sz) => s.length * sz);
      expect(size, inInclusiveRange(8.0, 40.0));
      final single = watermarkPlacements(
        pageWidth: 600,
        pageHeight: 800,
        textWidth: 100,
        textHeight: 20,
        tile: false,
      );
      expect(single.length, equals(1));
      expect(single.first.x, closeTo(300, 1e-6));
      final tiled = watermarkPlacements(
        pageWidth: 600,
        pageHeight: 800,
        textWidth: 100,
        textHeight: 20,
        tile: true,
      );
      expect(tiled.length, greaterThan(4));
    });
  });

  group('PdfAnnotationItem & PdfScreenTransform', () {
    test('JSON round-trip and validation cover all annotation kinds', () {
      for (final kind in AnnotationKind.values) {
        final item = PdfAnnotationItem(
          id: 'id_${kind.wireName}',
          kind: kind,
          page: 1,
          bbox: const PdfRectBox(20, 40, 120, 50),
          color: '#1971c2',
          opacity: 0.75,
          createdAt: 1700000000000,
          locked: kind == AnnotationKind.rect,
          thickness: 2.5,
          points: kind == AnnotationKind.ink
              ? const [PdfPoint(20, 40), PdfPoint(80, 70), PdfPoint(140, 90)]
              : const [],
          from: kind == AnnotationKind.arrow || kind == AnnotationKind.measure
              ? const PdfPoint(20, 40)
              : null,
          to: kind == AnnotationKind.arrow || kind == AnnotationKind.measure
              ? const PdfPoint(140, 90)
              : null,
          text: '中文批注 ABC',
          fontSize: 16,
          fontFamily: 'Microsoft YaHei',
          rotate: 90,
          stampKey: 'approved',
          label: '已批准',
          imgId: 'img-1',
          refPath: 'C:\\pic.png',
        );
        final parsed = PdfAnnotationItem.tryFromJson(item.toJson());
        expect(parsed, isNotNull);
        expect(parsed!.kind, equals(kind));
        expect(parsed.page, equals(1));
        expect(parsed.bbox.w, closeTo(120, 1e-6));
        if (kind == AnnotationKind.ink) {
          expect(parsed.points.length, equals(3));
        }
        if (kind == AnnotationKind.text) {
          expect(parsed.text, equals('中文批注 ABC'));
          expect(parsed.rotate, equals(90));
        }
      }

      // Rejects invalid / oversized payloads
      expect(PdfAnnotationItem.tryFromJson(null), isNull);
      expect(PdfAnnotationItem.tryFromJson({'id': '', 'kind': 'rect'}), isNull);
      expect(
        PdfAnnotationItem.tryFromJson({
          'id': 'ok',
          'kind': 'rect',
          'page': 0,
          'bbox': {'x': double.nan, 'y': 0, 'w': 10, 'h': 10},
        }),
        isNull,
      );
    });

    test('PdfScreenTransform inverse is exact across all rotations & scales', () {
      for (final rot in [0, 90, 180, 270]) {
        final t = PdfScreenTransform(
          rawWidthPt: 595.0,
          rawHeightPt: 842.0,
          scale: 1.75,
          viewRotationDeg: rot,
        );
        const orig = PdfPoint(123.4, 567.8);
        final screen = t.pdfToScreen(orig);
        final back = t.screenToPdf(screen);
        expect(back.x, closeTo(orig.x, 1e-4));
        expect(back.y, closeTo(orig.y, 1e-4));
      }
    });
  });

  group('InkProfileAnalyzer', () {
    test('detects page aspect orientation and consensus', () {
      expect(InkProfileAnalyzer.orientationOf(595, 842),
          PageOrientationKind.portrait);
      expect(InkProfileAnalyzer.orientationOf(842, 595),
          PageOrientationKind.landscape);
      expect(InkProfileAnalyzer.orientationOf(500, 505),
          PageOrientationKind.square);
      expect(
        InkProfileAnalyzer.pickBaseOrientation([
          PageOrientationKind.portrait,
          PageOrientationKind.portrait,
          PageOrientationKind.landscape,
        ]),
        PageOrientationKind.portrait,
      );
    });

    test('distinguishes upright horizontal bands vs 90-deg sideways bands', () {
      final uprightBgra = _makeSyntheticTextLinesBgra(
        width: 100,
        height: 100,
        horizontalBars: true,
      );
      final sidewaysBgra = _makeSyntheticTextLinesBgra(
        width: 100,
        height: 100,
        horizontalBars: false,
      );
      final inkUp = InkProfileAnalyzer.extractInkFromBgra(uprightBgra, 100, 100);
      final inkSide =
          InkProfileAnalyzer.extractInkFromBgra(sidewaysBgra, 100, 100);
      expect(InkProfileAnalyzer.uprightFromPixels(inkUp), isTrue);
      expect(InkProfileAnalyzer.uprightFromPixels(inkSide), isFalse);
    });

    test('consensusProfile flags upside-down inverted page', () {
      final ref = List<double>.filled(128, 0.0);
      for (var i = 8; i < 32; i++) {
        ref[i] = 1.0; // Asymmetric header mass near top
      }
      final flipped = ref.reversed.toList();
      final profiles = [
        RowProfile(page: 0, rows: ref),
        RowProfile(page: 1, rows: ref),
        RowProfile(page: 2, rows: ref),
        RowProfile(page: 3, rows: flipped),
      ];
      expect(InkProfileAnalyzer.invertedPages(profiles), equals([3]));
    });
  });

  group('SystemFontsService on Windows', () {
    test('locates default CJK font and checks Unicode coverage', () async {
      final cjkPath = SystemFontsService.findDefaultCjkFontPath();
      expect(cjkPath, isNotNull);
      expect(File(cjkPath!).existsSync(), isTrue);

      final faceBytes = await SystemFontsService.readDefaultCjkFontBytes();
      expect(faceBytes, isNotNull);
      expect(faceBytes!.length, greaterThan(10000));
      expect(SystemFontsService.fontCoversText(faceBytes, '你好PDF123'), isTrue);
    });

    test('cmap format 12 startGlyphID == 0 misses and falls back to format 4',
        () {
      Uint8List buildSyntheticFont({required int format4Glyph}) {
        // Minimal SFNT header + head (>= 12) + cmap with format 4 & format 12
        final b = BytesBuilder();
        void addU16(int v) => b.add([(v >> 8) & 0xFF, v & 0xFF]);
        void addU32(int v) => b.add([
              (v >> 24) & 0xFF,
              (v >> 16) & 0xFF,
              (v >> 8) & 0xFF,
              v & 0xFF,
            ]);

        // Format 4 subtable mapping U+4E2D..U+4E2D -> glyph = format4Glyph
        final f4 = BytesBuilder();
        void f4U16(int v) => f4.add([(v >> 8) & 0xFF, v & 0xFF]);
        final segCountX2 = 4; // 2 segments: 0x4E2D & 0xFFFF
        final f4Len = 16 + 4 * segCountX2;
        f4U16(4); // format
        f4U16(f4Len);
        f4U16(0); // language
        f4U16(segCountX2);
        f4U16(4); // searchRange
        f4U16(1); // entrySelector
        f4U16(0); // rangeShift
        f4U16(0x4E2D);
        f4U16(0xFFFF); // endCount
        f4U16(0); // reservedPad
        f4U16(0x4E2D);
        f4U16(0xFFFF); // startCount
        f4U16((format4Glyph - 0x4E2D) & 0xFFFF);
        f4U16(1); // idDelta
        f4U16(0);
        f4U16(0); // idRangeOffset
        final f4Bytes = f4.toBytes();

        // Format 12 subtable mapping U+4E2D..U+4E2D -> startGlyphID = 0 (.notdef)
        final f12 = BytesBuilder();
        void f12U16(int v) => f12.add([(v >> 8) & 0xFF, v & 0xFF]);
        void f12U32(int v) => f12.add([
              (v >> 24) & 0xFF,
              (v >> 16) & 0xFF,
              (v >> 8) & 0xFF,
              v & 0xFF,
            ]);
        f12U16(12);
        f12U16(0);
        f12U32(28);
        f12U32(0); // language
        f12U32(1); // numGroups
        f12U32(0x4E2D);
        f12U32(0x4E2D);
        f12U32(0); // startGlyphID == 0
        final f12Bytes = f12.toBytes();

        // cmap header (2 tables: platform 3 enc 1 -> f4, platform 3 enc 10 -> f12)
        final cmapHeaderSize = 4 + 2 * 8;
        final f4OffsetInCmap = cmapHeaderSize;
        final f12OffsetInCmap = f4OffsetInCmap + f4Bytes.length;

        const sfntHeaderSize = 12 + 2 * 16; // 2 tables: cmap, head
        const headOffset = sfntHeaderSize;
        const headLen = 16;
        const cmapOffset = headOffset + headLen;
        final cmapLen = f12OffsetInCmap + f12Bytes.length;

        // SFNT Offset Table
        addU32(0x00010000);
        addU16(2);
        addU16(32);
        addU16(1);
        addU16(0);
        // Directory: cmap then head
        b.add(ascii.encode('cmap'));
        addU32(0);
        addU32(cmapOffset);
        addU32(cmapLen);
        b.add(ascii.encode('head'));
        addU32(0);
        addU32(headOffset);
        addU32(headLen);

        // head bytes (dummy 16 bytes)
        b.add(Uint8List(headLen));

        // cmap header + records
        addU16(0);
        addU16(2);
        addU16(3);
        addU16(1);
        addU32(f4OffsetInCmap);
        addU16(3);
        addU16(10);
        addU32(f12OffsetInCmap);
        b.add(f4Bytes);
        b.add(f12Bytes);
        return b.toBytes();
      }

      // Format 12 says 0 (.notdef), format 4 also says 0 -> false
      expect(
        SystemFontsService.fontCoversText(buildSyntheticFont(format4Glyph: 0), '中'),
        isFalse,
      );
      // Format 12 says 0 (.notdef), format 4 maps U+4E2D to glyph 7 -> true via fallback
      expect(
        SystemFontsService.fontCoversText(buildSyntheticFont(format4Glyph: 7), '中'),
        isTrue,
      );
    });
  });

  group('PdEditorData & AppDataService regressions', () {
    test('decodePdEditorDataUnits recovers BOM-less UTF-8 with 0x80..0x9F bytes',
        () {
      const byteToPdfDoc = {
        0x80: 0x2022,
        0x81: 0x2020,
        0x82: 0x2021,
        0x83: 0x2026,
        0x84: 0x2014,
        0x85: 0x2013,
        0x86: 0x0192,
        0x87: 0x2044,
        0x88: 0x2039,
        0x89: 0x203A,
        0x8A: 0x2212,
        0x8B: 0x2030,
        0x8C: 0x201E,
        0x8D: 0x201C,
        0x8E: 0x201D,
        0x8F: 0x2018,
        0x90: 0x2019,
        0x91: 0x201A,
        0x92: 0x2122,
        0x93: 0xFB01,
        0x94: 0xFB02,
        0x95: 0x0141,
        0x96: 0x0152,
        0x97: 0x0160,
        0x98: 0x0178,
        0x99: 0x017D,
        0x9A: 0x0131,
        0x9B: 0x0142,
        0x9C: 0x0153,
        0x9D: 0x0161,
        0x9E: 0x017E,
        0xA0: 0x20AC,
      };
      // '中国文字' UTF-8 includes 0x9B ('国') and 0x96 ('文') in 0x80..0x9E range
      final jsonStr = jsonEncode({
        'id': 'u-utf8',
        'kind': 'text',
        'page': 0,
        'bbox': {'x': 10, 'y': 20, 'w': 100, 'h': 30},
        'color': '#1971c2',
        'opacity': 1.0,
        'createdAt': 100,
        'text': '中国文字—€',
      });
      final utf8Bytes = utf8.encode(jsonStr);
      final pdfiumUnits = [
        for (final byte in utf8Bytes) byteToPdfDoc[byte] ?? byte,
      ];

      final decoded = PdfEngineService.decodePdEditorDataUnits(pdfiumUnits, 3);
      expect(decoded, isNotNull);
      expect(decoded!.text, equals('中国文字—€'));
      expect(decoded.page, equals(3));

      // Proper UTF-16BE JSON (already decoded by PDFium) also works
      final utf16Units = jsonStr.codeUnits;
      final decoded16 = PdfEngineService.decodePdEditorDataUnits(utf16Units, 1);
      expect(decoded16, isNotNull);
      expect(decoded16!.text, equals('中国文字—€'));
      expect(decoded16.page, equals(1));
    });

    test('AppDataService atomicWriteString & concurrent recordRecent leave no tmp files',
        () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final dir = Directory.systemTemp.createTempSync('pdf_ed_appdata_');
      const channel = MethodChannel('plugins.flutter.io/path_provider');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => dir.path);
      try {
        await Future.wait([
          for (var i = 1; i <= 10; i++)
            AppDataService.recordRecent('C:\\docs\\file_$i.pdf', i),
        ]);
        final recent = await AppDataService.listRecent();
        expect(recent.length, equals(10));
        final leftoverTmp = dir
            .listSync(recursive: true)
            .where((f) => f.path.endsWith('.tmp'))
            .toList();
        expect(leftoverTmp, isEmpty);

        // Single remove, missingOnly cleanup & clearRecent
        final realPdf = File('${dir.path}${Platform.pathSeparator}exists.pdf')
          ..writeAsBytesSync(const [0x25, 0x50, 0x44, 0x46]);
        await AppDataService.recordRecent(realPdf.path, 2);
        await AppDataService.removeRecent('C:\\docs\\file_1.pdf');
        final afterRemove = await AppDataService.listRecent();
        expect(afterRemove.any((e) => e.path.endsWith('file_1.pdf')), isFalse);

        await AppDataService.clearRecent(missingOnly: true);
        final afterMissing = await AppDataService.listRecent();
        expect(afterMissing.length, equals(1));
        expect(afterMissing.single.path, equals(realPdf.path));

        await AppDataService.clearRecent(missingOnly: false);
        expect(await AppDataService.listRecent(), isEmpty);
      } finally {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });
  });
}
