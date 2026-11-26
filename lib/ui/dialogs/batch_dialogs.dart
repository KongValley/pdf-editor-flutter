import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../models/document_models.dart';
import '../../services/image_to_pdf_service.dart';
import '../../services/native_bridge.dart';
import '../../services/pdf_engine_service.dart';
import '../../state/editor_controller.dart';
import '../../utils/page_range.dart';
import '../theme/app_theme.dart';
import 'editor_dialogs.dart'
    show
        UnsavedChangesChoice,
        showPasswordPromptDialog,
        showUnsavedChangesDialog;

class _MergeEntry {
  _MergeEntry({
    required this.path,
    required this.pageCount,
    this.isCurrent = false,
    this.password,
  }) : rangeCtrl = TextEditingController(text: '1-$pageCount');

  final String path;
  final int pageCount;
  final bool isCurrent;
  final String? password;
  bool included = true;
  final TextEditingController rangeCtrl;

  void dispose() => rangeCtrl.dispose();
}

Future<void> showMergeDialog(
  BuildContext context,
  EditorController controller, {
  List<String> initialPaths = const [],
}) async {
  final hasCurrent = controller.hasDocument && controller.filePath != null;
  if (hasCurrent) {
    controller.flushPendingInlineEdits();
    if (controller.dirty) {
      final choice = await showUnsavedChangesDialog(
        context,
        title: '合并前确认',
        fileName: controller.displayFileName,
        message:
            '当前文档有未保存的修改。合并完成后将打开生成的新 PDF，原文档未保存的修改将不会写入原文件。是否先保存当前文档？',
        saveLabel: '保存并继续',
      );
      if (choice == UnsavedChangesChoice.cancel) return;
      if (choice == UnsavedChangesChoice.save) {
        final saved = await controller.saveDocument();
        if (!saved) return;
      }
    }
  }
  if (!context.mounted) return;

  final entries = <_MergeEntry>[
    if (hasCurrent)
      _MergeEntry(
        path: controller.filePath!,
        pageCount: controller.pageCount,
        isCurrent: true,
        password: controller.password,
      ),
  ];
  final outNameCtrl = TextEditingController(
    text: hasCurrent ? '${controller.fileStem}-合并.pdf' : '合并文档.pdf',
  );
  var outputDir = hasCurrent ? p.dirname(controller.filePath!) : '';
  var userPickedDir = false;
  var userEditedOutName = false;
  var openFolderAfter = true;

  Future<void> addPdfPath(String path) async {
    String? pw;
    var wrongPw = false;
    while (true) {
      final info = await PdfEngineService.inspectDocument(path, password: pw);
      if (info.passwordRequired) {
        if (!context.mounted) return;
        pw = await showPasswordPromptDialog(context, wrongPassword: wrongPw);
        if (pw == null) return;
        wrongPw = true;
        continue;
      }
      if (!info.ok) {
        controller.showToast(
          '无法读取 ${p.basename(path)}：${info.error ?? ""}',
          isError: true,
        );
        return;
      }
      entries.add(_MergeEntry(
        path: path,
        pageCount: info.pageCount,
        password: pw,
      ));
      if (!userPickedDir && outputDir.isEmpty) {
        outputDir = p.dirname(path);
      }
      if (!userEditedOutName && !hasCurrent && entries.length == 1) {
        outNameCtrl.text = '${p.basenameWithoutExtension(path)}-合并.pdf';
      }
      return;
    }
  }

  try {
    for (final path in initialPaths) {
      await addPdfPath(path);
      if (!context.mounted) return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final includedCount = entries.where((e) => e.included).length;
        var allRangesValid = true;
        final specs = <({
          String path,
          List<int>? pages,
          String? password,
          bool isCurrent,
        })>[];

        for (final e in entries) {
          if (!e.included) continue;
          if (e.isCurrent) {
            specs.add((
              path: e.path,
              pages: null,
              password: e.password ?? controller.password,
              isCurrent: true,
            ));
          } else {
            final parsed = parsePageRange(e.rangeCtrl.text, e.pageCount);
            if (parsed == null) {
              allRangesValid = false;
            } else {
              specs.add((
                path: e.path,
                pages: parsed,
                password: e.password,
                isCurrent: false,
              ));
            }
          }
        }
        final canStart = includedCount >= 2 &&
            allRangesValid &&
            outNameCtrl.text.trim().isNotEmpty &&
            outputDir.isNotEmpty;

        return AlertDialog(
          title: const Text('合并 PDF',
              style: TextStyle(fontSize: AppTypography.title)),
          content: SizedBox(
            width: 620,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () async {
                        final picked = await FilePicker.pickFiles(
                          type: FileType.custom,
                          allowedExtensions: ['pdf'],
                        );
                        if (picked.isEmpty) return;
                        for (final f in picked) {
                          if (f.path == null) continue;
                          await addPdfPath(f.path!);
                        }
                        if (!ctx.mounted) return;
                        setState(() {});
                      },
                      icon: const Icon(Icons.add_rounded, size: 17),
                      label: const Text('添加 PDF 文件'),
                    ),
                    const Spacer(),
                    Text(
                      includedCount < 2
                          ? '已选 $includedCount 份（至少需 2 份）'
                          : '已选 $includedCount 份参与合并',
                      style: TextStyle(
                        fontSize: AppTypography.body,
                        color: ctx.appColors.mutedText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: entries.isEmpty
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: ctx.appColors.subtleFill,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: ctx.appColors.border),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.merge_type_rounded,
                                size: 28,
                                color: ctx.appColors.mutedText,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '请点击上方「添加 PDF 文件」，选择至少 2 份需要合并的 PDF',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: AppTypography.body,
                                  color: ctx.appColors.mutedText,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                    shrinkWrap: true,
                    itemCount: entries.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (_, idx) {
                      final e = entries[idx];
                      final valid = e.isCurrent ||
                          parsePageRange(e.rangeCtrl.text, e.pageCount) != null;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: ctx.appColors.subtleFill,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: ctx.appColors.border),
                        ),
                        child: Row(
                          children: [
                            Checkbox(
                              value: e.included,
                              onChanged: e.isCurrent
                                  ? null
                                  : (v) => setState(
                                      () => e.included = v ?? true),
                            ),
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${p.basename(e.path)}${e.isCurrent ? "（当前文档）" : ""}',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: AppTypography.body,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    '${e.pageCount} 页',
                                    style: TextStyle(
                                      fontSize: AppTypography.body,
                                      color: ctx.appColors.mutedText,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 120,
                              child: e.isCurrent
                                  ? Text(
                                      '全部 ${e.pageCount} 页',
                                      style: TextStyle(
                                        fontSize: AppTypography.body,
                                        color: ctx.appColors.mutedText,
                                      ),
                                    )
                                  : TextField(
                                      controller: e.rangeCtrl,
                                      decoration: InputDecoration(
                                        isDense: true,
                                        errorText: valid ? null : '范围无效',
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_upward_rounded,
                                  size: 16),
                              onPressed: idx > 0
                                  ? () => setState(() {
                                        final item = entries.removeAt(idx);
                                        entries.insert(idx - 1, item);
                                      })
                                  : null,
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_downward_rounded,
                                  size: 16),
                              onPressed: idx < entries.length - 1
                                  ? () => setState(() {
                                        final item = entries.removeAt(idx);
                                        entries.insert(idx + 1, item);
                                      })
                                  : null,
                            ),
                            if (!e.isCurrent)
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 16),
                                onPressed: () => setState(() {
                                  entries.removeAt(idx).dispose();
                                }),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: outNameCtrl,
                        decoration: const InputDecoration(labelText: '输出文件名'),
                        onChanged: (_) => setState(() {
                          userEditedOutName = true;
                        }),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              outputDir.isEmpty
                                  ? '输出目录：添加文件后自动指定'
                                  : '输出目录：$outputDir',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppTypography.body,
                                color: ctx.appColors.mutedText,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final dir = (await FilePicker.pickDirectory())
                                  ?.toFilePath(windows: Platform.isWindows);
                              if (dir != null && ctx.mounted) {
                                setState(() {
                                  userPickedDir = true;
                                  outputDir = dir;
                                });
                              }
                            },
                            child: const Text('更改'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                CheckboxListTile(
                  value: openFolderAfter,
                  onChanged: (v) =>
                      setState(() => openFolderAfter = v ?? true),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('合并完成后打开输出所在文件夹',
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
              onPressed: canStart
                  ? () async {
                      var name = outNameCtrl.text.trim();
                      if (!name.toLowerCase().endsWith('.pdf')) {
                        name = '$name.pdf';
                      }
                      final target =
                          PdfEngineService.uniquePath(outputDir, name);
                      Navigator.of(ctx).pop();
                      await controller.mergeDocuments(
                        entries: specs,
                        targetPath: target,
                        openFolderAfter: openFolderAfter,
                      );
                    }
                  : null,
              child: const Text('开始合并'),
            ),
          ],
        );
      },
    ),
  );
  } finally {
    for (final e in entries) {
      e.dispose();
    }
    outNameCtrl.dispose();
  }
}

