import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/theme/tokens.dart';
import 'data/admin_repository.dart';

class AdminLoginPage extends ConsumerStatefulWidget {
  const AdminLoginPage({super.key});
  @override
  ConsumerState<AdminLoginPage> createState() => _AdminLoginPageState();
}

class _AdminLoginPageState extends ConsumerState<AdminLoginPage> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false, _hide = true;
  String? _error;

  Future<void> _submit() async {
    if (_email.text.trim().isEmpty || _password.text.isEmpty) {
      setState(() => _error = 'اكتب البريد وكلمة المرور.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(adminRepositoryProvider).signIn(_email.text, _password.text);
      ref.invalidate(adminMeProvider);
    } on AdminFailure catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(NSpace.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Container(
              padding: const EdgeInsets.all(NSpace.lg),
              decoration: BoxDecoration(
                color: NColors.surface,
                borderRadius: const BorderRadius.all(NRadius.lg),
                border: Border.all(color: NColors.line),
                boxShadow: NShadow.soft,
              ),
              child: AutofillGroup(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.menu_book_rounded, size: 40, color: NColors.sageDark),
                    const SizedBox(height: NSpace.sm),
                    Text('لوحة إدارة كتاب نسيم', textAlign: TextAlign.center, style: t.headlineSmall),
                    const SizedBox(height: NSpace.lg),
                    TextField(
                      controller: _email,
                      enabled: !_busy,
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'البريد الإلكتروني'),
                    ),
                    const SizedBox(height: NSpace.md),
                    TextField(
                      controller: _password,
                      enabled: !_busy,
                      obscureText: _hide,
                      textDirection: TextDirection.ltr,
                      autofillHints: const [AutofillHints.password],
                      onSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'كلمة المرور',
                        suffixIcon: IconButton(
                          tooltip: _hide ? 'إظهار' : 'إخفاء',
                          onPressed: () => setState(() => _hide = !_hide),
                          icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: NSpace.md),
                      Text(_error!, style: t.bodyMedium?.copyWith(color: NColors.danger)),
                    ],
                    const SizedBox(height: NSpace.lg),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('دخول'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
