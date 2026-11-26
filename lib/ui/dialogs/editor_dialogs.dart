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
import '../widgets/desktop_controls.dart';
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
      return CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              Navigator.of(ctx).pop(UnsavedChangesChoice.cancel),
        },
        child: AlertDialog(
          title: DesktopDialogHeader(
            icon: Icons.warning_amber_rounded,
            iconColor: AppTheme.warning,
            iconBackground: const Color(0xFFF59E0B).withValues(alpha: 0.16),
            title: title,
            subtitle: (fileName != null && fileName.isNotEmpty) ? fileName : null,
          ),
          content: SizedBox(
            width: 408,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (summary != null && summary.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    margin: const EdgeInsets.only(bottom: 12),
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
              child: const Text('取消'),
            ),
            OutlinedButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(UnsavedChangesChoice.discard),
              style: AppTheme.dangerOutlinedButtonStyle(c),
              child: const Text('不保存'),
            ),
            FilledButton.icon(
              autofocus: true,
              onPressed: () => Navigator.of(ctx).pop(UnsavedChangesChoice.save),
              icon: const Icon(Icons.save_rounded, size: 16),
              label: Text(saveLabel),
            ),
          ],
        ),
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
          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.escape): () =>
                  Navigator.of(ctx).pop(null),
            },
            child: AlertDialog(
              title: const DesktopDialogHeader(
                icon: Icons.lock_outline_rounded,
                title: '输入 PDF 密码',
                subtitle: '此文档受密码保护，请解锁后查看',
              ),
              content: SizedBox(
                width: 368,
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
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x18DC2626),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0x55DC2626),
                          ),
                        ),
                        child: const Row(
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 16,
                              color: AppTheme.danger,
                            ),
                            SizedBox(width: 6),
                            Text(
                              '密码错误，请重新输入',
                              style: TextStyle(
                                color: AppTheme.danger,
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
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(ctx).pop(ctrl.text),
                  child: const Text('解锁打开'),
                ),
              ],
            ),
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

  final isDelete = title.contains('删除');
  final headerIcon = showPrintOptions
      ? Icons.print_outlined
      : showExportOptions
          ? Icons.ios_share_rounded
          : isDelete
              ? Icons.delete_sweep_outlined
              : Icons.content_cut_rounded;

  return await showDialog<PageRangeDialogResult>(
    context: context,
    builder: (ctx) => DialogControllersHost(
      controllers: [rangeCtrl],
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final c = ctx.appColors;
          final parsed = parsePageRange(rangeCtrl.text, totalPages);
          final valid = parsed != null && parsed.isNotEmpty;
          return AlertDialog(
            title: DesktopDialogHeader(
              icon: headerIcon,
              iconColor: isDelete ? AppTheme.danger : null,
              iconBackground:
                  isDelete ? AppTheme.danger.withValues(alpha: 0.14) : null,
              title: title,
              subtitle: '共 $totalPages 页，示例：1-3,5,8',
              onClose: () => Navigator.of(ctx).pop(null),
            ),
            content: SizedBox(
              width: 410,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DesktopFieldLabel('页码范围'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: rangeCtrl,
                    autofocus: true,
                    decoration: AppTheme.compactInputDecoration(
                      c,
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
                      fontSize: AppTypography.caption,
                      fontWeight: FontWeight.w500,
                      color: valid ? c.accent : AppTheme.danger,
                    ),
                  ),
                  if (showExportOptions) ...[
                    const SizedBox(height: 14),
                    const DesktopFieldLabel('导出格式'),
                    const SizedBox(height: 6),
                    DesktopSelect<ExportFormatChoice>(
                      isExpanded: true,
                      value: exportFormat,
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
                    const SizedBox(height: 14),
                    const DesktopFieldLabel('清晰度'),
                    const SizedBox(height: 6),
                    DesktopSelect<PrintQuality>(
                      isExpanded: true,
                      value: printQuality,
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
                    const SizedBox(height: 12),
                    DesktopCheckboxRow(
                      value: includeAnnots,
                      label: '包含注释',
                      onChanged: (v) => setState(() => includeAnnots = v),
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
                style: isDelete
                    ? FilledButton.styleFrom(backgroundColor: AppTheme.danger)
                    : null,
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
          final c = ctx.appColors;
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
            title: DesktopDialogHeader(
              icon: Icons.format_list_numbered_rounded,
              title: '添加页码',
              subtitle: '批量为文档页面写入页码编号（共 $total 页）',
              onClose: () => Navigator.of(ctx).pop(),
            ),
            content: SizedBox(
              width: 460,
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const DesktopFieldLabel('编号格式'),
                            const SizedBox(height: 5),
                            DesktopSelect<PageNumberFormat>(
                              isExpanded: true,
                              value: format,
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
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const DesktopFieldLabel('位置'),
                            const SizedBox(height: 5),
                            DesktopSelect<PageNumberPosition>(
                              isExpanded: true,
                              value: position,
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
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: c.subtleFill,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.border),
                    ),
                    child: Row(
                      children: [
                        Text(
                          '预览样例',
                          style: TextStyle(
                            fontSize: AppTypography.caption,
                            color: c.mutedText,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          format.format(sampleStart, sampleTotal),
                          style: TextStyle(
                            fontSize: AppTypography.body,
                            fontWeight: FontWeight.w600,
                            color: c.accent,
                          ),
                        ),
                      ],
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
          final c = ctx.appColors;
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
            title: DesktopDialogHeader(
              icon: Icons.branding_watermark_outlined,
              title: '添加文字水印',
              subtitle: '自定义水印文本、角度、透明度与排布方式',
              onClose: () => Navigator.of(ctx).pop(),
            ),
            content: SizedBox(
              width: 452,
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
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const DesktopFieldLabel('颜色'),
                      const SizedBox(width: 10),
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const DesktopFieldLabel('不透明度'),
                      const Spacer(),
                      Text(
                        '${(opacity * 100).round()}%',
                        style: const TextStyle(
                          fontSize: AppTypography.body,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    min: 0.05,
                    max: 0.9,
                    value: opacity,
                    onChanged: (v) => setState(() => opacity = v),
                  ),
                  Row(
                    children: [
                      const DesktopFieldLabel('旋转角度'),
                      const Spacer(),
                      Text(
                        '${rotation.round()}°',
                        style: const TextStyle(
                          fontSize: AppTypography.body,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    min: -90,
                    max: 90,
                    divisions: 36,
                    value: rotation,
                    onChanged: (v) => setState(() => rotation = v),
                  ),
                  const SizedBox(height: 4),
                  DesktopCheckboxRow(
                    value: tile,
                    label: '铺满页面（否则居中单条）',
                    onChanged: (v) => setState(() => tile = v),
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
    builder: (ctx) {
      final c = ctx.appColors;
      return AlertDialog(
        title: DesktopDialogHeader(
          icon: Icons.report_gmailerrorred_rounded,
          iconColor: AppTheme.danger,
          iconBackground: AppTheme.danger.withValues(alpha: 0.14),
          title: '问题明细 (${controller.problems.length})',
          subtitle: '运行过程中的告警与错误记录',
          onClose: () => Navigator.of(ctx).pop(),
        ),
        content: SizedBox(
          width: 520,
          height: 320,
          child: controller.problems.isEmpty
              ? Container(
                  decoration: BoxDecoration(
                    color: c.subtleFill,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.border),
                  ),
                  child: Center(
                    child: Text(
                      '暂无异常记录',
                      style: TextStyle(
                        fontSize: AppTypography.body,
                        color: c.mutedText,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: controller.problems.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (_, idx) {
                    final pItem = controller.problems[idx];
                    final timeStr =
                        '${pItem.timestamp.hour.toString().padLeft(2, '0')}:${pItem.timestamp.minute.toString().padLeft(2, '0')}:${pItem.timestamp.second.toString().padLeft(2, '0')}';
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: c.subtleFill,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.danger.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(
                                  pItem.source,
                                  style: const TextStyle(
                                    fontSize: AppTypography.caption,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.danger,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  pItem.message,
                                  style: const TextStyle(
                                    fontSize: AppTypography.body,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            pItem.detail == null
                                ? timeStr
                                : '$timeStr · ${pItem.detail}',
                            style: TextStyle(
                              fontSize: AppTypography.caption,
                              color: c.mutedText,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          if (controller.problems.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () async {
                final text = controller.problems
                    .map((p) => '[${p.timestamp}] [${p.source}] ${p.message}')
                    .join('\n');
                await Clipboard.setData(ClipboardData(text: text));
                controller.showToast('已复制全部问题明细');
              },
              icon: const Icon(Icons.copy_rounded, size: 15),
              label: const Text('复制全部'),
            ),
          if (controller.problems.isNotEmpty)
            OutlinedButton(
              style: AppTheme.dangerOutlinedButtonStyle(c),
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
      );
    },
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
        final c = ctx.appColors;
        return AlertDialog(
          title: DesktopDialogHeader(
            icon: Icons.picture_as_pdf_rounded,
            title: '关于与环境自检',
            subtitle: 'PDF 编辑器 v2.1.3（Flutter + PDFium 原生桌面版）',
            onClose: () => Navigator.of(ctx).pop(),
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '专为 Windows 10/11 64 位重构，完全离线运行，支持原生 PDFium 光栅化与 Windows OCR。',
                    style: TextStyle(
                      fontSize: AppTypography.body,
                      color: c.mutedText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.subtleFill,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      children: [
                        _EnvRow('操作系统', '${Platform.operatingSystemVersion} (x64)'),
                        Divider(height: 12, color: c.border.withValues(alpha: 0.7)),
                        const _EnvRow('渲染引擎', 'Flutter Impeller/Skia + PDFium C++'),
                        Divider(height: 12, color: c.border.withValues(alpha: 0.7)),
                        _EnvRow('默认中文字体', cjkFont ?? '未检测到（文字中文保存受限）'),
                        Divider(height: 12, color: c.border.withValues(alpha: 0.7)),
                        _EnvRow('已扫系统字族', '${controller.systemFonts.length} 个'),
                        Divider(height: 12, color: c.border.withValues(alpha: 0.7)),
                        _EnvRow('数据目录可写', writable ? '是' : '否（受限）'),
                        Divider(height: 12, color: c.border.withValues(alpha: 0.7)),
                        _EnvRow('运行日志目录', logDir.path),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text(
                        '日志等级：',
                        style: TextStyle(fontSize: AppTypography.body),
                      ),
                      const SizedBox(width: 8),
                      DesktopSelect<AppLogLevel>(
                        minHeight: 34,
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
                        label: const Text('打开日志目录'),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 112,
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppTypography.caption,
              fontWeight: FontWeight.w500,
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
    );
  }
}
