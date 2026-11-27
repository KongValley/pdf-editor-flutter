import 'dart:async';
import 'dart:ffi' show nullptr;
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:pdfium_dart/pdfium_dart.dart' as pdfium;
import 'package:pdfrx/pdfrx.dart';
import 'package:uuid/uuid.dart';

import '../models/annotation_model.dart';
import '../models/document_models.dart';
import '../services/export_and_print_service.dart';
import '../services/image_to_pdf_service.dart';
import '../services/native_bridge.dart';
import '../services/orientation_service.dart';
import '../services/pdf_engine_service.dart';
import '../services/recent_and_log_service.dart';
import '../services/sidecar_service.dart';
import '../services/system_fonts_service.dart';
import '../ui/layout/workspace_breakpoints.dart';

enum ZoomIntent { fitWidth, fitPage, manual }

class DocumentTabItem {
  const DocumentTabItem({
    required this.path,
    required this.title,
    this.page = 1,
    this.pageCount = 0,
    this.encrypted = false,
  });

  final String path;
  final String title;
  final int page;
  final int pageCount;
  final bool encrypted;

  DocumentTabItem copyWith({
    String? title,
    int? page,
    int? pageCount,
    bool? encrypted,
  }) {
    return DocumentTabItem(
      path: path,
      title: title ?? this.title,
      page: page ?? this.page,
      pageCount: pageCount ?? this.pageCount,
      encrypted: encrypted ?? this.encrypted,
    );
  }
}

sealed class _UndoEntry {
  const _UndoEntry();
}

final class _AnnotUndoEntry extends _UndoEntry {
  const _AnnotUndoEntry(this.annotations);
  final List<PdfAnnotationItem> annotations;
}

final class _PageSnapshot extends _UndoEntry {
  const _PageSnapshot({
    required this.tempPdfPath,
    required this.pageCount,
    required this.pageSizes,
    required this.pageRotations,
    required this.viewRotationDeg,
    required this.annotations,
    required this.currentPage,
  });

  final String tempPdfPath;
  final int pageCount;
  final List<({double w, double h})> pageSizes;
  final List<int> pageRotations;
  final int viewRotationDeg;
  final List<PdfAnnotationItem> annotations;
  final int currentPage;
}

class EditorController extends ChangeNotifier {
  EditorController() {
    _init();
  }

  static const _uuid = Uuid();
  static const int _maxAnnotUndo = 100;
  static const int _maxPageUndo = 5;

  // -------------------------------------------------------------------------
  // 文档状态
  // -------------------------------------------------------------------------
  String? filePath; // 原始文档路径（用于保存、标题、recent 记录）
  String? activeRenderPath; // 当前实际渲染源（原路径或页面操作后的临时工作副本）
  String? password;
  bool encrypted = false;
  bool loading = false;
  String? loadError;

  /// 每当文档结构/文件变更需强制 PdfViewer 重载时自增
  int viewerRevision = 0;

  /// 页面操作后同步隐藏 PdfViewer 短暂释放句柄（覆盖原路径时用）
  bool suspendViewer = false;

  int pageCount = 0;
  List<({double w, double h})> pageSizes = [];
  List<int> pageRotations = [];
  PdfDocument? activePdfDoc;
  int currentPage = 1;
  double scale = 1.0;
  int viewRotationDeg = 0;
  ReadingViewMode viewMode = ReadingViewMode.continuous;
  bool dirty = false;

  // -------------------------------------------------------------------------
  // 工具、界面、面板
  // -------------------------------------------------------------------------
  EditorTool tool = EditorTool.select;
  StampPreset stampPreset = StampPreset.approved;
  String? defaultFontFamily;

  bool showThumbnails = true;
  bool showRightPanel = true;
  bool _dockedThumbnailsOpen = true;
  bool _dockedRightPanelOpen = true;
  bool _overlayThumbnailsOpen = false;
  bool _overlayRightPanelOpen = false;
  int rightPanelTab = 0; // 0: 属性, 1: 注释列表, 2: 大纲
  bool searchOpen = false;
  int searchFocusSeq = 0;
  bool autoCollapseDock = true;
  int dockExpandSeq = 0;
  bool isFullscreen = false;
  bool isDarkMode = false;
  ZoomIntent zoomIntent = ZoomIntent.fitWidth;
  bool _needsInitialAutoFit = false;

  String? busyMessage;
  String? toastMessage;
  bool toastIsError = false;
  Timer? _toastTimer;

  // -------------------------------------------------------------------------
  // 注释、选中、撤销栈、剪贴板、图片缓存
  // -------------------------------------------------------------------------
  List<PdfAnnotationItem> annotations = [];
  final Set<String> selectedIds = {};
  final List<_UndoEntry> _undoStack = [];
  final List<_UndoEntry> _redoStack = [];
  List<PdfAnnotationItem>? _batchStartSnapshot;
  List<PdfAnnotationItem> _clipboard = [];

  String? editingTextId;
  AnnotationKind? listKindFilter;
  bool listCurrentPageOnly = false;
  final Set<VoidCallback> _inlineCommitHooks = {};
  int? _pendingRestorePage;
  double? _pendingRestoreZoom;

  final Map<String, Uint8List> imageBytesCache = {};
  final Map<String, ui.Image> loadedImages = {};

  Directory? _workDir;

  // -------------------------------------------------------------------------
  // 缩略图多选、大纲、搜索、阅读历史、最近文件、问题面板、字体
  // -------------------------------------------------------------------------
  final Set<int> selectedThumbPages = {}; // 0-based
  List<PdfOutlineNode> outlineNodes = [];

  final List<int> _backHistory = [];
  final List<int> _forwardHistory = [];
  Timer? _historyDebounce;
  bool _navigatingHistory = false;

  List<RecentDocumentEntry> recentFiles = [];
  final List<DocumentTabItem> openTabs = [];
  List<SystemFontInfo> systemFonts = [];
  final List<ProblemEntry> problems = [];

  final PdfViewerController viewerController = PdfViewerController();
  late final PdfTextSearcher textSearcher =
      PdfTextSearcher(viewerController)..addListener(_onSearchChanged);

  String searchQuery = '';
  int searchMatchesCount = 0;
  int searchCurrentIndex = -1;

  // -------------------------------------------------------------------------
  // 计算属性
  // -------------------------------------------------------------------------
  bool get hasDocument => activeRenderPath != null && pageCount > 0;
  bool get isBusy => busyMessage != null;
  bool get canAnnotUndo => _undoStack.any((e) => e is _AnnotUndoEntry);
  bool get canAnnotRedo => _redoStack.any((e) => e is _AnnotUndoEntry);
  bool get canPageUndo => _undoStack.any((e) => e is _PageSnapshot);
  bool get canPageRedo => _redoStack.any((e) => e is _PageSnapshot);
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  bool get canGoBack => _backHistory.isNotEmpty;
  bool get canGoForward => _forwardHistory.isNotEmpty;

  PdfAnnotationItem? get singleSelectedAnnotation {
    if (selectedIds.length != 1) return null;
    final id = selectedIds.first;
    for (final a in annotations) {
      if (a.id == id) return a;
    }
    return null;
  }

  String get displayFileName =>
      filePath == null ? '' : p.basename(filePath!);

  String get fileStem =>
      filePath == null ? 'document' : p.basenameWithoutExtension(filePath!);

  bool _disposed = false;

  Future<void> _init() async {
    final loadedRecent = await AppDataService.listRecent();
    if (_disposed) return;
    if (recentFiles.isEmpty && loadedRecent.isNotEmpty) {
      recentFiles = loadedRecent;
      notifyListeners();
    }
    try {
      final fonts = await SystemFontsService.listFonts();
      if (_disposed) return;
      systemFonts = fonts;
      notifyListeners();
    } catch (_) {}
  }

  void _onSearchChanged() {
    searchMatchesCount = textSearcher.matches.length;
    searchCurrentIndex = textSearcher.currentIndex ?? -1;
    notifyListeners();
  }

  void toggleTheme() {
    isDarkMode = !isDarkMode;
    notifyListeners();
  }

  void _upsertOpenTab(DocumentTabItem tab) {
    final idx = openTabs.indexWhere(
      (t) => t.path.toLowerCase() == tab.path.toLowerCase(),
    );
    if (idx >= 0) {
      openTabs[idx] = tab;
    } else {
      openTabs.add(tab);
    }
  }

  /// 确保当前处于打开态的文档始终出现在顶部标签栏中（兼容测试直接赋值 filePath 的场景）
  List<DocumentTabItem> get effectiveTabs {
    final activePath = filePath;
    if (!hasDocument || activePath == null) {
      return List<DocumentTabItem>.unmodifiable(openTabs);
    }
    final exists = openTabs.any(
      (t) => t.path.toLowerCase() == activePath.toLowerCase(),
    );
    if (exists) {
      return openTabs.map((t) {
        if (t.path.toLowerCase() == activePath.toLowerCase()) {
          return t.copyWith(
            title: displayFileName,
            page: currentPage,
            pageCount: pageCount,
            encrypted: encrypted,
          );
        }
        return t;
      }).toList(growable: false);
    }
    return [
      ...openTabs,
      DocumentTabItem(
        path: activePath,
        title: displayFileName,
        page: currentPage,
        pageCount: pageCount,
        encrypted: encrypted,
      ),
    ];
  }

