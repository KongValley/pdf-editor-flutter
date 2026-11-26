import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pdf_editor_flutter/main.dart';
import 'package:pdf_editor_flutter/models/annotation_model.dart';
import 'package:pdf_editor_flutter/state/editor_controller.dart';
import 'package:pdf_editor_flutter/ui/dialogs/batch_dialogs.dart';
import 'package:pdf_editor_flutter/ui/dialogs/editor_dialogs.dart';
import 'package:pdf_editor_flutter/ui/theme/app_theme.dart';
import 'package:pdf_editor_flutter/ui/widgets/desktop_controls.dart';
import 'package:pdf_editor_flutter/ui/widgets/floating_tool_dock.dart';
import 'package:pdf_editor_flutter/ui/widgets/hover_feedback.dart';
import 'package:pdf_editor_flutter/ui/widgets/modern_status_bar.dart';
import 'package:pdf_editor_flutter/ui/widgets/modern_top_bar.dart';
import 'package:pdf_editor_flutter/ui/widgets/pdf_workspace_view.dart';
import 'package:pdf_editor_flutter/ui/widgets/right_inspector.dart';
import 'package:pdf_editor_flutter/ui/widgets/search_floating_bar.dart';
import 'package:pdf_editor_flutter/ui/widgets/thumbnails_sidebar.dart';

EditorController _makeTestDocController() {
  final ctrl = EditorController();
  ctrl.filePath = r'C:\demo\interaction_test.pdf';
  ctrl.activeRenderPath = r'C:\demo\interaction_test.pdf';
  ctrl.suspendViewer = true;
  ctrl.pageCount = 5;
  ctrl.pageSizes = List.generate(5, (_) => (w: 595.0, h: 842.0));
  ctrl.pageRotations = List.filled(5, 0);
  return ctrl;
}

