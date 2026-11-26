import 'package:flutter/material.dart';

class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.shellBg,
    required this.surfaceBg,
    required this.canvasBg,
    required this.elevatedBg,
    required this.border,
    required this.mutedText,
    required this.subtleFill,
    required this.hoverFill,
    required this.hoverBorder,
    required this.accent,
    required this.accentSoft,
  });

  final Color shellBg;
  final Color surfaceBg;
  final Color canvasBg;
  final Color elevatedBg;
  final Color border;
  final Color mutedText;
  final Color subtleFill;
  final Color hoverFill;
  final Color hoverBorder;
  final Color accent;
  final Color accentSoft;

  @override
  AppColors copyWith({
    Color? shellBg,
    Color? surfaceBg,
    Color? canvasBg,
    Color? elevatedBg,
    Color? border,
    Color? mutedText,
    Color? subtleFill,
    Color? hoverFill,
    Color? hoverBorder,
    Color? accent,
    Color? accentSoft,
  }) {
    return AppColors(
      shellBg: shellBg ?? this.shellBg,
      surfaceBg: surfaceBg ?? this.surfaceBg,
      canvasBg: canvasBg ?? this.canvasBg,
      elevatedBg: elevatedBg ?? this.elevatedBg,
      border: border ?? this.border,
      mutedText: mutedText ?? this.mutedText,
      subtleFill: subtleFill ?? this.subtleFill,
      hoverFill: hoverFill ?? this.hoverFill,
      hoverBorder: hoverBorder ?? this.hoverBorder,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      shellBg: Color.lerp(shellBg, other.shellBg, t)!,
      surfaceBg: Color.lerp(surfaceBg, other.surfaceBg, t)!,
      canvasBg: Color.lerp(canvasBg, other.canvasBg, t)!,
      elevatedBg: Color.lerp(elevatedBg, other.elevatedBg, t)!,
      border: Color.lerp(border, other.border, t)!,
      mutedText: Color.lerp(mutedText, other.mutedText, t)!,
      subtleFill: Color.lerp(subtleFill, other.subtleFill, t)!,
      hoverFill: Color.lerp(hoverFill, other.hoverFill, t)!,
      hoverBorder: Color.lerp(hoverBorder, other.hoverBorder, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentSoft: Color.lerp(accentSoft, other.accentSoft, t)!,
    );
  }

  static const light = AppColors(
    shellBg: Color(0xFFF3F5F8),
    surfaceBg: Color(0xFFFFFFFF),
    canvasBg: Color(0xFFE5E9F0),
    elevatedBg: Color(0xFFFCFDFF),
    border: Color(0xFFDDE2EB),
    mutedText: Color(0xFF526075),
    subtleFill: Color(0xFFF1F5F9),
    hoverFill: Color(0xFFE7EFFD),
    hoverBorder: Color(0xFF93C5FD),
    accent: Color(0xFF2563EB),
    accentSoft: Color(0xFFE0ECFF),
  );

  static const dark = AppColors(
    shellBg: Color(0xFF151820),
    surfaceBg: Color(0xFF1C202B),
    canvasBg: Color(0xFF111319),
    elevatedBg: Color(0xFF242937),
    border: Color(0xFF2D3344),
    mutedText: Color(0xFF94A3B8),
    subtleFill: Color(0xFF262B38),
    hoverFill: Color(0xFF2A364F),
    hoverBorder: Color(0xFF60A5FA),
    accent: Color(0xFF60A5FA),
    accentSoft: Color(0xFF1E3A5F),
  );
}

class AppTypography {
  AppTypography._();

  static const double display = 20;
  static const double title = 16;
  static const double body = 14;
  static const double caption = 12;

  static const List<double> allowedSizes = [caption, body, title, display];

  static TextStyle _withSize(TextStyle? style, double size,
      {FontWeight? weight}) {
    return (style ?? const TextStyle()).copyWith(
      fontSize: size,
      fontWeight: weight ?? style?.fontWeight,
    );
  }

