import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../core/theme/theme.dart';
import '../../core/widgets/widgets.dart';
import 'widgets/alertness_score_card.dart';
import 'widgets/gallery_section.dart';
import 'widgets/live_alertness_card.dart';

class ThemeGalleryPage extends StatelessWidget {
  const ThemeGalleryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recolly · Design system')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.xxl,
        ),
        children: const [
          GallerySection(
            title: 'Dữ liệu mock · GET /home',
            children: [LiveAlertnessCard()],
          ),
          GallerySection(
            title: 'Trạng thái thẻ tỉnh táo',
            children: [
              AlertnessScoreCard(snapshot: AlertnessLoading()),
              AlertnessScoreCard(
                snapshot: AlertnessFailed('Không kết nối được máy chủ.'),
              ),
              AlertnessScoreCard(snapshot: AlertnessUnavailable()),
            ],
          ),
          GallerySection(title: 'Màu', children: [_ColorPalette()]),
          GallerySection(title: 'Chữ', children: [_TypeScale()]),
          GallerySection(title: 'Thẻ', children: [_CardSamples()]),
          GallerySection(title: 'Nút', children: [_ButtonSamples()]),
          GallerySection(
            title: 'Badge chronotype',
            children: [_BadgeSamples()],
          ),
          GallerySection(
            title: 'Widget Material theo theme',
            children: [_MaterialSamples()],
          ),
        ],
      ),
    );
  }
}

class _ColorPalette extends StatelessWidget {
  const _ColorPalette();

  static const List<(String, Color)> _swatches = [
    ('ink', AppColors.ink),
    ('canvas', AppColors.canvas),
    ('paper', AppColors.paper),
    ('lagoon', AppColors.lagoon),
    ('lime', AppColors.lime),
    ('sunflower', AppColors.sunflower),
    ('coral', AppColors.coral),
    ('slate', AppColors.slate),
    ('disabled', AppColors.disabled),
    ('inkMuted', AppColors.inkMuted),
  ];

  static String _hexOf(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - AppSpacing.md) / 2;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final (name, color) in _swatches)
              SizedBox(
                width: tileWidth,
                child: BrutalCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        height: 56,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(AppRadii.md - 2),
                          ),
                          border: const Border(bottom: AppBorders.regular),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(AppSpacing.xs),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(name, style: AppTypography.label),
                            Text(_hexOf(color), style: AppTypography.caption),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _TypeScale extends StatelessWidget {
  const _TypeScale();

  static const List<(String, TextStyle, String)> _samples = [
    ('display', AppTypography.display, '72%'),
    ('headline', AppTypography.headline, 'Chào buổi sáng'),
    ('title', AppTypography.title, 'Kiểm tra lại lịch học'),
    (
      'body',
      AppTypography.body,
      'Nên ôn bài khó lúc 9:00 – 11:00 khi bạn tỉnh táo nhất.',
    ),
    ('label', AppTypography.label, 'Giờ vàng 9:00 – 11:30'),
    ('caption', AppTypography.caption, 'Cập nhật lúc 07:30'),
  ];

  @override
  Widget build(BuildContext context) {
    return BrutalCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (name, style, sample) in _samples)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$name · ${style.fontSize!.toStringAsFixed(0)}',
                    style: AppTypography.caption,
                  ),
                  Text(sample, style: style),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CardSamples extends StatelessWidget {
  const _CardSamples();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrutalCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Giải tích 1', style: AppTypography.title),
              SizedBox(height: AppSpacing.xxs),
              Text(
                'Phòng B3 · 201 · Thứ Hai 07:30 – 09:30',
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.md),
        BrutalCard(
          color: AppColors.sunflower,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lập trình Python', style: AppTypography.title),
              SizedBox(height: AppSpacing.xxs),
              Text(
                'Phòng C5 · 302 · Thứ Tư 09:30 – 11:30',
                style: AppTypography.body,
              ),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.md),
        BrutalCard(
          color: AppColors.slate,
          child: Row(
            children: [
              Icon(Icons.bedtime_rounded, color: AppColors.onSlate),
              SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Giấc ngủ 23:30 – 06:30',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.onSlate,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ButtonSamples extends StatelessWidget {
  const _ButtonSamples();

  void _announce(BuildContext context, String label) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Đã bấm: $label')));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BrutalButton(
          label: 'Tiếp tục',
          icon: Icons.arrow_forward_rounded,
          onPressed: () => _announce(context, 'Tiếp tục'),
        ),
        const SizedBox(height: AppSpacing.md),
        BrutalButton(
          label: 'Chọn từ thư viện',
          icon: Icons.photo_library_outlined,
          variant: BrutalButtonVariant.secondary,
          onPressed: () => _announce(context, 'Chọn từ thư viện'),
        ),
        const SizedBox(height: AppSpacing.md),
        BrutalButton(
          label: 'Hủy',
          variant: BrutalButtonVariant.ghost,
          onPressed: () => _announce(context, 'Hủy'),
        ),
        const SizedBox(height: AppSpacing.md),
        BrutalButton(
          label: 'Xóa',
          icon: Icons.delete_outline_rounded,
          variant: BrutalButtonVariant.danger,
          onPressed: () => _announce(context, 'Xóa'),
        ),
        const SizedBox(height: AppSpacing.md),
        const BrutalButton(label: 'Đang khóa', onPressed: null),
      ],
    );
  }
}

class _BadgeSamples extends StatelessWidget {
  const _BadgeSamples();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final chronotype in Chronotype.values)
          ChronotypeBadge(chronotype: chronotype),
        const BrutalBadge(label: 'Giờ vàng', color: AppColors.lime),
        const BrutalBadge(label: 'Trễ hạn', color: AppColors.coral),
      ],
    );
  }
}

class _MaterialSamples extends StatefulWidget {
  const _MaterialSamples();

  @override
  State<_MaterialSamples> createState() => _MaterialSamplesState();
}

class _MaterialSamplesState extends State<_MaterialSamples> {
  bool _isReminderEnabled = true;
  bool _isDeadlineChipSelected = true;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const TextField(
          decoration: InputDecoration(
            labelText: 'Tên môn',
            hintText: 'Vật lý đại cương',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            const Expanded(
              child: Text('Nhắc đi ngủ', style: AppTypography.title),
            ),
            Switch(
              value: _isReminderEnabled,
              onChanged: (value) => setState(() => _isReminderEnabled = value),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.xs,
          children: [
            FilterChip(
              label: const Text('Deadline'),
              selected: _isDeadlineChipSelected,
              onSelected: (value) =>
                  setState(() => _isDeadlineChipSelected = value),
            ),
            FilledButton(onPressed: () {}, child: const Text('FilledButton')),
          ],
        ),
      ],
    );
  }
}
