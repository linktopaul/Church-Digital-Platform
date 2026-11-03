import 'package:flutter/material.dart';
import '../services/celebration_api_client.dart';
import 'celebrations_screen.dart';
import 'placeholder_screen.dart';

class HomeScreen extends StatelessWidget {
  final CelebrationApiClient? celebrationClient;
  final bool isPastor;
  final Future<bool> Function(String url)? onLaunchUrl;

  const HomeScreen({
    super.key,
    this.celebrationClient,
    this.isPastor = false,
    this.onLaunchUrl,
  });

  @override
  Widget build(BuildContext context) {
    if (celebrationClient == null) {
      return const PlaceholderScreen(
        title: 'Welcome',
        description: 'Church announcements and updates will appear here.',
        icon: Icons.home_outlined,
      );
    }

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 2,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.home, color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'Welcome to Church Digital Platform',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('Church announcements and updates will appear here.'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer.withAlpha(80),
            elevation: 1,
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.purple,
                child: Icon(Icons.cake, color: Colors.white),
              ),
              title: const Text(
                'Celebrations & Blessings',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text(
                'Celebrate member birthdays and anniversaries with scripture blessings.',
              ),
              trailing: const Icon(Icons.arrow_forward_ios, size: 16),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => CelebrationsScreen(
                      apiClient: celebrationClient,
                      isPastor: isPastor,
                      onLaunchUrl: onLaunchUrl,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
