import 'package:flutter/services.dart';

/// Upper-cases whatever is typed or pasted, keeping the selection in place.
/// Used for lobby codes, which are case insensitive and always shown in caps.
class UpperCaseTextFormatter extends TextInputFormatter {
  const UpperCaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    // Dart's toUpperCase maps one code unit to one, so the selection and
    // composing range stay valid as they are.
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
