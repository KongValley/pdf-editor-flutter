import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../widgets/desktop_controls.dart';
import '../widgets/hover_feedback.dart';

class CommandPaletteAction {
  const CommandPaletteAction({
    required this.id,
    required this.group,
    required this.label,
    required this.icon,
    required this.onExecute,
    this.shortcut,
    this.enabled = true,
    this.keywords = const [],
  });

  final String id;
  final String group;
  final String label;
  final IconData icon;
  final String? shortcut;
  final bool enabled;
  final List<String> keywords;
  final FutureOr<void> Function() onExecute;
}

Future<void> showCommandPaletteDialog(
  BuildContext context, {
  required List<CommandPaletteAction> actions,
}) async {
  final action = await showDialog<CommandPaletteAction>(
    context: context,
    builder: (_) => CommandPaletteDialog(actions: actions),
  );
  if (action != null && context.mounted) await action.onExecute();
}

class CommandPaletteDialog extends StatefulWidget {
  const CommandPaletteDialog({super.key, required this.actions});

  final List<CommandPaletteAction> actions;

  @override
  State<CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<CommandPaletteDialog> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  final _highlightedKey = GlobalKey();
  late Map<String, List<CommandPaletteAction>> _groups;
  CommandPaletteAction? _highlighted;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _filter('');
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _filter(String query) {
    final terms = query.trim().toLowerCase().split(RegExp(r'\s+'));
    _groups = {};
    for (final action in widget.actions) {
      final haystack = [action.label, action.group, action.shortcut ?? '', ...action.keywords].join(' ').toLowerCase();
      if (terms.every(haystack.contains)) {
        (_groups[action.group] ??= []).add(action);
      }
    }
    _highlighted = _enabledActions.firstOrNull;
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _revealHighlight();
  }

  Iterable<CommandPaletteAction> get _enabledActions =>
      _groups.values.expand((actions) => actions).where((action) => action.enabled);

  void _revealHighlight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final item = _highlightedKey.currentContext;
      if (mounted && item != null) {
        Scrollable.ensureVisible(item, alignment: 0.5);
      }
    });
  }

  void _move(int delta) {
    final actions = _enabledActions.toList();
    if (actions.isEmpty) return;
    final index = _highlighted == null ? 0 : actions.indexOf(_highlighted!);
    final next = (index + delta + actions.length) % actions.length;
    setState(() => _highlighted = actions[next]);
    _revealHighlight();
  }

  void _close([CommandPaletteAction? action]) {
    if (_closing || !(ModalRoute.of(context)?.isCurrent ?? false)) return;
    _closing = true;
    Navigator.of(context).pop(action);
  }

  void _executeHighlight() {
    final action = _highlighted;
    if (action != null) _close(action);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final composing = _search.value.composing;
    if (composing.isValid && !composing.isCollapsed) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _move(1);
      case LogicalKeyboardKey.arrowUp:
        _move(-1);
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _executeHighlight();
      case LogicalKeyboardKey.escape:
        _close();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Dialog(
      backgroundColor: c.surfaceBg,
      surfaceTintColor: Colors.transparent,
      elevation: 18,
      shadowColor: Colors.black.withValues(alpha: 0.28),
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 440),
        child: SizedBox(
          width: 520,
          child: Focus(
            canRequestFocus: false,
            onKeyEvent: _onKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  child: Row(
                    children: [
                      Icon(Icons.search_rounded, size: 19, color: c.mutedText),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          autofocus: true,
                          controller: _search,
                          style: const TextStyle(fontSize: AppTypography.body),
                          decoration: const InputDecoration(
                            hintText: '搜索命令…',
                            filled: false,
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                          ),
                          onChanged: (query) => setState(() => _filter(query)),
                          onSubmitted: (_) => _executeHighlight(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const DesktopKeycap('Esc'),
                    ],
                  ),
                ),
                Divider(height: 1, thickness: 1, color: c.border),
                if (_groups.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('未找到匹配命令', style: TextStyle(fontSize: AppTypography.body, color: c.mutedText)),
                  )
                else
                  Flexible(
                    child: SingleChildScrollView(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final entry in _groups.entries) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                              child: Text(
                                entry.key,
                                style: TextStyle(fontSize: AppTypography.caption, color: c.mutedText, fontWeight: FontWeight.w600),
                              ),
                            ),
                            for (final action in entry.value)
                              KeyedSubtree(
                                key: ValueKey(action.id),
                                child: _CommandRow(
                                  key: action == _highlighted ? _highlightedKey : null,
                                  action: action,
                                  selected: action == _highlighted,
                                  onTap: () => _close(action),
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({super.key, required this.action, required this.selected, required this.onTap});

  final CommandPaletteAction action;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final muted = action.enabled ? c.mutedText : c.mutedText.withValues(alpha: 0.55);
    return Semantics(
      selected: selected,
      child: DesktopHoverContainer(
        height: 36,
        borderRadius: 6,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        focusable: false,
        enabled: action.enabled,
        active: selected,
        onTap: action.enabled ? onTap : null,
        activeColor: c.accentSoft,
        activeBorderColor: Colors.transparent,
        hoverColor: c.hoverFill,
        hoverBorderColor: Colors.transparent,
        pressedColor: c.accentSoft,
        builder: (context, hovered, _) => Row(
          children: [
            Icon(action.icon, size: 17, color: selected || hovered ? c.accent : muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                action.label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: AppTypography.body,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  color: action.enabled ? Theme.of(context).colorScheme.onSurface : muted,
                ),
              ),
            ),
            if (action.shortcut case final shortcut?) DesktopKeycap(shortcut),
          ],
        ),
      ),
    );
  }
}
