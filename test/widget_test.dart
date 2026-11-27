import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pdf_editor_flutter/main.dart';
import 'package:pdf_editor_flutter/models/annotation_model.dart';
import 'package:pdf_editor_flutter/models/document_models.dart';
import 'package:pdf_editor_flutter/state/editor_controller.dart';
import 'package:pdf_editor_flutter/ui/dialogs/batch_dialogs.dart';
import 'package:pdf_editor_flutter/ui/dialogs/editor_dialogs.dart';
import 'package:pdf_editor_flutter/ui/theme/app_theme.dart';
import 'package:pdf_editor_flutter/ui/widgets/floating_tool_dock.dart';
import 'package:pdf_editor_flutter/ui/widgets/modern_status_bar.dart';
import 'package:pdf_editor_flutter/ui/widgets/modern_top_bar.dart';
import 'package:pdf_editor_flutter/ui/widgets/right_inspector.dart';
import 'package:pdf_editor_flutter/ui/widgets/search_floating_bar.dart';
import 'package:pdf_editor_flutter/ui/widgets/thumbnails_sidebar.dart';
import 'package:pdf_editor_flutter/ui/widgets/vertical_tool_rail.dart';
import 'package:pdf_editor_flutter/ui/widgets/welcome_view.dart';

void main() {
  testWidgets('App shell renders welcome screen cleanly at desktop size',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const PdfEditorApp());
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('PDF 编辑器'), findsWidgets);
    expect(find.text('打开 PDF 文件 (Ctrl+O)'), findsOneWidget);
    expect(find.text('图片转 PDF'), findsOneWidget);
    expect(find.text('就绪'), findsOneWidget);
  });

  testWidgets('Top bar, floating tool dock and status bar render without overflow',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ctrl = EditorController();
    addTearDown(ctrl.dispose);
    ctrl.filePath = 'C:\\demo\\sample.pdf';
    ctrl.activeRenderPath = 'C:\\demo\\sample.pdf';
    ctrl.pageCount = 5;
    ctrl.pageSizes = List.generate(5, (_) => (w: 595.0, h: 842.0));
    ctrl.pageRotations = List.filled(5, 0);
    ctrl.currentPage = 2;
    ctrl.setTool(EditorTool.stamp);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: ctrl,
            builder: (_, _) => Column(
              children: [
                ModernTopBar(
                  controller: ctrl,
                  onOpenFile: () {},
                  onMergePdf: () {},
                  onImageToPdf: () {},
                  onSave: () {},
                  onSaveAs: () {},
                  onExportCurrentPng: () {},
                  onExportPagesDialog: () {},
                  onPrintDialog: () {},
                  onAbout: () {},
                ),
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: FloatingToolDock(controller: ctrl),
                    ),
                  ),
                ),
                ModernStatusBar(
                  controller: ctrl,
                  onOpenProblems: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('sample.pdf'), findsOneWidget);
    expect(find.text('图章:'), findsOneWidget);
    expect(find.text('共 5 页'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('连续'), findsOneWidget);

    expect(tester.widget<Text>(find.text('共 5 页')).style?.fontSize,
        AppTypography.caption);
    expect(tester.widget<Text>(find.text('连续')).style?.fontSize,
        AppTypography.body);

    // 验证最小窗口宽度 1024px 下底部状态栏仍不溢出
    tester.view.physicalSize = const Size(1024, 640);
    ctrl.dirty = true;
    ctrl.encrypted = true;
    ctrl.addProblem('test', '测试问题徽标');
    ctrl.refresh();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('未保存'), findsOneWidget);
    expect(find.text('加密文档'), findsOneWidget);
    expect(find.text('问题 (1)'), findsOneWidget);
    expect(tester.widget<Text>(find.text('未保存')).style?.fontSize,
        AppTypography.caption);
  });

  testWidgets('TopBar and ThumbnailsSidebar buttons highlight visibly on mouse hover',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ctrl = EditorController();
    addTearDown(ctrl.dispose);
    ctrl.filePath = 'C:\\demo\\sample.pdf';
    ctrl.activeRenderPath = 'C:\\demo\\sample.pdf';
    ctrl.suspendViewer = true;
    ctrl.pageCount = 2;
    ctrl.pageSizes = List.generate(2, (_) => (w: 595.0, h: 842.0));
    ctrl.pageRotations = List.filled(2, 0);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: Scaffold(
          body: Column(
            children: [
              ModernTopBar(
                controller: ctrl,
                onOpenFile: () {},
                onMergePdf: () {},
                onImageToPdf: () {},
                onSave: () {},
                onSaveAs: () {},
                onExportCurrentPng: () {},
                onExportPagesDialog: () {},
                onPrintDialog: () {},
                onAbout: () {},
              ),
              Expanded(
                child: Row(
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
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    final openFinder = find.text('打开');
    final topExportFinder = find.descendant(
      of: find.byType(ModernTopBar),
      matching: find.text('导出'),
    );
    final selectAllFinder = find.text('全选');
    final rotateLeftFinder = find.descendant(
      of: find.byType(ThumbnailsSidebar),
      matching: find.byIcon(Icons.rotate_left_rounded),
    );

    expect(
      _fillColorOf(tester, openFinder),
      equals(AppColors.light.hoverFill.withValues(alpha: 0)),
    );
    expect(
      _fillColorOf(tester, topExportFinder),
      equals(AppColors.light.hoverFill.withValues(alpha: 0)),
    );
    expect(
      _fillColorOf(tester, selectAllFinder),
      equals(AppColors.light.hoverFill.withValues(alpha: 0)),
    );
    expect(
      _fillColorOf(tester, rotateLeftFinder),
      equals(AppColors.light.subtleFill),
    );

    // Verify mid-hover interpolation keeps hoverFill RGB (no dark-gray flash)
    await gesture.moveTo(tester.getCenter(openFinder));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 25));
    final openContainer = find.ancestor(
      of: openFinder,
      matching: find.byType(AnimatedContainer),
    );
    final midDecorated = tester.widget<DecoratedBox>(
      find.descendant(
        of: openContainer.first,
        matching: find.byType(DecoratedBox),
      ).first,
    );
    final midColor = (midDecorated.decoration as BoxDecoration).color!;
    expect(midColor.r, closeTo(AppColors.light.hoverFill.r, 0.02));
    expect(midColor.g, closeTo(AppColors.light.hoverFill.g, 0.02));
    expect(midColor.b, closeTo(AppColors.light.hoverFill.b, 0.02));

    await tester.pump(const Duration(milliseconds: 120));
    expect(_fillColorOf(tester, openFinder), equals(AppColors.light.hoverFill));

    await _hoverOver(tester, gesture, topExportFinder);
    expect(_fillColorOf(tester, topExportFinder), equals(AppColors.light.hoverFill));

    await _hoverOver(tester, gesture, selectAllFinder);
    expect(_fillColorOf(tester, selectAllFinder), equals(AppColors.light.hoverFill));

    await _hoverOver(tester, gesture, rotateLeftFinder);
    expect(_fillColorOf(tester, rotateLeftFinder), equals(AppColors.light.hoverFill));

    await gesture.moveTo(Offset.zero);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(_fillColorOf(tester, rotateLeftFinder), equals(AppColors.light.subtleFill));
  });

  testWidgets(
      'WelcomeView, FloatingToolDock dropdowns and RightInspector highlight on hover',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tmpDir = Directory.systemTemp.createTempSync('pdf_hover_test_');
    addTearDown(() => tmpDir.deleteSync(recursive: true));
    final existingPdf = File('${tmpDir.path}${Platform.pathSeparator}recent_demo.pdf')
      ..writeAsBytesSync(const [0x25, 0x50, 0x44, 0x46]);

    final welcomeCtrl = EditorController();
    addTearDown(welcomeCtrl.dispose);
    welcomeCtrl.recentFiles = [
      RecentDocumentEntry(
        path: existingPdf.path,
        page: 2,
        updatedAt: 1732530000000,
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: Scaffold(
          body: WelcomeView(
            controller: welcomeCtrl,
            onOpenFile: () {},
            onMergePdf: () {},
            onImageToPdf: () {},
            onOpenPath: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    final recentFinder = find.text('recent_demo.pdf');
    expect(_fillColorOf(tester, recentFinder), equals(AppColors.light.subtleFill));
    await _hoverOver(tester, gesture, recentFinder);
    expect(_fillColorOf(tester, recentFinder), equals(AppColors.light.hoverFill));

    // 切到工具坞 + 右侧检查器
    final editCtrl = EditorController();
    addTearDown(editCtrl.dispose);
    editCtrl.filePath = existingPdf.path;
    editCtrl.activeRenderPath = existingPdf.path;
    editCtrl.pageCount = 1;
    editCtrl.pageSizes = const [(w: 595.0, h: 842.0)];
    editCtrl.pageRotations = [0];
    editCtrl.tool = EditorTool.stamp;
    editCtrl.annotations = [
      const PdfAnnotationItem(
        id: 'a1',
        kind: AnnotationKind.rect,
        page: 0,
        bbox: PdfRectBox(10, 10, 80, 40),
        color: '#2563eb',
        opacity: 0.9,
        createdAt: 1,
      ),
      const PdfAnnotationItem(
        id: 'a2',
        kind: AnnotationKind.rect,
        page: 0,
        bbox: PdfRectBox(30, 30, 80, 40),
        color: '#e03131',
        opacity: 0.9,
        createdAt: 2,
      ),
    ];
    editCtrl.selectedIds.add('a1');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: editCtrl,
            builder: (_, _) => Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: FloatingToolDock(controller: editCtrl),
                  ),
                ),
                RightInspector(controller: editCtrl),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final stampPresetFinder = find.text('已批准').first;
    final topBtnFinder = find.text('置顶');
    expect(_fillColorOf(tester, stampPresetFinder), equals(AppColors.light.subtleFill));
    expect(_fillColorOf(tester, topBtnFinder), equals(AppColors.light.subtleFill));

    await _hoverOver(tester, gesture, stampPresetFinder);
    expect(_fillColorOf(tester, stampPresetFinder), equals(AppColors.light.hoverFill));

    await _hoverOver(tester, gesture, topBtnFinder);
    expect(_fillColorOf(tester, topBtnFinder), equals(AppColors.light.hoverFill));

    // 切换到“注释”页签检查筛选下拉框外壳悬停反馈
    await _hoverOver(tester, gesture, find.text('注释 (2)'));
    await tester.tap(find.text('注释 (2)'));
    await tester.pump(const Duration(milliseconds: 50));

    final filterFinder = find.text('全部类型').first;
    expect(_fillColorOf(tester, filterFinder), equals(AppColors.light.subtleFill));
    await _hoverOver(tester, gesture, filterFinder);
    expect(_fillColorOf(tester, filterFinder), equals(AppColors.light.hoverFill));
  });

  testWidgets('Beautified UnsavedChanges and Password prompt dialogs render cleanly',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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

    final pendingChoice = showUnsavedChangesDialog(
      rootCtx,
      title: '退出确认',
      fileName: 'contract.pdf',
      message: '当前文档有未保存的修改，是否在退出前保存？',
      saveLabel: '保存并退出',
      barrierDismissible: false,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('退出确认'), findsOneWidget);
    expect(find.text('contract.pdf'), findsOneWidget);
    expect(find.text('保存并退出'), findsOneWidget);
    expect(find.text('不保存'), findsOneWidget);
    _expectUnifiedTypography(tester);

    await tester.tap(find.text('不保存'));
    await tester.pumpAndSettle();
    expect(await pendingChoice, equals(UnsavedChangesChoice.discard));

    final pendingPw = showPasswordPromptDialog(rootCtx, wrongPassword: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('输入 PDF 密码'), findsOneWidget);
    expect(find.text('密码错误，请重新输入'), findsOneWidget);
    _expectUnifiedTypography(tester);
    await tester.enterText(find.byType(TextField), 'secret123');
    await tester.tap(find.text('解锁打开'));
    await tester.pumpAndSettle();
    expect(await pendingPw, equals('secret123'));
  });

  testWidgets('Theme and all UI panels & dialogs enforce 12/14/16/20px typography without overflow',
      (WidgetTester tester) async {
    expect(AppTypography.display, 20);
    expect(AppTypography.title, 16);
    expect(AppTypography.body, 14);
    expect(AppTypography.caption, 12);

    for (final dark in [false, true]) {
      final theme = AppTheme.build(dark);
      for (final style in [
        theme.textTheme.displayLarge,
        theme.textTheme.displayMedium,
        theme.textTheme.displaySmall,
        theme.textTheme.headlineLarge,
        theme.textTheme.headlineMedium,
        theme.textTheme.headlineSmall,
        theme.textTheme.titleLarge,
        theme.textTheme.titleMedium,
        theme.textTheme.titleSmall,
        theme.textTheme.bodyLarge,
        theme.textTheme.bodyMedium,
        theme.textTheme.bodySmall,
        theme.textTheme.labelLarge,
        theme.textTheme.labelMedium,
        theme.textTheme.labelSmall,
        theme.tooltipTheme.textStyle,
        theme.dialogTheme.titleTextStyle,
        theme.dialogTheme.contentTextStyle,
        theme.popupMenuTheme.textStyle,
        theme.listTileTheme.titleTextStyle,
        theme.listTileTheme.subtitleTextStyle,
        theme.inputDecorationTheme.labelStyle,
        theme.inputDecorationTheme.floatingLabelStyle,
        theme.inputDecorationTheme.hintStyle,
        theme.inputDecorationTheme.helperStyle,
        theme.inputDecorationTheme.errorStyle,
      ]) {
        expect(
          style?.fontSize,
          isIn(AppTypography.allowedSizes),
          reason:
              'Theme(dark=$dark) style $style must be in ${AppTypography.allowedSizes}',
        );
      }
    }

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tmpDir = Directory.systemTemp.createTempSync('pdf_typo_test_');
    addTearDown(() => tmpDir.deleteSync(recursive: true));
    final samplePdf = File('${tmpDir.path}${Platform.pathSeparator}typo_demo.pdf')
      ..writeAsBytesSync(const [0x25, 0x50, 0x44, 0x46]);

    // 1. 欢迎页全部文本字号规范校验
    final welcomeCtrl = EditorController();
    addTearDown(welcomeCtrl.dispose);
    welcomeCtrl.recentFiles = [
      RecentDocumentEntry(
        path: samplePdf.path,
        page: 1,
        updatedAt: 1732530000000,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: Scaffold(
          body: WelcomeView(
            controller: welcomeCtrl,
            onOpenFile: () {},
            onMergePdf: () {},
            onImageToPdf: () {},
            onOpenPath: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    _expectUnifiedTypography(tester);
    expect(
      tester.widget<Text>(find.text('PDF 编辑器')).style?.fontSize,
      AppTypography.display,
    );

    // 2. 完整工作台外框（顶栏 + 左侧缩略图栏 + 悬浮工具坞 + 搜索条 + 右侧属性栏 + 底栏）
    final editCtrl = EditorController();
    addTearDown(editCtrl.dispose);
    editCtrl.filePath = samplePdf.path;
    editCtrl.activeRenderPath = samplePdf.path;
    editCtrl.suspendViewer = true;
    editCtrl.pageCount = 3;
    editCtrl.pageSizes = List.generate(3, (_) => (w: 595.0, h: 842.0));
    editCtrl.pageRotations = List.filled(3, 0);
    editCtrl.tool = EditorTool.stamp;
    editCtrl.searchOpen = true;
    editCtrl.searchQuery = 'PDF';
    editCtrl.annotations = [
      const PdfAnnotationItem(
        id: 't1',
        kind: AnnotationKind.text,
        page: 0,
        bbox: PdfRectBox(20, 20, 120, 40),
        color: '#212529',
        opacity: 1.0,
        text: '测试批注文本',
        createdAt: 1,
      ),
    ];
    editCtrl.selectedIds.add('t1');

    late BuildContext rootCtx;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              rootCtx = ctx;
              return Column(
                children: [
                  ModernTopBar(
                    controller: editCtrl,
                    onOpenFile: () {},
                    onMergePdf: () {},
                    onImageToPdf: () {},
                    onSave: () {},
                    onSaveAs: () {},
                    onExportCurrentPng: () {},
                    onExportPagesDialog: () {},
                    onPrintDialog: () {},
                    onAbout: () {},
                  ),
                  Expanded(
                    child: Row(
                      children: [
                        ThumbnailsSidebar(
                          controller: editCtrl,
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
                        Expanded(
                          child: Stack(
                            children: [
                              Positioned(
                                top: 12,
                                left: 16,
                                right: 16,
                                child: Center(
                                  child: FloatingToolDock(controller: editCtrl),
                                ),
                              ),
                              Positioned(
                                top: 66,
                                right: 16,
                                child: SearchFloatingBar(controller: editCtrl),
                              ),
                            ],
                          ),
                        ),
                        RightInspector(controller: editCtrl),
                      ],
                    ),
                  ),
                  ModernStatusBar(
                    controller: editCtrl,
                    onOpenProblems: () {},
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    _expectUnifiedTypography(tester);

    // 切换右侧“注释”和“大纲”页签验证无溢出且字号合规
    await tester.tap(find.text('注释 (1)'));
    await tester.pump(const Duration(milliseconds: 50));
    _expectUnifiedTypography(tester);
    await tester.tap(find.text('大纲'));
    await tester.pump(const Duration(milliseconds: 50));
    _expectUnifiedTypography(tester);

    // 2b. 最小桌面窗口 1024x640 下完整工作台仍不溢出
    tester.view.physicalSize = const Size(1024, 640);
    await tester.pump(const Duration(milliseconds: 50));
    _expectUnifiedTypography(tester);
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pump(const Duration(milliseconds: 50));

    // 3. 逐个验证所有对话框在 16px / 14px 规范下正常渲染且无溢出
    final f1 = showPageRangeDialog(
      rootCtx,
      title: '导出页面 / 图片',
      totalPages: 3,
      showIncludeAnnotations: true,
      showExportOptions: true,
    );
    await tester.pumpAndSettle();
    _expectUnifiedTypography(tester);
    await tester.enterText(find.byType(TextField).last, 'invalid');
    await tester.pump();
    _expectUnifiedTypography(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await f1;

    final f2 = showPageNumberDialog(rootCtx, editCtrl);
    await tester.pumpAndSettle();
    _expectUnifiedTypography(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await f2;

    final f3 = showWatermarkDialog(rootCtx, editCtrl);
    await tester.pumpAndSettle();
    _expectUnifiedTypography(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await f3;

    editCtrl.addProblem('test', '测试告警信息', '详细说明');
    final f4 = showProblemsDialog(rootCtx, editCtrl);
    await tester.pumpAndSettle();
    _expectUnifiedTypography(tester);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await f4;

    final f5 = showImageToPdfDialog(rootCtx, editCtrl);
    await tester.pumpAndSettle();
    _expectUnifiedTypography(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await f5;

    final f6 = showMergeDialog(rootCtx, editCtrl);
    await tester.pumpAndSettle();
    _expectUnifiedTypography(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await f6;

    final f7 = showSplitDialog(rootCtx, editCtrl);
    await tester.pumpAndSettle();
    _expectUnifiedTypography(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await f7;
  });

  testWidgets('Interactive page flows: dock/search non-overlap, status bar unfocus, sidebar & inspector controls',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tmpDir = Directory.systemTemp.createTempSync('pdf_flow_test_');
    addTearDown(() => tmpDir.deleteSync(recursive: true));
    final samplePdf = File('${tmpDir.path}${Platform.pathSeparator}flow_demo.pdf')
      ..writeAsBytesSync(const [0x25, 0x50, 0x44, 0x46]);

    // 1. 短窗口下 WelcomeView 垂直滚动不溢出
    final welcomeCtrl = EditorController();
    addTearDown(welcomeCtrl.dispose);
    welcomeCtrl.recentFiles = List.generate(
      6,
      (i) => RecentDocumentEntry(
        path: samplePdf.path,
        page: i + 1,
        updatedAt: 1732530000000 + i,
      ),
    );
    tester.view.physicalSize = const Size(1024, 500);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: Scaffold(
          body: WelcomeView(
            controller: welcomeCtrl,
            onOpenFile: () {},
            onMergePdf: () {},
            onImageToPdf: () {},
            onOpenPath: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1280, 800);

    // 2. 工具坞展开子条 + 搜索条同时开启时互不重叠，且底栏/侧栏/属性面板交互闭环
    final ctrl = EditorController();
    addTearDown(ctrl.dispose);
    ctrl.filePath = samplePdf.path;
    ctrl.activeRenderPath = samplePdf.path;
    ctrl.suspendViewer = true;
    ctrl.pageCount = 5;
    ctrl.pageSizes = List.generate(5, (_) => (w: 595.0, h: 842.0));
    ctrl.pageRotations = List.filled(5, 0);
    ctrl.currentPage = 1;
    ctrl.tool = EditorTool.stamp;
    ctrl.searchOpen = true;
    ctrl.annotations = [
      const PdfAnnotationItem(
        id: 'a1',
        kind: AnnotationKind.text,
        page: 0,
        bbox: PdfRectBox(20, 20, 120, 40),
        color: '#212529',
        opacity: 1.0,
        text: '初始文本',
        createdAt: 1,
      ),
      const PdfAnnotationItem(
        id: 'a2',
        kind: AnnotationKind.rect,
        page: 1,
        bbox: PdfRectBox(30, 30, 80, 40),
        color: '#e03131',
        opacity: 1.0,
        createdAt: 2,
      ),
    ];
    ctrl.selectedIds.add('a1');

    late BuildContext rootCtx;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              rootCtx = ctx;
              return ListenableBuilder(
                listenable: ctrl,
                builder: (_, _) => Column(
                  children: [
                    ModernTopBar(
                      controller: ctrl,
                      onOpenFile: () {},
                      onMergePdf: () {},
                      onImageToPdf: () {},
                      onSave: () {},
                      onSaveAs: () {},
                      onExportCurrentPng: () {},
                      onExportPagesDialog: () {},
                      onPrintDialog: () {},
                      onAbout: () {},
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          if (ctrl.showThumbnails)
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
                          Expanded(
                            child: Stack(
                              children: [
                                Positioned(
                                  top: 12,
                                  left: 16,
                                  right: 16,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Center(
                                        child: FloatingToolDock(controller: ctrl),
                                      ),
                                      if (ctrl.searchOpen)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 8),
                                          child: Align(
                                            alignment: Alignment.topRight,
                                            child: SearchFloatingBar(
                                              controller: ctrl,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (ctrl.showRightPanel)
                            RightInspector(controller: ctrl),
                        ],
                      ),
                    ),
                    ModernStatusBar(
                      controller: ctrl,
                      onOpenProblems: () {},
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    final dockRect = tester.getRect(find.byType(FloatingToolDock));
    final searchRect = tester.getRect(find.byType(SearchFloatingBar));
    expect(dockRect.bottom, lessThanOrEqualTo(searchRect.top));

    // 底栏页码输入按 Enter 后跳转并释放焦点，后续 jumpToPage 能继续同步到输入框
    final statusFields = find.descendant(
      of: find.byType(ModernStatusBar),
      matching: find.byType(TextField),
    );
    final statusEditables = find.descendant(
      of: find.byType(ModernStatusBar),
      matching: find.byType(EditableText),
    );
    final prevIconCenterY = tester
        .getCenter(find.descendant(
          of: find.byType(ModernStatusBar),
          matching: find.byIcon(Icons.chevron_left_rounded),
        ))
        .dy;
    final slashTextCenterY = tester
        .getCenter(find.descendant(
          of: find.byType(ModernStatusBar),
          matching: find.text('/ 5'),
        ))
        .dy;
    final minusIconCenterY = tester
        .getCenter(find.descendant(
          of: find.byType(ModernStatusBar),
          matching: find.byIcon(Icons.remove_rounded),
        ))
        .dy;
    final pageEditableCenterY = tester.getCenter(statusEditables.first).dy;
    final zoomEditableCenterY = tester.getCenter(statusEditables.last).dy;
    expect((pageEditableCenterY - prevIconCenterY).abs(), lessThanOrEqualTo(1.5));
    expect((pageEditableCenterY - slashTextCenterY).abs(), lessThanOrEqualTo(1.5));
    expect((zoomEditableCenterY - minusIconCenterY).abs(), lessThanOrEqualTo(1.5));

    await tester.tap(statusFields.first);
    await tester.enterText(statusFields.first, '4');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(ctrl.currentPage, 4);
    expect(FocusManager.instance.primaryFocus?.context?.widget, isNot(isA<EditableText>()));

    ctrl.jumpToPage(2);
    await tester.pump();
    expect(tester.widget<TextField>(statusFields.first).controller?.text, '2');

    // 底栏缩放输入按 Enter 后生效并释放焦点
    await tester.tap(statusFields.last);
    await tester.enterText(statusFields.last, '150');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    expect(ctrl.scale, closeTo(1.5, 0.001));

    // 阅读视图切换（单页 / 双页 / 连续）
    await tester.tap(find.text('双页'));
    await tester.pump();
    expect(ctrl.viewMode, ReadingViewMode.twoPage);
    await tester.tap(find.text('连续'));
    await tester.pump();
    expect(ctrl.viewMode, ReadingViewMode.continuous);

    // 缩略图栏 全选 / 反选 / 清空
    await tester.tap(find.text('全选'));
    await tester.pump();
    expect(ctrl.selectedThumbPages.length, 5);
    await tester.tap(find.text('清空'));
    await tester.pump();
    expect(ctrl.selectedThumbPages, isEmpty);
    await tester.tap(find.text('反选'));
    await tester.pump();
    expect(ctrl.selectedThumbPages.length, 5);

    // 右侧注释列表筛选与删除
    await tester.tap(find.text('注释 (2)'));
    await tester.pump();
    await tester.tap(find.text('全部页'));
    await tester.pump();
    expect(ctrl.listCurrentPageOnly, isTrue);
    expect(find.text('第 2 页 · 矩形', skipOffstage: false), findsNothing);

    // 拆分弹窗移除条目不触发已释放控制器异常
    final splitFuture = showSplitDialog(rootCtx, ctrl);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('移除').first);
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await splitFuture;

    // 合并弹窗页面范围交互无异常
    final mergeFuture = showMergeDialog(rootCtx, ctrl);
    await tester.pumpAndSettle();
    expect(find.text('全部 5 页'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await mergeFuture;
  });

  testWidgets('Recent file management, Ctrl+F refocus/select-all, and pre-merge prompt',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final tmpDir = Directory.systemTemp.createTempSync('pdf_enh_test_');
    addTearDown(() {
      try {
        if (tmpDir.existsSync()) tmpDir.deleteSync(recursive: true);
      } catch (_) {}
    });
    final existingA = File('${tmpDir.path}${Platform.pathSeparator}keep_a.pdf')
      ..writeAsBytesSync(const [0x25, 0x50, 0x44, 0x46]);
    final existingB = File('${tmpDir.path}${Platform.pathSeparator}drop_b.pdf')
      ..writeAsBytesSync(const [0x25, 0x50, 0x44, 0x46]);
    final missingPath = '${tmpDir.path}${Platform.pathSeparator}missing.pdf';

    final appDataDir = Directory('${tmpDir.path}${Platform.pathSeparator}appdata')
      ..createSync();
    const pathChannel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (call) async => appDataDir.path);
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null));

    // 1. 欢迎页最近记录管理：单条移除、清理失效、清空记录
    final welcomeCtrl = EditorController();
    addTearDown(welcomeCtrl.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: welcomeCtrl,
            builder: (_, _) => WelcomeView(
              controller: welcomeCtrl,
              onOpenFile: () {},
              onMergePdf: () {},
              onImageToPdf: () {},
              onOpenPath: (_) async {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    welcomeCtrl.recentFiles = [
      RecentDocumentEntry(path: existingA.path, page: 1, updatedAt: 3),
      RecentDocumentEntry(path: missingPath, page: 2, updatedAt: 2),
      RecentDocumentEntry(path: existingB.path, page: 4, updatedAt: 1),
    ];
    welcomeCtrl.refresh();
    await tester.pump();
    _expectUnifiedTypography(tester);
    expect(find.text('清理失效'), findsOneWidget);
    expect(find.text('清空记录'), findsOneWidget);

    // 移除最后一条 existingB
    await tester.tap(find.byTooltip('从最近记录移除').last);
    await tester.pump();
    expect(welcomeCtrl.recentFiles.length, 2);
    expect(find.text('drop_b.pdf'), findsNothing);

    // 清理失效记录 -> 仅剩 existingA
    await tester.tap(find.text('清理失效'));
    await tester.pump();
    expect(welcomeCtrl.recentFiles.length, 1);
    expect(find.text('missing.pdf'), findsNothing);
    expect(find.text('清理失效'), findsNothing);

    // 清空记录
    await tester.tap(find.text('清空记录'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    expect(welcomeCtrl.recentFiles, isEmpty);
    expect(find.text('最近打开'), findsNothing);

    // 2. Ctrl+F 重新聚焦搜索框并全选 + 合并未保存提示
    final ctrl = EditorController();
    addTearDown(ctrl.dispose);
    ctrl.filePath = existingA.path;
    ctrl.activeRenderPath = existingA.path;
    ctrl.suspendViewer = true;
    ctrl.pageCount = 3;
    ctrl.pageSizes = List.generate(3, (_) => (w: 595.0, h: 842.0));
    ctrl.pageRotations = List.filled(3, 0);
    ctrl.dirty = true;

    late BuildContext shellCtx;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: Builder(
          builder: (ctx) {
            shellCtx = ctx;
            return ListenableBuilder(
              listenable: ctrl,
              builder: (_, _) => PdfEditorShell(controller: ctrl),
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    // Ctrl+F 打开搜索条并输入关键字
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(ctrl.searchOpen, isTrue);

    final searchFieldFinder = find.descendant(
      of: find.byType(SearchFloatingBar),
      matching: find.byType(TextField),
    );
    await tester.enterText(searchFieldFinder, 'invoice');
    await tester.pump();
    final searchField = tester.widget<TextField>(searchFieldFinder);
    searchField.controller!.selection = const TextSelection.collapsed(offset: 3);

    // 焦点移走后，再次按 Ctrl+F 应重新聚焦并全选 'invoice'
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(searchField.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 7));

    // 在焦点仍在搜索条内部时再按 Ctrl+F 同样保持聚焦并全选
    searchField.controller!.selection = const TextSelection.collapsed(offset: 2);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(searchField.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 7));

    // 合并操作前的未保存提示（取消 -> 不进入合并；不保存 -> 进入合并）
    final mergeCancelFuture = showMergeDialog(shellCtx, ctrl);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('合并前确认'), findsOneWidget);
    _expectUnifiedTypography(tester);
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await mergeCancelFuture;
    expect(find.text('合并 PDF'), findsNothing);

    final mergeProceedFuture = showMergeDialog(shellCtx, ctrl);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('合并前确认'), findsOneWidget);
    await tester.tap(find.text('不保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('合并 PDF'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await mergeProceedFuture;

    // 工具栏已固定在画布左侧，默认选择模式不会遮挡画布顶部。
    expect(find.byType(VerticalToolRail), findsOneWidget);
    expect(find.byTooltip(EditorTool.highlight.tooltip), findsOneWidget);
    await tester.tap(find.byTooltip(EditorTool.highlight.tooltip));
    await tester.pump();
    expect(ctrl.tool, EditorTool.highlight);
  });

  testWidgets('Merge entry points and dialog work without an open document',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final noDocCtrl = EditorController();
    addTearDown(noDocCtrl.dispose);

    var welcomeMergeTapped = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: Scaffold(
          body: WelcomeView(
            controller: noDocCtrl,
            onOpenFile: () {},
            onMergePdf: () => welcomeMergeTapped = true,
            onImageToPdf: () {},
            onOpenPath: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('合并 PDF'), findsOneWidget);
    await tester.tap(find.text('合并 PDF'));
    await tester.pump();
    expect(welcomeMergeTapped, isTrue);
    _expectUnifiedTypography(tester);

    var topBarMergeTapped = false;
    late BuildContext rootCtx;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              rootCtx = ctx;
              return Column(
                children: [
                  ModernTopBar(
                    controller: noDocCtrl,
                    onOpenFile: () {},
                    onMergePdf: () => topBarMergeTapped = true,
                    onImageToPdf: () {},
                    onSave: () {},
                    onSaveAs: () {},
                    onExportCurrentPng: () {},
                    onExportPagesDialog: () {},
                    onPrintDialog: () {},
                    onAbout: () {},
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('合并'), findsOneWidget);
    await tester.tap(find.text('合并'));
    await tester.pump();
    expect(topBarMergeTapped, isTrue);

    tester.view.physicalSize = const Size(1024, 640);
    await tester.pump();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1280, 800);
    await tester.pump();

    showMergeDialog(rootCtx, noDocCtrl);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('合并 PDF'), findsOneWidget);
    expect(
      find.text('请点击上方「添加 PDF 文件」，选择至少 2 份需要合并的 PDF'),
      findsOneWidget,
    );
    expect(find.text('已选 0 份（至少需 2 份）'), findsOneWidget);
    expect(find.text('输出目录：添加文件后自动指定'), findsOneWidget);
    final startBtn = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '开始合并'),
    );
    expect(startBtn.onPressed, isNull);
    final outNameLabelRect = tester.getRect(find.text('输出文件名'));
    final outNameEditableRect = tester.getRect(
      find.descendant(
        of: find.widgetWithText(TextField, '输出文件名'),
        matching: find.byType(EditableText),
      ),
    );
    expect(
      outNameEditableRect.top - outNameLabelRect.bottom,
      greaterThanOrEqualTo(6.0),
    );
    _expectUnifiedTypography(tester);

    tester.view.physicalSize = const Size(1024, 640);
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('合并 PDF'), findsNothing);
  });

  testWidgets(
      'Responsive shell breakpoints, overlay drawers, top bar visibility and canvas-scoped shortcuts',
      (WidgetTester tester) async {
    final ctrl = EditorController();
    addTearDown(ctrl.dispose);
    ctrl.filePath = r'C:\demo\responsive.pdf';
    ctrl.activeRenderPath = r'C:\demo\responsive.pdf';
    ctrl.suspendViewer = true;
    ctrl.pageCount = 5;
    ctrl.pageSizes = List.generate(5, (_) => (w: 595.0, h: 842.0));
    ctrl.pageRotations = List.filled(5, 0);

    // 1. 1024x640: 双侧栏默认收起，画布占满全宽，顶栏右侧面板开关完整可见
    tester.view.physicalSize = const Size(1024, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: ListenableBuilder(
          listenable: ctrl,
          builder: (_, _) => PdfEditorShell(controller: ctrl),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));

    expect(find.byType(ThumbnailsSidebar), findsNothing);
    expect(find.byType(RightInspector), findsNothing);

    final rightToggleFinder = find.byTooltip('显示/隐藏右侧面板 (Ctrl+Shift+B)');
    final leftToggleFinder = find.byTooltip('显示/隐藏缩略图栏 (Ctrl+B)');
    expect(rightToggleFinder, findsOneWidget);
    expect(leftToggleFinder, findsOneWidget);
    expect(tester.getRect(rightToggleFinder).right, lessThanOrEqualTo(1024.0));
    expect(tester.getRect(leftToggleFinder).right, lessThanOrEqualTo(1024.0));
    expect(tester.getRect(rightToggleFinder).height, closeTo(32.0, 2.0));

    // 点击打开右侧抽屉 -> 覆盖显示；再点左侧抽屉时互斥关闭右侧抽屉；按 Esc 关闭
    await tester.tap(rightToggleFinder);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(RightInspector), findsOneWidget);
    expect(find.text('文档信息'), findsOneWidget);

    await tester.tap(leftToggleFinder);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(ThumbnailsSidebar), findsOneWidget);
    expect(find.byType(RightInspector), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(ThumbnailsSidebar), findsNothing);
    expect(find.byType(RightInspector), findsNothing);

    // 关闭过窄屏抽屉后放大回宽屏 (>=1440)，停靠双栏仍正常恢复
    tester.view.physicalSize = const Size(1480, 920);
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(ThumbnailsSidebar), findsOneWidget);
    expect(find.byType(RightInspector), findsOneWidget);
    tester.view.physicalSize = const Size(1024, 640);
    await tester.pump(const Duration(milliseconds: 50));

    // 单字母工具快捷键在画布未获焦时不误切工具
    expect(ctrl.tool, EditorTool.select);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyH);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyH);
    await tester.pump();
    expect(ctrl.tool, EditorTool.select);

    // 搜索条空匹配文案清晰
    ctrl.openOrFocusSearch();
    ctrl.searchQuery = '不存在的关键字';
    ctrl.searchMatchesCount = 0;
    ctrl.refresh();
    await tester.pump();
    expect(find.text('无匹配'), findsOneWidget);

    // 默认高亮透明度与快捷键提示
    expect(kToolDefaults[AnnotationKind.highlight]!.opacity, closeTo(0.26, 0.001));
    expect(EditorTool.highlight.tooltip, contains('(H)'));
  });
}

void _expectUnifiedTypography(WidgetTester tester) {
  for (final element in find.byType(Text).evaluate()) {
    final textWidget = element.widget as Text;
    final resolved = DefaultTextStyle.of(element).style.merge(textWidget.style);
    expect(
      resolved.fontSize,
      isIn(AppTypography.allowedSizes),
      reason: 'Text "${textWidget.data ?? textWidget.textSpan?.toPlainText()}" '
          'had unexpected fontSize ${resolved.fontSize}',
    );
  }
  for (final element in find.byType(EditableText).evaluate()) {
    final editable = element.widget as EditableText;
    expect(
      editable.style.fontSize,
      isIn(AppTypography.allowedSizes),
      reason: 'EditableText "${editable.controller.text}" '
          'had unexpected fontSize ${editable.style.fontSize}',
    );
  }
  for (final element in find.byType(RichText).evaluate()) {
    final hasIconAncestor = find
        .ancestor(
          of: find.byWidget(element.widget),
          matching: find.byType(Icon),
        )
        .evaluate()
        .isNotEmpty;
    if (hasIconAncestor) continue;
    final rich = element.widget as RichText;
    rich.text.visitChildren((span) {
      if (span is TextSpan && (span.text?.trim().isNotEmpty ?? false)) {
        final size = span.style?.fontSize;
        if (size != null) {
          expect(
            size,
            isIn(AppTypography.allowedSizes),
            reason: 'RichText span "${span.text}" had unexpected fontSize $size',
          );
        }
      }
      return true;
    });
  }
}

Color? _fillColorOf(WidgetTester tester, Finder targetFinder) {
  final containerFinder = find.ancestor(
    of: targetFinder,
    matching: find.byType(AnimatedContainer),
  );
  final dec = tester
      .widget<AnimatedContainer>(containerFinder.first)
      .decoration as BoxDecoration;
  return dec.color;
}

Future<void> _hoverOver(
  WidgetTester tester,
  TestGesture gesture,
  Finder target,
) async {
  await gesture.moveTo(tester.getCenter(target));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}
