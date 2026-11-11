import 'package:flutter/material.dart';

/// Shared "Warm Sanctuary" color tokens for the Church Digital Platform app.
///
/// Combines deep sanctuary navy with a warm ivory canvas, gentle stone borders,
/// brass/gold highlights for celebrations, and muted sage for giving verification.
abstract final class SanctuaryColors {
  static const Color navy = Color(0xFF2F5075);
  static const Color navyDeep = Color(0xFF203956);
  static const Color navySoft = Color(0xFFE7EEF6);

  static const Color ivory = Color(0xFFFAF8F4);
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color stone = Color(0xFFF3EFE7);
  static const Color borderSoft = Color(0xFFE3DDD1);

  static const Color gold = Color(0xFFB57C24);
  static const Color goldSoft = Color(0xFFFDF4E3);

  static const Color sage = Color(0xFF2B6A4F);
  static const Color sageSoft = Color(0xFFE9F4EE);

  static const Color plum = Color(0xFF6E4B7F);
  static const Color plumSoft = Color(0xFFF4EEF7);

  static const Color ink = Color(0xFF1F2937);
  static const Color inkMuted = Color(0xFF5E6773);
}

/// Centralized Material 3 theme definition for Warm Sanctuary styling.
abstract final class AppTheme {
  static ThemeData light() {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: SanctuaryColors.navy,
      brightness: Brightness.light,
      surface: SanctuaryColors.ivory,
    );

    final colorScheme = baseScheme.copyWith(
      primary: SanctuaryColors.navy,
      onPrimary: Colors.white,
      primaryContainer: SanctuaryColors.navySoft,
      onPrimaryContainer: SanctuaryColors.navyDeep,
      secondary: SanctuaryColors.gold,
      secondaryContainer: SanctuaryColors.goldSoft,
      onSecondaryContainer: const Color(0xFF5D3E0D),
      surface: SanctuaryColors.ivory,
      surfaceContainerLowest: SanctuaryColors.surfaceCard,
      surfaceContainerLow: SanctuaryColors.surfaceCard,
      surfaceContainer: SanctuaryColors.stone,
      surfaceContainerHighest: SanctuaryColors.stone,
      outline: SanctuaryColors.borderSoft,
      outlineVariant: SanctuaryColors.borderSoft,
      onSurface: SanctuaryColors.ink,
      onSurfaceVariant: SanctuaryColors.inkMuted,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'Roboto',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: SanctuaryColors.ivory,
      appBarTheme: const AppBarTheme(
        backgroundColor: SanctuaryColors.surfaceCard,
        foregroundColor: SanctuaryColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'Roboto',
          color: SanctuaryColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
        shape: Border(
          bottom: BorderSide(color: SanctuaryColors.borderSoft, width: 1),
        ),
      ),
      cardTheme: CardThemeData(
        color: SanctuaryColors.surfaceCard,
        surfaceTintColor: Colors.transparent,
        shadowColor: SanctuaryColors.navy.withValues(alpha: 0.08),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: SanctuaryColors.borderSoft, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: SanctuaryColors.borderSoft,
        thickness: 1,
        space: 1,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        highlightElevation: 2,
        backgroundColor: SanctuaryColors.navy,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: SanctuaryColors.navy,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: SanctuaryColors.navy,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w500,
            fontSize: 15,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: SanctuaryColors.navy,
          side: const BorderSide(color: SanctuaryColors.borderSoft),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: SanctuaryColors.surfaceCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: SanctuaryColors.borderSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: SanctuaryColors.borderSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: SanctuaryColors.navy, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.error),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: SanctuaryColors.surfaceCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: SanctuaryColors.navySoft,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: 'Roboto',
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? SanctuaryColors.navy : SanctuaryColors.inkMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: isSelected ? SanctuaryColors.navy : SanctuaryColors.inkMuted,
          );
        }),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: SanctuaryColors.navy,
        unselectedLabelColor: SanctuaryColors.inkMuted,
        indicatorColor: SanctuaryColors.navy,
        dividerColor: SanctuaryColors.borderSoft,
        labelStyle: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w700, fontSize: 14),
        unselectedLabelStyle: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w500, fontSize: 14),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: SanctuaryColors.stone,
        selectedColor: SanctuaryColors.navySoft,
        side: const BorderSide(color: SanctuaryColors.borderSoft),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// Soft pill status badge reused across announcements, prayer, giving, and worship screens.
class SanctuaryStatusBadge extends StatelessWidget {
  final String label;
  final Color foregroundColor;
  final Color backgroundColor;
  final IconData? icon;

  const SanctuaryStatusBadge({
    super.key,
    required this.label,
    required this.foregroundColor,
    required this.backgroundColor,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foregroundColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: foregroundColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Clean section header with optional trailing count pill or action widget.
class SanctuarySectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const SanctuarySectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: SanctuaryColors.ink,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: SanctuaryColors.inkMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Friendly warm-tinted empty state card with icon emblem and optional action button.
class SanctuaryEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final Color? accentColor;
  final Color? accentBackground;
  final Widget? action;

  const SanctuaryEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.accentColor,
    this.accentBackground,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = accentColor ?? SanctuaryColors.navy;
    final bg = accentBackground ?? SanctuaryColors.navySoft;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28, color: fg),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: SanctuaryColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: SanctuaryColors.inkMuted,
                height: 1.4,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 16),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
