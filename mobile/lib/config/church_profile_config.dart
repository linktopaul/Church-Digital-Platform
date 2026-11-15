import 'church_theme_config.dart';

/// Semantic church terminology dictionary allowing different Christian traditions
/// (Catholic, Protestant, Evangelical, Orthodox) to use their authentic nomenclature.
class ChurchTerminology {
  final String serviceName; // e.g. "Holy Mass" vs "Sunday Service"
  final String clergyTitle; // e.g. "Father / Canon" vs "Pastor"
  final String worshipLabel; // e.g. "Liturgia & Canticles" vs "Praise & Worship"
  final String prayerLabel; // e.g. "Preces Fidelium" vs "Prayer Wall"
  final String fellowshipLabel; // e.g. "Sodalitates" vs "Life Groups / Ministries"
  final String givingLabel; // e.g. "Caritas & Almsgiving" vs "Tithes & Offerings"

  const ChurchTerminology({
    this.serviceName = 'Holy Mass',
    this.clergyTitle = 'Father',
    this.worshipLabel = 'Liturgia & Canticles',
    this.prayerLabel = 'Preces Fidelium',
    this.fellowshipLabel = 'Sodalitates',
    this.givingLabel = 'Caritas & Almsgiving',
  });

  /// Catholic & Liturgical tradition terminology
  factory ChurchTerminology.catholic() => const ChurchTerminology(
        serviceName: 'Holy Mass',
        clergyTitle: 'Father',
        worshipLabel: 'Liturgia & Hymns',
        prayerLabel: 'Preces Fidelium (Prayer Petitions)',
        fellowshipLabel: 'Sodalitates (Parish Circles)',
        givingLabel: 'Caritas & Almsgiving',
      );

  /// Protestant & Contemporary tradition terminology
  factory ChurchTerminology.contemporary() => const ChurchTerminology(
        serviceName: 'Sunday Worship Service',
        clergyTitle: 'Pastor',
        worshipLabel: 'Praise & Worship Setlists',
        prayerLabel: 'Community Prayer Wall',
        fellowshipLabel: 'Small Groups & Fellowships',
        givingLabel: 'Tithes & Digital Offerings',
      );
}

/// UPI giving configuration specific to each church.
class ChurchUpiConfig {
  final String vpa;
  final String merchantName;
  final List<int> quickPresets;
  final List<String> availableFunds;

  const ChurchUpiConfig({
    required this.vpa,
    required this.merchantName,
    this.quickPresets = const [200, 500, 1000, 2500],
    this.availableFunds = const [
      'Sunday Tithes & General Fund',
      'Parish Building & Restoration',
      'Charity & Almsgiving for the Needy',
      'Missions & Youth Outreach',
    ],
  });
}

/// Central configuration object governing all customizations for a dedicated church.
class ChurchProfileConfig {
  final String churchId;
  final String churchName;
  final String? subtitle;
  final String address;
  final String? googleMapsUrl;
  final ChurchThemeConfig theme;
  final ChurchTerminology terminology;
  final ChurchUpiConfig upi;

  const ChurchProfileConfig({
    required this.churchId,
    required this.churchName,
    this.subtitle,
    required this.address,
    this.googleMapsUrl,
    required this.theme,
    required this.terminology,
    required this.upi,
  });

  /// Default flagship Roman Basilica profile configuration
  factory ChurchProfileConfig.romanBasilica() {
    return ChurchProfileConfig(
      churchId: 'roman-basilica',
      churchName: 'Basilica of St. Peter',
      subtitle: 'Basilica Maior · Missa & Vesperae',
      address: 'Piazza San Pietro, Vatican City / Main Cathedral Nave',
      theme: ChurchThemeConfig.romanBasilica(),
      terminology: ChurchTerminology.catholic(),
      upi: const ChurchUpiConfig(
        vpa: 'basilica.alms@icici',
        merchantName: 'Basilica of St. Peter Almsgiving Trust',
        quickPresets: [200, 500, 1000, 2500],
      ),
    );
  }

  /// Default contemporary sanctuary profile configuration
  factory ChurchProfileConfig.contemporarySanctuary() {
    return ChurchProfileConfig(
      churchId: 'grace-sanctuary',
      churchName: 'Grace Sanctuary Church',
      subtitle: 'Gathering in Faith, Hope & Community',
      address: '100 Grace Avenue, Indiranagar, Bengaluru, KA',
      theme: ChurchThemeConfig.warmSanctuary(),
      terminology: ChurchTerminology.contemporary(),
      upi: const ChurchUpiConfig(
        vpa: 'gracechurch@hdfcbank',
        merchantName: 'Grace Community Church Trust',
        quickPresets: [500, 1000, 2000, 5000],
      ),
    );
  }
}
