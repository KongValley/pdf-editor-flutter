import 'dart:convert';
import 'dart:io';

import '../models/annotation_model.dart';
import 'recent_and_log_service.dart';

class SidecarData {
  const SidecarData({
    required this.version,
    required this.annotations,
    required this.formValues,
  });

  final int version;
  final List<PdfAnnotationItem> annotations;
  final Map<String, Object?> formValues;
}

class SidecarService {
  SidecarService._();

  static String sidecarPathFor(String pdfPath) => '$pdfPath.pdfanno.json';

  static Future<SidecarData?> readSidecar(String pdfPath) async {
    final file = File(sidecarPathFor(pdfPath));
    if (!file.existsSync()) return null;
    try {
      final raw = jsonDecode(await file.readAsString());
      if (raw is! Map) return null;
      final annotations = <PdfAnnotationItem>[];
      if (raw['annotations'] is List) {
        for (final item in raw['annotations'] as List) {
          final parsed = PdfAnnotationItem.tryFromJson(item);
          if (parsed != null) annotations.add(parsed);
        }
      }
      final formValues = raw['formValues'] is Map
          ? Map<String, Object?>.from(raw['formValues'] as Map)
          : <String, Object?>{};
      return SidecarData(
        version: (raw['version'] as num?)?.toInt() ?? 1,
        annotations: annotations,
        formValues: formValues,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> writeSidecar(
    String pdfPath, {
    required List<PdfAnnotationItem> annotations,
    Map<String, Object?> formValues = const {},
  }) async {
    final payload = <String, dynamic>{
      'version': 1,
      'annotations': annotations.map((a) => a.toJson()).toList(),
      'formValues': formValues,
    };
    await AppDataService.atomicWriteString(
      sidecarPathFor(pdfPath),
      const JsonEncoder.withIndent('  ').convert(payload),
    );
  }
}
