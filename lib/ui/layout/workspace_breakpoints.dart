import 'package:flutter/widgets.dart';

enum PanelPresentation { docked, overlay }

enum TopBarDensity { full, compact, ultraCompact }

/// 桌面工作区响应式布局断点规格（以画布优先为原则）
///
/// - `>= 1440`: 左缩略图 + 右检查器双栏停靠
/// - `1200..1439`: 仅左侧缩略图停靠，右侧改为按需覆盖抽屉
/// - `1024..1199`: 双侧栏默认收起，均以覆盖抽屉打开；顶栏进入紧凑模式
/// - `< 1024`: 双侧栏覆盖抽屉；顶栏进入极简模式
class WorkspaceLayoutSpec {
  const WorkspaceLayoutSpec({
    required this.width,
    required this.height,
    required this.leftMode,
    required this.rightMode,
    required this.defaultLeftOpen,
    required this.defaultRightOpen,
    required this.topBarDensity,
    required this.compactStatusBar,
    required this.compactThumbnails,
  });

  final double width;
  final double height;
  final PanelPresentation leftMode;
  final PanelPresentation rightMode;
  final bool defaultLeftOpen;
  final bool defaultRightOpen;
  final TopBarDensity topBarDensity;
  final bool compactStatusBar;
  final bool compactThumbnails;

  static const double wideBreakpoint = 1440;
  static const double standardBreakpoint = 1200;
  static const double narrowBreakpoint = 1024;
  static const double compactHeightBreakpoint = 700;

  static const double dockedLeftWidth = 256;
  static const double overlayLeftWidth = 280;
  static const double dockedRightWidth = 292;
  static const double overlayRightWidth = 320;

  bool get leftIsOverlay => leftMode == PanelPresentation.overlay;
  bool get rightIsOverlay => rightMode == PanelPresentation.overlay;

  static WorkspaceLayoutSpec fromSize(Size size) {
    final w = size.width;
    final h = size.height;
    final compactH = h < compactHeightBreakpoint;
    if (w >= wideBreakpoint) {
      return WorkspaceLayoutSpec(
        width: w,
        height: h,
        leftMode: PanelPresentation.docked,
        rightMode: PanelPresentation.docked,
        defaultLeftOpen: true,
        defaultRightOpen: true,
        topBarDensity: TopBarDensity.full,
        compactStatusBar: false,
        compactThumbnails: compactH,
      );
    }
    if (w >= standardBreakpoint) {
      return WorkspaceLayoutSpec(
        width: w,
        height: h,
        leftMode: PanelPresentation.docked,
        rightMode: PanelPresentation.overlay,
        defaultLeftOpen: true,
        defaultRightOpen: false,
        topBarDensity: TopBarDensity.full,
        compactStatusBar: false,
        compactThumbnails: compactH,
      );
    }
    return WorkspaceLayoutSpec(
      width: w,
      height: h,
      leftMode: PanelPresentation.overlay,
      rightMode: PanelPresentation.overlay,
      defaultLeftOpen: false,
      defaultRightOpen: false,
      topBarDensity: w >= narrowBreakpoint
          ? TopBarDensity.compact
          : TopBarDensity.ultraCompact,
      compactStatusBar: true,
      compactThumbnails: compactH,
    );
  }
}
