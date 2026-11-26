import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../state/editor_controller.dart';
import '../layout/workspace_breakpoints.dart';
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
    this.width = WorkspaceLayoutSpec.dockedLeftWidth,
    this.compact = false,
    this.isOverlay = false,
    this.onClose,
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
  final double width;
  final bool compact;
  final bool isOverlay;
  final VoidCallback? onClose;

  @override
  State<ThumbnailsSidebar> createState() => _ThumbnailsSidebarState();
}

class _ThumbnailsSidebarState extends State<ThumbnailsSidebar> {
  static const double _kTileBottomGap = 8.0;
  static const double _kListTopPadding = 8.0;

  double get _tileOuterHeight => widget.compact ? 148.0 : 194.0;
  double get _previewHeight => widget.compact ? 100.0 : 146.0;
  double get _tileExtent => _tileOuterHeight + _kTileBottomGap;

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
    if (!docChanged && _scrollCtrl.hasClients) {
      _scrollToCurrentPage(animate: true);
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollToCurrentPage(animate: !docChanged);
      });
    }
  }

  void _scrollToCurrentPage({required bool animate}) {
    final ctrl = widget.controller;
    if (!ctrl.hasDocument || ctrl.suspendViewer || !_scrollCtrl.hasClients) {
      return;
    }
    final pos = _scrollCtrl.position;
    if (!pos.hasViewportDimension || pos.maxScrollExtent <= 0) return;
    final index = (ctrl.currentPage - 1).clamp(0, ctrl.pageCount - 1);
    final itemTop = _kListTopPadding + index * _tileExtent;
    final itemBottom = itemTop + _tileOuterHeight;
    final viewTop = pos.pixels;
    final viewBottom = viewTop + pos.viewportDimension;
    if (itemTop >= viewTop + 4 && itemBottom <= viewBottom - 4) {
      return;
    }
    final target = (itemTop - (pos.viewportDimension - _tileOuterHeight) / 2)
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
    final c = context.appColors;
    final hasDoc = controller.hasDocument;
    final busy = controller.isBusy;
    final encrypted = controller.encrypted;
    final selectedCount = controller.selectedThumbPages.length;
    final scopeHint = selectedCount > 0 ? '已选 $selectedCount 页' : '当前页';

    return Material(
      color: c.surfaceBg,
      elevation: widget.isOverlay ? 14 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.24),
      child: Container(
        width: widget.width,
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: c.border)),
        ),
        child: Column(
          children: [
            // 精简双行页面管理头部（高度约 90px）
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.border)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        '页面',
                        style: TextStyle(
                          fontSize: AppTypography.title,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (selectedCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: c.accentSoft,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '已选 $selectedCount',
                            style: TextStyle(
                              fontSize: AppTypography.caption,
                              fontWeight: FontWeight.w600,
                              color: c.accent,
                            ),
                          ),
                        )
                      else if (hasDoc)
                        Text(
                          '${controller.currentPage}/${controller.pageCount}',
                          style: TextStyle(
                            fontSize: AppTypography.caption,
                            color: c.mutedText,
                          ),
                        ),
                      const Spacer(),
                      _LinkBtn(
                        label: '全选',
                        enabled: hasDoc,
                        onTap: controller.selectAllThumbs,
                      ),
                      const SizedBox(width: 2),
                      _LinkBtn(
                        label: '反选',
                        enabled: hasDoc,
                        onTap: controller.invertThumbSelection,
                      ),
                      const SizedBox(width: 2),
                      _LinkBtn(
                        label: '清空',
                        enabled: hasDoc && selectedCount > 0,
                        onTap: controller.clearThumbSelection,
                      ),
                      if (widget.isOverlay && widget.onClose != null) ...[
                        const SizedBox(width: 2),
                        DesktopHoverContainer(
                          tooltip: '关闭页面面板 (Esc)',
                          onTap: widget.onClose,
                          width: 28,
                          height: 28,
                          borderRadius: 6,
                          hoverColor: c.hoverFill,
                          hoverBorderColor: c.hoverBorder,
                          pressedColor: c.accentSoft,
                          builder: (context, hovered, _) => Center(
                            child: Icon(
                              Icons.close_rounded,
                              size: 16,
                              color: hovered ? c.accent : c.mutedText,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: _CompactPageAction(
                          icon: Icons.rotate_left_rounded,
                          tooltip: '左旋 90°（作用域：$scopeHint）',
                          enabled: hasDoc && !busy && !encrypted,
                          onTap: () {
                            final pages = _targetPagesForQuickAction();
                            controller.rotatePages({
                              for (final p in pages) p: -90,
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _CompactPageAction(
                          icon: Icons.rotate_right_rounded,
                          tooltip: '右旋 90°（作用域：$scopeHint）',
                          enabled: hasDoc && !busy && !encrypted,
                          onTap: () {
                            final pages = _targetPagesForQuickAction();
                            controller.rotatePages({
                              for (final p in pages) p: 90,
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _CompactPageAction(
                          icon: Icons.note_add_outlined,
                          tooltip: '在当前页后插入空白页 (Ctrl+Shift+N)',
                          enabled: hasDoc && !busy && !encrypted,
                          onTap: () => controller
                              .insertBlankPageAfter(controller.currentPage - 1),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _CompactPageAction(
                          icon: Icons.delete_outline_rounded,
                          tooltip: '删除页面（作用域：$scopeHint）',
                          danger: true,
                          enabled: hasDoc &&
                              !busy &&
                              !encrypted &&
                              controller.pageCount > 1,
                          onTap: widget.onDeleteDialog,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: PopupMenuButton<String>(
                            enabled: hasDoc && !busy,
                            tooltip: '更多页面批处理（提取、拆分、水印、页码等）',
                            offset: const Offset(0, 36),
                            onSelected: (value) {
                              switch (value) {
                                case 'extract':
                                  widget.onExtractDialog();
                                  break;
                                case 'split':
                                  widget.onSplitDialog();
                                  break;
                                case 'export':
                                  widget.onExportDialog();
                                  break;
                                case 'orientation':
                                  widget.onOrientationDialog();
                                  break;
                                case 'page_num':
                                  widget.onPageNumberDialog();
                                  break;
                                case 'watermark':
                                  widget.onWatermarkDialog();
                                  break;
                                case 'merge':
                                  widget.onMergeDialog();
                                  break;
                              }
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'extract',
                                height: 40,
                                child: _SidebarMenuItem(
                                  icon: Icons.content_cut_rounded,
                                  label: '提取页面为 PDF…',
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'split',
                                height: 40,
                                child: _SidebarMenuItem(
                                  icon: Icons.call_split_rounded,
                                  label: '拆分 PDF…',
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'export',
                                height: 40,
                                child: _SidebarMenuItem(
                                  icon: Icons.ios_share_rounded,
                                  label: '导出页面 / 图片…',
                                ),
                              ),
                              const PopupMenuDivider(),
                              PopupMenuItem(
                                value: 'orientation',
                                enabled: !encrypted,
                                height: 40,
                                child: const _SidebarMenuItem(
                                  icon: Icons.auto_fix_high_rounded,
                                  label: '统一页面方向…',
                                ),
                              ),
                              PopupMenuItem(
                                value: 'page_num',
                                enabled: !encrypted,
                                height: 40,
                                child: const _SidebarMenuItem(
                                  icon: Icons.format_list_numbered_rounded,
                                  label: '添加页码…',
                                ),
                              ),
                              PopupMenuItem(
                                value: 'watermark',
                                enabled: !encrypted,
                                height: 40,
                                child: const _SidebarMenuItem(
                                  icon: Icons.branding_watermark_outlined,
                                  label: '添加水印…',
                                ),
                              ),
                              const PopupMenuDivider(),
                              const PopupMenuItem(
                                value: 'merge',
                                height: 40,
                                child: _SidebarMenuItem(
                                  icon: Icons.merge_type_rounded,
                                  label: '合并其他 PDF…',
                                ),
                              ),
                            ],
                            child: DesktopHoverContainer(
                              enabled: hasDoc && !busy,
                              focusable: false,
                              height: 34,
                              borderRadius: 6,
                              baseColor: c.subtleFill,
                              borderColor: c.border.withValues(
                                alpha: (hasDoc && !busy) ? 0.65 : 0.35,
                              ),
                              hoverColor: c.hoverFill,
                              hoverBorderColor: c.hoverBorder,
                              pressedColor: c.accentSoft,
                              builder: (context, hovered, _) {
                                final fg = (!hasDoc || busy)
                                    ? c.mutedText.withValues(alpha: 0.35)
                                    : hovered
                                        ? c.accent
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurface;
                                return Center(
                                  child: Icon(
                                    Icons.more_horiz_rounded,
                                    size: 18,
                                    color: fg,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
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
                            final isCurrent =
                                controller.currentPage == index + 1;
                            final isChecked =
                                controller.selectedThumbPages.contains(index);
                            return ReorderableDragStartListener(
                              key: ValueKey('thumb_item_$index'),
                              index: index,
                              enabled: !encrypted && !busy,
                              child: _ThumbTile(
                                document: doc,
                                pageIndex: index,
                                outerHeight: _tileOuterHeight,
                                previewHeight: _previewHeight,
                                isCurrent: isCurrent,
                                isChecked: isChecked,
                                onTap: () => controller.jumpToPage(index + 1),
                                onToggleCheck: () =>
                                    controller.toggleThumbSelection(index),
                                onSecondaryTap: (pos) =>
                                    widget.onPageContextMenu(index, pos),
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

class _SidebarMenuItem extends StatelessWidget {
  const _SidebarMenuItem({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 17),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: AppTypography.body)),
      ],
    );
  }
}

class _CompactPageAction extends StatelessWidget {
  const _CompactPageAction({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    const dangerRed = Color(0xFFDC2626);
    return DesktopHoverContainer(
      tooltip: tooltip,
      semanticLabel: tooltip,
      enabled: enabled,
      onTap: enabled ? onTap : null,
      height: 34,
      borderRadius: 6,
      baseColor: c.subtleFill,
      borderColor: c.border.withValues(alpha: enabled ? 0.65 : 0.35),
      hoverColor: danger ? dangerRed.withValues(alpha: 0.1) : c.hoverFill,
      hoverBorderColor:
          danger ? dangerRed.withValues(alpha: 0.48) : c.hoverBorder,
      pressedColor: danger ? dangerRed.withValues(alpha: 0.18) : c.accentSoft,
      builder: (context, hovered, _) {
        final fg = !enabled
            ? c.mutedText.withValues(alpha: 0.35)
            : danger
                ? dangerRed
                : hovered
                    ? c.accent
                    : Theme.of(context).colorScheme.onSurface;
        return Center(
          child: Icon(icon, size: 17, color: fg),
        );
      },
    );
  }
}

class _ThumbTile extends StatelessWidget {
  const _ThumbTile({
    required this.document,
    required this.pageIndex,
    required this.outerHeight,
    required this.previewHeight,
    required this.isCurrent,
    required this.isChecked,
    required this.onTap,
    required this.onToggleCheck,
    required this.onSecondaryTap,
  });

  final PdfDocument document;
  final int pageIndex;
  final double outerHeight;
  final double previewHeight;
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
            padding: const EdgeInsets.only(
              bottom: _ThumbnailsSidebarState._kTileBottomGap,
            ),
            child: SizedBox(
              height: outerHeight,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 110),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.fromLTRB(6, 6, 6, 4),
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
                      height: previewHeight,
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
                    const Spacer(),
                    SizedBox(
                      height: 30,
                      child: Row(
                        children: [
                          DesktopHoverContainer(
                            tooltip: isChecked
                                ? '取消勾选第 ${pageIndex + 1} 页'
                                : '勾选第 ${pageIndex + 1} 页用于批处理',
                            onTap: onToggleCheck,
                            width: 30,
                            height: 30,
                            borderRadius: 6,
                            hoverColor: c.accentSoft.withValues(alpha: 0.75),
                            hoverBorderColor: c.hoverBorder,
                            builder: (context, _, _) => Center(
                              child: IgnorePointer(
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: Checkbox(
                                    value: isChecked,
                                    onChanged: (_) {},
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '${pageIndex + 1}',
                            style: TextStyle(
                              fontSize: AppTypography.body,
                              fontWeight: isCurrent
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isCurrent ? c.accent : c.mutedText,
                            ),
                          ),
                          const Spacer(),
                          SizedBox(
                            width: 30,
                            child: Center(
                              child: Icon(
                                Icons.drag_indicator_rounded,
                                size: 15,
                                color: c.mutedText.withValues(alpha: 0.65),
                              ),
                            ),
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
      minHeight: 28,
      borderRadius: 5,
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      hoverColor: c.hoverFill,
      hoverBorderColor: c.hoverBorder,
      pressedColor: c.accentSoft,
      scaleOnPress: 0.95,
      builder: (context, hovered, pressed) {
        return Text(
          label,
          style: TextStyle(
            fontSize: AppTypography.caption,
            fontWeight: hovered ? FontWeight.w600 : FontWeight.w500,
            color: enabled ? c.accent : c.mutedText.withValues(alpha: 0.4),
          ),
        );
      },
    );
  }
}
