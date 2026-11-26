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

  static TextStyle _withSize(TextStyle? style, double size, {FontWeight? weight}) {
    return (style ?? const TextStyle()).copyWith(
      fontSize: size,
      fontWeight: weight ?? style?.fontWeight,
    );
  }

  static TextTheme unifyTextTheme(TextTheme base) {
    return TextTheme(
      displayLarge: _withSize(base.displayLarge, display, weight: FontWeight.w700),
      displayMedium: _withSize(base.displayMedium, display, weight: FontWeight.w700),
      displaySmall: _withSize(base.displaySmall, display, weight: FontWeight.w600),
      headlineLarge: _withSize(base.headlineLarge, display, weight: FontWeight.w700),
      headlineMedium: _withSize(base.headlineMedium, title, weight: FontWeight.w700),
      headlineSmall: _withSize(base.headlineSmall, title, weight: FontWeight.w600),
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

class AppTheme {
  AppTheme._();

  static ThemeData build(bool dark) {
    final ext = dark ? AppColors.dark : AppColors.light;
    final brightness = dark ? Brightness.dark : Brightness.light;
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Microsoft YaHei UI',
      colorScheme: ColorScheme.fromSeed(
        seedColor: ext.accent,
        brightness: brightness,
      ),
      scaffoldBackgroundColor: ext.shellBg,
      dividerColor: ext.border,
      tooltipTheme: TooltipThemeData(
        waitDuration: const Duration(milliseconds: 350),
        textStyle: const TextStyle(
          fontSize: AppTypography.body,
          color: Colors.white,
        ),
        decoration: BoxDecoration(
          color: const Color(0xEE1E293B),
          borderRadius: BorderRadius.circular(6),
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
      highlightColor: ext.accentSoft.withValues(alpha: 0.6),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          ),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return ext.accentSoft.withValues(alpha: 0.85);
            }
            if (states.contains(WidgetState.hovered)) {
              return ext.hoverFill;
            }
            return null;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered)) {
              return BorderSide(color: ext.hoverBorder);
            }
            return BorderSide(color: ext.border);
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return ext.accentSoft.withValues(alpha: 0.85);
            }
            if (states.contains(WidgetState.hovered)) {
              return ext.hoverFill;
            }
            return null;
          }),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return ext.accentSoft.withValues(alpha: 0.85);
            }
            if (states.contains(WidgetState.hovered)) {
              return ext.hoverFill;
            }
            return null;
          }),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: ext.surfaceBg,
        surfaceTintColor: Colors.transparent,
        elevation: 16,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.55 : 0.18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: ext.border),
        ),
        titleTextStyle: TextStyle(
          fontSize: AppTypography.title,
          fontWeight: FontWeight.w700,
          color: base.colorScheme.onSurface,
        ),
        contentTextStyle: TextStyle(
          fontSize: AppTypography.body,
          height: 1.5,
          color: base.colorScheme.onSurface.withValues(alpha: 0.86),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
      ),
      popupMenuTheme: PopupMenuThemeData(
        textStyle: TextStyle(
          fontSize: AppTypography.body,
          color: base.colorScheme.onSurface,
        ),
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontSize: AppTypography.body,
            color: base.colorScheme.onSurface,
          ),
        ),
      ),
      listTileTheme: ListTileThemeData(
        titleTextStyle: TextStyle(
          fontSize: AppTypography.body,
          color: base.colorScheme.onSurface,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: AppTypography.caption,
          color: ext.mutedText,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: false,
        labelStyle: const TextStyle(fontSize: AppTypography.body),
        floatingLabelStyle: const TextStyle(fontSize: AppTypography.body),
        hintStyle: TextStyle(fontSize: AppTypography.body, color: ext.mutedText),
        helperStyle: const TextStyle(fontSize: AppTypography.caption),
        errorStyle: const TextStyle(fontSize: AppTypography.caption),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: ext.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: ext.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: ext.accent, width: 1.5),
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
}

extension AppColorsBuildContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}
