import 'package:flutter/material.dart';

/// One "label: value" line shared by `TicketWidget` and `ReceiptWidget` —
/// both are thermal-ticket layouts printed through the same
/// `PosPrinterService` path, so they share this row instead of each
/// carrying its own copy.
Widget ticketRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('$label:', style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.w600)),
        Flexible(
          child: Text(
            value,
            style: const TextStyle(color: Colors.black, fontSize: 18),
            textAlign: TextAlign.left,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}
