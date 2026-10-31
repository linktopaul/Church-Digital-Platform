import 'package:flutter/material.dart';

import 'placeholder_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Welcome',
      description: 'Church announcements and updates will appear here.',
      icon: Icons.home_outlined,
    );
  }
}
