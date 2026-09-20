import 'package:flutter/material.dart';

/// Shows a player their role and, for civilians, the drawn champion/item.
/// Shared by the role-reveal and round screens so they can't drift apart.
class RoleCard extends StatelessWidget {
  final String role;
  final String word;
  final String icon;
  final bool isChampion;
  final bool large;

  const RoleCard({
    super.key,
    required this.role,
    required this.word,
    required this.icon,
    required this.isChampion,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final fontSize = large ? 24.0 : 18.0;
    final isCivilian = role == 'Civilian';
    final isUndercover = role == 'Undercover';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isCivilian)
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Image.asset(
              icon,
              width: 200,
              height: 200,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                debugPrint('Error loading image $icon: $error');
                return const Icon(Icons.image_not_supported, size: 200);
              },
            ),
          ),
        if (isUndercover) const Icon(Icons.question_mark, size: 200, color: Colors.red),
        const SizedBox(height: 20),
        Text('Your Role: $role', style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.bold)),
        const SizedBox(height: 20),
        if (isCivilian)
          Text(
            isChampion ? 'Your champion: $word' : 'Your item: $word',
            style: TextStyle(fontSize: fontSize, color: Colors.blue),
          ),
        if (isUndercover)
          Text(
            'You are the Undercover!',
            style: TextStyle(fontSize: fontSize, color: Colors.red, fontWeight: FontWeight.bold),
          ),
      ],
    );
  }
}