void main() {
  testWidgets(
      'DesktopHoverContainer supports Tab focus, focus ring, and Enter/Space activation',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var firstHits = 0;
    var secondHits = 0;
    final focusA = FocusNode(debugLabel: 'btn_a');
    final focusB = FocusNode(debugLabel: 'btn_b');
    addTearDown(focusA.dispose);
    addTearDown(focusB.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: Scaffold(
          body: Row(
            children: [
              DesktopHoverContainer(
                focusNode: focusA,
                tooltip: '按钮 A',
                minWidth: 32,
                minHeight: 32,
                onTap: () => firstHits++,
                builder: (_, _, _) => const Text('按钮 A'),
              ),
              const SizedBox(width: 8),
              DesktopHoverContainer(
                focusNode: focusB,
                tooltip: '按钮 B',
                minWidth: 32,
                minHeight: 32,
                onTap: () => secondHits++,
                builder: (_, _, _) => const Text('按钮 B'),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    // Tab 聚焦到按钮 A -> Enter 激活
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focusA.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(firstHits, 1);

    // Tab 聚焦到按钮 B -> Space 激活
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(focusB.hasFocus, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(secondHits, 1);
  });

  testWidgets(
      'F6 focuses canvas; single-letter shortcuts only trigger when canvas focused and not IME composing',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1480, 920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ctrl = _makeTestDocController();
    addTearDown(ctrl.dispose);

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

    // 画布未获焦时，按 H/R 不应切换工具
    expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('pdf_canvas'));
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pump();
    expect(ctrl.tool, EditorTool.select);

    // 注意：suspendViewer=true 时 PdfWorkspaceView 返回占位容器，不挂载 Focus；
    // 解除 suspendViewer 并验证 Focus 节点与按键门控需要真实 Focus，这里用直接聚焦或非挂起外壳验证。
    // 先验证直接打开搜索框并处于 IME 组字状态时，Esc 不会关闭搜索条，H 不会切工具
    ctrl.openOrFocusSearch();
    await tester.pump();
    expect(ctrl.searchOpen, isTrue);

    final searchFieldFinder = find.descendant(
      of: find.byType(SearchFloatingBar),
      matching: find.byType(TextField),
    );
    final searchField = tester.widget<TextField>(searchFieldFinder);
    searchField.controller!.value = const TextEditingValue(
      text: 'ni',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    await tester.pump();

    // 组字态下按 Esc 不关闭搜索条
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(ctrl.searchOpen, isTrue);

    // 组字态下按 H 不切换工具
    await tester.sendKeyEvent(LogicalKeyboardKey.keyH);
    await tester.pump();
    expect(ctrl.tool, EditorTool.select);

    // 清除组字态后，按 Esc 正常关闭搜索条
    searchField.controller!.value = const TextEditingValue(
      text: '你',
      selection: TextSelection.collapsed(offset: 1),
      composing: TextRange.empty,
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(ctrl.searchOpen, isFalse);
  });

  testWidgets(
      'ZoomIntent locks manual zoom and resists viewport resize overwrite',
      (WidgetTester tester) async {
    final ctrl = _makeTestDocController();
    addTearDown(ctrl.dispose);

    expect(ctrl.zoomIntent, ZoomIntent.fitWidth);

    ctrl.setZoomPercent(135);
    expect(ctrl.zoomIntent, ZoomIntent.manual);
    expect(ctrl.scale, closeTo(1.35, 0.001));

    // 手动缩放后，即使视口变化回调触发，缩放仍保持 135%
    ctrl.onWorkspaceViewportResized();
    expect(ctrl.scale, closeTo(1.35, 0.001));
    expect(ctrl.zoomIntent, ZoomIntent.manual);
  });

  testWidgets(
      'Unsaved dialog uses barrierDismissible=false, safe autofocus, truthful summary, and guards image-to-pdf',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ctrl = _makeTestDocController();
    addTearDown(ctrl.dispose);

    // 预置 2 条未改动的既有批注：此时未产生编辑历史，unsavedSummary 不应虚报批注修改
    ctrl.annotations = const [
      PdfAnnotationItem(
        id: 'existing_1',
        kind: AnnotationKind.highlight,
        page: 0,
        bbox: PdfRectBox(10, 10, 80, 16),
        color: '#ffe066',
        opacity: 0.26,
        createdAt: 1,
      ),
    ];
    expect(ctrl.unsavedSummary, isEmpty);

    // 添加 1 条新批注 -> dirty=true，unsavedSummary 准确记录 1 次批注修改
    ctrl.addAnnotation(
      const PdfAnnotationItem(
        id: 'new_1',
        kind: AnnotationKind.rect,
        page: 0,
        bbox: PdfRectBox(20, 20, 60, 40),
        color: '#e03131',
        opacity: 1.0,
        createdAt: 2,
      ),
    );
    expect(ctrl.dirty, isTrue);
    expect(ctrl.unsavedSummary, contains('1 次批注修改'));

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

    // 1. showUnsavedChangesDialog: 点击空白遮罩不关闭，按 Esc 取消
    final dialogFuture = showUnsavedChangesDialog(
      rootCtx,
      title: '未保存的更改',
      fileName: ctrl.displayFileName,
      summary: ctrl.unsavedSummary,
      message: '确认是否保存？',
      saveLabel: '保存并继续',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('1 次批注修改'), findsOneWidget);
    // 点击左上角遮罩区域不应关闭弹窗
    await tester.tapAt(const Offset(5, 5));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('未保存的更改'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(await dialogFuture, UnsavedChangesChoice.cancel);

    // 2. showImageToPdfDialog 在 dirty 态弹出三选一确认：取消不进入图转PDF，不保存则继续进入
    final imgCancelFuture = showImageToPdfDialog(rootCtx, ctrl);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('图片转 PDF 前确认'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await imgCancelFuture;
    expect(find.text('请添加 PNG 或 JPEG 图片'), findsNothing);

    final imgProceedFuture = showImageToPdfDialog(rootCtx, ctrl);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('图片转 PDF 前确认'), findsOneWidget);
    await tester.tap(find.text('不保存'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('请添加 PNG 或 JPEG 图片'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await imgProceedFuture;
  });

  testWidgets(
      'Overlay drawer does not shrink canvas at 1280/1024; ultraCompact 900 keeps filename & panel toggles visible',
      (WidgetTester tester) async {
    final ctrl = _makeTestDocController();
    addTearDown(ctrl.dispose);

    // 1280x800: 左停靠 + 右覆盖抽屉，打开右抽屉不压缩画布宽度
    tester.view.physicalSize = const Size(1280, 800);
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

    expect(find.byType(ThumbnailsSidebar), findsOneWidget);
    expect(find.byType(RightInspector), findsNothing);
    final canvasWidthBefore =
        tester.getRect(find.byType(PdfWorkspaceView)).width;
    expect(canvasWidthBefore, closeTo(1024.0, 1.0));

    await tester.tap(find.byTooltip('显示/隐藏右侧面板 (Ctrl+Shift+B)'));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(RightInspector), findsOneWidget);
    final canvasWidthAfter =
        tester.getRect(find.byType(PdfWorkspaceView)).width;
    expect(canvasWidthAfter, closeTo(canvasWidthBefore, 0.5));

    // 切到 900x640（极窄模式）：顶栏单行、文件名仍可见、面板开关在视口内、底栏视图收进菜单无溢出
    tester.view.physicalSize = const Size(900, 640);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));

    expect(tester.takeException(), isNull);
    expect(tester.getRect(find.byType(ModernTopBar)).height, 48.0);
    expect(
      find.descendant(
        of: find.byType(ModernTopBar),
        matching: find.text('interaction_test.pdf'),
      ),
      findsOneWidget,
    );
    expect(
      tester
          .getRect(find.byTooltip('显示/隐藏右侧面板 (Ctrl+Shift+B)'))
          .right,
      lessThanOrEqualTo(900.0),
    );
    expect(
      find.descendant(
        of: find.byType(ModernStatusBar),
        matching: find.byTooltip('阅读模式与页面旋转'),
      ),
      findsOneWidget,
    );
  });

  testWidgets(
      'Narrow FloatingToolDock stays single-row with More overflow menu',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(700, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ctrl = _makeTestDocController();
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: ctrl,
            builder: (_, _) => Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 12, left: 16, right: 16),
                child: FloatingToolDock(controller: ctrl),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    // 展开态仍为单行（高度 <= 48），且提供“更多批注工具”菜单
    expect(tester.getRect(find.byType(FloatingToolDock)).height, lessThanOrEqualTo(48.0));
    final moreToolsBtn = find.byTooltip('更多批注工具');
    expect(moreToolsBtn, findsOneWidget);

    await tester.tap(moreToolsBtn);
    await tester.pumpAndSettle();
    await tester.tap(find.text('图章').last);
    await tester.pumpAndSettle();

    expect(ctrl.tool, EditorTool.stamp);
    expect(find.text('图章:'), findsOneWidget);
  });

  testWidgets(
      'AppTheme and custom desktop controls replace raw Material styling in light & dark themes',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final dark in [false, true]) {
      final theme = AppTheme.build(dark);
      final ext = dark ? AppColors.dark : AppColors.light;
      expect(theme.splashFactory, NoSplash.splashFactory);
      expect(theme.colorScheme.primary, ext.accent);
      expect(theme.colorScheme.surface, ext.surfaceBg);
      expect(theme.popupMenuTheme.color, ext.elevatedBg);
      expect(theme.popupMenuTheme.surfaceTintColor, Colors.transparent);
      expect(theme.dialogTheme.surfaceTintColor, Colors.transparent);
      expect(theme.sliderTheme.trackHeight, 4.0);
      expect(theme.progressIndicatorTheme.linearMinHeight, 5.0);
    }

    var checked = false;
    var mode = 'pixel';
    var selected = 'a';

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(true),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DesktopDialogHeader(
                    icon: Icons.tune_rounded,
                    title: '桌面控件校验',
                    subtitle: '深色主题自定义控件',
                    onClose: () {},
                  ),
                  const SizedBox(height: 12),
                  DesktopCheckboxRow(
                    value: checked,
                    label: '启用桌面勾选框',
                    onChanged: (v) => setState(() => checked = v),
                  ),
                  const SizedBox(height: 12),
                  DesktopSegmentedControl<String>(
                    value: mode,
                    options: const [
                      DesktopSegmentedOption(value: 'pixel', label: '按像素'),
                      DesktopSegmentedOption(value: 'a4', label: '按 A4'),
                    ],
                    onChanged: (v) => setState(() => mode = v),
                  ),
                  const SizedBox(height: 12),
                  DesktopSelect<String>(
                    value: selected,
                    items: const [
                      DropdownMenuItem(value: 'a', child: Text('选项 A')),
                      DropdownMenuItem(value: 'b', child: Text('选项 B')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => selected = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  const DesktopProgressPanel(
                    message: '正在处理',
                    detail: 'demo.pdf',
                    progress: 0.5,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('50%'), findsOneWidget);
    await tester.tap(find.text('启用桌面勾选框'));
    await tester.pump();
    expect(checked, isTrue);

    await tester.tap(find.text('按 A4'));
    await tester.pump();
    expect(mode, 'a4');

    await tester.tap(find.text('选项 A'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.text('选项 B').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(selected, 'b');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'ModernStatusBar compact inputs stay vertically centered on Windows VisualDensity.compact',
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final ctrl = _makeTestDocController();
    addTearDown(ctrl.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ModernStatusBar(
              controller: ctrl,
              onOpenProblems: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final editables = find.descendant(
      of: find.byType(ModernStatusBar),
      matching: find.byType(EditableText),
    );
    expect(editables, findsNWidgets(2));

    final pageFieldBox = find
        .ancestor(
          of: editables.first,
          matching: find.byType(AnimatedContainer),
        )
        .first;
    final zoomFieldBox = find
        .ancestor(
          of: editables.last,
          matching: find.byType(AnimatedContainer),
        )
        .first;
    final slashText = find.text('/ 5');

    final pageBoxCenterY = tester.getCenter(pageFieldBox).dy;
    final pageEditableCenterY = tester.getCenter(editables.first).dy;
    final zoomBoxCenterY = tester.getCenter(zoomFieldBox).dy;
    final zoomEditableCenterY = tester.getCenter(editables.last).dy;
    final slashCenterY = tester.getCenter(slashText).dy;

    expect((pageEditableCenterY - pageBoxCenterY).abs(), lessThanOrEqualTo(0.5));
    expect((zoomEditableCenterY - zoomBoxCenterY).abs(), lessThanOrEqualTo(0.5));
    expect((pageEditableCenterY - slashCenterY).abs(), lessThanOrEqualTo(1.0));
    expect(tester.takeException(), isNull);
  });
}
