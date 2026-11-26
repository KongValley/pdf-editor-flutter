import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/document_models.dart';

enum AppLogLevel {
  debug('调试', 0),
  info('信息', 1),
  off('关闭', 99);

  const AppLogLevel(this.label, this.priority);
  final String label;
  final int priority;
}

class AppDataService {
  AppDataService._();

  static Directory? _appDir;
  static Directory? _logDir;
  static AppLogLevel logLevel = AppLogLevel.info;
  static const int _maxRecent = 10;
  static const int _maxLogBytes = 1024 * 1024;
  static const int _maxLogFiles = 3;

  static Future<Directory> ensureAppDir() async {
    if (_appDir != null) return _appDir!;
    final support = await getApplicationSupportDirectory();
    if (!support.existsSync()) {
      support.createSync(recursive: true);
    }
    _appDir = support;
    return support;
  }

  static Future<Directory> ensureLogDir() async {
    if (_logDir != null) return _logDir!;
    final base = await ensureAppDir();
    final logs = Directory(p.join(base.path, 'logs'));
    if (!logs.existsSync()) {
      logs.createSync(recursive: true);
    }
    _logDir = logs;
    return logs;
  }

  static Future<bool> isDataDirWritable() async {
    try {
      final dir = await ensureAppDir();
      final probe = File(p.join(dir.path, '.write_probe'));
      await probe.writeAsString('ok');
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> log(
    String level,
    String category,
    String message, [
    Map<String, Object?>? meta,
  ]) async {
    if (logLevel == AppLogLevel.off) return;
    if (logLevel == AppLogLevel.info && level == 'debug') return;
    try {
      final dir = await ensureLogDir();
      final now = DateTime.now();
      final dateStr =
          '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      final logFile = File(p.join(dir.path, 'app-$dateStr.log'));
      if (logFile.existsSync() && logFile.lengthSync() > _maxLogBytes) {
        var seq = 1;
        while (File(p.join(dir.path, 'app-$dateStr.$seq.log')).existsSync()) {
          seq++;
        }
        try {
          await logFile.rename(p.join(dir.path, 'app-$dateStr.$seq.log'));
        } catch (_) {}
        await _rotateLogs(dir);
      }
      final ts = now.toIso8601String();
      final metaStr = meta == null || meta.isEmpty ? '' : ' ${jsonEncode(meta)}';
      await logFile.writeAsString(
        '[$ts] [$level] [$category] $message$metaStr\n',
        mode: FileMode.append,
        flush: false,
      );
    } catch (_) {}
  }

  static Future<void> _rotateLogs(Directory dir) async {
    try {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('app-') && f.path.endsWith('.log'))
          .toList()
        ..sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
      if (files.length >= _maxLogFiles) {
        for (var i = _maxLogFiles - 1; i < files.length; i++) {
          await files[i].delete().catchError((_) => files[i]);
        }
      }
    } catch (_) {}
  }

  static Future<List<RecentDocumentEntry>> listRecent() async {
    try {
      final dir = await ensureAppDir();
      final file = File(p.join(dir.path, 'recent.json'));
      if (!file.existsSync()) return const [];
      final raw = jsonDecode(await file.readAsString());
      if (raw is! List) return const [];
      final out = <RecentDocumentEntry>[];
      for (final item in raw) {
        if (item is Map) {
          final entry =
              RecentDocumentEntry.fromJson(Map<String, dynamic>.from(item));
          if (entry.path.isNotEmpty) out.add(entry);
        }
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  static Future<RecentDocumentEntry?> getRecentFor(String filePath) async {
    final norm = _normPath(filePath);
    final list = await listRecent();
    for (final item in list) {
      if (_normPath(item.path) == norm) return item;
    }
    return null;
  }

  static Future<void> _recentChain = Future.value();
  static int _tmpCounter = 0;

  static Future<void> recordRecent(String filePath, int page) {
    if (filePath.trim().isEmpty) return Future.value();
    final op = _recentChain.then((_) => _recordRecentImpl(filePath, page));
    _recentChain = op.catchError((_) {});
    return op;
  }

  static Future<void> removeRecent(String filePath) {
    if (filePath.trim().isEmpty) return Future.value();
    final op = _recentChain.then((_) => _removeRecentImpl(filePath));
    _recentChain = op.catchError((_) {});
    return op;
  }

  static Future<void> clearRecent({bool missingOnly = false}) {
    final op = _recentChain.then((_) => _clearRecentImpl(missingOnly));
    _recentChain = op.catchError((_) {});
    return op;
  }

  static Future<void> _writeRecentList(List<RecentDocumentEntry> list) async {
    final dir = await ensureAppDir();
    final file = File(p.join(dir.path, 'recent.json'));
    await atomicWriteString(
      file.path,
      const JsonEncoder.withIndent('  ').convert(
        list.map((e) => e.toJson()).toList(),
      ),
    );
  }

  static Future<void> _removeRecentImpl(String filePath) async {
    try {
      final list = (await listRecent()).toList();
      final norm = _normPath(filePath);
      final before = list.length;
      list.removeWhere((item) => _normPath(item.path) == norm);
      if (list.length != before) {
        await _writeRecentList(list);
      }
    } catch (_) {}
  }

  static Future<void> _clearRecentImpl(bool missingOnly) async {
    try {
      if (!missingOnly) {
        await _writeRecentList(const []);
        return;
      }
      final list = (await listRecent())
          .where((item) => File(item.path).existsSync())
          .toList();
      await _writeRecentList(list);
    } catch (_) {}
  }

  static Future<void> _recordRecentImpl(String filePath, int page) async {
    try {
      final list = (await listRecent()).toList();
      final norm = _normPath(filePath);
      list.removeWhere((item) => _normPath(item.path) == norm);
      list.insert(
        0,
        RecentDocumentEntry(
          path: filePath,
          page: page < 1 ? 1 : page,
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );
      if (list.length > _maxRecent) {
        list.removeRange(_maxRecent, list.length);
      }
      await _writeRecentList(list);
    } catch (_) {}
  }

  static String _normPath(String path) => p.normalize(path).toLowerCase();

  static Future<void> atomicWriteString(String targetPath, String content) async {
    await atomicWriteBytes(targetPath, utf8.encode(content));
  }

  static Future<void> atomicWriteBytes(String targetPath, List<int> bytes) async {
    final target = File(targetPath);
    final parent = target.parent;
    if (!parent.existsSync()) {
      parent.createSync(recursive: true);
    }
    final tmpPath =
        '$targetPath.${DateTime.now().microsecondsSinceEpoch}.${_tmpCounter++}.tmp';
    final tmpFile = File(tmpPath);
    try {
      await tmpFile.writeAsBytes(bytes, flush: true);
      try {
        await tmpFile.rename(targetPath);
      } catch (_) {
        // Windows 上若目标存在或跨权限，拷贝覆盖后删临时文件
        await tmpFile.copy(targetPath);
      }
    } finally {
      if (tmpFile.existsSync()) {
        await tmpFile.delete().catchError((_) => tmpFile);
      }
    }
  }
}