  bool isTabActive(String path) =>
      hasDocument &&
      filePath != null &&
      filePath!.toLowerCase() == path.toLowerCase();

  /// 从标签栏移除一个非激活标签（不会中断当前文档）
  void removeInactiveTab(String path) {
    if (isTabActive(path)) return;
    openTabs.removeWhere((t) => t.path.toLowerCase() == path.toLowerCase());
    notifyListeners();
  }

  /// 关闭当前激活文档并回到欢迎开始页（调用方需先完成未保存确认）
  Future<void> closeCurrentDocument({bool removeFromTabs = true}) async {
    flushPendingInlineEdits();
    final closingPath = filePath;
    if (removeFromTabs && closingPath != null) {
      openTabs.removeWhere(
        (t) => t.path.toLowerCase() == closingPath.toLowerCase(),
      );
    }
    await _cleanupWorkFiles();
    _undoStack.clear();
    _redoStack.clear();
    _batchStartSnapshot = null;
    selectedIds.clear();
    selectedThumbPages.clear();
    editingTextId = null;
    _backHistory.clear();
    _forwardHistory.clear();
    searchOpen = false;
    searchQuery = '';
    searchMatchesCount = 0;
    searchCurrentIndex = -1;
    textSearcher.resetTextSearch();
    _disposeLoadedImages();

    filePath = null;
    activeRenderPath = null;
    password = null;
    encrypted = false;
    pageCount = 0;
    pageSizes = [];
    pageRotations = [];
    activePdfDoc = null;
    currentPage = 1;
    viewRotationDeg = 0;
    outlineNodes = [];
    annotations = [];
    viewerRevision++;
    _setDirty(false);
    _syncWindowTitle();
    notifyListeners();
  }

  void showToast(String msg, {bool isError = false}) {
    _toastTimer?.cancel();
    toastMessage = msg;
    toastIsError = isError;
    notifyListeners();
    _toastTimer = Timer(const Duration(seconds: 3), () {
      toastMessage = null;
      notifyListeners();
    });
  }

  void addProblem(String source, String message, [String? detail]) {
    problems.insert(
      0,
      ProblemEntry(
        id: _uuid.v4(),
        timestamp: DateTime.now(),
        source: source,
        message: message,
        detail: detail,
      ),
    );
    if (problems.length > 20) {
      problems.removeRange(20, problems.length);
    }
    notifyListeners();
  }

  void clearProblems() {
    problems.clear();
    notifyListeners();
  }

  void _setDirty(bool value) {
    if (dirty == value) return;
    dirty = value;
    NativeBridge.setDirty(value);
    _syncWindowTitle();
    notifyListeners();
  }

  void _syncWindowTitle() {
    final name = displayFileName;
    final title = name.isEmpty
        ? 'PDF 编辑器'
        : '$name${dirty ? ' *' : ''} — PDF 编辑器';
    NativeBridge.setTitle(title);
  }

  Future<T?> runBusy<T>(String message, Future<T> Function() task) async {
    if (busyMessage != null) {
      showToast('正在执行「$busyMessage」，请稍候…', isError: true);
      return null;
    }
    busyMessage = message;
    notifyListeners();
    try {
      return await task();
    } finally {
      busyMessage = null;
      notifyListeners();
    }
  }

