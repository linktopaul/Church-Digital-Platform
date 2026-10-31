import 'package:flutter/material.dart';

import 'placeholder_screen.dart';

class WorshipScreen extends StatelessWidget {
  const WorshipScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Worship',
      description: 'Songs, chords, and Sunday setlists will appear here.',
      icon: Icons.music_note_outlined,
    );
  }
}
