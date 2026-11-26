import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../state/editor_controller.dart';
import '../theme/app_theme.dart';
import 'hover_feedback.dart';

class ThumbnailsSidebar extends StatefulWidget {
  const ThumbnailsSidebar({
    super.key,
    required this.controller,
    required this.onDeleteDialog,
    required this.onExtractDialog,
    required this.onSplitDialog,
    required this.onExportDialog,
    required this.onOrientationDialog,
    required this.onPageNumberDialog,
    required this.onWatermarkDialog,
    required this.onMergeDialog,
    required this.onPageContextMenu,
  });

  final EditorController controller;
  final VoidCallback onDeleteDialog;
  final VoidCallback onExtractDialog;
  final VoidCallback onSplitDialog;
  final VoidCallback onExportDialog;
  final VoidCallback onOrientationDialog;
  final VoidCallback onPageNumberDialog;
  final VoidCallback onWatermarkDialog;
  final VoidCallback onMergeDialog;
  final void Function(int pageZeroBased, Offset globalPos) onPageContextMenu;

  @override
  State<ThumbnailsSidebar> createState() => _ThumbnailsSidebarState();
}

class _ThumbnailsSidebarState extends State<ThumbnailsSidebar> {
  static const double _kTileOuterHeight = 194.0;
  static const double _kTileBottomGap = 8.0;
  static const double _kTileExtent = _kTileOuterHeight + _kTileBottomGap;
  static const double _kListTopPadding = 8.0;

