from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected exactly one match, found {count}')
    return text.replace(old, new, 1)


backend_path = Path('lib/services/vet_backend.dart')
backend = backend_path.read_text()
backend = replace_once(
    backend,
    "  Future<AuthResponse> refreshAuthSession() => client.auth.refreshSession();\n\n  Future<Map<String, dynamic>?> myProfile() async {",
    """  Future<AuthResponse> refreshAuthSession() => client.auth.refreshSession();

  Future<void> sendPasswordReset(String email) {
    return client.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: authCallbackUrl,
    );
  }

  Future<UserResponse> updatePassword(String password) {
    return client.auth.updateUser(UserAttributes(password: password));
  }

  Future<Map<String, dynamic>?> myProfile() async {""",
    'backend password helpers',
)
backend_path.write_text(backend)


app_path = Path('lib/v5_app.dart')
app = app_path.read_text()

app = replace_once(
    app,
    """      builder: (context, _) {
        if (!VetBackend.instance.signedIn) return const V5AuthScreen();""",
    """      builder: (context, snapshot) {
        if (snapshot.data?.event == AuthChangeEvent.passwordRecovery && VetBackend.instance.signedIn) {
          return const V5PasswordRecoveryScreen();
        }
        if (!VetBackend.instance.signedIn) return const V5AuthScreen();""",
    'auth gate recovery routing',
)

app = replace_once(
    app,
    "  bool resending = false;\n  String? confirmationEmail;",
    "  bool resending = false;\n  bool resettingPassword = false;\n  String? confirmationEmail;",
    'reset state field',
)

app = replace_once(
    app,
    "  Future<void> submit() async {",
    """  Future<void> sendPasswordReset() async {
    FocusScope.of(context).unfocus();
    final target = email.text.trim();
    if (target.isEmpty) {
      _snack(
        tr(context, 'Enter your email address first.', 'اكتب بريدك الإلكتروني الأول.', 'Vul eerst je e-mailadres in.'),
        true,
      );
      return;
    }
    setState(() => resettingPassword = true);
    try {
      await VetBackend.instance.sendPasswordReset(target);
      if (!mounted) return;
      _snack(
        tr(
          context,
          'If an account exists for this email, Vet AI has sent a password reset link. Open the newest email and return to the app from that link.',
          'إذا كان هناك حساب بهذا البريد، أرسل Vet AI رابط تغيير كلمة المرور. افتح أحدث رسالة وارجع للتطبيق من الرابط الموجود فيها.',
          'Als er een account voor dit e-mailadres bestaat, heeft Vet AI een link gestuurd om het wachtwoord te wijzigen. Open de nieuwste e-mail en keer via die link terug naar de app.',
        ),
        false,
      );
    } on AuthException catch (e) {
      if (mounted) _snack(_friendlyAuth(e), true);
    } catch (_) {
      if (mounted) {
        _snack(
          tr(context, 'Could not start password recovery.', 'تعذر بدء استعادة كلمة المرور.', 'Wachtwoordherstel kon niet worden gestart.'),
          true,
        );
      }
    } finally {
      if (mounted) setState(() => resettingPassword = false);
    }
  }

  Future<void> submit() async {""",
    'password reset request method',
)

old_fields = """            _Field(controller: password, label: tr(context, 'Password', 'كلمة المرور', 'Wachtwoord'), icon: Icons.lock_outline_rounded, obscure: true, onSubmitted: (_) => submit()),
            const SizedBox(height: 20),
            ElevatedButton.icon("""
new_fields = """            _Field(controller: password, label: tr(context, 'Password', 'كلمة المرور', 'Wachtwoord'), icon: Icons.lock_outline_rounded, obscure: true, onSubmitted: (_) => submit()),
            if (!create) ...[
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: busy || resettingPassword ? null : sendPasswordReset,
                  icon: resettingPassword
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.key_rounded, size: 22),
                  label: Text(tr(context, 'Forgot password?', 'نسيت كلمة المرور؟', 'Wachtwoord vergeten?')),
                ),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton.icon("""
app = replace_once(app, old_fields, new_fields, 'forgot password button')

screen_anchor = "class V5VerifyScreen extends StatelessWidget {"
if screen_anchor not in app:
    raise SystemExit('recovery screen insertion anchor not found')