  Future<Directory> _ensureWorkDir() async {
    if (_workDir != null && _workDir!.existsSync()) return _workDir!;
    final dir = Directory(
      p.join(
        Directory.systemTemp.path,
        'pdf_editor_work_${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    dir.createSync(recursive: true);
    _workDir = dir;
    return dir;
  }

  int _workSeq = 0;

  void registerInlineCommitHook(VoidCallback cb) => _inlineCommitHooks.add(cb);

  void unregisterInlineCommitHook(VoidCallback cb) =>
      _inlineCommitHooks.remove(cb);

  void flushPendingInlineEdits() {
    for (final cb in List<VoidCallback>.from(_inlineCommitHooks)) {
      cb();
    }
  }

  void _scheduleViewerRestore({required int page, double? zoom}) {
    _pendingRestorePage = page;
    _pendingRestoreZoom = zoom;
    _tryApplyPendingRestore();
  }

  void onViewerReady() {
    final hadRestoreZoom = _pendingRestoreZoom != null;
    _tryApplyPendingRestore();
    if (_needsInitialAutoFit && !hadRestoreZoom) {
      _needsInitialAutoFit = false;
      applyAutoFitForViewport();
    }
  }

  /// 按当前视口和缩放意图执行自动适配；用户手动缩放后不再覆盖。
  void applyAutoFitForViewport({bool isInitial = true}) {
    if (!hasDocument || !viewerController.isReady) return;
    if (!isInitial && zoomIntent == ZoomIntent.manual) return;
    final viewW = viewerController.viewSize.width;
    if (viewW <= 0) return;
    if (isInitial) {
      if (viewW < 680) {
        fitPage(userAction: false);
      } else {
        fitWidth(maxAutoZoom: 1.4, userAction: false);
      }
      return;
    }
    if (zoomIntent == ZoomIntent.fitPage) {
      fitPage(userAction: false);
    } else if (zoomIntent == ZoomIntent.fitWidth) {
      fitWidth(maxAutoZoom: 1.4, userAction: false);
    }
  }

  void onWorkspaceViewportResized() {
    if (!hasDocument || !viewerController.isReady) return;
    if (zoomIntent == ZoomIntent.manual) return;
    applyAutoFitForViewport(isInitial: false);
  }

  String get unsavedSummary {
    final parts = <String>[];
    final annotOps = _undoStack.whereType<_AnnotUndoEntry>().length;
    final pageOps = _undoStack.whereType<_PageSnapshot>().length;
    if (annotOps > 0) {
      parts.add('$annotOps 次批注修改');
    }
    if (pageOps > 0) {
      parts.add('$pageOps 次页面结构修改');
    }
    if (parts.isEmpty && dirty) {
      parts.add('文档已修改');
    }
    return parts.join('、');
  }

  void _tryApplyPendingRestore() {
    if (!viewerController.isReady) return;
    final pTarget = _pendingRestorePage;
    final zTarget = _pendingRestoreZoom;
    _pendingRestorePage = null;
    _pendingRestoreZoom = null;
    if (pTarget != null) {
      viewerController.goToPage(
        pageNumber: pTarget.clamp(1, math.max(1, pageCount)),
      );
    }
    if (zTarget != null) {
      viewerController.setZoom(viewerController.centerPosition, zTarget);
      scale = zTarget;
    }
  }

  void _deleteTempIfUnused(String path) {
    if (path == activeRenderPath) return;
    final inUndo =
        _undoStack.whereType<_PageSnapshot>().any((s) => s.tempPdfPath == path);
    final inRedo =
        _redoStack.whereType<_PageSnapshot>().any((s) => s.tempPdfPath == path);
    if (inUndo || inRedo) return;
    final f = File(path);
    if (f.existsSync()) {
      unawaited(f.delete().catchError((_) => f));
    }
  }

  void _clearRedoStack() {
    final removed = List<_UndoEntry>.from(_redoStack);
    _redoStack.clear();
    for (final entry in removed) {
      if (entry is _PageSnapshot) {
        _deleteTempIfUnused(entry.tempPdfPath);
      }
    }
  }

  void _trimUndoStack() {
    while (_undoStack.length > _maxAnnotUndo) {
      final oldest = _undoStack.removeAt(0);
      if (oldest is _PageSnapshot) {
        _deleteTempIfUnused(oldest.tempPdfPath);
      }
    }
    var pageSnaps = _undoStack.whereType<_PageSnapshot>().length;
    while (pageSnaps > _maxPageUndo) {
      final idx = _undoStack.indexWhere((e) => e is _PageSnapshot);
      if (idx < 0) break;
      final removed = _undoStack.removeAt(idx) as _PageSnapshot;
      pageSnaps--;
      _deleteTempIfUnused(removed.tempPdfPath);
    }
  }

  Future<void> _cleanupWorkFiles() async {
    _undoStack.clear();
    _redoStack.clear();
    _batchStartSnapshot = null;
    _pendingRestorePage = null;
    _pendingRestoreZoom = null;
    final dir = _workDir;
    _workDir = null;
    if (dir != null && dir.existsSync()) {
      await dir.delete(recursive: true).catchError((_) => dir);
    }
  }

  // -------------------------------------------------------------------------
  // 打开 / 关闭 / 保存
  // -------------------------------------------------------------------------
  Future<bool> openDocument(
    String path, {
    String? docPassword,
    Future<String?> Function(bool wrongPassword)? promptPassword,
  }) async {
    if (isBusy) return false;
    loading = true;
    loadError = null;
    notifyListeners();

    String? attemptPw = docPassword;
    var wrongPw = false;

    try {
      while (true) {
        final inspect =
            await PdfEngineService.inspectDocument(path, password: attemptPw);
        if (inspect.passwordRequired) {
          if (promptPassword == null) {
            loading = false;
            notifyListeners();
            return false;
          }
          final entered = await promptPassword(wrongPw);
          if (entered == null) {
            loading = false;
            notifyListeners();
            return false;
          }
          attemptPw = entered;
          wrongPw = true;
          continue;
        }
        if (!inspect.ok) {
          loading = false;
          loadError = inspect.error ?? '打开文件失败';
          showToast(loadError!, isError: true);
          addProblem('打开文件', loadError!);
          notifyListeners();
          return false;
        }

        // 重置上一个文档状态
        flushPendingInlineEdits();
        await _cleanupWorkFiles();
        _undoStack.clear();
        _redoStack.clear();
        _batchStartSnapshot = null;
        selectedIds.clear();
        selectedThumbPages.clear();
        editingTextId = null;
        _backHistory.clear();
        _forwardHistory.clear();
        searchOpen = false;
        searchQuery = '';
        searchMatchesCount = 0;
        searchCurrentIndex = -1;
        textSearcher.resetTextSearch();
        _disposeLoadedImages();

        filePath = path;
        activeRenderPath = path;
        password = attemptPw;
        encrypted = attemptPw != null && attemptPw.isNotEmpty;
        pageCount = inspect.pageCount;
        pageSizes = inspect.pageSizes;
        pageRotations = inspect.pageRotations;
        viewRotationDeg = 0;
        currentPage = 1;
        outlineNodes = [];

        // 读取批注：加密文档优先加载已保存的 sidecar（即使已清空为 []），
        // 非加密文档优先使用 PDF 内部 /PdEditorData，并在后台展示剥离副本防止重影。
        final sidecar = await SidecarService.readSidecar(path);
        if (encrypted) {
          if (sidecar != null) {
            annotations = sidecar.annotations
                .where((a) => a.page >= 0 && a.page < pageCount)
                .toList();
          } else {
            annotations = inspect.annotations;
          }
        } else if (inspect.annotations.isNotEmpty) {
          annotations = inspect.annotations;
          final strippedPath = await _createWorkingTarget();
          final stripRes = await PdfEngineService.stripPdEditorAnnotations(
            sourcePath: path,
            targetPath: strippedPath,
            password: attemptPw,
          );
          if (stripRes.ok) {
            activeRenderPath = strippedPath;
          }
        } else if (sidecar != null && sidecar.annotations.isNotEmpty) {
          annotations = sidecar.annotations
              .where((a) => a.page >= 0 && a.page < pageCount)
              .toList();
        } else {
          annotations = [];
        }

        // 异步加载批注引用图片与自定义字体
        unawaited(_restoreAnnotationAssets(annotations));

        // 恢复上次阅读页
        final recent = await AppDataService.getRecentFor(path);
        final resumePage =
            (recent != null && recent.page > 1 && recent.page <= pageCount)
                ? recent.page
                : 1;
        currentPage = resumePage;
        zoomIntent = ZoomIntent.fitWidth;
        _needsInitialAutoFit = true;
        if (annotations.isNotEmpty) {
          rightPanelTab = 1;
        } else {
          rightPanelTab = 0;
        }

        viewerRevision++;
        _upsertOpenTab(
          DocumentTabItem(
            path: path,
            title: p.basename(path),
            page: resumePage,
            pageCount: pageCount,
            encrypted: encrypted,
          ),
        );
        _setDirty(false);
        loading = false;
        notifyListeners();

        await AppDataService.recordRecent(path, resumePage);
        recentFiles = await AppDataService.listRecent();
        await AppDataService.log('info', 'open', '打开文档', {
          'file': p.basename(path),
          'pages': pageCount,
          'encrypted': encrypted,
        });
        if (resumePage > 1) {
          showToast('已回到上次阅读位置（第 $resumePage 页）');
        }
        notifyListeners();
        return true;
      }
    } catch (e) {
      loading = false;
      loadError = '打开文档异常：$e';
      showToast(loadError!, isError: true);
      notifyListeners();
      return false;
    }
  }

  Future<void> _restoreAnnotationAssets(List<PdfAnnotationItem> items) async {
    for (final ann in items) {
      if (ann.kind == AnnotationKind.image && ann.refPath.isNotEmpty) {
        await ensureImageLoaded(ann.imgId, ann.refPath);
      }
      if ((ann.kind == AnnotationKind.text ||
              ann.kind == AnnotationKind.stamp) &&
          ann.fontFamily != null &&
          ann.fontFamily!.isNotEmpty) {
        final face = await SystemFontsService.findFont(ann.fontFamily);
        if (face != null) {
          await SystemFontsService.ensureFlutterFontLoaded(face);
        }
      }
    }
    notifyListeners();
  }

  Future<String?> ensureImageLoaded(String imgId, String refPath) async {
    if (loadedImages.containsKey(imgId)) return imgId;
    if (refPath.isEmpty || !File(refPath).existsSync()) return null;
    try {
      final bytes = await File(refPath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      imageBytesCache[imgId] = bytes;
      loadedImages[imgId] = frame.image;
      notifyListeners();
      return imgId;
    } catch (_) {
      return null;
    }
  }

  Future<({String imgId, int width, int height})?> importImageFile(
      String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final imgId = _uuid.v4();
      imageBytesCache[imgId] = bytes;
      loadedImages[imgId] = frame.image;
      codec.dispose();
      notifyListeners();
      return (
        imgId: imgId,
        width: frame.image.width,
        height: frame.image.height,
      );
    } catch (_) {
      return null;
    }
  }

  void _disposeLoadedImages() {
    for (final im in loadedImages.values) {
      im.dispose();
    }
    loadedImages.clear();
    imageBytesCache.clear();
  }

  Future<bool> saveDocument({String? saveAsPath}) async {
    if (!hasDocument || filePath == null) return false;
    flushPendingInlineEdits();
    final targetPath = saveAsPath ?? filePath!;
    final isOverwriteOriginal = saveAsPath == null &&
        p.normalize(targetPath).toLowerCase() ==
            p.normalize(filePath!).toLowerCase();

    final res = await runBusy('正在保存文档…', () async {
      if (encrypted && isOverwriteOriginal) {
        await SidecarService.writeSidecar(
          targetPath,
          annotations: annotations,
        );
        _setDirty(false);
        const msg = '加密文档未改写原文件，批注已保存至同名 .pdfanno.json';
        showToast(msg);
        addProblem('保存', msg);
        return true;
      }

      final src = activeRenderPath!;
      final tempDest = p.join(
        (await _ensureWorkDir()).path,
        'save_${DateTime.now().microsecondsSinceEpoch}_${_workSeq++}.pdf',
      );
      final writeRes = await PdfEngineService.saveWithAnnotations(
        sourcePath: src,
        targetPath: tempDest,
        annotations: annotations,
        password: password,
        resolvedImages: imageBytesCache,
      );
      if (!writeRes.ok) {
        final err = writeRes.error ?? '保存失败';
        showToast(err, isError: true);
        addProblem('保存', err);
        return false;
      }
      for (final w in writeRes.warnings) {
        addProblem('保存提示', w);
      }

      // 若 activeRenderPath 指向目标文件自身（从未进过工作副本），先准备洁净工作副本并卸载 Viewer 释放句柄
      final normTarget = p.normalize(targetPath).toLowerCase();
      final normActive = p.normalize(src).toLowerCase();
      final needsViewerSwap = normTarget == normActive;
      var newRenderPath = src;
      final keepPage = currentPage;
      final keepScale = scale;

      if (needsViewerSwap) {
        final cleanRender = await _createWorkingTarget();
        await File(src).copy(cleanRender);
        newRenderPath = cleanRender;
        suspendViewer = true;
        notifyListeners();
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }

      try {
        final targetFile = File(targetPath);
        if (!targetFile.parent.existsSync()) {
          targetFile.parent.createSync(recursive: true);
        }
        final tmpFile = File(tempDest);
        try {
          await tmpFile.rename(targetPath);
        } catch (_) {
          await tmpFile.copy(targetPath);
          await tmpFile.delete().catchError((_) => tmpFile);
        }
      } finally {
        if (File(tempDest).existsSync()) {
          await File(tempDest).delete().catchError((_) => File(tempDest));
        }
        if (needsViewerSwap) {
          suspendViewer = false;
        }
      }

      // 同步 sidecar（与原版保持一致：明文 PDF 中 annotations 置空数组）
      await SidecarService.writeSidecar(
        targetPath,
        annotations: const [],
      );

      filePath = targetPath;
      activeRenderPath = newRenderPath;
      await AppDataService.recordRecent(targetPath, keepPage);
      recentFiles = await AppDataService.listRecent();
      _setDirty(false);
      if (needsViewerSwap) {
        viewRotationDeg = 0;
        viewerRevision++;
        _scheduleViewerRestore(page: keepPage, zoom: keepScale);
      }
      notifyListeners();

      showToast('已保存：${p.basename(targetPath)}');
      await PdfEngineService.logSaved('保存文档', targetPath);
      return true;
    });
    return res ?? false;
  }

  // -------------------------------------------------------------------------
  // 工具 & 批注编辑 & 统一时间线撤销栈
  // -------------------------------------------------------------------------
  void setTool(EditorTool next) {
    if (tool == next) return;
    flushPendingInlineEdits();
    tool = next;
    editingTextId = null;
    notifyListeners();
  }

  void _pushAnnotUndoSnapshot([List<PdfAnnotationItem>? customBefore]) {
    _undoStack.add(
      _AnnotUndoEntry(
        List<PdfAnnotationItem>.unmodifiable(
          customBefore ?? List<PdfAnnotationItem>.from(annotations),
        ),
      ),
    );
    _trimUndoStack();
    _clearRedoStack();
  }

  void beginAnnotBatch() {
    _batchStartSnapshot ??= List<PdfAnnotationItem>.from(annotations);
  }

  void commitAnnotBatch() {
    final before = _batchStartSnapshot;
    _batchStartSnapshot = null;
    if (before != null) {
      _pushAnnotUndoSnapshot(before);
      _setDirty(true);
    }
  }

  void addAnnotation(
    PdfAnnotationItem ann, {
    bool selectAfter = true,
    bool recordHistory = true,
  }) {
    if (recordHistory) {
      _pushAnnotUndoSnapshot();
    }
    annotations = [...annotations, ann];
    if (selectAfter) {
      selectedIds
        ..clear()
        ..add(ann.id);
      rightPanelTab = 0;
      if (ann.kind == AnnotationKind.text) {
        editingTextId = ann.id;
      }
    }
    _setDirty(true);
    notifyListeners();
  }

  void patchAnnotation(
    String id,
    PdfAnnotationItem Function(PdfAnnotationItem cur) updater, {
    bool recordHistory = true,
  }) {
    final idx = annotations.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    if (recordHistory) _pushAnnotUndoSnapshot();
    final updated = updater(annotations[idx]);
    final next = [...annotations];
    next[idx] = updated;
    annotations = next;
    _setDirty(true);
    notifyListeners();
  }

  void commitAnnotationDrag(List<PdfAnnotationItem> updatedItems) {
    if (updatedItems.isEmpty) return;
    _pushAnnotUndoSnapshot();
    final byId = {for (final a in updatedItems) a.id: a};
    annotations = [
      for (final a in annotations) byId[a.id] ?? a,
    ];
    _setDirty(true);
    notifyListeners();
  }

  void selectAnnotation(String? id, {bool additive = false}) {
    if (id == null) {
      selectedIds.clear();
      editingTextId = null;
    } else if (additive) {
      if (!selectedIds.add(id)) selectedIds.remove(id);
    } else {
      selectedIds
        ..clear()
        ..add(id);
      rightPanelTab = 0;
    }
    notifyListeners();
  }

  void deleteSelectedAnnotations() {
    if (selectedIds.isEmpty) return;
    _pushAnnotUndoSnapshot();
    annotations = annotations
        .where((a) => !selectedIds.contains(a.id))
        .toList();
    selectedIds.clear();
    editingTextId = null;
    _setDirty(true);
    notifyListeners();
  }

  void discardNewEmptyAnnotation(String id) {
    final idx = annotations.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    annotations = annotations.where((a) => a.id != id).toList();
    selectedIds.remove(id);
    if (editingTextId == id) editingTextId = null;
    if (_undoStack.isNotEmpty && _undoStack.last is _AnnotUndoEntry) {
      final last = _undoStack.last as _AnnotUndoEntry;
      if (last.annotations.length == annotations.length &&
          last.annotations.every((a) => annotations.any((b) => b.id == a.id))) {
        _undoStack.removeLast();
      }
    }
    notifyListeners();
  }

  void deleteAnnotationById(String id) {
    _pushAnnotUndoSnapshot();
    annotations = annotations.where((a) => a.id != id).toList();
    selectedIds.remove(id);
    if (editingTextId == id) editingTextId = null;
    _setDirty(true);
    notifyListeners();
  }

  void moveSelectedZOrder(String direction) {
    if (selectedIds.length != 1) return;
    final id = selectedIds.first;
    final targetIdx = annotations.indexWhere((a) => a.id == id);
    if (targetIdx < 0) return;
    final page = annotations[targetIdx].page;
    final samePageIndices = <int>[];
    for (var i = 0; i < annotations.length; i++) {
      if (annotations[i].page == page) samePageIndices.add(i);
    }
    final posInPage = samePageIndices.indexOf(targetIdx);
    if (posInPage < 0) return;

    int? swapWith;
    switch (direction) {
      case 'bottom':
        if (posInPage > 0) swapWith = samePageIndices.first;
        break;
      case 'down':
        if (posInPage > 0) swapWith = samePageIndices[posInPage - 1];
        break;
      case 'up':
        if (posInPage < samePageIndices.length - 1) {
          swapWith = samePageIndices[posInPage + 1];
        }
        break;
      case 'top':
        if (posInPage < samePageIndices.length - 1) {
          swapWith = samePageIndices.last;
        }
        break;
    }
    if (swapWith == null) return;
    _pushAnnotUndoSnapshot();
    final next = [...annotations];
    final item = next.removeAt(targetIdx);
    next.insert(swapWith, item);
    annotations = next;
    _setDirty(true);
    notifyListeners();
  }

  ({bool canDown, bool canUp}) selectedZOrderCapability() {
    final sel = singleSelectedAnnotation;
    if (sel == null) return (canDown: false, canUp: false);
    final samePage = annotations.where((a) => a.page == sel.page).toList();
    final pos = samePage.indexWhere((a) => a.id == sel.id);
    return (
      canDown: pos > 0,
      canUp: pos >= 0 && pos < samePage.length - 1,
    );
  }

  void copySelectedAnnotations() {
    if (selectedIds.isEmpty) return;
    _clipboard = annotations
        .where((a) => selectedIds.contains(a.id))
        .map((a) => a)
        .toList();
    showToast('已复制 ${_clipboard.length} 条批注');
  }

  void pasteAnnotations() {
    if (!hasDocument || _clipboard.isEmpty) return;
    final targetPage = (currentPage - 1).clamp(0, pageCount - 1);
    _pushAnnotUndoSnapshot();
    final pasted = <PdfAnnotationItem>[];
    for (final src in _clipboard) {
      pasted.add(
        src.translate(12, -12).copyWith(
              id: _uuid.v4(),
              page: targetPage,
              createdAt: DateTime.now().millisecondsSinceEpoch,
              locked: false,
            ),
      );
    }
    annotations = [...annotations, ...pasted];
    selectedIds
      ..clear()
      ..addAll(pasted.map((a) => a.id));
    _setDirty(true);
    notifyListeners();
  }

  void duplicateSelectedAnnotations() {
    if (!hasDocument || selectedIds.isEmpty) return;
    final sources =
        annotations.where((a) => selectedIds.contains(a.id)).toList();
    if (sources.isEmpty) return;
    _pushAnnotUndoSnapshot();
    final clones = sources
        .map(
          (src) => src.translate(12, -12).copyWith(
                id: _uuid.v4(),
                createdAt: DateTime.now().millisecondsSinceEpoch,
                locked: false,
              ),
        )
        .toList();
    annotations = [...annotations, ...clones];
    selectedIds
      ..clear()
      ..addAll(clones.map((a) => a.id));
    _setDirty(true);
    notifyListeners();
  }

  // -------------------------------------------------------------------------
  // 统一时间线撤销 / 重做（按操作先后精确恢复注释或页面结构）
  // -------------------------------------------------------------------------
  Future<void> undo() async {
    flushPendingInlineEdits();
    _batchStartSnapshot = null;
    if (_undoStack.isEmpty) return;
    final top = _undoStack.last;
    if (top is _AnnotUndoEntry) {
      _undoStack.removeLast();
      _redoStack.add(
        _AnnotUndoEntry(
          List<PdfAnnotationItem>.unmodifiable(
            List<PdfAnnotationItem>.from(annotations),
          ),
        ),
      );
      annotations = List<PdfAnnotationItem>.from(top.annotations);
      selectedIds.clear();
      editingTextId = null;
      _setDirty(true);
      notifyListeners();
      return;
    }
    if (top is _PageSnapshot) {
      await _undoPageOp();
    }
  }

  Future<void> redo() async {
    flushPendingInlineEdits();
    _batchStartSnapshot = null;
    if (_redoStack.isEmpty) return;
    final top = _redoStack.last;
    if (top is _AnnotUndoEntry) {
      _redoStack.removeLast();
      _undoStack.add(
        _AnnotUndoEntry(
          List<PdfAnnotationItem>.unmodifiable(
            List<PdfAnnotationItem>.from(annotations),
          ),
        ),
      );
      annotations = List<PdfAnnotationItem>.from(top.annotations);
      selectedIds.clear();
      editingTextId = null;
      _setDirty(true);
      notifyListeners();
      return;
    }
    if (top is _PageSnapshot) {
      await _redoPageOp();
    }
  }

  Future<String> _createWorkingTarget() async {
    final dir = await _ensureWorkDir();
    return p.join(
      dir.path,
      'work_${DateTime.now().microsecondsSinceEpoch}_${_workSeq++}.pdf',
    );
  }

  Future<void> _pushPageUndoSnapshot() async {
    if (activeRenderPath == null) return;
    final snapPath = await _createWorkingTarget();
    await File(activeRenderPath!).copy(snapPath);
    _undoStack.add(_PageSnapshot(
      tempPdfPath: snapPath,
      pageCount: pageCount,
      pageSizes: List.of(pageSizes),
      pageRotations: List.of(pageRotations),
      viewRotationDeg: viewRotationDeg,
      annotations: List.of(annotations),
      currentPage: currentPage,
    ));
    _trimUndoStack();
    _clearRedoStack();
  }

  void _discardLastFailedPageUndo() {
    if (_undoStack.isEmpty || _undoStack.last is! _PageSnapshot) return;
    final failed = _undoStack.removeLast() as _PageSnapshot;
    _deleteTempIfUnused(failed.tempPdfPath);
  }

  Future<void> _restoreSnapshot(_PageSnapshot snap) async {
    final inspect = await PdfEngineService.inspectDocument(
      snap.tempPdfPath,
      password: password,
    );
    final keepScale = scale;
    activeRenderPath = snap.tempPdfPath;
    pageCount = inspect.ok ? inspect.pageCount : snap.pageCount;
    pageSizes = inspect.ok ? inspect.pageSizes : snap.pageSizes;
    pageRotations = inspect.ok ? inspect.pageRotations : List.of(snap.pageRotations);
    viewRotationDeg = 0;
    annotations = List.of(snap.annotations);
    currentPage = snap.currentPage.clamp(1, math.max(1, pageCount));
    selectedThumbPages.clear();
    selectedIds.clear();
    editingTextId = null;
    _batchStartSnapshot = null;
    viewerRevision++;
    _setDirty(true);
    _scheduleViewerRestore(page: currentPage, zoom: keepScale);
    notifyListeners();
  }

  Future<void> _undoPageOp() async {
    if (_undoStack.isEmpty ||
        _undoStack.last is! _PageSnapshot ||
        activeRenderPath == null) {
      return;
    }
    await runBusy('正在撤销页面操作…', () async {
      final redoSnapPath = await _createWorkingTarget();
      await File(activeRenderPath!).copy(redoSnapPath);
      _redoStack.add(_PageSnapshot(
        tempPdfPath: redoSnapPath,
        pageCount: pageCount,
        pageSizes: List.of(pageSizes),
        pageRotations: List.of(pageRotations),
        viewRotationDeg: viewRotationDeg,
        annotations: List.of(annotations),
        currentPage: currentPage,
      ));
      final prev = _undoStack.removeLast() as _PageSnapshot;
      await _restoreSnapshot(prev);
      showToast('已撤销页面操作');
    });
  }

  Future<void> _redoPageOp() async {
    if (_redoStack.isEmpty ||
        _redoStack.last is! _PageSnapshot ||
        activeRenderPath == null) {
      return;
    }
    await runBusy('正在重做页面操作…', () async {
      final undoSnapPath = await _createWorkingTarget();
      await File(activeRenderPath!).copy(undoSnapPath);
      _undoStack.add(_PageSnapshot(
        tempPdfPath: undoSnapPath,
        pageCount: pageCount,
        pageSizes: List.of(pageSizes),
        pageRotations: List.of(pageRotations),
        viewRotationDeg: viewRotationDeg,
        annotations: List.of(annotations),
        currentPage: currentPage,
      ));
      _trimUndoStack();
      final next = _redoStack.removeLast() as _PageSnapshot;
      await _restoreSnapshot(next);
      showToast('已重做页面操作');
    });
  }

  // -------------------------------------------------------------------------
  // 页面操作（删除、旋转、插入空白页、移动排序、页码、水印、合并、提取、拆分、统一方向）
  // -------------------------------------------------------------------------
  Future<void> deletePages(List<int> pagesZeroBased) async {
    if (!hasDocument || encrypted) {
      if (encrypted) showToast('加密文档不支持页面结构操作', isError: true);
      return;
    }
    flushPendingInlineEdits();
    final valid = pagesZeroBased.where((i) => i >= 0 && i < pageCount).toSet().toList()
      ..sort();
    if (valid.isEmpty) return;
    if (valid.length >= pageCount) {
      showToast('不能删除全部页面', isError: true);
      return;
    }

    await runBusy('正在删除页面…', () async {
      await _pushPageUndoSnapshot();
      final nextPath = await _createWorkingTarget();
      final res = await PdfEngineService.deletePages(
        sourcePath: activeRenderPath!,
        targetPath: nextPath,
        pagesZeroBased: valid,
        password: password,
      );
      if (!res.ok) {
        _discardLastFailedPageUndo();
        showToast(res.error ?? '删除页面失败', isError: true);
        return;
      }

      // 构建 pageMap 迁移批注页码
      final removedSet = valid.toSet();
      final pageMap = <int, int>{};
      var nextIdx = 0;
      for (var i = 0; i < pageCount; i++) {
        if (!removedSet.contains(i)) {
          pageMap[i] = nextIdx++;
        }
      }
      annotations = [
        for (final a in annotations)
          if (pageMap.containsKey(a.page)) a.copyWith(page: pageMap[a.page]!),
      ];

      final keepScale = scale;
      final inspect =
          await PdfEngineService.inspectDocument(nextPath, password: password);
      activeRenderPath = nextPath;
      pageCount = inspect.ok ? inspect.pageCount : res.pageCount;
      pageSizes = inspect.ok ? inspect.pageSizes : pageSizes;
      if (inspect.ok) pageRotations = inspect.pageRotations;
      viewRotationDeg = 0;
      currentPage = currentPage.clamp(1, pageCount);
      selectedThumbPages.clear();
      selectedIds.clear();
      editingTextId = null;
      viewerRevision++;
      _setDirty(true);
      _scheduleViewerRestore(page: currentPage, zoom: keepScale);
      notifyListeners();
      showToast('已删除 ${valid.length} 页（可按 Ctrl+Z 撤销）');
    });
  }

  Future<void> rotatePages(Map<int, int> deltasByPage) async {
    if (!hasDocument || encrypted) {
      if (encrypted) showToast('加密文档不支持旋转页面保存', isError: true);
      return;
    }
    flushPendingInlineEdits();
    final activeDeltas = <int, int>{};
    for (final e in deltasByPage.entries) {
      if (e.key >= 0 && e.key < pageCount && (e.value % 360) != 0) {
        activeDeltas[e.key] = e.value;
      }
    }
    if (activeDeltas.isEmpty) return;

    await runBusy('正在旋转页面…', () async {
      await _pushPageUndoSnapshot();
      final nextPath = await _createWorkingTarget();
      final res = await PdfEngineService.rotatePages(
        sourcePath: activeRenderPath!,
        targetPath: nextPath,
        deltasByPage: activeDeltas,
        password: password,
      );
      if (!res.ok) {
        _discardLastFailedPageUndo();
        showToast(res.error ?? '旋转页面失败', isError: true);
        return;
      }
      final inspect =
          await PdfEngineService.inspectDocument(nextPath, password: password);
      final keepPage = currentPage;
      final keepScale = scale;
      activeRenderPath = nextPath;
      if (inspect.ok) {
        pageSizes = inspect.pageSizes;
        pageRotations = inspect.pageRotations;
        pageCount = inspect.pageCount;
      }
      viewRotationDeg = 0;
      viewerRevision++;
      _setDirty(true);
      _scheduleViewerRestore(page: keepPage, zoom: keepScale);
      notifyListeners();
      showToast('已旋转 ${activeDeltas.length} 页（可按 Ctrl+Z 撤销）');
    });
  }

  Future<void> insertBlankPageAfter(int afterIndexZeroBased) async {
    if (!hasDocument || encrypted) {
      if (encrypted) showToast('加密文档不支持插入空白页', isError: true);
      return;
    }
    flushPendingInlineEdits();
    await runBusy('正在插入空白页…', () async {
      await _pushPageUndoSnapshot();
      final nextPath = await _createWorkingTarget();
      final res = await PdfEngineService.insertBlankPage(
        sourcePath: activeRenderPath!,
        targetPath: nextPath,
        afterIndex: afterIndexZeroBased,
        password: password,
      );
      if (!res.ok) {
        _discardLastFailedPageUndo();
        showToast(res.error ?? '插入空白页失败', isError: true);
        return;
      }
      final insertAt = (afterIndexZeroBased + 1).clamp(0, pageCount);
      annotations = [
        for (final a in annotations)
          a.page >= insertAt ? a.copyWith(page: a.page + 1) : a,
      ];
      final keepScale = scale;
      final inspect =
          await PdfEngineService.inspectDocument(nextPath, password: password);
      activeRenderPath = nextPath;
      pageCount = inspect.ok ? inspect.pageCount : res.pageCount;
      pageSizes = inspect.ok ? inspect.pageSizes : pageSizes;
      if (inspect.ok) pageRotations = inspect.pageRotations;
      viewRotationDeg = 0;
      currentPage = insertAt + 1;
      selectedThumbPages.clear();
      selectedIds.clear();
      editingTextId = null;
      viewerRevision++;
      _setDirty(true);
      _scheduleViewerRestore(page: currentPage, zoom: keepScale);
      notifyListeners();
      showToast('已在第 ${insertAt + 1} 页插入空白页（可按 Ctrl+Z 撤销）');
    });
  }

  Future<void> movePage(int fromIndex, int toIndex) async {
    if (!hasDocument || encrypted) return;
    if (fromIndex == toIndex ||
        fromIndex < 0 ||
        fromIndex >= pageCount ||
        toIndex < 0 ||
        toIndex >= pageCount) {
      return;
    }
    flushPendingInlineEdits();
    await runBusy('正在移动页面…', () async {
      await _pushPageUndoSnapshot();
      final nextPath = await _createWorkingTarget();
      final res = await PdfEngineService.movePage(
        sourcePath: activeRenderPath!,
        targetPath: nextPath,
        fromIndex: fromIndex,
        toIndex: toIndex,
        password: password,
      );
      if (!res.ok) {
        _discardLastFailedPageUndo();
        showToast(res.error ?? '移动页面失败', isError: true);
        return;
      }

      // 构建移动后映射
      final order = List<int>.generate(pageCount, (i) => i);
      final moved = order.removeAt(fromIndex);
      order.insert(toIndex, moved);
      final oldToNew = <int, int>{};
      for (var newIdx = 0; newIdx < order.length; newIdx++) {
        oldToNew[order[newIdx]] = newIdx;
      }
      annotations = [
        for (final a in annotations)
          a.copyWith(page: oldToNew[a.page] ?? a.page),
      ];

      final keepScale = scale;
      final inspect =
          await PdfEngineService.inspectDocument(nextPath, password: password);
      activeRenderPath = nextPath;
      if (inspect.ok) {
        pageSizes = inspect.pageSizes;
        pageRotations = inspect.pageRotations;
        pageCount = inspect.pageCount;
      }
      viewRotationDeg = 0;
      currentPage = toIndex + 1;
      selectedThumbPages.clear();
      selectedIds.clear();
      editingTextId = null;
      viewerRevision++;
      _setDirty(true);
      _scheduleViewerRestore(page: currentPage, zoom: keepScale);
      notifyListeners();
      showToast('已将第 ${fromIndex + 1} 页移至第 ${toIndex + 1} 页（可按 Ctrl+Z 撤销）');
    });
  }

  Future<bool> applyPageNumbers({
    required List<int> pagesZeroBased,
    required PageNumberFormat format,
    required int startNumber,
    required PageNumberPosition position,
    required double fontSize,
    required double marginPt,
  }) async {
    if (!hasDocument || encrypted) return false;
    flushPendingInlineEdits();
    final ok = await runBusy('正在添加页码…', () async {
      await _pushPageUndoSnapshot();
      final nextPath = await _createWorkingTarget();
      final res = await PdfEngineService.applyPageNumbers(
        sourcePath: activeRenderPath!,
        targetPath: nextPath,
        pagesZeroBased: pagesZeroBased,
        format: format,
        startNumber: startNumber,
        position: position,
        fontSize: fontSize,
        marginPt: marginPt,
        password: password,
      );
      if (!res.ok) {
        _discardLastFailedPageUndo();
        showToast(res.error ?? '添加页码失败', isError: true);
        return false;
      }
      final keepPage = currentPage;
      final keepScale = scale;
      activeRenderPath = nextPath;
      viewRotationDeg = 0;
      viewerRevision++;
      _setDirty(true);
      _scheduleViewerRestore(page: keepPage, zoom: keepScale);
      notifyListeners();
      showToast('已添加页码（可按 Ctrl+Z 撤销）');
      return true;
    });
    return ok ?? false;
  }

  Future<bool> applyWatermark({
    required List<int> pagesZeroBased,
    required String text,
    required double fontSize,
    required double opacity,
    required double rotationDeg,
    required bool tile,
    required String colorHex,
  }) async {
    if (!hasDocument || encrypted) return false;
    flushPendingInlineEdits();
    final ok = await runBusy('正在添加水印…', () async {
      await _pushPageUndoSnapshot();
      final nextPath = await _createWorkingTarget();
      final res = await PdfEngineService.applyWatermark(
        sourcePath: activeRenderPath!,
        targetPath: nextPath,
        pagesZeroBased: pagesZeroBased,
        text: text,
        fontSize: fontSize,
        opacity: opacity,
        rotationDeg: rotationDeg,
        tile: tile,
        colorHex: colorHex,
        password: password,
      );
      if (!res.ok) {
        _discardLastFailedPageUndo();
        showToast(res.error ?? '添加水印失败', isError: true);
        return false;
      }
      final keepPage = currentPage;
      final keepScale = scale;
      activeRenderPath = nextPath;
      viewRotationDeg = 0;
      viewerRevision++;
      _setDirty(true);
      _scheduleViewerRestore(page: keepPage, zoom: keepScale);
      notifyListeners();
      showToast('已添加水印（可按 Ctrl+Z 撤销）');
      return true;
    });
    return ok ?? false;
  }

  Future<bool> mergeDocuments({
    required List<({String path, List<int>? pages, String? password, bool isCurrent})>
        entries,
    required String targetPath,
    required bool openFolderAfter,
  }) async {
    if (entries.length < 2) return false;
    final ok = await runBusy('正在合并 PDF…', () async {
      final specs = <({String path, List<int>? pages, String? password})>[];
      String? preparedCurrent;
      try {
        for (final e in entries) {
          if (e.isCurrent && hasDocument) {
            if (annotations.isNotEmpty) {
              preparedCurrent = await _createWorkingTarget();
              final saveRes = await PdfEngineService.saveWithAnnotations(
                sourcePath: activeRenderPath!,
                targetPath: preparedCurrent,
                annotations: annotations,
                password: password,
                resolvedImages: imageBytesCache,
              );
              specs.add((
                path: saveRes.ok ? preparedCurrent : activeRenderPath!,
                pages: e.pages,
                password: password,
              ));
            } else {
              specs.add((
                path: activeRenderPath!,
                pages: e.pages,
                password: password,
              ));
            }
          } else {
            specs.add((path: e.path, pages: e.pages, password: e.password));
          }
        }
        final res = await PdfEngineService.mergePdfs(
          specs: specs,
          targetPath: targetPath,
        );
        if (!res.ok) {
          addProblem('合并', res.error ?? '合并失败');
          showToast(res.error ?? '合并失败', isError: true);
          return false;
        }
        await PdfEngineService.logSaved('merge', targetPath);
        if (openFolderAfter) {
          await NativeBridge.openFolder(targetPath, select: true);
        }
        return true;
      } finally {
        if (preparedCurrent != null) {
          await File(preparedCurrent)
              .delete()
              .catchError((_) => File(preparedCurrent!));
        }
      }
    });
    if (ok == true) {
      await openDocument(targetPath);
      showToast('合并完成：${p.basename(targetPath)}');
    }
    return ok ?? false;
  }

  Future<bool> extractOrExportPdf({
    required String targetPath,
    required List<int> pagesZeroBased,
    required bool includeAnnotations,
  }) async {
    if (!hasDocument) return false;
    final ok = await runBusy('正在导出 PDF…', () async {
      final res = await PdfEngineService.exportPdfPages(
        sourcePath: activeRenderPath!,
        targetPath: targetPath,
        pagesZeroBased: pagesZeroBased,
        includeAnnotations: includeAnnotations,
        annotations: annotations,
        password: password,
        resolvedImages: imageBytesCache,
      );
      if (!res.ok) {
        showToast(res.error ?? '导出失败', isError: true);
        addProblem('导出 PDF', res.error ?? '导出失败');
        return false;
      }
      showToast('已导出：${p.basename(targetPath)}');
      return true;
    });
    return ok ?? false;
  }

  Future<void> exportCurrentPagePng(String targetPath) async {
    if (!hasDocument) return;
    await runBusy('正在导出当前页图片…', () async {
      final pi = (currentPage - 1).clamp(0, pageCount - 1);
      final sz = pageSizes[pi];
      final pageRot = pi < pageRotations.length ? pageRotations[pi] : 0;
      final pageAnnots = annotations.where((a) => a.page == pi).toList();
      final res = await ExportAndPrintService.renderPagePng(
        filePath: activeRenderPath!,
        pageIndex: pi,
        scale: 2.0,
        viewRotationDeg: viewRotationDeg,
        pageRotationDeg: pageRot,
        pageDisplayWidthPt: sz.w,
        pageDisplayHeightPt: sz.h,
        includeAnnotations: true,
        pageAnnotations: pageAnnots,
        loadedImages: loadedImages,
        password: password,
      );
      if (res == null) {
        showToast('渲染页面失败', isError: true);
        return;
      }
      await AppDataService.atomicWriteBytes(targetPath, res.pngBytes);
      showToast('已导出图片：${p.basename(targetPath)}');
    });
  }

  Future<void> exportImages({
    required List<int> pagesZeroBased,
    required bool longMode,
    required bool vertical,
    required bool includeAnnotations,
    required String targetPathOrDir,
  }) async {
    if (!hasDocument) return;
    await runBusy(
      longMode ? '正在拼接长图…' : '正在导出 ${pagesZeroBased.length} 张图片…',
      () async {
        final ExportImagesResult res;
        if (longMode) {
          res = await ExportAndPrintService.exportLongPng(
            filePath: activeRenderPath!,
            targetPath: targetPathOrDir,
            pagesZeroBased: pagesZeroBased,
            pageSizes: pageSizes,
            pageRotations: pageRotations,
            viewRotationDeg: viewRotationDeg,
            vertical: vertical,
            includeAnnotations: includeAnnotations,
            allAnnotations: annotations,
            loadedImages: loadedImages,
            password: password,
          );
          if (res.ok) {
            if (res.downscalePercent != null) {
              showToast(
                '页数较多，长图已自动降到 ${res.downscalePercent}% 分辨率并导出',
              );
            } else {
              showToast('已导出长图：${p.basename(targetPathOrDir)}');
            }
          }
        } else {
          res = await ExportAndPrintService.exportEachPng(
            filePath: activeRenderPath!,
            targetDir: targetPathOrDir,
            stem: fileStem,
            pagesZeroBased: pagesZeroBased,
            pageSizes: pageSizes,
            pageRotations: pageRotations,
            viewRotationDeg: viewRotationDeg,
            includeAnnotations: includeAnnotations,
            allAnnotations: annotations,
            loadedImages: loadedImages,
            password: password,
          );
          if (res.ok) {
            showToast('已导出 ${res.savedPaths.length} 张 PNG 到 $targetPathOrDir');
          }
        }
        if (!res.ok) {
          showToast(res.error ?? '导出图片失败', isError: true);
          addProblem('导出图片', res.error ?? '导出图片失败');
        }
      },
    );
  }

  Future<void> printPages({
    required List<int> pagesZeroBased,
    required PrintQuality quality,
    required bool includeAnnotations,
  }) async {
    if (!hasDocument) return;
    await runBusy('正在渲染打印页面…', () async {
      final res = await ExportAndPrintService.printPages(
        filePath: activeRenderPath!,
        jobName: displayFileName.isEmpty ? 'PDF 打印' : displayFileName,
        pagesZeroBased: pagesZeroBased,
        pageSizes: pageSizes,
        pageRotations: pageRotations,
        viewRotationDeg: viewRotationDeg,
        quality: quality,
        includeAnnotations: includeAnnotations,
        allAnnotations: annotations,
        loadedImages: loadedImages,
        password: password,
      );
      if (res.ok) {
        showToast('打印任务已提交');
      } else if (res.canceled) {
        showToast('已取消打印');
      } else {
        final err = res.error ?? '打印失败';
        showToast(err, isError: true);
        addProblem('打印', err);
      }
    });
  }

  Future<OrientationPlanResult?> analyzeOrientation({
    void Function(int current, int total)? onProgress,
  }) async {
    if (!hasDocument) return null;
    return OrientationService.analyzeDocument(
      filePath: activeRenderPath!,
      pageSizes: pageSizes,
      password: password,
      onProgress: onProgress,
    );
  }

  Future<bool> convertImagesToPdf({
    required List<String> imagePaths,
    required String targetPath,
    required bool useA4,
    bool allowReplaceDirty = false,
    void Function(int done, int total, String name)? onProgress,
  }) async {
    final res = await ImageToPdfService.convert(
      imagePaths: imagePaths,
      targetPath: targetPath,
      useA4: useA4,
      onProgress: onProgress,
    );
    if (!res.ok) {
      showToast(res.error ?? '转换失败', isError: true);
      return false;
    }
    if (res.failedFiles.isNotEmpty) {
      addProblem('图片转 PDF', '以下图片已跳过：${res.failedFiles.join("、")}');
    }
    if (!dirty || allowReplaceDirty) {
      await openDocument(targetPath);
      showToast('已生成并打开 PDF（${res.pageCount} 页）');
    } else {
      showToast('已生成 PDF 到：$targetPath（当前文档有未保存改动，未覆盖）');
    }
    return true;
  }

  // -------------------------------------------------------------------------
  // 视图控制、缩放、翻页、大纲、历史
  // -------------------------------------------------------------------------
  void setViewMode(ReadingViewMode mode) {
    if (viewMode == mode) return;
    viewMode = mode;
    notifyListeners();
  }

  Future<void> onViewerDocumentChanged(PdfDocument? doc) async {
    activePdfDoc = doc;
    if (doc == null) {
      outlineNodes = [];
      notifyListeners();
      return;
    }
    try {
      outlineNodes = await doc.loadOutline();
    } catch (_) {
      outlineNodes = [];
    }
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryApplyPendingRestore());
  }

  Future<void> rotateView(int deltaDeg) async {
    viewRotationDeg = ((viewRotationDeg + deltaDeg) % 360 + 360) % 360;
    final doc = activePdfDoc;
    if (doc != null) {
      final steps = ((deltaDeg ~/ 90) % 4 + 4) % 4;
      if (steps != 0) {
        final fp = pdfium.getPdfium();
        await doc.useNativeDocumentHandle((addr) {
          final nativeDoc = pdfium.FPDF_DOCUMENT.fromAddress(addr);
          final count = fp.FPDF_GetPageCount(nativeDoc);
          for (var i = 0; i < count; i++) {
            final page = fp.FPDF_LoadPage(nativeDoc, i);
            if (page == nullptr) continue;
            try {
              final rawRot = fp.FPDFPage_GetRotation(page);
              final cur = rawRot < 0 ? 0 : rawRot % 4;
              fp.FPDFPage_SetRotation(page, (cur + steps) % 4);
            } finally {
              fp.FPDF_ClosePage(page);
            }
          }
        });
        await doc.reloadPages();
      }
    }
    notifyListeners();
  }

  void onViewerPageChanged(int? page) {
    if (page == null || page < 1 || page > pageCount) return;
    if (currentPage == page) return;
    final prev = currentPage;
    currentPage = page;
    if (!_navigatingHistory) {
      _historyDebounce?.cancel();
      _historyDebounce = Timer(const Duration(milliseconds: 700), () {
        if (_backHistory.isEmpty || _backHistory.last != prev) {
          _backHistory.add(prev);
          if (_backHistory.length > 100) _backHistory.removeAt(0);
          _forwardHistory.clear();
          notifyListeners();
        }
      });
    }
    if (filePath != null) {
      AppDataService.recordRecent(filePath!, page);
    }
    notifyListeners();
  }

  void jumpToPage(int page) {
    if (!hasDocument) return;
    final target = page.clamp(1, pageCount);
    if (viewerController.isReady) {
      viewerController.goToPage(pageNumber: target);
    }
    currentPage = target;
    notifyListeners();
  }

  void stepPage(int delta) {
    final step = viewMode == ReadingViewMode.twoPage ? delta * 2 : delta;
    jumpToPage((currentPage + step).clamp(1, math.max(1, pageCount)));
  }

  void goBack() {
    if (_backHistory.isEmpty) return;
    _navigatingHistory = true;
    final target = _backHistory.removeLast();
    _forwardHistory.add(currentPage);
    jumpToPage(target);
    _navigatingHistory = false;
    notifyListeners();
  }

  void goForward() {
    if (_forwardHistory.isEmpty) return;
    _navigatingHistory = true;
    final target = _forwardHistory.removeLast();
    _backHistory.add(currentPage);
    jumpToPage(target);
    _navigatingHistory = false;
    notifyListeners();
  }

  void setZoomPercent(double percent) {
    final nextZoom = (percent / 100.0).clamp(0.25, 4.0);
    zoomIntent = ZoomIntent.manual;
    if (viewerController.isReady) {
      viewerController.setZoom(viewerController.centerPosition, nextZoom);
    }
    scale = nextZoom;
    notifyListeners();
  }

  void fitWidth({double? maxAutoZoom, bool userAction = true}) {
    if (!hasDocument || !viewerController.isReady || pageSizes.isEmpty) return;
    final viewW = viewerController.viewSize.width;
    if (viewW <= 0) return;
    final pi = (currentPage - 1).clamp(0, pageSizes.length - 1);
    final sz = pageSizes[pi];
    final rotSteps = ((viewRotationDeg ~/ 90) % 4 + 4) % 4;
    final pageW = rotSteps.isOdd ? sz.h : sz.w;
    final targetW = viewMode == ReadingViewMode.twoPage ? pageW * 2 + 16 : pageW;
    final maxZoom = maxAutoZoom ?? 4.0;
    final nextZoom =
        ((viewW - 48) / math.max(targetW, 1)).clamp(0.25, maxZoom);
    zoomIntent = ZoomIntent.fitWidth;
    viewerController.setZoom(viewerController.centerPosition, nextZoom);
    scale = nextZoom;
    notifyListeners();
  }

  void fitPage({bool userAction = true}) {
    if (!hasDocument || !viewerController.isReady || pageSizes.isEmpty) return;
    final viewW = viewerController.viewSize.width;
    final viewH = viewerController.viewSize.height;
    if (viewW <= 0 || viewH <= 0) return;
    final pi = (currentPage - 1).clamp(0, pageSizes.length - 1);
    final sz = pageSizes[pi];
    final rotSteps = ((viewRotationDeg ~/ 90) % 4 + 4) % 4;
    final pageW = rotSteps.isOdd ? sz.h : sz.w;
    final pageH = rotSteps.isOdd ? sz.w : sz.h;
    final targetW = viewMode == ReadingViewMode.twoPage ? pageW * 2 + 16 : pageW;
    final zx = (viewW - 48) / math.max(targetW, 1);
    final zy = (viewH - 48) / math.max(pageH, 1);
    final nextZoom = math.min(zx, zy).clamp(0.25, 4.0);
    zoomIntent = ZoomIntent.fitPage;
    viewerController.setZoom(viewerController.centerPosition, nextZoom);
    scale = nextZoom;
    notifyListeners();
  }

  void updateSearchQuery(String query) {
    searchQuery = query;
    if (query.trim().isEmpty) {
      textSearcher.resetTextSearch();
      searchMatchesCount = 0;
      searchCurrentIndex = -1;
      notifyListeners();
      return;
    }
    textSearcher.startTextSearch(query, caseInsensitive: true);
    notifyListeners();
  }

  void nextSearchMatch() {
    if (searchMatchesCount == 0) return;
    textSearcher.goToNextMatch();
  }

  void prevSearchMatch() {
    if (searchMatchesCount == 0) return;
    textSearcher.goToPrevMatch();
  }

  bool isThumbnailsOpenFor(WorkspaceLayoutSpec spec) {
    return spec.leftIsOverlay ? _overlayThumbnailsOpen : _dockedThumbnailsOpen;
  }

  bool isRightPanelOpenFor(WorkspaceLayoutSpec spec) {
    return spec.rightIsOverlay ? _overlayRightPanelOpen : _dockedRightPanelOpen;
  }

  void toggleThumbnails([WorkspaceLayoutSpec? spec]) {
    if (spec != null && spec.leftIsOverlay) {
      _overlayThumbnailsOpen = !_overlayThumbnailsOpen;
      if (_overlayThumbnailsOpen && spec.rightIsOverlay) {
        _overlayRightPanelOpen = false;
      }
      showThumbnails = _overlayThumbnailsOpen;
      notifyListeners();
      return;
    }
    _dockedThumbnailsOpen = !_dockedThumbnailsOpen;
    showThumbnails = _dockedThumbnailsOpen;
    notifyListeners();
  }

  void toggleRightPanel([WorkspaceLayoutSpec? spec]) {
    if (spec != null && spec.rightIsOverlay) {
      _overlayRightPanelOpen = !_overlayRightPanelOpen;
      if (_overlayRightPanelOpen && spec.leftIsOverlay) {
        _overlayThumbnailsOpen = false;
      }
      showRightPanel = _overlayRightPanelOpen;
      notifyListeners();
      return;
    }
    _dockedRightPanelOpen = !_dockedRightPanelOpen;
    showRightPanel = _dockedRightPanelOpen;
    notifyListeners();
  }

  bool closeOverlayPanels(WorkspaceLayoutSpec spec) {
    var changed = false;
    if (spec.leftIsOverlay && _overlayThumbnailsOpen) {
      _overlayThumbnailsOpen = false;
      changed = true;
    }
    if (spec.rightIsOverlay && _overlayRightPanelOpen) {
      _overlayRightPanelOpen = false;
      changed = true;
    }
    if (changed) notifyListeners();
    return changed;
  }

  void syncPanelOverridesOnBreakpointChange({
    required bool leftBecameOverlay,
    required bool rightBecameOverlay,
  }) {
    var changed = false;
    if (leftBecameOverlay && _overlayThumbnailsOpen) {
      _overlayThumbnailsOpen = false;
      changed = true;
    }
    if (rightBecameOverlay && _overlayRightPanelOpen) {
      _overlayRightPanelOpen = false;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void toggleSearch() {
    searchOpen = !searchOpen;
    if (searchOpen) {
      searchFocusSeq++;
    } else {
      updateSearchQuery('');
    }
    notifyListeners();
  }

  void openOrFocusSearch() {
    if (!hasDocument) return;
    if (!searchOpen) {
      searchOpen = true;
    }
    searchFocusSeq++;
    notifyListeners();
  }

  void toggleAutoCollapseDock() {
    autoCollapseDock = !autoCollapseDock;
    if (!autoCollapseDock) {
      dockExpandSeq++;
    }
    notifyListeners();
  }

  Future<void> removeRecentFile(String path) async {
    final norm = p.normalize(path).toLowerCase();
    recentFiles = recentFiles
        .where((e) => p.normalize(e.path).toLowerCase() != norm)
        .toList();
    notifyListeners();
    await AppDataService.removeRecent(path);
  }

  Future<void> clearMissingRecentFiles() async {
    final before = recentFiles.length;
    recentFiles =
        recentFiles.where((e) => File(e.path).existsSync()).toList();
    final removed = before - recentFiles.length;
    notifyListeners();
    await AppDataService.clearRecent(missingOnly: true);
    if (removed > 0) {
      showToast('已清理 $removed 条失效记录');
    }
  }

  Future<void> clearAllRecentFiles() async {
    if (recentFiles.isEmpty) return;
    recentFiles = [];
    notifyListeners();
    await AppDataService.clearRecent(missingOnly: false);
    showToast('已清空最近打开记录');
  }

  void toggleThumbSelection(int pageZeroBased) {
    if (!selectedThumbPages.add(pageZeroBased)) {
      selectedThumbPages.remove(pageZeroBased);
    }
    notifyListeners();
  }

  void selectAllThumbs() {
    selectedThumbPages
      ..clear()
      ..addAll(List<int>.generate(pageCount, (i) => i));
    notifyListeners();
  }

  void invertThumbSelection() {
    final next = <int>{};
    for (var i = 0; i < pageCount; i++) {
      if (!selectedThumbPages.contains(i)) next.add(i);
    }
    selectedThumbPages
      ..clear()
      ..addAll(next);
    notifyListeners();
  }

  void clearThumbSelection() {
    selectedThumbPages.clear();
    notifyListeners();
  }

  void syncViewerZoom(double zoom, {bool fromUserGesture = false}) {
    if ((scale - zoom).abs() <= 0.002) return;
    if (fromUserGesture && (scale - zoom).abs() > 0.015) {
      zoomIntent = ZoomIntent.manual;
    }
    scale = zoom;
    notifyListeners();
  }

  void startEditingText(String id) {
    editingTextId = id;
    notifyListeners();
  }

  void stopEditingText() {
    if (editingTextId == null) return;
    editingTextId = null;
    notifyListeners();
  }

  void refresh() {
    notifyListeners();
  }

  Future<void> toggleFullscreen() async {
    isFullscreen = await NativeBridge.toggleFullscreen();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _inlineCommitHooks.clear();
    _toastTimer?.cancel();
    _historyDebounce?.cancel();
    textSearcher.removeListener(_onSearchChanged);
    textSearcher.dispose();
    _disposeLoadedImages();
    unawaited(_cleanupWorkFiles());
    super.dispose();
  }
}
