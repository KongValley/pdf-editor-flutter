import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart' hide PdfPoint;
import 'package:uuid/uuid.dart';

import '../../models/annotation_model.dart';
import '../../rendering/annotation_painter.dart';
import '../../state/editor_controller.dart';
import '../../utils/page_range.dart';
import '../dialogs/editor_dialogs.dart' show DialogControllersHost;
import '../theme/app_theme.dart';
import 'desktop_controls.dart';
import 'pdf_desktop_scrollbar.dart';

class _PointerLatch {
  bool consumedByOverlay = false;
  bool contextMenuHandled = false;
}

class PdfWorkspaceView extends StatefulWidget {
  const PdfWorkspaceView({
    super.key,
    required this.controller,
    required this.onContextMenu,
    this.focusNode,
  });

  final EditorController controller;
  final void Function(int pageZeroBased, Offset globalPos, String? annotId)
      onContextMenu;
  final FocusNode? focusNode;

  @override
  State<PdfWorkspaceView> createState() => PdfWorkspaceViewState();
}

class PdfWorkspaceViewState extends State<PdfWorkspaceView> {
  final GlobalKey _viewerKey = GlobalKey();
  final _PointerLatch _pointerLatch = _PointerLatch();
  FocusNode? _ownedFocusNode;

  FocusNode get canvasFocusNode =>
      widget.focusNode ?? (_ownedFocusNode ??= FocusNode(debugLabel: 'pdf_canvas'));

  bool _spaceDown = false;
  bool _panning = false;
  bool _canvasFocused = false;
  Offset? _panLastGlobal;
  Offset? _secondaryDownGlobal;
  double _lastZoom = 1.0;
  Size? _lastViewportSize;

