import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../models/annotation_model.dart';
import '../../services/system_fonts_service.dart';
import '../../state/editor_controller.dart';
import '../../utils/page_range.dart';
import '../layout/workspace_breakpoints.dart';
import '../theme/app_theme.dart';
import 'hover_feedback.dart';

class RightInspector extends StatelessWidget {
  const RightInspector({
    super.key,
    required this.controller,
    this.width = WorkspaceLayoutSpec.dockedRightWidth,
    this.isOverlay = false,
    this.onClose,
  });

  final EditorController controller;
  final double width;
  final bool isOverlay;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final annotCount = controller.annotations.length;
    return Material(
      color: c.surfaceBg,
      elevation: isOverlay ? 14 : 0,
      shadowColor: Colors.black.withValues(alpha: 0.24),
      child: Container(
        width: width,
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: c.border)),
        ),
        child: Column(
          children: [
            // 顶部 Segmented Tab
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.border)),
              ),
              child: Row(
                children: [
                  _TabButton(
                    label: '属性',
                    selected: controller.rightPanelTab == 0,
                    onTap: () {
                      controller.rightPanelTab = 0;
                      controller.refresh();
                    },
                  ),
                  const SizedBox(width: 4),
                  _TabButton(
                    label: annotCount > 0 ? '注释 ($annotCount)' : '注释',
                    selected: controller.rightPanelTab == 1,
                    onTap: () {
                      controller.rightPanelTab = 1;
                      controller.refresh();
                    },
                  ),
                  const SizedBox(width: 4),
                  _TabButton(
                    label: '大纲',
                    selected: controller.rightPanelTab == 2,
                    onTap: () {
                      controller.rightPanelTab = 2;
                      controller.refresh();
                    },
                  ),
                  if (isOverlay && onClose != null) ...[
                    const SizedBox(width: 4),
                    DesktopHoverContainer(
                      tooltip: '关闭右侧面板 (Esc)',
                      onTap: onClose,
                      width: 32,
                      height: 32,
                      borderRadius: 7,
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
            ),
            Expanded(
              child: switch (controller.rightPanelTab) {
                0 => _PropertiesTab(controller: controller),
                1 => _AnnotationsListTab(controller: controller),
                _ => _OutlineTab(controller: controller),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Expanded(
      child: DesktopHoverContainer(
        active: selected,
        onTap: onTap,
        minHeight: 34,
        borderRadius: 7,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        activeColor: c.accentSoft,
        activeBorderColor: c.accent.withValues(alpha: 0.42),
        hoverColor: c.hoverFill,
        hoverBorderColor: c.hoverBorder,
        pressedColor: c.accentSoft,
        builder: (context, hovered, pressed) => Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppTypography.body,
              fontWeight:
                  (selected || hovered) ? FontWeight.w600 : FontWeight.w400,
              color: (selected || hovered) ? c.accent : c.mutedText,
            ),
          ),
        ),
      ),
    );
  }
}

class _PropertiesTab extends StatefulWidget {
  const _PropertiesTab({required this.controller});
  final EditorController controller;

  @override
  State<_PropertiesTab> createState() => _PropertiesTabState();
}

