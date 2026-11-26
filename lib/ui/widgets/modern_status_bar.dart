import 'package:flutter/material.dart';

import '../../models/annotation_model.dart';
import '../../state/editor_controller.dart';
import '../theme/app_theme.dart';
import 'hover_feedback.dart';

class ModernStatusBar extends StatefulWidget {
  const ModernStatusBar({
    super.key,
    required this.controller,
    required this.onOpenProblems,
  });

  final EditorController controller;
  final VoidCallback onOpenProblems;

  @override
  State<ModernStatusBar> createState() => _ModernStatusBarState();
}

class _ModernStatusBarState extends State<ModernStatusBar> {
  final TextEditingController _pageInput = TextEditingController();
  final TextEditingController _zoomInput = TextEditingController();
  final FocusNode _pageFocus = FocusNode();
  final FocusNode _zoomFocus = FocusNode();
  bool _editingPage = false;
  bool _editingZoom = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncFromController);
    _pageFocus.addListener(_onPageFocusChange);
    _zoomFocus.addListener(_onZoomFocusChange);
    _syncFromController();
  }

  @override
  void didUpdateWidget(covariant ModernStatusBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncFromController);
      widget.controller.addListener(_syncFromController);
      _syncFromController();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    _pageFocus.removeListener(_onPageFocusChange);
    _zoomFocus.removeListener(_onZoomFocusChange);
    _pageFocus.dispose();
    _zoomFocus.dispose();
    _pageInput.dispose();
    _zoomInput.dispose();
    super.dispose();
  }

  void _onPageFocusChange() {
    if (_pageFocus.hasFocus) {
      _editingPage = true;
    } else if (_editingPage) {
      _commitPage();
    }
  }

  void _onZoomFocusChange() {
    if (_zoomFocus.hasFocus) {
      _editingZoom = true;
    } else if (_editingZoom) {
      _commitZoom();
    }
  }

  void _syncFromController() {
    final ctrl = widget.controller;
    if (!_editingPage && !_pageFocus.hasFocus) {
      final targetPageText = ctrl.hasDocument ? '${ctrl.currentPage}' : '';
      if (_pageInput.text != targetPageText) {
        _pageInput.text = targetPageText;
      }
    }
    if (!_editingZoom && !_zoomFocus.hasFocus) {
      final zoomPct = (ctrl.scale * 100).round();
      final targetZoomText = '$zoomPct%';
      if (_zoomInput.text != targetZoomText) {
        _zoomInput.text = targetZoomText;
      }
    }
  }

  void _commitPage() {
    final v = int.tryParse(_pageInput.text.trim());
    if (v != null && v >= 1 && v <= widget.controller.pageCount) {
      widget.controller.jumpToPage(v);
    }
    setState(() => _editingPage = false);
    _syncFromController();
  }

  void _commitZoom() {
    final raw = _zoomInput.text.replaceAll('%', '').trim();
    final v = double.tryParse(raw);
    if (v != null && v >= 25 && v <= 400) {
      widget.controller.setZoomPercent(v);
    }
    setState(() => _editingZoom = false);
    _syncFromController();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final c = context.appColors;
    final hasDoc = ctrl.hasDocument;
    final zoomPct = (ctrl.scale * 100).round();

    return Material(
      color: c.surfaceBg,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: Row(
          children: [
            // 左侧：状态指示与问题面板入口
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (ctrl.busyMessage != null) ...[
                      SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: c.accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 240),
                        child: Text(
                          ctrl.busyMessage!,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppTypography.body,
                            color: c.accent,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ] else if (hasDoc) ...[
                      Text(
                        '共 ${ctrl.pageCount} 页',
                        style: TextStyle(
                          fontSize: AppTypography.body,
                          color: c.mutedText,
                        ),
                      ),
                      const SizedBox(width: 10),
                    ] else ...[
                      Text(
                        '就绪',
                        style: TextStyle(
                          fontSize: AppTypography.body,
                          color: c.mutedText,
                        ),
                      ),
                    ],
                    if (ctrl.dirty) ...[
                      const _StatusChip(
                        label: '未保存',
                        color: Color(0xFFD97706),
                        bg: Color(0x22F59E0B),
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (ctrl.encrypted) ...[
                      _StatusChip(
                        label: '加密文档',
                        color: c.mutedText,
                        bg: c.subtleFill,
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (ctrl.problems.isNotEmpty)
                      HoverStateBuilder(
                        enabled: true,
                        onTap: widget.onOpenProblems,
                        builder: (context, hovered, pressed) => AnimatedContainer(
                          duration: const Duration(milliseconds: 100),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: hovered
                                  ? const Color(0xFFDC2626)
                                      .withValues(alpha: 0.65)
                                  : Colors.transparent,
                            ),
                          ),
                          child: _StatusChip(
                            label: '问题 (${ctrl.problems.length})',
                            color: const Color(0xFFDC2626),
                            bg: hovered
                                ? const Color(0x36EF4444)
                                : const Color(0x20EF4444),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            if (hasDoc) ...[
              const SizedBox(width: 8),
              Flexible(
                flex: 0,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 阅读历史 后退 / 前进
                      _IconStep(
                        icon: Icons.arrow_back_rounded,
                        tooltip: '后退 (Alt+←)',
                        enabled: ctrl.canGoBack,
                        onTap: ctrl.goBack,
                      ),
                      const SizedBox(width: 4),
                      _IconStep(
                        icon: Icons.arrow_forward_rounded,
                        tooltip: '前进 (Alt+→)',
                        enabled: ctrl.canGoForward,
                        onTap: ctrl.goForward,
                      ),
                      _StatusDivider(color: c.border),

                      // 翻页与页码输入
                      _IconStep(
                        icon: Icons.chevron_left_rounded,
                        tooltip: '上一页',
                        enabled: ctrl.currentPage > 1,
                        onTap: () => ctrl.stepPage(-1),
                      ),
                      const SizedBox(width: 4),
                      _CompactBarField(
                        width: 50,
                        controller: _pageInput,
                        focusNode: _pageFocus,
                        onBeginEdit: () => _editingPage = true,
                        onCommit: _commitPage,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          '/ ${ctrl.pageCount}',
                          style: TextStyle(
                            fontSize: AppTypography.body,
                            color: c.mutedText,
                          ),
                        ),
                      ),
                      _IconStep(
                        icon: Icons.chevron_right_rounded,
                        tooltip: '下一页',
                        enabled: ctrl.currentPage < ctrl.pageCount,
                        onTap: () => ctrl.stepPage(1),
                      ),
                      _StatusDivider(color: c.border),

                      // 页面快速物理旋转
                      _IconStep(
                        icon: Icons.rotate_90_degrees_ccw_rounded,
                        tooltip: '左旋当前页 90°',
                        enabled: !ctrl.encrypted && !ctrl.isBusy,
                        onTap: () =>
                            ctrl.rotatePages({ctrl.currentPage - 1: -90}),
                      ),
                      const SizedBox(width: 4),
                      _IconStep(
                        icon: Icons.rotate_90_degrees_cw_rounded,
                        tooltip: '右旋当前页 90°',
                        enabled: !ctrl.encrypted && !ctrl.isBusy,
                        onTap: () =>
                            ctrl.rotatePages({ctrl.currentPage - 1: 90}),
                      ),
                      _StatusDivider(color: c.border),

                      // 阅读视图切换（连续 / 单页 / 双页）
                      Container(
                        height: 32,
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: c.subtleFill,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: c.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (int i = 0; i < ReadingViewMode.values.length; i++) ...[
                              if (i > 0) const SizedBox(width: 3),
                              DesktopHoverContainer(
                                tooltip: ReadingViewMode.values[i].tooltip,
                                active: ctrl.viewMode == ReadingViewMode.values[i],
                                onTap: () =>
                                    ctrl.setViewMode(ReadingViewMode.values[i]),
                                borderRadius: 5,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                activeColor: c.surfaceBg,
                                activeBorderColor: c.border,
                                hoverColor: c.hoverFill,
                                hoverBorderColor: c.hoverBorder,
                                pressedColor: c.accentSoft,
                                scaleOnPress: 0.96,
                                builder: (context, hovered, pressed) => Center(
                                  child: Text(
                                    ReadingViewMode.values[i].label,
                                    style: TextStyle(
                                      fontSize: AppTypography.body,
                                      height: 1.1,
                                      fontWeight: (ctrl.viewMode ==
                                                  ReadingViewMode.values[i] ||
                                              hovered)
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: (ctrl.viewMode ==
                                                  ReadingViewMode.values[i] ||
                                              hovered)
                                          ? c.accent
                                          : c.mutedText,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      _StatusDivider(color: c.border),

                      // 缩放控制
                      _IconStep(
                        icon: Icons.remove_rounded,
                        tooltip: '缩小 (Ctrl+-)',
                        enabled: zoomPct > 25,
                        onTap: () => ctrl.setZoomPercent(
                          (zoomPct - 15).clamp(25, 400).toDouble(),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _CompactBarField(
                        width: 62,
                        controller: _zoomInput,
                        focusNode: _zoomFocus,
                        onBeginEdit: () => _editingZoom = true,
                        onCommit: _commitZoom,
                      ),
                      const SizedBox(width: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: PopupMenuButton<double>(
                          tooltip: '常用缩放比例 (实际大小 Ctrl+0)',
                          onSelected: ctrl.setZoomPercent,
                          itemBuilder: (_) => [
                            for (final pct in [
                              50.0,
                              75.0,
                              100.0,
                              125.0,
                              150.0,
                              200.0,
                              300.0
                            ])
                              PopupMenuItem(
                                value: pct,
                                child: Text(
                                  '${pct.toInt()}%',
                                  style: TextStyle(
                                    fontSize: AppTypography.body,
                                    fontWeight: zoomPct == pct.toInt()
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                          ],
                          child: DesktopHoverContainer(
                            enabled: true,
                            width: 24,
                            height: 28,
                            borderRadius: 6,
                            hoverColor: c.hoverFill,
                            hoverBorderColor: c.hoverBorder,
                            pressedColor: c.accentSoft,
                            builder: (context, hovered, pressed) => Center(
                              child: Icon(
                                Icons.arrow_drop_down,
                                size: 18,
                                color: hovered
                                    ? c.accent
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _IconStep(
                        icon: Icons.add_rounded,
                        tooltip: '放大 (Ctrl+=)',
                        enabled: zoomPct < 400,
                        onTap: () => ctrl.setZoomPercent(
                          (zoomPct + 15).clamp(25, 400).toDouble(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _IconStep(
                        icon: Icons.fit_screen_outlined,
                        tooltip: '适合页面',
                        onTap: ctrl.fitPage,
                      ),
                      const SizedBox(width: 4),
                      _IconStep(
                        icon: Icons.width_normal_rounded,
                        tooltip: '适合宽度',
                        onTap: ctrl.fitWidth,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusDivider extends StatelessWidget {
  const _StatusDivider({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 7),
      color: color,
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.color,
    required this.bg,
  });

  final String label;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: AppTypography.body,
          height: 1.15,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _IconStep extends StatelessWidget {
  const _IconStep({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return DesktopHoverContainer(
      tooltip: tooltip,
      enabled: enabled,
      onTap: enabled ? onTap : null,
      width: 28,
      height: 28,
      borderRadius: 6,
      hoverColor: c.hoverFill,
      hoverBorderColor: c.hoverBorder,
      pressedColor: c.accentSoft,
      scaleOnPress: 0.94,
      builder: (context, hovered, pressed) => Center(
        child: Icon(
          icon,
          size: 18,
          color: !enabled
              ? c.mutedText.withValues(alpha: 0.35)
              : hovered
                  ? c.accent
                  : Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}

class _CompactBarField extends StatelessWidget {
  const _CompactBarField({
    required this.width,
    required this.controller,
    required this.focusNode,
    required this.onBeginEdit,
    required this.onCommit,
  });

  final double width;
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onBeginEdit;
  final VoidCallback onCommit;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return SizedBox(
      width: width,
      height: 28,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        textAlignVertical: TextAlignVertical.center,
        style: const TextStyle(fontSize: AppTypography.body, height: 1.15),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: c.subtleFill,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 6,
            vertical: 0,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: c.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: c.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(6),
            borderSide: BorderSide(color: c.accent, width: 1.4),
          ),
        ),
        onTap: () {
          onBeginEdit();
          controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: controller.text.length,
          );
        },
        onSubmitted: (_) {
          onCommit();
          focusNode.unfocus();
        },
        onTapOutside: (_) {
          if (focusNode.hasFocus) {
            onCommit();
            focusNode.unfocus();
          }
        },
      ),
    );
  }
}
