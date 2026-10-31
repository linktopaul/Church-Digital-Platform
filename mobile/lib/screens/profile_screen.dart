import 'package:flutter/material.dart';

import 'placeholder_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Profile',
      description: 'Your member profile and family details will appear here.',
      icon: Icons.person_outline,
    );
  }
}