class _SplitEntry {
  _SplitEntry({
    required this.path,
    required this.pageCount,
    this.isCurrent = false,
  })  : rangeCtrl = TextEditingController(text: '1-$pageCount'),
        maxPagesCtrl = TextEditingController(text: '5');

  final String path;
  final int pageCount;
  final bool isCurrent;
  bool included = true;
  bool byMaxPages = true;
  final TextEditingController rangeCtrl;
  final TextEditingController maxPagesCtrl;

  void dispose() {
    rangeCtrl.dispose();
    maxPagesCtrl.dispose();
  }
}

Future<void> showSplitDialog(
  BuildContext context,
  EditorController controller,
) async {
  if (!controller.hasDocument || controller.filePath == null) return;
  final entries = <_SplitEntry>[
    _SplitEntry(
      path: controller.filePath!,
      pageCount: controller.pageCount,
      isCurrent: true,
    ),
  ];
  var outputDir = p.dirname(controller.filePath!);
  var includeAnnotations = true;
  var openFolderAfter = true;

  var running = false;
  var cancelled = false;
  var processedFiles = 0;
  var totalFiles = 0;
  var outputCount = 0;

  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        final tasks = <SplitTaskInput>[];
        var valid = false;
        for (final e in entries) {
          if (!e.included) continue;
          final parsed = parsePageRange(e.rangeCtrl.text, e.pageCount);
          if (parsed == null) {
            valid = false;
            tasks.clear();
            break;
          }
          List<List<int>> chunks;
          if (e.byMaxPages) {
            final per = int.tryParse(e.maxPagesCtrl.text.trim()) ?? 0;
            if (per <= 0) {
              valid = false;
              tasks.clear();
              break;
            }
            chunks = [
              for (var i = 0; i < parsed.length; i += per)
                parsed.sublist(
                    i, (i + per) > parsed.length ? parsed.length : i + per),
            ];
          } else {
            chunks = splitPageSegments(parsed);
          }
          tasks.add(SplitTaskInput(
            path: e.isCurrent ? controller.activeRenderPath! : e.path,
            chunks: chunks,
            password: e.isCurrent ? controller.password : null,
            annotations: e.isCurrent ? controller.annotations : null,
            isCurrentDoc: e.isCurrent,
            outputStem: e.isCurrent ? controller.fileStem : null,
          ));
          valid = true;
        }

        return AlertDialog(
          title: const Text('批量拆分 PDF',
              style: TextStyle(fontSize: AppTypography.title)),
          content: SizedBox(
            width: 640,
            child: running
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 10),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                      Text(
                        '正在拆分文件 $processedFiles / $totalFiles，已输出 $outputCount 个文件…',
                        style: const TextStyle(fontSize: AppTypography.body),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              final picked = await FilePicker.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['pdf'],
                              );
                              if (picked.isEmpty) return;
                              for (final f in picked) {
                                if (f.path == null) continue;
                                final info =
                                    await PdfEngineService.inspectDocument(
                                        f.path!);
                                if (!info.ok) {
                                  controller.showToast(
                                    '无法读取 ${p.basename(f.path!)}：${info.error ?? ""}',
                                    isError: true,
                                  );
                                  continue;
                                }
                                entries.add(_SplitEntry(
                                  path: f.path!,
                                  pageCount: info.pageCount,
                                ));
                              }
                              if (!ctx.mounted) return;
                              setState(() {});
                            },
                            icon: const Icon(Icons.add_rounded, size: 17),
                            label: const Text('添加 PDF 文件'),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: entries.any((e) => e.included)
                                ? () => setState(() {
                                      for (final e
                                          in entries.where((e) => e.included)) {
                                        e.dispose();
                                      }
                                      entries.removeWhere((e) => e.included);
                                    })
                                : null,
                            child: const Text('移除已选'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 240),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: entries.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 6),
                          itemBuilder: (_, idx) {
                            final e = entries[idx];
                            final rValid =
                                parsePageRange(e.rangeCtrl.text, e.pageCount) !=
                                    null;
                            return Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: ctx.appColors.subtleFill,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: ctx.appColors.border),
                              ),
                              child: Row(
                                children: [
                                  Checkbox(
                                    value: e.included,
                                    onChanged: (v) => setState(
                                        () => e.included = v ?? true),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      '${p.basename(e.path)} (${e.pageCount}页)',
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: AppTypography.body),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  DropdownButton<bool>(
                                    value: e.byMaxPages,
                                    items: const [
                                      DropdownMenuItem(
                                          value: true,
                                          child: Text('按页数',
                                              style: TextStyle(
                                                  fontSize:
                                                      AppTypography.body))),
                                      DropdownMenuItem(
                                          value: false,
                                          child: Text('按连续段',
                                              style: TextStyle(
                                                  fontSize:
                                                      AppTypography.body))),
                                    ],
                                    onChanged: (v) => setState(
                                        () => e.byMaxPages = v ?? true),
                                  ),
                                  const SizedBox(width: 6),
                                  SizedBox(
                                    width: 106,
                                    child: TextField(
                                      controller: e.rangeCtrl,
                                      decoration: InputDecoration(
                                        labelText: '范围',
                                        errorText: rValid ? null : '无效',
                                      ),
                                      onChanged: (_) => setState(() {}),
                                    ),
                                  ),
                                  if (e.byMaxPages) ...[
                                    const SizedBox(width: 6),
                                    SizedBox(
                                      width: 84,
                                      child: TextField(
                                        controller: e.maxPagesCtrl,
                                        decoration: const InputDecoration(
                                            labelText: '每份页'),
                                        onChanged: (_) => setState(() {}),
                                      ),
                                    ),
                                  ],
                                  const SizedBox(width: 4),
                                  IconButton(
                                    icon: const Icon(Icons.close_rounded,
                                        size: 16),
                                    tooltip: '移除',
                                    onPressed: () => setState(() {
                                      entries.removeAt(idx).dispose();
                                    }),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '输出目录：$outputDir',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: AppTypography.body,
                                color: ctx.appColors.mutedText,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final dir = (await FilePicker.pickDirectory())
                                  ?.toFilePath(windows: Platform.isWindows);
                              if (dir != null && ctx.mounted) {
                                setState(() => outputDir = dir);
                              }
                            },
                            child: const Text('选择目录'),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: CheckboxListTile(
                              value: includeAnnotations,
                              onChanged: (v) => setState(
                                  () => includeAnnotations = v ?? true),
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text('包含注释',
                                  style:
                                      TextStyle(fontSize: AppTypography.body)),
                              dense: true,
                            ),
                          ),
                          Expanded(
                            child: CheckboxListTile(
                              value: openFolderAfter,
                              onChanged: (v) =>
                                  setState(() => openFolderAfter = v ?? true),
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text('完成后打开目录',
                                  style:
                                      TextStyle(fontSize: AppTypography.body)),
                              dense: true,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
          ),
          actions: running
              ? [
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFE03131),
                    ),
                    onPressed: () => setState(() => cancelled = true),
                    child: const Text('停止'),
                  ),
                ]
              : [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: valid && tasks.isNotEmpty
                        ? () async {
                            setState(() {
                              running = true;
                              totalFiles = tasks.length;
                              processedFiles = 0;
                              outputCount = 0;
                            });
                            final outcomes =
                                await PdfEngineService.splitBatch(
                              tasks: tasks,
                              outputDir: outputDir,
                              includeAnnotations: includeAnnotations,
                              resolvedImages: controller.imageBytesCache,
                              onProgress: (pf, tf, out) {
                                if (ctx.mounted) {
                                  setState(() {
                                    processedFiles = pf;
                                    totalFiles = tf;
                                    outputCount = out;
                                  });
                                }
                              },
                              isCancelled: () => cancelled,
                            );
                            if (ctx.mounted) Navigator.of(ctx).pop();
                            final firstOut = outcomes
                                .expand((o) => o.outputs)
                                .firstOrNull;
                            if (openFolderAfter && firstOut != null) {
                              await NativeBridge.openFolder(firstOut,
                                  select: true);
                            }
                            final errList = outcomes
                                .where((o) => !o.ok)
                                .map((o) =>
                                    '${p.basename(o.path)}: ${o.error ?? "失败"}')
                                .toList();
                            if (errList.isNotEmpty) {
                              controller.addProblem(
                                  '拆分', errList.join('；'));
                            }
                            controller.showToast(
                              cancelled
                                  ? '已停止拆分（已输出 $outputCount 个文件）'
                                  : '拆分完成：共输出 $outputCount 个文件',
                            );
                          }
                        : null,
                    child: const Text('开始拆分'),
                  ),
                ],
        );
      },
    ),
  );
  } finally {
    for (final e in entries) {
      e.dispose();
    }
  }
}

