import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import 'package:pdf_editor_flutter/main.dart';
import 'package:pdf_editor_flutter/models/annotation_model.dart';
import 'package:pdf_editor_flutter/state/editor_controller.dart';
import 'package:pdf_editor_flutter/ui/theme/app_theme.dart';
import 'package:pdf_editor_flutter/ui/widgets/modern_top_bar.dart';
import 'package:pdf_editor_flutter/ui/widgets/right_inspector.dart';
import 'package:pdf_editor_flutter/ui/widgets/search_floating_bar.dart';

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
  Duration step = const Duration(milliseconds: 100),
  String Function()? debugReason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(step);
    if (condition()) return;
  }
  final extra = debugReason != null ? ' (${debugReason()})' : '';
  fail('Timed out after $timeout waiting for condition$extra');
}

Widget _buildRealApp(EditorController ctrl, {String? initialFilePath}) {
  return ListenableBuilder(
    listenable: ctrl,
    builder: (_, _) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.build(false),
      darkTheme: AppTheme.build(true),
      themeMode: ctrl.isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: PdfEditorShell(
        controller: ctrl,
        initialFilePath: initialFilePath,
      ),
    ),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late String samplePdfPath;

  setUpAll(() async {
    await pdfrxFlutterInitialize();
    tempDir = Directory.systemTemp.createTempSync('pdf_editor_e2e_');
    samplePdfPath = p.join(tempDir.path, 'e2e_sample.pdf');

    final doc = pw.Document();
    final markers = [
      'PageOneMarker Welcome to Flutter PDF Editor',
      'PageTwoMarker Quarterly Audit Report',
      'PageThreeMarker Annotation and Layout Test',
      'PageFourMarker Final Verification Page',
    ];
    for (var i = 0; i < markers.length; i++) {
      doc.addPage(
        pw.Page(
          build: (_) => pw.Padding(
            padding: const pw.EdgeInsets.all(40),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Document Page ${i + 1}',
                  style: pw.TextStyle(fontSize: 22),
                ),
                pw.SizedBox(height: 16),
                pw.Text(
                  markers[i],
                  style: pw.TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      );
    }
    File(samplePdfPath).writeAsBytesSync(await doc.save());
  });

  tearDownAll(() {
    try {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  testWidgets(
      'Windows desktop E2E: open real PDF, auto-fit zoom, F6 canvas shortcuts, search, annotations, save & reload',
      (WidgetTester tester) async {
    final ctrl = EditorController();
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(_buildRealApp(ctrl, initialFilePath: samplePdfPath));

    // 1. 等待真实 PDFium 打开并完成首次自动适配缩放
    await _pumpUntil(
      tester,
      () => ctrl.hasDocument && ctrl.viewerController.isReady && !ctrl.loading,
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(ctrl.pageCount, 4);
    expect(ctrl.displayFileName, 'e2e_sample.pdf');
    expect(ctrl.scale, greaterThanOrEqualTo(0.35));
    expect(ctrl.scale, lessThanOrEqualTo(1.5));
    expect(
      find.descendant(
        of: find.byType(ModernTopBar),
        matching: find.text('e2e_sample.pdf'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // 1b. 验证 PDF 右侧纵向滚动条已渲染，并可通过点击轨道与拖拽滑块快速下滑/回顶
    final vScrollbar = find.byKey(const Key('pdf_vertical_scrollbar'));
    expect(vScrollbar, findsOneWidget);
    final sbRect = tester.getRect(vScrollbar);
    // 点击轨道底部快速跳转到后半段页面
    await tester.tapAt(Offset(sbRect.center.dx, sbRect.bottom - 12));
    await _pumpUntil(
      tester,
      () => ctrl.currentPage >= 3,
      debugReason: () =>
          'after track tap bottom: page=${ctrl.currentPage}, vcPage=${ctrl.viewerController.pageNumber}, y=${ctrl.viewerController.value.y}, sbRect=$sbRect',
    );
    expect(ctrl.currentPage, greaterThanOrEqualTo(3));

    // 点击轨道顶部回到第 1 页
    await tester.tapAt(Offset(sbRect.center.dx, sbRect.top + 12));
    await _pumpUntil(
      tester,
      () => ctrl.currentPage == 1,
      debugReason: () =>
          'after track tap top: page=${ctrl.currentPage}, vcPage=${ctrl.viewerController.pageNumber}, y=${ctrl.viewerController.value.y}',
    );
    expect(ctrl.currentPage, 1);

    // 拖拽滑块向下快速滚动并校验页码推进
    await tester.dragFrom(
      Offset(sbRect.center.dx, sbRect.top + 18),
      Offset(0, sbRect.height * 0.72),
    );
    await _pumpUntil(
      tester,
      () => ctrl.currentPage >= 3,
      debugReason: () =>
          'after thumb drag down: page=${ctrl.currentPage}, vcPage=${ctrl.viewerController.pageNumber}, y=${ctrl.viewerController.value.y}',
    );
    expect(ctrl.currentPage, greaterThanOrEqualTo(3));

    // 回到第 1 页继续后续测试
    await tester.tapAt(Offset(sbRect.center.dx, sbRect.top + 12));
    await _pumpUntil(tester, () => ctrl.currentPage == 1);
    expect(ctrl.currentPage, 1);

    // 2. 验证点击画布/滚动条已聚焦 pdf_canvas，且 F6 可在画布与工具栏之间双向切换焦点
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'pdf_canvas');
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('pdf_canvas'));
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'pdf_canvas');

    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pump();
    expect(ctrl.tool, EditorTool.highlight);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.pump();
    expect(ctrl.tool, EditorTool.rect);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.pump();
    expect(ctrl.tool, EditorTool.select);

    // 3. 验证真实文本搜索（Ctrl+F -> 命中 PageTwoMarker -> 无匹配 -> Esc 关闭）
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump(const Duration(milliseconds: 100));
    expect(ctrl.searchOpen, isTrue);

    final searchField = find.descendant(
      of: find.byType(SearchFloatingBar),
      matching: find.byType(TextField),
    );
    await tester.enterText(searchField, 'PageTwoMarker');
    await _pumpUntil(tester, () => ctrl.searchMatchesCount >= 1);
    expect(ctrl.searchMatchesCount, greaterThanOrEqualTo(1));

    await tester.enterText(searchField, 'NoSuchTokenXYZ999');
    await _pumpUntil(
      tester,
      () =>
          ctrl.searchQuery == 'NoSuchTokenXYZ999' &&
          ctrl.searchMatchesCount == 0,
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('无匹配'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 100));
    expect(ctrl.searchOpen, isFalse);

    // 4. 验证手动缩放锁定 ZoomIntent.manual + 放大后横向滚动条出现并可操作 + 视图切换 + 浅深主题切换
    ctrl.setZoomPercent(220);
    await _pumpUntil(
      tester,
      () =>
          ctrl.viewerController.currentZoom > 2.0 &&
          find.byKey(const Key('pdf_horizontal_scrollbar')).evaluate().isNotEmpty,
    );
    expect(ctrl.zoomIntent, ZoomIntent.manual);
    expect(ctrl.scale, closeTo(2.2, 0.05));
    final hScrollbar = find.byKey(const Key('pdf_horizontal_scrollbar'));
    expect(hScrollbar, findsOneWidget);
    final hRect = tester.getRect(hScrollbar);
    final beforeX = ctrl.viewerController.value.x;
    await tester.tapAt(Offset(hRect.right - 12, hRect.center.dy));
    await _pumpUntil(
      tester,
      () => (ctrl.viewerController.value.x - beforeX).abs() > 10.0,
    );

    ctrl.setZoomPercent(120);
    await _pumpUntil(
      tester,
      () => (ctrl.viewerController.currentZoom - 1.2).abs() < 0.015,
    );
    expect(ctrl.zoomIntent, ZoomIntent.manual);
    expect(ctrl.scale, closeTo(1.2, 0.02));

    ctrl.setViewMode(ReadingViewMode.twoPage);
    await tester.pump(const Duration(milliseconds: 150));
    expect(ctrl.viewMode, ReadingViewMode.twoPage);
    ctrl.setViewMode(ReadingViewMode.continuous);
    await tester.pump(const Duration(milliseconds: 150));

    ctrl.toggleTheme();
    await tester.pump(const Duration(milliseconds: 150));
    expect(ctrl.isDarkMode, isTrue);
    ctrl.toggleTheme();
    await tester.pump(const Duration(milliseconds: 150));
    expect(ctrl.isDarkMode, isFalse);

    // 5. 验证批注创建 -> 右侧面板可见（若当前为抽屉模式则点击打开）-> 撤销/重做 -> 保存并重新打开校验持久化
    ctrl.addAnnotation(
      PdfAnnotationItem(
        id: 'e2e_hl_1',
        kind: AnnotationKind.highlight,
        page: 0,
        bbox: const PdfRectBox(40, 740, 220, 20),
        color: kToolDefaults[AnnotationKind.highlight]!.colorHex,
        opacity: kToolDefaults[AnnotationKind.highlight]!.opacity,
        createdAt: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(ctrl.dirty, isTrue);
    expect(ctrl.annotations.length, 1);

    if (find.byType(RightInspector).evaluate().isEmpty) {
      await tester.tap(find.byTooltip('显示/隐藏右侧面板 (Ctrl+Shift+B)'));
      await tester.pump(const Duration(milliseconds: 150));
    }
    expect(find.byType(RightInspector), findsOneWidget);
    expect(find.text('高亮 · 第 1 页'), findsOneWidget);

    // Ctrl+Z 撤销 -> Ctrl+Y 重做
    await ctrl.undo();
    await tester.pump(const Duration(milliseconds: 100));
    expect(ctrl.annotations, isEmpty);

    await ctrl.redo();
    await tester.pump(const Duration(milliseconds: 100));
    expect(ctrl.annotations.length, 1);

    // 插入空白页并验证撤销恢复页数
    await ctrl.insertBlankPageAfter(0);
    await _pumpUntil(
      tester,
      () => !ctrl.isBusy && ctrl.pageCount == 5 && ctrl.viewerController.isReady,
    );
    expect(ctrl.pageCount, 5);

    await ctrl.undo();
    await _pumpUntil(
      tester,
      () => !ctrl.isBusy && ctrl.pageCount == 4 && ctrl.viewerController.isReady,
    );
    expect(ctrl.pageCount, 4);

    // 保存并校验重新加载后批注持久化无损
    final saved = await ctrl.saveDocument();
    await tester.pump(const Duration(milliseconds: 200));
    expect(saved, isTrue);
    expect(ctrl.dirty, isFalse);

    final verifyCtrl = EditorController();
    addTearDown(verifyCtrl.dispose);
    final reopened = await verifyCtrl.openDocument(samplePdfPath);
    expect(reopened, isTrue);
    expect(verifyCtrl.pageCount, 4);
    expect(verifyCtrl.annotations.length, 1);
    expect(verifyCtrl.annotations.first.id, 'e2e_hl_1');
    expect(verifyCtrl.annotations.first.opacity, closeTo(0.26, 0.01));
    expect(tester.takeException(), isNull);
  });
}
