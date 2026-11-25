import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// One row of a [BrutalConfirmTable].
class ConfirmRow {
  const ConfirmRow({
    required this.cells,
    this.selected,
    this.needsCheck = false,
    this.onTap,
    this.onSelected,
  });

  /// One text per column, same order as the table headers.
  final List<String> cells;

  /// `null` hides the checkbox for this row.
  final bool? selected;

  /// Highlights a row the server was unsure about (low OCR confidence).
  final bool needsCheck;

  /// Opens an editor for this row.
  final VoidCallback? onTap;
  final ValueChanged<bool>? onSelected;
}

/// Neo-brutalist table the user reads to confirm what the server
/// understood (OCR timetable, voice todo) before anything is saved.
class BrutalConfirmTable extends StatelessWidget {
  const BrutalConfirmTable({
    super.key,
    required this.headers,
    required this.rows,
    this.columnFlex,
  });

  final List<String> headers;
  final List<ConfirmRow> rows;

  /// Relative column widths; equal when `null`.
  final List<int>? columnFlex;

  bool get _hasCheckboxes => rows.any((row) => row.selected != null);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppTheme.brutalBox(color: AppColors.white),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _line(
            color: AppColors.yellow,
            leading: _hasCheckboxes ? const SizedBox(width: 40) : null,
            cells: [
              for (final h in headers)
                Text(
                  h,
                  style: AppTypography.label.copyWith(
                    fontWeight: AppTypography.extraBold,
                  ),
                ),
            ],
          ),
          for (final row in rows) ...[
            const Divider(height: 2, thickness: 2, color: AppColors.ink),
            Material(
              color: row.needsCheck ? AppColors.coral : AppColors.white,
              child: InkWell(
                onTap: row.onTap,
                child: _line(
                  leading: !_hasCheckboxes
                      ? null
                      : SizedBox(
                          width: 40,
                          child: row.selected == null
                              ? null
                              : Checkbox(
                                  value: row.selected,
                                  onChanged: (v) =>
                                      row.onSelected?.call(v ?? false),
                                ),
                        ),
                  cells: [
                    for (final cell in row.cells)
                      Text(cell, style: AppTypography.body),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // One table line: optional checkbox column, then the flexible cells.
  Widget _line({required List<Widget> cells, Widget? leading, Color? color}) {
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          ?leading,
          for (var i = 0; i < cells.length; i++)
            Expanded(
              flex: columnFlex?[i] ?? 1,
              child: Padding(
                padding: const EdgeInsets.only(right: AppSpacing.xs),
                child: cells[i],
              ),
            ),
        ],
      ),
    );
  }
}