Future<void> showOrientationUnifyDialog(
  BuildContext context,
  EditorController controller,
) async {
  if (!controller.hasDocument) return;
  OrientationPlanResult? plan;
  var analyzing = true;
  var cancelled = false;
  var progressCur = 0;
  var progressTotal = controller.pageCount;
  var started = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        if (!started) {
          started = true;
          controller
              .analyzeOrientation(
            onProgress: (cur, total) {
              if (!cancelled && ctx.mounted) {
                setState(() {
                  progressCur = cur;
                  progressTotal = total;
                });
              }
            },
          )
              .then((res) {
            if (!cancelled && ctx.mounted) {
              setState(() {
                plan = res;
                analyzing = false;
              });
            }
          });
        }

        if (analyzing) {
          return AlertDialog(
            title: const Text('统一页面方向',
                style: TextStyle(fontSize: AppTypography.title)),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                  Text('正在分析页面方向… ($progressCur / $progressTotal)',
                      style: const TextStyle(fontSize: AppTypography.body)),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  cancelled = true;
                  Navigator.of(ctx).pop();
                },
                child: const Text('取消'),
              ),
            ],
          );
        }

        final pRes = plan;
        if (pRes == null || pRes.base == null) {
          return AlertDialog(
            title: const Text('统一页面方向',
                style: TextStyle(fontSize: AppTypography.title)),
            content: Text(pRes?.baseError ?? '无法判定基准方向'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('关闭'),
              ),
            ],
          );
        }

        final items = pRes.items;
        return AlertDialog(
          title: Text(
            '统一页面方向（基准：${pRes.base == PageOrientationKind.portrait ? "纵向" : "横向"}）',
            style: const TextStyle(fontSize: AppTypography.title),
          ),
          content: SizedBox(
            width: 600,
            child: items.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Text('所有页面方向与内容朝向均已一致，无需调整。'),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text(
                            '发现 ${items.length} 页需核对或调整：',
                            style: TextStyle(
                              fontSize: AppTypography.body,
                              color: ctx.appColors.mutedText,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: () => setState(() {
                              for (final it in items) {
                                it.selected = it.delta != 0;
                              }
                            }),
                            child: const Text('全选有效项'),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              for (final it in items) {
                                it.selected = false;
                              }
                            }),
                            child: const Text('全部不转'),
                          ),
                        ],
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, idx) {
                            final item = items[idx];
                            return Row(
                              children: [
                                Checkbox(
                                  value: item.selected,
                                  onChanged: (v) => setState(
                                      () => item.selected = v ?? false),
                                ),
                                SizedBox(
                                  width: 78,
                                  child: Text('第 ${item.page} 页',
                                      style: const TextStyle(
                                          fontSize: AppTypography.body)),
                                ),
                                Expanded(
                                  child: Text(
                                    item.reason.label,
                                    style: TextStyle(
                                      fontSize: AppTypography.body,
                                      color: ctx.appColors.mutedText,
                                    ),
                                  ),
                                ),
                                DropdownButton<int>(
                                  value: item.delta,
                                  items: const [
                                    DropdownMenuItem(
                                        value: 0,
                                        child: Text('不转',
                                            style: TextStyle(
                                                fontSize: AppTypography.body))),
                                    DropdownMenuItem(
                                        value: 90,
                                        child: Text('顺时针 90°',
                                            style: TextStyle(
                                                fontSize: AppTypography.body))),
                                    DropdownMenuItem(
                                        value: 180,
                                        child: Text('旋转 180°',
                                            style: TextStyle(
                                                fontSize: AppTypography.body))),
                                    DropdownMenuItem(
                                        value: 270,
                                        child: Text('逆时针 90°',
                                            style: TextStyle(
                                                fontSize: AppTypography.body))),
                                  ],
                                  onChanged: (v) {
                                    if (v != null) {
                                      setState(() {
                                        item.delta = v;
                                        item.selected = v != 0;
                                      });
                                    }
                                  },
                                ),
                              ],
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                cancelled = true;
                Navigator.of(ctx).pop();
              },
              child: const Text('取消'),
            ),
            if (items.isNotEmpty)
              FilledButton(
                onPressed: () async {
                  final deltas = <int, int>{};
                  for (final it in items) {
                    if (it.selected && it.delta != 0) {
                      deltas[it.page - 1] = it.delta;
                    }
                  }
                  Navigator.of(ctx).pop();
                  if (deltas.isNotEmpty) {
                    await controller.rotatePages(deltas);
                  }
                },
                child: const Text('应用旋转'),
              ),
          ],
        );
      },
    ),
  );
}

