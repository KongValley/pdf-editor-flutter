import 'dart:collection';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../models/document_models.dart';

const int _ttcTag = 0x74746366; // 'ttcf'
const Set<int> _sfntVersions = {
  0x00010000,
  0x4F54544F, // 'OTTO'
  0x74727565, // 'true'
  0x74797031, // 'typ1'
};
const int _maxFontFileBytes = 128 * 1024 * 1024;
const int _fontBytesCacheLimit = 64 * 1024 * 1024;
const int _englishLang = 0x0409;
const List<int> _chineseLangs = [0x0804, 0x0404, 0x0C04, 0x1004];
const Set<String> _fontExtensions = {'.ttf', '.otf', '.ttc', '.otc'};

class _NameRecord {
  const _NameRecord({
    required this.platformId,
    required this.encodingId,
    required this.languageId,
    required this.nameId,
    required this.text,
  });

  final int platformId;
  final int encodingId;
  final int languageId;
  final int nameId;
  final String text;
}

class _TableRecord {
  const _TableRecord({
    required this.tag,
    required this.checksum,
    required this.offset,
    required this.length,
  });

  final String tag;
  final int checksum;
  final int offset;
  final int length;
}

class SystemFontsService {
  SystemFontsService._();

  static Future<List<SystemFontInfo>>? _listFuture;
  static final Map<String, SystemFontInfo> _aliasMap = {};
  static final LinkedHashMap<String, Uint8List> _bytesCache = LinkedHashMap();
  static int _cachedBytes = 0;
  static final Set<String> _loadedFlutterFonts = {};

  static String _normalizeKey(String v) =>
      v.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  static String _sanitizeText(String v) =>
      v.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();

  static Future<List<SystemFontInfo>> listFonts() async {
    if (_listFuture != null) return _listFuture!;
    _listFuture = _scanFontsInIsolate().then((faces) {
      _aliasMap.clear();
      for (final face in faces) {
        for (final alias in face.aliases) {
          final k = _normalizeKey(alias);
          if (k.isNotEmpty && !_aliasMap.containsKey(k)) {
            _aliasMap[k] = face;
          }
        }
      }
      for (final face in faces) {
        _aliasMap[_normalizeKey(face.family)] = face;
        _aliasMap[_normalizeKey(face.label)] = face;
      }
      return faces;
    }).catchError((Object err) {
      _listFuture = null;
      throw err;
    });
    return _listFuture!;
  }

  static Future<SystemFontInfo?> findFont(String? family) async {
    final key = _normalizeKey(family ?? '');
    if (key.isEmpty) return null;
    await listFonts();
    return _aliasMap[key];
  }

  static Future<void> ensureFlutterFontLoaded(SystemFontInfo face) async {
    final familyKey = face.family;
    if (_loadedFlutterFonts.contains(familyKey)) return;
    try {
      final bytes = await readFaceBytes(face);
      final loader = FontLoader(familyKey);
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      _loadedFlutterFonts.add(familyKey);
    } catch (_) {
      // 回退到系统默认字体，不影响展示
    }
  }

  /// 查找默认可用中文字体（优先黑体/楷体/微软雅黑/宋体）
  static String? findDefaultCjkFontPath() {
    final windir = Platform.environment['WINDIR'] ?? r'C:\Windows';
    final candidates = [
      p.join(windir, 'Fonts', 'simhei.ttf'),
      p.join(windir, 'Fonts', 'simkai.ttf'),
      p.join(windir, 'Fonts', 'msyh.ttc'),
      p.join(windir, 'Fonts', 'simsun.ttc'),
    ];
    for (final candidate in candidates) {
      try {
        if (File(candidate).existsSync()) return candidate;
      } catch (_) {}
    }
    return null;
  }

