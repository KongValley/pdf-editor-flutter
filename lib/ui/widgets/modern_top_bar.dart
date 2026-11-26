import 'package:flutter/material.dart';

import '../../state/editor_controller.dart';
import '../layout/workspace_breakpoints.dart';
import '../theme/app_theme.dart';
import 'hover_feedback.dart';

class ModernTopBar extends StatelessWidget {
  const ModernTopBar({
    super.key,
    required this.controller,
    required this.onOpenFile,
    required this.onMergePdf,
    required this.onImageToPdf,
    required this.onSave,
    required this.onSaveAs,
    required this.onExportCurrentPng,
    required this.onExportPagesDialog,
    required this.onPrintDialog,
    required this.onAbout,
    this.thumbnailsActive,
    this.rightPanelActive,
    this.onToggleThumbnails,
    this.onToggleRightPanel,
  });

  final EditorController controller;
  final VoidCallback onOpenFile;
  final VoidCallback onMergePdf;
  final VoidCallback onImageToPdf;
  final VoidCallback onSave;
  final VoidCallback onSaveAs;
  final VoidCallback onExportCurrentPng;
  final VoidCallback onExportPagesDialog;
  final VoidCallback onPrintDialog;
  final VoidCallback onAbout;
  final bool? thumbnailsActive;
  final bool? rightPanelActive;
  final VoidCallback? onToggleThumbnails;
  final VoidCallback? onToggleRightPanel;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final hasDoc = controller.hasDocument;
    final busy = controller.isBusy;
    final leftActive = thumbnailsActive ?? controller.showThumbnails;
    final rightActive = rightPanelActive ?? controller.showRightPanel;
    final toggleLeft = onToggleThumbnails ?? () => controller.toggleThumbnails();
    final toggleRight =
        onToggleRightPanel ?? () => controller.toggleRightPanel();

