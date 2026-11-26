import 'dart:math' as math;

enum EditorTool {
  select('选择', '选择 / 移动批注与选区复制'),
  highlight('高亮', '高亮：划选文本或拖拽框选'),
  rect('矩形', '矩形框'),
  ellipse('椭圆', '椭圆框'),
  ink('画笔', '自由绘制'),
  arrow('箭头', '箭头标注'),
  measure('测量', '距离测量 (mm)'),
  text('文字', '插入文字批注'),
  note('便签', '插入便签'),
  stamp('图章', '插入图章'),
  image('图片', '插入图片 (PNG/JPEG)');

  const EditorTool(this.label, this.tooltip);
  final String label;
  final String tooltip;

  bool get isDrawTool => this != EditorTool.select;

  AnnotationKind? get annotationKind => switch (this) {
        EditorTool.select => null,
        EditorTool.highlight => AnnotationKind.highlight,
        EditorTool.rect => AnnotationKind.rect,
        EditorTool.ellipse => AnnotationKind.ellipse,
        EditorTool.ink => AnnotationKind.ink,
        EditorTool.arrow => AnnotationKind.arrow,
        EditorTool.measure => AnnotationKind.measure,
        EditorTool.text => AnnotationKind.text,
        EditorTool.note => AnnotationKind.note,
        EditorTool.stamp => AnnotationKind.stamp,
        EditorTool.image => AnnotationKind.image,
      };
}

enum ReadingViewMode {
  continuous('连续', '连续滚动阅读 (Ctrl+1)'),
  single('单页', '单页阅览 (Ctrl+2)'),
  twoPage('双页', '双页对开 (Ctrl+3)');

  const ReadingViewMode(this.label, this.tooltip);
  final String label;
  final String tooltip;
}

enum StampPreset {
  approved('approved', '已批准', 0xFF2F9E44),
  voided('void', '作废', 0xFFE03131),
  reviewing('reviewing', '审核中', 0xFFF08C00),
  pending('pending', '待复核', 0xFF1971C2),
  archived('archived', '已归档', 0xFF7048E8),
  confidential('confidential', '机密', 0xFFC92A2A);

  const StampPreset(this.key, this.label, this.colorValue);
  final String key;
  final String label;
  final int colorValue;

  static StampPreset fromKey(String? key) {
    for (final s in values) {
      if (s.key == key) return s;
    }
    return StampPreset.approved;
  }
}

enum AnnotationKind {
  highlight('highlight', '高亮'),
  rect('rect', '矩形'),
  ellipse('ellipse', '椭圆'),
  ink('ink', '涂鸦'),
  arrow('arrow', '箭头'),
  measure('measure', '测量'),
  text('text', '文字'),
  note('note', '便签'),
  image('image', '图片'),
  stamp('stamp', '图章');

  const AnnotationKind(this.wireName, this.label);
  final String wireName;
  final String label;

  static AnnotationKind? fromWire(String? raw) {
    for (final k in values) {
      if (k.wireName == raw) return k;
    }
    return null;
  }
}

class PdfPoint {
  const PdfPoint(this.x, this.y);
  final double x;
  final double y;

