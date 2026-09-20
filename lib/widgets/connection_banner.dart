import 'package:flutter/material.dart';
import 'package:undercoverleague/services/game_connection.dart';

/// Thin bar shown above the screen body while the socket is being resumed.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ConnectionStatus>(
      valueListenable: GameConnection.instance.status,
      builder: (context, status, _) {
        if (status != ConnectionStatus.reconnecting) return const SizedBox.shrink();
        return Material(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 10),
                Text('Reconnecting…', style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer)),
              ],
            ),
          ),
        );
      },
    );
  }
}