Future<void> showImageToPdfDialog(
  BuildContext context,
  EditorController controller, {
  List<String> initialPaths = const [],
}) async {
  var nextImgId = 0;
  final imageItems = [
    for (final path in initialPaths) (id: nextImgId++, path: path),
  ];
  var useA4 = false;
  var converting = false;
  var done = 0;
  var total = 0;
  var currentName = '';

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) {
        return AlertDialog(
          title: const Text('图片转 PDF',
              style: TextStyle(fontSize: AppTypography.title)),
          content: SizedBox(
            width: 520,
            child: converting
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: total > 0 ? done / total : null,
                      ),
                      const SizedBox(height: 12),
                      Text('已转换 $done / $total：$currentName',
                          style: const TextStyle(fontSize: AppTypography.body)),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              final picked = await FilePicker.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: ['png', 'jpg', 'jpeg'],
                              );
                              if (picked.isEmpty) return;
                              for (final f in picked) {
                                if (f.path == null) continue;
                                final u8 = await File(f.path!)
                                    .openRead(0, 12)
                                    .expand((x) => x)
                                    .toList();
                                if (u8.length >= 8 &&
                                    ((u8[0] == 0x89 && u8[1] == 0x50) ||
                                        (u8[0] == 0xFF && u8[1] == 0xD8))) {
                                  if (imageItems.length <
                                      ImageToPdfService.maxImages) {
                                    imageItems.add((
                                      id: nextImgId++,
                                      path: f.path!,
                                    ));
                                  }
                                } else {
                                  controller.showToast(
                                    '已跳过非 PNG/JPEG 图片：${p.basename(f.path!)}',
                                    isError: true,
                                  );
                                }
                              }
                              if (!ctx.mounted) return;
                              setState(() {});
                            },
                            icon: const Icon(Icons.add_photo_alternate_outlined,
                                size: 17),
                            label: const Text('添加图片'),
                          ),
                          const Spacer(),
                          Text(
                            '共 ${imageItems.length} 张（上限 ${ImageToPdfService.maxImages}）',
                            style: TextStyle(
                              fontSize: AppTypography.body,
                              color: ctx.appColors.mutedText,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: imageItems.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Text(
                                    '请添加 PNG 或 JPEG 图片',
                                    style: TextStyle(
                                      fontSize: AppTypography.body,
                                      color: ctx.appColors.mutedText,
                                    ),
                                  ),
                                ),
                              )
                            : ReorderableListView.builder(
                                shrinkWrap: true,
                                itemCount: imageItems.length,
                                onReorderItem: (oldIndex, newIndex) {
                                  setState(() {
                                    final item = imageItems.removeAt(oldIndex);
                                    imageItems.insert(newIndex, item);
                                  });
                                },
                                itemBuilder: (_, idx) {
                                  final item = imageItems[idx];
                                  return ListTile(
                                    key: ValueKey('img_${item.id}'),
                                    dense: true,
                                    leading: const Icon(Icons.image_outlined,
                                        size: 18),
                                    title: Text(
                                      p.basename(item.path),
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: AppTypography.body),
                                    ),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.close_rounded,
                                          size: 16),
                                      onPressed: () => setState(
                                          () => imageItems.removeAt(idx)),
                                    ),
                                  );
                                },
                              ),
                      ),
                      const SizedBox(height: 10),
                      const Text('页面尺寸模式：',
                          style: TextStyle(fontSize: AppTypography.body)),
                      const SizedBox(height: 4),
                      SegmentedButton<bool>(
                        segments: const [
                          ButtonSegment(
                            value: false,
                            label: Text('按图像像素 (无留白)',
                                style: TextStyle(fontSize: AppTypography.body)),
                          ),
                          ButtonSegment(
                            value: true,
                            label: Text('A4 自动适配方向',
                                style: TextStyle(fontSize: AppTypography.body)),
                          ),
                        ],
                        selected: {useA4},
                        onSelectionChanged: (s) =>
                            setState(() => useA4 = s.first),
                      ),
                    ],
                  ),
          ),
          actions: converting
              ? null
              : [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: imageItems.isEmpty
                        ? null
                        : () async {
                            final savePath = await NativeBridge.pickSaveFile(
                              dialogTitle: '保存生成的 PDF',
                              fileName: '图片合成.pdf',
                              filterLabel: 'PDF 文档 (*.pdf)',
                              ext: 'pdf',
                            );
                            if (savePath == null || !ctx.mounted) return;
                            setState(() {
                              converting = true;
                              done = 0;
                              total = imageItems.length;
                            });
                            await controller.convertImagesToPdf(
                              imagePaths: [
                                for (final item in imageItems) item.path,
                              ],
                              targetPath: savePath,
                              useA4: useA4,
                              onProgress: (d, t, name) {
                                if (ctx.mounted) {
                                  setState(() {
                                    done = d;
                                    total = t;
                                    currentName = name;
                                  });
                                }
                              },
                            );
                            if (ctx.mounted) Navigator.of(ctx).pop();
                          },
                    child: const Text('开始生成 PDF'),
                  ),
                ],
        );
      },
    ),
  );
}
