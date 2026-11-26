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

/// 统一的桌面触感胶囊 / 卡片按钮容器（自带悬停底色、描边、阴影、键盘焦点圈与按压微缩反馈）
class DesktopHoverContainer extends StatefulWidget {
  const DesktopHoverContainer({
    super.key,
    required this.builder,
    this.tooltip,
    this.semanticLabel,
    this.onTap,
    this.enabled = true,
    this.active = false,
    this.focusable = true,
    this.focusNode,
    this.onFocusChange,
    this.width,
    this.height,
    this.minWidth,
    this.minHeight,
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
  final String? semanticLabel;
  final VoidCallback? onTap;
  final bool enabled;
  final bool active;
  final bool focusable;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;
  final double? width;
  final double? height;
  final double? minWidth;
  final double? minHeight;
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
  State<DesktopHoverContainer> createState() => _DesktopHoverContainerState();
}

class _DesktopHoverContainerState extends State<DesktopHoverContainer> {
  bool _focused = false;

  @override
  void didUpdateWidget(covariant DesktopHoverContainer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _focused) {
      _focused = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final appColors = Theme.of(context).extension<AppColors>();
    final focusRingColor = appColors?.accent ?? cs.primary;
    final resolvedHoverBg = widget.hoverColor ?? cs.primary.withValues(alpha: 0.12);
    final resolvedPressedBg =
        widget.pressedColor ?? cs.primary.withValues(alpha: 0.22);
    final resolvedActiveBg =
        widget.activeColor ?? cs.primary.withValues(alpha: 0.14);
    final resolvedHoverBorder =
        widget.hoverBorderColor ?? cs.primary.withValues(alpha: 0.48);
    final resolvedActiveBorder =
        widget.activeBorderColor ?? cs.primary.withValues(alpha: 0.45);
    // Use same-hue 0-alpha endpoints instead of Colors.transparent (0x00000000)
    // so AnimatedContainer color lerping never passes through dark gray.
    final resolvedBaseBg = widget.baseColor.a == 0
        ? resolvedHoverBg.withValues(alpha: 0)
        : widget.baseColor;
    final resolvedBaseBorder = widget.borderColor.a == 0
        ? resolvedHoverBorder.withValues(alpha: 0)
        : widget.borderColor;

    final canFocus =
        widget.focusable && widget.enabled && widget.onTap != null;

    Widget content = HoverStateBuilder(
      enabled: widget.enabled,
      onTap: widget.onTap,
      builder: (context, hovered, pressed) {
        final showFocus = canFocus && _focused;
        final bg = !widget.enabled
            ? resolvedBaseBg
            : pressed
                ? resolvedPressedBg
                : hovered
                    ? (widget.active
                        ? Color.alphaBlend(
                            cs.primary.withValues(alpha: 0.08),
                            resolvedActiveBg,
                          )
                        : resolvedHoverBg)
                    : widget.active
                        ? resolvedActiveBg
                        : resolvedBaseBg;
        final bColor = !widget.enabled
            ? resolvedBaseBorder
            : showFocus
                ? focusRingColor
                : (hovered || pressed)
                    ? resolvedHoverBorder
                    : widget.active
                        ? resolvedActiveBorder
                        : resolvedBaseBorder;

        final List<BoxShadow>? shadows = showFocus
            ? [
                BoxShadow(
                  color: focusRingColor.withValues(alpha: 0.42),
                  spreadRadius: 1.5,
                  blurRadius: 0,
                ),
                if (widget.hoverShadow != null && hovered && !pressed)
                  ...widget.hoverShadow!,
              ]
            : (widget.enabled && hovered && !pressed)
                ? widget.hoverShadow
                : null;

        final BoxConstraints? constraints =
            (widget.minWidth != null || widget.minHeight != null)
                ? BoxConstraints(
                    minWidth: widget.minWidth ?? 0,
                    minHeight: widget.minHeight ?? 0,
                  )
                : null;

        final innerChild = widget.builder(context, hovered, pressed);

        return AnimatedScale(
          scale: (widget.enabled && pressed) ? widget.scaleOnPress : 1.0,
          duration: const Duration(milliseconds: 85),
          curve: Curves.easeOut,
          child: AnimatedContainer(
            duration: Duration(milliseconds: (hovered || pressed) ? 55 : 75),
            curve: Curves.easeOutCubic,
            width: widget.width,
            height: widget.height,
            constraints: constraints,
            padding: widget.padding,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: Border.all(
                color: bColor,
                width: showFocus ? 1.8 : 1,
              ),
              boxShadow: shadows,
            ),
            child: (widget.minWidth != null || widget.minHeight != null)
                ? Center(
                    widthFactor: 1.0,
                    heightFactor: 1.0,
                    child: innerChild,
                  )
                : innerChild,
          ),
        );
      },
    );

    if (canFocus) {
      content = FocusableActionDetector(
        focusNode: widget.focusNode,
        enabled: true,
        onShowFocusHighlight: (focused) {
          if (_focused != focused && mounted) {
            setState(() => _focused = focused);
          }
          widget.onFocusChange?.call(focused);
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
          ButtonActivateIntent: CallbackAction<ButtonActivateIntent>(
            onInvoke: (_) {
              widget.onTap?.call();
              return null;
            },
          ),
        },
        child: content,
      );
    }

    if (widget.onTap != null || widget.semanticLabel != null) {
      content = Semantics(
        button: widget.onTap != null,
        enabled: widget.enabled,
        selected: widget.active,
        label: widget.semanticLabel ?? widget.tooltip,
        child: content,
      );
    }

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      content = Tooltip(message: widget.tooltip!, child: content);
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
