import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/annotation_model.dart';
import '../../models/document_models.dart';
import '../../services/native_bridge.dart';
import '../../services/recent_and_log_service.dart';
import '../../services/system_fonts_service.dart';
import '../../state/editor_controller.dart';
import '../../utils/page_range.dart';
import '../theme/app_theme.dart';
import '../widgets/hover_feedback.dart';

enum UnsavedChangesChoice { save, discard, cancel }

Future<UnsavedChangesChoice> showUnsavedChangesDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String saveLabel,
  String? fileName,
  String? summary,
  bool barrierDismissible = false,
}) async {
  final res = await showDialog<UnsavedChangesChoice>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) {
      final c = ctx.appColors;
      const dangerRed = Color(0xFFDC2626);
      return AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
        contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 12),
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                size: 21,
                color: Color(0xFFD97706),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontSize: AppTypography.title)),
                  if (fileName != null && fileName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      fileName,
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
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (summary != null && summary.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: c.subtleFill,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.border),
                  ),
                  child: Text(
                    '未保存内容：$summary',
                    style: TextStyle(
                      fontSize: AppTypography.caption,
                      color: c.mutedText,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
              Text(
                message,
                style: TextStyle(
                  fontSize: AppTypography.body,
                  height: 1.55,
                  color: Theme.of(ctx)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.88),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(ctx).pop(UnsavedChangesChoice.cancel),
            child: Text('取消', style: TextStyle(color: c.mutedText)),
          ),
          OutlinedButton(
            onPressed: () =>
                Navigator.of(ctx).pop(UnsavedChangesChoice.discard),
            style: ButtonStyle(
              foregroundColor: const WidgetStatePropertyAll(dangerRed),
              side: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.hovered)) {
                  return BorderSide(color: dangerRed.withValues(alpha: 0.7));
                }
                return BorderSide(color: dangerRed.withValues(alpha: 0.35));
              }),
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return dangerRed.withValues(alpha: 0.14);
                }
                if (states.contains(WidgetState.hovered)) {
                  return dangerRed.withValues(alpha: 0.08);
                }
                return null;
              }),
            ),
            child: const Text('不保存'),
          ),
          FilledButton.icon(
            autofocus: true,
            onPressed: () => Navigator.of(ctx).pop(UnsavedChangesChoice.save),
            icon: const Icon(Icons.save_rounded, size: 16),
            label: Text(saveLabel),
          ),
        ],
      );
    },
  );
  return res ?? UnsavedChangesChoice.cancel;
}

class DialogControllersHost extends StatefulWidget {
  const DialogControllersHost({
    super.key,
    required this.controllers,
    required this.builder,
  });

  final List<TextEditingController> controllers;
  final WidgetBuilder builder;

  @override
  State<DialogControllersHost> createState() => _DialogControllersHostState();
}

class _DialogControllersHostState extends State<DialogControllersHost> {
  @override
  void dispose() {
    for (final c in widget.controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context);
}

Future<String?> showPasswordPromptDialog(
  BuildContext context, {
  bool wrongPassword = false,
}) async {
  final ctrl = TextEditingController();
  var obscure = true;
  return await showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => DialogControllersHost(
      controllers: [ctrl],
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final c = ctx.appColors;
          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
            contentPadding: const EdgeInsets.fromLTRB(22, 14, 22, 12),
            title: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: c.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.lock_outline_rounded,
                    size: 20,
                    color: c.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('输入 PDF 密码',
                          style: TextStyle(fontSize: AppTypography.title)),
                      const SizedBox(height: 2),
                      Text(
                        '此文档受密码保护，请解锁后查看',
                        style: TextStyle(
                          fontSize: AppTypography.body,
                          fontWeight: FontWeight.w400,
                          color: c.mutedText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (wrongPassword)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0x18DC2626),
                        borderRadius: BorderRadius.circular(7),
                        border: Border.all(
                          color: const Color(0x55DC2626),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 15,
                            color: Color(0xFFDC2626),
                          ),
                          SizedBox(width: 6),
                          Text(
                            '密码错误，请重新输入',
                            style: TextStyle(
                              color: Color(0xFFDC2626),
                              fontSize: AppTypography.body,
                            ),
                          ),
                        ],
                      ),
                    ),
                  TextField(
                    controller: ctrl,
                    obscureText: obscure,
                    autofocus: true,
                    decoration: AppTheme.compactInputDecoration(
                      c,
                      hintText: '请输入文档打开密码',
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 18,
                        ),
                        tooltip: obscure ? '显示密码' : '隐藏密码',
                        onPressed: () => setState(() => obscure = !obscure),
                      ),
                    ),
                    onSubmitted: (v) => Navigator.of(ctx).pop(v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: Text('取消', style: TextStyle(color: c.mutedText)),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(ctrl.text),
                child: const Text('解锁打开'),
              ),
            ],
          );
        },
      ),
    ),
  );
}

