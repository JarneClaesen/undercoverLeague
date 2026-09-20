import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:undercoverleague/services/lobby_service.dart';
import 'package:undercoverleague/widgets/upper_case_text_formatter.dart';

void main() {
  const formatter = UpperCaseTextFormatter();

  test('upper-cases typed text and keeps the caret', () {
    final out = formatter.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(text: 'abC12', selection: TextSelection.collapsed(offset: 3)),
    );
    expect(out.text, 'ABC12');
    expect(out.selection, const TextSelection.collapsed(offset: 3));
  });

  test('lobby ids are trimmed and upper-cased before use', () {
    expect(LobbyService.normalizeLobbyId(' abc12 '), 'ABC12');
  });
}
