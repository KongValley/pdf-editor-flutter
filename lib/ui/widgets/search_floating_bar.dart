import 'dart:async';

import 'package:flutter/material.dart';

import '../../state/editor_controller.dart';
import '../theme/app_theme.dart';

class SearchFloatingBar extends StatefulWidget {
  const SearchFloatingBar({super.key, required this.controller});

  final EditorController controller;

  @override
  State<SearchFloatingBar> createState() => _SearchFloatingBarState();
}

class _SearchFloatingBarState extends State<SearchFloatingBar> {
  final TextEditingController _textCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  Timer? _debounce;
  int _lastFocusSeq = 0;
  String _lastControllerQuery = '';

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncFromController);
    _textCtrl.text = widget.controller.searchQuery;
    _lastControllerQuery = widget.controller.searchQuery;
    _lastFocusSeq = widget.controller.searchFocusSeq;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusAndSelectAll();
    });
  }

  @override
  void didUpdateWidget(covariant SearchFloatingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncFromController);
      widget.controller.addListener(_syncFromController);
      _lastControllerQuery = widget.controller.searchQuery;
      _lastFocusSeq = widget.controller.searchFocusSeq;
      _syncFromController();
    }
  }

  void _focusAndSelectAll() {
    _focusNode.requestFocus();
    _selectAll();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focusNode.hasFocus) {
        _selectAll();
      }
    });
  }

  void _selectAll() {
    _textCtrl.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _textCtrl.text.length,
    );
  }

  void _syncFromController() {
    final query = widget.controller.searchQuery;
    if (query != _lastControllerQuery) {
      _lastControllerQuery = query;
      if (query.isEmpty && _textCtrl.text.isNotEmpty) {
        _debounce?.cancel();
        _textCtrl.clear();
      }
    }
    if (widget.controller.searchFocusSeq != _lastFocusSeq) {
      _lastFocusSeq = widget.controller.searchFocusSeq;
      _focusAndSelectAll();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncFromController);
    _debounce?.cancel();
    _textCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      widget.controller.updateSearchQuery(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final c = context.appColors;
    final count = ctrl.searchMatchesCount;
    final cur = ctrl.searchCurrentIndex;
    final counter = ctrl.searchQuery.trim().isEmpty
        ? ''
        : count == 0
            ? '0 / 0'
            : '${(cur < 0 ? 0 : cur) + 1} / $count';

    return Material(
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.2),
      color: c.elevatedBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: c.border),
      ),
      child: Container(
        width: 360,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 17, color: c.mutedText),
            const SizedBox(width: 6),
            Expanded(
              child: TextField(
                controller: _textCtrl,
                focusNode: _focusNode,
                style: const TextStyle(fontSize: AppTypography.body),
                decoration: const InputDecoration(
                  hintText: '搜索文档文本…',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 4),
                ),
                onChanged: _onChanged,
                onSubmitted: (_) {
                  _debounce?.cancel();
                  if (ctrl.searchQuery != _textCtrl.text) {
                    ctrl.updateSearchQuery(_textCtrl.text);
                  } else {
                    ctrl.nextSearchMatch();
                  }
                },
              ),
            ),
            if (counter.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text(
                  counter,
                  style: TextStyle(
                    fontSize: AppTypography.body,
                    color: c.mutedText,
                  ),
                ),
              ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 18),
              tooltip: '上一条 (Shift+F3)',
              visualDensity: VisualDensity.compact,
              onPressed: count > 0 ? ctrl.prevSearchMatch : null,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
              tooltip: '下一条 (F3)',
              visualDensity: VisualDensity.compact,
              onPressed: count > 0 ? ctrl.nextSearchMatch : null,
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 17),
              tooltip: '关闭 (Esc)',
              visualDensity: VisualDensity.compact,
              onPressed: ctrl.toggleSearch,
            ),
          ],
        ),
      ),
    );
  }
}