  static Future<Uint8List?> readDefaultCjkFontBytes() async {
    final path = findDefaultCjkFontPath();
    if (path == null) return null;
    final key = '${_normalizeKey(path)}#0';
    final cached = _bytesCache.remove(key);
    if (cached != null) {
      _bytesCache[key] = cached;
      return cached;
    }
    try {
      final raw = await File(path).readAsBytes();
      final sfnt = extractFaceFromCollection(raw, 0);
      _putCache(key, sfnt);
      return sfnt;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List> readFaceBytes(SystemFontInfo face) async {
    final key = '${_normalizeKey(face.filePath)}#${face.faceIndex}';
    final cached = _bytesCache.remove(key);
    if (cached != null) {
      _bytesCache[key] = cached;
      return cached;
    }
    final file = File(face.filePath);
    final stat = await file.stat();
    if (stat.size > _maxFontFileBytes) {
      throw StateError('字体文件过大: ${face.filePath}');
    }
    final raw = await file.readAsBytes();
    final faceBytes = extractFaceFromCollection(raw, face.faceIndex);
    _putCache(key, faceBytes);
    return faceBytes;
  }

  static void _putCache(String key, Uint8List data) {
    if (data.length > _fontBytesCacheLimit) return;
    final prev = _bytesCache.remove(key);
    if (prev != null) {
      _cachedBytes -= prev.length;
    }
    while (_cachedBytes + data.length > _fontBytesCacheLimit &&
        _bytesCache.isNotEmpty) {
      final oldestKey = _bytesCache.keys.first;
      final oldest = _bytesCache.remove(oldestKey);
      _cachedBytes -= oldest?.length ?? 0;
    }
    _bytesCache[key] = data;
    _cachedBytes += data.length;
  }

  /// 将 TTC/OTC 中指定索引的面抽取为独立 sfnt 字体字节
  static Uint8List extractFaceFromCollection(Uint8List bytes, int index) {
    if (bytes.length < 12) return bytes;
    final bd = ByteData.sublistView(bytes);
    if (bd.getUint32(0) != _ttcTag) return bytes;

    final count = bd.getUint32(8);
    if (count == 0 || index < 0 || index >= count) {
      throw StateError('字体集合索引越界');
    }
    if (12 + count * 4 > bytes.length) {
      throw StateError('字体集合头损坏');
    }
    final faceOffset = bd.getUint32(12 + index * 4);
    if (faceOffset + 12 > bytes.length) {
      throw StateError('字体集合表目录越界');
    }

    final version = bd.getUint32(faceOffset);
    if (!_sfntVersions.contains(version)) {
      throw StateError('不支持的字体格式');
    }
    final numTables = bd.getUint16(faceOffset + 4);
    if (numTables == 0 || numTables > 256 ||
        faceOffset + 12 + numTables * 16 > bytes.length) {
      throw StateError('字体表目录损坏');
    }

    final tables = <_TableRecord>[];
    for (var i = 0; i < numTables; i++) {
      final recAt = faceOffset + 12 + i * 16;
      final tag = latin1.decode(bytes.sublist(recAt, recAt + 4));
      final checksum = bd.getUint32(recAt + 4);
      final offset = bd.getUint32(recAt + 8);
      final length = bd.getUint32(recAt + 12);
      if (offset + length > bytes.length) {
        throw StateError('字体表 $tag 越界');
      }
      tables.add(_TableRecord(
        tag: tag,
        checksum: checksum,
        offset: offset,
        length: length,
      ));
    }

    int align4(int v) => (v + 3) & ~3;
    var total = 12 + numTables * 16;
    final newOffsets = List<int>.filled(tables.length, 0);
    for (var i = 0; i < tables.length; i++) {
      newOffsets[i] = total;
      total += align4(tables[i].length);
    }
    if (total > (bytes.length * 2).clamp(16 * 1024 * 1024, 256 * 1024 * 1024)) {
      throw StateError('字体表数据异常');
    }

    final out = Uint8List(total);
    final outBd = ByteData.sublistView(out);
    out.setRange(0, 12, bytes, faceOffset);

    _TableRecord? headTable;
    int headNewOffset = 0;
    for (var i = 0; i < tables.length; i++) {
      final t = tables[i];
      final recAt = 12 + i * 16;
      out.setRange(recAt, recAt + 4, latin1.encode(t.tag));
      outBd.setUint32(recAt + 4, t.checksum);
      outBd.setUint32(recAt + 8, newOffsets[i]);
      outBd.setUint32(recAt + 12, t.length);
      out.setRange(newOffsets[i], newOffsets[i] + t.length, bytes, t.offset);
      if (t.tag == 'head') {
        headTable = t;
        headNewOffset = newOffsets[i];
      }
    }

    if (headTable != null &&
        headTable.length >= 12 &&
        headNewOffset + 12 <= out.length) {
      outBd.setUint32(headNewOffset + 8, 0);
      var sum = 0;
      for (var i = 0; i + 4 <= out.length; i += 4) {
        sum = (sum + outBd.getUint32(i)) & 0xFFFFFFFF;
      }
      final adj = (0xB1B0AFBA - sum) & 0xFFFFFFFF;
      outBd.setUint32(headNewOffset + 8, adj);
    }
    return out;
  }

  /// 检查独立 sfnt 字体是否包含文本中所有可见字符的字形（解析 cmap format 4 / 12）
  static bool fontCoversText(Uint8List sfnt, String text) {
    final codepoints = <int>[];
    for (final rune in text.runes) {
      if (rune < 0x20 ||
          rune == 0x7F ||
          (rune >= 0x200B && rune <= 0x200F) ||
          rune == 0xFEFF) {
        continue;
      }
      codepoints.add(rune);
    }
    if (codepoints.isEmpty) return true;
    if (sfnt.length < 12) return false;

    final bd = ByteData.sublistView(sfnt);
    final numTables = bd.getUint16(4);
    int cmapOffset = -1;
    int cmapLength = 0;
    for (var i = 0; i < numTables; i++) {
      final recAt = 12 + i * 16;
      if (recAt + 16 > sfnt.length) break;
      final tag = latin1.decode(sfnt.sublist(recAt, recAt + 4));
      if (tag == 'cmap') {
        cmapOffset = bd.getUint32(recAt + 8);
        cmapLength = bd.getUint32(recAt + 12);
        break;
      }
    }
    if (cmapOffset < 0 || cmapOffset + cmapLength > sfnt.length || cmapLength < 4) {
      return false;
    }

    final cmapEnd = cmapOffset + cmapLength;
    final numSubtables = bd.getUint16(cmapOffset + 2);
    int? format12Off;
    int format12Prio = -1;
    int? format4Off;
    int format4Prio = -1;
    for (var i = 0; i < numSubtables; i++) {
      final subAt = cmapOffset + 4 + i * 8;
      if (subAt + 8 > cmapEnd) break;
      final platform = bd.getUint16(subAt);
      final encoding = bd.getUint16(subAt + 2);
      final relOff = bd.getUint32(subAt + 4);
      final absOff = cmapOffset + relOff;
      if (absOff + 4 > cmapEnd) continue;
      final format = bd.getUint16(absOff);
      final prio = switch ((platform, encoding)) {
        (3, 10) => 5,
        (0, 4) => 4,
        (0, 3) => 3,
        (3, 1) => 2,
        (0, _) => 1,
        _ => -1,
      };
      if (prio < 0) continue;
      if (format == 12 && prio > format12Prio) {
        format12Off = absOff;
        format12Prio = prio;
      }
      if (format == 4 && prio > format4Prio) {
        format4Off = absOff;
        format4Prio = prio;
      }
    }

    if (format12Off != null &&
        _checkFormat12(bd, cmapEnd, format12Off, codepoints)) {
      return true;
    }
    if (format4Off != null) {
      return _checkFormat4(bd, cmapEnd, format4Off, codepoints);
    }
    return false;
  }

  static bool _checkFormat12(
      ByteData bd, int totalLen, int offset, List<int> codepoints) {
    if (offset + 16 > totalLen) return false;
    final numGroups = bd.getUint32(offset + 12);
    if (offset + 16 + numGroups * 12 > totalLen) return false;
    for (final cp in codepoints) {
      var low = 0;
      var high = numGroups - 1;
      var found = false;
      while (low <= high) {
        final mid = (low + high) >> 1;
        final g = offset + 16 + mid * 12;
        final start = bd.getUint32(g);
        final end = bd.getUint32(g + 4);
        final startGlyph = bd.getUint32(g + 8);
        if (cp < start) {
          high = mid - 1;
        } else if (cp > end) {
          low = mid + 1;
        } else {
          found = (startGlyph + (cp - start)) != 0;
          break;
        }
      }
      if (!found) return false;
    }
    return true;
  }

  static bool _checkFormat4(
      ByteData bd, int totalLen, int offset, List<int> codepoints) {
    if (offset + 14 > totalLen) return false;
    final segCount = bd.getUint16(offset + 6) >> 1;
    final endCodesOff = offset + 14;
    final startCodesOff = endCodesOff + segCount * 2 + 2;
    final idDeltaOff = startCodesOff + segCount * 2;
    final idRangeOff = idDeltaOff + segCount * 2;
    if (idRangeOff + segCount * 2 > totalLen) return false;

    for (final cp in codepoints) {
      if (cp > 0xFFFF) return false;
      var found = false;
      for (var i = 0; i < segCount; i++) {
        final endCode = bd.getUint16(endCodesOff + i * 2);
        if (cp > endCode) continue;
        final startCode = bd.getUint16(startCodesOff + i * 2);
        if (cp < startCode || startCode == 0xFFFF) break;
        final rangeOff = bd.getUint16(idRangeOff + i * 2);
        int glyphId = 0;
        if (rangeOff == 0) {
          final delta = bd.getInt16(idDeltaOff + i * 2);
          glyphId = (cp + delta) & 0xFFFF;
        } else {
          final glyphIdxOff =
              idRangeOff + i * 2 + rangeOff + (cp - startCode) * 2;
          if (glyphIdxOff + 2 <= totalLen) {
            glyphId = bd.getUint16(glyphIdxOff);
            if (glyphId != 0) {
              glyphId = (glyphId + bd.getInt16(idDeltaOff + i * 2)) & 0xFFFF;
            }
          }
        }
        found = glyphId != 0;
        break;
      }
      if (!found) return false;
    }
    return true;
  }

  static Future<List<SystemFontInfo>> _scanFontsInIsolate() async {
    return compute(_scanFontsSync, null);
  }

  static List<String> _collectRegistryFontPaths(String winFontsDir) {
    if (!Platform.isWindows) return const [];
    final paths = <String>[];
    try {
      final advapi = DynamicLibrary.open('advapi32.dll');
      final regOpen = advapi.lookupFunction<
          Int32 Function(IntPtr, Pointer<Utf16>, Uint32, Uint32, Pointer<IntPtr>),
          int Function(int, Pointer<Utf16>, int, int, Pointer<IntPtr>)>(
        'RegOpenKeyExW',
      );
      final regEnum = advapi.lookupFunction<
          Int32 Function(
            IntPtr,
            Uint32,
            Pointer<Utf16>,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Uint8>,
            Pointer<Uint32>,
          ),
          int Function(
            int,
            int,
            Pointer<Utf16>,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Uint32>,
            Pointer<Uint8>,
            Pointer<Uint32>,
          )>('RegEnumValueW');
      final regClose = advapi.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'RegCloseKey',
      );

      const hklm = -2147483646; // 0x80000002 HKEY_LOCAL_MACHINE
      const hkcu = -2147483647; // 0x80000001 HKEY_CURRENT_USER
      const keyRead = 0x20019;
      const regSz = 1;
      const errSuccess = 0;
      const errMoreData = 234;
      const errNoMoreItems = 259;

      using((arena) {
        final subKey = r'SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
            .toNativeUtf16(allocator: arena);
        final hKeyOut = arena<IntPtr>();
        var nameBufChars = 512;
        var nameBuf = arena<Uint16>(nameBufChars);
        var dataBufBytes = 2048;
        var dataBuf = arena<Uint8>(dataBufBytes);
        final nameLen = arena<Uint32>();
        final dataType = arena<Uint32>();
        final dataLen = arena<Uint32>();

        for (final hive in [hklm, hkcu]) {
          hKeyOut.value = 0;
          if (regOpen(hive, subKey, 0, keyRead, hKeyOut) != errSuccess) {
            continue;
          }
          final hKey = hKeyOut.value;
          try {
            var idx = 0;
            while (true) {
              nameLen.value = nameBufChars;
              dataLen.value = dataBufBytes;
              final rc = regEnum(
                hKey,
                idx,
                nameBuf.cast<Utf16>(),
                nameLen,
                nullptr,
                dataType,
                dataBuf,
                dataLen,
              );
              if (rc == errNoMoreItems) break;
              if (rc == errMoreData) {
                if (nameLen.value + 2 > nameBufChars) {
                  nameBufChars = nameLen.value + 64;
                  nameBuf = arena<Uint16>(nameBufChars);
                }
                if (dataLen.value + 4 > dataBufBytes) {
                  dataBufBytes = dataLen.value + 64;
                  dataBuf = arena<Uint8>(dataBufBytes);
                }
                continue;
              }
              idx++;
              if (rc != errSuccess || dataType.value != regSz) continue;
              final rawVal = dataBuf
                  .cast<Utf16>()
                  .toDartString(length: dataLen.value ~/ 2)
                  .replaceAll('\x00', '')
                  .trim();
              if (rawVal.isEmpty) continue;
              final fullPath = p.isAbsolute(rawVal)
                  ? rawVal
                  : p.join(winFontsDir, rawVal);
              if (_fontExtensions.contains(p.extension(fullPath).toLowerCase()) &&
                  File(fullPath).existsSync()) {
                paths.add(fullPath);
              }
            }
          } finally {
            regClose(hKey);
          }
        }
      });
    } catch (_) {}
    return paths;
  }

  static List<SystemFontInfo> _scanFontsSync(void _) {
    final winFontsDir =
        p.join(Platform.environment['WINDIR'] ?? r'C:\Windows', 'Fonts');
    final dirs = <String>[
      winFontsDir,
      if (Platform.environment['LOCALAPPDATA'] != null)
        p.join(
          Platform.environment['LOCALAPPDATA']!,
          'Microsoft',
          'Windows',
          'Fonts',
        ),
    ];
    final files = <String>[];
    final seenPaths = <String>{};
    for (final dirPath in dirs) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;
      try {
        for (final entity in dir.listSync(recursive: true, followLinks: true)) {
          if (entity is! File) continue;
          final ext = p.extension(entity.path).toLowerCase();
          if (!_fontExtensions.contains(ext)) continue;
          final norm = _normalizeKey(entity.path);
          if (seenPaths.add(norm)) {
            files.add(entity.path);
          }
        }
      } catch (_) {}
    }
    for (final regPath in _collectRegistryFontPaths(winFontsDir)) {
      final norm = _normalizeKey(regPath);
      if (seenPaths.add(norm)) {
        files.add(regPath);
      }
    }

    final allFaces = <SystemFontInfo>[];
    for (final file in files) {
      allFaces.addAll(_parseFontFileHeaders(file));
    }

    final byFamily = <String, SystemFontInfo>{};
    for (final face in allFaces) {
      final key = _normalizeKey(face.family);
      if (key.isEmpty || key.startsWith('@')) continue;
      final existing = byFamily[key];
      if (existing == null || _regularScore(face) < _regularScore(existing)) {
        byFamily[key] = face;
      }
    }
    final list = byFamily.values.toList()
      ..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return list;
  }

