import 'package:flutter/material.dart';

import 'placeholder_screen.dart';

class MessagesScreen extends StatelessWidget {
  const MessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderScreen(
      title: 'Messages',
      description: 'Church and fellowship conversations will appear here.',
      icon: Icons.chat_bubble_outline,
    );
  }
}
