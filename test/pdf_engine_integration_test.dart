import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart' hide PdfPoint;
import 'package:pdfrx_engine/pdfrx_engine.dart' as engine show Pdfrx;

import 'package:pdf_editor_flutter/models/annotation_model.dart';
import 'package:pdf_editor_flutter/models/document_models.dart';
import 'package:pdf_editor_flutter/services/export_and_print_service.dart';
import 'package:pdf_editor_flutter/services/image_to_pdf_service.dart';
import 'package:pdf_editor_flutter/services/pdf_engine_service.dart';
import 'package:pdf_editor_flutter/services/sidecar_service.dart';
import 'package:pdf_editor_flutter/state/editor_controller.dart';
import 'package:pdf_editor_flutter/ui/dialogs/batch_dialogs.dart';
import 'package:pdf_editor_flutter/ui/theme/app_theme.dart';
import 'package:pdf_editor_flutter/ui/widgets/thumbnails_sidebar.dart';

Uint8List _makePngBytes(int w, int h, {int r = 40, int g = 110, int b = 220}) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgba8(245, 245, 245, 255));
  img.fillRect(
    im,
    x1: w ~/ 6,
    y1: h ~/ 6,
    x2: (w * 5) ~/ 6,
    y2: (h * 5) ~/ 6,
    color: img.ColorRgba8(r, g, b, 255),
  );
  return Uint8List.fromList(img.encodePng(im));
}

