import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../../../data/models/page_template.dart';
import '../../editor/draft/image_tools.dart';
import '../data/admin_repository.dart';

/// Upload the 300 DPI page designs of a product in one go. Files are matched
/// by name: p01.jpg … p34.jpg for the pages, cover.jpg for the front cover.
Future<void> showPrintFilesDialog(BuildContext context, String slug) =>
    showDialog<void>(context: context, builder: (_) => _PrintFilesDialog(slug: slug));

final _printTemplatesProvider = FutureProvider.autoDispose
    .family<List<PageTemplate>, String>((ref, slug) => ref.watch(adminRepositoryProvider).printTemplatesBySlug(slug));

/// Page number a file name refers to: 0 = cover, null = unknown.
int? pageOfFile(String name) {
  final n = name.toLowerCase();
  if (RegExp(r'cover|front|غلاف').hasMatch(n)) return 0;
  final m = RegExp(r'p\s*0*(\d{1,3})').firstMatch(n) ?? RegExp(r'^0*(\d{1,3})\b').firstMatch(n);
  return m == null ? null : int.parse(m.group(1)!);
}

class _PrintFilesDialog extends ConsumerStatefulWidget {
  const _PrintFilesDialog({required this.slug});
  final String slug;
  @override
  ConsumerState<_PrintFilesDialog> createState() => _PrintFilesDialogState();
}

class _PrintFilesDialogState extends ConsumerState<_PrintFilesDialog> {
  bool _busy = false;
  int _done = 0, _total = 0;
  final _problems = <String>[];

  Future<void> _upload(List<PageTemplate> templates) async {
    final files = await pickFiles(accept: 'image/jpeg,image/png', multiple: true);
    if (files.isEmpty) return;
    final repo = ref.read(adminRepositoryProvider);
    setState(() {
      _busy = true;
      _done = 0;
      _total = files.length;
      _problems.clear();
    });
    for (final f in files) {
      final page = pageOfFile(f.name);
      final t = page == null
          ? null
          : templates.where((t) => page == 0 ? t.isCover : (!t.isCover && t.pageNumber == page)).firstOrNull;
      if (t == null) {
        _problems.add('${f.name}: لم أعرف أي صفحة هذه (سمِّ الملف p01.jpg … أو cover.jpg)');
      } else if (f.size > 40 * 1024 * 1024) {
        _problems.add('${f.name}: أكبر من 40 ميغابايت');
      } else {
        try {
          await repo.uploadPrintFile(t, widget.slug, await blobBytes(f), f.type.isEmpty ? 'image/jpeg' : f.type);
        } catch (_) {
          _problems.add('${f.name}: تعذّر الرفع');
        }
      }
      if (mounted) setState(() => _done++);
    }
    ref.invalidate(_printTemplatesProvider(widget.slug));
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final list = ref.watch(_printTemplatesProvider(widget.slug));
    return AlertDialog(
      title: const Text('ملفات الطباعة (300 DPI)'),
      content: SizedBox(
        width: 520,
        child: list.when(
          loading: () => const SizedBox(height: 120, child: Center(child: CircularProgressIndicator())),
          error: (_, _) => const Text('تعذّر التحميل.'),
          data: (templates) {
            final have = templates.where((x) => x.printPath != null).length;
            return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                  'هذه ملفات التصميم بدقتها الكاملة، تُستخدم فقط لتجهيز ملفات الطباعة ولا يراها الزبائن. '
                  'سمِّ الملفات p01.jpg إلى p${(templates.length - 1).toString().padLeft(2, '0')}.jpg، '
                  'والغلاف cover.jpg، واخترها كلها مرة واحدة.',
                  style: t.bodySmall),
              const SizedBox(height: NSpace.md),
              Text('مرفوع: $have من ${templates.length}', style: t.titleSmall),
              const SizedBox(height: NSpace.sm),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final x in templates)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    avatar: Icon(x.printPath != null ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
                        size: 16, color: x.printPath != null ? NColors.success : NColors.inkMuted),
                    label: Text(x.isCover ? 'الغلاف' : '${x.pageNumber}'),
                  ),
              ]),
              if (_busy) ...[
                const SizedBox(height: NSpace.md),
                LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
                Text('نرفع $_done من $_total…', style: t.bodySmall),
              ],
              if (_problems.isNotEmpty) ...[
                const SizedBox(height: NSpace.md),
                for (final p in _problems) Text('• $p', style: t.bodySmall?.copyWith(color: NColors.danger)),
              ],
            ]);
          },
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('إغلاق')),
        FilledButton.icon(
          onPressed: _busy || !list.hasValue ? null : () => _upload(list.value!),
          icon: const Icon(Icons.upload_rounded),
          label: const Text('اختيار الملفات'),
        ),
      ],
    );
  }
}
