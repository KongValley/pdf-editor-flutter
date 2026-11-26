import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:pdf_editor_flutter/main.dart';
import 'package:pdf_editor_flutter/models/annotation_model.dart';
import 'package:pdf_editor_flutter/models/document_models.dart';
import 'package:pdf_editor_flutter/state/editor_controller.dart';
import 'package:pdf_editor_flutter/ui/theme/app_theme.dart';
import 'package:pdf_editor_flutter/ui/widgets/floating_tool_dock.dart';
import 'package:pdf_editor_flutter/ui/widgets/modern_status_bar.dart';
import 'package:pdf_editor_flutter/ui/widgets/modern_top_bar.dart';
import 'package:pdf_editor_flutter/ui/widgets/pdf_workspace_view.dart';
import 'package:pdf_editor_flutter/ui/widgets/right_inspector.dart';
import 'package:pdf_editor_flutter/ui/widgets/search_floating_bar.dart';
import 'package:pdf_editor_flutter/ui/widgets/thumbnails_sidebar.dart';
import 'package:pdf_editor_flutter/ui/widgets/welcome_view.dart';

typedef _Metrics = Map<String, Object?>;

final List<_Metrics> _report = [];

void main() {
  tearDownAll(() {
    final out = File('build/ui-audit/report.json');
    out.parent.createSync(recursive: true);
    out.writeAsStringSync(_encodeJson(_report, pretty: true));
    // ignore: avoid_print
    print('UI_AUDIT_JSON=${out.absolute.path}');
  });

  testWidgets('measure workspace density and panel policy at four widths',
      (WidgetTester tester) async {
    for (final size in const [
      Size(1480, 920),
      Size(1280, 800),
      Size(1024, 640),
      Size(900, 640),
    ]) {
      final ctrl = _documentController();
      addTearDown(ctrl.dispose);

      await _setView(tester, size);
      await tester.pumpWidget(_realShell(ctrl));
      await tester.pump(const Duration(milliseconds: 60));

      final top = tester.getRect(find.byType(ModernTopBar));
      final status = tester.getRect(find.byType(ModernStatusBar));
      final thumbsFound = find.byType(ThumbnailsSidebar).evaluate().isNotEmpty;
      final inspectorFound = find.byType(RightInspector).evaluate().isNotEmpty;
      final thumbsW =
          thumbsFound ? tester.getRect(find.byType(ThumbnailsSidebar)).width : 0.0;
      final inspectorW =
          inspectorFound ? tester.getRect(find.byType(RightInspector)).width : 0.0;
      final canvasRect = tester.getRect(find.byType(PdfWorkspaceView));
      final dock = tester.getRect(find.byType(FloatingToolDock));
      final toolbarChrome = top.height + status.height;
      final panelChrome = thumbsW + inspectorW;
      final dockOcclusion =
          (dock.bottom - canvasRect.top).clamp(0.0, canvasRect.height);

      _report.add({
        'group': 'workspace_geometry',
        'viewport': '${size.width.toInt()}x${size.height.toInt()}',
        'topBarHeight': _r(top.height),
        'statusBarHeight': _r(status.height),
        'thumbnailsWidth': _r(thumbsW),
        'inspectorWidth': _r(inspectorW),
        'canvasWidth': _r(canvasRect.width),
        'canvasHeight': _r(canvasRect.height),
        'canvasAreaPx': (canvasRect.width * canvasRect.height).round(),
        'canvasAreaRatio':
            _r((canvasRect.width * canvasRect.height) / (size.width * size.height)),
        'canvasWidthRatio': _r(canvasRect.width / size.width),
        'horizontalChromeRatio': _r(panelChrome / size.width),
        'verticalChromeRatio': _r(toolbarChrome / size.height),
        'dockTopOcclusionPx': _r(dockOcclusion),
        'dockOcclusionRatio': _r(dockOcclusion / canvasRect.height),
        'dockHeight': _r(dock.height),
        'inspectorVisible': inspectorFound,
        'inspectorHasEmptyState':
            find.textContaining('在画布上点击选中').evaluate().isNotEmpty,
      });
    }
  });

  testWidgets('measure control hit targets and top-bar crowding',
      (WidgetTester tester) async {
    for (final size in const [Size(1480, 920), Size(1280, 800), Size(1024, 640)]) {
      final ctrl = _documentController();
      addTearDown(ctrl.dispose);

      await _setView(tester, size);
      await tester.pumpWidget(_realShell(ctrl));
      await tester.pump(const Duration(milliseconds: 60));

      final rightToggle = find.byTooltip('显示/隐藏右侧面板 (Ctrl+Shift+B)');
      final leftToggle = find.byTooltip('显示/隐藏缩略图栏 (Ctrl+B)');
      final rightToggleRect = tester.getRect(rightToggle);
      final leftToggleRect = tester.getRect(leftToggle);
      expect(rightToggleRect.right, lessThanOrEqualTo(size.width));
      expect(leftToggleRect.right, lessThanOrEqualTo(size.width));

      _report.add({
        'group': 'hit_targets',
        'viewport': '${size.width.toInt()}x${size.height.toInt()}',
        'leftToggleSize':
            '${_r(leftToggleRect.width)}x${_r(leftToggleRect.height)}',
        'rightToggleSize':
            '${_r(rightToggleRect.width)}x${_r(rightToggleRect.height)}',
        'rightToggleVisibleInViewport': rightToggleRect.right <= size.width,
        'topBarSingleLine': tester.getRect(find.byType(ModernTopBar)).height == 48,
      });
    }
  });

  testWidgets('measure contrast tokens in both themes',
      (WidgetTester tester) async {
    _setViewSync(tester, const Size(1280, 800));
    for (final dark in [false, true]) {
      final theme = AppTheme.build(dark);
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey('contrast_theme_$dark'),
          theme: theme,
          home: Builder(builder: (context) {
            final c = context.appColors;
            final surface = c.surfaceBg;
            final primary = theme.colorScheme.onSurface;
            _report.add({
              'group': 'contrast',
              'theme': dark ? 'dark' : 'light',
              'brightness': theme.brightness.name,
              'onSurface': hexColor(primary),
              'canvasBg': hexColor(c.canvasBg),
              'muted_on_surface': _r(_contrast(c.mutedText, surface)),
              'accent_on_surface': _r(_contrast(c.accent, surface)),
              'accent_on_accentSoft': _r(_contrast(c.accent, c.accentSoft)),
              'on_surface': _r(_contrast(primary, surface)),
              'text_on_canvas': _r(_contrast(primary, c.canvasBg)),
              'secondary_text_on_canvas':
                  _r(_contrast(c.mutedText, c.canvasBg)),
            });
            return const SizedBox.shrink();
          }),
        ),
      );
    }
  });

  testWidgets('measure welcome first-paint density',
      (WidgetTester tester) async {
    final ctrl = EditorController();
    addTearDown(ctrl.dispose);
    final tmp = Directory.systemTemp.createTempSync('pdf_ui_audit_recent_');
    addTearDown(() => tmp.deleteSync(recursive: true));
    ctrl.recentFiles = List.generate(
      8,
      (i) => RecentDocumentEntry(
        path: '${tmp.path}${Platform.pathSeparator}recent_$i.pdf',
        page: 1,
        updatedAt: 1732530000000 + i,
      ),
    );

    await _setView(tester, const Size(1480, 920));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.build(false),
        home: Scaffold(
          backgroundColor: contextColorless(),
          body: WelcomeView(
            controller: ctrl,
            onOpenFile: () {},
            onMergePdf: () {},
            onImageToPdf: () {},
            onOpenPath: (_) async {},
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));

    final card = tester.getRect(
      find
          .ancestor(
            of: find.text('打开 PDF 文件 (Ctrl+O)'),
            matching: find.byType(Container),
          )
          .last,
    );
    final open = tester.getRect(find.text('打开 PDF 文件 (Ctrl+O)'));
    final merge = tester.getRect(find.text('合并 PDF'));
    final image = tester.getRect(find.text('图片转 PDF'));
    final recent = tester.getRect(find.text('最近打开'));

    _report.add({
      'group': 'welcome',
      'viewport': '1480x920',
      'cardWidth': _r(card.width),
      'cardHeight': _r(card.height),
      'cardWidthRatio': _r(card.width / 1480),
      'openButton': '${_r(open.width)}x${_r(open.height)}',
      'mergeButton': '${_r(merge.width)}x${_r(merge.height)}',
      'imageButton': '${_r(image.width)}x${_r(image.height)}',
      'recentSectionVisible': recent.width > 0,
      'recentCount': ctrl.recentFiles.length,
      'primaryActionDistinct': open.width > merge.width,
    });
  });

  testWidgets('measure toolbar auto-collapse and search overlap',
      (WidgetTester tester) async {
    final ctrl = _documentController();
    addTearDown(ctrl.dispose);
    ctrl.searchOpen = true;
    ctrl.tool = EditorTool.highlight;

    await _setView(tester, const Size(1480, 920));
    await tester.pumpWidget(_realShell(ctrl));
    await tester.pump(const Duration(milliseconds: 60));

    final dock = tester.getRect(find.byType(FloatingToolDock));
    final search = tester.getRect(find.byType(SearchFloatingBar));

    _report.add({
      'group': 'toolbar',
      'viewport': '1480x920',
      'expandedDock': _r(dock.height),
      'searchBarWidth': _r(search.width),
      'searchBarHeight': _r(search.height),
      'searchLeft': _r(search.left),
      'searchRight': _r(search.right),
      'sameHorizontalBand': (search.top - dock.top).abs() < 4,
      'totalTopBandHeight': _r(math.max(dock.bottom, search.bottom) -
          math.min(dock.top, search.top)),
      'dockWidthPx': _r(dock.width),
      'dockToolCount': EditorTool.values.length,
    });
  });

  testWidgets('measure annotation overlay selection chrome and panel occupancy',
      (WidgetTester tester) async {
    final ctrl = _documentController();
    addTearDown(ctrl.dispose);
    ctrl.tool = EditorTool.highlight;
    ctrl.annotations = [
      const PdfAnnotationItem(
        id: 'audit_hl',
        kind: AnnotationKind.highlight,
        page: 0,
        bbox: PdfRectBox(80, 620, 280, 18),
        color: '#ffe066',
        opacity: 0.26,
        createdAt: 1,
      ),
    ];
    ctrl.selectedIds.add('audit_hl');

    await _setView(tester, const Size(1480, 920));
    await tester.pumpWidget(_realShell(ctrl));
    await tester.pump(const Duration(milliseconds: 60));

    final inspector = tester.getRect(find.byType(RightInspector));
    final propsTitle = tester.getRect(find.text('高亮 · 第 1 页'));
    final topDelete = tester.getRect(find.byTooltip('删除此批注 (Delete)'));
    final colorHeading = tester.getRect(find.text('颜色'));
    final slider = tester.getRect(find.byType(Slider).first);

    _report.add({
      'group': 'inspector',
      'viewport': '1480x920',
      'inspectorWidth': _r(inspector.width),
      'titleToColorGap': _r(colorHeading.top - propsTitle.bottom),
      'colorToSliderGap': _r(slider.top - colorHeading.bottom),
      'topDeleteOffsetFromTop': _r(topDelete.top - inspector.top),
      'panelScrollable': find
          .descendant(
            of: find.byType(RightInspector),
            matching: find.byType(Scrollable),
          )
          .evaluate()
          .isNotEmpty,
    });
  });

  testWidgets('measure toolbar shortcut hint discoverability',
      (WidgetTester tester) async {
    final ctrl = _documentController();
    addTearDown(ctrl.dispose);
    ctrl.tool = EditorTool.highlight;

    await _setView(tester, const Size(1480, 920));
    await tester.pumpWidget(_realShell(ctrl));
    await tester.pump(const Duration(milliseconds: 60));

    final tooltipsWithShortcut = [
      for (final t in EditorTool.values)
        if (RegExp(r'\([A-Z]\)').hasMatch(t.tooltip)) t.tooltip,
    ];

    _report.add({
      'group': 'shortcut_discoverability',
      'viewport': '1480x920',
      'tooltipsWithSingleKeyShortcutCount': tooltipsWithShortcut.length,
      'toolCount': EditorTool.values.length,
      'statusBarVisible': find.byType(ModernStatusBar).evaluate().isNotEmpty,
    });
  });
}

