import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../theme/app_theme.dart';

/// 桌面端 PDF 画布滚动条（支持右侧纵向 + 底部横向，支持拖拽滑块与点击轨道快速跳转，拖拽时显示当前页码气泡）
class PdfDesktopScrollbars extends StatelessWidget {
  const PdfDesktopScrollbars({
    super.key,
    required this.viewerController,
    required this.pageCount,
    this.onPointerInteracting,
  });

  final PdfViewerController viewerController;
  final int pageCount;
  final VoidCallback? onPointerInteracting;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewerController,
      builder: (context, _) {
        if (!viewerController.isReady) return const SizedBox.shrink();

        final view = viewerController.visibleRect;
        final all = viewerController.documentSize;
        final boundaryMargin = viewerController.params.boundaryMargin;

        final effectiveDocHeight =
            boundaryMargin == null || boundaryMargin.vertical.isInfinite
                ? all.height
                : all.height + boundaryMargin.vertical;
        final effectiveDocWidth =
            boundaryMargin == null || boundaryMargin.horizontal.isInfinite
                ? all.width
                : all.width + boundaryMargin.horizontal;

        final showVertical = effectiveDocHeight > view.height + 1.0;
        final showHorizontal = effectiveDocWidth > view.width + 1.0;

        if (!showVertical && !showHorizontal) return const SizedBox.shrink();

        return Stack(
          fit: StackFit.expand,
          children: [
            if (showVertical)
              Positioned(
                top: 4,
                bottom: showHorizontal ? 18 : 4,
                right: 2,
                child: _VerticalPdfScrollbar(
                  key: const Key('pdf_vertical_scrollbar'),
                  controller: viewerController,
                  pageCount: pageCount,
                  effectiveDocHeight: effectiveDocHeight,
                  minScrollY:
                      boundaryMargin == null || boundaryMargin.vertical.isInfinite
                          ? 0.0
                          : -boundaryMargin.top,
                  onPointerInteracting: onPointerInteracting,
                ),
              ),
            if (showHorizontal)
              Positioned(
                left: 4,
                right: showVertical ? 18 : 4,
                bottom: 2,
                child: _HorizontalPdfScrollbar(
                  key: const Key('pdf_horizontal_scrollbar'),
                  controller: viewerController,
                  effectiveDocWidth: effectiveDocWidth,
                  minScrollX:
                      boundaryMargin == null || boundaryMargin.horizontal.isInfinite
                          ? 0.0
                          : -boundaryMargin.left,
                  onPointerInteracting: onPointerInteracting,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _VerticalPdfScrollbar extends StatefulWidget {
  const _VerticalPdfScrollbar({
    super.key,
    required this.controller,
    required this.pageCount,
    required this.effectiveDocHeight,
    required this.minScrollY,
    this.onPointerInteracting,
  });

  final PdfViewerController controller;
  final int pageCount;
  final double effectiveDocHeight;
  final double minScrollY;
  final VoidCallback? onPointerInteracting;

  @override
  State<_VerticalPdfScrollbar> createState() => _VerticalPdfScrollbarState();
}

class _VerticalPdfScrollbarState extends State<_VerticalPdfScrollbar> {
  static const double _trackWidth = 16.0;
  static const double _minThumbHeight = 36.0;

  bool _hovered = false;
  bool _dragging = false;
  int? _activePointer;
  double _dragGrabOffset = 0.0;

  void _scrollToFraction(double fraction, double scrollRange) {
    final clamped = fraction.clamp(0.0, 1.0);
    final m = widget.controller.value.clone();
    m.y = -(clamped * scrollRange + widget.minScrollY);
    unawaited(widget.controller.goTo(m, duration: Duration.zero));
  }

  void _endPointerDrag(int pointer) {
    if (_activePointer != pointer) return;
    _activePointer = null;
    if (_dragging && mounted) {
      setState(() => _dragging = false);
    }
    widget.controller.endUserScroll();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final view = widget.controller.visibleRect;
    final scrollRange =
        math.max(1.0, widget.effectiveDocHeight - view.height);
    final currentFraction =
        ((-widget.controller.value.y - widget.minScrollY) / scrollRange)
            .clamp(0.0, 1.0);
    final curPage =
        (widget.controller.pageNumber ?? 1).clamp(1, math.max(1, widget.pageCount));

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackH = constraints.maxHeight;
        if (trackH <= _minThumbHeight + 4) return const SizedBox.shrink();

        final ratio = (view.height / widget.effectiveDocHeight).clamp(0.0, 1.0);
        final thumbH = (trackH * ratio)
            .clamp(_minThumbHeight, math.max(_minThumbHeight, trackH - 12))
            .toDouble();
        final travel = math.max(1.0, trackH - thumbH);
        final thumbTop = currentFraction * travel;
        final active = _hovered || _dragging;

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 拖拽时在滑块左侧显示浮动页码提示气泡
            if (_dragging)
              Padding(
                padding: EdgeInsets.only(
                  top: (thumbTop + thumbH / 2 - 14)
                      .clamp(0.0, math.max(0.0, trackH - 28)),
                  right: 8,
                ),
                child: IgnorePointer(
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.elevatedBg.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: c.accent.withValues(alpha: 0.45)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      '第 $curPage / ${math.max(1, widget.pageCount)} 页',
                      style: TextStyle(
                        fontSize: AppTypography.caption,
                        fontWeight: FontWeight.w600,
                        color: c.accent,
                      ),
                    ),
                  ),
                ),
              ),
            Semantics(
              label: 'PDF 纵向滚动条',
              child: MouseRegion(
                cursor: _dragging
                    ? SystemMouseCursors.grabbing
                    : SystemMouseCursors.click,
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) {
                    if (event.kind == PointerDeviceKind.mouse &&
                        (event.buttons & kPrimaryMouseButton) == 0) {
                      return;
                    }
                    widget.onPointerInteracting?.call();
                    _activePointer = event.pointer;
                    final y = event.localPosition.dy;
                    final insideThumb =
                        y >= thumbTop && y <= thumbTop + thumbH;
                    _dragGrabOffset =
                        insideThumb ? (y - thumbTop) : thumbH / 2;
                    setState(() => _dragging = true);
                    widget.controller.beginUserScroll();
                    if (!insideThumb) {
                      final targetTop = (y - thumbH / 2).clamp(0.0, travel);
                      _scrollToFraction(targetTop / travel, scrollRange);
                    }
                  },
                  onPointerMove: (event) {
                    if (_activePointer != event.pointer) return;
                    final nextTop =
                        (event.localPosition.dy - _dragGrabOffset)
                            .clamp(0.0, travel);
                    _scrollToFraction(nextTop / travel, scrollRange);
                  },
                  onPointerUp: (event) => _endPointerDrag(event.pointer),
                  onPointerCancel: (event) => _endPointerDrag(event.pointer),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) {},
                    onVerticalDragStart: (_) {},
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: _trackWidth,
                      height: trackH,
                      decoration: BoxDecoration(
                        color: active
                            ? c.surfaceBg.withValues(alpha: 0.55)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            top: thumbTop,
                            right: 3,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              width: active ? 9.0 : 6.0,
                              height: thumbH,
                              decoration: BoxDecoration(
                                color: _dragging
                                    ? c.accent
                                    : _hovered
                                        ? c.mutedText.withValues(alpha: 0.80)
                                        : c.mutedText.withValues(alpha: 0.48),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _HorizontalPdfScrollbar extends StatefulWidget {
  const _HorizontalPdfScrollbar({
    super.key,
    required this.controller,
    required this.effectiveDocWidth,
    required this.minScrollX,
    this.onPointerInteracting,
  });

  final PdfViewerController controller;
  final double effectiveDocWidth;
  final double minScrollX;
  final VoidCallback? onPointerInteracting;

  @override
  State<_HorizontalPdfScrollbar> createState() =>
      _HorizontalPdfScrollbarState();
}

class _HorizontalPdfScrollbarState extends State<_HorizontalPdfScrollbar> {
  static const double _trackHeight = 16.0;
  static const double _minThumbWidth = 36.0;

  bool _hovered = false;
  bool _dragging = false;
  int? _activePointer;
  double _dragGrabOffset = 0.0;

  void _scrollToFraction(double fraction, double scrollRange) {
    final clamped = fraction.clamp(0.0, 1.0);
    final m = widget.controller.value.clone();
    m.x = -(clamped * scrollRange + widget.minScrollX);
    unawaited(widget.controller.goTo(m, duration: Duration.zero));
  }

  void _endPointerDrag(int pointer) {
    if (_activePointer != pointer) return;
    _activePointer = null;
    if (_dragging && mounted) {
      setState(() => _dragging = false);
    }
    widget.controller.endUserScroll();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final view = widget.controller.visibleRect;
    final scrollRange =
        math.max(1.0, widget.effectiveDocWidth - view.width);
    final currentFraction =
        ((-widget.controller.value.x - widget.minScrollX) / scrollRange)
            .clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackW = constraints.maxWidth;
        if (trackW <= _minThumbWidth + 4) return const SizedBox.shrink();

        final ratio = (view.width / widget.effectiveDocWidth).clamp(0.0, 1.0);
        final thumbW = (trackW * ratio)
            .clamp(_minThumbWidth, math.max(_minThumbWidth, trackW - 12))
            .toDouble();
        final travel = math.max(1.0, trackW - thumbW);
        final thumbLeft = currentFraction * travel;
        final active = _hovered || _dragging;

        return Semantics(
          label: 'PDF 横向滚动条',
          child: MouseRegion(
            cursor: _dragging
                ? SystemMouseCursors.grabbing
                : SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) {
                if (event.kind == PointerDeviceKind.mouse &&
                    (event.buttons & kPrimaryMouseButton) == 0) {
                  return;
                }
                widget.onPointerInteracting?.call();
                _activePointer = event.pointer;
                final x = event.localPosition.dx;
                final insideThumb =
                    x >= thumbLeft && x <= thumbLeft + thumbW;
                _dragGrabOffset =
                    insideThumb ? (x - thumbLeft) : thumbW / 2;
                setState(() => _dragging = true);
                widget.controller.beginUserScroll();
                if (!insideThumb) {
                  final targetLeft = (x - thumbW / 2).clamp(0.0, travel);
                  _scrollToFraction(targetLeft / travel, scrollRange);
                }
              },
              onPointerMove: (event) {
                if (_activePointer != event.pointer) return;
                final nextLeft =
                    (event.localPosition.dx - _dragGrabOffset)
                        .clamp(0.0, travel);
                _scrollToFraction(nextLeft / travel, scrollRange);
              },
              onPointerUp: (event) => _endPointerDrag(event.pointer),
              onPointerCancel: (event) => _endPointerDrag(event.pointer),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (_) {},
                onHorizontalDragStart: (_) {},
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  width: trackW,
                  height: _trackHeight,
                  decoration: BoxDecoration(
                    color: active
                        ? c.surfaceBg.withValues(alpha: 0.55)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        left: thumbLeft,
                        bottom: 3,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 100),
                          width: thumbW,
                          height: active ? 9.0 : 6.0,
                          decoration: BoxDecoration(
                            color: _dragging
                                ? c.accent
                                : _hovered
                                    ? c.mutedText.withValues(alpha: 0.80)
                                    : c.mutedText.withValues(alpha: 0.48),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ],
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
