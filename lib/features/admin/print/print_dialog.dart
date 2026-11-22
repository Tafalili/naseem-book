import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/theme/tokens.dart';
import '../data/admin_repository.dart';
import 'print_export.dart';

/// Builds and downloads the order's print package, with progress.
Future<void> showPrintDialog(BuildContext context, AdminOrder order) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PrintDialog(order: order),
    );

class _PrintDialog extends ConsumerStatefulWidget {
  const _PrintDialog({required this.order});
  final AdminOrder order;
  @override
  ConsumerState<_PrintDialog> createState() => _PrintDialogState();
}

class _PrintDialogState extends ConsumerState<_PrintDialog> {
  String _stage = 'نجهّز الملفات…';
  int _done = 0, _total = 0;
  String? _error;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    try {
      final zip = await buildPrintZip(ref.read(adminRepositoryProvider), widget.order,
          onProgress: (s, d, t) {
        if (mounted) {
          setState(() {
            _stage = s;
            _done = d;
            _total = t;
          });
        }
      });
      saveFile(zip, 'naseem_${widget.order.row.code}_print.zip', 'application/zip');
      if (mounted) setState(() => _finished = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'تعذّر تجهيز ملفات الطباعة. تأكد من الإنترنت وحاول مجدداً.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final books = widget.order.books.length;
    return AlertDialog(
      title: const Text('ملفات الطباعة'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (_error != null)
            Text(_error!, style: t.bodyMedium?.copyWith(color: NColors.danger))
          else if (_finished) ...[
            const Icon(Icons.check_circle_rounded, color: NColors.success, size: 40),
            const SizedBox(height: NSpace.sm),
            Text('تم تنزيل الملف. فيه ${books > 1 ? 'مجلد لكل كتاب، وفي كل مجلد ' : ''}'
                'الغلاف وكل الصفحات على A4 بدقة 300، جاهزة للطباعة على الوجهين، مع ملف معلومات الطلب.',
                style: t.bodyMedium),
          ] else ...[
            LinearProgressIndicator(
              value: _total == 0 ? null : _done / _total,
              minHeight: 6,
              borderRadius: const BorderRadius.all(NRadius.pill),
            ),
            const SizedBox(height: NSpace.sm),
            Text(_total == 0 ? _stage : '$_stage ($_done من $_total)', style: t.bodyMedium),
            const SizedBox(height: NSpace.xs),
            Text('أبقِ هذه الصفحة مفتوحة حتى يكتمل التنزيل.', style: t.bodySmall),
          ],
        ]),
      ),
      actions: [
        if (_finished || _error != null)
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
      ],
    );
  }
}