    return Material(
      color: c.surfaceBg,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: c.border)),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final density = constraints.maxWidth >=
                    WorkspaceLayoutSpec.standardBreakpoint
                ? TopBarDensity.full
                : constraints.maxWidth >= WorkspaceLayoutSpec.narrowBreakpoint
                    ? TopBarDensity.compact
                    : TopBarDensity.ultraCompact;

            final brand = Tooltip(
              message: 'PDF 编辑器',
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: density == TopBarDensity.full ? 8 : 7,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: c.accentSoft,
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.picture_as_pdf_rounded,
                      size: 17,
                      color: c.accent,
                    ),
                    if (density == TopBarDensity.full) ...[
                      const SizedBox(width: 5),
                      Text(
                        'PDF 编辑器',
                        style: TextStyle(
                          fontSize: AppTypography.title,
                          fontWeight: FontWeight.w700,
                          color: c.accent,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );

            final exportMenu = ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: PopupMenuButton<String>(
                enabled: hasDoc && !busy,
                tooltip: '导出 PDF / PNG 图片 / 拼接长图',
                offset: const Offset(0, 36),
                onSelected: (value) {
                  if (value == 'cur_png') onExportCurrentPng();
                  if (value == 'range_export') onExportPagesDialog();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'cur_png',
                    height: 40,
                    child: Row(
                      children: [
                        Icon(Icons.image_outlined, size: 17),
                        SizedBox(width: 8),
                        Text(
                          '导出当前页 PNG',
                          style: TextStyle(fontSize: AppTypography.body),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'range_export',
                    height: 40,
                    child: Row(
                      children: [
                        Icon(Icons.collections_outlined, size: 17),
                        SizedBox(width: 8),
                        Text(
                          '按页码范围导出 (Ctrl+E)…',
                          style: TextStyle(fontSize: AppTypography.body),
                        ),
                      ],
                    ),
                  ),
                ],
                child: DesktopHoverContainer(
                  enabled: hasDoc && !busy,
                  focusable: false,
                  minHeight: 32,
                  borderRadius: 7,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 5,
                  ),
                  hoverColor: c.hoverFill,
                  hoverBorderColor: c.hoverBorder,
                  pressedColor: c.accentSoft,
                  builder: (context, hovered, pressed) {
                    final fg = (!hasDoc || busy)
                        ? c.mutedText.withValues(alpha: 0.4)
                        : hovered
                            ? c.accent
                            : Theme.of(context).colorScheme.onSurface;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.ios_share_rounded, size: 16, color: fg),
                        const SizedBox(width: 4),
                        Text(
                          '导出',
                          style: TextStyle(
                            fontSize: AppTypography.body,
                            color: fg,
                          ),
                        ),
                        Icon(Icons.arrow_drop_down, size: 16, color: fg),
                      ],
                    );
                  },
                ),
              ),
            );

            final moreMenu = ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: PopupMenuButton<String>(
                tooltip: '更多文件与视图操作',
                offset: const Offset(0, 36),
                onSelected: (value) {
                  switch (value) {
                    case 'img2pdf':
                      onImageToPdf();
                      break;
                    case 'merge':
                      onMergePdf();
                      break;
                    case 'save_as':
                      onSaveAs();
                      break;
                    case 'export_cur_png':
                      onExportCurrentPng();
                      break;
                    case 'export_range':
                      onExportPagesDialog();
                      break;
                    case 'print':
                      onPrintDialog();
                      break;
                    case 'rot_left':
                      controller.rotateView(-90);
                      break;
                    case 'rot_right':
                      controller.rotateView(90);
                      break;
                    case 'theme':
                      controller.toggleTheme();
                      break;
                    case 'about':
                      onAbout();
                      break;
                  }
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'img2pdf',
                    enabled: !busy,
                    height: 40,
                    child: const _MenuLabel(
                      icon: Icons.photo_library_outlined,
                      label: '图片转 PDF',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'merge',
                    enabled: !busy,
                    height: 40,
                    child: const _MenuLabel(
                      icon: Icons.merge_type_rounded,
                      label: '合并 PDF',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'save_as',
                    enabled: hasDoc && !busy,
                    height: 40,
                    child: const _MenuLabel(
                      icon: Icons.save_as_outlined,
                      label: '另存为 (Ctrl+Shift+S)',
                    ),
                  ),
                  if (density == TopBarDensity.ultraCompact) ...[
                    PopupMenuItem(
                      value: 'export_cur_png',
                      enabled: hasDoc && !busy,
                      height: 40,
                      child: const _MenuLabel(
                        icon: Icons.image_outlined,
                        label: '导出当前页 PNG',
                      ),
                    ),
                    PopupMenuItem(
                      value: 'export_range',
                      enabled: hasDoc && !busy,
                      height: 40,
                      child: const _MenuLabel(
                        icon: Icons.collections_outlined,
                        label: '按页码范围导出 (Ctrl+E)…',
                      ),
                    ),
                  ],
                  PopupMenuItem(
                    value: 'print',
                    enabled: hasDoc && !busy,
                    height: 40,
                    child: const _MenuLabel(
                      icon: Icons.print_outlined,
                      label: '打印 (Ctrl+P)',
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'rot_left',
                    enabled: hasDoc && !busy,
                    height: 40,
                    child: const _MenuLabel(
                      icon: Icons.rotate_left_rounded,
                      label: '视图左旋 90° ([)',
                    ),
                  ),
                  PopupMenuItem(
                    value: 'rot_right',
                    enabled: hasDoc && !busy,
                    height: 40,
                    child: const _MenuLabel(
                      icon: Icons.rotate_right_rounded,
                      label: '视图右旋 90° (])',
                    ),
                  ),
                  const PopupMenuDivider(),
                  PopupMenuItem(
                    value: 'theme',
                    height: 40,
                    child: _MenuLabel(
                      icon: controller.isDarkMode
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      label: controller.isDarkMode ? '切换浅色外观' : '切换深色外观',
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'about',
                    height: 40,
                    child: _MenuLabel(
                      icon: Icons.info_outline_rounded,
                      label: '关于与环境自检',
                    ),
                  ),
                ],
                child: DesktopHoverContainer(
                  enabled: true,
                  focusable: false,
                  minWidth: 32,
                  minHeight: 32,
                  borderRadius: 7,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 5,
                  ),
                  hoverColor: c.hoverFill,
                  hoverBorderColor: c.hoverBorder,
                  pressedColor: c.accentSoft,
                  builder: (context, hovered, _) {
                    final fg = hovered
                        ? c.accent
                        : Theme.of(context).colorScheme.onSurface;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.more_horiz_rounded, size: 18, color: fg),
                        if (density == TopBarDensity.compact) ...[
                          const SizedBox(width: 3),
                          Text(
                            '更多',
                            style: TextStyle(
                              fontSize: AppTypography.body,
                              color: fg,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            );

            final leftChildren = <Widget>[
              brand,
              const SizedBox(width: 6),
              _TopButton(
                icon: Icons.folder_open_rounded,
                label: density == TopBarDensity.ultraCompact ? null : '打开',
                tooltip: '打开 PDF 文件 (Ctrl+O)',
                enabled: !busy,
                onPressed: onOpenFile,
              ),
              if (density == TopBarDensity.full) ...[
                const SizedBox(width: 2),
                _TopButton(
                  icon: Icons.photo_library_outlined,
                  label: '图转PDF',
                  tooltip: '把 PNG/JPEG 图片合并为 PDF',
                  enabled: !busy,
                  onPressed: onImageToPdf,
                ),
                const SizedBox(width: 2),
                _TopButton(
                  icon: Icons.merge_type_rounded,
                  label: '合并',
                  tooltip: '选择并合并多个 PDF 文件',
                  enabled: !busy,
                  onPressed: onMergePdf,
                ),
              ],
              const SizedBox(width: 2),
              _TopButton(
                icon: Icons.save_rounded,
                label: density == TopBarDensity.ultraCompact ? null : '保存',
                tooltip: '保存 PDF (Ctrl+S)',
                enabled: hasDoc && !busy,
                highlight: controller.dirty,
                onPressed: onSave,
              ),
              if (density == TopBarDensity.full) ...[
                const SizedBox(width: 2),
                _TopButton(
                  icon: Icons.save_as_outlined,
                  tooltip: '另存为 (Ctrl+Shift+S)',
                  enabled: hasDoc && !busy,
                  onPressed: onSaveAs,
                ),
              ],
              if (density != TopBarDensity.ultraCompact) ...[
                const SizedBox(width: 2),
                exportMenu,
              ],
              if (density == TopBarDensity.full) ...[
                const SizedBox(width: 2),
                _TopButton(
                  icon: Icons.print_outlined,
                  label: '打印',
                  tooltip: '打印 (Ctrl+P)',
                  enabled: hasDoc && !busy,
                  onPressed: onPrintDialog,
                ),
              ],
              _BarDivider(color: c.border),
              _TopButton(
                icon: Icons.undo_rounded,
                tooltip: '撤销 (Ctrl+Z)',
                enabled: controller.canUndo && !busy,
                onPressed: () => controller.undo(),
              ),
              const SizedBox(width: 2),
              _TopButton(
                icon: Icons.redo_rounded,
                tooltip: '重做 (Ctrl+Y)',
                enabled: controller.canRedo && !busy,
                onPressed: () => controller.redo(),
              ),
              if (density != TopBarDensity.full) ...[
                const SizedBox(width: 2),
                moreMenu,
              ],
            ];

            final docMaxWidth = density == TopBarDensity.full
                ? 280.0
                : density == TopBarDensity.compact
                    ? 190.0
                    : 150.0;
            final Widget docPill = hasDoc && constraints.maxWidth >= 560
                ? Container(
                        constraints: BoxConstraints(maxWidth: docMaxWidth),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: c.subtleFill,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: c.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (controller.dirty) ...[
                              Container(
                                width: 7,
                                height: 7,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFF59E0B),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                controller.displayFileName,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: AppTypography.body,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (controller.encrypted) ...[
                              const SizedBox(width: 6),
                              Icon(
                                Icons.lock_outline_rounded,
                                size: 13,
                                color: c.mutedText,
                              ),
                            ],
                          ],
                        ),
                      )
                    : const SizedBox.shrink();

            final rightChildren = <Widget>[
              if (density == TopBarDensity.full) ...[
                _TopButton(
                  icon: Icons.rotate_left_rounded,
                  tooltip: '视图左旋 90°（不改文件）([)',
                  enabled: hasDoc && !busy,
                  onPressed: () => controller.rotateView(-90),
                ),
                const SizedBox(width: 2),
                _TopButton(
                  icon: Icons.rotate_right_rounded,
                  tooltip: '视图右旋 90°（不改文件）(])',
                  enabled: hasDoc && !busy,
                  onPressed: () => controller.rotateView(90),
                ),
                const SizedBox(width: 2),
              ],
              _TopButton(
                icon: Icons.search_rounded,
                tooltip: '搜索文本 (Ctrl+F)',
                enabled: hasDoc,
                active: controller.searchOpen,
                onPressed: controller.toggleSearch,
              ),
              _BarDivider(color: c.border),
              _TopButton(
                icon: Icons.view_sidebar_outlined,
                tooltip: '显示/隐藏缩略图栏 (Ctrl+B)',
                active: leftActive,
                onPressed: toggleLeft,
              ),
              const SizedBox(width: 2),
              _TopButton(
                icon: Icons.vertical_split_outlined,
                tooltip: '显示/隐藏右侧面板 (Ctrl+Shift+B)',
                active: rightActive,
                onPressed: toggleRight,
              ),
              if (density == TopBarDensity.full) ...[
                const SizedBox(width: 2),
                _TopButton(
                  icon: controller.isDarkMode
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                  tooltip: controller.isDarkMode ? '切换浅色外观' : '切换深色外观',
                  onPressed: controller.toggleTheme,
                ),
                const SizedBox(width: 2),
                _TopButton(
                  icon: Icons.info_outline_rounded,
                  tooltip: '关于与环境自检',
                  onPressed: onAbout,
                ),
              ],
            ];

            return Row(
              children: [
                ...leftChildren,
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      child: docPill,
                    ),
                  ),
                ),
                ...rightChildren,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel({required this.icon, required this.label});

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

class _BarDivider extends StatelessWidget {
  const _BarDivider({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: color,
    );
  }
}

class _TopButton extends StatelessWidget {
  const _TopButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.label,
    this.enabled = true,
    this.active = false,
    this.highlight = false,
  });

  final IconData icon;
  final String? label;
  final String tooltip;
  final bool enabled;
  final bool active;
  final bool highlight;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return DesktopHoverContainer(
      tooltip: tooltip,
      semanticLabel: label ?? tooltip,
      enabled: enabled,
      active: active || highlight,
      onTap: enabled ? onPressed : null,
      minWidth: 32,
      minHeight: 32,
      borderRadius: 7,
      padding: EdgeInsets.symmetric(
        horizontal: label == null ? 6 : 8,
        vertical: 5,
      ),
      baseColor: Colors.transparent,
      activeColor: active ? c.accentSoft : c.accentSoft.withValues(alpha: 0.65),
      activeBorderColor: c.accent.withValues(alpha: active ? 0.42 : 0.28),
      hoverColor: c.hoverFill,
      hoverBorderColor: c.hoverBorder,
      pressedColor: c.accentSoft,
      builder: (context, hovered, pressed) {
        final fg = !enabled
            ? c.mutedText.withValues(alpha: 0.4)
            : (active || highlight || hovered)
                ? c.accent
                : Theme.of(context).colorScheme.onSurface;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(
                label!,
                style: TextStyle(
                  fontSize: AppTypography.body,
                  color: fg,
                  fontWeight: (active || highlight || hovered)
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