  static TextTheme unifyTextTheme(TextTheme base) {
    return TextTheme(
      displayLarge: _withSize(base.displayLarge, display, weight: FontWeight.w700),
      displayMedium:
          _withSize(base.displayMedium, display, weight: FontWeight.w700),
      displaySmall: _withSize(base.displaySmall, display, weight: FontWeight.w600),
      headlineLarge:
          _withSize(base.headlineLarge, display, weight: FontWeight.w700),
      headlineMedium:
          _withSize(base.headlineMedium, title, weight: FontWeight.w700),
      headlineSmall:
          _withSize(base.headlineSmall, title, weight: FontWeight.w600),
      titleLarge: _withSize(base.titleLarge, title, weight: FontWeight.w600),
      titleMedium: _withSize(base.titleMedium, body, weight: FontWeight.w600),
      titleSmall: _withSize(base.titleSmall, body, weight: FontWeight.w500),
      bodyLarge: _withSize(base.bodyLarge, body),
      bodyMedium: _withSize(base.bodyMedium, body),
      bodySmall: _withSize(base.bodySmall, caption),
      labelLarge: _withSize(base.labelLarge, body),
      labelMedium: _withSize(base.labelMedium, caption),
      labelSmall: _withSize(base.labelSmall, caption),
    );
  }
}

/// 桌面端高精度圆形滑块 Thumb（白底/浮起底 + 主题色描边 + 轻阴影，替换默认 Android M3 大圆球）
class _DesktopSliderThumbShape extends SliderComponentShape {
  const _DesktopSliderThumbShape({
    required this.fillColor,
    required this.borderColor,
    required this.disabledBorderColor,
    required this.shadowColor,
  });

  static const double _radius = 6.5;

  final Color fillColor;
  final Color borderColor;
  final Color disabledBorderColor;
  final Color shadowColor;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size.fromRadius(_radius);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;
    final r = _radius + activationAnimation.value * 1.0;

    final shadowPath = Path()
      ..addOval(Rect.fromCircle(center: center + const Offset(0, 1), radius: r));
    canvas.drawShadow(shadowPath, shadowColor, 2.5, true);

    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = fillColor
        ..style = PaintingStyle.fill,
    );

    final stroke = Color.lerp(
      disabledBorderColor,
      borderColor,
      enableAnimation.value,
    )!;
    canvas.drawCircle(
      center,
      r - 0.85,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }
}

class AppTheme {
  AppTheme._();

  static const Color danger = Color(0xFFDC2626);
  static const Color warning = Color(0xFFD97706);

  static ThemeData build(bool dark) {
    final ext = dark ? AppColors.dark : AppColors.light;
    final brightness = dark ? Brightness.dark : Brightness.light;
    final onSurface = dark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
    final onPrimary = dark ? const Color(0xFF0B1220) : Colors.white;
    final accentHover = dark ? const Color(0xFF7BB8FC) : const Color(0xFF1D4ED8);
    final accentPressed =
        dark ? const Color(0xFF3B82F6) : const Color(0xFF1E40AF);

    final colorScheme = ColorScheme.fromSeed(
      seedColor: ext.accent,
      brightness: brightness,
    ).copyWith(
      primary: ext.accent,
      onPrimary: onPrimary,
      primaryContainer: ext.accentSoft,
      onPrimaryContainer: ext.accent,
      secondary: ext.accent,
      onSecondary: onPrimary,
      secondaryContainer: ext.accentSoft,
      onSecondaryContainer: ext.accent,
      surface: ext.surfaceBg,
      onSurface: onSurface,
      onSurfaceVariant: ext.mutedText,
      surfaceContainerLowest: ext.surfaceBg,
      surfaceContainerLow: ext.shellBg,
      surfaceContainer: ext.subtleFill,
      surfaceContainerHigh: ext.elevatedBg,
      surfaceContainerHighest: ext.subtleFill,
      outline: ext.border,
      outlineVariant: ext.border,
      error: danger,
      onError: Colors.white,
      shadow: Colors.black,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Microsoft YaHei UI',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: ext.shellBg,
      canvasColor: ext.elevatedBg,
      cardColor: ext.surfaceBg,
      dividerColor: ext.border,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 350),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        textStyle: TextStyle(
          fontSize: AppTypography.caption,
          fontWeight: FontWeight.w500,
          color: dark ? const Color(0xFFF8FAFC) : Colors.white,
        ),
        decoration: BoxDecoration(
          color: dark ? const Color(0xF52A3142) : const Color(0xF21E293B),
          borderRadius: BorderRadius.circular(7),
          border: Border.all(
            color: dark
                ? ext.border.withValues(alpha: 0.9)
                : Colors.white.withValues(alpha: 0.12),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.42 : 0.18),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
      ),
    );
    final unifiedTextTheme = AppTypography.unifyTextTheme(base.textTheme);
    final unifiedPrimaryTextTheme =
        AppTypography.unifyTextTheme(base.primaryTextTheme);

