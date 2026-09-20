import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';

/// Names the side a player was on, in the two colours the game already uses
/// for those sides: gold for the Civilians, danger red for the Undercover.
///
/// Only meaningful once the roles are public (game over), so this is
/// deliberately a plain label with no reveal behaviour of its own.
class RoleChip extends StatelessWidget {
  final String role;

  const RoleChip({super.key, required this.role});

  @override
  Widget build(BuildContext context) {
    final hextech = context.hextech;
    final isUndercover = role.toLowerCase() == 'undercover';
    final colour = isUndercover ? HextechColors.dangerBright : hextech.accent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: 0.12),
        border: Border.all(color: colour.withValues(alpha: 0.6)),
      ),
      child: Text(
        role.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: colour, fontSize: 10),
      ),
    );
  }
}
