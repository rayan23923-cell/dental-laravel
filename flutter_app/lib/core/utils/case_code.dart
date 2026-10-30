/// The short, typeable twin of a case's QR (2026-10-30, by request) — a
/// supervisor whose camera can't read the code types these digits instead.
/// Same algorithm as the server's `App\Support\CaseCode` (which also turns
/// a typed code back into the QR payload):
/// - a started case: `1` + instance id + check digit;
/// - a task not started yet: `2` + digit count of the task id + task id +
///   doctor id + check digit.
/// The last digit is a Luhn check digit, so a mistyped digit is refused.
class CaseCode {
  const CaseCode._();

  static String forInstance(int instanceId) => _withCheck('1$instanceId');

  static String forPending(int taskId, int doctorId) {
    final task = '$taskId';
    return _withCheck('2${task.length}$task$doctorId');
  }

  /// Groups of three for display, e.g. `145 238`.
  static String format(String code) {
    final parts = <String>[];
    for (var i = 0; i < code.length; i += 3) {
      parts.add(code.substring(i, i + 3 > code.length ? code.length : i + 3));
    }
    return parts.join(' ');
  }

  static String _withCheck(String body) => '$body${_luhnDigit(body)}';

  static int _luhnDigit(String body) {
    var sum = 0;
    var doubleIt = true;
    for (var i = body.length - 1; i >= 0; i--) {
      var d = body.codeUnitAt(i) - 48;
      if (doubleIt) {
        d *= 2;
        if (d > 9) d -= 9;
      }
      sum += d;
      doubleIt = !doubleIt;
    }
    return (10 - sum % 10) % 10;
  }
}
