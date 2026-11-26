import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'hover_feedback.dart';

/// 统一的桌面弹窗标题头（图标徽章 + 标题 + 可选副标题 + 可选右上角关闭按钮）
class DesktopDialogHeader extends StatelessWidget {
  const DesktopDialogHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.iconBackground,
    this.onClose,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? iconColor;
  final Color? iconBackground;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final fg = iconColor ?? c.accent;
    final bg = iconBackground ?? c.accentSoft;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 19, color: fg),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTypography.title,
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: AppTypography.caption,
                    fontWeight: FontWeight.w400,
                    color: c.mutedText,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (onClose != null) ...[
          const SizedBox(width: 8),
          DesktopHoverContainer(
            tooltip: '关闭',
            onTap: onClose,
            width: 30,
            height: 30,
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
    );
  }
}

/// 自定义桌面端复选框（圆角柔和、勾选有明确高对比视觉，无 Material 大水波纹）
class DesktopCheckbox extends StatelessWidget {
  const DesktopCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.size = 18,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final enabled = onChanged != null;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return HoverStateBuilder(
      enabled: enabled,
      onTap: enabled ? () => onChanged!(!value) : null,
      builder: (context, hovered, pressed) {
        final bg = !enabled
            ? (value ? c.accent.withValues(alpha: 0.42) : c.subtleFill)
            : value
                ? c.accent
                : hovered
                    ? c.hoverFill
                    : c.surfaceBg;
        final borderColor = !enabled
            ? c.border.withValues(alpha: 0.65)
            : value
                ? c.accent
                : hovered
                    ? c.accent
                    : c.mutedText.withValues(alpha: 0.55);

        return AnimatedScale(
          scale: (enabled && pressed) ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 80),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOutCubic,
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: borderColor, width: 1.5),
            ),
            child: value
                ? Center(
                    child: Icon(
                      Icons.check_rounded,
                      size: size - 4,
                      color: onPrimary,
                    ),
                  )
                : null,
          ),
        );
      },
    );
  }
}

/// 替代原生 CheckboxListTile 的桌面端紧凑勾选行
class DesktopCheckboxRow extends StatelessWidget {
  const DesktopCheckboxRow({
    super.key,
    required this.value,
    required this.label,
    required this.onChanged,
    this.subtitle,
  });

