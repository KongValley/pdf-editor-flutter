import 'package:flutter/material.dart';

import '../../state/editor_controller.dart';
import '../theme/app_theme.dart';
import 'hover_feedback.dart';

class DocumentTabBar extends StatefulWidget {
  const DocumentTabBar({
    super.key,
    required this.controller,
    required this.onOpenFile,
    required this.onSelectTab,
    required this.onCloseTab,
  });

  static const height = 36.0;

  final EditorController controller;
  final VoidCallback onOpenFile;
  final ValueChanged<String> onSelectTab;
  final ValueChanged<String> onCloseTab;

  @override
  State<DocumentTabBar> createState() => _DocumentTabBarState();
}

class _DocumentTabBarState extends State<DocumentTabBar> {
  final _activeTabKey = GlobalKey();
  String? _lastActivePath;
  double? _lastWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final ctrl = widget.controller;
    final tabs = ctrl.effectiveTabs;
    final activePath = ctrl.hasDocument ? ctrl.filePath : null;
    return Material(
      color: c.shellBg,
      child: SizedBox(
        height: DocumentTabBar.height,
        // Paint the hairline behind the tabs without reserving a layout pixel.
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: LayoutBuilder(
          builder: (context, constraints) {
            if (activePath != _lastActivePath || constraints.maxWidth != _lastWidth) {
              _lastActivePath = activePath;
              _lastWidth = constraints.maxWidth;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final activeContext = _activeTabKey.currentContext;
                if (mounted && activeContext != null) {
                  Scrollable.ensureVisible(
                    activeContext,
                    alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
                  );
                  Scrollable.ensureVisible(
                    activeContext,
                    alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtStart,
                  );
                }
              });
            }
            return Row(
              children: [
                Tooltip(
                  message: 'PDF 编辑器',
                  child: Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    decoration: BoxDecoration(
                      color: c.accentSoft,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.picture_as_pdf_rounded, size: 17, color: c.accent),
                        if (constraints.maxWidth + 16 >= 960) ...[
                          const SizedBox(width: 6),
                          Text(
                            'PDF 编辑器',
                            style: TextStyle(
                              fontSize: AppTypography.body,
                              fontWeight: FontWeight.w700,
                              color: c.accent,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (tabs.isEmpty)
                            const _DocumentTab(
                              title: '开始页',
                              icon: Icons.home_outlined,
                              active: true,
                            ),
                          for (final tab in tabs) ...[
                            _DocumentTab(
                              key: ValueKey(tab.path.toLowerCase()),
                              activeMarker: ctrl.isTabActive(tab.path) ? _activeTabKey : null,
                              title: tab.title,
                              path: tab.path,
                              icon: tab.encrypted ? Icons.lock_outline_rounded : Icons.picture_as_pdf_outlined,
                              active: ctrl.isTabActive(tab.path),
                              dirty: ctrl.isTabActive(tab.path) && ctrl.dirty,
                              onSelect: !ctrl.isBusy && !ctrl.isTabActive(tab.path)
                                  ? () => widget.onSelectTab(tab.path)
                                  : null,
                              onClose: !ctrl.isBusy ? () => widget.onCloseTab(tab.path) : null,
                            ),
                            const SizedBox(width: 3),
                          ],
                          const SizedBox(width: 4),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _TabIconButton(
                              icon: Icons.add_rounded,
                              tooltip: '打开新文档 (Ctrl+O)',
                              onTap: ctrl.isBusy ? null : widget.onOpenFile,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
            ),
          ),
        ),
      ),
    );
  }
}

class _DocumentTab extends StatelessWidget {
  const _DocumentTab({
    super.key,
    this.activeMarker,
    required this.title,
    required this.icon,
    required this.active,
    this.dirty = false,
    this.path,
    this.onSelect,
    this.onClose,
  });

  final Key? activeMarker;
  final String title;
  final IconData icon;
  final bool active;
  final bool dirty;
  final String? path;
  final VoidCallback? onSelect;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Padding(
      key: activeMarker,
      padding: const EdgeInsets.only(top: 4),
      child: HoverStateBuilder(
        enabled: !active && onSelect != null,
        builder: (context, hovered, _) => CustomPaint(
          painter: _TabShape(
            fill: active ? c.surfaceBg : hovered ? c.hoverFill : Colors.transparent,
            border: active ? c.border : null,
          ),
          child: Container(
            height: 32,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 190),
                  child: DesktopHoverContainer(
                    tooltip: path,
                    semanticLabel: title,
                    onTap: onSelect,
                    enabled: onSelect != null,
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    hoverColor: Colors.transparent,
                    hoverBorderColor: Colors.transparent,
                    pressedColor: c.accentSoft,
                    builder: (context, _, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, size: 15, color: active ? c.accent : c.mutedText),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppTypography.body,
                              fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                              color: active ? onSurface : c.mutedText,
                            ),
                          ),
                        ),
                        if (dirty) ...[
                          const SizedBox(width: 6),
                          const SizedBox.square(
                            dimension: 6,
                            child: DecoratedBox(
                              decoration: BoxDecoration(color: Color(0xFFF59E0B), shape: BoxShape.circle),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (path != null)
                  _TabIconButton(
                    icon: Icons.close_rounded,
                    tooltip: '关闭标签',
                    semanticLabel: '关闭标签：$title',
                    onTap: onClose,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabIconButton extends StatelessWidget {
  const _TabIconButton({required this.icon, required this.tooltip, required this.onTap, this.semanticLabel});

  final IconData icon;
  final String tooltip;
  final String? semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return DesktopHoverContainer(
      width: 24,
      height: 24,
      borderRadius: 6,
      tooltip: tooltip,
      semanticLabel: semanticLabel ?? tooltip,
      enabled: onTap != null,
      onTap: onTap,
      hoverColor: c.hoverFill,
      hoverBorderColor: Colors.transparent,
      pressedColor: c.accentSoft,
      builder: (context, hovered, _) => Icon(icon, size: 16, color: hovered ? c.accent : c.mutedText),
    );
  }
}

// An open-bottom stroke lets the active surface run through the strip's hairline.
class _TabShape extends CustomPainter {
  const _TabShape({required this.fill, this.border});

  final Color fill;
  final Color? border;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = Radius.circular(8);
    final rect = Offset.zero & size;
    canvas.drawRRect(RRect.fromRectAndCorners(rect, topLeft: radius, topRight: radius), Paint()..color = fill);
    if (border case final color?) {
      final path = Path()
        ..moveTo(0.5, size.height)
        ..lineTo(0.5, 8)
        ..arcToPoint(const Offset(8, 0.5), radius: const Radius.circular(7.5))
        ..lineTo(size.width - 8, 0.5)
        ..arcToPoint(Offset(size.width - 0.5, 8), radius: const Radius.circular(7.5))
        ..lineTo(size.width - 0.5, size.height);
      canvas.drawPath(path, Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1);
    }
  }

  @override
  bool shouldRepaint(_TabShape oldDelegate) => oldDelegate.fill != fill || oldDelegate.border != border;
}
