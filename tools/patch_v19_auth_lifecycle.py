from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if text.count(old) != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {text.count(old)}')
    return text.replace(old, new, 1)


backend_path = Path('lib/services/vet_backend.dart')
backend = backend_path.read_text()
backend = replace_once(
    backend,
    "  Future<void> signOut() => client.auth.signOut();\n\n  Future<Map<String, dynamic>?> myProfile() async {",
    """  Future<void> signOut() => client.auth.signOut();

  Future<ResendResponse> resendSignupConfirmation(String email) {
    return client.auth.resend(
      type: OtpType.signup,
      email: email.trim(),
      emailRedirectTo: authCallbackUrl,
    );
  }

  Future<AuthResponse> refreshAuthSession() => client.auth.refreshSession();

  Future<Map<String, dynamic>?> myProfile() async {""",
    'backend auth helpers',
)
backend_path.write_text(backend)


app_path = Path('lib/v5_app.dart')
app = app_path.read_text()
app = replace_once(
    app,
    "  bool create = true;\n  bool busy = false;\n  String? confirmationEmail;",
    "  bool create = true;\n  bool busy = false;\n  bool resending = false;\n  String? confirmationEmail;",
    'auth state fields',
)

app = replace_once(
    app,
    "  Future<void> submit() async {",
    """  Future<void> resendConfirmation() async {
    FocusScope.of(context).unfocus();
    final target = (confirmationEmail ?? email.text).trim();
    if (target.isEmpty) {
      _snack(
        tr(context, 'Enter the email address first.', 'اكتب البريد الإلكتروني الأول.', 'Vul eerst het e-mailadres in.'),
        true,
      );
      return;
    }
    setState(() => resending = true);
    try {
      await VetBackend.instance.resendSignupConfirmation(target);
      if (!mounted) return;
      setState(() => confirmationEmail = target);
      _snack(
        tr(
          context,
          'A new Vet AI confirmation email was sent. Open the newest message and use its confirmation button.',
          'تم إرسال رسالة تفعيل جديدة من Vet AI. افتح أحدث رسالة واضغط زر التفعيل الموجود فيها.',
          'Er is een nieuwe Vet AI-bevestigingsmail verzonden. Open het nieuwste bericht en gebruik de bevestigingsknop.',
        ),
        false,
      );
    } on AuthException catch (e) {
      if (mounted) _snack(_friendlyAuth(e), true);
    } catch (_) {
      if (mounted) {
        _snack(
          tr(context, 'Could not resend the confirmation email.', 'تعذر إعادة إرسال رسالة التفعيل.', 'De bevestigingsmail kon niet opnieuw worden verzonden.'),
          true,
        );
      }
    } finally {
      if (mounted) setState(() => resending = false);
    }
  }

  Future<void> submit() async {""",
    'resend confirmation method',
)

anchor = "            if (confirmationEmail != null) ...[\n"
start = app.find(anchor)
if start < 0:
    raise SystemExit('confirmation block: start anchor not found')
end = app.find("            SegmentedButton<bool>(", start)
if end < 0:
    raise SystemExit('confirmation block: end anchor not found')
segment = app[start:end]
tail = "              const SizedBox(height: 18),\n            ],\n"
if segment.count(tail) != 1:
    raise SystemExit(f'confirmation block tail: expected one match, found {segment.count(tail)}')
new_tail = """              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: busy || resending ? null : resendConfirmation,
                icon: resending
                    ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh_rounded, size: 26),
                label: Text(
                  resending
                      ? tr(context, 'Sending…', 'جاري الإرسال…', 'Verzenden…')
                      : tr(context, 'Resend confirmation email', 'إعادة إرسال رسالة التفعيل', 'Bevestigingsmail opnieuw verzenden'),
                ),
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: busy || resending ? null : () => setState(() => create = false),
                icon: const Icon(Icons.login_rounded, size: 25),
                label: Text(
                  tr(
                    context,
                    'I confirmed my email — sign in',
                    'فعّلت البريد — تسجيل الدخول',
                    'Ik heb mijn e-mail bevestigd — inloggen',
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ],
"""
segment = segment.replace(tail, new_tail, 1)
app = app[:start] + segment + app[end:]

app_path.write_text(app)
print('V19 auth lifecycle patch applied.')
