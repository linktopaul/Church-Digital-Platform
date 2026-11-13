import 'package:flutter/material.dart';

/// Roman Basilica & Sacred Sanctuary color tokens for Church Digital Platform.
///
/// Combines deep imperial Roman burgundy (#4E051A / #6B1D2F) with warm alabaster
/// parchment (#FFF8F6), antique travertine stone (#F2E6E1 / #FDF1EC), marble
/// hairline borders (#DAC0C2), Roman liturgical gold (#B8860B), sacred laurel
/// olive (#2B6A4F), and deep warm sepia ink (#201A18).
abstract final class BasilicaColors {
  static const Color burgundy = Color(0xFF4E051A);
  static const Color burgundyDeep = Color(0xFF360312);
  static const Color burgundyContainer = Color(0xFF6B1D2F);
  static const Color burgundySoft = Color(0xFFF8EBE6);

  static const Color parchment = Color(0xFFFFF8F6);
  static const Color surfaceCard = Color(0xFFFFFFFF);
  static const Color stone = Color(0xFFF2E6E1);
  static const Color stoneLow = Color(0xFFFDF1EC);
  static const Color borderSoft = Color(0xFFDAC0C2);

  static const Color gold = Color(0xFFB8860B);
  static const Color goldLight = Color(0xFFFED488);
  static const Color goldSoft = Color(0xFFFDF1EC);

  static const Color olive = Color(0xFF2B6A4F);
  static const Color oliveSoft = Color(0xFFE9F4EE);

  static const Color porphyry = Color(0xFF6B1D2F);
  static const Color porphyrySoft = Color(0xFFF8EBE6);

  static const Color ink = Color(0xFF201A18);
  static const Color inkMuted = Color(0xFF544244);
}

/// Backward-compatible alias for existing Sanctuary color references.
abstract final class SanctuaryColors {
  static const Color navy = BasilicaColors.burgundy;
  static const Color navyDeep = BasilicaColors.burgundyDeep;
  static const Color navySoft = BasilicaColors.burgundySoft;

  static const Color ivory = BasilicaColors.parchment;
  static const Color surfaceCard = BasilicaColors.surfaceCard;
  static const Color stone = BasilicaColors.stone;
  static const Color borderSoft = BasilicaColors.borderSoft;

  static const Color gold = BasilicaColors.gold;
  static const Color goldSoft = BasilicaColors.goldSoft;

  static const Color sage = BasilicaColors.olive;
  static const Color sageSoft = BasilicaColors.oliveSoft;

  static const Color plum = BasilicaColors.porphyry;
  static const Color plumSoft = BasilicaColors.porphyrySoft;

  static const Color ink = BasilicaColors.ink;
  static const Color inkMuted = BasilicaColors.inkMuted;
}

