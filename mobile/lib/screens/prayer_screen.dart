import 'package:flutter/material.dart';

import 'placeholder_screen.dart';

class PrayerScreen extends StatelessWidget {
  const PrayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Prayer',
      description: 'Share prayer requests and follow their updates here.',
      icon: Icons.favorite_border,
    );
  }
}
