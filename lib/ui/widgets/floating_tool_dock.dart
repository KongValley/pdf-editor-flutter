import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/annotation_model.dart';
import '../../services/system_fonts_service.dart';
import '../../state/editor_controller.dart';
import '../theme/app_theme.dart';
import 'hover_feedback.dart';

class FloatingToolDock extends StatefulWidget {
  const FloatingToolDock({
    super.key,
    required this.controller,
  });

  final EditorController controller;

  @override
  State<FloatingToolDock> createState() => _FloatingToolDockState();
}

class _FloatingToolDockState extends State<FloatingToolDock> {
  static const _toolIcons = <EditorTool, IconData>{
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

  static const List<EditorTool> _coreTools = [
    EditorTool.select,
    EditorTool.highlight,
    EditorTool.rect,
    EditorTool.ink,
    EditorTool.text,
    EditorTool.note,
  ];

  static const Duration _idleCollapseDelay = Duration(seconds: 3);
  static const Duration _leaveCollapseDelay = Duration(milliseconds: 900);

  Timer? _collapseTimer;
  bool _collapsed = false;
  bool _hovered = false;
  bool _hasFocus = false;
  bool _dropdownOpen = false;
  late EditorTool _lastTool;
  late int _lastExpandSeq;
  String? _lastRenderPath;
  bool _lastHasSelection = false;

  @override
  void initState() {
    super.initState();
    final ctrl = widget.controller;
    _lastTool = ctrl.tool;
    _lastExpandSeq = ctrl.dockExpandSeq;
    _lastRenderPath = ctrl.activeRenderPath;
    _lastHasSelection = ctrl.selectedIds.isNotEmpty;
    ctrl.addListener(_onControllerChanged);
    if (ctrl.autoCollapseDock && !_lastHasSelection) {
      _scheduleCollapse(_idleCollapseDelay);
    }
  }

  @override
  void didUpdateWidget(covariant FloatingToolDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      final ctrl = widget.controller;
      _lastTool = ctrl.tool;
      _lastExpandSeq = ctrl.dockExpandSeq;
      _lastRenderPath = ctrl.activeRenderPath;
      _lastHasSelection = ctrl.selectedIds.isNotEmpty;
      ctrl.addListener(_onControllerChanged);
      if (!ctrl.autoCollapseDock) {
        _collapseTimer?.cancel();
        _collapsed = false;
      } else if (!_hovered && !_hasFocus && !_lastHasSelection) {
        _scheduleCollapse(_idleCollapseDelay);
      }
    }
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final ctrl = widget.controller;
    final hasSelection = ctrl.selectedIds.isNotEmpty;
    if (!ctrl.autoCollapseDock) {
      _collapseTimer?.cancel();
      if (_collapsed && mounted) {
        setState(() => _collapsed = false);
      }
      _lastTool = ctrl.tool;
      _lastExpandSeq = ctrl.dockExpandSeq;
      _lastRenderPath = ctrl.activeRenderPath;
      _lastHasSelection = hasSelection;
      return;
    }

    final toolChanged = ctrl.tool != _lastTool;
    final expandRequested = ctrl.dockExpandSeq != _lastExpandSeq;
    final docChanged = ctrl.activeRenderPath != _lastRenderPath;
    final selectionCleared = _lastHasSelection && !hasSelection;
    _lastTool = ctrl.tool;
    _lastExpandSeq = ctrl.dockExpandSeq;
    _lastRenderPath = ctrl.activeRenderPath;
    _lastHasSelection = hasSelection;

    if (toolChanged || expandRequested || docChanged || hasSelection) {
      _collapseTimer?.cancel();
      if (_collapsed && mounted) {
        setState(() => _collapsed = false);
      }
      if (!hasSelection && !_hovered && !_hasFocus && !_dropdownOpen) {
        _scheduleCollapse(_idleCollapseDelay);
      }
    } else if (selectionCleared && !_hovered && !_hasFocus && !_dropdownOpen) {
      _scheduleCollapse(_idleCollapseDelay);
    }
  }

  void _scheduleCollapse(Duration delay) {
    _collapseTimer?.cancel();
    if (!widget.controller.autoCollapseDock) return;
    _collapseTimer = Timer(delay, () {
      if (!mounted || !widget.controller.autoCollapseDock) return;
      final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
      if (!routeIsCurrent) {
        _scheduleCollapse(const Duration(milliseconds: 600));
        return;
      }
      _dropdownOpen = false;
      if (_hovered || _hasFocus || widget.controller.selectedIds.isNotEmpty) {
        return;
      }
      if (!_collapsed) {
        setState(() => _collapsed = true);
      }
    });
  }

