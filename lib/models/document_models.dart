class SystemFontInfo {
  const SystemFontInfo({
    required this.family,
    required this.label,
    required this.style,
    required this.filePath,
    required this.faceIndex,
    required this.aliases,
  });

  final String family;
  final String label;
  final String style;
  final String filePath;
  final int faceIndex;
  final List<String> aliases;
}

class ProblemEntry {
  const ProblemEntry({
    required this.id,
    required this.timestamp,
    required this.source,
    required this.message,
    this.detail,
  });

  final String id;
  final DateTime timestamp;
  final String source;
  final String message;
  final String? detail;
}

class RecentDocumentEntry {
  const RecentDocumentEntry({
    required this.path,
    required this.page,
    required this.updatedAt,
  });

  final String path;
  final int page;
  final int updatedAt;

  factory RecentDocumentEntry.fromJson(Map<String, dynamic> json) {
    return RecentDocumentEntry(
      path: json['path'] as String? ?? '',
      page: (json['page'] as num?)?.toInt() ?? 1,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'page': page,
        'updatedAt': updatedAt,
      };
}

enum PageNumberFormat {
  numberOnly('1'),
  zhPage('第 1 页'),
  zhPageTotal('第 1 页 / 共 N 页'),
  slashTotal('1 / N');

  const PageNumberFormat(this.label);
  final String label;

  String format(int page, int total) {
    switch (this) {
      case PageNumberFormat.numberOnly:
        return '$page';
      case PageNumberFormat.zhPage:
        return '第 $page 页';
      case PageNumberFormat.zhPageTotal:
        return '第 $page 页 / 共 $total 页';
      case PageNumberFormat.slashTotal:
        return '$page / $total';
    }
  }

  bool get needsCjk => this == PageNumberFormat.zhPage || this == PageNumberFormat.zhPageTotal;
}

enum PageNumberPosition {
  bottomCenter('页脚居中'),
  bottomRight('页脚右侧'),
  topCenter('页眉居中'),
  topRight('页眉右侧');

  const PageNumberPosition(this.label);
  final String label;
}

enum PageOrientationKind { portrait, landscape, square }

enum OrientationReason {
  textSideways('内容横躺'),
  textInverted('内容倒置'),
  pageOnly('页面方向不同，内容与页面一致'),
  contentUnknown('无法判定内容方向'),
  ocr('按 OCR 识别的内容方向');

  const OrientationReason(this.label);
  final String label;
}

class OrientationPlanItem {
  OrientationPlanItem({
    required this.page,
    required this.from,
    required this.to,
    required this.delta,
    required this.reason,
    bool? selected,
  }) : selected = selected ?? (delta != 0);

  final int page; // 1-based
  final PageOrientationKind from;
  final PageOrientationKind to;
  int delta; // 0, 90, 180, 270
  final OrientationReason reason;
  bool selected;
}

class OrientationPlanResult {
  const OrientationPlanResult({
    this.base,
    this.baseError = '',
    this.items = const [],
  });

  final PageOrientationKind? base;
  final String baseError;
  final List<OrientationPlanItem> items;
}

enum PrintQuality {
  standard('标准 (150 dpi)', 150),
  high('高清 (300 dpi)', 300);

  const PrintQuality(this.label, this.dpi);
  final String label;
  final int dpi;
}
