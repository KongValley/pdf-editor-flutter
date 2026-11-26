import 'package:flutter/services.dart';

class NativeOcrOrientationResult {
  const NativeOcrOrientationResult({
    required this.ok,
    this.delta = 0,
    this.confidence = 0,
  });

  final bool ok;
  final int delta;
  final double confidence;
}

class NativePrintResult {
  const NativePrintResult({
    required this.ok,
    this.canceled = false,
    this.error,
  });

  final bool ok;
  final bool canceled;
  final String? error;
}

class NativeBridge {
  NativeBridge._();
  static const MethodChannel _channel = MethodChannel('pdf_editor_flutter/native');

  static Future<void> setTitle(String title) async {
    try {
      await _channel.invokeMethod<bool>('setTitle', {'title': title});
    } catch (_) {}
  }

  static Future<void> setDirty(bool dirty) async {
    try {
      await _channel.invokeMethod<bool>('setDirty', {'dirty': dirty});
    } catch (_) {}
  }

  static Future<bool> toggleFullscreen() async {
    try {
      return await _channel.invokeMethod<bool>('toggleFullscreen') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> openFolder(String path, {bool select = false}) async {
    try {
      return await _channel.invokeMethod<bool>('openFolder', {
            'path': path,
            'select': select,
          }) ??
          false;
    } catch (_) {
      return false;
    }
  }

  static void setCloseRequestHandler(Future<bool> Function()? handler) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'requestClose' && handler != null) {
        return await handler();
      }
      return null;
    });
  }

  static Future<void> forceCloseWindow() async {
    try {
      await _channel.invokeMethod<bool>('forceClose');
    } catch (_) {}
  }

  static Future<NativeOcrOrientationResult> detectOcrOrientation({
    required Uint8List bgraBytes,
    required int width,
    required int height,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<Object?, Object?>(
        'ocrDetectOrientation',
        {
          'bytes': bgraBytes,
          'width': width,
          'height': height,
        },
      );
      if (raw == null || raw['ok'] != true) {
        return const NativeOcrOrientationResult(ok: false);
      }
      final delta = (raw['delta'] as num?)?.toInt() ?? 0;
      final confidence = (raw['confidence'] as num?)?.toDouble() ?? 0.0;
      if (delta != 0 && delta != 90 && delta != 180 && delta != 270) {
        return const NativeOcrOrientationResult(ok: false);
      }
      return NativeOcrOrientationResult(
        ok: true,
        delta: delta,
        confidence: confidence,
      );
    } catch (_) {
      return const NativeOcrOrientationResult(ok: false);
    }
  }

  static Future<String?> printPrepare(String jobName) async {
    return await _channel.invokeMethod<String>('printPrepare', {
      'jobName': jobName,
    });
  }

  static Future<void> printAddPage({
    required String jobId,
    required String rawPath,
    required double widthPt,
    required double heightPt,
  }) async {
    await _channel.invokeMethod<bool>('printAddPage', {
      'jobId': jobId,
      'rawPath': rawPath,
      'widthPt': widthPt,
      'heightPt': heightPt,
    });
  }

  static Future<void> printAbort(String jobId) async {
    try {
      await _channel.invokeMethod<bool>('printAbort', {'jobId': jobId});
    } catch (_) {}
  }

  static Future<NativePrintResult> printCommit(String jobId) async {
    final raw = await _channel.invokeMapMethod<Object?, Object?>(
      'printCommit',
      {'jobId': jobId},
    );
    if (raw == null) {
      return const NativePrintResult(ok: false, error: '打印返回为空');
    }
    return NativePrintResult(
      ok: raw['ok'] == true,
      canceled: raw['canceled'] == true,
      error: raw['error'] as String?,
    );
  }

  static Future<String?> pickSaveFile({
    String? dialogTitle,
    String? fileName,
    String? filterLabel,
    String? ext,
  }) async {
    try {
      return await _channel.invokeMethod<String>('pickSaveFile', {
        'dialogTitle': ?dialogTitle,
        'fileName': ?fileName,
        'filterLabel': ?filterLabel,
        'ext': ?ext,
      });
    } catch (_) {
      return null;
    }
  }
}
