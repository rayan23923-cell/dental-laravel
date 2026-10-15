import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// Where tickets and slips can be printed from the app (2026-10-12): the
/// phones/POS terminals through the native printer plugin, and Windows
/// through the system printers (`desktop_ticket_printer.dart`).
bool get canPrintTickets => !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isWindows);

/// Windows desktop build: no `mobile_scanner` camera and no native POS
/// plugin, so scanning and printing take the desktop paths instead.
bool get isWindowsDesktop => !kIsWeb && Platform.isWindows;
