import 'package:flutter/material.dart';

/// The label/value grid shared by `TicketWidget`, `TaskInstanceTicketWidget`,
/// and `ReceiptWidget` — both are thermal-ticket layouts printed through
/// the same `PosPrinterService` path, so they share this instead of each
/// carrying its own copy.
///
/// Replaces the earlier borderless `ticketRow()` (one `Row` per line,
/// stacked in a `Column`) with a real bordered `Table` (2026-08-29, by
/// request: the info should read as an actual جدول, and its text was too
/// small). Font size bumped 18 -> 22 for the same request; the value
/// column keeps its `TextOverflow.ellipsis` safety net, so a long value
/// truncates rather than overflowing the fixed ticket width.
Widget ticketTable(List<(String label, String value)> rows) {
  return Table(
    border: TableBorder.all(color: Colors.black, width: 1),
    columnWidths: const {0: IntrinsicColumnWidth(), 1: FlexColumnWidth()},
    children: [
      for (final (label, value) in rows)
        TableRow(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                label,
                style: const TextStyle(color: Colors.black, fontSize: 22, fontWeight: FontWeight.w600),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Text(
                value,
                style: const TextStyle(color: Colors.black, fontSize: 22),
                textAlign: TextAlign.left,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
    ],
  );
}
