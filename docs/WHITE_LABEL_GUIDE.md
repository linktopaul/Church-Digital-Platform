# White-Label Multi-Church Architecture & Customization Guide

This guide details how to build and maintain dedicated mobile applications for different churches using the **Church Digital Platform Core Engine (`church_core`)**.

---

## 1. Architectural Strategy: Central Core Engine + Dedicated Repositories

Rather than managing multiple long-lived git branches or attempting to cram multi-tenant styling into a single bloated codebase, we use **Option 1: Central Core Engine + Dedicated Church Repositories**.

```
                           ┌────────────────────────────────────────┐
                           │      Church-Digital-Platform Repos     │
                           │  • Backend Microservices & API Gateway │
                           │  • mobile/lib/church_core.dart         │
                           │  • Roman Basilica Reference App        │
                           └──────────────────┬─────────────────────┘
                                              │ Git Dependency
                 ┌────────────────────────────┼───────────────────────────┐
                 ▼                            ▼                           ▼
┌─────────────────────────────────┐ ┌───────────────────┐ ┌─────────────────────────────────┐
│     church-grace-community      │ │ church-st-marys   │ │      church-city-light          │
│ • Custom Contemporary UI / Hero │ │ • Liturgical Mass │ │ • Youth Ministry & Modern Grid  │
│ • Warm Sanctuary / Indigo Theme │ │ • Roman Basilica  │ │ • Vibrant Emerald / Forest      │
│ • Custom Features & Nav Drawer  │ │ • Latin & Rosary  │ │ • Bottom Nav Bar with Badges    │
│ • Dedicated Play Store ID       │ │ • Dedicated App ID│ │ • Dedicated Play Store ID       │
└─────────────────────────────────┘ └───────────────────┘ └─────────────────────────────────┘
```

### Why this approach?
1. **Zero Merge Divergence**: Churches frequently demand bespoke features (e.g. choir sign-ups, specific sacramental records, bilingual Latin/English chants). Custom code in individual repos never creates merge conflicts against core updates.
2. **Unified Core Logic**: All churches receive battle-tested OIDC PKCE authentication, secure JWT refresh handling, offline-first SQLite cache, UPI payment intents, and typed domain models from `church_core`.
3. **Repository Limits & Asset Hygiene**: App icons, splash screens, church photos, and branding assets stay in that church's repo, preventing the central platform from bloating over time.
4. **Independent Store Listings**: Each church gets its own `applicationId` (`org.grace.church`, `org.stmarys.basilica`), Apple Team ID, Google Play Console credentials, and independent release cycles.

---

## 2. Setting Up a New Church Client Repository in 5 Minutes

### Step 1: Create a new Flutter project
```bash
flutter create --org org.gracechurch --project-name grace_community_app church_grace_community
cd church_grace_community
```

### Step 2: Configure `pubspec.yaml`
Add the mobile core package directly from your Git repository:

```yaml
name: grace_community_app
description: "Grace Community Church Mobile App"
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.3.0 <4.0.0'
  flutter: ">=3.19.0"

dependencies:
  flutter:
    sdk: flutter
  # Reusable core platform engine
  church_digital_platform_mobile:
    git:
      url: https://github.com/linktopaul/Church-Digital-Platform.git
      path: mobile
      ref: main # Or pin to a release tag: v1.0.0

  shared_preferences: ^2.5.6
```

### Step 3: Define Church Configuration (`lib/config/church_config.dart`)
Define the church identity, branding tokens, UPI payment routing, and liturgical/contemporary terminology:

