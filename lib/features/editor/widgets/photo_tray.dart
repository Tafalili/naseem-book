import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../draft/draft_controller.dart';

/// Grid of the customer's uploaded photos. Tap assigns; long-press removes.
class PhotoTray extends ConsumerWidget {
  const PhotoTray({super.key, required this.onPick, this.dense = false});
  final void Function(String photoId) onPick;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final st = ref.watch(draftProvider);
    final d = st.draft;
    if (d == null) return const SizedBox.shrink();
    final used = d.usedPhotoIds;
    final size = dense ? 64.0 : 76.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('صوري (${d.photos.length})', style: t.titleSmall),
            const Spacer(),
            if (st.importing > 0) ...[
              const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: NSpace.sm),
              Text('جارٍ تجهيز ${st.importing}', style: t.labelSmall),
            ],
          ],
        ),
        const SizedBox(height: NSpace.sm),
        OutlinedButton.icon(
          onPressed: () => ref.read(draftProvider.notifier).importPhotos(),
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: const Text('أضيفي صوراً من جهازك'),
        ),
        if (st.error != null) ...[
          const SizedBox(height: NSpace.xs),
          Text(st.error!, style: t.bodySmall?.copyWith(color: NColors.danger)),
        ],
        const SizedBox(height: NSpace.sm),
        if (d.photos.isEmpty)
          Text('صورك تبقى على جهازك حتى ترسلي الطلب.', style: t.bodySmall)
        else
          Wrap(
            spacing: NSpace.sm,
            runSpacing: NSpace.sm,
            children: [
              for (final p in d.photos)
                _Thumb(
                  id: p.id,
                  size: size,
                  used: used.contains(p.id),
                  onTap: () => onPick(p.id),
                  onRemove: () => ref.read(draftProvider.notifier).removePhoto(p.id),
                ),
            ],
          ),
      ],
    );
  }
}

class _Thumb extends ConsumerWidget {
  const _Thumb({
    required this.id,
    required this.size,
    required this.used,
    required this.onTap,
    required this.onRemove,
  });
  final String id;
  final double size;
  final bool used;
  final VoidCallback onTap, onRemove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(photoPreviewProvider(id)).value;
    return Tooltip(
      message: 'اضغطي للوضع في الإطار المحدد',
      child: GestureDetector(
        onTap: onTap,
        child: Stack(
          children: [
            Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(NRadius.sm),
                border: Border.all(color: used ? NColors.sage : NColors.line, width: used ? 2 : 1),
                color: NColors.surfaceAlt,
                image: bytes == null
                    ? null
                    : DecorationImage(image: MemoryImage(bytes), fit: BoxFit.cover),
              ),
            ),
            if (used)
              const PositionedDirectional(
                bottom: 4,
                start: 4,
                child: CircleAvatar(
                  radius: 9,
                  backgroundColor: NColors.sage,
                  child: Icon(Icons.check, size: 12, color: Colors.white),
                ),
              ),
            PositionedDirectional(
              top: 0,
              end: 0,
              child: InkWell(
                onTap: onRemove,
                customBorder: const CircleBorder(),
                child: Container(
                  margin: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: Color(0xAA000000), shape: BoxShape.circle),
                  padding: const EdgeInsets.all(2),
                  child: const Icon(Icons.close, size: 13, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
