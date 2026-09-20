import 'package:flutter/material.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';

/// The picture of a drawn word. The server sends Data Dragon URLs; the one
/// bundled asset left is the placeholder for players who may not see the
/// word, so both kinds are accepted.
bool isNetworkIcon(String icon) => icon.startsWith('http://') || icon.startsWith('https://');

ImageProvider wordImageProvider(String icon) =>
    isNetworkIcon(icon) ? NetworkImage(icon) : AssetImage(icon) as ImageProvider;

/// Builds the image with a spinner while a network portrait loads and the
/// same fallback icon on failure for both kinds.
Widget wordImage(
  BuildContext context,
  String icon, {
  required double width,
  required double height,
  required BoxFit fit,
  double? fallbackSize,
}) {
  final hextech = context.hextech;
  Widget fallback(Object error) {
    debugPrint('Could not load word image $icon: $error');
    return SizedBox(
      width: width,
      height: height,
      child: Icon(Icons.image_not_supported_outlined, size: fallbackSize ?? width * 0.5, color: hextech.textDisabled),
    );
  }

  return Image(
    image: wordImageProvider(icon),
    width: width,
    height: height,
    fit: fit,
    filterQuality: FilterQuality.medium,
    gaplessPlayback: true,
    loadingBuilder: (context, child, progress) {
      if (progress == null) return child;
      return SizedBox(
        width: width,
        height: height,
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: hextech.accent),
          ),
        ),
      );
    },
    errorBuilder: (context, error, stackTrace) => fallback(error),
  );
}