```dart
import 'package:flutter/material.dart';
import 'package:church_digital_platform_mobile/church_core.dart';

class GraceChurchProfile {
  static final theme = ChurchThemeConfig.warmSanctuary();
  // Or: ChurchThemeConfig.cathedralEmerald();
  // Or: ChurchThemeConfig.modernCommunity();
  // Or: ChurchThemeConfig.fromSeed(primary: Color(0xFF1E3A8A), displayName: 'Grace Navy');

  static final profile = ChurchProfileConfig(
    churchId: 'grace-community-bengaluru',
    churchName: 'Grace Community Church',
    subtitle: 'Loving God, Serving People, Transforming Cities',
    address: 'Koramangala, Bengaluru, Karnataka 560034',
    theme: theme,
    // Choose between Catholic/Liturgical vs Protestant/Contemporary terminology
    terminology: ChurchTerminology.contemporary(),
    upi: const ChurchUpiConfig(
      vpa: 'gracechurch@icici',
      merchantName: 'Grace Community Church Trust',
      quickPresets: [200, 500, 1000, 2500, 5000],
    ),
  );
}
```

### Step 4: Bootstrap `main.dart`
```dart
import 'package:flutter/material.dart';
import 'package:church_digital_platform_mobile/church_core.dart';
import 'config/church_config.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const GraceChurchApp());
}

class GraceChurchApp extends StatelessWidget {
  const GraceChurchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: GraceChurchProfile.profile.churchName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.fromConfig(GraceChurchProfile.theme),
      home: const ChurchRootGateway(
        // Inject custom church home feed or use standard modules
      ),
    );
  }
}
```

---

## 3. Supported Theme Archetypes

`ChurchThemeConfig` includes four built-in archetypes designed by sacred design guidelines:

| Archetype | Primary Colors | Typography | Ideal Church Tradition |
|---|---|---|---|
| **Roman Basilica** | Imperial Burgundy (`#4E051A`), Gold (`#B8860B`), Travertine (`#FFF8F6`) | Georgia Serif | Catholic, Orthodox, High Anglican |
| **Warm Sanctuary** | Deep Nave Navy (`#1A365D`), Alabaster (`#F8FAFC`), Honey Gold (`#D97706`) | Sans-serif / Inter | Protestant, Reformed, Presbyterian, Baptist |
| **Cathedral Emerald** | Sacred Pine (`#1B4332`), Forest Mint (`#D8F3DC`), Polished Brass (`#C5A059`) | Classical Serif | Episcopal, Lutheran, Celtic Christian |
| **Modern Community** | Electric Indigo (`#4338CA`), Slate Crisp (`#F8FAFC`), Vibrant Violet (`#7C3AED`) | Modern Sans | Contemporary, Pentecostal, Multi-site |

Custom branding can also be generated on the fly from any brand hex code:
```dart
final customTheme = ChurchThemeConfig.fromSeed(
  primary: const Color(0xFF0F172A),
  displayName: 'Metropolitan Church',
  isSerif: false,
);
```

---

## 4. Customizing UI & UX per Church

Because each church owns its own Flutter repository, you have complete architectural freedom to structure navigation and layouts:

1. **Liturgical Layout (e.g. St. Mary's)**:
   - Centered Tab Bar with Latin headers (*Oratio*, *Liturgia*, *Caritas*).
   - Prominent Liturgical calendar banner (Advent, Lent, Ordinary Time).
   - High-contrast card borders with sacred gold pill badges.

2. **Contemporary Community Layout (e.g. Grace Chapel)**:
   - Full-bleed video hero for Sunday livestreams.
   - Quick card actions: "Watch Live", "Connect Groups", "Next Steps", "Give".
   - Navigation Drawer with event registration and small-group chat rooms.

---

## 5. Deployment & Release Checklist per Church

When packaging an individual church application:
1. **Update Android Application ID**:
   Edit `android/app/build.gradle`:
   ```groovy
   defaultConfig {
       applicationId "org.gracechurch.mobile"
       minSdkVersion 21
       targetSdkVersion 34
   }
   ```
2. **Set OAuth Redirect URI**:
   Ensure `authClientId` and OIDC redirect schemes match in `android/app/src/main/AndroidManifest.xml`:
   ```xml
   <data android:scheme="org.gracechurch.mobile" android:host="oauth2redirect" />
   ```
3. **App Assets**:
   Replace `assets/icon/icon.png` and `assets/splash.png` with the church's high-res crest or logo.
