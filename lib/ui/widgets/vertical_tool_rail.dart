import 'package:flutter/material.dart';

import '../../models/annotation_model.dart';
import '../../services/system_fonts_service.dart';
import '../../state/editor_controller.dart';
import '../theme/app_theme.dart';
import 'desktop_controls.dart';
import 'hover_feedback.dart';

const editorToolIcons = {
  EditorTool.select: Icons.near_me_outlined,
  EditorTool.highlight: Icons.highlight_rounded,
  EditorTool.rect: Icons.crop_square_rounded,
  EditorTool.ellipse: Icons.panorama_fish_eye_rounded,
  EditorTool.ink: Icons.gesture_rounded,
  EditorTool.arrow: Icons.north_east_rounded,
  EditorTool.measure: Icons.straighten_rounded,
  EditorTool.text: Icons.title_rounded,
  EditorTool.note: Icons.sticky_note_2_outlined,
  EditorTool.stamp: Icons.approval_outlined,
  EditorTool.image: Icons.add_photo_alternate_outlined,
};

class VerticalToolRail extends StatelessWidget {
  const VerticalToolRail({super.key, required this.controller});

  static const width = 46.0;
  static const _groups = [
    [EditorTool.select, EditorTool.highlight],
    [EditorTool.rect, EditorTool.ellipse, EditorTool.ink, EditorTool.arrow, EditorTool.measure],
    [EditorTool.text, EditorTool.note, EditorTool.stamp, EditorTool.image],
  ];

  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return SizedBox(
      width: width,
      height: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: c.surfaceBg,
          border: Border(right: BorderSide(color: c.border)),
        ),
        child: SingleChildScrollView(
          primary: false,
          padding: const EdgeInsets.fromLTRB(0, 6, 1, 6),
          child: Column(
            children: [
              for (var i = 0; i < _groups.length; i++) ...[
                if (i > 0)
                  Container(
                    width: 20,
                    height: 1,
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    color: c.border,
                  ),
                for (final tool in _groups[i])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: _ToolButton(
                      tool: tool,
                      active: controller.tool == tool,
                      onTap: () => controller.setTool(tool),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({required this.tool, required this.active, required this.onTap});

  final EditorTool tool;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.centerLeft,
      children: [
        DesktopHoverContainer(
          width: 34,
          height: 34,
          borderRadius: 7,
          tooltip: tool.tooltip,
          semanticLabel: tool.tooltip,
          active: active,
          onTap: onTap,
          activeColor: c.accentSoft,
          activeBorderColor: Colors.transparent,
          hoverColor: c.hoverFill,
          hoverBorderColor: Colors.transparent,
          pressedColor: c.accentSoft,
          builder: (context, hovered, _) => Icon(
            editorToolIcons[tool],
            size: 18,
            color: active || hovered ? c.accent : c.mutedText,
          ),
        ),
        if (active)
          Positioned(
            left: -4,
            child: IgnorePointer(
              child: Container(
                width: 2.5,
                height: 18,
                decoration: BoxDecoration(
                  color: c.accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class ToolContextStrip extends StatelessWidget {
  const ToolContextStrip({super.key, required this.controller});

  final EditorController controller;

  static bool _showsFont(EditorController controller) =>
      controller.tool == EditorTool.text || controller.tool == EditorTool.stamp;

  static bool isVisibleFor(EditorController controller) =>
      _showsFont(controller) || controller.selectedIds.isNotEmpty;

  // A single-line budget; on narrower canvases the control groups wrap together.
  static double inlineWidthFor(EditorController controller) =>
      16 +
      (controller.tool == EditorTool.stamp ? 144 : 0) +
      (_showsFont(controller) ? 188 : 0) +
      (controller.selectedIds.isNotEmpty ? 258 : 0);

  @override
  Widget build(BuildContext context) {
    if (!isVisibleFor(controller)) return const SizedBox.shrink();
    final c = context.appColors;
    return Material(
      color: c.elevatedBg,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: c.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (controller.tool == EditorTool.stamp)
              _ControlGroup(
                label: '图章:',
                child: DesktopSelect<StampPreset>(
                  value: controller.stampPreset,
                  minHeight: 30,
                  borderRadius: 6,
                  items: [
                    for (final preset in StampPreset.values)
                      DropdownMenuItem(
                        value: preset,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: Color(preset.colorValue),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(preset.label, style: const TextStyle(fontSize: AppTypography.body)),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (preset) {
                    if (preset == null) return;
                    controller.stampPreset = preset;
                    controller.refresh();
                  },
                ),
              ),
            if (_showsFont(controller))
              _ControlGroup(
                label: '字体:',
                child: SizedBox(
                  width: 146,
                  child: DesktopSelect<String?>(
                    value: controller.systemFonts.any((font) => font.family == controller.defaultFontFamily)
                        ? controller.defaultFontFamily
                        : null,
                    minHeight: 30,
                    borderRadius: 6,
                    isExpanded: true,
                    hint: const Text('默认中文字体', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: AppTypography.body)),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('默认中文字体', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: AppTypography.body)),
                      ),
                      for (final font in controller.systemFonts)
                        DropdownMenuItem<String?>(
                          value: font.family,
                          child: Text(font.label, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: AppTypography.body)),
                        ),
                    ],
                    onChanged: (family) async {
                      if (family != null) {
                        final face = await SystemFontsService.findFont(family);
                        if (face != null) await SystemFontsService.ensureFlutterFontLoaded(face);
                      }
                      if (!context.mounted) return;
                      controller.defaultFontFamily = family;
                      controller.refresh();
                    },
                  ),
                ),
              ),
            if (controller.selectedIds.isNotEmpty)
              Wrap(
                spacing: 3,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '已选 ${controller.selectedIds.length} 项',
                      style: TextStyle(fontSize: AppTypography.caption, fontWeight: FontWeight.w600, color: c.accent),
                    ),
                  ),
                  _SelectionAction(icon: Icons.copy_rounded, label: '复制', onTap: controller.copySelectedAnnotations),
                  _SelectionAction(icon: Icons.control_point_duplicate_rounded, label: '再制', onTap: controller.duplicateSelectedAnnotations),
                  _SelectionAction(icon: Icons.delete_outline_rounded, label: '删除', danger: true, onTap: controller.deleteSelectedAnnotations),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ControlGroup extends StatelessWidget {
  const _ControlGroup({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: AppTypography.caption, color: context.appColors.mutedText)),
        const SizedBox(width: 5),
        Flexible(child: child),
      ],
    );
  }
}

class _SelectionAction extends StatelessWidget {
  const _SelectionAction({required this.icon, required this.label, required this.onTap, this.danger = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final scheme = Theme.of(context).colorScheme;
    return DesktopHoverContainer(
      minHeight: 30,
      borderRadius: 6,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      onTap: onTap,
      hoverColor: danger ? scheme.error.withValues(alpha: 0.1) : c.hoverFill,
      hoverBorderColor: Colors.transparent,
      pressedColor: c.accentSoft,
      builder: (context, hovered, _) {
        final color = danger ? scheme.error : hovered ? c.accent : c.mutedText;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: AppTypography.caption, color: color)),
          ],
        );
      },
    );
  }
}
