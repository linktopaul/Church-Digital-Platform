import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:church_digital_platform_mobile/church_core.dart';

void main() {
  group('ChurchThemeConfig presets', () {
    test('romanBasilica preset properties', () {
      final theme = ChurchThemeConfig.romanBasilica();
      expect(theme.id, 'roman-basilica');
      expect(theme.displayName, 'Roman Basilica');
      expect(theme.primary, const Color(0xFF4E051A));
      expect(theme.primaryContainer, const Color(0xFFF8EBE6));
      expect(theme.fontFamily, 'serif');
      expect(theme.cardRadius, 18.0);
    });

    test('warmSanctuary preset properties', () {
      final theme = ChurchThemeConfig.warmSanctuary();
      expect(theme.id, 'warm-sanctuary');
      expect(theme.displayName, 'Warm Sanctuary');
      expect(theme.primary, const Color(0xFF1A365D));
      expect(theme.fontFamily, isNull);
    });

    test('cathedralEmerald preset properties', () {
      final theme = ChurchThemeConfig.cathedralEmerald();
      expect(theme.id, 'cathedral-emerald');
      expect(theme.displayName, 'Cathedral Emerald');
      expect(theme.primary, const Color(0xFF1B4332));
      expect(theme.fontFamily, 'serif');
    });

    test('modernCommunity preset properties', () {
      final theme = ChurchThemeConfig.modernCommunity();
      expect(theme.id, 'modern-community');
      expect(theme.displayName, 'Modern Community');
      expect(theme.primary, const Color(0xFF1F2937));
      expect(theme.secondary, const Color(0xFF4F46E5));
      expect(theme.cardRadius, 14.0);
    });

    test('fromSeed dynamically creates custom theme', () {
      final custom = ChurchThemeConfig.fromSeed(
        primary: const Color(0xFF0F172A),
        displayName: 'Midnight Cathedral',
        fontFamily: 'serif',
      );
      expect(custom.id, 'custom-church');
      expect(custom.displayName, 'Midnight Cathedral');
      expect(custom.primary, const Color(0xFF0F172A));
      expect(custom.fontFamily, 'serif');
    });
  });

  group('AppTheme.fromConfig', () {
    test('constructs consistent ThemeData for romanBasilica matching light()', () {
      final configTheme = AppTheme.fromConfig(ChurchThemeConfig.romanBasilica());
      final defaultTheme = AppTheme.light();

      expect(configTheme.colorScheme.primary, defaultTheme.colorScheme.primary);
      expect(configTheme.scaffoldBackgroundColor, defaultTheme.scaffoldBackgroundColor);
      expect(configTheme.cardTheme.color, defaultTheme.cardTheme.color);
    });

    test('constructs custom ThemeData for warmSanctuary', () {
      final theme = AppTheme.fromConfig(ChurchThemeConfig.warmSanctuary());
      expect(theme.colorScheme.primary, const Color(0xFF1A365D));
      expect(theme.scaffoldBackgroundColor, const Color(0xFFF8FAFC));
    });
  });

  group('ChurchProfileConfig & Terminology', () {
    test('catholic vs contemporary terminology', () {
      final catholic = ChurchTerminology.catholic();
      final contemporary = ChurchTerminology.contemporary();

      expect(catholic.clergyTitle, 'Father');
      expect(contemporary.clergyTitle, 'Pastor');

      expect(catholic.givingLabel, 'Caritas & Almsgiving');
      expect(contemporary.givingLabel, 'Tithes & Digital Offerings');

      expect(catholic.serviceName, 'Holy Mass');
      expect(contemporary.serviceName, 'Sunday Worship Service');
    });

    test('ChurchProfileConfig holds identity, upi, and terminology', () {
      final profile = ChurchProfileConfig(
        churchId: 'st-marys-bangalore',
        churchName: "St. Mary's Basilica",
        subtitle: 'Sacred Heart of Bangalore',
        address: 'Shivajinagar, Bengaluru',
        theme: ChurchThemeConfig.romanBasilica(),
        terminology: ChurchTerminology.catholic(),
        upi: const ChurchUpiConfig(
          vpa: 'stmarys@icici',
          merchantName: "St. Mary's Basilica Trust",
        ),
      );

      expect(profile.churchId, 'st-marys-bangalore');
      expect(profile.upi.vpa, 'stmarys@icici');
      expect(profile.terminology.clergyTitle, 'Father');
    });
  });
}