EditorController _documentController() {
  final ctrl = EditorController();
  ctrl.filePath = r'C:\demo\audit.pdf';
  ctrl.activeRenderPath = r'C:\demo\audit.pdf';
  ctrl.suspendViewer = true;
  ctrl.pageCount = 5;
  ctrl.pageSizes = List.generate(5, (_) => (w: 595.0, h: 842.0));
  ctrl.pageRotations = List.filled(5, 0);
  return ctrl;
}

Widget _realShell(EditorController ctrl) {
  return MaterialApp(
    theme: AppTheme.build(false),
    home: ListenableBuilder(
      listenable: ctrl,
      builder: (_, _) => PdfEditorShell(controller: ctrl),
    ),
  );
}

Color contextColorless() => const Color(0xFFF3F5F8);

Future<void> _setView(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void _setViewSync(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

double _contrast(Color a, Color b, {bool clampMin = true}) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final hi = math.max(la, lb);
  final lo = math.min(la, lb);
  final ratio = (hi + 0.05) / (lo + 0.05);
  return clampMin ? math.max(ratio, 1.0) : ratio;
}

String hexColor(Color color) {
  final a = (color.a * 255).round();
  final r = (color.r * 255).round();
  final g = (color.g * 255).round();
  final b = (color.b * 255).round();
  return '#${a.toRadixString(16).padLeft(2, '0')}'
      '${r.toRadixString(16).padLeft(2, '0')}'
      '${g.toRadixString(16).padLeft(2, '0')}'
      '${b.toRadixString(16).padLeft(2, '0')}';
}

double _luminance(Color color) {
  double channel(double c) {
    return c <= 0.04045
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _r(double v) => double.parse(v.toStringAsFixed(2));

String _encodeJson(Object? value, {bool pretty = false}) {
  final buf = StringBuffer();
  void write(Object? v, int depth) {
    final pad = pretty ? '  ' * depth : '';
    final childPad = pretty ? '  ' * (depth + 1) : '';
    if (v is Map) {
      buf.write('{');
      if (v.isNotEmpty && pretty) buf.write('\n');
      var first = true;
      for (final e in v.entries) {
        if (!first) buf.write(pretty ? ',\n' : ',');
        first = false;
        buf.write(childPad);
        buf.write(_jsonString(e.key.toString()));
        buf.write(pretty ? ': ' : ':');
        write(e.value, depth + 1);
      }
      if (v.isNotEmpty) buf.write(pretty ? '\n$pad' : '');
      buf.write('}');
    } else if (v is List) {
      buf.write('[');
      if (v.isNotEmpty && pretty) buf.write('\n');
      for (var i = 0; i < v.length; i++) {
        if (i > 0) buf.write(pretty ? ',\n' : ',');
        buf.write(childPad);
        write(v[i], depth + 1);
      }
      if (v.isNotEmpty) buf.write(pretty ? '\n$pad' : '');
      buf.write(']');
    } else if (v is String) {
      buf.write(_jsonString(v));
    } else {
      buf.write(v);
    }
  }

  write(value, 0);
  return buf.toString();
}

String _jsonString(String s) {
  final b = StringBuffer('"');
  for (final code in s.codeUnits) {
    switch (code) {
      case 0x22:
        b.write(r'\"');
      case 0x5C:
        b.write(r'\\');
      case 0x0A:
        b.write(r'\n');
      case 0x0D:
        b.write(r'\r');
      case 0x09:
        b.write(r'\t');
      default:
        if (code < 0x20) {
          b.write('\\u${code.toRadixString(16).padLeft(4, '0')}');
        } else {
          b.writeCharCode(code);
        }
    }
  }
  b.write('"');
  return b.toString();
}
