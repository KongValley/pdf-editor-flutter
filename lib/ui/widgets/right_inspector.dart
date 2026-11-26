import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../models/annotation_model.dart';
import '../../services/system_fonts_service.dart';
import '../../state/editor_controller.dart';
import '../../utils/page_range.dart';
import '../theme/app_theme.dart';
import 'hover_feedback.dart';

class RightInspector extends StatelessWidget {
  const RightInspector({super.key, required this.controller});

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Material(
      color: c.surfaceBg,
      child: Container(
        width: 292,
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
                const SizedBox(width: 6),
                _TabButton(
                  label: '注释 (${controller.annotations.length})',
                  selected: controller.rightPanelTab == 1,
                  onTap: () {
                    controller.rightPanelTab = 1;
                    controller.refresh();
                  },
                ),
                const SizedBox(width: 6),
                _TabButton(
                  label: '大纲',
                  selected: controller.rightPanelTab == 2,
                  onTap: () {
                    controller.rightPanelTab = 2;
                    controller.refresh();
                  },
                ),
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
        borderRadius: 7,
        padding: const EdgeInsets.symmetric(vertical: 6),
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
              fontWeight: (selected || hovered) ? FontWeight.w600 : FontWeight.w400,
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

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final c = context.appColors;
    final ann = ctrl.singleSelectedAnnotation;

    if (ann == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            ctrl.selectedIds.length > 1
                ? '已多选 ${ctrl.selectedIds.length} 条批注\n可拖动批量移动或按 Delete 删除'
                : '在画布上点击选中一条批注\n即可在此调整颜色、透明度、字体、层级或锁定状态',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppTypography.body,
              color: c.mutedText,
              height: 1.5,
            ),
          ),
        ),
      );
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
            IconButton(
              icon: Icon(
                ann.locked ? Icons.lock_rounded : Icons.lock_open_rounded,
                size: 17,
                color: ann.locked ? const Color(0xFFD97706) : c.mutedText,
              ),
              tooltip: ann.locked ? '解锁注释' : '锁定注释（禁止拖动/缩放）',
              onPressed: () => ctrl.patchAnnotation(
                ann.id,
                (cur) => cur.copyWith(locked: !cur.locked),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 8 色调色板
        Text(
          '颜色',
          style: TextStyle(fontSize: AppTypography.body, color: c.mutedText),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final hex in kAnnotationPalette)
              HoverStateBuilder(
                enabled: true,
                onTap: () => ctrl.patchAnnotation(
                  ann.id,
                  (cur) => cur.copyWith(color: hex),
                ),
                builder: (context, hovered, pressed) {
                  final selected =
                      ann.color.toLowerCase() == hex.toLowerCase();
                  return AnimatedScale(
                    scale: pressed
                        ? 0.92
                        : hovered
                            ? 1.15
                            : 1.0,
                    duration: const Duration(milliseconds: 100),
                    child: Container(
                      width: 22,
                      height: 22,
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
                  );
                },
              ),
          ],
        ),
        const SizedBox(height: 14),

        // 透明度
        Row(
          children: [
            Text(
              '透明度',
              style: TextStyle(fontSize: AppTypography.body, color: c.mutedText),
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
                  fontSize: AppTypography.body,
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
                  fontSize: AppTypography.body,
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
            style: TextStyle(fontSize: AppTypography.body, color: c.mutedText),
          ),
          const SizedBox(height: 6),
          DropdownButtonFormField<String?>(
            isExpanded: true,
            initialValue: ctrl.systemFonts.any((f) => f.family == ann.fontFamily)
                ? ann.fontFamily
                : null,
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('默认中文字体',
                    style: TextStyle(fontSize: AppTypography.body)),
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
            style: TextStyle(fontSize: AppTypography.body, color: c.mutedText),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _textCtrl,
            focusNode: _textFocus,
            minLines: 2,
            maxLines: 5,
            style: const TextStyle(fontSize: AppTypography.body),
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
          style: TextStyle(fontSize: AppTypography.body, color: c.mutedText),
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
        const SizedBox(height: 18),

        OutlinedButton.icon(
          onPressed: ctrl.deleteSelectedAnnotations,
          icon: const Icon(Icons.delete_outline_rounded,
              size: 16, color: Color(0xFFE03131)),
          label: const Text(
            '删除此批注',
            style: TextStyle(
              color: Color(0xFFE03131),
              fontSize: AppTypography.body,
            ),
          ),
        ),
      ],
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
                          fontSize: AppTypography.body,
                          color: c.mutedText,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.close_rounded, size: 15),
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
            borderRadius: 6,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            hoverColor: c.hoverFill,
            hoverBorderColor: c.hoverBorder,
            pressedColor: c.accentSoft,
            scaleOnPress: 0.99,
            builder: (context, hovered, pressed) => Row(
              children: [
                if (hasChildren)
                  DesktopHoverContainer(
                    width: 20,
                    height: 20,
                    borderRadius: 4,
                    hoverColor: c.accentSoft,
                    hoverBorderColor: c.hoverBorder,
                    onTap: () => setState(() => _expanded = !_expanded),
                    builder: (context, chevronHover, _) => Center(
                      child: Icon(
                        _expanded
                            ? Icons.keyboard_arrow_down_rounded
                            : Icons.keyboard_arrow_right_rounded,
                        size: 16,
                        color: chevronHover ? c.accent : c.mutedText,
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 20),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    widget.node.title,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTypography.body,
                      color: (dest != null || hasChildren) && hovered
                          ? c.accent
                          : dest == null
                              ? c.mutedText
                              : null,
                    ),
                  ),
                ),
                if (dest != null)
                  Text(
                    '${dest.pageNumber}',
                    style: TextStyle(
                      fontSize: AppTypography.body,
                      color: hovered ? c.accent : c.mutedText,
                    ),
                  ),
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
