import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../state/editor_controller.dart';
import '../theme/app_theme.dart';
import 'hover_feedback.dart';

class WelcomeView extends StatelessWidget {
  const WelcomeView({
    super.key,
    required this.controller,
    required this.onOpenFile,
    required this.onMergePdf,
    required this.onImageToPdf,
    required this.onOpenPath,
  });

  final EditorController controller;
  final VoidCallback onOpenFile;
  final VoidCallback onMergePdf;
  final VoidCallback onImageToPdf;
  final Future<void> Function(String path) onOpenPath;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: (constraints.maxHeight - 32).clamp(0.0, double.infinity),
          ),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 620),
              padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: c.surfaceBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: c.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Icons.picture_as_pdf_rounded,
                    size: 24,
                    color: c.accent,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PDF 编辑器',
                        style: TextStyle(
                          fontSize: AppTypography.title,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '拖放 PDF 或 PNG/JPEG 图片到窗口，或点击下方入口开始',
                        style: TextStyle(
                          fontSize: AppTypography.body,
                          color: c.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onOpenFile,
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text('打开 PDF 文件 (Ctrl+O)'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onMergePdf,
                    icon: const Icon(Icons.merge_type_rounded, size: 18),
                    label: const Text('合并 PDF'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onImageToPdf,
                    icon: const Icon(Icons.photo_library_outlined, size: 18),
                    label: const Text('图片转 PDF'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (controller.recentFiles.isNotEmpty) ...[
              const SizedBox(height: 22),
              Builder(
                builder: (context) {
                  final hasMissing = controller.recentFiles
                      .any((e) => !File(e.path).existsSync());
                  return Row(
                    children: [
                      Text(
                        '最近打开',
                        style: TextStyle(
                          fontSize: AppTypography.body,
                          fontWeight: FontWeight.w600,
                          color: c.mutedText,
                        ),
                      ),
                      const Spacer(),
                      if (hasMissing) ...[
                        _RecentManageBtn(
                          label: '清理失效',
                          onTap: controller.clearMissingRecentFiles,
                        ),
                        const SizedBox(width: 6),
                      ],
                      _RecentManageBtn(
                        label: '清空记录',
                        danger: true,
                        onTap: controller.clearAllRecentFiles,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 280),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: controller.recentFiles.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final item = controller.recentFiles[index];
                    final exists = File(item.path).existsSync();
                    return DesktopHoverContainer(
                      enabled: exists,
                      onTap: exists ? () => onOpenPath(item.path) : null,
                      borderRadius: 8,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      baseColor: c.subtleFill,
                      borderColor: c.border.withValues(alpha: 0.55),
                      hoverColor: c.hoverFill,
                      hoverBorderColor: c.hoverBorder,
                      pressedColor: c.accentSoft,
                      scaleOnPress: 0.99,
                      builder: (context, hovered, pressed) => Row(
                        children: [
                          Icon(
                            Icons.description_outlined,
                            size: 16,
                            color: exists ? c.accent : c.mutedText,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  p.basename(item.path),
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: AppTypography.body,
                                    fontWeight: FontWeight.w500,
                                    color: exists
                                        ? (hovered ? c.accent : null)
                                        : c.mutedText,
                                  ),
                                ),
                                Text(
                                  item.path,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: AppTypography.body,
                                    color: c.mutedText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            exists ? '第 ${item.page} 页' : '文件不存在',
                            style: TextStyle(
                              fontSize: AppTypography.body,
                              color: exists && hovered ? c.accent : c.mutedText,
                            ),
                          ),
                          const SizedBox(width: 6),
                          DesktopHoverContainer(
                            tooltip: '从最近记录移除',
                            onTap: () => controller.removeRecentFile(item.path),
                            width: 24,
                            height: 24,
                            borderRadius: 5,
                            hoverColor: c.hoverFill,
                            hoverBorderColor: c.hoverBorder,
                            pressedColor: c.accentSoft,
                            builder: (context, btnHover, _) => Center(
                              child: Icon(
                                Icons.close_rounded,
                                size: 15,
                                color: btnHover ? c.accent : c.mutedText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    ),
    ),
    ),
    );
  }
}

class _RecentManageBtn extends StatelessWidget {
  const _RecentManageBtn({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    const dangerRed = Color(0xFFE03131);
    return DesktopHoverContainer(
      onTap: onTap,
      borderRadius: 6,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      hoverColor: danger ? dangerRed.withValues(alpha: 0.1) : c.hoverFill,
      hoverBorderColor:
          danger ? dangerRed.withValues(alpha: 0.45) : c.hoverBorder,
      pressedColor: danger ? dangerRed.withValues(alpha: 0.18) : c.accentSoft,
      scaleOnPress: 0.96,
      builder: (context, hovered, _) => Text(
        label,
        style: TextStyle(
          fontSize: AppTypography.body,
          color: hovered
              ? (danger ? dangerRed : c.accent)
              : c.mutedText,
          fontWeight: hovered ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}