  void _expandImmediately() {
    _collapseTimer?.cancel();
    if (_collapsed && mounted) {
      setState(() => _collapsed = false);
    }
  }

  void _collapseNow() {
    _collapseTimer?.cancel();
    if (mounted) {
      setState(() {
        _hovered = false;
        _hasFocus = false;
        _collapsed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    if (!controller.hasDocument) return const SizedBox.shrink();
    final c = context.appColors;
    final showStampOptions = controller.tool == EditorTool.stamp;
    final showFontOptions = controller.tool == EditorTool.text ||
        controller.tool == EditorTool.stamp;
    final hasSelection = controller.selectedIds.isNotEmpty;
    final isCollapsed = controller.autoCollapseDock &&
        _collapsed &&
        !_hovered &&
        !_hasFocus &&
        !_dropdownOpen &&
        !hasSelection;

    final showSubBar =
        !isCollapsed && (showStampOptions || showFontOptions || hasSelection);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxDockWidth =
            constraints.hasBoundedWidth ? constraints.maxWidth : double.infinity;
        return Focus(
          canRequestFocus: false,
          onFocusChange: (focused) {
            _hasFocus = focused;
            if (focused) {
              _collapseTimer?.cancel();
            } else if (controller.autoCollapseDock &&
                !_hovered &&
                !_dropdownOpen &&
                !hasSelection) {
              _scheduleCollapse(_leaveCollapseDelay);
            }
          },
          child: MouseRegion(
            onEnter: (_) {
              _hovered = true;
              _expandImmediately();
            },
            onExit: (_) {
              _hovered = false;
              if (_dropdownOpen && (ModalRoute.of(context)?.isCurrent ?? true)) {
                _dropdownOpen = false;
              }
              if (controller.autoCollapseDock &&
                  !_hasFocus &&
                  !_dropdownOpen &&
                  !hasSelection) {
                _scheduleCollapse(_leaveCollapseDelay);
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 单一持久化外胶囊：收缩 / 展开时平滑形变宽高并交叉淡入淡出
                Material(
                  elevation: 6,
                  shadowColor: Colors.black.withValues(alpha: 0.18),
                  color: c.elevatedBg.withValues(alpha: 0.96),
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                    side: BorderSide(color: c.border),
                  ),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    reverseDuration: const Duration(milliseconds: 220),
                    curve: Curves.easeInOutCubicEmphasized,
                    alignment: Alignment.center,
                    clipBehavior: Clip.hardEdge,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 210),
                      reverseDuration: const Duration(milliseconds: 170),
                      switchInCurve:
                          const Interval(0.24, 1.0, curve: Curves.easeOutCubic),
                      switchOutCurve:
                          const Interval(0.0, 0.65, curve: Curves.easeOutCubic),
                      layoutBuilder: (currentChild, previousChildren) {
                        return Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            for (final prev in previousChildren)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: OverflowBox(
                                    minWidth: 0,
                                    maxWidth: maxDockWidth,
                                    minHeight: 0,
                                    maxHeight: double.infinity,
                                    alignment: Alignment.center,
                                    child: prev,
                                  ),
                                ),
                              ),
                            ?currentChild,
                          ],
                        );
                      },
                      transitionBuilder: (child, animation) {
                        final scale = Tween<double>(begin: 0.95, end: 1.0)
                            .animate(animation);
                        return FadeTransition(
                          opacity: animation,
                          child: ScaleTransition(
                            scale: scale,
                            child: child,
                          ),
                        );
                      },
                      child: isCollapsed
                          ? _buildCollapsedPillContent(context, controller, c)
                          : _buildExpandedPillContent(
                              context,
                              controller,
                              c,
                              hasSelection: hasSelection,
                              maxDockWidth: maxDockWidth,
                            ),
                    ),
                  ),
                ),

