import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 桌面端悬停 / 按下交互状态构建器（支持独立点击或嵌套在 PopupMenuButton 内）
class HoverStateBuilder extends StatefulWidget {
  const HoverStateBuilder({
    super.key,
    required this.enabled,
    required this.builder,
    this.onTap,
    this.cursor,
  });

  final bool enabled;
  final VoidCallback? onTap;
  final MouseCursor? cursor;
  final Widget Function(BuildContext context, bool hovered, bool pressed) builder;

  @override
  State<HoverStateBuilder> createState() => _HoverStateBuilderState();
}

class _HoverStateBuilderState extends State<HoverStateBuilder> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  void didUpdateWidget(covariant HoverStateBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && (_hovered || _pressed)) {
      _hovered = false;
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled;
    final child = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: active
          ? (_) {
              if (!_pressed && mounted) setState(() => _pressed = true);
            }
          : null,
      onPointerUp: (_) {
        if (_pressed && mounted) setState(() => _pressed = false);
      },
      onPointerCancel: (_) {
        if (_pressed && mounted) setState(() => _pressed = false);
      },
      child: widget.onTap == null
          ? widget.builder(context, active && _hovered, active && _pressed)
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: active ? widget.onTap : null,
              child: widget.builder(
                context,
                active && _hovered,
                active && _pressed,
              ),
            ),
    );

    return MouseRegion(
      cursor: active
          ? (widget.cursor ?? SystemMouseCursors.click)
          : SystemMouseCursors.basic,
      onEnter: (_) {
        if (active && !_hovered && mounted) {
          setState(() => _hovered = true);
        }
      },
      onExit: (_) {
        if ((_hovered || _pressed) && mounted) {
          setState(() {
            _hovered = false;
            _pressed = false;
          });
        }
      },
      child: child,
    );
  }
}

/// 统一的桌面触感胶囊 / 卡片按钮容器（自带悬停底色、描边、阴影与按压微缩反馈）
class DesktopHoverContainer extends StatelessWidget {
  const DesktopHoverContainer({
    super.key,
    required this.builder,
    this.tooltip,
    this.onTap,
    this.enabled = true,
    this.active = false,
    this.width,
    this.height,
    this.padding = EdgeInsets.zero,
    this.borderRadius = 7.0,
    this.baseColor = Colors.transparent,
    this.hoverColor,
    this.pressedColor,
    this.activeColor,
    this.borderColor = Colors.transparent,
    this.hoverBorderColor,
    this.activeBorderColor,
    this.hoverShadow,
    this.scaleOnPress = 0.96,
  });

  final Widget Function(BuildContext context, bool hovered, bool pressed) builder;
  final String? tooltip;
  final VoidCallback? onTap;
  final bool enabled;
  final bool active;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color baseColor;
  final Color? hoverColor;
  final Color? pressedColor;
  final Color? activeColor;
  final Color borderColor;
  final Color? hoverBorderColor;
  final Color? activeBorderColor;
  final List<BoxShadow>? hoverShadow;
  final double scaleOnPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final resolvedHoverBg = hoverColor ?? cs.primary.withValues(alpha: 0.12);
    final resolvedPressedBg =
        pressedColor ?? cs.primary.withValues(alpha: 0.22);
    final resolvedActiveBg = activeColor ?? cs.primary.withValues(alpha: 0.14);
    final resolvedHoverBorder =
        hoverBorderColor ?? cs.primary.withValues(alpha: 0.48);
    final resolvedActiveBorder =
        activeBorderColor ?? cs.primary.withValues(alpha: 0.45);

    Widget content = HoverStateBuilder(
      enabled: enabled,
      onTap: onTap,
      builder: (context, hovered, pressed) {
        final bg = !enabled
            ? baseColor
            : pressed
                ? resolvedPressedBg
                : hovered
                    ? (active
                        ? Color.alphaBlend(
                            cs.primary.withValues(alpha: 0.08),
                            resolvedActiveBg,
                          )
                        : resolvedHoverBg)
                    : active
                        ? resolvedActiveBg
                        : baseColor;
        final bColor = !enabled
            ? borderColor
            : (hovered || pressed)
                ? resolvedHoverBorder
                : active
                    ? resolvedActiveBorder
                    : borderColor;

        return AnimatedScale(
          scale: (enabled && pressed) ? scaleOnPress : 1.0,
          duration: const Duration(milliseconds: 85),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            curve: Curves.easeOutCubic,
            width: width,
            height: height,
            padding: padding,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: bColor, width: 1),
              boxShadow: (enabled && hovered && !pressed) ? hoverShadow : null,
            ),
            child: builder(context, hovered, pressed),
          ),
        );
      },
    );

    if (tooltip != null && tooltip!.isNotEmpty) {
      content = Tooltip(message: tooltip!, child: content);
    }
    return content;
  }
}

/// 下拉选择器桌面端悬停描边外壳（点击直接透传给内部 DropdownButton）
class DesktopHoverDropdownShell extends StatelessWidget {
  const DesktopHoverDropdownShell({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    this.borderRadius = 6.0,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).extension<AppColors>();
    final cs = Theme.of(context).colorScheme;
    final baseBg = c?.subtleFill ?? cs.onSurface.withValues(alpha: 0.04);
    final hoverBg = c?.hoverFill ?? cs.primary.withValues(alpha: 0.12);
    final baseBorder = c?.border ?? cs.outlineVariant;
    final hoverBorder = c?.hoverBorder ?? cs.primary.withValues(alpha: 0.45);

    return HoverStateBuilder(
      enabled: true,
      builder: (context, hovered, pressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOutCubic,
        padding: padding,
        decoration: BoxDecoration(
          color: hovered ? hoverBg : baseBg,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(
            color: hovered ? hoverBorder : baseBorder.withValues(alpha: 0.7),
          ),
        ),
        child: child,
      ),
    );
  }
}
