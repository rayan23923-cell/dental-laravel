import 'package:flutter/services.dart';

/// Number fields accept numbers only (2026-10-14, by request: "حقول الارقام
/// لاتقبل سوى الارقام"), matching the web's `numericInputs.js`: Arabic-Indic
/// digits (٠-٩, ۰-۹) become 0-9 and anything else is dropped as it is typed
/// or pasted. The server still validates every value.
class NumericInputFormatter extends TextInputFormatter {
  const NumericInputFormatter({this.decimal = false, this.signed = false, this.phone = false});

  final bool decimal;
  final bool signed;
  final bool phone;

  static String toAscii(String s) => s.replaceAllMapped(
        RegExp('[٠-٩۰-۹]'),
        (m) => '${(m[0]!.codeUnitAt(0) & 0xf) % 10}',
      );

  bool _allowed(String c) {
    if (RegExp(r'[0-9]').hasMatch(c)) return true;
    if (phone) return c == '+' || c == '-' || c == ' ';
    if (decimal && c == '.') return true;
    return signed && c == '-';
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final ascii = toAscii(newValue.text);
    final buffer = StringBuffer();
    var cursor = newValue.selection.baseOffset;
    for (var i = 0; i < ascii.length; i++) {
      if (_allowed(ascii[i])) {
        buffer.write(ascii[i]);
      } else if (i < newValue.selection.baseOffset) {
        cursor--;
      }
    }
    final text = buffer.toString();
    if (text == newValue.text) return newValue;
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: cursor.clamp(0, text.length)),
    );
  }
}

const digitsOnly = <TextInputFormatter>[NumericInputFormatter()];
const decimalOnly = <TextInputFormatter>[NumericInputFormatter(decimal: true)];
const signedDigitsOnly = <TextInputFormatter>[NumericInputFormatter(signed: true)];
const phoneOnly = <TextInputFormatter>[NumericInputFormatter(phone: true)];