  static int _regularScore(SystemFontInfo face) {
    final style = face.style.toLowerCase();
    if (RegExp(r'^(regular|normal|book|roman|标准|常规)$').hasMatch(style)) {
      return 0;
    }
    if (style.contains('regular') || style.contains('normal')) return 1;
    if (style.contains('bold') ||
        style.contains('italic') ||
        style.contains('black') ||
        style.contains('heavy')) {
      return 3;
    }
    return 2;
  }

  static List<SystemFontInfo> _parseFontFileHeaders(String filePath) {
    RandomAccessFile? raf;
    try {
      final file = File(filePath);
      final size = file.lengthSync();
      if (size < 12 || size > _maxFontFileBytes) return const [];
      raf = file.openSync(mode: FileMode.read);
      final headLen = size < 65536 ? size : 65536;
      final head = raf.readSync(headLen);
      if (head.length < 12) return const [];
      final headBd = ByteData.sublistView(head);

      final offsets = <int>[];
      final tag = headBd.getUint32(0);
      if (tag == _ttcTag) {
        final count = headBd.getUint32(8);
        if (count == 0 || count > 256 || head.length < 12 + count * 4) {
          return const [];
        }
        for (var i = 0; i < count; i++) {
          offsets.add(headBd.getUint32(12 + i * 4));
        }
      } else if (_sfntVersions.contains(tag)) {
        offsets.add(0);
      } else {
        return const [];
      }

      final faces = <SystemFontInfo>[];
      for (var index = 0; index < offsets.length; index++) {
        final faceOffset = offsets[index];
        if (faceOffset + 12 > size) continue;
        Uint8List header;
        if (faceOffset + 12 + 16 * 256 <= head.length) {
          header = Uint8List.sublistView(head, faceOffset);
        } else {
          raf.setPositionSync(faceOffset);
          final toRead = (size - faceOffset).clamp(0, 12 + 16 * 256);
          header = raf.readSync(toRead);
        }
        if (header.length < 12) continue;
        final hBd = ByteData.sublistView(header);
        if (!_sfntVersions.contains(hBd.getUint32(0))) continue;
        final numTables = hBd.getUint16(4);
        if (numTables == 0 || numTables > 256) continue;

        int? nameOff;
        int? nameLen;
        for (var i = 0; i < numTables; i++) {
          final recAt = 12 + i * 16;
          if (recAt + 16 > header.length) break;
          final tTag = latin1.decode(header.sublist(recAt, recAt + 4));
          if (tTag != 'name') continue;
          final off = hBd.getUint32(recAt + 8);
          final len = hBd.getUint32(recAt + 12);
          if (off + len <= size && len > 0 && len <= 4 * 1024 * 1024) {
            nameOff = off;
            nameLen = len;
          }
          break;
        }
        if (nameOff == null || nameLen == null) continue;
        raf.setPositionSync(nameOff);
        final nameBuf = raf.readSync(nameLen);
        final face = _namesToFace(_parseNameTable(nameBuf), filePath, index);
        if (face != null) faces.add(face);
      }
      return faces;
    } catch (_) {
      return const [];
    } finally {
      try {
        raf?.closeSync();
      } catch (_) {}
    }
  }

