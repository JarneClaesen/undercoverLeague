import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:undercoverleague/theme/hextech_colors.dart';
import 'package:undercoverleague/theme/motion.dart';

/// A [TextField] with the hextech input decoration and a soft blue halo while
/// it has focus. Everything else comes from `inputDecorationTheme`.
class HextechTextField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData? prefixIcon;
  final TextCapitalization textCapitalization;
  final int? maxLength;
  final ValueChanged<String>? onSubmitted;
  final String? errorText;
  final TextInputAction? textInputAction;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;

  const HextechTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint,
    this.prefixIcon,
    this.textCapitalization = TextCapitalization.none,
    this.maxLength,
    this.onSubmitted,
    this.errorText,
    this.textInputAction,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  State<HextechTextField> createState() => _HextechTextFieldState();
}

class _HextechTextFieldState extends State<HextechTextField> {
  final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus != _focused) setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.errorText != null;

    return AnimatedContainer(
      duration: Motion.of(context, Motion.fast),
      curve: Motion.enter,
      decoration: BoxDecoration(
        boxShadow: _focused && !hasError
            ? [BoxShadow(color: HextechColors.blue.withValues(alpha: 0.25), blurRadius: 8)]
            : const [],
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        textCapitalization: widget.textCapitalization,
        maxLength: widget.maxLength,
        onSubmitted: widget.onSubmitted,
        textInputAction: widget.textInputAction,
        keyboardType: widget.keyboardType,
        inputFormatters: widget.inputFormatters,
        style: Theme.of(context).textTheme.bodyLarge,
        cursorColor: HextechColors.blue,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          errorText: widget.errorText,
          prefixIcon: widget.prefixIcon == null ? null : Icon(widget.prefixIcon, size: 18),
          // The theme's counter styling is fine, but a counter under every
          // field is noise; only show it when a limit is actually set low.
          counterText: widget.maxLength == null ? null : '',
        ),
      ),
    );
  }
}
