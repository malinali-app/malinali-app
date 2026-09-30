import 'package:flutter/material.dart';

/// Brand chrome: navy field, yellow accents (shared across all screens).
abstract final class MalinaliChrome {
  static const blueBg = Color.fromARGB(255, 2, 21, 72);

  /// Darker panel fill for cards / source / target zones.
  static const bluePanel = Color(0xFF0B1F4A);
  static const blueAction = Color(0xFF2563EB);

  /// Lighter blue chip behind the source → target pair.
  static const blueChip = Color(0xFF3B82F6);
  static const yellowBorder = Color(0xFFFACC15);
  static const whiteBorder = Color(0xFFF8FAFC);
  static const redAccent = Color(0xFFDC2626);
  static const onBlue = Color(0xFFF8FAFC);

  /// Source text: very light white on dark blue.
  static const sourceText = Color(0xFFF8FAFC);

  /// Target text: very light yellow on dark blue.
  static const targetText = Color(0xFFFEF08A);

  /// Secondary / muted label on navy.
  static const mutedOnBlue = Color(0xFF94A3B8);

  /// Success accent readable on navy.
  static const success = Color(0xFF4ADE80);

  /// Soft green panel for custom / BYO rows.
  static const customPanel = Color(0xFF0F2E22);

  static ThemeData theme() {
    final scheme = ColorScheme.dark(
      primary: blueAction,
      onPrimary: Colors.white,
      secondary: yellowBorder,
      onSecondary: blueBg,
      surface: blueBg,
      onSurface: onBlue,
      error: redAccent,
      onError: Colors.white,
      surfaceContainerHighest: bluePanel,
      outline: whiteBorder.withValues(alpha: 0.28),
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'NotoSans',
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: blueBg,
      appBarTheme: const AppBarTheme(
        backgroundColor: blueBg,
        foregroundColor: onBlue,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: onBlue),
        actionsIconTheme: IconThemeData(color: onBlue),
        titleTextStyle: TextStyle(
          fontFamily: 'NotoSans',
          color: onBlue,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: bluePanel,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: whiteBorder.withValues(alpha: 0.15)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        textColor: onBlue,
        iconColor: onBlue,
        subtitleTextStyle: TextStyle(
          fontFamily: 'NotoSans',
          color: mutedOnBlue,
          fontSize: 13,
        ),
      ),
      dividerTheme: DividerThemeData(
        color: whiteBorder.withValues(alpha: 0.15),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bluePanel,
        hintStyle: TextStyle(color: onBlue.withValues(alpha: 0.45)),
        labelStyle: const TextStyle(color: onBlue),
        prefixIconColor: onBlue.withValues(alpha: 0.7),
        suffixIconColor: onBlue.withValues(alpha: 0.7),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: whiteBorder.withValues(alpha: 0.25)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: whiteBorder.withValues(alpha: 0.25)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: yellowBorder),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: bluePanel,
        titleTextStyle: const TextStyle(
          fontFamily: 'NotoSans',
          color: onBlue,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: 'NotoSans',
          color: onBlue,
          fontSize: 14,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return yellowBorder;
          return onBlue.withValues(alpha: 0.55);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return blueAction;
          return bluePanel;
        }),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: bluePanel,
        selectedColor: blueAction,
        disabledColor: bluePanel.withValues(alpha: 0.5),
        labelStyle: const TextStyle(color: onBlue, fontFamily: 'NotoSans'),
        secondaryLabelStyle: const TextStyle(
          color: onBlue,
          fontFamily: 'NotoSans',
        ),
        side: BorderSide(color: whiteBorder.withValues(alpha: 0.25)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: yellowBorder,
        linearTrackColor: bluePanel,
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: bluePanel,
        contentTextStyle: TextStyle(color: onBlue, fontFamily: 'NotoSans'),
        actionTextColor: yellowBorder,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: blueAction,
          foregroundColor: Colors.white,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onBlue,
          side: BorderSide(color: whiteBorder.withValues(alpha: 0.35)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: yellowBorder),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: blueAction,
          foregroundColor: Colors.white,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: onBlue),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return blueAction;
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(Colors.white),
        side: BorderSide(color: onBlue.withValues(alpha: 0.5)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: blueAction,
        foregroundColor: Colors.white,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: bluePanel,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: bluePanel,
      ),
    );
  }
}
