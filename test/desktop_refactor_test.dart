import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pdf_editor_flutter/main.dart';
import 'package:pdf_editor_flutter/models/annotation_model.dart';
import 'package:pdf_editor_flutter/state/editor_controller.dart';
import 'package:pdf_editor_flutter/ui/dialogs/command_palette_dialog.dart';
import 'package:pdf_editor_flutter/ui/theme/app_theme.dart';
import 'package:pdf_editor_flutter/ui/widgets/document_tab_bar.dart';
import 'package:pdf_editor_flutter/ui/widgets/pdf_workspace_view.dart';
import 'package:pdf_editor_flutter/ui/widgets/vertical_tool_rail.dart';

void main() {
  testWidgets('DocumentTabBar renders idle and document tabs', (tester) async {
    final controller = EditorController();
    addTearDown(controller.dispose);

    var opened = 0;
    String? selected;
    String? closed;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: ListenableBuilder(
          listenable: controller,
          builder: (_, _) => DocumentTabBar(
            controller: controller,
            onOpenFile: () => opened++,
            onSelectTab: (path) => selected = path,
            onCloseTab: (path) => closed = path,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('开始页'), findsOneWidget);
    await tester.tap(find.byTooltip('打开新文档 (Ctrl+O)'));
    expect(opened, 1);

    controller.filePath = r'C:\docs\active.pdf';
    controller.activeRenderPath = controller.filePath;
    controller.pageCount = 2;
    controller.openTabs.add(
      const DocumentTabItem(
        path: r'C:\docs\active.pdf',
        title: 'active.pdf',
        pageCount: 2,
      ),
    );
    controller.openTabs.add(
      const DocumentTabItem(
        path: r'C:\docs\other.pdf',
        title: 'other.pdf',
        pageCount: 4,
      ),
    );
    controller.refresh();
    await tester.pump();

    expect(find.text('active.pdf'), findsOneWidget);
    expect(find.text('other.pdf'), findsOneWidget);
    expect(find.byTooltip('关闭标签'), findsNWidgets(2));

    await tester.tap(find.text('other.pdf'));
    expect(selected, r'C:\docs\other.pdf');
    await tester.tap(find.byTooltip('关闭标签').last);
    expect(closed, r'C:\docs\other.pdf');
  });

  testWidgets('VerticalToolRail keeps the canvas clear and shows context strip',
      (tester) async {
    tester.view.physicalSize = const Size(900, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = EditorController();
    addTearDown(controller.dispose);
    controller.filePath = r'C:\docs\rail.pdf';
    controller.activeRenderPath = controller.filePath;
    controller.suspendViewer = true;
    controller.pageCount = 1;
    controller.pageSizes = const [(w: 595.0, h: 842.0)];
    controller.pageRotations = [0];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: ListenableBuilder(
          listenable: controller,
          builder: (_, _) => PdfEditorShell(controller: controller),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));

    final rail = tester.getRect(find.byType(VerticalToolRail));
    final canvas = tester.getRect(find.byType(PdfWorkspaceView));
    expect(rail.width, 46.0);
    expect(rail.right, closeTo(canvas.left, 0.1));
    expect(rail.top, closeTo(canvas.top, 0.1));
    expect(find.byType(ToolContextStrip), findsNothing);

    await tester.tap(find.byTooltip(EditorTool.highlight.tooltip));
    await tester.pump();
    expect(controller.tool, EditorTool.highlight);

    await tester.tap(find.byTooltip(EditorTool.stamp.tooltip));
    await tester.pump();
    expect(find.byType(ToolContextStrip), findsOneWidget);
    expect(find.text('图章:'), findsOneWidget);

    controller.annotations = [
      const PdfAnnotationItem(
        id: 'selected',
        kind: AnnotationKind.rect,
        page: 0,
        bbox: PdfRectBox(10, 10, 40, 40),
        color: '#2563eb',
        opacity: 1,
        createdAt: 1,
      ),
    ];
    controller.selectedIds.add('selected');
    controller.refresh();
    await tester.pump();
    expect(find.text('已选 1 项'), findsOneWidget);
    expect(find.text('复制'), findsOneWidget);
    expect(find.text('再制'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
  });

  testWidgets('Ctrl+K opens palette, filters, executes, and Esc closes',
      (tester) async {
    tester.view.physicalSize = const Size(1024, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = EditorController();
    addTearDown(controller.dispose);
    controller.filePath = r'C:\docs\palette.pdf';
    controller.activeRenderPath = controller.filePath;
    controller.suspendViewer = true;
    controller.pageCount = 1;
    controller.pageSizes = const [(w: 595.0, h: 842.0)];
    controller.pageRotations = [0];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: PdfEditorShell(controller: controller),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.byType(CommandPaletteDialog), findsOneWidget);
    final search = find.descendant(
      of: find.byType(CommandPaletteDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(search, '图章');
    await tester.pump();
    expect(find.text('图章'), findsNWidgets(2));
    expect(find.text('撤销'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(controller.tool, EditorTool.stamp);
    expect(find.byType(CommandPaletteDialog), findsNothing);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(find.byType(CommandPaletteDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(CommandPaletteDialog), findsNothing);
  });

  testWidgets('CommandPaletteDialog filters keywords and supports ArrowUp',
      (tester) async {
    var executed = '';
    late BuildContext root;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: Builder(
          builder: (context) {
            root = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    final future = showCommandPaletteDialog(
      root,
      actions: [
        CommandPaletteAction(
          id: 'first',
          group: '测试',
          label: '第一个命令',
          icon: Icons.looks_one_outlined,
          keywords: const ['alpha'],
          onExecute: () => executed = 'first',
        ),
        CommandPaletteAction(
          id: 'second',
          group: '测试',
          label: '第二个命令',
          icon: Icons.looks_two_outlined,
          keywords: const ['beta'],
          onExecute: () => executed = 'second',
        ),
      ],
    );
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'beta');
    await tester.pump();
    expect(find.text('第二个命令'), findsOneWidget);
    expect(find.text('第一个命令'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await future;
    expect(executed, 'second');
  });
}
