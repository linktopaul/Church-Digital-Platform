import 'package:flutter/material.dart';

/// Configuration definition for church-specific visual branding, colors, and typography.
///
/// Supports preset church archetypes (Roman Basilica, Warm Sanctuary, Cathedral Emerald, Modern Community)
/// as well as dynamic seed-generated palettes for custom church brand guidelines.
class ChurchThemeConfig {
  final String id;
  final String displayName;

  // Primary brand identity
  final Color primary;
  final Color primaryContainer;
  final Color onPrimary;
  final Color onPrimaryContainer;

  // Secondary & liturgical highlights
  final Color secondary;
  final Color secondaryContainer;
  final Color accentGold;
  final Color accentSuccess;

  // Surfaces & structural cards
  final Color scaffoldBackground;
  final Color cardBackground;
  final Color containerBackground;
  final Color containerLow;
  final Color hairlineBorder;

  // Ink & contrast typography
  final Color ink;
  final Color inkMuted;

  // Geometry & font family
  final String? fontFamily;
  final double cardRadius;

  const ChurchThemeConfig({
    required this.id,
    required this.displayName,
    required this.primary,
    required this.primaryContainer,
    required this.onPrimary,
    required this.onPrimaryContainer,
    required this.secondary,
    required this.secondaryContainer,
    required this.accentGold,
    required this.accentSuccess,
    required this.scaffoldBackground,
    required this.cardBackground,
    required this.containerBackground,
    required this.containerLow,
    required this.hairlineBorder,
    required this.ink,
    required this.inkMuted,
    this.fontFamily,
    this.cardRadius = 18.0,
  });

  /// Preset 1: Roman Basilica — Traditional liturgical burgundy, travertine stone, gold halo accents, and classical serif typography.
  factory ChurchThemeConfig.romanBasilica() {
    return const ChurchThemeConfig(
      id: 'roman-basilica',
      displayName: 'Roman Basilica',
      primary: Color(0xFF4E051A),
      primaryContainer: Color(0xFFF8EBE6),
      onPrimary: Colors.white,
      onPrimaryContainer: Color(0xFF360312),
      secondary: Color(0xFFB8860B),
      secondaryContainer: Color(0xFFFED488),
      accentGold: Color(0xFFFED488),
      accentSuccess: Color(0xFF2B6A4F),
      scaffoldBackground: Color(0xFFFFF8F6),
      cardBackground: Color(0xFFFFFFFF),
      containerBackground: Color(0xFFF2E6E1),
      containerLow: Color(0xFFFDF1EC),
      hairlineBorder: Color(0xFFDAC0C2),
      ink: Color(0xFF201A18),
      inkMuted: Color(0xFF544244),
      fontFamily: 'serif',
      cardRadius: 18.0,
    );
  }

  /// Preset 2: Warm Sanctuary — Deep nave navy, warm alabaster, radiant gold, and soft sage for Protestant/Reformed traditions.
  factory ChurchThemeConfig.warmSanctuary() {
    return const ChurchThemeConfig(
      id: 'warm-sanctuary',
      displayName: 'Warm Sanctuary',
      primary: Color(0xFF1A365D),
      primaryContainer: Color(0xFF2A4365),
      onPrimary: Colors.white,
      onPrimaryContainer: Color(0xFFFEFCBF),
      secondary: Color(0xFFD97706),
      secondaryContainer: Color(0xFFFDE68A),
      accentGold: Color(0xFFF59E0B),
      accentSuccess: Color(0xFF059669),
      scaffoldBackground: Color(0xFFF8FAFC),
      cardBackground: Color(0xFFFFFFFF),
      containerBackground: Color(0xFFEDF2F7),
      containerLow: Color(0xFFF7FAFC),
      hairlineBorder: Color(0xFFCBD5E1),
      ink: Color(0xFF0F172A),
      inkMuted: Color(0xFF64748B),
      fontFamily: null, // Clean sans-serif
      cardRadius: 16.0,
    );
  }

  /// Preset 3: Cathedral Emerald — Sacred forest emerald, cream linen, and antique brass for heritage and Celtic chapels.
  factory ChurchThemeConfig.cathedralEmerald() {
    return const ChurchThemeConfig(
      id: 'cathedral-emerald',
      displayName: 'Cathedral Emerald',
      primary: Color(0xFF1B4332),
      primaryContainer: Color(0xFF2D6A4F),
      onPrimary: Colors.white,
      onPrimaryContainer: Color(0xFFD8F3DC),
      secondary: Color(0xFFC5A059),
      secondaryContainer: Color(0xFFEDE0C8),
      accentGold: Color(0xFFD4AF37),
      accentSuccess: Color(0xFF40916C),
      scaffoldBackground: Color(0xFFFAF7F2),
      cardBackground: Color(0xFFFFFFFF),
      containerBackground: Color(0xFFF0EBE1),
      containerLow: Color(0xFFF8F5EE),
      hairlineBorder: Color(0xFFD4C7B5),
      ink: Color(0xFF1C1917),
      inkMuted: Color(0xFF57534E),
      fontFamily: 'serif',
      cardRadius: 18.0,
    );
  }

  /// Preset 4: Modern Community — Minimalist charcoal, clean white, and electric indigo for contemporary and youth-led churches.
  factory ChurchThemeConfig.modernCommunity() {
    return const ChurchThemeConfig(
      id: 'modern-community',
      displayName: 'Modern Community',
      primary: Color(0xFF1F2937),
      primaryContainer: Color(0xFF374151),
      onPrimary: Colors.white,
      onPrimaryContainer: Color(0xFFE5E7EB),
      secondary: Color(0xFF4F46E5),
      secondaryContainer: Color(0xFFEEF2FF),
      accentGold: Color(0xFFF59E0B),
      accentSuccess: Color(0xFF10B981),
      scaffoldBackground: Color(0xFFF9FAFB),
      cardBackground: Color(0xFFFFFFFF),
      containerBackground: Color(0xFFF3F4F6),
      containerLow: Color(0xFFFAFAFA),
      hairlineBorder: Color(0xFFE5E7EB),
      ink: Color(0xFF111827),
      inkMuted: Color(0xFF6B7280),
      fontFamily: null,
      cardRadius: 14.0,
    );
  }

  /// Generates a harmonious, contrast-safe church theme dynamically from any primary seed color.
  factory ChurchThemeConfig.fromSeed({
    required Color primary,
    Color? accent,
    String? fontFamily,
    double cardRadius = 16.0,
    String id = 'custom-church',
    String displayName = 'Custom Church Theme',
  }) {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    );

    final computedOnPrimary =
        ThemeData.estimateBrightnessForColor(primary) == Brightness.dark
            ? Colors.white
            : const Color(0xFF111827);

    return ChurchThemeConfig(
      id: id,
      displayName: displayName,
      primary: primary,
      primaryContainer: scheme.primaryContainer,
      onPrimary: computedOnPrimary,
      onPrimaryContainer: scheme.onPrimaryContainer,
      secondary: accent ?? scheme.secondary,
      secondaryContainer: scheme.secondaryContainer,
      accentGold: accent ?? scheme.secondary,
      accentSuccess: const Color(0xFF10B981),
      scaffoldBackground: scheme.surface,
      cardBackground: Colors.white,
      containerBackground: scheme.surfaceContainer,
      containerLow: scheme.surfaceContainerLow,
      hairlineBorder: scheme.outlineVariant,
      ink: scheme.onSurface,
      inkMuted: scheme.onSurfaceVariant,
      fontFamily: fontFamily,
      cardRadius: cardRadius,
    );
  }
}