    return base.copyWith(
      textTheme: unifiedTextTheme,
      primaryTextTheme: unifiedPrimaryTextTheme,
      extensions: [ext],
      hoverColor: ext.hoverFill.withValues(alpha: 0.85),
      highlightColor: ext.accentSoft.withValues(alpha: 0.5),
      focusColor: ext.accent.withValues(alpha: 0.16),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: ext.accent,
        selectionColor: ext.accent.withValues(alpha: dark ? 0.34 : 0.2),
        selectionHandleColor: ext.accent,
      ),
      dividerTheme: DividerThemeData(
        color: ext.border,
        thickness: 1,
        space: 1,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          splashFactory: NoSplash.splashFactory,
          padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return ext.mutedText.withValues(alpha: 0.38);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed)) {
              return ext.accent;
            }
            return ext.mutedText;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return Colors.transparent;
            }
            if (states.contains(WidgetState.pressed)) {
              return ext.accentSoft;
            }
            if (states.contains(WidgetState.hovered)) {
              return ext.hoverFill;
            }
            return Colors.transparent;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return BorderSide.none;
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed)) {
              return BorderSide(color: ext.hoverBorder.withValues(alpha: 0.75));
            }
            return BorderSide.none;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          splashFactory: NoSplash.splashFactory,
          elevation: const WidgetStatePropertyAll(0),
          minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontSize: AppTypography.body,
              fontWeight: FontWeight.w500,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return ext.subtleFill.withValues(alpha: 0.5);
            }
            if (states.contains(WidgetState.pressed)) {
              return ext.accentSoft;
            }
            if (states.contains(WidgetState.hovered)) {
              return ext.hoverFill;
            }
            return ext.surfaceBg;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return ext.mutedText.withValues(alpha: 0.45);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed)) {
              return ext.accent;
            }
            return onSurface;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return BorderSide(color: ext.border.withValues(alpha: 0.55));
            }
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: ext.accent, width: 1.5);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed)) {
              return BorderSide(color: ext.hoverBorder);
            }
            return BorderSide(color: ext.border);
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          splashFactory: NoSplash.splashFactory,
          elevation: const WidgetStatePropertyAll(0),
          minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontSize: AppTypography.body,
              fontWeight: FontWeight.w600,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return ext.subtleFill;
            }
            if (states.contains(WidgetState.pressed)) {
              return accentPressed;
            }
            if (states.contains(WidgetState.hovered)) {
              return accentHover;
            }
            return ext.accent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return ext.mutedText.withValues(alpha: 0.55);
            }
            return onPrimary;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          splashFactory: NoSplash.splashFactory,
          minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontSize: AppTypography.body,
              fontWeight: FontWeight.w500,
            ),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return ext.mutedText.withValues(alpha: 0.42);
            }
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.pressed)) {
              return ext.accent;
            }
            return ext.mutedText;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return Colors.transparent;
            }
            if (states.contains(WidgetState.pressed)) {
              return ext.accentSoft;
            }
            if (states.contains(WidgetState.hovered)) {
              return ext.hoverFill;
            }
            return Colors.transparent;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 4,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        activeTrackColor: ext.accent,
        inactiveTrackColor: ext.border,
        disabledActiveTrackColor: ext.mutedText.withValues(alpha: 0.35),
        disabledInactiveTrackColor: ext.border.withValues(alpha: 0.5),
        thumbColor: ext.surfaceBg,
        overlayColor: ext.accent.withValues(alpha: 0.14),
        thumbShape: _DesktopSliderThumbShape(
          fillColor: dark ? ext.elevatedBg : Colors.white,
          borderColor: ext.accent,
          disabledBorderColor: ext.mutedText.withValues(alpha: 0.4),
          shadowColor: Colors.black.withValues(alpha: dark ? 0.55 : 0.25),
        ),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 13),
        trackShape: const RoundedRectSliderTrackShape(),
        tickMarkShape: SliderTickMarkShape.noTickMark,
        valueIndicatorColor: dark ? ext.elevatedBg : const Color(0xFF1E293B),
        valueIndicatorTextStyle: const TextStyle(
          fontSize: AppTypography.caption,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      checkboxTheme: CheckboxThemeData(
        splashRadius: 14,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4.5),
        ),
        side: WidgetStateBorderSide.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return BorderSide(
              color: ext.border.withValues(alpha: 0.7),
              width: 1.4,
            );
          }
          if (states.contains(WidgetState.selected)) {
            return BorderSide(color: ext.accent, width: 1.5);
          }
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return BorderSide(color: ext.accent, width: 1.5);
          }
          return BorderSide(
            color: dark ? const Color(0xFF475569) : const Color(0xFF94A3B8),
            width: 1.4,
          );
        }),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            if (states.contains(WidgetState.disabled)) {
              return ext.accent.withValues(alpha: 0.42);
            }
            return ext.accent;
          }
          if (states.contains(WidgetState.hovered)) {
            return ext.hoverFill;
          }
          return ext.surfaceBg;
        }),
        checkColor: WidgetStatePropertyAll(onPrimary),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered)) {
            return ext.hoverFill.withValues(alpha: 0.7);
          }
          return Colors.transparent;
        }),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          splashFactory: NoSplash.splashFactory,
          visualDensity: VisualDensity.compact,
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          side: WidgetStatePropertyAll(BorderSide(color: ext.border)),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return ext.accentSoft;
            }
            if (states.contains(WidgetState.hovered)) {
              return ext.hoverFill;
            }
            return ext.subtleFill;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return ext.accent;
            }
            return onSurface;
          }),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: ext.subtleFill,
        selectedColor: ext.accentSoft,
        disabledColor: ext.subtleFill.withValues(alpha: 0.5),
        showCheckmark: false,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(7),
          side: BorderSide(color: ext.border),
        ),
        side: WidgetStateBorderSide.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return BorderSide(color: ext.accent.withValues(alpha: 0.5));
          }
          if (states.contains(WidgetState.hovered)) {
            return BorderSide(color: ext.hoverBorder);
          }
          return BorderSide(color: ext.border);
        }),
        labelStyle: TextStyle(
          fontSize: AppTypography.body,
          color: onSurface,
        ),
        secondaryLabelStyle: TextStyle(
          fontSize: AppTypography.body,
          fontWeight: FontWeight.w600,
          color: ext.accent,
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: ext.accent,
        linearTrackColor: ext.accentSoft,
        circularTrackColor: ext.accentSoft.withValues(alpha: 0.45),
        linearMinHeight: 5,
        borderRadius: BorderRadius.circular(999),
        strokeCap: StrokeCap.round,
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(999),
        thickness: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged)) {
            return 7.0;
          }
          return 5.0;
        }),
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.dragged)) {
            return ext.accent.withValues(alpha: dark ? 0.78 : 0.72);
          }
          if (states.contains(WidgetState.hovered)) {
            return ext.mutedText.withValues(alpha: dark ? 0.62 : 0.52);
          }
          return ext.mutedText.withValues(alpha: dark ? 0.34 : 0.28);
        }),
        trackColor: const WidgetStatePropertyAll(Colors.transparent),
        trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
        crossAxisMargin: 2,
        mainAxisMargin: 4,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: ext.surfaceBg,
        surfaceTintColor: Colors.transparent,
        elevation: 18,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.58 : 0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: ext.border),
        ),
        titleTextStyle: TextStyle(
          fontSize: AppTypography.title,
          fontWeight: FontWeight.w700,
          color: onSurface,
        ),
        contentTextStyle: TextStyle(
          fontSize: AppTypography.body,
          height: 1.5,
          color: onSurface.withValues(alpha: 0.86),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: ext.elevatedBg,
        surfaceTintColor: Colors.transparent,
        elevation: 10,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.52 : 0.16),
        menuPadding: const EdgeInsets.symmetric(vertical: 5),
        enableFeedback: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: ext.border),
        ),
        textStyle: TextStyle(
          fontSize: AppTypography.body,
          color: onSurface,
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) {
            return TextStyle(
              fontSize: AppTypography.body,
              color: ext.mutedText.withValues(alpha: 0.45),
            );
          }
          return TextStyle(
            fontSize: AppTypography.body,
            color: onSurface,
          );
        }),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(ext.elevatedBg),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(10),
          shadowColor: WidgetStatePropertyAll(
            Colors.black.withValues(alpha: dark ? 0.52 : 0.16),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: ext.border),
            ),
          ),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 5),
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        selectedTileColor: ext.accentSoft.withValues(alpha: 0.65),
        selectedColor: ext.accent,
        iconColor: ext.mutedText,
        titleTextStyle: TextStyle(
          fontSize: AppTypography.body,
          color: onSurface,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: AppTypography.caption,
          color: ext.mutedText,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        visualDensity: VisualDensity.standard,
        filled: true,
        fillColor: ext.subtleFill.withValues(alpha: dark ? 0.68 : 0.72),
        hoverColor: ext.hoverFill.withValues(alpha: dark ? 0.35 : 0.5),
        labelStyle: TextStyle(
          fontSize: AppTypography.body,
          color: ext.mutedText,
        ),
        floatingLabelStyle: TextStyle(
          fontSize: AppTypography.body,
          fontWeight: FontWeight.w500,
          color: ext.accent,
        ),
        hintStyle: TextStyle(fontSize: AppTypography.body, color: ext.mutedText),
        helperStyle: TextStyle(
          fontSize: AppTypography.caption,
          color: ext.mutedText,
        ),
        errorStyle: const TextStyle(
          fontSize: AppTypography.caption,
          color: danger,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: ext.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: ext.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: ext.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: danger, width: 1.5),
        ),
        contentPadding: const EdgeInsets.fromLTRB(12, 20, 12, 12),
      ),
    );
  }

  /// Compact filled decoration for fields without a floating border label.
  static InputDecoration compactInputDecoration(
    AppColors colors, {
    String? hintText,
    String? errorText,
    Widget? suffixIcon,
    bool isDense = true,
    EdgeInsetsGeometry contentPadding =
        const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
  }) {
    return InputDecoration(
      isDense: isDense,
      filled: true,
      fillColor: colors.subtleFill,
      hintText: hintText,
      errorText: errorText,
      suffixIcon: suffixIcon,
      contentPadding: contentPadding,
    );
  }

  /// Secondary tonal-accent button style for desktop dialogs (e.g. "添加文件").
  static ButtonStyle tonalActionButtonStyle(AppColors colors) {
    return ButtonStyle(
      splashFactory: NoSplash.splashFactory,
      elevation: const WidgetStatePropertyAll(0),
      minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 13, vertical: 8),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: AppTypography.body, fontWeight: FontWeight.w600),
      ),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colors.subtleFill;
        }
        if (states.contains(WidgetState.pressed)) {
          return colors.accent.withValues(alpha: 0.22);
        }
        if (states.contains(WidgetState.hovered)) {
          return colors.hoverFill;
        }
        return colors.accentSoft;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return colors.mutedText.withValues(alpha: 0.45);
        }
        return colors.accent;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return BorderSide(color: colors.border.withValues(alpha: 0.5));
        }
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed)) {
          return BorderSide(color: colors.accent.withValues(alpha: 0.65));
        }
        return BorderSide(color: colors.accent.withValues(alpha: 0.28));
      }),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    );
  }

  /// Destructive outlined button style (red tint on hover).
  static ButtonStyle dangerOutlinedButtonStyle(AppColors colors) {
    return ButtonStyle(
      splashFactory: NoSplash.splashFactory,
      elevation: const WidgetStatePropertyAll(0),
      minimumSize: const WidgetStatePropertyAll(Size(0, 36)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(fontSize: AppTypography.body, fontWeight: FontWeight.w500),
      ),
      foregroundColor: const WidgetStatePropertyAll(danger),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.pressed)) {
          return danger.withValues(alpha: 0.14);
        }
        if (states.contains(WidgetState.hovered)) {
          return danger.withValues(alpha: 0.08);
        }
        return colors.surfaceBg;
      }),
      side: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered) ||
            states.contains(WidgetState.pressed)) {
          return BorderSide(color: danger.withValues(alpha: 0.72));
        }
        return BorderSide(color: danger.withValues(alpha: 0.36));
      }),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    );
  }
}

extension AppColorsBuildContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