  final ScrollController _scrollCtrl = ScrollController();
  int? _lastSyncedPage;
  String? _lastRenderPath;
  bool _didScrollForCurrentList = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
    _lastSyncedPage = widget.controller.currentPage;
    _lastRenderPath = widget.controller.activeRenderPath;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToCurrentPage(animate: false);
    });
  }

  @override
  void didUpdateWidget(covariant ThumbnailsSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _lastSyncedPage = widget.controller.currentPage;
      _lastRenderPath = widget.controller.activeRenderPath;
      _didScrollForCurrentList = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToCurrentPage(animate: false);
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final ctrl = widget.controller;
    final pageChanged = ctrl.currentPage != _lastSyncedPage;
    final docChanged = ctrl.activeRenderPath != _lastRenderPath;
    if (!pageChanged && !docChanged) return;
    _lastSyncedPage = ctrl.currentPage;
    _lastRenderPath = ctrl.activeRenderPath;
    if (docChanged) {
      _didScrollForCurrentList = false;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToCurrentPage(animate: !docChanged);
    });
  }

  void _scrollToCurrentPage({required bool animate}) {
    final ctrl = widget.controller;
    if (!ctrl.hasDocument || ctrl.suspendViewer || !_scrollCtrl.hasClients) {
      return;
    }
    final pos = _scrollCtrl.position;
    if (!pos.hasViewportDimension || pos.maxScrollExtent <= 0) return;
    final index = (ctrl.currentPage - 1).clamp(0, ctrl.pageCount - 1);
    final itemTop = _kListTopPadding + index * _kTileExtent;
    final itemBottom = itemTop + _kTileOuterHeight;
    final viewTop = pos.pixels;
    final viewBottom = viewTop + pos.viewportDimension;
    if (itemTop >= viewTop + 4 && itemBottom <= viewBottom - 4) {
      return;
    }
    final target = (itemTop - (pos.viewportDimension - _kTileOuterHeight) / 2)
        .clamp(0.0, pos.maxScrollExtent);
    if ((target - viewTop).abs() < 2.0) return;
    if (animate && (target - viewTop).abs() <= pos.viewportDimension * 4) {
      _scrollCtrl.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    } else {
      _scrollCtrl.jumpTo(target);
    }
  }

  List<int> _targetPagesForQuickAction() {
    if (widget.controller.selectedThumbPages.isNotEmpty) {
      return widget.controller.selectedThumbPages.toList()..sort();
    }
    return [
      (widget.controller.currentPage - 1)
          .clamp(0, widget.controller.pageCount - 1),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final onDeleteDialog = widget.onDeleteDialog;
    final onExtractDialog = widget.onExtractDialog;
    final onSplitDialog = widget.onSplitDialog;
    final onExportDialog = widget.onExportDialog;
    final onOrientationDialog = widget.onOrientationDialog;
    final onPageNumberDialog = widget.onPageNumberDialog;
    final onWatermarkDialog = widget.onWatermarkDialog;
    final onMergeDialog = widget.onMergeDialog;
    final onPageContextMenu = widget.onPageContextMenu;
    final c = context.appColors;
    final hasDoc = controller.hasDocument;
    final busy = controller.isBusy;
    final encrypted = controller.encrypted;

    return Material(
      color: c.surfaceBg,
      child: Container(
        width: 256,
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: c.border)),
        ),
        child: Column(
        children: [
          // 顶部选择操作
          Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Text(
                      '页面管理',
                      style: TextStyle(
                        fontSize: AppTypography.body,
                        fontWeight: FontWeight.w600,
                        color: c.mutedText,
                      ),
                    ),
                    const Spacer(),
                    _LinkBtn(
                      label: '全选',
                      enabled: hasDoc,
                      onTap: controller.selectAllThumbs,
                    ),
                    const SizedBox(width: 4),
                    _LinkBtn(
                      label: '反选',
                      enabled: hasDoc,
                      onTap: controller.invertThumbSelection,
                    ),
                    const SizedBox(width: 4),
                    _LinkBtn(
                      label: '清空',
                      enabled: hasDoc && controller.selectedThumbPages.isNotEmpty,
                      onTap: controller.clearThumbSelection,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // 紧凑图标化页面工具网格
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    _PageOpBtn(
                      icon: Icons.delete_outline_rounded,
                      label: '删除',
                      enabled: hasDoc && !busy && !encrypted && controller.pageCount > 1,
                      onTap: onDeleteDialog,
                    ),
                    _PageOpBtn(
                      icon: Icons.content_cut_rounded,
                      label: '提取',
                      enabled: hasDoc && !busy,
                      onTap: onExtractDialog,
                    ),
                    _PageOpBtn(
                      icon: Icons.call_split_rounded,
                      label: '拆分',
                      enabled: hasDoc && !busy,
                      onTap: onSplitDialog,
                    ),
                    _PageOpBtn(
                      icon: Icons.ios_share_rounded,
                      label: '导出',
                      enabled: hasDoc && !busy,
                      onTap: onExportDialog,
                    ),
                    _PageOpBtn(
                      icon: Icons.rotate_left_rounded,
                      label: '左旋',
                      enabled: hasDoc && !busy && !encrypted,
                      onTap: () {
                        final pages = _targetPagesForQuickAction();
                        controller.rotatePages({for (final p in pages) p: -90});
                      },
                    ),
                    _PageOpBtn(
                      icon: Icons.rotate_right_rounded,
                      label: '右旋',
                      enabled: hasDoc && !busy && !encrypted,
                      onTap: () {
                        final pages = _targetPagesForQuickAction();
                        controller.rotatePages({for (final p in pages) p: 90});
                      },
                    ),
                    _PageOpBtn(
                      icon: Icons.auto_fix_high_rounded,
                      label: '统方向',
                      enabled: hasDoc && !busy && !encrypted,
                      onTap: onOrientationDialog,
                    ),
                    _PageOpBtn(
                      icon: Icons.note_add_outlined,
                      label: '空白页',
                      enabled: hasDoc && !busy && !encrypted,
                      onTap: () => controller
                          .insertBlankPageAfter(controller.currentPage - 1),
                    ),
                    _PageOpBtn(
                      icon: Icons.format_list_numbered_rounded,
                      label: '页码',
                      enabled: hasDoc && !busy && !encrypted,
                      onTap: onPageNumberDialog,
                    ),
                    _PageOpBtn(
                      icon: Icons.branding_watermark_outlined,
                      label: '水印',
                      enabled: hasDoc && !busy && !encrypted,
                      onTap: onWatermarkDialog,
                    ),
                    _PageOpBtn(
                      icon: Icons.merge_type_rounded,
                      label: '合并',
                      enabled: hasDoc && !busy,
                      onTap: onMergeDialog,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 缩略图列表（按需懒加载 + 支持拖拽重排）
          Expanded(
            child: !hasDoc ||
                    controller.suspendViewer ||
                    controller.activeRenderPath == null
                ? Center(
                    child: Text(
                      controller.suspendViewer ? '正在刷新…' : '暂无页面',
                      style: TextStyle(
                        fontSize: AppTypography.body,
                        color: c.mutedText,
                      ),
                    ),
                  )
                : PdfDocumentViewBuilder.file(
                    controller.activeRenderPath!,
                    key: ValueKey(
                      'thumbs_${controller.activeRenderPath}_${controller.viewerRevision}',
                    ),
                    passwordProvider: () => controller.password,
                    builder: (context, doc) {
                      if (doc == null) {
                        _didScrollForCurrentList = false;
                        return const Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      }
                      if (!_didScrollForCurrentList) {
                        _didScrollForCurrentList = true;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _scrollToCurrentPage(animate: false);
                        });
                      }
                      return ReorderableListView.builder(
                        scrollController: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        buildDefaultDragHandles: false,
                        itemCount: doc.pages.length,
                        onReorderItem: (oldIndex, newIndex) {
                          if (encrypted || busy) return;
                          if (oldIndex != newIndex) {
                            controller.movePage(oldIndex, newIndex);
                          }
                        },
                        itemBuilder: (context, index) {
                          final isCurrent = controller.currentPage == index + 1;
                          final isChecked =
                              controller.selectedThumbPages.contains(index);
                          return ReorderableDragStartListener(
                            key: ValueKey('thumb_item_$index'),
                            index: index,
                            enabled: !encrypted && !busy,
                            child: _ThumbTile(
                              document: doc,
                              pageIndex: index,
                              isCurrent: isCurrent,
                              isChecked: isChecked,
                              onTap: () => controller.jumpToPage(index + 1),
                              onToggleCheck: () =>
                                  controller.toggleThumbSelection(index),
                              onSecondaryTap: (pos) =>
                                  onPageContextMenu(index, pos),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      ),
    );
  }
}

class _ThumbTile extends StatelessWidget {
  const _ThumbTile({
    required this.document,
    required this.pageIndex,
    required this.isCurrent,
    required this.isChecked,
    required this.onTap,
    required this.onToggleCheck,
    required this.onSecondaryTap,
  });

  final PdfDocument document;
  final int pageIndex;
  final bool isCurrent;
  final bool isChecked;
  final VoidCallback onTap;
  final VoidCallback onToggleCheck;
  final void Function(Offset globalPos) onSecondaryTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return GestureDetector(
      onSecondaryTapDown: (d) => onSecondaryTap(d.globalPosition),
      child: HoverStateBuilder(
        enabled: true,
        onTap: onTap,
        builder: (context, hovered, pressed) {
          final bg = isCurrent
              ? c.accentSoft.withValues(alpha: 0.78)
              : hovered
                  ? c.hoverFill
                  : c.subtleFill;
          final borderColor = isCurrent
              ? c.accent
              : hovered
                  ? c.hoverBorder
                  : c.border;
          return Padding(
            padding: const EdgeInsets.only(bottom: _ThumbnailsSidebarState._kTileBottomGap),
            child: SizedBox(
              height: _ThumbnailsSidebarState._kTileOuterHeight,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 110),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: borderColor,
                    width: (isCurrent || hovered) ? 1.5 : 1,
                  ),
                  boxShadow: hovered && !pressed
                      ? [
                          BoxShadow(
                            color: c.accent.withValues(alpha: 0.12),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  children: [
                    SizedBox(
                      height: 150,
                      child: Center(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: PdfPageView(
                            document: document,
                            pageNumber: pageIndex + 1,
                            maximumDpi: 96,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    SizedBox(
                      height: 22,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: Checkbox(
                              value: isChecked,
                              onChanged: (_) => onToggleCheck(),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${pageIndex + 1}',
                            style: TextStyle(
                              fontSize: AppTypography.body,
                              fontWeight:
                                  isCurrent ? FontWeight.w700 : FontWeight.w500,
                              color: isCurrent ? c.accent : c.mutedText,
                            ),
                          ),
                          const Spacer(),
                          Icon(
                            Icons.drag_indicator_rounded,
                            size: 14,
                            color: c.mutedText.withValues(alpha: 0.6),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
      },
    ),
  );
  }
}

class _LinkBtn extends StatelessWidget {
  const _LinkBtn({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return DesktopHoverContainer(
      enabled: enabled,
      onTap: enabled ? onTap : null,
      borderRadius: 5,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      hoverColor: c.hoverFill,
      hoverBorderColor: c.hoverBorder,
      pressedColor: c.accentSoft,
      scaleOnPress: 0.95,
      builder: (context, hovered, pressed) {
        return Text(
          label,
          style: TextStyle(
            fontSize: AppTypography.body,
            fontWeight: hovered ? FontWeight.w600 : FontWeight.w500,
            color: enabled ? c.accent : c.mutedText.withValues(alpha: 0.4),
          ),
        );
      },
    );
  }
}

class _PageOpBtn extends StatelessWidget {
  const _PageOpBtn({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return DesktopHoverContainer(
      enabled: enabled,
      onTap: enabled ? onTap : null,
      width: 56,
      borderRadius: 6,
      padding: const EdgeInsets.symmetric(vertical: 5),
      baseColor: c.subtleFill,
      borderColor: c.border.withValues(alpha: enabled ? 0.65 : 0.35),
      hoverColor: c.hoverFill,
      hoverBorderColor: c.hoverBorder,
      pressedColor: c.accentSoft,
      hoverShadow: [
        BoxShadow(
          color: c.accent.withValues(alpha: 0.14),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ],
      builder: (context, hovered, pressed) {
        final fg = !enabled
            ? c.mutedText.withValues(alpha: 0.35)
            : hovered
                ? c.accent
                : Theme.of(context).colorScheme.onSurface;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                fontSize: AppTypography.body,
                color: fg,
                fontWeight: hovered ? FontWeight.w600 : FontWeight.w400,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      },
    );
  }
}