enum ExportFormatChoice { pdf, pngEach, pngLongV, pngLongH }

class PageRangeDialogResult {
  const PageRangeDialogResult({
    required this.pagesZeroBased,
    this.includeAnnotations = true,
    this.exportFormat = ExportFormatChoice.pdf,
    this.printQuality = PrintQuality.standard,
  });

  final List<int> pagesZeroBased;
  final bool includeAnnotations;
  final ExportFormatChoice exportFormat;
  final PrintQuality printQuality;
}

Future<PageRangeDialogResult?> showPageRangeDialog(
  BuildContext context, {
  required String title,
  required int totalPages,
  String initialRange = '',
  bool showIncludeAnnotations = false,
  bool showExportOptions = false,
  bool showPrintOptions = false,
  String confirmLabel = '确定',
}) async {
  final rangeCtrl = TextEditingController(
    text: initialRange.isEmpty ? '1-$totalPages' : initialRange,
  );
  var includeAnnots = true;
  var exportFormat = ExportFormatChoice.pdf;
  var printQuality = PrintQuality.standard;

  return await showDialog<PageRangeDialogResult>(
    context: context,
    builder: (ctx) => DialogControllersHost(
      controllers: [rangeCtrl],
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final parsed = parsePageRange(rangeCtrl.text, totalPages);
          final valid = parsed != null && parsed.isNotEmpty;
          return AlertDialog(
            title: Text(title,
                style: const TextStyle(fontSize: AppTypography.title)),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '页码范围（共 $totalPages 页，示例：1-3,5,8）',
                    style: TextStyle(
                      fontSize: AppTypography.body,
                      color: ctx.appColors.mutedText,
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextField(
                    controller: rangeCtrl,
                    autofocus: true,
                    decoration: AppTheme.compactInputDecoration(
                      ctx.appColors,
                      hintText: '1-$totalPages',
                      errorText: valid ? null : '请输入有效的 1-$totalPages 范围',
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) {
                      if (valid) {
                        Navigator.of(ctx).pop(PageRangeDialogResult(
                          pagesZeroBased: parsed,
                          includeAnnotations: includeAnnots,
                          exportFormat: exportFormat,
                          printQuality: printQuality,
                        ));
                      }
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    valid ? '将处理 ${parsed.length} 页' : '范围无效',
                    style: TextStyle(
                      fontSize: AppTypography.body,
                      color: valid
                          ? ctx.appColors.accent
                          : const Color(0xFFE03131),
                    ),
                  ),
                  if (showExportOptions) ...[
                    const SizedBox(height: 12),
                    const Text('导出格式',
                        style: TextStyle(fontSize: AppTypography.body)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<ExportFormatChoice>(
                      initialValue: exportFormat,
                      decoration: AppTheme.compactInputDecoration(ctx.appColors),
                      items: const [
                        DropdownMenuItem(
                          value: ExportFormatChoice.pdf,
                          child: Text('PDF 文档'),
                        ),
                        DropdownMenuItem(
                          value: ExportFormatChoice.pngEach,
                          child: Text('PNG 图片（逐页多图）'),
                        ),
                        DropdownMenuItem(
                          value: ExportFormatChoice.pngLongV,
                          child: Text('PNG 拼接长图（纵向）'),
                        ),
                        DropdownMenuItem(
                          value: ExportFormatChoice.pngLongH,
                          child: Text('PNG 拼接长图（横向）'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => exportFormat = v);
                      },
                    ),
                  ],
                  if (showPrintOptions) ...[
                    const SizedBox(height: 12),
                    const Text('清晰度',
                        style: TextStyle(fontSize: AppTypography.body)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<PrintQuality>(
                      initialValue: printQuality,
                      decoration: AppTheme.compactInputDecoration(ctx.appColors),
                      items: [
                        for (final q in PrintQuality.values)
                          DropdownMenuItem(value: q, child: Text(q.label)),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => printQuality = v);
                      },
                    ),
                  ],
                  if (showIncludeAnnotations) ...[
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      value: includeAnnots,
                      onChanged: (v) =>
                          setState(() => includeAnnots = v ?? true),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('包含注释',
                          style: TextStyle(fontSize: AppTypography.body)),
                      dense: true,
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(null),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: valid
                    ? () => Navigator.of(ctx).pop(PageRangeDialogResult(
                          pagesZeroBased: parsed,
                          includeAnnotations: includeAnnots,
                          exportFormat: exportFormat,
                          printQuality: printQuality,
                        ))
                    : null,
                child: Text(confirmLabel),
              ),
            ],
          );
        },
      ),
    ),
  );
}

Future<void> showPageNumberDialog(
  BuildContext context,
  EditorController controller,
) async {
  final rangeCtrl = TextEditingController();
  final startCtrl = TextEditingController(text: '1');
  final sizeCtrl = TextEditingController(text: '11');
  final marginCtrl = TextEditingController(text: '24');
  var format = PageNumberFormat.zhPageTotal;
  var position = PageNumberPosition.bottomCenter;

  await showDialog<void>(
    context: context,
    builder: (ctx) => DialogControllersHost(
      controllers: [rangeCtrl, startCtrl, sizeCtrl, marginCtrl],
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final total = controller.pageCount;
          final pages = rangeCtrl.text.trim().isEmpty
              ? List<int>.generate(total, (i) => i)
              : parsePageRange(rangeCtrl.text, total);
          final parsedStart = int.tryParse(startCtrl.text.trim());
          final parsedSize = double.tryParse(sizeCtrl.text.trim());
          final parsedMargin = double.tryParse(marginCtrl.text.trim());
          final startOk = parsedStart != null && parsedStart >= 0;
          final sizeOk =
              parsedSize != null && parsedSize >= 6 && parsedSize <= 72;
          final marginOk =
              parsedMargin != null && parsedMargin >= 0 && parsedMargin <= 200;
          final valid = pages != null && startOk && sizeOk && marginOk;
          final sampleStart = startOk ? parsedStart : 1;
          final sampleTotal =
              pages == null ? total : sampleStart + pages.length - 1;

          return AlertDialog(
            title: const Text('添加页码',
                style: TextStyle(fontSize: AppTypography.title)),
            content: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: rangeCtrl,
                    decoration: InputDecoration(
                      labelText: '页码范围（留空表示全部 $total 页）',
                      hintText: '例如 1-$total',
                      errorText: pages == null ? '页码范围无效' : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<PageNumberFormat>(
                          isExpanded: true,
                          initialValue: format,
                          decoration: const InputDecoration(labelText: '编号格式'),
                          items: [
                            for (final f in PageNumberFormat.values)
                              DropdownMenuItem(
                                value: f,
                                child: Text(
                                  f.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => format = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<PageNumberPosition>(
                          isExpanded: true,
                          initialValue: position,
                          decoration: const InputDecoration(labelText: '位置'),
                          items: [
                            for (final pos in PageNumberPosition.values)
                              DropdownMenuItem(
                                value: pos,
                                child: Text(
                                  pos.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => position = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: startCtrl,
                          decoration: InputDecoration(
                            labelText: '起始页码',
                            errorText: startOk ? null : '需 >= 0 整数',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: sizeCtrl,
                          decoration: InputDecoration(
                            labelText: '字号 (pt)',
                            errorText: sizeOk ? null : '6 ~ 72',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: marginCtrl,
                          decoration: InputDecoration(
                            labelText: '边距 (pt)',
                            errorText: marginOk ? null : '0 ~ 200',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: ctx.appColors.subtleFill,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '预览样例：${format.format(sampleStart, sampleTotal)}',
                      style: const TextStyle(fontSize: AppTypography.body),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: valid
                    ? () async {
                        Navigator.of(ctx).pop();
                        await controller.applyPageNumbers(
                          pagesZeroBased: pages,
                          format: format,
                          startNumber: parsedStart,
                          position: position,
                          fontSize: parsedSize,
                          marginPt: parsedMargin,
                        );
                      }
                    : null,
                child: const Text('确定添加'),
              ),
            ],
          );
        },
      ),
    ),
  );
}

Future<void> showWatermarkDialog(
  BuildContext context,
  EditorController controller,
) async {
  final rangeCtrl = TextEditingController();
  final textCtrl = TextEditingController(text: '机密');
  final sizeCtrl = TextEditingController(text: '44');
  var opacity = 0.15;
  var rotation = 45.0;
  var tile = true;
  var colorHex = '#e03131';

  await showDialog<void>(
    context: context,
    builder: (ctx) => DialogControllersHost(
      controllers: [rangeCtrl, textCtrl, sizeCtrl],
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final total = controller.pageCount;
          final pages = rangeCtrl.text.trim().isEmpty
              ? List<int>.generate(total, (i) => i)
              : parsePageRange(rangeCtrl.text, total);
          final textOk = textCtrl.text.trim().isNotEmpty;
          final parsedSize = double.tryParse(sizeCtrl.text.trim());
          final sizeOk =
              parsedSize != null && parsedSize >= 8 && parsedSize <= 180;
          final valid = pages != null && textOk && sizeOk;

          return AlertDialog(
            title: const Text('添加文字水印',
                style: TextStyle(fontSize: AppTypography.title)),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: rangeCtrl,
                    decoration: InputDecoration(
                      labelText: '页码范围（留空表示全部 $total 页）',
                      errorText: pages == null ? '页码范围无效' : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: textCtrl,
                          decoration: InputDecoration(
                            labelText: '水印文字',
                            errorText: textOk ? null : '请输入水印文字',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: sizeCtrl,
                          decoration: InputDecoration(
                            labelText: '字号 (pt)',
                            errorText: sizeOk ? null : '8 ~ 180',
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('颜色：',
                          style: TextStyle(fontSize: AppTypography.body)),
                      const SizedBox(width: 6),
                      for (final hex in kAnnotationPalette)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: HoverStateBuilder(
                            enabled: true,
                            onTap: () => setState(() => colorHex = hex),
                            builder: (context, hovered, pressed) {
                              final selected = colorHex == hex;
                              return AnimatedScale(
                                scale: pressed
                                    ? 0.92
                                    : hovered
                                        ? 1.15
                                        : 1.0,
                                duration: const Duration(milliseconds: 100),
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color: hexToColor(hex),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: selected
                                          ? ctx.appColors.accent
                                          : hovered
                                              ? ctx.appColors.accent
                                                  .withValues(alpha: 0.75)
                                              : Colors.black26,
                                      width: (selected || hovered) ? 2.5 : 1,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text('不透明度 ${(opacity * 100).round()}%',
                          style: const TextStyle(fontSize: AppTypography.body)),
                      Expanded(
                        child: Slider(
                          min: 0.05,
                          max: 0.9,
                          value: opacity,
                          onChanged: (v) => setState(() => opacity = v),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Text('旋转 ${rotation.round()}°',
                          style: const TextStyle(fontSize: AppTypography.body)),
                      Expanded(
                        child: Slider(
                          min: -90,
                          max: 90,
                          divisions: 36,
                          value: rotation,
                          onChanged: (v) => setState(() => rotation = v),
                        ),
                      ),
                    ],
                  ),
                  CheckboxListTile(
                    value: tile,
                    onChanged: (v) => setState(() => tile = v ?? true),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('铺满页面（否则居中单条）',
                        style: TextStyle(fontSize: AppTypography.body)),
                    dense: true,
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: valid
                    ? () async {
                        Navigator.of(ctx).pop();
                        await controller.applyWatermark(
                          pagesZeroBased: pages,
                          text: textCtrl.text.trim(),
                          fontSize: parsedSize,
                          opacity: opacity,
                          rotationDeg: rotation,
                          tile: tile,
                          colorHex: colorHex,
                        );
                      }
                    : null,
                child: const Text('确定添加'),
              ),
            ],
          );
        },
      ),
    ),
  );
}

Future<void> showProblemsDialog(
  BuildContext context,
  EditorController controller,
) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('问题明细 (${controller.problems.length})',
          style: const TextStyle(fontSize: AppTypography.title)),
      content: SizedBox(
        width: 520,
        height: 320,
        child: controller.problems.isEmpty
            ? const Center(child: Text('暂无异常记录'))
            : ListView.separated(
                itemCount: controller.problems.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, idx) {
                  final pItem = controller.problems[idx];
                  final timeStr =
                      '${pItem.timestamp.hour.toString().padLeft(2, '0')}:${pItem.timestamp.minute.toString().padLeft(2, '0')}:${pItem.timestamp.second.toString().padLeft(2, '0')}';
                  return ListTile(
                    dense: true,
                    title: Text('[${pItem.source}] ${pItem.message}',
                        style: const TextStyle(fontSize: AppTypography.body)),
                    subtitle: Text(
                      pItem.detail == null ? timeStr : '$timeStr · ${pItem.detail}',
                      style: const TextStyle(fontSize: AppTypography.body),
                    ),
                  );
                },
              ),
      ),
      actions: [
        if (controller.problems.isNotEmpty)
          TextButton(
            onPressed: () async {
              final text = controller.problems
                  .map((p) => '[${p.timestamp}] [${p.source}] ${p.message}')
                  .join('\n');
              await Clipboard.setData(ClipboardData(text: text));
              controller.showToast('已复制全部问题明细');
            },
            child: const Text('复制全部'),
          ),
        if (controller.problems.isNotEmpty)
          TextButton(
            onPressed: () {
              controller.clearProblems();
              Navigator.of(ctx).pop();
            },
            child: const Text('清空'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

Future<void> showAboutSelfCheckDialog(
  BuildContext context,
  EditorController controller,
) async {
  final writable = await AppDataService.isDataDirWritable();
  final logDir = await AppDataService.ensureLogDir();
  final cjkFont = SystemFontsService.findDefaultCjkFontPath();
  if (!context.mounted) return;

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        return AlertDialog(
          title: const Text('关于与环境自检',
              style: TextStyle(fontSize: AppTypography.title)),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PDF 编辑器 v2.1.0（Flutter + PDFium 原生桌面版）',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: AppTypography.body,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '专为 Windows 10/11 64 位重构，完全离线运行，支持原生 PDFium 光栅化与 Windows OCR。',
                    style: TextStyle(
                      fontSize: AppTypography.body,
                      color: ctx.appColors.mutedText,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _EnvRow('操作系统', '${Platform.operatingSystemVersion} (x64)'),
                  _EnvRow('渲染引擎', 'Flutter Impeller/Skia + PDFium C++'),
                  _EnvRow('默认中文字体', cjkFont ?? '未检测到（文字中文保存受限）'),
                  _EnvRow('已扫系统字族', '${controller.systemFonts.length} 个'),
                  _EnvRow('数据目录可写', writable ? '是' : '否（受限）'),
                  _EnvRow('运行日志目录', logDir.path),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Text('日志等级：',
                          style: TextStyle(fontSize: AppTypography.body)),
                      const SizedBox(width: 8),
                      DropdownButton<AppLogLevel>(
                        value: AppDataService.logLevel,
                        items: [
                          for (final lvl in AppLogLevel.values)
                            DropdownMenuItem(value: lvl, child: Text(lvl.label)),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => AppDataService.logLevel = v);
                          }
                        },
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: () => NativeBridge.openFolder(logDir.path),
                        icon: const Icon(Icons.folder_open_rounded, size: 16),
                        label: const Text('打开日志目录',
                            style: TextStyle(fontSize: AppTypography.body)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    ),
  );
}

class _EnvRow extends StatelessWidget {
  const _EnvRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontSize: AppTypography.body,
                color: context.appColors.mutedText,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontSize: AppTypography.body),
            ),
          ),
        ],
      ),
    );
  }
}
