import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import 'core/router/app_router.dart';
import 'core/storage/web_storage.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/tokens.dart';

class NaseemApp extends ConsumerWidget {
  const NaseemApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'كتاب نسيم',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: ref.watch(appRouterProvider),
      locale: const Locale('ar', 'IQ'),
      supportedLocales: const [Locale('ar', 'IQ'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: WebStorage.available ? child! : _NoStorageNotice(child: child!),
      ),
    );
  }
}

/// Safari with "Block All Cookies" (or similar) can't keep drafts: say so once.
class _NoStorageNotice extends StatefulWidget {
  const _NoStorageNotice({required this.child});
  final Widget child;

  @override
  State<_NoStorageNotice> createState() => _NoStorageNoticeState();
}

class _NoStorageNoticeState extends State<_NoStorageNotice> {
  bool _open = true;

  @override
  Widget build(BuildContext context) {
    if (!_open) return widget.child;
    return Column(children: [
      Material(
        color: NColors.sandSoft,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 4, 8),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded, size: 20, color: NColors.ink),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'متصفحك يمنع حفظ البيانات، فتصميمك يضيع إذا أغلقتِ الصفحة. '
                  'لحفظه: الإعدادات ← سفاري ← أطفئي «حظر كل ملفات تعريف الارتباط».',
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: NColors.ink),
                ),
              ),
              // No IconButton: its tooltip needs an Overlay, which sits below this builder.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _open = false),
                child: const Padding(
                  padding: EdgeInsets.all(10),
                  child: Icon(Icons.close_rounded, size: 18, color: NColors.ink),
                ),
              ),
            ]),
          ),
        ),
      ),
      Expanded(child: MediaQuery.removePadding(context: context, removeTop: true, child: widget.child)),
    ]);
  }
}
