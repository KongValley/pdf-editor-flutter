import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:collection/collection.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:path/path.dart' as p;
import 'package:pdfrx/pdfrx.dart';

import 'models/annotation_model.dart';
import 'services/native_bridge.dart';
import 'services/recent_and_log_service.dart';
import 'state/editor_controller.dart';
import 'ui/dialogs/batch_dialogs.dart';
import 'ui/dialogs/editor_dialogs.dart';
import 'ui/theme/app_theme.dart';
import 'ui/widgets/floating_tool_dock.dart';
import 'ui/widgets/modern_status_bar.dart';
import 'ui/widgets/modern_top_bar.dart';
import 'ui/widgets/pdf_workspace_view.dart';
import 'ui/widgets/right_inspector.dart';
import 'ui/widgets/search_floating_bar.dart';
import 'ui/widgets/thumbnails_sidebar.dart';
import 'ui/widgets/welcome_view.dart';
import 'utils/page_range.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  await pdfrxFlutterInitialize();
  final initialPdf = args.firstWhereOrNull(
    (a) => a.toLowerCase().endsWith('.pdf') && File(a).existsSync(),
  );
  runApp(PdfEditorApp(initialFilePath: initialPdf));
}

class PdfEditorApp extends StatefulWidget {
  const PdfEditorApp({super.key, this.initialFilePath});

  final String? initialFilePath;

  @override
  State<PdfEditorApp> createState() => _PdfEditorAppState();
}

class _PdfEditorAppState extends State<PdfEditorApp> {
  final EditorController _controller = EditorController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        return MaterialApp(
          title: 'PDF 编辑器',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(false),
          darkTheme: AppTheme.build(true),
          themeMode: _controller.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('en', 'US'),
          ],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: PdfEditorShell(
            controller: _controller,
            initialFilePath: widget.initialFilePath,
          ),
        );
      },
    );
  }
}

class PdfEditorShell extends StatefulWidget {
  const PdfEditorShell({
    super.key,
    required this.controller,
    this.initialFilePath,
  });

  final EditorController controller;
  final String? initialFilePath;

  @override
  State<PdfEditorShell> createState() => _PdfEditorShellState();
}

