import 'package:flutter/material.dart';

/// Estado vazio honesto: diz o que ainda não existe e quando chega.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.message,
    required this.hint,
    super.key,
  });

  final IconData icon;
  final String message;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              message,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              hint,
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