recovery_screen = r'''class V5PasswordRecoveryScreen extends StatefulWidget {
  const V5PasswordRecoveryScreen({super.key});

  @override
  State<V5PasswordRecoveryScreen> createState() => _V5PasswordRecoveryScreenState();
}

class _V5PasswordRecoveryScreenState extends State<V5PasswordRecoveryScreen> {
  final password = TextEditingController();
  final confirm = TextEditingController();
  bool busy = false;
  bool done = false;

  @override
  void dispose() {
    password.dispose();
    confirm.dispose();
    super.dispose();
  }

  Future<void> save() async {
    FocusScope.of(context).unfocus();
    final next = password.text;
    if (next.length < 8) {
      _snack(tr(context, 'Use at least 8 characters.', 'استخدم 8 أحرف على الأقل.', 'Gebruik minimaal 8 tekens.'), true);
      return;
    }
    if (next != confirm.text) {
      _snack(tr(context, 'The passwords do not match.', 'كلمتا المرور غير متطابقتين.', 'De wachtwoorden komen niet overeen.'), true);
      return;
    }
    setState(() => busy = true);
    try {
      await VetBackend.instance.updatePassword(next);
      if (!mounted) return;
      password.clear();
      confirm.clear();
      setState(() => done = true);
    } on AuthException catch (e) {
      if (mounted) _snack(e.message, true);
    } catch (_) {
      if (mounted) {
        _snack(tr(context, 'Could not update the password.', 'تعذر تحديث كلمة المرور.', 'Het wachtwoord kon niet worden bijgewerkt.'), true);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _snack(String text, bool error) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Theme.of(context).colorScheme.error : VetColors.surface2,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(children: [const _MiniBrand(), const SizedBox(width: 12), Text(tr(context, 'Reset password', 'تغيير كلمة المرور', 'Wachtwoord wijzigen'))]),
        actions: [IconButton(onPressed: busy ? null : () => showVetLanguagePicker(context), icon: const Icon(Icons.language_rounded, color: VetColors.blue))],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
          children: [
            if (done) ...[
              _Notice(
                icon: Icons.verified_user_rounded,
                title: tr(context, 'Password updated', 'تم تحديث كلمة المرور', 'Wachtwoord bijgewerkt'),
                text: tr(
                  context,
                  'Your new password is active. Continue securely to Vet AI.',
                  'كلمة المرور الجديدة أصبحت فعالة. يمكنك المتابعة بأمان إلى Vet AI.',
                  'Je nieuwe wachtwoord is actief. Ga veilig verder naar Vet AI.',
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const V5AuthGate())),
                icon: const Icon(Icons.arrow_forward_rounded, size: 27),
                label: Text(tr(context, 'Continue to Vet AI', 'متابعة إلى Vet AI', 'Doorgaan naar Vet AI')),
              ),
            ] else ...[
              _StepTitle(
                icon: Icons.lock_reset_rounded,
                title: tr(context, 'Choose a new password', 'اختر كلمة مرور جديدة', 'Kies een nieuw wachtwoord'),
                subtitle: tr(
                  context,
                  'This screen is shown only after opening a valid Vet AI recovery link.',
                  'تظهر هذه الشاشة فقط بعد فتح رابط استعادة صالح من Vet AI.',
                  'Dit scherm verschijnt alleen nadat je een geldige Vet AI-herstellink hebt geopend.',
                ),
              ),
              const SizedBox(height: 20),
              _Field(controller: password, label: tr(context, 'New password', 'كلمة المرور الجديدة', 'Nieuw wachtwoord'), icon: Icons.lock_outline_rounded, obscure: true),
              const SizedBox(height: 12),
              _Field(controller: confirm, label: tr(context, 'Confirm new password', 'تأكيد كلمة المرور الجديدة', 'Bevestig nieuw wachtwoord'), icon: Icons.lock_reset_outlined, obscure: true, onSubmitted: (_) => save()),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: busy ? null : save,
                icon: busy
                    ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.password_rounded, size: 28),
                label: Text(tr(context, 'Update password', 'تحديث كلمة المرور', 'Wachtwoord bijwerken')),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

'''
app = app.replace(screen_anchor, recovery_screen + screen_anchor, 1)
app_path.write_text(app)
print('V19 password recovery patch applied.')