/// Centralized Material 3 theme definition for the Roman Basilica aesthetic.
abstract final class AppTheme {
  static ThemeData light() {
    final baseScheme = ColorScheme.fromSeed(
      seedColor: BasilicaColors.burgundy,
      brightness: Brightness.light,
      surface: BasilicaColors.parchment,
    );

    final colorScheme = baseScheme.copyWith(
      primary: BasilicaColors.burgundy,
      onPrimary: Colors.white,
      primaryContainer: BasilicaColors.burgundySoft,
      onPrimaryContainer: BasilicaColors.burgundyDeep,
      secondary: BasilicaColors.gold,
      secondaryContainer: BasilicaColors.goldLight,
      onSecondaryContainer: const Color(0xFF3B2700),
      surface: BasilicaColors.parchment,
      surfaceContainerLowest: BasilicaColors.surfaceCard,
      surfaceContainerLow: BasilicaColors.stoneLow,
      surfaceContainer: BasilicaColors.stone,
      surfaceContainerHighest: BasilicaColors.stone,
      outline: BasilicaColors.borderSoft,
      outlineVariant: BasilicaColors.borderSoft,
      onSurface: BasilicaColors.ink,
      onSurfaceVariant: BasilicaColors.inkMuted,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'serif',
      colorScheme: colorScheme,
      scaffoldBackgroundColor: BasilicaColors.parchment,
      appBarTheme: const AppBarTheme(
        backgroundColor: BasilicaColors.surfaceCard,
        foregroundColor: BasilicaColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: 'serif',
          color: BasilicaColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
        shape: Border(
          bottom: BorderSide(color: BasilicaColors.borderSoft, width: 1),
        ),
      ),
      cardTheme: CardThemeData(
        color: BasilicaColors.surfaceCard,
        surfaceTintColor: Colors.transparent,
        shadowColor: BasilicaColors.burgundy.withValues(alpha: 0.06),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: BasilicaColors.borderSoft, width: 1),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: BasilicaColors.borderSoft,
        thickness: 1,
        space: 1,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        elevation: 0,
        highlightElevation: 2,
        backgroundColor: BasilicaColors.burgundy,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: BasilicaColors.burgundy,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: 'serif',
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: 0.5,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: BasilicaColors.burgundy,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: 'serif',
            fontWeight: FontWeight.w600,
            fontSize: 15,
            letterSpacing: 0.5,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: BasilicaColors.burgundy,
          side: const BorderSide(color: BasilicaColors.borderSoft),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(
            fontFamily: 'serif',
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: BasilicaColors.surfaceCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BasilicaColors.borderSoft),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BasilicaColors.borderSoft),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: BasilicaColors.burgundy, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: colorScheme.error),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: BasilicaColors.surfaceCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        indicatorColor: BasilicaColors.burgundySoft,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontFamily: 'serif',
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: 0.5,
            color: isSelected ? BasilicaColors.burgundy : BasilicaColors.inkMuted,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: isSelected ? BasilicaColors.burgundy : BasilicaColors.inkMuted,
          );
        }),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: BasilicaColors.burgundy,
        unselectedLabelColor: BasilicaColors.inkMuted,
        indicatorColor: BasilicaColors.burgundy,
        dividerColor: BasilicaColors.borderSoft,
        labelStyle: TextStyle(
          fontFamily: 'serif',
          fontWeight: FontWeight.w700,
          fontSize: 13,
          letterSpacing: 0.6,
        ),
        unselectedLabelStyle: TextStyle(
          fontFamily: 'serif',
          fontWeight: FontWeight.w500,
          fontSize: 13,
          letterSpacing: 0.6,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: BasilicaColors.stone,
        selectedColor: BasilicaColors.burgundySoft,
        side: const BorderSide(color: BasilicaColors.borderSoft),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

/// Pill status badge for liturgical tags, urgency, and category indicators.
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
        border: Border.all(
          color: foregroundColor.withValues(alpha: 0.2),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: foregroundColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: TextStyle(
              fontFamily: 'serif',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: foregroundColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Clean section header with classical Roman small-caps styling.
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
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFamily: 'serif',
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: BasilicaColors.burgundy,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontFamily: 'serif',
                    fontStyle: FontStyle.italic,
                    color: BasilicaColors.inkMuted,
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

/// Dignified Roman Basilica empty state card with icon emblem and optional action button.
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
    final fg = accentColor ?? BasilicaColors.burgundy;
    final bg = accentBackground ?? BasilicaColors.burgundySoft;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: Border.all(color: fg.withValues(alpha: 0.2)),
              ),
              child: Icon(icon, size: 28, color: fg),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontFamily: 'serif',
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: BasilicaColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              description,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontFamily: 'serif',
                color: BasilicaColors.inkMuted,
                height: 1.45,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 18),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Roman liturgical scripture quote card (Inscriptio Sacra / Benediction banner).
class BasilicaVerseCard extends StatelessWidget {
  final String quote;
  final String attribution;
  final String? rubric;

  const BasilicaVerseCard({
    super.key,
    required this.quote,
    required this.attribution,
    this.rubric,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
      decoration: BoxDecoration(
        color: BasilicaColors.stoneLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: BasilicaColors.borderSoft),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.church_outlined,
            size: 24,
            color: BasilicaColors.gold,
          ),
          const SizedBox(height: 10),
          if (rubric != null) ...[
            Text(
              rubric!.toUpperCase(),
              style: const TextStyle(
                fontFamily: 'serif',
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: BasilicaColors.gold,
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            '« $quote »',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'serif',
              fontSize: 15,
              fontStyle: FontStyle.italic,
              height: 1.5,
              color: BasilicaColors.burgundy,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '— $attribution',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'serif',
              fontSize: 12.5,
              fontStyle: FontStyle.italic,
              color: BasilicaColors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}