  bool get spaceDown => _spaceDown;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    widget.controller.viewerController.addListener(_onViewerMatrixChanged);
  }

  @override
  void didUpdateWidget(covariant PdfWorkspaceView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.viewerController
          .removeListener(_onViewerMatrixChanged);
      widget.controller.viewerController.addListener(_onViewerMatrixChanged);
    }
  }

  @override
  void deactivate() {
    if (_spaceDown || _panning) {
      _spaceDown = false;
      _panning = false;
      _panLastGlobal = null;
    }
    super.deactivate();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    widget.controller.viewerController.removeListener(_onViewerMatrixChanged);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  bool _isEditableFocused() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.space) return false;
    final modalActive = mounted && !(ModalRoute.of(context)?.isCurrent ?? true);
    if (modalActive) {
      if (_spaceDown && mounted) {
        setState(() {
          _spaceDown = false;
          _panning = false;
          _panLastGlobal = null;
        });
      }
      return false;
    }
    if (event is KeyDownEvent) {
      if (_isEditableFocused() || !widget.controller.hasDocument) return false;
      if (!_spaceDown && mounted) {
        setState(() => _spaceDown = true);
      }
      return true;
    }
    if (event is KeyUpEvent) {
      if (_spaceDown && mounted) {
        setState(() {
          _spaceDown = false;
          _panning = false;
          _panLastGlobal = null;
        });
        return true;
      }
    }
    return false;
  }

  void _onViewerMatrixChanged({bool fromUserGesture = false}) {
    final vc = widget.controller.viewerController;
    if (!vc.isReady) return;
    final zoom = vc.currentZoom;
    if ((zoom - _lastZoom).abs() > 0.002) {
      _lastZoom = zoom;
      widget.controller.syncViewerZoom(zoom, fromUserGesture: fromUserGesture);
    }
  }

  Future<bool> copySelectedDocumentText() async {
    final vc = widget.controller.viewerController;
    if (!vc.isReady) return false;
    final d = vc.textSelectionDelegate;
    if (d.hasSelectedText) {
      return d.copyTextSelection();
    }
    return false;
  }

  void _panByDelta(Offset screenDelta) {
    final vc = widget.controller.viewerController;
    if (!vc.isReady) return;
    final m = vc.value.clone();
    m.setEntry(0, 3, m.entry(0, 3) + screenDelta.dx);
    m.setEntry(1, 3, m.entry(1, 3) + screenDelta.dy);
    unawaited(vc.goTo(m, duration: Duration.zero));
  }

  void _handleWorkspacePointerDown(PointerDownEvent event) {
    final isMiddle = (event.buttons & kMiddleMouseButton) != 0;
    final isPrimary = (event.buttons & kPrimaryButton) != 0;
    final isSecondary = (event.buttons & kSecondaryMouseButton) != 0;

    // 空格+左键由 PdfViewer(panEnabled: true) 原生平移，避免与 _panByDelta 叠加造成双倍位移
    if (_spaceDown && isPrimary) {
      return;
    }

    if (isMiddle) {
      _panning = true;
      _panLastGlobal = event.position;
      if (mounted) setState(() {});
      return;
    }

    if (isSecondary) {
      _secondaryDownGlobal = event.position;
    }

    if (isPrimary) {
      if (!_pointerLatch.consumedByOverlay) {
        widget.controller.flushPendingInlineEdits();
      }
      if (widget.controller.editingTextId == null && !canvasFocusNode.hasFocus) {
        canvasFocusNode.requestFocus();
      }
      if (!_pointerLatch.consumedByOverlay &&
          widget.controller.tool == EditorTool.select &&
          (widget.controller.selectedIds.isNotEmpty ||
              widget.controller.editingTextId != null)) {
        widget.controller.selectAnnotation(null);
      }
    }
    _pointerLatch.consumedByOverlay = false;
  }

  void _handleWorkspacePointerMove(PointerMoveEvent event) {
    if (_panning && _panLastGlobal != null) {
      final delta = event.position - _panLastGlobal!;
      _panLastGlobal = event.position;
      _panByDelta(delta);
    }
  }

  void _handleWorkspacePointerUp(PointerUpEvent event) {
    if (_panning) {
      _panning = false;
      _panLastGlobal = null;
      if (mounted) setState(() {});
    }

    if (_secondaryDownGlobal != null) {
      final moved = (event.position - _secondaryDownGlobal!).distance;
      final downPos = _secondaryDownGlobal!;
      _secondaryDownGlobal = null;
      final handledByOverlay = _pointerLatch.contextMenuHandled;
      _pointerLatch.contextMenuHandled = false;
      if (!handledByOverlay && moved < 8.0) {
        final box = _viewerKey.currentContext?.findRenderObject() as RenderBox?;
        final vc = widget.controller.viewerController;
        if (box != null && vc.isReady) {
          final local = box.globalToLocal(downPos);
          final hit = vc.getPdfPageHitTestResult(
            local,
            useDocumentLayoutCoordinates: false,
          );
          final pageZeroBased = hit != null
              ? hit.page.pageNumber - 1
              : (widget.controller.currentPage - 1)
                  .clamp(0, math.max<int>(0, widget.controller.pageCount - 1))
                  .toInt();
          widget.onContextMenu(pageZeroBased, downPos, null);
        }
      }
    } else {
      _pointerLatch.contextMenuHandled = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final c = context.appColors;

    if (ctrl.suspendViewer || ctrl.activeRenderPath == null) {
      return Container(
        color: c.canvasBg,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(strokeWidth: 2.5),
            const SizedBox(height: 12),
            Text(
              ctrl.busyMessage ?? '正在刷新文档...',
              style: TextStyle(fontSize: AppTypography.body, color: c.mutedText),
            ),
          ],
        ),
      );
    }

    final layoutStrategy = ctrl.viewMode == ReadingViewMode.twoPage
        ? const FacingPagesLayout(
            coverPage: false,
            margin: 16.0,
            fitMode: PdfFitMode.none,
          )
        : const SequentialPagesLayout(
            spacing: 12.0,
            margin: 16.0,
            fitMode: PdfFitMode.none,
          );

    final paging =
        ctrl.viewMode == ReadingViewMode.single ? const PdfPaging() : null;

    final cursor = _panning
        ? SystemMouseCursors.grabbing
        : _spaceDown
            ? SystemMouseCursors.grab
            : ctrl.tool != EditorTool.select
                ? SystemMouseCursors.precise
                : MouseCursor.defer;

    return LayoutBuilder(
      builder: (context, constraints) {
        final nextSize = Size(constraints.maxWidth, constraints.maxHeight);
        final widthChanged = _lastViewportSize != null &&
            (_lastViewportSize!.width - nextSize.width).abs() > 4.0;
        final heightChanged = _lastViewportSize != null &&
            ctrl.zoomIntent == ZoomIntent.fitPage &&
            (_lastViewportSize!.height - nextSize.height).abs() > 4.0;
        if (widthChanged || heightChanged) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.controller.onWorkspaceViewportResized();
          });
        }
        _lastViewportSize = nextSize;

        return Focus(
          focusNode: canvasFocusNode,
          canRequestFocus: true,
          onFocusChange: (focused) {
            if (_canvasFocused != focused && mounted) {
              setState(() => _canvasFocused = focused);
            }
          },
          child: Semantics(
            label: 'PDF 文档画布',
            child: Container(
              color: c.canvasBg,
              foregroundDecoration: _canvasFocused
                  ? BoxDecoration(
                      border: Border.all(
                        color: c.accent.withValues(alpha: 0.55),
                        width: 2,
                      ),
                    )
                  : null,
              child: MouseRegion(
                cursor: cursor,
                opaque: false,
                child: Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: _handleWorkspacePointerDown,
                  onPointerMove: _handleWorkspacePointerMove,
                  onPointerUp: _handleWorkspacePointerUp,
                  onPointerCancel: (_) {
                    _panning = false;
                    _panLastGlobal = null;
                    _secondaryDownGlobal = null;
                    _pointerLatch.consumedByOverlay = false;
                    _pointerLatch.contextMenuHandled = false;
                  },
                  child: KeyedSubtree(
                    key: _viewerKey,
                    child: PdfViewer.file(
                      ctrl.activeRenderPath!,
                      key: ValueKey(
                        'viewer_${ctrl.activeRenderPath}_${ctrl.viewerRevision}',
                      ),
                      controller: ctrl.viewerController,
                      initialPageNumber: ctrl.currentPage,
                      passwordProvider: () => ctrl.password,
                      params: PdfViewerParams(
                        backgroundColor: c.canvasBg,
                        layoutStrategy: layoutStrategy,
                        paging: paging,
                        limitRenderingCache: true,
                        maxImageBytesCachedOnMemory: 120 * 1024 * 1024,
                        enableKeyboardNavigation: false,
                        keyHandlerParams: const PdfViewerKeyHandlerParams(
                          enabled: false,
                          canRequestFocus: false,
                        ),
                        buildContextMenu: (_, _) => const SizedBox.shrink(),
                        panEnabled: true,
                        pageDropShadow: BoxShadow(
                          color: Colors.black.withValues(
                            alpha: ctrl.isDarkMode ? 0.45 : 0.16,
                          ),
                          blurRadius: 12,
                          spreadRadius: 1,
                          offset: const Offset(0, 3),
                        ),
                        textSelectionParams: PdfTextSelectionParams(
                          enabled: ctrl.tool == EditorTool.select && !_spaceDown,
                        ),
                        pagePaintCallbacks: [
                          ctrl.textSearcher.pageTextMatchPaintCallback,
                        ],
                        onDocumentChanged: ctrl.onViewerDocumentChanged,
                        onPageChanged: ctrl.onViewerPageChanged,
                        onInteractionUpdate: (_) =>
                            _onViewerMatrixChanged(fromUserGesture: true),
                        onAnimationEnd: _onViewerMatrixChanged,
                        onViewerReady: (_, _) {
                          ctrl.onViewerReady();
                          _onViewerMatrixChanged();
                        },
                        viewerOverlayBuilder: (context, size, handleLinkTap) =>
                            [
                          Positioned.fill(
                            child: PdfDesktopScrollbars(
                              viewerController: ctrl.viewerController,
                              pageCount: ctrl.pageCount,
                              onPointerInteracting: () {
                                _pointerLatch.consumedByOverlay = true;
                              },
                            ),
                          ),
                        ],
                        pageOverlaysBuilder: (context, pageRect, page) {
                          return [
                            Positioned.fill(
                              child: IgnorePointer(
                                ignoring: _spaceDown,
                                child: _PageAnnotationOverlay(
                                  controller: ctrl,
                                  page: page,
                                  pageRect: pageRect,
                                  spaceDown: _spaceDown,
                                  pointerLatch: _pointerLatch,
                                  onContextMenu: widget.onContextMenu,
                                ),
                              ),
                            ),
                          ];
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================================================
// 选择性命中探测容器：Select 模式下空白处完全穿透给 pdfrx 文本选择 / 平移
// ============================================================================
class _SelectiveOverlayHitBox extends SingleChildRenderObjectWidget {
  const _SelectiveOverlayHitBox({
    required this.allowPassthrough,
    required this.shouldInterceptPoint,
    super.child,
  });

  final bool allowPassthrough;
  final bool Function(Offset position) shouldInterceptPoint;

  @override
  _RenderSelectiveOverlayHitBox createRenderObject(BuildContext context) {
    return _RenderSelectiveOverlayHitBox(
      allowPassthrough: allowPassthrough,
      shouldInterceptPoint: shouldInterceptPoint,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSelectiveOverlayHitBox renderObject,
  ) {
    renderObject
      ..allowPassthrough = allowPassthrough
      ..shouldInterceptPoint = shouldInterceptPoint;
  }
}

class _RenderSelectiveOverlayHitBox extends RenderProxyBox {
  _RenderSelectiveOverlayHitBox({
    required this.allowPassthrough,
    required this.shouldInterceptPoint,
  });

  bool allowPassthrough;
  bool Function(Offset position) shouldInterceptPoint;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position)) return false;
    if (allowPassthrough) return false;
    if (!shouldInterceptPoint(position)) return false;
    return super.hitTest(result, position: position);
  }
}

// ============================================================================
// 单页交互批注叠加层
// ============================================================================
enum _ActiveGestureMode {
  none,
  move,
  resize,
  draw,
}

class _PageAnnotationOverlay extends StatefulWidget {
  const _PageAnnotationOverlay({
    required this.controller,
    required this.page,
    required this.pageRect,
    required this.spaceDown,
    required this.pointerLatch,
    required this.onContextMenu,
  });

  final EditorController controller;
  final PdfPage page;
  final Rect pageRect;
  final bool spaceDown;
  final _PointerLatch pointerLatch;
  final void Function(int pageZeroBased, Offset globalPos, String? annotId)
      onContextMenu;

  @override
  State<_PageAnnotationOverlay> createState() => _PageAnnotationOverlayState();
}

class _PageAnnotationOverlayState extends State<_PageAnnotationOverlay> {
  static const _uuid = Uuid();

  PdfPageRawText? _cachedPageText;
  bool _loadingText = false;

  _ActiveGestureMode _mode = _ActiveGestureMode.none;
  Offset? _downLocal;
  PdfPoint? _downPdf;

  // Move state
  final Set<String> _movingIds = {};
  Offset _moveDeltaScreen = Offset.zero;

  // Resize state
  PdfAnnotationItem? _resizeOriginal;
  PdfAnnotationItem? _resizeDraft;
  ResizeHandle _resizeHandle = ResizeHandle.none;

  // Draw state
  final List<PdfPoint> _inkPoints = [];
  PdfAnnotationItem? _drawDraft;
  List<PdfRect> _highlightPreviewCharRects = [];

  // Double-tap tracking
  int _lastTapMs = 0;
  String? _lastTapId;
  MouseCursor _hoverCursor = MouseCursor.defer;

  // Inline text editor
  final TextEditingController _inlineTextCtrl = TextEditingController();
  final FocusNode _inlineFocus = FocusNode();
  String? _boundInlineId;
  bool _committingInline = false;

  @override
  void initState() {
    super.initState();
    _inlineFocus.addListener(_onInlineFocusChange);
    widget.controller.registerInlineCommitHook(_commitInlineText);
  }

  @override
  void deactivate() {
    if (_boundInlineId != null && !_committingInline) {
      _commitInlineText();
    }
    super.deactivate();
  }

  @override
  void dispose() {
    widget.controller.unregisterInlineCommitHook(_commitInlineText);
    _inlineFocus.removeListener(_onInlineFocusChange);
    _inlineFocus.dispose();
    _inlineTextCtrl.dispose();
    super.dispose();
  }

  PdfScreenTransform _buildTransform() {
    final rotIndex = widget.page.rotation.index;
    final swap = rotIndex.isOdd;
    final rawW = swap ? widget.page.height : widget.page.width;
    final rawH = swap ? widget.page.width : widget.page.height;
    final baseScale = widget.pageRect.width / math.max(widget.page.width, 1.0);
    return PdfScreenTransform(
      rawWidthPt: rawW,
      rawHeightPt: rawH,
      scale: baseScale,
      viewRotationDeg: rotIndex * 90,
    );
  }

  List<PdfAnnotationItem> _pageAnnotations() {
    final pageIdx = widget.page.pageNumber - 1;
    return [
      for (final a in widget.controller.annotations)
        if (a.page == pageIdx) a,
    ];
  }

  void _ensurePageTextLoaded() {
    if (_cachedPageText != null || _loadingText) return;
    _loadingText = true;
    unawaited(
      widget.page.loadText().then((txt) {
        _cachedPageText = txt;
        _loadingText = false;
      }).catchError((_) {
        _loadingText = false;
      }),
    );
  }

  bool _isShiftPressed() {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }

  ResizeHandle _hitTestHandle(
    Offset localPos,
    PdfScreenTransform transform,
    List<PdfAnnotationItem> pageAnnots,
  ) {
    final single = widget.controller.singleSelectedAnnotation;
    if (single == null ||
        single.locked ||
        single.page != widget.page.pageNumber - 1) {
      return ResizeHandle.none;
    }
    const tol = 8.5;
    for (final h in handlesForAnnotation(single, transform)) {
      if ((h.center - localPos).distance <= tol) {
        return h.handle;
      }
    }
    return ResizeHandle.none;
  }

  PdfAnnotationItem? _hitTestAnnotation(
    Offset localPos,
    PdfScreenTransform transform,
    List<PdfAnnotationItem> pageAnnots,
  ) {
    const margin = 6.5;
    for (var i = pageAnnots.length - 1; i >= 0; i--) {
      final ann = pageAnnots[i];
      switch (ann.kind) {
        case AnnotationKind.ink:
          if (ann.points.length >= 2) {
            final tol = math.max(margin, ann.thickness * transform.scale + 4.0);
            for (var k = 0; k < ann.points.length - 1; k++) {
              final a = transform.pdfToScreen(ann.points[k]);
              final b = transform.pdfToScreen(ann.points[k + 1]);
              if (_distPointToSegment(localPos, a, b) <= tol) {
                return ann;
              }
            }
          }
          break;

        case AnnotationKind.arrow:
        case AnnotationKind.measure:
          final from = transform.pdfToScreen(
            ann.from ?? PdfPoint(ann.bbox.x, ann.bbox.y),
          );
          final to = transform.pdfToScreen(
            ann.to ?? PdfPoint(ann.bbox.right, ann.bbox.top),
          );
          final tol = math.max(margin, ann.thickness * transform.scale + 5.0);
          if (_distPointToSegment(localPos, from, to) <= tol) {
            return ann;
          }
          if (ann.kind == AnnotationKind.measure) {
            final mid = Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2);
            if ((localPos - mid).distance <= 24.0) {
              return ann;
            }
          }
          break;

        case AnnotationKind.rect:
          final r = transform.pdfRectToScreen(ann.bbox);
          if (r.inflate(margin).contains(localPos) &&
              (!r.deflate(margin).contains(localPos) ||
                  math.min(r.width, r.height) <= 24.0)) {
            return ann;
          }
          break;

        case AnnotationKind.ellipse:
          final r = transform.pdfRectToScreen(ann.bbox);
          if (r.width > 0 && r.height > 0 && r.inflate(margin).contains(localPos)) {
            final rx = r.width / 2;
            final ry = r.height / 2;
            final nx = (localPos.dx - r.center.dx) / math.max(rx, 1.0);
            final ny = (localPos.dy - r.center.dy) / math.max(ry, 1.0);
            final dNorm = math.sqrt(nx * nx + ny * ny);
            final band = margin / math.max(math.min(rx, ry), 1.0);
            if ((dNorm - 1.0).abs() <= band ||
                math.min(r.width, r.height) <= 24.0) {
              return ann;
            }
          }
          break;

        case AnnotationKind.highlight:
        case AnnotationKind.text:
        case AnnotationKind.note:
        case AnnotationKind.stamp:
        case AnnotationKind.image:
          final r = transform.pdfRectToScreen(ann.effectiveBounds);
          if (r.inflate(margin * 0.6).contains(localPos)) {
            return ann;
          }
          break;
      }
    }
    return null;
  }

  bool _shouldInterceptPoint(Offset localPos) {
    final ctrl = widget.controller;
    if (ctrl.tool != EditorTool.select) return true;
    final transform = _buildTransform();
    final pageAnnots = _pageAnnotations();
    if (_hitTestHandle(localPos, transform, pageAnnots) != ResizeHandle.none) {
      return true;
    }
    return _hitTestAnnotation(localPos, transform, pageAnnots) != null;
  }

  void _updateHoverCursor(Offset localPos) {
    final ctrl = widget.controller;
    if (ctrl.tool != EditorTool.select) {
      if (_hoverCursor != SystemMouseCursors.precise) {
        setState(() => _hoverCursor = SystemMouseCursors.precise);
      }
      return;
    }
    final transform = _buildTransform();
    final pageAnnots = _pageAnnotations();
    final handle = _hitTestHandle(localPos, transform, pageAnnots);
    MouseCursor next;
    if (handle != ResizeHandle.none) {
      next = _cursorForHandle(handle);
    } else {
      final hit = _hitTestAnnotation(localPos, transform, pageAnnots);
      if (hit != null) {
        next = hit.locked ? SystemMouseCursors.basic : SystemMouseCursors.move;
      } else {
        next = MouseCursor.defer;
      }
    }
    if (next != _hoverCursor) {
      setState(() => _hoverCursor = next);
    }
  }

  MouseCursor _cursorForHandle(ResizeHandle h) {
    return switch (h) {
      ResizeHandle.topLeft || ResizeHandle.bottomRight =>
        SystemMouseCursors.resizeUpLeftDownRight,
      ResizeHandle.topRight || ResizeHandle.bottomLeft =>
        SystemMouseCursors.resizeUpRightDownLeft,
      ResizeHandle.topCenter || ResizeHandle.bottomCenter =>
        SystemMouseCursors.resizeUpDown,
      ResizeHandle.middleLeft || ResizeHandle.middleRight =>
        SystemMouseCursors.resizeLeftRight,
      ResizeHandle.endpointFrom || ResizeHandle.endpointTo =>
        SystemMouseCursors.grab,
      ResizeHandle.none => SystemMouseCursors.move,
    };
  }

  void _onInlineFocusChange() {
    if (!_inlineFocus.hasFocus && _boundInlineId != null && !_committingInline) {
      unawaited(Future.microtask(_commitInlineText));
    }
  }

  void _commitInlineText() {
    final id = _boundInlineId;
    if (id == null || _committingInline) return;
    _committingInline = true;
    try {
      final ctrl = widget.controller;
      final txt = _inlineTextCtrl.text;
      final idx = ctrl.annotations.indexWhere((a) => a.id == id);
      if (idx >= 0) {
        final cur = ctrl.annotations[idx];
        if (txt.trim().isEmpty) {
          if (cur.text.isEmpty) {
            ctrl.discardNewEmptyAnnotation(id);
          } else {
            ctrl.deleteAnnotationById(id);
          }
        } else {
          final fontFamily =
              (cur.fontFamily != null && cur.fontFamily!.isNotEmpty)
                  ? cur.fontFamily
                  : null;
          double measure(String s) {
            if (s.isEmpty) return 0;
            final tp = TextPainter(
              text: TextSpan(
                text: s,
                style: TextStyle(fontSize: cur.fontSize, fontFamily: fontFamily),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            return tp.width;
          }

          final frame = textBlockFrame(cur.bbox, cur.rotate);
          final lines = wrapText(txt, math.max(frame.run, 24), measure);
          final minStack =
              math.max(frame.stack, lines.length * cur.fontSize * 1.2 + 6);
          final rot = ((cur.rotate % 360) + 360) % 360;
          final swapped = rot == 90 || rot == 270;
          final updatedBox = swapped
              ? cur.bbox.copyWith(w: math.max(cur.bbox.w, minStack))
              : cur.bbox.copyWith(h: math.max(cur.bbox.h, minStack));
          ctrl.patchAnnotation(
            id,
            (c) => c.copyWith(text: txt, bbox: updatedBox),
            recordHistory: cur.text.isNotEmpty,
          );
        }
      }
      ctrl.stopEditingText();
      _boundInlineId = null;
    } finally {
      _committingInline = false;
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (widget.spaceDown) return;
    final ctrl = widget.controller;
    final transform = _buildTransform();
    final pageAnnots = _pageAnnotations();
    final localPos = event.localPosition;

    if ((event.buttons & kMiddleMouseButton) != 0) {
      return;
    }

    if ((event.buttons & kSecondaryMouseButton) != 0) {
      widget.pointerLatch.consumedByOverlay = true;
      widget.pointerLatch.contextMenuHandled = true;
      final hit = _hitTestAnnotation(localPos, transform, pageAnnots);
      if (hit != null && !ctrl.selectedIds.contains(hit.id)) {
        ctrl.selectAnnotation(hit.id);
      }
      widget.onContextMenu(
        widget.page.pageNumber - 1,
        event.position,
        hit?.id,
      );
      return;
    }

    if ((event.buttons & kPrimaryButton) == 0) return;
    widget.pointerLatch.consumedByOverlay = true;

    // If editing an inline text box on this or another page and clicked away, commit first
    if (ctrl.editingTextId != null) {
      _commitInlineText();
    }

    if (ctrl.tool == EditorTool.select) {
      final handle = _hitTestHandle(localPos, transform, pageAnnots);
      if (handle != ResizeHandle.none) {
        final single = ctrl.singleSelectedAnnotation;
        if (single != null && !single.locked) {
          setState(() {
            _mode = _ActiveGestureMode.resize;
            _resizeHandle = handle;
            _resizeOriginal = single;
            _resizeDraft = single;
            _downLocal = localPos;
            _downPdf = transform.screenToPdf(localPos);
          });
          return;
        }
      }

      final hit = _hitTestAnnotation(localPos, transform, pageAnnots);
      if (hit != null) {
        final nowMs = DateTime.now().millisecondsSinceEpoch;
        final isDoubleTap =
            _lastTapId == hit.id && (nowMs - _lastTapMs) <= 380;
        _lastTapId = hit.id;
        _lastTapMs = nowMs;

        final additive = _isShiftPressed();
        if (additive) {
          ctrl.selectAnnotation(hit.id, additive: true);
          return;
        }
        if (!ctrl.selectedIds.contains(hit.id)) {
          ctrl.selectAnnotation(hit.id);
        }

        if (isDoubleTap && !hit.locked) {
          if (hit.kind == AnnotationKind.text) {
            ctrl.startEditingText(hit.id);
            return;
          } else if (hit.kind == AnnotationKind.note) {
            unawaited(_openNoteDialog(hit, isNew: false));
            return;
          }
        }

        // Start moving unlocked selected items on this page
        final movable = {
          for (final a in pageAnnots)
            if (ctrl.selectedIds.contains(a.id) && !a.locked) a.id,
        };
        if (movable.isNotEmpty) {
          setState(() {
            _mode = _ActiveGestureMode.move;
            _movingIds
              ..clear()
              ..addAll(movable);
            _moveDeltaScreen = Offset.zero;
            _downLocal = localPos;
            _downPdf = transform.screenToPdf(localPos);
          });
        }
        return;
      }
      return;
    }

    // Active creation tool
    final startPdf = _clampPdfPoint(transform.screenToPdf(localPos), transform);
    _downLocal = localPos;
    _downPdf = startPdf;

    if (ctrl.tool == EditorTool.highlight) {
      _ensurePageTextLoaded();
    }

    if (ctrl.tool == EditorTool.ink) {
      _inkPoints
        ..clear()
        ..add(startPdf);
      setState(() {
        _mode = _ActiveGestureMode.draw;
        _drawDraft = _createDraftAnnotation(
          kind: AnnotationKind.ink,
          bbox: PdfRectBox.fromPoints(_inkPoints),
          points: List.of(_inkPoints),
        );
      });
      return;
    }

    if (ctrl.tool == EditorTool.note || ctrl.tool == EditorTool.image) {
      // Action on pointer up click
      setState(() => _mode = _ActiveGestureMode.draw);
      return;
    }

    setState(() {
      _mode = _ActiveGestureMode.draw;
      _highlightPreviewCharRects = [];
      _drawDraft = _buildShapeDraft(startPdf, startPdf, transform);
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_mode == _ActiveGestureMode.none) return;
    final localPos = event.localPosition;
    final transform = _buildTransform();
    final curPdf = _clampPdfPoint(transform.screenToPdf(localPos), transform);

    if (_mode == _ActiveGestureMode.move && _downLocal != null) {
      setState(() {
        _moveDeltaScreen = localPos - _downLocal!;
      });
      return;
    }

    if (_mode == _ActiveGestureMode.resize &&
        _resizeOriginal != null &&
        _downPdf != null) {
      setState(() {
        _resizeDraft = _computeResizedAnnotation(
          orig: _resizeOriginal!,
          handle: _resizeHandle,
          downPdf: _downPdf!,
          curPdf: curPdf,
          transform: transform,
        );
      });
      return;
    }

    if (_mode == _ActiveGestureMode.draw && _downPdf != null) {
      final ctrl = widget.controller;
      if (ctrl.tool == EditorTool.ink) {
        final prevScreen = transform.pdfToScreen(_inkPoints.last);
        if ((localPos - prevScreen).distance >= 2.0) {
          _inkPoints.add(curPdf);
          setState(() {
            _drawDraft = _createDraftAnnotation(
              kind: AnnotationKind.ink,
              bbox: PdfRectBox.fromPoints(_inkPoints),
              points: List.of(_inkPoints),
            );
          });
        }
        return;
      }

      if (ctrl.tool == EditorTool.note || ctrl.tool == EditorTool.image) {
        return;
      }

      if (ctrl.tool == EditorTool.highlight && _cachedPageText != null) {
        _updateHighlightPreview(_downPdf!, curPdf);
      }

      setState(() {
        _drawDraft = _buildShapeDraft(_downPdf!, curPdf, transform);
      });
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_mode == _ActiveGestureMode.none) return;
    final mode = _mode;
    final downPos = _downLocal;
    final curPos = event.localPosition;
    final downPdf = _downPdf;
    final transform = _buildTransform();
    final ctrl = widget.controller;

    if (mode == _ActiveGestureMode.move && downPos != null && downPdf != null) {
      final movedScreen = (curPos - downPos).distance;
      if (movedScreen >= 2.0) {
        final curPdf = transform.screenToPdf(curPos);
        final dx = curPdf.x - downPdf.x;
        final dy = curPdf.y - downPdf.y;
        final updates = <PdfAnnotationItem>[
          for (final a in ctrl.annotations)
            if (_movingIds.contains(a.id)) _translateAnnotation(a, dx, dy, transform),
        ];
        ctrl.commitAnnotationDrag(updates);
      }
      _resetGestureState();
      return;
    }

    if (mode == _ActiveGestureMode.resize) {
      final orig = _resizeOriginal;
      final draft = _resizeDraft;
      if (orig != null &&
          draft != null &&
          downPos != null &&
          (curPos - downPos).distance >= 1.5) {
        ctrl.commitAnnotationDrag([draft]);
      }
      _resetGestureState();
      return;
    }

    if (mode == _ActiveGestureMode.draw && downPdf != null) {
      final curPdf = _clampPdfPoint(transform.screenToPdf(curPos), transform);
      _finalizeDraw(downPdf, curPdf, transform);
      _resetGestureState();
    }
  }

  void _resetGestureState() {
    if (!mounted) return;
    setState(() {
      _mode = _ActiveGestureMode.none;
      _downLocal = null;
      _downPdf = null;
      _movingIds.clear();
      _moveDeltaScreen = Offset.zero;
      _resizeOriginal = null;
      _resizeDraft = null;
      _resizeHandle = ResizeHandle.none;
      _inkPoints.clear();
      _drawDraft = null;
      _highlightPreviewCharRects = [];
    });
  }

  PdfPoint _clampPdfPoint(PdfPoint pt, PdfScreenTransform t) {
    return PdfPoint(
      pt.x.clamp(0.0, t.rawWidthPt),
      pt.y.clamp(0.0, t.rawHeightPt),
    );
  }

  PdfAnnotationItem _translateAnnotation(
    PdfAnnotationItem ann,
    double dx,
    double dy,
    PdfScreenTransform t,
  ) {
    final bounds = ann.effectiveBounds;
    var clampedDx = dx;
    var clampedDy = dy;
    if (bounds.x + clampedDx < 0) clampedDx = -bounds.x;
    if (bounds.right + clampedDx > t.rawWidthPt) {
      clampedDx = t.rawWidthPt - bounds.right;
    }
    if (bounds.y + clampedDy < 0) clampedDy = -bounds.y;
    if (bounds.top + clampedDy > t.rawHeightPt) {
      clampedDy = t.rawHeightPt - bounds.top;
    }

    return ann.copyWith(
      bbox: PdfRectBox(
        ann.bbox.x + clampedDx,
        ann.bbox.y + clampedDy,
        ann.bbox.w,
        ann.bbox.h,
      ),
      from: ann.from == null
          ? null
          : PdfPoint(ann.from!.x + clampedDx, ann.from!.y + clampedDy),
      to: ann.to == null
          ? null
          : PdfPoint(ann.to!.x + clampedDx, ann.to!.y + clampedDy),
      points: [
        for (final pt in ann.points)
          PdfPoint(pt.x + clampedDx, pt.y + clampedDy),
      ],
    );
  }

  PdfAnnotationItem _computeResizedAnnotation({
    required PdfAnnotationItem orig,
    required ResizeHandle handle,
    required PdfPoint downPdf,
    required PdfPoint curPdf,
    required PdfScreenTransform transform,
  }) {
    if (orig.kind == AnnotationKind.arrow || orig.kind == AnnotationKind.measure) {
      final pFrom = orig.from ?? PdfPoint(orig.bbox.x, orig.bbox.y);
      final pTo = orig.to ?? PdfPoint(orig.bbox.right, orig.bbox.top);
      var nextFrom = pFrom;
      var nextTo = pTo;
      if (handle == ResizeHandle.endpointFrom) {
        nextFrom = _isShiftPressed() ? _snapAngle45(pTo, curPdf) : curPdf;
      } else if (handle == ResizeHandle.endpointTo) {
        nextTo = _isShiftPressed() ? _snapAngle45(pFrom, curPdf) : curPdf;
      }
      return orig.copyWith(
        from: nextFrom,
        to: nextTo,
        bbox: PdfRectBox.fromPoints([nextFrom, nextTo]),
      );
    }

    // Move screen handle delta in display coordinates for intuitive dragging under any rotation
    final origScreen = transform.pdfRectToScreen(orig.effectiveBounds);
    final handleOffset = curPdf;
    final curScreen = transform.pdfToScreen(handleOffset);
    var left = origScreen.left;
    var top = origScreen.top;
    var right = origScreen.right;
    var bottom = origScreen.bottom;

    switch (handle) {
      case ResizeHandle.topLeft:
        left = curScreen.dx;
        top = curScreen.dy;
        break;
      case ResizeHandle.topCenter:
        top = curScreen.dy;
        break;
      case ResizeHandle.topRight:
        right = curScreen.dx;
        top = curScreen.dy;
        break;
      case ResizeHandle.middleLeft:
        left = curScreen.dx;
        break;
      case ResizeHandle.middleRight:
        right = curScreen.dx;
        break;
      case ResizeHandle.bottomLeft:
        left = curScreen.dx;
        bottom = curScreen.dy;
        break;
      case ResizeHandle.bottomCenter:
        bottom = curScreen.dy;
        break;
      case ResizeHandle.bottomRight:
        right = curScreen.dx;
        bottom = curScreen.dy;
        break;
      default:
        break;
    }

    const minPx = 10.0;
    if (right - left < minPx) {
      if (handle == ResizeHandle.topLeft ||
          handle == ResizeHandle.middleLeft ||
          handle == ResizeHandle.bottomLeft) {
        left = right - minPx;
      } else {
        right = left + minPx;
      }
    }
    if (bottom - top < minPx) {
      if (handle == ResizeHandle.topLeft ||
          handle == ResizeHandle.topCenter ||
          handle == ResizeHandle.topRight) {
        top = bottom - minPx;
      } else {
        bottom = top + minPx;
      }
    }

    // Preserve aspect ratio for images / Shift+corner without crushing at page borders
    final isCorner = handle == ResizeHandle.topLeft ||
        handle == ResizeHandle.topRight ||
        handle == ResizeHandle.bottomLeft ||
        handle == ResizeHandle.bottomRight;
    if (isCorner &&
        (orig.kind == AnnotationKind.image || _isShiftPressed()) &&
        origScreen.width > 1 &&
        origScreen.height > 1) {
      final ratio = origScreen.width / origScreen.height;
      final isLeft =
          handle == ResizeHandle.topLeft || handle == ResizeHandle.bottomLeft;
      final isTop =
          handle == ResizeHandle.topLeft || handle == ResizeHandle.topRight;
      final anchorX = isLeft ? right : left;
      final anchorY = isTop ? bottom : top;
      final maxW = isLeft ? anchorX : (transform.displayWidthPx - anchorX);
      final maxH = isTop ? anchorY : (transform.displayHeightPx - anchorY);
      final effectiveMaxW = math.max(1.0, math.min(maxW, maxH * ratio));
      final minW = math.min(effectiveMaxW, math.max(minPx, minPx * ratio));
      final clampedW = (right - left).clamp(minW, effectiveMaxW);
      final clampedH = clampedW / ratio;
      left = isLeft ? (anchorX - clampedW) : anchorX;
      right = isLeft ? anchorX : (anchorX + clampedW);
      top = isTop ? (anchorY - clampedH) : anchorY;
      bottom = isTop ? anchorY : (anchorY + clampedH);
    } else {
      left = left.clamp(0.0, transform.displayWidthPx);
      right = right.clamp(0.0, transform.displayWidthPx);
      top = top.clamp(0.0, transform.displayHeightPx);
      bottom = bottom.clamp(0.0, transform.displayHeightPx);
    }

    final pdfA = transform.screenToPdf(Offset(left, top));
    final pdfB = transform.screenToPdf(Offset(right, bottom));
    final newBox = PdfRectBox.fromPoints([pdfA, pdfB]);

    if (orig.kind == AnnotationKind.ink && orig.points.isNotEmpty) {
      final oldBox = orig.effectiveBounds;
      final oldW = math.max(oldBox.w, 1.0);
      final oldH = math.max(oldBox.h, 1.0);
      final scaledPts = [
        for (final pt in orig.points)
          PdfPoint(
            newBox.x + ((pt.x - oldBox.x) / oldW) * newBox.w,
            newBox.y + ((pt.y - oldBox.y) / oldH) * newBox.h,
          ),
      ];
      return orig.copyWith(bbox: newBox, points: scaledPts);
    }

    return orig.copyWith(bbox: newBox);
  }

  PdfPoint _snapAngle45(PdfPoint anchor, PdfPoint target) {
    final dx = target.x - anchor.x;
    final dy = target.y - anchor.y;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len < 1e-4) return target;
    final angle = math.atan2(dy, dx);
    const step = math.pi / 4.0;
    final snapped = (angle / step).round() * step;
    return PdfPoint(
      anchor.x + len * math.cos(snapped),
      anchor.y + len * math.sin(snapped),
    );
  }

  PdfAnnotationItem _createDraftAnnotation({
    required AnnotationKind kind,
    required PdfRectBox bbox,
    List<PdfPoint> points = const [],
    PdfPoint? from,
    PdfPoint? to,
    String text = '',
    String? stampKey,
    String? label,
    String? colorOverride,
    int rotate = 0,
  }) {
    final defaults = kToolDefaults[kind]!;
    return PdfAnnotationItem(
      id: _uuid.v4(),
      kind: kind,
      page: widget.page.pageNumber - 1,
      bbox: bbox,
      color: colorOverride ?? defaults.colorHex,
      opacity: defaults.opacity,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      thickness: defaults.thickness,
      points: points,
      from: from,
      to: to,
      text: text,
      fontSize: defaults.fontSize,
      fontFamily: widget.controller.defaultFontFamily,
      rotate: rotate,
      stampKey: stampKey ?? widget.controller.stampPreset.key,
      label: label ?? widget.controller.stampPreset.label,
    );
  }

  PdfAnnotationItem? _buildShapeDraft(
    PdfPoint a,
    PdfPoint b,
    PdfScreenTransform t,
  ) {
    final kind = widget.controller.tool.annotationKind;
    if (kind == null) return null;

    if (kind == AnnotationKind.arrow || kind == AnnotationKind.measure) {
      final snappedB = _isShiftPressed() ? _snapAngle45(a, b) : b;
      return _createDraftAnnotation(
        kind: kind,
        bbox: PdfRectBox.fromPoints([a, snappedB]),
        from: a,
        to: snappedB,
      );
    }

    if (kind == AnnotationKind.stamp) {
      final preset = widget.controller.stampPreset;
      final colorHex =
          '#${(preset.colorValue & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
      return _createDraftAnnotation(
        kind: AnnotationKind.stamp,
        bbox: PdfRectBox.fromPoints([a, b]),
        stampKey: preset.key,
        label: preset.label,
        colorOverride: colorHex,
        rotate: t.viewRotationDeg % 360,
      );
    }

    if (kind == AnnotationKind.highlight &&
        _highlightPreviewCharRects.isNotEmpty) {
      final merged = _highlightPreviewCharRects.reduce((x, y) => x.merge(y));
      return _createDraftAnnotation(
        kind: AnnotationKind.highlight,
        bbox: PdfRectBox(merged.left, merged.bottom, merged.width, merged.height),
      );
    }

    return _createDraftAnnotation(
      kind: kind,
      bbox: PdfRectBox.fromPoints([a, b]),
      rotate: kind == AnnotationKind.text ? (t.viewRotationDeg % 360) : 0,
    );
  }

  void _updateHighlightPreview(PdfPoint a, PdfPoint b) {
    final pt = _cachedPageText;
    if (pt == null || pt.charRects.isEmpty) {
      _highlightPreviewCharRects = [];
      return;
    }
    final selBox = PdfRectBox.fromPoints([a, b]);
    final hits = <PdfRect>[];
    for (var i = 0; i < pt.charRects.length; i++) {
      final ch = i < pt.fullText.length ? pt.fullText[i] : '';
      if (ch == '\r' || ch == '\n') continue;
      final r = pt.charRects[i];
      if (r.isEmpty) continue;
      final overlapX = r.right >= selBox.x && r.left <= selBox.right;
      final overlapY = r.top >= selBox.y - 1.5 && r.bottom <= selBox.top + 1.5;
      if (overlapX && overlapY) {
        hits.add(r);
      }
    }
    _highlightPreviewCharRects = hits;
  }

  List<PdfRectBox> _groupCharRectsIntoLines(
    List<PdfRect> rects,
    PdfScreenTransform t,
  ) {
    if (rects.isEmpty) return const [];
    final screenRects = [
      for (final r in rects)
        t.pdfRectToScreen(PdfRectBox(r.left, r.bottom, r.width, r.height)),
    ]..sort((a, b) => a.center.dy.compareTo(b.center.dy));

    final lines = <List<Rect>>[];
    for (final r in screenRects) {
      final cy = r.center.dy;
      final h = math.max(r.height, 4.0);
      if (lines.isEmpty) {
        lines.add([r]);
        continue;
      }
      final last = lines.last;
      final avgCy =
          last.fold<double>(0, (s, x) => s + x.center.dy) / last.length;
      if ((cy - avgCy).abs() <= h * 0.65) {
        last.add(r);
      } else {
        lines.add([r]);
      }
    }
    return [
      for (final line in lines)
        () {
          var left = line.first.left;
          var top = line.first.top;
          var right = line.first.right;
          var bottom = line.first.bottom;
          for (final r in line.skip(1)) {
            if (r.left < left) left = r.left;
            if (r.top < top) top = r.top;
            if (r.right > right) right = r.right;
            if (r.bottom > bottom) bottom = r.bottom;
          }
          final p1 = t.screenToPdf(Offset(left, top));
          final p2 = t.screenToPdf(Offset(right, bottom));
          return PdfRectBox.fromPoints([p1, p2]);
        }(),
    ];
  }

  void _finalizeDraw(PdfPoint a, PdfPoint b, PdfScreenTransform t) {
    final ctrl = widget.controller;
    final kind = ctrl.tool.annotationKind;
    if (kind == null) return;

    switch (kind) {
      case AnnotationKind.ink:
        if (_inkPoints.length >= 2) {
          final simplified = simplifyPoints(_inkPoints, tolerance: 0.8);
          final box = PdfRectBox.fromPoints(simplified);
          if (box.w >= 2 || box.h >= 2) {
            ctrl.addAnnotation(
              _createDraftAnnotation(
                kind: AnnotationKind.ink,
                bbox: box,
                points: simplified,
              ),
            );
          }
        }
        break;

      case AnnotationKind.highlight:
        if (_highlightPreviewCharRects.isEmpty && _cachedPageText != null) {
          _updateHighlightPreview(a, b);
        }
        if (_highlightPreviewCharRects.isNotEmpty) {
          final lineBoxes =
              _groupCharRectsIntoLines(_highlightPreviewCharRects, t);
          if (lineBoxes.length == 1) {
            ctrl.addAnnotation(
              _createDraftAnnotation(
                kind: AnnotationKind.highlight,
                bbox: lineBoxes.first,
              ),
            );
          } else {
            ctrl.beginAnnotBatch();
            for (final box in lineBoxes) {
              ctrl.addAnnotation(
                _createDraftAnnotation(
                  kind: AnnotationKind.highlight,
                  bbox: box,
                ),
                selectAfter: box == lineBoxes.last,
                recordHistory: false,
              );
            }
            ctrl.commitAnnotBatch();
          }
        } else {
          final box = PdfRectBox.fromPoints([a, b]);
          if (box.w >= 6 && box.h >= 4) {
            ctrl.addAnnotation(
              _createDraftAnnotation(kind: AnnotationKind.highlight, bbox: box),
            );
          }
        }
        break;

      case AnnotationKind.rect:
      case AnnotationKind.ellipse:
        var box = PdfRectBox.fromPoints([a, b]);
        if (box.w < 4 && box.h < 4) {
          box = _centeredBox(a, 76, 48, t);
        }
        if (box.w >= 4 && box.h >= 4) {
          ctrl.addAnnotation(_createDraftAnnotation(kind: kind, bbox: box));
        }
        break;

      case AnnotationKind.arrow:
      case AnnotationKind.measure:
        final endPt = _isShiftPressed() ? _snapAngle45(a, b) : b;
        if (hypot(endPt.x - a.x, endPt.y - a.y) >= 4.0) {
          ctrl.addAnnotation(
            _createDraftAnnotation(
              kind: kind,
              bbox: PdfRectBox.fromPoints([a, endPt]),
              from: a,
              to: endPt,
            ),
          );
        }
        break;

      case AnnotationKind.text:
        var box = PdfRectBox.fromPoints([a, b]);
        final oddViewRot = ((t.viewRotationDeg ~/ 90) % 4 + 4) % 4;
        if (box.w < 24 || box.h < 18) {
          final defRun = math.min(
            180.0,
            (oddViewRot.isOdd ? t.rawHeightPt : t.rawWidthPt) * 0.45,
          );
          const defStack = 34.0;
          final w = oddViewRot.isOdd ? defStack : defRun;
          final h = oddViewRot.isOdd ? defRun : defStack;
          box = PdfRectBox(
            (a.x - w * 0.1).clamp(0.0, math.max(0.0, t.rawWidthPt - w)),
            (a.y - h * 0.5).clamp(0.0, math.max(0.0, t.rawHeightPt - h)),
            w,
            h,
          );
        }
        final created = _createDraftAnnotation(
          kind: AnnotationKind.text,
          bbox: box,
          text: '',
          rotate: t.viewRotationDeg % 360,
        );
        ctrl.addAnnotation(created);
        ctrl.startEditingText(created.id);
        break;

      case AnnotationKind.note:
        final box = PdfRectBox(
          (a.x - 11).clamp(0.0, math.max(0.0, t.rawWidthPt - 22)),
          (a.y - 11).clamp(0.0, math.max(0.0, t.rawHeightPt - 22)),
          22,
          22,
        );
        final created = _createDraftAnnotation(
          kind: AnnotationKind.note,
          bbox: box,
          text: '',
        );
        unawaited(_openNoteDialog(created, isNew: true));
        break;

      case AnnotationKind.stamp:
        final preset = ctrl.stampPreset;
        final colorHex =
            '#${(preset.colorValue & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
        var box = PdfRectBox.fromPoints([a, b]);
        final rotSteps = ((t.viewRotationDeg ~/ 90) % 4 + 4) % 4;
        if (box.w < 16 || box.h < 12) {
          box = _centeredBox(
            a,
            rotSteps.isOdd ? 46 : 132,
            rotSteps.isOdd ? 132 : 46,
            t,
          );
        }
        ctrl.addAnnotation(
          _createDraftAnnotation(
            kind: AnnotationKind.stamp,
            bbox: box,
            stampKey: preset.key,
            label: preset.label,
            colorOverride: colorHex,
            rotate: t.viewRotationDeg % 360,
          ),
        );
        break;

      case AnnotationKind.image:
        unawaited(_pickAndInsertImage(a, t));
        break;
    }
  }

  PdfRectBox _centeredBox(
    PdfPoint center,
    double w,
    double h,
    PdfScreenTransform t,
  ) {
    final cw = math.min(w, t.rawWidthPt);
    final ch = math.min(h, t.rawHeightPt);
    return PdfRectBox(
      (center.x - cw / 2).clamp(0.0, math.max(0.0, t.rawWidthPt - cw)),
      (center.y - ch / 2).clamp(0.0, math.max(0.0, t.rawHeightPt - ch)),
      cw,
      ch,
    );
  }

  Future<void> _pickAndInsertImage(
    PdfPoint anchor,
    PdfScreenTransform t,
  ) async {
    final picked = await FilePicker.pickFile(
      dialogTitle: '选择插入的图片',
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg'],
    );
    final path = picked?.path;
    if (path == null) return;

    final ctrl = widget.controller;
    final imported = await ctrl.importImageFile(path);
    if (imported == null) {
      ctrl.showToast('无法解码该图片文件', isError: true);
      return;
    }

    final rotSteps = ((t.viewRotationDeg ~/ 90) % 4 + 4) % 4;
    final swapped = rotSteps.isOdd;
    final visMaxW = math.min(220.0, (swapped ? t.rawHeightPt : t.rawWidthPt) * 0.45);
    final visMaxH = (swapped ? t.rawWidthPt : t.rawHeightPt) * 0.6;
    final ratio = imported.height / math.max(imported.width, 1);
    var visW = math.min(visMaxW, imported.width * 72.0 / 96.0);
    if (visW < 36) visW = math.min(visMaxW, 80.0);
    var visH = visW * ratio;
    if (visH > visMaxH) {
      visH = visMaxH;
      visW = visH / math.max(ratio, 0.05);
    }

    final box = _centeredBox(
      anchor,
      swapped ? visH : visW,
      swapped ? visW : visH,
      t,
    );
    final defaults = kToolDefaults[AnnotationKind.image]!;
    ctrl.addAnnotation(
      PdfAnnotationItem(
        id: _uuid.v4(),
        kind: AnnotationKind.image,
        page: widget.page.pageNumber - 1,
        bbox: box,
        color: defaults.colorHex,
        opacity: defaults.opacity,
        rotate: t.viewRotationDeg % 360,
        createdAt: DateTime.now().millisecondsSinceEpoch,
        imgId: imported.imgId,
        refPath: path,
      ),
    );
  }

  Future<void> _openNoteDialog(
    PdfAnnotationItem note, {
    required bool isNew,
  }) async {
    if (!mounted) return;
    final ctrl = widget.controller;
    final textCtrl = TextEditingController(text: note.text);
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => DialogControllersHost(
        controllers: [textCtrl],
        builder: (ctx) {
          final c = ctx.appColors;
          return AlertDialog(
            title: DesktopDialogHeader(
              icon: Icons.sticky_note_2_outlined,
              iconColor: AppTheme.warning,
              iconBackground: const Color(0xFFF59E0B).withValues(alpha: 0.14),
              title: '便签内容',
              subtitle: '双击页面便签可随时修改备注内容',
              onClose: () => Navigator.of(ctx).pop(null),
            ),
            content: SizedBox(
              width: 390,
              child: TextField(
                controller: textCtrl,
                autofocus: true,
                maxLines: 6,
                style: const TextStyle(fontSize: AppTypography.body),
                decoration: AppTheme.compactInputDecoration(
                  c,
                  hintText: '输入便签备注...',
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(textCtrl.text),
                child: const Text('确定'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null) {
      return;
    }
    if (isNew) {
      ctrl.addAnnotation(note.copyWith(text: result));
    } else {
      ctrl.patchAnnotation(note.id, (cur) => cur.copyWith(text: result));
    }
  }

  static double _distPointToSegment(Offset p, Offset a, Offset b) {
    final vx = b.dx - a.dx;
    final vy = b.dy - a.dy;
    final lenSq = vx * vx + vy * vy;
    if (lenSq < 1e-6) return (p - a).distance;
    final t = (((p.dx - a.dx) * vx + (p.dy - a.dy) * vy) / lenSq).clamp(0.0, 1.0);
    final proj = Offset(a.dx + t * vx, a.dy + t * vy);
    return (p - proj).distance;
  }

  Widget? _buildInlineEditor(
    PdfScreenTransform transform,
    List<PdfAnnotationItem> pageAnnots,
  ) {
    final editingId = widget.controller.editingTextId;
    if (editingId == null) {
      _boundInlineId = null;
      return null;
    }
    final target = pageAnnots.where((a) => a.id == editingId).firstOrNull;
    if (target == null || target.kind != AnnotationKind.text) {
      return null;
    }
    if (_boundInlineId != editingId) {
      _boundInlineId = editingId;
      _inlineTextCtrl.text = target.text;
      _inlineTextCtrl.selection = TextSelection.fromPosition(
        TextPosition(offset: _inlineTextCtrl.text.length),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _boundInlineId == editingId) {
          _inlineFocus.requestFocus();
        }
      });
    }

    final frame = textBlockFrame(target.bbox, target.rotate);
    final originScreen = transform.pdfToScreen(frame.origin);
    final width = math.max(frame.run * transform.scale, 130.0 * transform.scale);
    final height = math.max(
      frame.stack * transform.scale,
      target.fontSize * transform.scale * 1.6,
    );
    final fontFamily =
        (target.fontFamily != null && target.fontFamily!.isNotEmpty)
            ? target.fontFamily
            : null;
    final screenAngleDeg =
        ((transform.viewRotationDeg - target.rotate) % 360 + 360) % 360;

    return Positioned(
      left: originScreen.dx,
      top: originScreen.dy,
      width: width,
      height: height,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) {
          widget.pointerLatch.consumedByOverlay = true;
        },
        child: Transform.rotate(
          alignment: Alignment.topLeft,
          angle: screenAngleDeg * math.pi / 180.0,
          child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _commitInlineText,
            const SingleActivator(LogicalKeyboardKey.enter, control: true):
                _commitInlineText,
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.92),
              border: Border.all(color: const Color(0xFF2563EB), width: 1.5),
              borderRadius: BorderRadius.circular(3),
            ),
            child: TextField(
              controller: _inlineTextCtrl,
              focusNode: _inlineFocus,
              maxLines: null,
              keyboardType: TextInputType.multiline,
              style: TextStyle(
                color: hexToColor(target.color, opacity: target.opacity),
                fontSize: target.fontSize * transform.scale,
                fontFamily: fontFamily,
                height: 1.2,
              ),
              decoration: const InputDecoration(
                isCollapsed: true,
                filled: false,
                visualDensity: VisualDensity.standard,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: '输入文字（Ctrl+Enter 完成）',
                hintStyle: TextStyle(
                  fontSize: AppTypography.body,
                  color: Colors.black38,
                ),
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final transform = _buildTransform();
    final pageAnnots = _pageAnnotations();
    final editingId = _resizeDraft?.id ?? ctrl.editingTextId;
    final draft = _resizeDraft ?? _drawDraft;
    final inlineEditor = _buildInlineEditor(transform, pageAnnots);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: _SelectiveOverlayHitBox(
            allowPassthrough: widget.spaceDown,
            shouldInterceptPoint: _shouldInterceptPoint,
            child: MouseRegion(
              cursor: _hoverCursor,
              onHover: (ev) => _updateHoverCursor(ev.localPosition),
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: (_) => _resetGestureState(),
                child: RepaintBoundary(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: AnnotationOverlayPainter(
                      transform: transform,
                      annotations: pageAnnots,
                      selectedIds: ctrl.selectedIds,
                      loadedImages: ctrl.loadedImages,
                      movingIds: _movingIds,
                      moveOffsetScreen: _moveDeltaScreen,
                      draftAnnotation: draft,
                      editingAnnotationId: editingId,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        ?inlineEditor,
      ],
    );
  }
}
