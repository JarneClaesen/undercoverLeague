import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:undercoverleague/services/game_connection.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';

/// Thin bar shown above the screen body while the socket is being resumed.
/// It grows and shrinks rather than popping, so a brief blip does not make the
/// whole screen jump.
class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ConnectionStatus>(
      valueListenable: GameConnection.instance.status,
      builder: (context, status, _) {
        final reconnecting = status == ConnectionStatus.reconnecting;
        return AnimatedSize(
          duration: Motion.of(context, Motion.base),
          curve: Motion.enter,
          alignment: Alignment.topCenter,
          child: reconnecting ? const _Banner() : const SizedBox(width: double.infinity, height: 0),
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner();

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);

    Widget dot = Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(color: HextechColors.blue, shape: BoxShape.circle),
    );
    if (!reduced) {
      dot = dot
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .fadeIn(duration: 700.ms, begin: 0.25, curve: Motion.emphasized);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: HextechColors.blueDeep.withValues(alpha: 0.22),
        border: const Border(
          top: BorderSide(color: HextechColors.blueMid),
          bottom: BorderSide(color: HextechColors.blueMid),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          dot,
          const SizedBox(width: 10),
          Text(
            'RECONNECTING…',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: HextechColors.blue),
          ),
        ],
      ),
    );
  }
}