class _PdfEditorShellState extends State<PdfEditorShell> {
  final GlobalKey<PdfWorkspaceViewState> _workspaceKey = GlobalKey();
  bool _draggingFilesOver = false;
  late final AppLifecycleListener _lifecycleListener;
  Future<bool>? _pendingCloseDecision;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onGlobalKey);
    NativeBridge.setCloseRequestHandler(_handleClosePromptOnce);
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: () async {
        final allowExit = await _handleClosePromptOnce();
        if (allowExit) {
          await NativeBridge.setDirty(false);
          return AppExitResponse.exit;
        }
        return AppExitResponse.cancel;
      },
    );
    final initPath = widget.initialFilePath;
    if (initPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_openPath(initPath, skipDirtyConfirm: true));
        }
      });
    }
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    NativeBridge.setCloseRequestHandler(null);
    HardwareKeyboard.instance.removeHandler(_onGlobalKey);
    super.dispose();
  }

  Future<bool> _handleClosePromptOnce() {
    final inFlight = _pendingCloseDecision;
    if (inFlight != null) return inFlight;
    final op = _handleNativeCloseRequest().whenComplete(() {
      _pendingCloseDecision = null;
    });
    _pendingCloseDecision = op;
    return op;
  }

  Future<bool> _handleNativeCloseRequest() async {
    if (!mounted) {
      return true;
    }
    widget.controller.flushPendingInlineEdits();
    final ctrl = widget.controller;
    await AppDataService.log('info', 'lifecycle', '收到窗口关闭请求', {
      'dirty': ctrl.dirty,
    });
    if (!mounted) {
      return true;
    }
    if (!ctrl.dirty) {
      return true;
    }
    final choice = await showUnsavedChangesDialog(
      context,
      title: '退出确认',
      fileName: ctrl.displayFileName,
      message: '当前文档有未保存的修改，直接退出将丢失这些更改。是否在退出前保存？',
      saveLabel: '保存并退出',
      barrierDismissible: false,
    );
    if (choice == UnsavedChangesChoice.save) {
      return await _handleSave();
    }
    return choice == UnsavedChangesChoice.discard;
  }

  bool _isTextFieldFocused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _onGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final modalActive = !(ModalRoute.of(context)?.isCurrent ?? true);
    if (modalActive) return false;
    final ctrl = widget.controller;
    final key = event.logicalKey;
    final isCtrl = HardwareKeyboard.instance.isControlPressed;
    final isShift = HardwareKeyboard.instance.isShiftPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    if (key == LogicalKeyboardKey.f11) {
      unawaited(ctrl.toggleFullscreen());
      return true;
    }

    if (key == LogicalKeyboardKey.escape) {
      if (ctrl.editingTextId != null) return false;
      if (ctrl.searchOpen) {
        ctrl.toggleSearch();
        return true;
      }
      if (ctrl.selectedIds.isNotEmpty) {
        ctrl.selectAnnotation(null);
        return true;
      }
      if (ctrl.tool != EditorTool.select) {
        ctrl.setTool(EditorTool.select);
        return true;
      }
      return false;
    }

    if (isCtrl && key == LogicalKeyboardKey.keyO && !isAlt) {
      if (ctrl.isBusy) return true;
      unawaited(_handleOpenFile());
      return true;
    }
    if (isCtrl && key == LogicalKeyboardKey.keyS && !isAlt) {
      if (ctrl.isBusy) return true;
      ctrl.flushPendingInlineEdits();
      if (isShift) {
        unawaited(_handleSaveAs());
      } else {
        unawaited(_handleSave());
      }
      return true;
    }
    if (isCtrl && key == LogicalKeyboardKey.keyF && !isAlt && !isShift) {
      if (!ctrl.hasDocument) return false;
      ctrl.flushPendingInlineEdits();
      ctrl.openOrFocusSearch();
      return true;
    }

    if (_isTextFieldFocused()) return false;
    if (ctrl.isBusy) return false;

    if (isCtrl && !isAlt) {
      if (key == LogicalKeyboardKey.keyE) {
        unawaited(_handleExportPagesDialog());
        return true;
      }
      if (key == LogicalKeyboardKey.keyP) {
        unawaited(_handlePrintDialog());
        return true;
      }
      if (key == LogicalKeyboardKey.digit1) {
        ctrl.setViewMode(ReadingViewMode.continuous);
        return true;
      }
      if (key == LogicalKeyboardKey.digit2) {
        ctrl.setViewMode(ReadingViewMode.single);
        return true;
      }
      if (key == LogicalKeyboardKey.digit3) {
        ctrl.setViewMode(ReadingViewMode.twoPage);
        return true;
      }
      if (key == LogicalKeyboardKey.keyB) {
        if (isShift) {
          ctrl.toggleRightPanel();
        } else {
          ctrl.toggleThumbnails();
        }
        return true;
      }
      if (key == LogicalKeyboardKey.digit0 ||
          key == LogicalKeyboardKey.numpad0) {
        ctrl.setZoomPercent(100);
        return true;
      }
      if (key == LogicalKeyboardKey.equal ||
          key == LogicalKeyboardKey.numpadAdd) {
        ctrl.setZoomPercent((ctrl.scale * 100 + 15).clamp(25, 400));
        return true;
      }
      if (key == LogicalKeyboardKey.minus ||
          key == LogicalKeyboardKey.numpadSubtract) {
        ctrl.setZoomPercent((ctrl.scale * 100 - 15).clamp(25, 400));
        return true;
      }
      if (key == LogicalKeyboardKey.keyZ) {
        if (isShift) {
          unawaited(ctrl.redo());
        } else {
          unawaited(ctrl.undo());
        }
        return true;
      }
      if (key == LogicalKeyboardKey.keyY) {
        unawaited(ctrl.redo());
        return true;
      }
      if (key == LogicalKeyboardKey.keyC) {
        if (ctrl.selectedIds.isNotEmpty) {
          ctrl.copySelectedAnnotations();
        } else {
          unawaited(_workspaceKey.currentState?.copySelectedDocumentText());
        }
        return true;
      }
      if (key == LogicalKeyboardKey.keyV) {
        if (ctrl.hasDocument) ctrl.pasteAnnotations();
        return true;
      }
      if (key == LogicalKeyboardKey.keyD) {
        if (ctrl.selectedIds.isNotEmpty) ctrl.duplicateSelectedAnnotations();
        return true;
      }
      if (key == LogicalKeyboardKey.keyN && isShift) {
        if (ctrl.hasDocument && !ctrl.encrypted && !ctrl.isBusy) {
          unawaited(ctrl.insertBlankPageAfter(ctrl.currentPage - 1));
        }
        return true;
      }
      if (key == LogicalKeyboardKey.delete && isShift) {
        if (ctrl.hasDocument && !ctrl.encrypted && !ctrl.isBusy) {
          unawaited(_handleDeletePagesDialog());
        }
        return true;
      }
    }

    if (isAlt && !isCtrl) {
      if (key == LogicalKeyboardKey.arrowLeft) {
        ctrl.goBack();
        return true;
      }
      if (key == LogicalKeyboardKey.arrowRight) {
        ctrl.goForward();
        return true;
      }
    }

    if (!isCtrl && !isAlt) {
      if (key == LogicalKeyboardKey.f3) {
        if (isShift) {
          ctrl.prevSearchMatch();
        } else {
          ctrl.nextSearchMatch();
        }
        return true;
      }
      if (key == LogicalKeyboardKey.delete ||
          key == LogicalKeyboardKey.backspace) {
        if (ctrl.selectedIds.isNotEmpty) {
          ctrl.deleteSelectedAnnotations();
          return true;
        }
      }
      if (key == LogicalKeyboardKey.bracketLeft && ctrl.hasDocument) {
        unawaited(ctrl.rotateView(-90));
        return true;
      }
      if (key == LogicalKeyboardKey.bracketRight && ctrl.hasDocument) {
        unawaited(ctrl.rotateView(90));
        return true;
      }
      if (key == LogicalKeyboardKey.pageUp && ctrl.hasDocument) {
        ctrl.stepPage(-1);
        return true;
      }
      if (key == LogicalKeyboardKey.pageDown && ctrl.hasDocument) {
        ctrl.stepPage(1);
        return true;
      }
      if (key == LogicalKeyboardKey.arrowLeft && ctrl.hasDocument) {
        ctrl.stepPage(-1);
        return true;
      }
      if (key == LogicalKeyboardKey.arrowRight && ctrl.hasDocument) {
        ctrl.stepPage(1);
        return true;
      }
      if (key == LogicalKeyboardKey.home && ctrl.hasDocument) {
        ctrl.jumpToPage(1);
        return true;
      }
      if (key == LogicalKeyboardKey.end && ctrl.hasDocument) {
        ctrl.jumpToPage(ctrl.pageCount);
        return true;
      }
      if (ctrl.hasDocument && !isShift) {
        final mapped = switch (key) {
          LogicalKeyboardKey.keyV => EditorTool.select,
          LogicalKeyboardKey.keyH => EditorTool.highlight,
          LogicalKeyboardKey.keyR => EditorTool.rect,
          LogicalKeyboardKey.keyO => EditorTool.ellipse,
          LogicalKeyboardKey.keyP => EditorTool.ink,
          LogicalKeyboardKey.keyA => EditorTool.arrow,
          LogicalKeyboardKey.keyM => EditorTool.measure,
          LogicalKeyboardKey.keyT => EditorTool.text,
          LogicalKeyboardKey.keyN => EditorTool.note,
          LogicalKeyboardKey.keyS => EditorTool.stamp,
          LogicalKeyboardKey.keyI => EditorTool.image,
          _ => null,
        };
        if (mapped != null) {
          ctrl.setTool(mapped);
          return true;
        }
      }
    }
    return false;
  }

  String _defaultRangeText() {
    final ctrl = widget.controller;
    if (ctrl.selectedThumbPages.isNotEmpty) {
      return formatPageRange(ctrl.selectedThumbPages.toList());
    }
    return ctrl.currentPage.toString();
  }

  Future<bool> _confirmDiscardIfDirty() async {
    final ctrl = widget.controller;
    ctrl.flushPendingInlineEdits();
    if (!ctrl.dirty) return true;
    final choice = await showUnsavedChangesDialog(
      context,
      title: '未保存的更改',
      fileName: ctrl.displayFileName,
      message: '当前文档有未保存的批注或页面修改，直接在打开新文档前切换将丢失更改。是否保存？',
      saveLabel: '保存并继续',
    );
    if (choice == UnsavedChangesChoice.discard) return true;
    if (choice == UnsavedChangesChoice.save) return await _handleSave();
    return false;
  }

  Future<void> _openPath(
    String path, {
    bool skipDirtyConfirm = false,
  }) async {
    if (!skipDirtyConfirm && !await _confirmDiscardIfDirty()) return;
    if (!mounted) return;
    await widget.controller.openDocument(
      path,
      promptPassword: (wrongPw) => showPasswordPromptDialog(
        context,
        wrongPassword: wrongPw,
      ),
    );
  }

  Future<void> _handleOpenFile() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: '打开 PDF 文档',
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
    );
    final path = picked?.path;
    if (path != null) {
      await _openPath(path);
    }
  }

  Future<void> _handleImageToPdf({List<String> initialPaths = const []}) async {
    await showImageToPdfDialog(
      context,
      widget.controller,
      initialPaths: initialPaths,
    );
  }

  Future<void> _handleMergePdf({List<String> initialPaths = const []}) async {
    await showMergeDialog(
      context,
      widget.controller,
      initialPaths: initialPaths,
    );
  }

  Future<bool> _handleSave() async {
    final ctrl = widget.controller;
    if (!ctrl.hasDocument) return false;
    ctrl.flushPendingInlineEdits();
    return await ctrl.saveDocument();
  }

  Future<bool> _handleSaveAs() async {
    final ctrl = widget.controller;
    if (!ctrl.hasDocument) return false;
    ctrl.flushPendingInlineEdits();
    if (ctrl.encrypted) {
      ctrl.showToast('加密 PDF 无法重写入新文件，请选择支持解密的源文件', isError: true);
      return false;
    }
    final outPath = await NativeBridge.pickSaveFile(
      dialogTitle: '另存为 PDF',
      fileName: '${ctrl.fileStem}_edited.pdf',
      filterLabel: 'PDF 文档 (*.pdf)',
      ext: 'pdf',
    );
    if (outPath == null || outPath.trim().isEmpty) return false;
    return await ctrl.saveDocument(saveAsPath: outPath);
  }

  Future<void> _handleExportCurrentPng() async {
    final ctrl = widget.controller;
    if (!ctrl.hasDocument) return;
    final outPath = await NativeBridge.pickSaveFile(
      dialogTitle: '导出当前页为 PNG',
      fileName: '${ctrl.fileStem}_p${ctrl.currentPage}.png',
      filterLabel: 'PNG 图片 (*.png)',
      ext: 'png',
    );
    if (outPath == null || outPath.trim().isEmpty) return;
    await ctrl.exportCurrentPagePng(outPath);
  }

  Future<void> _handleExportPagesDialog() async {
    final ctrl = widget.controller;
    if (!ctrl.hasDocument) return;
    final res = await showPageRangeDialog(
      context,
      totalPages: ctrl.pageCount,
      title: '导出页面 / 图片',
      confirmLabel: '开始导出',
      initialRange: _defaultRangeText(),
      showIncludeAnnotations: true,
      showExportOptions: true,
    );
    if (res == null || res.pagesZeroBased.isEmpty) return;

    if (res.exportFormat == ExportFormatChoice.pdf) {
      final outPath = await NativeBridge.pickSaveFile(
        dialogTitle: '导出选定页为 PDF',
        fileName: '${ctrl.fileStem}_export.pdf',
        filterLabel: 'PDF 文档 (*.pdf)',
        ext: 'pdf',
      );
      if (outPath == null || outPath.trim().isEmpty) return;
      await ctrl.extractOrExportPdf(
        pagesZeroBased: res.pagesZeroBased,
        targetPath: outPath,
        includeAnnotations: res.includeAnnotations,
      );
      return;
    }

    if (res.exportFormat == ExportFormatChoice.pngEach) {
      final outDir = (await FilePicker.pickDirectory(
        dialogTitle: '选择 PNG 输出目录',
      ))
          ?.toFilePath(windows: Platform.isWindows);
      if (outDir == null || outDir.trim().isEmpty) return;
      await ctrl.exportImages(
        pagesZeroBased: res.pagesZeroBased,
        longMode: false,
        vertical: true,
        targetPathOrDir: outDir,
        includeAnnotations: res.includeAnnotations,
      );
      return;
    }

    final isVertical = res.exportFormat == ExportFormatChoice.pngLongV;
    final suffix = isVertical ? 'long_v' : 'long_h';
    final outPath = await NativeBridge.pickSaveFile(
      dialogTitle: '保存拼接长图 PNG',
      fileName: '${ctrl.fileStem}_$suffix.png',
      filterLabel: 'PNG 图片 (*.png)',
      ext: 'png',
    );
    if (outPath == null || outPath.trim().isEmpty) return;
    await ctrl.exportImages(
      pagesZeroBased: res.pagesZeroBased,
      longMode: true,
      vertical: isVertical,
      targetPathOrDir: outPath,
      includeAnnotations: res.includeAnnotations,
    );
  }

  Future<void> _handlePrintDialog() async {
    final ctrl = widget.controller;
    if (!ctrl.hasDocument) return;
    final res = await showPageRangeDialog(
      context,
      totalPages: ctrl.pageCount,
      title: '打印文档',
      confirmLabel: '打印',
      initialRange: '1-${ctrl.pageCount}',
      showIncludeAnnotations: true,
      showPrintOptions: true,
    );
    if (res == null || res.pagesZeroBased.isEmpty) return;
    await ctrl.printPages(
      pagesZeroBased: res.pagesZeroBased,
      quality: res.printQuality,
      includeAnnotations: res.includeAnnotations,
    );
  }

  Future<void> _handleDeletePagesDialog() async {
    final ctrl = widget.controller;
    if (!ctrl.hasDocument || ctrl.encrypted) return;
    final res = await showPageRangeDialog(
      context,
      totalPages: ctrl.pageCount,
      title: '删除页面',
      confirmLabel: '确认删除',
      initialRange: _defaultRangeText(),
    );
    if (res == null || res.pagesZeroBased.isEmpty) return;
    if (res.pagesZeroBased.length >= ctrl.pageCount) {
      ctrl.showToast('至少需保留 1 页', isError: true);
      return;
    }
    await ctrl.deletePages(res.pagesZeroBased);
  }

  Future<void> _handleExtractPagesDialog() async {
    final ctrl = widget.controller;
    if (!ctrl.hasDocument) return;
    final res = await showPageRangeDialog(
      context,
      totalPages: ctrl.pageCount,
      title: '提取页面另存为 PDF',
      confirmLabel: '提取',
      initialRange: _defaultRangeText(),
      showIncludeAnnotations: true,
    );
    if (res == null || res.pagesZeroBased.isEmpty) return;
    final outPath = await NativeBridge.pickSaveFile(
      dialogTitle: '保存提取的 PDF',
      fileName: '${ctrl.fileStem}_extracted.pdf',
      filterLabel: 'PDF 文档 (*.pdf)',
      ext: 'pdf',
    );
    if (outPath == null || outPath.trim().isEmpty) return;
    await ctrl.extractOrExportPdf(
      pagesZeroBased: res.pagesZeroBased,
      targetPath: outPath,
      includeAnnotations: res.includeAnnotations,
    );
  }

  Future<void> _showContextMenu({
    required int pageZeroBased,
    required Offset globalPos,
    String? annotId,
  }) async {
    final ctrl = widget.controller;
    if (!ctrl.hasDocument || pageZeroBased < 0 || pageZeroBased >= ctrl.pageCount) {
      return;
    }
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final annot = annotId == null
        ? null
        : ctrl.annotations.firstWhereOrNull((a) => a.id == annotId);
    final isMulti = ctrl.selectedIds.length > 1;

    final items = <PopupMenuEntry<String>>[
      if (annot != null) ...[
        if (annot.kind == AnnotationKind.text && !annot.locked)
          const PopupMenuItem(
            value: 'annot_edit_text',
            height: 36,
            child: Row(
              children: [
                Icon(Icons.edit_outlined, size: 16),
                SizedBox(width: 8),
                Text('编辑文字', style: TextStyle(fontSize: AppTypography.body)),
              ],
            ),
          ),
        const PopupMenuItem(
          value: 'annot_copy',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.copy_rounded, size: 16),
              SizedBox(width: 8),
              Text('复制批注', style: TextStyle(fontSize: AppTypography.body)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'annot_dup',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.control_point_duplicate_rounded, size: 16),
              SizedBox(width: 8),
              Text('创建副本', style: TextStyle(fontSize: AppTypography.body)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'annot_top',
          enabled: !isMulti && ctrl.selectedZOrderCapability().canUp,
          height: 36,
          child: const Row(
            children: [
              Icon(Icons.vertical_align_top_rounded, size: 16),
              SizedBox(width: 8),
              Text('置于顶层', style: TextStyle(fontSize: AppTypography.body)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'annot_bottom',
          enabled: !isMulti && ctrl.selectedZOrderCapability().canDown,
          height: 36,
          child: const Row(
            children: [
              Icon(Icons.vertical_align_bottom_rounded, size: 16),
              SizedBox(width: 8),
              Text('置于底层', style: TextStyle(fontSize: AppTypography.body)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'annot_lock',
          enabled: !isMulti,
          height: 36,
          child: Row(
            children: [
              Icon(
                annot.locked ? Icons.lock_open_rounded : Icons.lock_outline_rounded,
                size: 16,
              ),
              const SizedBox(width: 8),
              Text(
                annot.locked ? '解锁批注' : '锁定批注',
                style: const TextStyle(fontSize: AppTypography.body),
              ),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'annot_delete',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded, size: 16, color: Colors.redAccent),
              SizedBox(width: 8),
              Text(
                '删除批注',
                style: TextStyle(
                  fontSize: AppTypography.body,
                  color: Colors.redAccent,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
      ],
      PopupMenuItem(
        enabled: false,
        height: 32,
        child: Text(
          '第 ${pageZeroBased + 1} 页',
          style: const TextStyle(
            fontSize: AppTypography.body,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      PopupMenuItem(
        value: 'page_rot_cw',
        enabled: !ctrl.encrypted && !ctrl.isBusy,
        height: 36,
        child: const Row(
          children: [
            Icon(Icons.rotate_right_rounded, size: 16),
            SizedBox(width: 8),
            Text('顺时针旋转此页 90°',
                style: TextStyle(fontSize: AppTypography.body)),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'page_rot_ccw',
        enabled: !ctrl.encrypted && !ctrl.isBusy,
        height: 36,
        child: const Row(
          children: [
            Icon(Icons.rotate_left_rounded, size: 16),
            SizedBox(width: 8),
            Text('逆时针旋转此页 90°',
                style: TextStyle(fontSize: AppTypography.body)),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'page_insert_blank',
        enabled: !ctrl.encrypted && !ctrl.isBusy,
        height: 36,
        child: const Row(
          children: [
            Icon(Icons.note_add_outlined, size: 16),
            SizedBox(width: 8),
            Text('在此页后插入空白页',
                style: TextStyle(fontSize: AppTypography.body)),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'page_extract',
        enabled: !ctrl.isBusy,
        height: 36,
        child: const Row(
          children: [
            Icon(Icons.content_cut_rounded, size: 16),
            SizedBox(width: 8),
            Text('提取此页为 PDF',
                style: TextStyle(fontSize: AppTypography.body)),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'page_export_png',
        enabled: !ctrl.isBusy,
        height: 36,
        child: const Row(
          children: [
            Icon(Icons.image_outlined, size: 16),
            SizedBox(width: 8),
            Text('导出此页为 PNG',
                style: TextStyle(fontSize: AppTypography.body)),
          ],
        ),
      ),
      PopupMenuItem(
        value: 'page_delete',
        enabled: !ctrl.encrypted && !ctrl.isBusy && ctrl.pageCount > 1,
        height: 36,
        child: const Row(
          children: [
            Icon(Icons.delete_sweep_outlined, size: 16, color: Colors.redAccent),
            SizedBox(width: 8),
            Text(
              '删除此页',
              style: TextStyle(
                fontSize: AppTypography.body,
                color: Colors.redAccent,
              ),
            ),
          ],
        ),
      ),
    ];

    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPos.dx, globalPos.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: items,
    );
    if (selected == null || !mounted) return;

    switch (selected) {
      case 'annot_edit_text':
        if (annot != null) ctrl.startEditingText(annot.id);
        break;
      case 'annot_copy':
        ctrl.copySelectedAnnotations();
        break;
      case 'annot_dup':
        ctrl.duplicateSelectedAnnotations();
        break;
      case 'annot_top':
        if (ctrl.selectedIds.length == 1) ctrl.moveSelectedZOrder('top');
        break;
      case 'annot_bottom':
        if (ctrl.selectedIds.length == 1) ctrl.moveSelectedZOrder('bottom');
        break;
      case 'annot_lock':
        if (annot != null) {
          ctrl.patchAnnotation(annot.id, (c) => c.copyWith(locked: !c.locked));
        }
        break;
      case 'annot_delete':
        ctrl.deleteSelectedAnnotations();
        break;
      case 'page_rot_cw':
        await ctrl.rotatePages({pageZeroBased: 90});
        break;
      case 'page_rot_ccw':
        await ctrl.rotatePages({pageZeroBased: 270});
        break;
      case 'page_insert_blank':
        await ctrl.insertBlankPageAfter(pageZeroBased);
        break;
      case 'page_extract':
        final outPdf = await NativeBridge.pickSaveFile(
          dialogTitle: '提取第 ${pageZeroBased + 1} 页',
          fileName: '${ctrl.fileStem}_p${pageZeroBased + 1}.pdf',
          filterLabel: 'PDF 文档 (*.pdf)',
          ext: 'pdf',
        );
        if (outPdf != null && outPdf.trim().isNotEmpty) {
          await ctrl.extractOrExportPdf(
            pagesZeroBased: [pageZeroBased],
            targetPath: outPdf,
            includeAnnotations: true,
          );
        }
        break;
      case 'page_export_png':
        final outDir = (await FilePicker.pickDirectory(
          dialogTitle: '选择导出 PNG 的目录',
        ))
            ?.toFilePath(windows: Platform.isWindows);
        if (outDir != null && outDir.trim().isNotEmpty) {
          await ctrl.exportImages(
            pagesZeroBased: [pageZeroBased],
            longMode: false,
            vertical: true,
            targetPathOrDir: outDir,
            includeAnnotations: true,
          );
        }
        break;
      case 'page_delete':
        await ctrl.deletePages([pageZeroBased]);
        break;
    }
  }

  Future<void> _onFilesDropped(DropDoneDetails details) async {
    setState(() => _draggingFilesOver = false);
    if (widget.controller.isBusy || !(ModalRoute.of(context)?.isCurrent ?? true)) {
      return;
    }
    final paths = details.files.map((f) => f.path).where((s) => s.isNotEmpty).toList();
    if (paths.isEmpty) return;

    final pdfPaths = paths
        .where((s) => p.extension(s).toLowerCase() == '.pdf')
        .toList();
    if (pdfPaths.length >= 2) {
      await _handleMergePdf(initialPaths: pdfPaths);
      return;
    }
    if (pdfPaths.length == 1) {
      await _openPath(pdfPaths.first);
      return;
    }

    final imgPaths = paths.where((s) {
      final ext = p.extension(s).toLowerCase();
      return ext == '.png' || ext == '.jpg' || ext == '.jpeg';
    }).toList();
    if (imgPaths.isNotEmpty) {
      await _handleImageToPdf(initialPaths: imgPaths);
      return;
    }

    widget.controller.showToast('仅支持拖入 PDF 或 PNG/JPG 图片', isError: true);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final c = context.appColors;

    return DropTarget(
      enable: !ctrl.isBusy && (ModalRoute.of(context)?.isCurrent ?? true),
      onDragEntered: (_) => setState(() => _draggingFilesOver = true),
      onDragExited: (_) => setState(() => _draggingFilesOver = false),
      onDragDone: _onFilesDropped,
      child: Scaffold(
        backgroundColor: c.canvasBg,
        body: Stack(
          children: [
            Column(
              children: [
                ModernTopBar(
                  controller: ctrl,
                  onOpenFile: _handleOpenFile,
                  onMergePdf: () => _handleMergePdf(),
                  onImageToPdf: () => _handleImageToPdf(),
                  onSave: _handleSave,
                  onSaveAs: _handleSaveAs,
                  onExportCurrentPng: _handleExportCurrentPng,
                  onExportPagesDialog: _handleExportPagesDialog,
                  onPrintDialog: _handlePrintDialog,
                  onAbout: () => showAboutSelfCheckDialog(context, ctrl),
                ),
                Expanded(
                  child: ctrl.hasDocument
                      ? Row(
                          children: [
                            if (ctrl.showThumbnails)
                              ThumbnailsSidebar(
                                controller: ctrl,
                                onDeleteDialog: _handleDeletePagesDialog,
                                onExtractDialog: _handleExtractPagesDialog,
                                onSplitDialog: () =>
                                    showSplitDialog(context, ctrl),
                                onExportDialog: _handleExportPagesDialog,
                                onOrientationDialog: () =>
                                    showOrientationUnifyDialog(context, ctrl),
                                onPageNumberDialog: () =>
                                    showPageNumberDialog(context, ctrl),
                                onWatermarkDialog: () =>
                                    showWatermarkDialog(context, ctrl),
                                onMergeDialog: () => _handleMergePdf(),
                                onPageContextMenu: (pageZeroBased, pos) =>
                                    _showContextMenu(
                                  pageZeroBased: pageZeroBased,
                                  globalPos: pos,
                                ),
                              ),
                            Expanded(
                              child: Stack(
                                children: [
                                  Positioned.fill(
                                    child: PdfWorkspaceView(
                                      key: _workspaceKey,
                                      controller: ctrl,
                                      onContextMenu: (pIdx, pos, annotId) =>
                                          _showContextMenu(
                                        pageZeroBased: pIdx,
                                        globalPos: pos,
                                        annotId: annotId,
                                      ),
                                    ),
                                  ),
                                  // 居中顶部悬浮批注工具坞 + 右上角搜索条（纵向排布防止重叠）
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
                                          child: FloatingToolDock(
                                            controller: ctrl,
                                          ),
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
                        )
                      : WelcomeView(
                          controller: ctrl,
                          onOpenFile: _handleOpenFile,
                          onMergePdf: () => _handleMergePdf(),
                          onImageToPdf: () => _handleImageToPdf(),
                          onOpenPath: (path) => _openPath(path),
                        ),
                ),
                ModernStatusBar(
                  controller: ctrl,
                  onOpenProblems: () => showProblemsDialog(context, ctrl),
                ),
              ],
            ),

            // 加载 / 批处理状态提示气泡
            if (ctrl.isBusy || ctrl.loading)
              Positioned(
                top: 56,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: c.surfaceBg.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: c.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.14),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            ctrl.busyMessage ?? '正在加载文档...',
                            style: const TextStyle(fontSize: AppTypography.body),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // 底部 Toast 提示
            if (ctrl.toastMessage != null)
              Positioned(
                bottom: 44,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 460),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: ctrl.toastIsError
                            ? const Color(0xFFDC2626)
                            : (ctrl.isDarkMode
                                ? const Color(0xFF282F3D)
                                : const Color(0xFF1F2937)),
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 14,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Text(
                        ctrl.toastMessage!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: AppTypography.body,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // 外部文件拖拽高亮覆盖
            if (_draggingFilesOver)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: c.accent.withValues(alpha: 0.12),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: c.surfaceBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: c.accent, width: 2),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.file_download_outlined,
                              size: 28, color: c.accent),
                          const SizedBox(width: 12),
                          const Text(
                            '松开以打开/合并 PDF，或将 PNG/JPG 转为 PDF',
                            style: TextStyle(
                              fontSize: AppTypography.title,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