  static List<_NameRecord> _parseNameTable(Uint8List buf) {
    if (buf.length < 6) return const [];
    final bd = ByteData.sublistView(buf);
    final count = bd.getUint16(2);
    final stringOff = bd.getUint16(4);
    final records = <_NameRecord>[];
    for (var i = 0; i < count; i++) {
      final recAt = 6 + i * 12;
      if (recAt + 12 > buf.length) break;
      final platformId = bd.getUint16(recAt);
      final encodingId = bd.getUint16(recAt + 2);
      final languageId = bd.getUint16(recAt + 4);
      final nameId = bd.getUint16(recAt + 6);
      final length = bd.getUint16(recAt + 8);
      final offset = bd.getUint16(recAt + 10);
      final start = stringOff + offset;
      if (start + length > buf.length) continue;

      var text = '';
      final isUnicodeWin = platformId == 0 ||
          (platformId == 3 &&
              (encodingId == 0 || encodingId == 1 || encodingId == 10));
      if (isUnicodeWin) {
        if (length % 2 == 0) {
          final codes = List<int>.generate(
            length ~/ 2,
            (j) => bd.getUint16(start + j * 2),
          );
          text = String.fromCharCodes(codes);
        }
      } else if (platformId == 1 && encodingId == 0) {
        text = latin1.decode(buf.sublist(start, start + length));
      }
      text = _sanitizeText(text);
      if (text.isNotEmpty) {
        records.add(_NameRecord(
          platformId: platformId,
          encodingId: encodingId,
          languageId: languageId,
          nameId: nameId,
          text: text,
        ));
      }
    }
    return records;
  }