class _PropertiesTabState extends State<_PropertiesTab> {
  final TextEditingController _textCtrl = TextEditingController();
  final FocusNode _textFocus = FocusNode();
  String? _lastBoundId;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncFromController);
    _textFocus.addListener(_onTextFocusChange);
    _syncFromController();
  }

  @override
  void didUpdateWidget(covariant _PropertiesTab oldWidget) {
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
    _textFocus.removeListener(_onTextFocusChange);
    _textFocus.dispose();
    _textCtrl.dispose();
    super.dispose();
  }

  void _onTextFocusChange() {
    if (!_textFocus.hasFocus) {
      widget.controller.commitAnnotBatch();
      _syncFromController();
    }
  }

  void _syncFromController() {
    final ann = widget.controller.singleSelectedAnnotation;
    if (ann == null) {
      if (_lastBoundId != null) {
        widget.controller.commitAnnotBatch();
      }
      _lastBoundId = null;
      return;
    }
    if (_lastBoundId != ann.id) {
      if (_lastBoundId != null) {
        widget.controller.commitAnnotBatch();
      }
      _lastBoundId = ann.id;
      if (_textCtrl.text != ann.text) {
        _textCtrl.text = ann.text;
      }
    } else if (!_textFocus.hasFocus && _textCtrl.text != ann.text) {
      _textCtrl.text = ann.text;
    }
  }

  Widget _buildDocumentOverview(BuildContext context, EditorController ctrl) {
    final c = context.appColors;
    final pageIdx =
        (ctrl.currentPage - 1).clamp(0, ctrl.pageSizes.isEmpty ? 0 : ctrl.pageSizes.length - 1);
    final sizeText = ctrl.pageSizes.isNotEmpty
        ? () {
            final sz = ctrl.pageSizes[pageIdx];
            final wMm = pointsToMm(sz.w).round();
            final hMm = pointsToMm(sz.h).round();
            return '$wMm × $hMm mm';
          }()
        : '—';

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (ctrl.selectedIds.length > 1) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.accentSoft.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.accent.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '已多选 ${ctrl.selectedIds.length} 条批注',
                  style: TextStyle(
                    fontSize: AppTypography.title,
                    fontWeight: FontWeight.w600,
                    color: c.accent,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '可在画布拖动批量移动，或使用下方快捷动作。',
                  style: TextStyle(
                    fontSize: AppTypography.caption,
                    color: c.mutedText,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: ctrl.duplicateSelectedAnnotations,
                        icon: const Icon(
                          Icons.control_point_duplicate_rounded,
                          size: 16,
                        ),
                        label: const Text('再制'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: ctrl.deleteSelectedAnnotations,
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 16,
                          color: Color(0xFFDC2626),
                        ),
                        label: const Text(
                          '删除',
                          style: TextStyle(color: Color(0xFFDC2626)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
        ],
        Text(
          '文档信息',
          style: TextStyle(
            fontSize: AppTypography.caption,
            fontWeight: FontWeight.w600,
            color: c.mutedText,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.subtleFill,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ctrl.displayFileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppTypography.body,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (ctrl.filePath != null) ...[
                const SizedBox(height: 4),
                Text(
                  ctrl.filePath!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTypography.caption,
                    color: c.mutedText,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Divider(height: 1, color: c.border),
              const SizedBox(height: 10),
              _InfoRow(label: '当前页 / 总页数', value: '${ctrl.currentPage} / ${ctrl.pageCount}'),
              const SizedBox(height: 6),
              _InfoRow(label: '当前页尺寸', value: sizeText),
              const SizedBox(height: 6),
              _InfoRow(label: '批注数量', value: '${ctrl.annotations.length} 条'),
              const SizedBox(height: 6),
              _InfoRow(
                label: '文档状态',
                value: ctrl.encrypted
                    ? '加密只读'
                    : (ctrl.dirty ? '有未保存更改' : '已保存'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (ctrl.annotations.isNotEmpty || ctrl.outlineNodes.isNotEmpty) ...[
          Row(
            children: [
              if (ctrl.annotations.isNotEmpty)
                Expanded(
                  child: _QuickSwitchCard(
                    icon: Icons.comment_outlined,
                    label: '查看批注 (${ctrl.annotations.length})',
                    onTap: () {
                      ctrl.rightPanelTab = 1;
                      ctrl.refresh();
                    },
                  ),
                ),
              if (ctrl.annotations.isNotEmpty && ctrl.outlineNodes.isNotEmpty)
                const SizedBox(width: 8),
              if (ctrl.outlineNodes.isNotEmpty)
                Expanded(
                  child: _QuickSwitchCard(
                    icon: Icons.toc_rounded,
                    label: '查看大纲',
                    onTap: () {
                      ctrl.rightPanelTab = 2;
                      ctrl.refresh();
                    },
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.subtleFill.withValues(alpha: 0.65),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.border.withValues(alpha: 0.7)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.touch_app_outlined, size: 16, color: c.mutedText),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '在画布上选中任意批注，即可在此调整颜色、透明度、字体、层级或锁定状态。',
                  style: TextStyle(
                    fontSize: AppTypography.caption,
                    color: c.mutedText,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final c = context.appColors;
    final ann = ctrl.singleSelectedAnnotation;

    if (ann == null) {
      return _buildDocumentOverview(context, ctrl);
    }

    final showThickness = ann.kind == AnnotationKind.rect ||
        ann.kind == AnnotationKind.ellipse ||
        ann.kind == AnnotationKind.ink ||
        ann.kind == AnnotationKind.arrow ||
        ann.kind == AnnotationKind.measure;
    final showFontSize = ann.kind == AnnotationKind.text ||
        ann.kind == AnnotationKind.stamp;
    final showTextContent =
        ann.kind == AnnotationKind.text || ann.kind == AnnotationKind.note;
    final zCap = ctrl.selectedZOrderCapability();

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${ann.kind.label} · 第 ${ann.page + 1} 页',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: AppTypography.title,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            DesktopHoverContainer(
              tooltip: ann.locked ? '解锁注释' : '锁定注释（禁止拖动/缩放）',
              onTap: () => ctrl.patchAnnotation(
                ann.id,
                (cur) => cur.copyWith(locked: !cur.locked),
              ),
              width: 32,
              height: 32,
              borderRadius: 7,
              active: ann.locked,
              activeColor: const Color(0x22F59E0B),
              activeBorderColor: const Color(0x66D97706),
              hoverColor: c.hoverFill,
              hoverBorderColor: c.hoverBorder,
              builder: (context, hovered, _) => Center(
                child: Icon(
                  ann.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                  size: 16,
                  color: ann.locked
                      ? const Color(0xFFD97706)
                      : (hovered ? c.accent : c.mutedText),
                ),
              ),
            ),
            const SizedBox(width: 4),
            DesktopHoverContainer(
              tooltip: '删除此批注 (Delete)',
              onTap: ctrl.deleteSelectedAnnotations,
              width: 32,
              height: 32,
              borderRadius: 7,
              hoverColor: const Color(0x18DC2626),
              hoverBorderColor: const Color(0x66DC2626),
              pressedColor: const Color(0x2ADC2626),
              builder: (context, hovered, _) => const Center(
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 17,
                  color: Color(0xFFDC2626),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 8 色调色板（32x32 命中区 + 26x26 视觉色点，支持键盘聚焦）
        Text(
          '颜色',
          style: TextStyle(fontSize: AppTypography.caption, color: c.mutedText),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 2,
          runSpacing: 4,
          children: [
            for (final hex in kAnnotationPalette)
              DesktopHoverContainer(
                tooltip: hex.toUpperCase(),
                semanticLabel: '颜色 $hex',
                width: 32,
                height: 32,
                borderRadius: 16,
                hoverColor: c.hoverFill,
                hoverBorderColor: c.hoverBorder,
                onTap: () => ctrl.patchAnnotation(
                  ann.id,
                  (cur) => cur.copyWith(color: hex),
                ),
                builder: (context, hovered, pressed) {
                  final selected =
                      ann.color.toLowerCase() == hex.toLowerCase();
                  return Center(
                    child: AnimatedScale(
                      scale: pressed
                          ? 0.92
                          : hovered
                              ? 1.12
                              : 1.0,
                      duration: const Duration(milliseconds: 100),
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: hexToColor(hex),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected
                                ? c.accent
                                : hovered
                                    ? c.accent.withValues(alpha: 0.75)
                                    : Colors.black26,
                            width: selected || hovered ? 2.5 : 1,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 12),

        // 透明度
        Row(
          children: [
            Text(
              '透明度',
              style:
                  TextStyle(fontSize: AppTypography.caption, color: c.mutedText),
            ),
            const Spacer(),
            Text(
              '${(ann.opacity * 100).round()}%',
              style: const TextStyle(fontSize: AppTypography.body),
            ),
          ],
        ),
        Slider(
          min: 0.1,
          max: 1.0,
          value: ann.opacity.clamp(0.1, 1.0),
          onChangeStart: (_) => ctrl.beginAnnotBatch(),
          onChanged: (v) => ctrl.patchAnnotation(
            ann.id,
            (cur) => cur.copyWith(opacity: v),
            recordHistory: false,
          ),
          onChangeEnd: (_) => ctrl.commitAnnotBatch(),
        ),

        if (showThickness) ...[
          Row(
            children: [
              Text(
                '线宽',
                style: TextStyle(
                  fontSize: AppTypography.caption,
                  color: c.mutedText,
                ),
              ),
              const Spacer(),
              Text(
                '${ann.thickness.toStringAsFixed(1)} pt',
                style: const TextStyle(fontSize: AppTypography.body),
              ),
            ],
          ),
          Slider(
            min: 0.5,
            max: 10.0,
            value: ann.thickness.clamp(0.5, 10.0),
            onChangeStart: (_) => ctrl.beginAnnotBatch(),
            onChanged: (v) => ctrl.patchAnnotation(
              ann.id,
              (cur) => cur.copyWith(thickness: v),
              recordHistory: false,
            ),
            onChangeEnd: (_) => ctrl.commitAnnotBatch(),
          ),
        ],

        if (showFontSize) ...[
          Row(
            children: [
              Text(
                '字号',
                style: TextStyle(
                  fontSize: AppTypography.caption,
                  color: c.mutedText,
                ),
              ),
              const Spacer(),
              Text(
                '${ann.fontSize.round()} pt',
                style: const TextStyle(fontSize: AppTypography.body),
              ),
            ],
          ),
          Slider(
            min: 8,
            max: 72,
            value: ann.fontSize.clamp(8, 72),
            onChangeStart: (_) => ctrl.beginAnnotBatch(),
            onChanged: (v) => ctrl.patchAnnotation(
              ann.id,
              (cur) => cur.copyWith(fontSize: v),
              recordHistory: false,
            ),
            onChangeEnd: (_) => ctrl.commitAnnotBatch(),
          ),
          const SizedBox(height: 6),
          Text(
            '字体',
            style:
                TextStyle(fontSize: AppTypography.caption, color: c.mutedText),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            isExpanded: true,
            decoration: AppTheme.compactInputDecoration(c),
            initialValue: ctrl.systemFonts.any((f) => f.family == ann.fontFamily)
                ? ann.fontFamily
                : null,
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  '默认中文字体',
                  style: TextStyle(fontSize: AppTypography.body),
                ),
              ),
              for (final f in ctrl.systemFonts)
                DropdownMenuItem<String?>(
                  value: f.family,
                  child: Text(
                    f.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: AppTypography.body),
                  ),
                ),
            ],
            onChanged: (val) async {
              if (val != null) {
                final face = await SystemFontsService.findFont(val);
                if (face != null) {
                  await SystemFontsService.ensureFlutterFontLoaded(face);
                }
              }
              ctrl.patchAnnotation(
                ann.id,
                (cur) => val == null
                    ? cur.copyWith(clearFontFamily: true)
                    : cur.copyWith(fontFamily: val),
              );
            },
          ),
          const SizedBox(height: 12),
        ],

        if (showTextContent) ...[
          Text(
            '内容',
            style:
                TextStyle(fontSize: AppTypography.caption, color: c.mutedText),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _textCtrl,
            focusNode: _textFocus,
            minLines: 2,
            maxLines: 5,
            style: const TextStyle(fontSize: AppTypography.body),
            decoration: AppTheme.compactInputDecoration(c),
            onChanged: (v) {
              ctrl.beginAnnotBatch();
              ctrl.patchAnnotation(
                ann.id,
                (cur) => cur.copyWith(text: v),
                recordHistory: false,
              );
            },
            onSubmitted: (v) {
              ctrl.beginAnnotBatch();
              ctrl.patchAnnotation(
                ann.id,
                (cur) => cur.copyWith(text: v),
                recordHistory: false,
              );
              ctrl.commitAnnotBatch();
            },
          ),
          const SizedBox(height: 12),
        ],

        // 层级控制
        Text(
          '层级（同页内）',
          style: TextStyle(fontSize: AppTypography.caption, color: c.mutedText),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _ZBtn(
              label: '置底',
              enabled: zCap.canDown,
              onTap: () => ctrl.moveSelectedZOrder('bottom'),
            ),
            const SizedBox(width: 6),
            _ZBtn(
              label: '下移',
              enabled: zCap.canDown,
              onTap: () => ctrl.moveSelectedZOrder('down'),
            ),
            const SizedBox(width: 6),
            _ZBtn(
              label: '上移',
              enabled: zCap.canUp,
              onTap: () => ctrl.moveSelectedZOrder('up'),
            ),
            const SizedBox(width: 6),
            _ZBtn(
              label: '置顶',
              enabled: zCap.canUp,
              onTap: () => ctrl.moveSelectedZOrder('top'),
            ),
          ],
        ),
        const SizedBox(height: 16),

        OutlinedButton.icon(
          onPressed: ctrl.deleteSelectedAnnotations,
          icon: const Icon(
            Icons.delete_outline_rounded,
            size: 16,
            color: Color(0xFFDC2626),
          ),
          label: const Text(
            '删除此批注',
            style: TextStyle(
              color: Color(0xFFDC2626),
              fontSize: AppTypography.body,
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: AppTypography.caption, color: c.mutedText),
        ),
        const Spacer(),
        Text(
          value,
          style: const TextStyle(
            fontSize: AppTypography.caption,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _QuickSwitchCard extends StatelessWidget {
  const _QuickSwitchCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return DesktopHoverContainer(
      onTap: onTap,
      minHeight: 36,
      borderRadius: 8,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      baseColor: c.subtleFill,
      borderColor: c.border,
      hoverColor: c.hoverFill,
      hoverBorderColor: c.hoverBorder,
      pressedColor: c.accentSoft,
      builder: (context, hovered, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 15,
            color: hovered ? c.accent : c.mutedText,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTypography.caption,
                fontWeight: FontWeight.w500,
                color: hovered
                    ? c.accent
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ZBtn extends StatelessWidget {
  const _ZBtn({
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
    return Expanded(
      child: DesktopHoverContainer(
        enabled: enabled,
        onTap: enabled ? onTap : null,
        minHeight: 32,
        borderRadius: 6,
        padding: const EdgeInsets.symmetric(vertical: 6),
        baseColor: c.subtleFill,
        borderColor: c.border.withValues(alpha: enabled ? 0.8 : 0.4),
        hoverColor: c.hoverFill,
        hoverBorderColor: c.hoverBorder,
        pressedColor: c.accentSoft,
        builder: (context, hovered, pressed) => Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppTypography.body,
              fontWeight: hovered ? FontWeight.w600 : FontWeight.w400,
              color: !enabled
                  ? c.mutedText.withValues(alpha: 0.4)
                  : hovered
                      ? c.accent
                      : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _AnnotationsListTab extends StatelessWidget {
  const _AnnotationsListTab({required this.controller});
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final items = controller.annotations.where((a) {
      if (controller.listCurrentPageOnly &&
          a.page != controller.currentPage - 1) {
        return false;
      }
      if (controller.listKindFilter != null &&
          a.kind != controller.listKindFilter) {
        return false;
      }
      return true;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: Row(
            children: [
              ChoiceChip(
                label: Text(
                  controller.listCurrentPageOnly ? '当前页' : '全部页',
                  style: const TextStyle(fontSize: AppTypography.body),
                ),
                selected: controller.listCurrentPageOnly,
                onSelected: (v) {
                  controller.listCurrentPageOnly = v;
                  controller.refresh();
                },
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DesktopHoverDropdownShell(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<AnnotationKind?>(
                      isDense: true,
                      isExpanded: true,
                      value: controller.listKindFilter,
                      style: TextStyle(
                        fontSize: AppTypography.body,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      items: [
                        const DropdownMenuItem<AnnotationKind?>(
                          value: null,
                          child: Text('全部类型'),
                        ),
                        for (final k in AnnotationKind.values)
                          DropdownMenuItem<AnnotationKind?>(
                            value: k,
                            child: Text(k.label),
                          ),
                      ],
                      onChanged: (v) {
                        controller.listKindFilter = v;
                        controller.refresh();
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: items.isEmpty
              ? Center(
                  child: Text(
                    '暂无符合条件的批注',
                    style: TextStyle(
                      fontSize: AppTypography.body,
                      color: c.mutedText,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (_, index) {
                    final ann = items[index];
                    final selected = controller.selectedIds.contains(ann.id);
                    return ListTile(
                      dense: true,
                      selected: selected,
                      selectedTileColor: c.accentSoft.withValues(alpha: 0.65),
                      leading: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: hexToColor(ann.color),
                          shape: BoxShape.circle,
                        ),
                      ),
                      title: Text(
                        ann.summary,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: AppTypography.body),
                      ),
                      subtitle: Text(
                        '${ann.kind.label} · 第 ${ann.page + 1} 页',
                        style: TextStyle(
                          fontSize: AppTypography.caption,
                          color: c.mutedText,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close_rounded, size: 16),
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        tooltip: '删除',
                        onPressed: () =>
                            controller.deleteAnnotationById(ann.id),
                      ),
                      onTap: () {
                        controller.jumpToPage(ann.page + 1);
                        controller.selectAnnotation(ann.id);
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _OutlineTab extends StatelessWidget {
  const _OutlineTab({required this.controller});
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    if (controller.outlineNodes.isEmpty) {
      return Center(
        child: Text(
          '当前文档无书签大纲',
          style: TextStyle(fontSize: AppTypography.body, color: c.mutedText),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 6),
      children: [
        for (final node in controller.outlineNodes)
          _OutlineNodeTile(
            node: node,
            depth: 0,
            controller: controller,
          ),
      ],
    );
  }
}

class _OutlineNodeTile extends StatefulWidget {
  const _OutlineNodeTile({
    required this.node,
    required this.depth,
    required this.controller,
  });

  final PdfOutlineNode node;
  final int depth;
  final EditorController controller;

  @override
  State<_OutlineNodeTile> createState() => _OutlineNodeTileState();
}

class _OutlineNodeTileState extends State<_OutlineNodeTile> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final hasChildren = widget.node.children.isNotEmpty;
    final dest = widget.node.dest;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(
            left: 4.0 + widget.depth * 14.0,
            right: 4,
            top: 1,
            bottom: 1,
          ),
          child: DesktopHoverContainer(
            enabled: dest != null || hasChildren,
            onTap: dest != null
                ? () {
                    if (widget.controller.viewerController.isReady) {
                      widget.controller.viewerController.goToDest(dest);
                    } else {
                      widget.controller.jumpToPage(dest.pageNumber);
                    }
                  }
                : hasChildren
                    ? () => setState(() => _expanded = !_expanded)
                    : null,
            minHeight: 32,
            borderRadius: 6,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            hoverColor: c.hoverFill,
            hoverBorderColor: c.hoverBorder,
            pressedColor: c.accentSoft,
            scaleOnPress: 0.99,
            builder: (context, hovered, pressed) => Row(
              children: [
                if (hasChildren)
                  DesktopHoverContainer(
                    tooltip: _expanded ? '折叠子书签' : '展开子书签',
                    width: 28,
                    height: 28,
                    borderRadius: 5,
                    hoverColor: c.accentSoft,
                    hoverBorderColor: c.hoverBorder,
                    onTap: () => setState(() => _expanded = !_expanded),
                    builder: (context, chevronHover, _) => Center(
                      child: Icon(
                        _expanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_right_rounded,
                        size: 18,
                        color: chevronHover ? c.accent : c.mutedText,
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 28),
                const SizedBox(width: 2),
                Expanded(
                  child: Text(
                    widget.node.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTypography.body,
                      fontWeight: hovered ? FontWeight.w500 : FontWeight.w400,
                      color: hovered
                          ? c.accent
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                if (dest != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    '${dest.pageNumber}',
                    style: TextStyle(
                      fontSize: AppTypography.caption,
                      color: hovered ? c.accent : c.mutedText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (hasChildren && _expanded)
          for (final child in widget.node.children)
            _OutlineNodeTile(
              node: child,
              depth: widget.depth + 1,
              controller: widget.controller,
            ),
      ],
    );
  }
}