  final bool value;
  final String label;
  final String? subtitle;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final enabled = onChanged != null;
    return DesktopHoverContainer(
      enabled: enabled,
      onTap: enabled ? () => onChanged!(!value) : null,
      borderRadius: 7,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      hoverColor: c.hoverFill.withValues(alpha: 0.65),
      hoverBorderColor: c.hoverBorder.withValues(alpha: 0.55),
      pressedColor: c.accentSoft,
      scaleOnPress: 0.99,
      builder: (context, hovered, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IgnorePointer(
            child: DesktopCheckbox(
              value: value,
              onChanged: enabled ? (_) {} : null,
            ),
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: AppTypography.body,
                    color: enabled
                        ? (hovered
                            ? c.accent
                            : Theme.of(context).colorScheme.onSurface)
                        : c.mutedText.withValues(alpha: 0.55),
                  ),
                ),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: AppTypography.caption,
                      color: c.mutedText,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 桌面端风格化下拉选择器（统一圆角边框、悬停高亮、自定义浮层样式，替换裸 Material DropdownButton）
class DesktopSelect<T> extends StatelessWidget {
  const DesktopSelect({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.onTap,
    this.isExpanded = false,
    this.minHeight = 36,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
    this.borderRadius = 8.0,
    this.baseColor,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final Widget? hint;
  final VoidCallback? onTap;
  final bool isExpanded;
  final double minHeight;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? baseColor;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return HoverStateBuilder(
      enabled: onChanged != null,
      builder: (context, hovered, _) => AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        constraints: BoxConstraints(minHeight: minHeight),
        padding: padding,
        alignment: Alignment.centerLeft,
        decoration: BoxDecoration(
          color: hovered ? c.hoverFill : (baseColor ?? c.subtleFill),
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: hovered ? c.hoverBorder : c.border,
          ),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            items: items,
            onChanged: onChanged,
            onTap: onTap,
            hint: hint,
            isDense: true,
            isExpanded: isExpanded,
            dropdownColor: c.elevatedBg,
            elevation: 8,
            borderRadius: BorderRadius.circular(10),
            focusColor: Colors.transparent,
            icon: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: hovered ? c.accent : c.mutedText,
              ),
            ),
            style: TextStyle(
              fontSize: AppTypography.body,
              color: onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

/// 桌面端分段控件（与底部状态栏阅读视图切换统一，替换 Material 3 胶囊 SegmentedButton）
class DesktopSegmentedOption<T> {
  const DesktopSegmentedOption({
    required this.value,
    required this.label,
    this.icon,
  });

  final T value;
  final String label;
  final IconData? icon;
}

class DesktopSegmentedControl<T> extends StatelessWidget {
  const DesktopSegmentedControl({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<DesktopSegmentedOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.subtleFill,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          for (var i = 0; i < options.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: DesktopHoverContainer(
                active: options[i].value == value,
                onTap: () => onChanged(options[i].value),
                minHeight: 34,
                borderRadius: 6.5,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                activeColor: c.surfaceBg,
                activeBorderColor: c.border,
                hoverColor: c.hoverFill,
                hoverBorderColor: c.hoverBorder,
                pressedColor: c.accentSoft,
                scaleOnPress: 0.98,
                builder: (context, hovered, _) {
                  final active = options[i].value == value;
                  final fg = (active || hovered) ? c.accent : c.mutedText;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (options[i].icon != null) ...[
                        Icon(options[i].icon, size: 15, color: fg),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          options[i].label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppTypography.body,
                            fontWeight: (active || hovered)
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: fg,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 桌面端进度条卡片（圆角细轨 + 百分比/文案提示，替换弹窗内裸 LinearProgressIndicator）
class DesktopProgressPanel extends StatelessWidget {
  const DesktopProgressPanel({
    super.key,
    required this.message,
    this.progress,
    this.detail,
  });

  final String message;
  final double? progress;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final pct = progress != null ? '${(progress!.clamp(0.0, 1.0) * 100).round()}%' : null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.subtleFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.accent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: AppTypography.body,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (pct != null) ...[
                const SizedBox(width: 8),
                Text(
                  pct,
                  style: TextStyle(
                    fontSize: AppTypography.caption,
                    fontWeight: FontWeight.w600,
                    color: c.accent,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
            ),
          ),
          if (detail != null && detail!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              detail!,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: AppTypography.caption,
                color: c.mutedText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 统一菜单项行（图标 + 文案 + 可选快捷键徽标 / 选中勾选 / 危险态着色）
class DesktopMenuItemRow extends StatelessWidget {
  const DesktopMenuItemRow({
    super.key,
    required this.label,
    this.icon,
    this.shortcut,
    this.selected = false,
    this.danger = false,
  });

  final String label;
  final IconData? icon;
  final String? shortcut;
  final bool selected;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final fg = danger
        ? AppTheme.danger
        : selected
            ? c.accent
            : null;
    return Row(
      children: [
        if (icon != null) ...[
          Icon(
            icon,
            size: 16,
            color: danger
                ? AppTheme.danger
                : selected
                    ? c.accent
                    : c.mutedText,
          ),
          const SizedBox(width: 9),
        ],
        Expanded(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppTypography.body,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: fg,
            ),
          ),
        ),
        if (selected) ...[
          const SizedBox(width: 8),
          Icon(Icons.check_rounded, size: 16, color: c.accent),
        ] else if (shortcut != null && shortcut!.isNotEmpty) ...[
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: c.subtleFill,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: c.border),
            ),
            child: Text(
              shortcut!,
              style: TextStyle(
                fontSize: AppTypography.caption,
                color: c.mutedText,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// 表单字段上方小标题（替代部分冗杂的浮动 label 或裸 Text）
class DesktopFieldLabel extends StatelessWidget {
  const DesktopFieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: AppTypography.caption,
        fontWeight: FontWeight.w600,
        color: context.appColors.mutedText,
      ),
    );
  }
}
