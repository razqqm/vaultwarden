import 'package:flutter/material.dart';

class FingerprintPhrase extends StatelessWidget {
  final String phrase;

  const FingerprintPhrase({super.key, required this.phrase});

  @override
  Widget build(BuildContext context) {
    final words = phrase.split('-');
    final theme = Theme.of(context);

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: words.map((word) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            word,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
        );
      }).toList(),
    );
  }
}