                // 上下文子条：图章预设 / 字体 / 选中快捷动作（滑出 / 收起动效）
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  reverseDuration: const Duration(milliseconds: 160),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) => ClipRect(
                    child: SizeTransition(
                      sizeFactor: animation,
                      alignment: Alignment.topCenter,
                      child: FadeTransition(
                        opacity: animation,
                        child: child,
                      ),
                    ),
                  ),
                  child: showSubBar
                      ? _buildSubBar(
                          context,
                          controller,
                          c,
                          showStampOptions: showStampOptions,
                          showFontOptions: showFontOptions,
                          hasSelection: hasSelection,
                        )
                      : const SizedBox.shrink(
                          key: ValueKey('dock_subbar_empty'),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCollapsedPillContent(
    BuildContext context,
    EditorController controller,
    AppColors c,
  ) {
    return Padding(
      key: const ValueKey('dock_collapsed'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DesktopHoverContainer(
            tooltip: '展开悬浮工具栏',
            semanticLabel: '展开悬浮工具栏，当前工具：${controller.tool.label}',
            onTap: _expandImmediately,
            minHeight: 32,
            borderRadius: 8,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            hoverColor: c.hoverFill,
            hoverBorderColor: c.hoverBorder,
            pressedColor: c.accentSoft,
            builder: (context, hovered, _) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _toolIcons[controller.tool]!,
                  size: 16,
                  color: c.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  controller.tool.label,
                  style: TextStyle(
                    fontSize: AppTypography.body,
                    fontWeight: FontWeight.w600,
                    color: hovered
                        ? c.accent
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 8),
                Container(width: 1, height: 14, color: c.border),
                const SizedBox(width: 8),
                Text(
                  '工具栏',
                  style: TextStyle(
                    fontSize: AppTypography.body,
                    color: hovered ? c.accent : c.mutedText,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: hovered ? c.accent : c.mutedText,
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          DesktopHoverContainer(
            tooltip: '固定展开工具栏（关闭自动收纳）',
            onTap: controller.toggleAutoCollapseDock,
            width: 32,
            height: 32,
            borderRadius: 7,
            hoverColor: c.hoverFill,
            hoverBorderColor: c.hoverBorder,
            pressedColor: c.accentSoft,
            builder: (context, hovered, _) => Center(
              child: Icon(
                Icons.push_pin_outlined,
                size: 16,
                color: hovered ? c.accent : c.mutedText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedPillContent(
    BuildContext context,
    EditorController controller,
    AppColors c, {
    required bool hasSelection,
    required double maxDockWidth,
  }) {
    // 单行优先策略：绝不折成 2~3 行遮挡画布顶部
    final showAllTools = maxDockWidth >= 820;
    final showLabels = maxDockWidth >= 560;

    final List<EditorTool> visibleTools;
    final List<EditorTool> overflowTools;
    if (showAllTools) {
      visibleTools = EditorTool.values;
      overflowTools = const [];
    } else {
      visibleTools = List<EditorTool>.from(_coreTools);
      overflowTools = EditorTool.values
          .where((t) => !_coreTools.contains(t))
          .toList(growable: false);
    }
    final overflowActive = overflowTools.contains(controller.tool);

    return Padding(
      key: const ValueKey('dock_expanded'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < visibleTools.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            _DockToolButton(
              icon: _toolIcons[visibleTools[i]]!,
              label: showLabels ? visibleTools[i].label : null,
              tooltip: visibleTools[i].tooltip,
              active: controller.tool == visibleTools[i],
              onTap: () => controller.setTool(visibleTools[i]),
            ),
          ],
          if (overflowTools.isNotEmpty) ...[
            const SizedBox(width: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: PopupMenuButton<EditorTool>(
                tooltip: '更多批注工具',
                offset: const Offset(0, 38),
                onOpened: () {
                  _dropdownOpen = true;
                  _collapseTimer?.cancel();
                },
                onCanceled: () {
                  _dropdownOpen = false;
                  if (controller.autoCollapseDock &&
                      !_hovered &&
                      !_hasFocus &&
                      !hasSelection) {
                    _scheduleCollapse(_leaveCollapseDelay);
                  }
                },
                onSelected: (t) {
                  _dropdownOpen = false;
                  controller.setTool(t);
                },
                itemBuilder: (_) => [
                  for (final t in overflowTools)
                    PopupMenuItem(
                      value: t,
                      height: 40,
                      child: Row(
                        children: [
                          Icon(
                            _toolIcons[t],
                            size: 17,
                            color: controller.tool == t ? c.accent : null,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              t.label,
                              style: TextStyle(
                                fontSize: AppTypography.body,
                                fontWeight: controller.tool == t
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: controller.tool == t ? c.accent : null,
                              ),
                            ),
                          ),
                          Text(
                            t.shortcutKey,
                            style: TextStyle(
                              fontSize: AppTypography.caption,
                              color: c.mutedText,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
                child: DesktopHoverContainer(
                  focusable: false,
                  active: overflowActive,
                  minWidth: 32,
                  minHeight: 32,
                  borderRadius: 9,
                  padding: EdgeInsets.symmetric(
                    horizontal: showLabels ? 8 : 6,
                    vertical: 5,
                  ),
                  activeColor: c.accentSoft,
                  activeBorderColor: c.accent.withValues(alpha: 0.42),
                  hoverColor: c.hoverFill,
                  hoverBorderColor: c.hoverBorder,
                  pressedColor: c.accentSoft,
                  builder: (context, hovered, _) {
                    final fg = (overflowActive || hovered)
                        ? c.accent
                        : Theme.of(context).colorScheme.onSurface;
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          overflowActive
                              ? _toolIcons[controller.tool]!
                              : Icons.more_horiz_rounded,
                          size: 16,
                          color: fg,
                        ),
                        if (showLabels) ...[
                          const SizedBox(width: 4),
                          Text(
                            overflowActive ? controller.tool.label : '更多',
                            style: TextStyle(
                              fontSize: AppTypography.body,
                              color: fg,
                              fontWeight: (overflowActive || hovered)
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ),
          ],
          Container(
            width: 1,
            height: 18,
            margin: const EdgeInsets.symmetric(horizontal: 5),
            color: c.border,
          ),
          DesktopHoverContainer(
            tooltip: controller.autoCollapseDock
                ? '自动收纳已开启（点击固定展开）'
                : '已固定展开（点击开启自动收纳）',
            active: !controller.autoCollapseDock,
            onTap: controller.toggleAutoCollapseDock,
            width: 32,
            height: 32,
            borderRadius: 8,
            activeColor: c.accentSoft,
            activeBorderColor: c.accent.withValues(alpha: 0.42),
            hoverColor: c.hoverFill,
            hoverBorderColor: c.hoverBorder,
            pressedColor: c.accentSoft,
            builder: (context, hovered, _) => Center(
              child: Icon(
                controller.autoCollapseDock
                    ? Icons.push_pin_outlined
                    : Icons.push_pin_rounded,
                size: 16,
                color: (!controller.autoCollapseDock || hovered)
                    ? c.accent
                    : c.mutedText,
              ),
            ),
          ),
          const SizedBox(width: 2),
          DesktopHoverContainer(
            tooltip: (controller.autoCollapseDock && !hasSelection)
                ? '收起工具栏'
                : (hasSelection ? '取消选中批注后可收起工具栏' : '取消固定后可收起工具栏'),
            enabled: controller.autoCollapseDock && !hasSelection,
            onTap: (controller.autoCollapseDock && !hasSelection)
                ? _collapseNow
                : null,
            width: 32,
            height: 32,
            borderRadius: 8,
            hoverColor: c.hoverFill,
            hoverBorderColor: c.hoverBorder,
            pressedColor: c.accentSoft,
            builder: (context, hovered, _) => Center(
              child: Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 18,
                color: !(controller.autoCollapseDock && !hasSelection)
                    ? c.mutedText.withValues(alpha: 0.32)
                    : hovered
                        ? c.accent
                        : c.mutedText,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubBar(
    BuildContext context,
    EditorController controller,
    AppColors c, {
    required bool showStampOptions,
    required bool showFontOptions,
    required bool hasSelection,
  }) {
    return Padding(
      key: const ValueKey('dock_subbar'),
      padding: const EdgeInsets.only(top: 6),
      child: Material(
        elevation: 4,
        shadowColor: Colors.black.withValues(alpha: 0.14),
        color: c.elevatedBg.withValues(alpha: 0.96),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: c.border),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (showStampOptions) ...[
                Text(
                  '图章:',
                  style: TextStyle(
                    fontSize: AppTypography.body,
                    color: c.mutedText,
                  ),
                ),
                DesktopHoverDropdownShell(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<StampPreset>(
                      isDense: true,
                      value: controller.stampPreset,
                      style: TextStyle(
                        fontSize: AppTypography.body,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      onTap: () {
                        _dropdownOpen = true;
                        _collapseTimer?.cancel();
                      },
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
                                Text(preset.label),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        _dropdownOpen = false;
                        if (v != null) {
                          controller.stampPreset = v;
                          controller.refresh();
                        }
                        if (controller.autoCollapseDock &&
                            !_hovered &&
                            !_hasFocus &&
                            !hasSelection) {
                          _scheduleCollapse(_leaveCollapseDelay);
                        }
                      },
                    ),
                  ),
                ),
              ],
              if (showFontOptions) ...[
                Text(
                  '字体:',
                  style: TextStyle(
                    fontSize: AppTypography.body,
                    color: c.mutedText,
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 210),
                  child: DesktopHoverDropdownShell(
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        isDense: true,
                        isExpanded: true,
                        value: controller.systemFonts.any(
                          (f) => f.family == controller.defaultFontFamily,
                        )
                            ? controller.defaultFontFamily
                            : null,
                        hint: const Text(
                          '默认中文字体',
                          style: TextStyle(fontSize: AppTypography.body),
                        ),
                        style: TextStyle(
                          fontSize: AppTypography.body,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                        onTap: () {
                          _dropdownOpen = true;
                          _collapseTimer?.cancel();
                        },
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text(
                              '默认中文字体',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          for (final f in controller.systemFonts)
                            DropdownMenuItem<String?>(
                              value: f.family,
                              child: Text(
                                f.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) async {
                          _dropdownOpen = false;
                          if (v != null) {
                            final face = await SystemFontsService.findFont(v);
                            if (face != null) {
                              await SystemFontsService.ensureFlutterFontLoaded(
                                face,
                              );
                            }
                          }
                          controller.defaultFontFamily = v;
                          controller.refresh();
                          if (controller.autoCollapseDock &&
                              !_hovered &&
                              !_hasFocus &&
                              !hasSelection) {
                            _scheduleCollapse(_leaveCollapseDelay);
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
              if (hasSelection) ...[
                if (showStampOptions || showFontOptions)
                  Container(width: 1, height: 16, color: c.border),
                Text(
                  '已选 ${controller.selectedIds.length} 项',
                  style: TextStyle(
                    fontSize: AppTypography.body,
                    fontWeight: FontWeight.w600,
                    color: c.accent,
                  ),
                ),
                _MiniActionBtn(
                  icon: Icons.copy_rounded,
                  label: '复制',
                  onTap: controller.copySelectedAnnotations,
                ),
                _MiniActionBtn(
                  icon: Icons.control_point_duplicate_rounded,
                  label: '再制',
                  onTap: controller.duplicateSelectedAnnotations,
                ),
                _MiniActionBtn(
                  icon: Icons.delete_outline_rounded,
                  label: '删除',
                  danger: true,
                  onTap: controller.deleteSelectedAnnotations,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _DockToolButton extends StatelessWidget {
  const _DockToolButton({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String? label;
  final String tooltip;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return DesktopHoverContainer(
      tooltip: tooltip,
      semanticLabel: tooltip,
      active: active,
      onTap: onTap,
      minWidth: 32,
      minHeight: 32,
      borderRadius: 9,
      padding: EdgeInsets.symmetric(
        horizontal: label == null ? 6 : 7,
        vertical: 5,
      ),
      activeColor: c.accentSoft,
      activeBorderColor: c.accent.withValues(alpha: 0.42),
      hoverColor: c.hoverFill,
      hoverBorderColor: c.hoverBorder,
      pressedColor: c.accentSoft,
      builder: (context, hovered, pressed) {
        final fg = (active || hovered)
            ? c.accent
            : Theme.of(context).colorScheme.onSurface;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: fg),
            if (label != null) ...[
              const SizedBox(width: 4),
              Text(
                label!,
                style: TextStyle(
                  fontSize: AppTypography.body,
                  color: fg,
                  fontWeight:
                      (active || hovered) ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _MiniActionBtn extends StatelessWidget {
  const _MiniActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    const dangerRed = Color(0xFFDC2626);
    return DesktopHoverContainer(
      onTap: onTap,
      minHeight: 30,
      borderRadius: 6,
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      hoverColor: danger ? dangerRed.withValues(alpha: 0.1) : c.hoverFill,
      hoverBorderColor:
          danger ? dangerRed.withValues(alpha: 0.45) : c.hoverBorder,
      pressedColor: danger ? dangerRed.withValues(alpha: 0.18) : c.accentSoft,
      builder: (context, hovered, pressed) {
        final fg = danger
            ? dangerRed
            : hovered
                ? c.accent
                : Theme.of(context).colorScheme.onSurface;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: AppTypography.body,
                color: fg,
                fontWeight: hovered ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        );
      },
    );
  }
}