Uint8List _makeJpgBytes(int w, int h) {
  final im = img.Image(width: w, height: h);
  img.fill(im, color: img.ColorRgba8(250, 230, 200, 255));
  img.fillRect(
    im,
    x1: 10,
    y1: 10,
    x2: w - 10,
    y2: h - 10,
    color: img.ColorRgba8(200, 70, 50, 255),
  );
  return Uint8List.fromList(img.encodeJpg(im, quality: 90));
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final mockDir =
        Directory.systemTemp.createTempSync('pdf_editor_test_appdir_').path;
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => mockDir);
    final debugPdfium = File(
      p.join(
        Directory.current.path,
        'build',
        'windows',
        'x64',
        'runner',
        'Debug',
        'pdfium.dll',
      ),
    );
    if (debugPdfium.existsSync()) {
      engine.Pdfrx.pdfiumModulePath = debugPdfium.path;
    }
    await pdfrxFlutterInitialize();
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('pdf_editor_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    }
  });

  Future<String> createSamplePdf({String name = 'sample.pdf'}) async {
    final img1 = File(p.join(tempDir.path, 'p1.png'))
      ..writeAsBytesSync(_makePngBytes(400, 600));
    final img2 = File(p.join(tempDir.path, 'p2.jpg'))
      ..writeAsBytesSync(_makeJpgBytes(600, 400));
    final outPdf = p.join(tempDir.path, name);
    final res = await ImageToPdfService.convert(
      imagePaths: [img1.path, img2.path],
      targetPath: outPdf,
      useA4: true,
    );
    expect(res.ok, isTrue, reason: res.error);
    return outPdf;
  }

  test('ImageToPdfService builds valid pixel-sized and A4 auto-oriented PDFs',
      () async {
    final portraitPng = File(p.join(tempDir.path, 'port.png'))
      ..writeAsBytesSync(_makePngBytes(480, 720));
    final landscapeJpg = File(p.join(tempDir.path, 'land.jpg'))
      ..writeAsBytesSync(_makeJpgBytes(800, 500));

    final a4Out = p.join(tempDir.path, 'a4.pdf');
    final a4Res = await ImageToPdfService.convert(
      imagePaths: [portraitPng.path, landscapeJpg.path],
      targetPath: a4Out,
      useA4: true,
    );
    expect(a4Res.ok, isTrue);
    expect(a4Res.pageCount, equals(2));

    final inspectA4 = await PdfEngineService.inspectDocument(a4Out);
    expect(inspectA4.ok, isTrue);
    expect(inspectA4.pageCount, equals(2));
    // Page 0 portrait A4, Page 1 landscape A4
    expect(inspectA4.pageSizes[0].w, lessThan(inspectA4.pageSizes[0].h));
    expect(inspectA4.pageSizes[1].w, greaterThan(inspectA4.pageSizes[1].h));

    final pixelOut = p.join(tempDir.path, 'pixel.pdf');
    final pxRes = await ImageToPdfService.convert(
      imagePaths: [portraitPng.path],
      targetPath: pixelOut,
      useA4: false,
    );
    expect(pxRes.ok, isTrue);
    final inspectPx = await PdfEngineService.inspectDocument(pixelOut);
    expect(inspectPx.ok, isTrue);
    expect(inspectPx.pageSizes[0].w, closeTo(480 * 72 / 96, 1.5));
    expect(inspectPx.pageSizes[0].h, closeTo(720 * 72 / 96, 1.5));
  });

  test(
      'saveWithAnnotations writes all 10 annotation kinds and round-trips without duplication',
      () async {
    final srcPdf = await createSamplePdf();
    final stampedPdf = p.join(tempDir.path, 'with_annots.pdf');
    final imgPng = _makePngBytes(120, 80, r: 10, g: 180, b: 90);
    final imgFile = File(p.join(tempDir.path, 'stamp_pic.png'))
      ..writeAsBytesSync(imgPng);

    final items = [
      const PdfAnnotationItem(
        id: 'ann-hl',
        kind: AnnotationKind.highlight,
        page: 0,
        bbox: PdfRectBox(40, 700, 180, 18),
        color: '#ffe066',
        opacity: 0.4,
        createdAt: 1001,
      ),
      const PdfAnnotationItem(
        id: 'ann-rect',
        kind: AnnotationKind.rect,
        page: 0,
        bbox: PdfRectBox(50, 620, 120, 60),
        color: '#e03131',
        opacity: 1.0,
        createdAt: 1002,
        thickness: 2.0,
      ),
      const PdfAnnotationItem(
        id: 'ann-ell',
        kind: AnnotationKind.ellipse,
        page: 0,
        bbox: PdfRectBox(200, 620, 90, 60),
        color: '#1971c2',
        opacity: 0.9,
        createdAt: 1003,
      ),
      const PdfAnnotationItem(
        id: 'ann-ink',
        kind: AnnotationKind.ink,
        page: 0,
        bbox: PdfRectBox(50, 500, 100, 50),
        color: '#2f9e44',
        opacity: 1.0,
        createdAt: 1004,
        thickness: 2.5,
        points: [PdfPoint(50, 500), PdfPoint(100, 540), PdfPoint(150, 550)],
      ),
      const PdfAnnotationItem(
        id: 'ann-arrow',
        kind: AnnotationKind.arrow,
        page: 0,
        bbox: PdfRectBox(60, 420, 120, 40),
        color: '#e03131',
        opacity: 1.0,
        createdAt: 1005,
        from: PdfPoint(60, 420),
        to: PdfPoint(180, 460),
      ),
      const PdfAnnotationItem(
        id: 'ann-measure',
        kind: AnnotationKind.measure,
        page: 0,
        bbox: PdfRectBox(60, 360, 72, 0),
        color: '#1971c2',
        opacity: 1.0,
        createdAt: 1006,
        from: PdfPoint(60, 360),
        to: PdfPoint(132, 360),
      ),
      const PdfAnnotationItem(
        id: 'ann-text',
        kind: AnnotationKind.text,
        page: 0,
        bbox: PdfRectBox(60, 260, 200, 60),
        color: '#212529',
        opacity: 1.0,
        createdAt: 1007,
        text: '测试中文批注 Text 123',
        fontSize: 14,
      ),
      const PdfAnnotationItem(
        id: 'ann-note',
        kind: AnnotationKind.note,
        page: 1,
        bbox: PdfRectBox(100, 200, 22, 22),
        color: '#f7c948',
        opacity: 1.0,
        createdAt: 1008,
        text: '这是一条便签',
      ),
      const PdfAnnotationItem(
        id: 'ann-stamp',
        kind: AnnotationKind.stamp,
        page: 1,
        bbox: PdfRectBox(150, 200, 130, 46),
        color: '#2f9e44',
        opacity: 0.95,
        createdAt: 1009,
        stampKey: 'approved',
        label: '已批准',
      ),
      PdfAnnotationItem(
        id: 'ann-image',
        kind: AnnotationKind.image,
        page: 1,
        bbox: const PdfRectBox(320, 180, 120, 80),
        color: '#212529',
        opacity: 1.0,
        createdAt: 1010,
        imgId: 'img-id-1',
        refPath: imgFile.path,
      ),
    ];

    final save1 = await PdfEngineService.saveWithAnnotations(
      sourcePath: srcPdf,
      targetPath: stampedPdf,
      annotations: items,
      resolvedImages: {'img-id-1': imgPng},
    );
    expect(save1.ok, isTrue, reason: save1.error);

    final inspect1 = await PdfEngineService.inspectDocument(stampedPdf);
    expect(inspect1.ok, isTrue);
    expect(inspect1.annotations.length, equals(10));
    expect(
      inspect1.annotations.firstWhere((a) => a.id == 'ann-text').text,
      equals('测试中文批注 Text 123'),
    );

    // Save a second time overwriting/saving -> count must still be 10 (no duplicates)
    final save2 = await PdfEngineService.saveWithAnnotations(
      sourcePath: stampedPdf,
      targetPath: stampedPdf,
      annotations: inspect1.annotations,
      resolvedImages: {'img-id-1': imgPng},
    );
    expect(save2.ok, isTrue, reason: save2.error);
    final inspect2 = await PdfEngineService.inspectDocument(stampedPdf);
    expect(inspect2.annotations.length, equals(10));

    // Sidecar read/write/delete
    await SidecarService.writeSidecar(stampedPdf, annotations: items);
    final sc = await SidecarService.readSidecar(stampedPdf);
    expect(sc, isNotNull);
    expect(sc!.annotations.length, equals(10));
    await File(SidecarService.sidecarPathFor(stampedPdf)).delete();
    expect(await SidecarService.readSidecar(stampedPdf), isNull);
  });

  test(
      'Page ops: rotate, insertBlank, move, delete, merge, export, pageNumbers, watermark, split & PNG export',
      () async {
    final pdfA = await createSamplePdf(name: 'a.pdf');
    final pdfB = await createSamplePdf(name: 'b.pdf');

    // Insert blank page after page 0 -> 3 pages
    final blankOut = p.join(tempDir.path, 'blank.pdf');
    expect(
      (await PdfEngineService.insertBlankPage(
        sourcePath: pdfA,
        targetPath: blankOut,
        afterIndex: 0,
      ))
          .ok,
      isTrue,
    );
    expect((await PdfEngineService.inspectDocument(blankOut)).pageCount,
        equals(3));

    // Move page 2 -> 0
    final movedOut = p.join(tempDir.path, 'moved.pdf');
    expect(
      (await PdfEngineService.movePage(
        sourcePath: blankOut,
        targetPath: movedOut,
        fromIndex: 2,
        toIndex: 0,
      ))
          .ok,
      isTrue,
    );

    // Rotate page 0 by +90 -> width & height swap
    final beforeRot = await PdfEngineService.inspectDocument(movedOut);
    final rotOut = p.join(tempDir.path, 'rot.pdf');
    expect(
      (await PdfEngineService.rotatePages(
        sourcePath: movedOut,
        targetPath: rotOut,
        deltasByPage: const {0: 90},
      ))
          .ok,
      isTrue,
    );
    final afterRot = await PdfEngineService.inspectDocument(rotOut);
    expect(
        afterRot.pageSizes[0].w, closeTo(beforeRot.pageSizes[0].h, 1.5));
    expect(
        afterRot.pageSizes[0].h, closeTo(beforeRot.pageSizes[0].w, 1.5));

    // Delete page 1 -> 2 pages
    final delOut = p.join(tempDir.path, 'del.pdf');
    expect(
      (await PdfEngineService.deletePages(
        sourcePath: rotOut,
        targetPath: delOut,
        pagesZeroBased: const [1],
      ))
          .ok,
      isTrue,
    );
    expect(
        (await PdfEngineService.inspectDocument(delOut)).pageCount, equals(2));

    // Merge pdfA + pdfB (page 0 of each -> 2 pages)
    final mergedOut = p.join(tempDir.path, 'merged.pdf');
    expect(
      (await PdfEngineService.mergePdfs(
        specs: [
          (path: pdfA, pages: const [0, 1], password: null),
          (path: pdfB, pages: const [0], password: null),
        ],
        targetPath: mergedOut,
      ))
          .ok,
      isTrue,
    );
    expect((await PdfEngineService.inspectDocument(mergedOut)).pageCount,
        equals(3));

    // Page numbers & Watermark
    final numOut = p.join(tempDir.path, 'numbered.pdf');
    expect(
      (await PdfEngineService.applyPageNumbers(
        sourcePath: mergedOut,
        targetPath: numOut,
        pagesZeroBased: const [0, 1, 2],
        format: PageNumberFormat.zhPageTotal,
        startNumber: 1,
        position: PageNumberPosition.bottomCenter,
        fontSize: 12,
        marginPt: 20,
      ))
          .ok,
      isTrue,
    );
    final wmOut = p.join(tempDir.path, 'watermarked.pdf');
    expect(
      (await PdfEngineService.applyWatermark(
        sourcePath: numOut,
        targetPath: wmOut,
        pagesZeroBased: const [0, 1, 2],
        text: '机密 WATERMARK',
        fontSize: 28,
        opacity: 0.25,
        rotationDeg: 35,
        tile: true,
        colorHex: '#64748b',
      ))
          .ok,
      isTrue,
    );

    // Split batch into 2 chunks
    final splitDir = Directory(p.join(tempDir.path, 'split_out'))..createSync();
    final splitRes = await PdfEngineService.splitBatch(
      tasks: [
        SplitTaskInput(
          path: wmOut,
          chunks: const [
            [0, 1],
            [2],
          ],
        ),
      ],
      outputDir: splitDir.path,
      includeAnnotations: true,
    );
    expect(splitRes.length, equals(1));
    expect(splitRes.first.ok, isTrue, reason: splitRes.first.error);
    expect(splitRes.first.outputs.length, equals(2));

    // Extract single page PDF & Render BGRA + Export Each & Long PNG
    final extractOut = p.join(tempDir.path, 'extract.pdf');
    expect(
      (await PdfEngineService.exportPdfPages(
        sourcePath: wmOut,
        targetPath: extractOut,
        pagesZeroBased: const [0],
        includeAnnotations: true,
      ))
          .ok,
      isTrue,
    );

    final bgra = await PdfEngineService.renderPageBgra(
      filePath: wmOut,
      pageIndexZeroBased: 0,
      maxSideOrScale: 1.0,
      byScale: true,
    );
    expect(bgra, isNotNull);
    expect(bgra!.width, greaterThan(100));

    final wmInfo = await PdfEngineService.inspectDocument(wmOut);
    final pngEachDir = Directory(p.join(tempDir.path, 'png_each'))..createSync();
    final eachRes = await ExportAndPrintService.exportEachPng(
      filePath: wmOut,
      targetDir: pngEachDir.path,
      stem: 'doc',
      pagesZeroBased: const [0, 1],
      pageSizes: wmInfo.pageSizes,
      pageRotations: wmInfo.pageRotations,
      viewRotationDeg: 0,
      includeAnnotations: true,
      allAnnotations: const [],
      loadedImages: const <String, ui.Image>{},
    );
    expect(eachRes.ok, isTrue, reason: eachRes.error);
    expect(eachRes.savedPaths.length, equals(2));

    final longPngPath = p.join(tempDir.path, 'long_v.png');
    final longRes = await ExportAndPrintService.exportLongPng(
      filePath: wmOut,
      targetPath: longPngPath,
      pagesZeroBased: const [0, 1],
      pageSizes: wmInfo.pageSizes,
      pageRotations: wmInfo.pageRotations,
      viewRotationDeg: 0,
      vertical: true,
      includeAnnotations: false,
      allAnnotations: const [],
      loadedImages: const <String, ui.Image>{},
    );
    expect(longRes.ok, isTrue, reason: longRes.error);
    expect(File(longPngPath).existsSync(), isTrue);
    expect(File(longPngPath).lengthSync(), greaterThan(1000));
  });

  test('Regression: movePage 0->1 and 0->last, in-place page ops, splitBatch non-current annots, rotated ops & chronological undo',
      () async {
    // 1) Distinct 3-page PDF to verify movePage forward & backward indices
    final p0 = File(p.join(tempDir.path, 'sz0.png'))
      ..writeAsBytesSync(_makePngBytes(200, 300));
    final p1 = File(p.join(tempDir.path, 'sz1.png'))
      ..writeAsBytesSync(_makePngBytes(400, 300));
    final p2 = File(p.join(tempDir.path, 'sz2.png'))
      ..writeAsBytesSync(_makePngBytes(600, 500));
    final threePdf = p.join(tempDir.path, 'three.pdf');
    expect(
      (await ImageToPdfService.convert(
        imagePaths: [p0.path, p1.path, p2.path],
        targetPath: threePdf,
        useA4: false,
      ))
          .ok,
      isTrue,
    );

    final m01 = p.join(tempDir.path, 'move01.pdf');
    expect(
      (await PdfEngineService.movePage(
        sourcePath: threePdf,
        targetPath: m01,
        fromIndex: 0,
        toIndex: 1,
      ))
          .ok,
      isTrue,
    );
    final info01 = await PdfEngineService.inspectDocument(m01);
    expect(info01.pageSizes[0].w, closeTo(400 * 72 / 96, 1.5));
    expect(info01.pageSizes[1].w, closeTo(200 * 72 / 96, 1.5));
    expect(info01.pageSizes[2].w, closeTo(600 * 72 / 96, 1.5));

    // Move first to last in-place (sourcePath == targetPath)
    expect(
      (await PdfEngineService.movePage(
        sourcePath: threePdf,
        targetPath: threePdf,
        fromIndex: 0,
        toIndex: 2,
      ))
          .ok,
      isTrue,
    );
    final info02 = await PdfEngineService.inspectDocument(threePdf);
    expect(info02.pageSizes[0].w, closeTo(400 * 72 / 96, 1.5));
    expect(info02.pageSizes[1].w, closeTo(600 * 72 / 96, 1.5));
    expect(info02.pageSizes[2].w, closeTo(200 * 72 / 96, 1.5));

    // Rotate page 0 by 90 deg in-place, then apply bottomCenter page number + rotated image + strip
    expect(
      (await PdfEngineService.rotatePages(
        sourcePath: threePdf,
        targetPath: threePdf,
        deltasByPage: const {0: 90},
      ))
          .ok,
      isTrue,
    );
    expect(
      (await PdfEngineService.applyPageNumbers(
        sourcePath: threePdf,
        targetPath: threePdf,
        pagesZeroBased: const [0, 1, 2],
        format: PageNumberFormat.numberOnly,
        startNumber: 1,
        position: PageNumberPosition.bottomCenter,
        fontSize: 16,
        marginPt: 16,
      ))
          .ok,
      isTrue,
    );
    final renderedRot = await PdfEngineService.renderPageBgra(
      filePath: threePdf,
      pageIndexZeroBased: 0,
      maxSideOrScale: 1.0,
      byScale: true,
    );
    expect(renderedRot, isNotNull);
    // Rotated 90 CW from 400x300px => visual width < height (225 x 300 pt)
    expect(renderedRot!.width, lessThan(renderedRot.height));

    // Check rotated image annotation & stripPdEditorAnnotations & splitBatch non-current doc preservation
    final rotImgPng = _makePngBytes(100, 60, r: 220, g: 30, b: 30);
    final rotImgFile = File(p.join(tempDir.path, 'rot_img.png'))
      ..writeAsBytesSync(rotImgPng);
    final savedAnn = [
      PdfAnnotationItem(
        id: 'rot-img-1',
        kind: AnnotationKind.image,
        page: 1,
        bbox: const PdfRectBox(40, 40, 60, 100),
        color: '#212529',
        opacity: 1.0,
        rotate: 90,
        createdAt: 2026,
        imgId: 'rot-img-id',
        refPath: rotImgFile.path,
      ),
    ];
    final withAnnPath = p.join(tempDir.path, 'with_rot_ann.pdf');
    expect(
      (await PdfEngineService.saveWithAnnotations(
        sourcePath: threePdf,
        targetPath: withAnnPath,
        annotations: savedAnn,
        resolvedImages: {'rot-img-id': rotImgPng},
      ))
          .ok,
      isTrue,
    );

    // splitBatch with isCurrentDoc = false must preserve PdEditorData from withAnnPath
    final splitOutDir =
        Directory(p.join(tempDir.path, 'split_preserve'))..createSync();
    final batchRes = await PdfEngineService.splitBatch(
      tasks: [
        SplitTaskInput(
          path: withAnnPath,
          chunks: const [
            [1],
          ],
          isCurrentDoc: false,
          outputStem: '自定义导出名',
        ),
      ],
      outputDir: splitOutDir.path,
      includeAnnotations: true,
      resolvedImages: {'rot-img-id': rotImgPng},
    );
    expect(batchRes.single.ok, isTrue, reason: batchRes.single.error);
    expect(
      p.basename(batchRes.single.outputs.single),
      equals('自定义导出名-1.pdf'),
    );
    final splitInspect =
        await PdfEngineService.inspectDocument(batchRes.single.outputs.single);
    expect(splitInspect.annotations.length, equals(1));
    expect(splitInspect.annotations.single.id, equals('rot-img-1'));
    expect(splitInspect.annotations.single.rotate, equals(90));

    // stripPdEditorAnnotations leaves 0 PdEditorData annotations
    final strippedPath = p.join(tempDir.path, 'stripped.pdf');
    expect(
      (await PdfEngineService.stripPdEditorAnnotations(
        sourcePath: withAnnPath,
        targetPath: strippedPath,
      ))
          .ok,
      isTrue,
    );
    expect(
      (await PdfEngineService.inspectDocument(strippedPath)).annotations,
      isEmpty,
    );

    // 2) EditorController unified chronological undo/redo across mixed annot & page ops
    final ctrl = EditorController();
    try {
      expect(await ctrl.openDocument(threePdf), isTrue);
      const a1 = PdfAnnotationItem(
        id: 'chrono-1',
        kind: AnnotationKind.rect,
        page: 0,
        bbox: PdfRectBox(10, 10, 40, 40),
        color: '#e03131',
        opacity: 1.0,
        createdAt: 1,
      );
      const a2 = PdfAnnotationItem(
        id: 'chrono-2',
        kind: AnnotationKind.ellipse,
        page: 0,
        bbox: PdfRectBox(60, 10, 40, 40),
        color: '#1971c2',
        opacity: 1.0,
        createdAt: 2,
      );
      ctrl.addAnnotation(a1);
      final rotBefore = ctrl.pageRotations[0];
      await ctrl.rotatePages({0: 90});
      ctrl.addAnnotation(a2);
      expect(ctrl.annotations.length, equals(2));

      // Undo 1 -> removes a2, keeps page rotation
      await ctrl.undo();
      expect(ctrl.annotations.map((a) => a.id), equals(['chrono-1']));
      expect(ctrl.pageRotations[0], equals((rotBefore + 90) % 360));

      // Undo 2 -> reverts page rotation, preserves a1
      await ctrl.undo();
      expect(ctrl.annotations.map((a) => a.id), equals(['chrono-1']));
      expect(ctrl.pageRotations[0], equals(rotBefore));

      // Undo 3 -> removes a1
      await ctrl.undo();
      expect(ctrl.annotations, isEmpty);

      // Redo x3 -> restores in chronological order
      await ctrl.redo();
      expect(ctrl.annotations.map((a) => a.id), equals(['chrono-1']));
      await ctrl.redo();
      expect(ctrl.pageRotations[0], equals((rotBefore + 90) % 360));
      await ctrl.redo();
      expect(ctrl.annotations.length, equals(2));

      // Discarding a newly created empty text annotation leaves undo stack clean
      const emptyTxt = PdfAnnotationItem(
        id: 'empty-txt',
        kind: AnnotationKind.text,
        page: 0,
        bbox: PdfRectBox(20, 20, 100, 30),
        color: '#212529',
        opacity: 1.0,
        text: '',
        createdAt: 3,
      );
      ctrl.addAnnotation(emptyTxt);
      expect(ctrl.annotations.length, equals(3));
      ctrl.discardNewEmptyAnnotation('empty-txt');
      expect(ctrl.annotations.length, equals(2));
      expect(ctrl.annotations.any((a) => a.id == 'empty-txt'), isFalse);
    } finally {
      ctrl.dispose();
    }
  });

  testWidgets('ThumbnailsSidebar auto-scrolls when currentPage jumps far away',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 560);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final doc = pw.Document();
    for (var i = 0; i < 12; i++) {
      doc.addPage(
        pw.Page(
          build: (_) => pw.Center(child: pw.Text('Page ${i + 1}')),
        ),
      );
    }
    final multiPath = p.join(tempDir.path, 'twelve_pages.pdf');
    final bytes = await tester.runAsync(() => doc.save());
    File(multiPath).writeAsBytesSync(bytes!);

    final ctrl = EditorController();
    addTearDown(ctrl.dispose);
    final opened = await tester.runAsync(() => ctrl.openDocument(multiPath));
    expect(opened, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: Scaffold(
          body: Row(
            children: [
              ThumbnailsSidebar(
                controller: ctrl,
                onDeleteDialog: () {},
                onExtractDialog: () {},
                onSplitDialog: () {},
                onExportDialog: () {},
                onOrientationDialog: () {},
                onPageNumberDialog: () {},
                onWatermarkDialog: () {},
                onMergeDialog: () {},
                onPageContextMenu: (_, _) {},
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );

    for (var i = 0; i < 40; i++) {
      if (find.byType(ReorderableListView).evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(find.byType(ReorderableListView), findsOneWidget);

    final scrollableState = tester.state<ScrollableState>(
      find.descendant(
        of: find.byType(ThumbnailsSidebar),
        matching: find.byType(Scrollable),
      ),
    );
    expect(scrollableState.position.pixels, equals(0.0));

    ctrl.jumpToPage(11);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    expect(scrollableState.position.pixels, greaterThan(1000.0));
  });

  testWidgets('showMergeDialog works without an open document and opens merged PDF',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final pdfA = p.join(tempDir.path, 'merge_a.pdf');
    final pdfB = p.join(tempDir.path, 'merge_b.pdf');
    await tester.runAsync(() async {
      final docA = pw.Document();
      for (var i = 0; i < 2; i++) {
        docA.addPage(pw.Page(build: (_) => pw.Center(child: pw.Text('A$i'))));
      }
      File(pdfA).writeAsBytesSync(await docA.save());

      final docB = pw.Document();
      for (var i = 0; i < 3; i++) {
        docB.addPage(pw.Page(build: (_) => pw.Center(child: pw.Text('B$i'))));
      }
      File(pdfB).writeAsBytesSync(await docB.save());
    });

    final ctrl = EditorController();
    addTearDown(ctrl.dispose);

    late BuildContext rootCtx;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              rootCtx = ctx;
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );
    await tester.pump();

    var dialogDone = false;
    showMergeDialog(
      rootCtx,
      ctrl,
      initialPaths: [pdfA, pdfB],
    ).whenComplete(() => dialogDone = true);

    for (var i = 0; i < 60; i++) {
      if (find.text('开始合并').evaluate().isNotEmpty) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    expect(find.text('合并 PDF'), findsOneWidget);
    expect(find.text('已选 2 份参与合并'), findsOneWidget);
    expect(find.text('输出目录：${tempDir.path}'), findsOneWidget);
    final startBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '开始合并'),
    );
    expect(startBtn.onPressed, isNotNull);

    await tester.tap(find.text('合并完成后打开输出所在文件夹'));
    await tester.pump();
    await tester.tap(find.text('开始合并'));
    await tester.pump();

    for (var i = 0; i < 80; i++) {
      if (dialogDone && ctrl.hasDocument && !ctrl.isBusy) break;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    expect(ctrl.hasDocument, isTrue);
    expect(ctrl.pageCount, equals(5));
    expect(ctrl.filePath, isNotNull);
    expect(p.basename(ctrl.filePath!), startsWith('merge_a-合并'));
    expect(File(ctrl.filePath!).existsSync(), isTrue);
  });
}