  factory PdfPoint.fromJson(Map<String, dynamic> json) {
    return PdfPoint(
      (json['x'] as num).toDouble(),
      (json['y'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y};

  PdfPoint translate(double dx, double dy) => PdfPoint(x + dx, y + dy);
}

/// PDF 用户空间矩形（单位 pt，原点左下角，Y 向上）
class PdfRectBox {
  const PdfRectBox(this.x, this.y, this.w, this.h);
  final double x;
  final double y;
  final double w;
  final double h;

  double get right => x + w;
  double get top => y + h;

  factory PdfRectBox.fromJson(Map<String, dynamic> json) {
    return PdfRectBox(
      (json['x'] as num).toDouble(),
      (json['y'] as num).toDouble(),
      (json['w'] as num).toDouble(),
      (json['h'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {'x': x, 'y': y, 'w': w, 'h': h};

  PdfRectBox translate(double dx, double dy) =>
      PdfRectBox(x + dx, y + dy, w, h);

  PdfRectBox copyWith({double? x, double? y, double? w, double? h}) =>
      PdfRectBox(x ?? this.x, y ?? this.y, w ?? this.w, h ?? this.h);

  static PdfRectBox fromPoints(Iterable<PdfPoint> pts) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    var any = false;
    for (final p in pts) {
      any = true;
      if (p.x < minX) minX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.x > maxX) maxX = p.x;
      if (p.y > maxY) maxY = p.y;
    }
    if (!any) return const PdfRectBox(0, 0, 0, 0);
    return PdfRectBox(minX, minY, math.max(0, maxX - minX), math.max(0, maxY - minY));
  }
}

class ToolStyleDefaults {
  const ToolStyleDefaults({
    required this.colorHex,
    required this.opacity,
    required this.thickness,
    required this.fontSize,
  });
  final String colorHex;
  final double opacity;
  final double thickness;
  final double fontSize;
}

const List<String> kAnnotationPalette = [
  '#e03131',
  '#f08c00',
  '#2f9e44',
  '#1971c2',
  '#7048e8',
  '#212529',
  '#ffe066',
  '#f7a1c4',
];

const Map<AnnotationKind, ToolStyleDefaults> kToolDefaults = {
  AnnotationKind.highlight: ToolStyleDefaults(colorHex: '#ffe066', opacity: 0.4, thickness: 1, fontSize: 14),
  AnnotationKind.rect: ToolStyleDefaults(colorHex: '#e03131', opacity: 1.0, thickness: 1.5, fontSize: 14),
  AnnotationKind.ellipse: ToolStyleDefaults(colorHex: '#e03131', opacity: 1.0, thickness: 1.5, fontSize: 14),
  AnnotationKind.ink: ToolStyleDefaults(colorHex: '#e03131', opacity: 1.0, thickness: 2.0, fontSize: 14),
  AnnotationKind.arrow: ToolStyleDefaults(colorHex: '#e03131', opacity: 1.0, thickness: 2.0, fontSize: 14),
  AnnotationKind.measure: ToolStyleDefaults(colorHex: '#1971c2', opacity: 1.0, thickness: 1.5, fontSize: 12),
  AnnotationKind.text: ToolStyleDefaults(colorHex: '#212529', opacity: 1.0, thickness: 1, fontSize: 14),
  AnnotationKind.note: ToolStyleDefaults(colorHex: '#f7c948', opacity: 1.0, thickness: 1, fontSize: 12),
  AnnotationKind.stamp: ToolStyleDefaults(colorHex: '#e03131', opacity: 0.95, thickness: 1.5, fontSize: 16),
  AnnotationKind.image: ToolStyleDefaults(colorHex: '#212529', opacity: 1.0, thickness: 1, fontSize: 14),
};

/// 与原 Electron 版 /PdEditorData 与 .pdfanno.json 完全兼容的批注模型
class PdfAnnotationItem {
  const PdfAnnotationItem({
    required this.id,
    required this.kind,
    required this.page,
    required this.bbox,
    required this.color,
    required this.opacity,
    required this.createdAt,
    this.locked = false,
    this.thickness = 1.5,
    this.points = const [],
    this.from,
    this.to,
    this.unit = 'mm',
    this.text = '',
    this.fontSize = 14,
    this.fontFamily,
    this.rotate = 0,
    this.stampKey = 'approved',
    this.label = '已批准',
    this.imgId = '',
    this.refPath = '',
  });

  final String id;
  final AnnotationKind kind;
  final int page; // 0-based
  final PdfRectBox bbox;
  final String color;
  final double opacity;
  final int createdAt;
  final bool locked;
  final double thickness;
  final List<PdfPoint> points;
  final PdfPoint? from;
  final PdfPoint? to;
  final String unit;
  final String text;
  final double fontSize;
  final String? fontFamily;
  final int rotate;
  final String stampKey;
  final String label;
  final String imgId;
  final String refPath;

  PdfRectBox get effectiveBounds {
    if (kind == AnnotationKind.ink && points.isNotEmpty) {
      return PdfRectBox.fromPoints(points);
    }
    if ((kind == AnnotationKind.arrow || kind == AnnotationKind.measure) &&
        from != null &&
        to != null) {
      return PdfRectBox.fromPoints([from!, to!]);
    }
    return bbox;
  }

  String get summary {
    if (kind == AnnotationKind.text || kind == AnnotationKind.note) {
      final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (compact.isEmpty) return '(空)';
      return compact.length > 20 ? '${compact.substring(0, 20)}…' : compact;
    }
    if (kind == AnnotationKind.stamp) return label;
    if (kind == AnnotationKind.measure) return '距离测量';
    return kind.label;
  }

  PdfAnnotationItem copyWith({
    String? id,
    AnnotationKind? kind,
    int? page,
    PdfRectBox? bbox,
    String? color,
    double? opacity,
    int? createdAt,
    bool? locked,
    double? thickness,
    List<PdfPoint>? points,
    PdfPoint? from,
    PdfPoint? to,
    String? unit,
    String? text,
    double? fontSize,
    String? fontFamily,
    bool clearFontFamily = false,
    int? rotate,
    String? stampKey,
    String? label,
    String? imgId,
    String? refPath,
  }) {
    return PdfAnnotationItem(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      page: page ?? this.page,
      bbox: bbox ?? this.bbox,
      color: color ?? this.color,
      opacity: opacity ?? this.opacity,
      createdAt: createdAt ?? this.createdAt,
      locked: locked ?? this.locked,
      thickness: thickness ?? this.thickness,
      points: points ?? this.points,
      from: from ?? this.from,
      to: to ?? this.to,
      unit: unit ?? this.unit,
      text: text ?? this.text,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: clearFontFamily ? null : (fontFamily ?? this.fontFamily),
      rotate: rotate ?? this.rotate,
      stampKey: stampKey ?? this.stampKey,
      label: label ?? this.label,
      imgId: imgId ?? this.imgId,
      refPath: refPath ?? this.refPath,
    );
  }

  PdfAnnotationItem translate(double dx, double dy) {
    return copyWith(
      bbox: bbox.translate(dx, dy),
      points: kind == AnnotationKind.ink
          ? points.map((p) => p.translate(dx, dy)).toList()
          : null,
      from: from?.translate(dx, dy),
      to: to?.translate(dx, dy),
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'id': id,
      'kind': kind.wireName,
      'page': page,
      'bbox': bbox.toJson(),
      'color': color,
      'opacity': opacity,
      'createdAt': createdAt,
    };
    if (locked) map['locked'] = true;
    switch (kind) {
      case AnnotationKind.highlight:
        break;
      case AnnotationKind.rect:
      case AnnotationKind.ellipse:
        map['thickness'] = thickness;
        break;
      case AnnotationKind.ink:
        map['points'] = points.map((p) => p.toJson()).toList();
        map['thickness'] = thickness;
        break;
      case AnnotationKind.arrow:
        map['from'] = (from ?? const PdfPoint(0, 0)).toJson();
        map['to'] = (to ?? const PdfPoint(0, 0)).toJson();
        map['thickness'] = thickness;
        break;
      case AnnotationKind.measure:
        map['from'] = (from ?? const PdfPoint(0, 0)).toJson();
        map['to'] = (to ?? const PdfPoint(0, 0)).toJson();
        map['thickness'] = thickness;
        map['unit'] = unit;
        break;
      case AnnotationKind.text:
        map['text'] = text;
        map['fontSize'] = fontSize;
        if (fontFamily != null && fontFamily!.isNotEmpty) {
          map['fontFamily'] = fontFamily;
        }
        map['rotate'] = rotate;
        break;
      case AnnotationKind.note:
        map['text'] = text;
        break;
      case AnnotationKind.image:
        map['imgId'] = imgId;
        map['refPath'] = refPath;
        map['rotate'] = rotate;
        break;
      case AnnotationKind.stamp:
        map['stampKey'] = stampKey;
        map['label'] = label;
        map['fontSize'] = fontSize;
        if (fontFamily != null && fontFamily!.isNotEmpty) {
          map['fontFamily'] = fontFamily;
        }
        map['rotate'] = rotate;
        break;
    }
    return map;
  }

  static PdfAnnotationItem? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final json = Map<String, dynamic>.from(raw);
    final id = json['id'];
    final kind = AnnotationKind.fromWire(json['kind'] as String?);
    final page = json['page'];
    final bboxRaw = json['bbox'];
    if (id is! String ||
        id.isEmpty ||
        id.length > 128 ||
        kind == null ||
        page is! num ||
        bboxRaw is! Map) {
      return null;
    }
    final bboxMap = Map<String, dynamic>.from(bboxRaw);
    for (final k in ['x', 'y', 'w', 'h']) {
      final v = bboxMap[k];
      if (v is! num || !v.isFinite) return null;
    }
    final bbox = PdfRectBox.fromJson(bboxMap);
    final color = json['color'] is String ? json['color'] as String : '#e03131';
    final opacity =
        json['opacity'] is num && (json['opacity'] as num).isFinite
            ? (json['opacity'] as num).toDouble().clamp(0.05, 1.0)
            : 1.0;
    final createdAt = json['createdAt'] is num ? (json['createdAt'] as num).toInt() : 0;
    final locked = json['locked'] == true;
    final thickness =
        json['thickness'] is num && (json['thickness'] as num).isFinite
            ? (json['thickness'] as num).toDouble().clamp(0.5, 24.0)
            : 1.5;

    final points = <PdfPoint>[];
    if (json['points'] is List) {
      for (final p in json['points'] as List) {
        if (p is Map &&
            p['x'] is num &&
            p['y'] is num &&
            (p['x'] as num).isFinite &&
            (p['y'] as num).isFinite) {
          points.add(PdfPoint((p['x'] as num).toDouble(), (p['y'] as num).toDouble()));
        }
      }
    }

    PdfPoint? parsePt(Object? rawPt) {
      if (rawPt is Map &&
          rawPt['x'] is num &&
          rawPt['y'] is num &&
          (rawPt['x'] as num).isFinite &&
          (rawPt['y'] as num).isFinite) {
        return PdfPoint((rawPt['x'] as num).toDouble(), (rawPt['y'] as num).toDouble());
      }
      return null;
    }

    final text = json['text'] is String ? json['text'] as String : '';
    if (text.length > 100000) return null;
    final label = json['label'] is String ? json['label'] as String : '已批准';
    final fontSize =
        json['fontSize'] is num && (json['fontSize'] as num).isFinite
            ? (json['fontSize'] as num).toDouble().clamp(6.0, 144.0)
            : 14.0;
    final fontFamily = json['fontFamily'] is String ? json['fontFamily'] as String : null;
    final rotate = json['rotate'] is num ? (json['rotate'] as num).toInt() : 0;
    final stampKey = json['stampKey'] is String ? json['stampKey'] as String : 'approved';
    final imgId = json['imgId'] is String ? json['imgId'] as String : '';
    final refPath = json['refPath'] is String ? json['refPath'] as String : '';
    final unit = json['unit'] is String ? json['unit'] as String : 'mm';

    return PdfAnnotationItem(
      id: id,
      kind: kind,
      page: page.toInt(),
      bbox: bbox,
      color: color,
      opacity: opacity,
      createdAt: createdAt,
      locked: locked,
      thickness: thickness,
      points: points,
      from: parsePt(json['from']),
      to: parsePt(json['to']),
      unit: unit,
      text: text,
      fontSize: fontSize,
      fontFamily: fontFamily,
      rotate: rotate,
      stampKey: stampKey,
      label: label,
      imgId: imgId,
      refPath: refPath,
    );
  }
}