  static String? _pickName(
      List<_NameRecord> records, List<int> nameIds, List<int> langs) {
    for (final nid in nameIds) {
      for (final lang in langs) {
        for (final r in records) {
          if (r.nameId == nid &&
              r.platformId == 3 &&
              (r.encodingId == 0 || r.encodingId == 1 || r.encodingId == 10) &&
              r.languageId == lang) {
            return r.text;
          }
        }
      }
    }
    return null;
  }

  static String? _anyName(List<_NameRecord> records, List<int> nameIds) {
    for (final nid in nameIds) {
      for (final pId in [3, 0, -1]) {
        for (final r in records) {
          if (r.nameId == nid && (pId == -1 || r.platformId == pId)) {
            return r.text;
          }
        }
      }
    }
    return null;
  }

  static SystemFontInfo? _namesToFace(
      List<_NameRecord> records, String filePath, int index) {
    final familyEn = _pickName(records, [1], [_englishLang]) ??
        _pickName(records, [16], [_englishLang]) ??
        _anyName(records, [1, 16]);
    if (familyEn == null || familyEn.isEmpty) return null;

    final familyZh = _pickName(records, [1, 16], _chineseLangs);
    final label = (familyZh != null && familyZh != familyEn) ? familyZh : familyEn;
    final style = _pickName(records, [2], [_englishLang]) ??
        _pickName(records, [17], [_englishLang]) ??
        _anyName(records, [2, 17]) ??
        'Regular';
    final psName = _anyName(records, [6]) ?? '';
    final aliases = <String>{
      _sanitizeText(familyEn),
      _sanitizeText(label),
      if (psName.isNotEmpty) _sanitizeText(psName),
      for (final r in records)
        if (r.nameId == 1 || r.nameId == 16) _sanitizeText(r.text),
    }..removeWhere((e) => e.isEmpty);

    return SystemFontInfo(
      family: _sanitizeText(familyEn),
      label: _sanitizeText(label),
      style: _sanitizeText(style),
      filePath: filePath,
      faceIndex: index,
      aliases: aliases.toList(),
    );
  }
}
