import 'package:client/data/data.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/widgets.dart';
import '../today/widgets/alertness_score_card.dart';
import '../today/widgets/live_alertness_card.dart';
import 'navigation_preview_page.dart';
import 'widgets/gallery_section.dart';

class ThemeGalleryPage extends StatelessWidget {
  const ThemeGalleryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Design system')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
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
          GallerySection(title: 'Thanh điều hướng', children: [_NavSamples()]),
          GallerySection(title: 'Màu', children: [_ColorPalette()]),
          GallerySection(title: 'Chữ', children: [_TypeScale()]),
          GallerySection(title: 'Thẻ', children: [_CardSamples()]),
          GallerySection(title: 'Nút', children: [_ButtonSamples()]),
          GallerySection(title: 'Badge', children: [_BadgeSamples()]),
          GallerySection(
            title: 'Widget Material theo theme',
            children: [_MaterialSamples()],
          ),
        ],
      ),
    );
  }
}

class _NavSamples extends StatefulWidget {
  const _NavSamples();

  @override
  State<_NavSamples> createState() => _NavSamplesState();
}

class _NavSamplesState extends State<_NavSamples> {
  BrutalNavTab _currentTab = BrutalNavTab.today;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MediaQuery.removePadding(
          context: context,
          removeBottom: true,
          child: BrutalBottomNavBar(
            currentTab: _currentTab,
            onTabSelected: (tab) => setState(() => _currentTab = tab),
          ),
        ),
        BrutalButton(
          label: 'Mở khung 4 tab',
          icon: Icons.open_in_new_rounded,
          color: AppColors.white,
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const NavigationPreviewPage(),
            ),
          ),
        ),
      ],
    );
  }
}

class _ColorPalette extends StatelessWidget {
  const _ColorPalette();

  static const List<(String, Color)> _swatches = [
    ('cream', AppColors.cream),
    ('teal', AppColors.teal),
    ('green', AppColors.green),
    ('coral', AppColors.coral),
    ('yellow', AppColors.yellow),
    ('white', AppColors.white),
    ('ink', AppColors.ink),
    ('slate', AppColors.slate),
    ('inkMuted', AppColors.inkMuted),
    ('disabled', AppColors.disabled),
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
                            top: Radius.circular(
                              AppRadii.card - AppBorders.width,
                            ),
                          ),
                          border: const Border(bottom: AppBorders.side),
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
    ('display · ExtraBold', AppTypography.display, '72%'),
    ('title · ExtraBold', AppTypography.title, 'Chào buổi sáng'),
    ('subtitle · ExtraBold', AppTypography.subtitle, 'Kiểm tra lại lịch học'),
    (
      'body · Regular',
      AppTypography.body,
      'Nên ôn bài khó lúc 9:00 – 11:00 khi bạn tỉnh táo nhất.',
    ),
    ('label · SemiBold', AppTypography.label, 'Giờ vàng 9:00 – 11:30'),
    ('caption · Regular', AppTypography.caption, 'Cập nhật lúc 07:30'),
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
          color: AppColors.teal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Giải tích 1', style: AppTypography.subtitle),
              SizedBox(height: AppSpacing.xxs),
              Text(
                'Phòng B3 · 201 · Thứ Hai 07:30 – 09:30',
                style: AppTypography.body,
              ),
            ],
          ),
        ),
        SizedBox(height: AppSpacing.md),
        BrutalCard(
          color: AppColors.yellow,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Lập trình Python', style: AppTypography.subtitle),
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
          color: AppColors.cream,
          borderStyle: BrutalBorderStyle.dashed,
          hasShadow: false,
          child: Column(
            children: [
              Icon(Icons.photo_camera_outlined, size: 32),
              SizedBox(height: AppSpacing.xs),
              Text(
                'Chụp ảnh thời khóa biểu của bạn',
                textAlign: TextAlign.center,
                style: AppTypography.label,
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
          color: AppColors.white,
          onPressed: () => _announce(context, 'Chọn từ thư viện'),
        ),
        const SizedBox(height: AppSpacing.md),
        BrutalButton(
          label: 'Nhập bằng giọng nói',
          icon: Icons.mic_none_rounded,
          color: AppColors.yellow,
          onPressed: () => _announce(context, 'Nhập bằng giọng nói'),
        ),
        const SizedBox(height: AppSpacing.md),
        BrutalButton(
          label: 'Xóa',
          icon: Icons.delete_outline_rounded,
          color: AppColors.coral,
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
        const BrutalBadge(label: 'Giờ vàng', color: AppColors.green),
        const BrutalBadge(label: 'AI xếp', color: AppColors.teal),
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
              child: Text('Nhắc đi ngủ', style: AppTypography.subtitle),
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
