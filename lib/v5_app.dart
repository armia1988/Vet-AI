import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/vet_backend.dart';
import 'services/vet_operations.dart';
import 'services/alert_notification_service.dart';
import 'analysis/vet_analysis_report.dart';
import 'support/support_chat_v6.dart';
import 'support/support_console.dart';
import 'theme/app_theme.dart';
import 'i18n/vet_locale.dart';
import 'startup/vet_startup_experience.dart';
import 'monitoring/smart_home_vitals.dart';
import 'monitoring/sensor_alert_rules.dart';
import 'models/animal_taxonomy.dart';
import 'legal/vet_legal_pages.dart';

class VetAIAppV5 extends StatefulWidget {
  const VetAIAppV5({super.key});

  @override
  State<VetAIAppV5> createState() => _VetAIAppV5State();
}

class _VetAIAppV5State extends State<VetAIAppV5> {
  final localeController = VetLocaleController.instance;
  final translator = VetTranslator.instance;

  @override
  void initState() {
    super.initState();
    localeController.addListener(_refresh);
    translator.addListener(_refresh);
    localeController.load();
    translator.load();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    localeController.removeListener(_refresh);
    translator.removeListener(_refresh);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Vet AI',
      theme: buildVetTheme(),
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child ?? const SizedBox.shrink(),
      ),
      locale: localeController.locale,
      supportedLocales: vetSupportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeResolutionCallback: (deviceLocale, supported) {
        if (deviceLocale == null) return const Locale('en');
        for (final locale in supported) {
          if (locale.languageCode == deviceLocale.languageCode) return locale;
        }
        return const Locale('en');
      },
      home: const VetStartupExperience(child: V5AuthGate()),
    );
  }
}

String tr(BuildContext context, String en, String ar, String nl) {
  return VetTranslator.instance.text(
    localeCode: Localizations.localeOf(context).languageCode,
    en: en,
    ar: ar,
    nl: nl,
  );
}

class V5AuthGate extends StatefulWidget {
  const V5AuthGate({super.key});

  @override
  State<V5AuthGate> createState() => _V5AuthGateState();
}

class _V5AuthGateState extends State<V5AuthGate> {
  late final Stream<AuthState> authStream;

  @override
  void initState() {
    super.initState();
    authStream = VetBackend.instance.authChanges;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: authStream,
      builder: (context, snapshot) {
        if (snapshot.data?.event == AuthChangeEvent.passwordRecovery &&
            VetBackend.instance.signedIn) {
          return const V5PasswordRecoveryScreen();
        }
        if (!VetBackend.instance.signedIn) return const V5AuthScreen();
        if (!VetBackend.instance.emailConfirmed) return const V5VerifyScreen();
        return FutureBuilder<Map<String, dynamic>?>(
          future: VetBackend.instance.myFarm(),
          builder: (context, farm) {
            if (farm.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (farm.hasError) {
              return _FatalState(
                message: tr(
                  context,
                  'Could not load your farm safely. Please sign out and try again.',
                  'تعذر تحميل بيانات المزرعة بأمان. سجل الخروج وحاول مرة أخرى.',
                  'De boerderijgegevens konden niet veilig worden geladen. Log uit en probeer opnieuw.',
                ),
              );
            }
            if (farm.data == null) return const V5OnboardingScreen();
            return V5Dashboard(initialFarm: farm.data!);
          },
        );
      },
    );
  }
}

class V5AuthScreen extends StatefulWidget {
  const V5AuthScreen({super.key});

  @override
  State<V5AuthScreen> createState() => _V5AuthScreenState();
}

class _V5AuthScreenState extends State<V5AuthScreen> {
  bool create = true;
  bool busy = false;
  bool resending = false;
  bool resettingPassword = false;
  String? confirmationEmail;
  final fullName = TextEditingController();
  final phone = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();

  @override
  void dispose() {
    fullName.dispose();
    phone.dispose();
    email.dispose();
    password.dispose();
    super.dispose();
  }

  String _friendlyAuth(AuthException e) {
    final raw = e.message.toLowerCase();
    if (raw.contains('rate limit')) {
      return tr(
        context,
        'Too many confirmation emails were requested. Wait a few minutes before trying again. This limit comes from the current email provider.',
        'تم طلب رسائل تفعيل كثيرة في وقت قصير. انتظر بضع دقائق قبل المحاولة مرة أخرى. هذا الحد من مزود البريد الحالي.',
        'Er zijn te veel bevestigingsmails aangevraagd. Wacht enkele minuten en probeer opnieuw. Deze limiet komt van de huidige e-mailprovider.',
      );
    }
    if (raw.contains('confirm') && raw.contains('email')) {
      return tr(
        context,
        'Confirm your email address before signing in.',
        'أكد بريدك الإلكتروني قبل تسجيل الدخول.',
        'Bevestig eerst je e-mailadres voordat je inlogt.',
      );
    }
    return e.message;
  }

  Future<void> resendConfirmation() async {
    FocusScope.of(context).unfocus();
    final target = (confirmationEmail ?? email.text).trim();
    if (target.isEmpty) {
      _snack(
        tr(
          context,
          'Enter the email address first.',
          'اكتب البريد الإلكتروني الأول.',
          'Vul eerst het e-mailadres in.',
        ),
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
          tr(
            context,
            'Could not resend the confirmation email.',
            'تعذر إعادة إرسال رسالة التفعيل.',
            'De bevestigingsmail kon niet opnieuw worden verzonden.',
          ),
          true,
        );
      }
    } finally {
      if (mounted) setState(() => resending = false);
    }
  }

  Future<void> sendPasswordReset() async {
    FocusScope.of(context).unfocus();
    final target = email.text.trim();
    if (target.isEmpty) {
      _snack(
        tr(
          context,
          'Enter your email address first.',
          'اكتب بريدك الإلكتروني الأول.',
          'Vul eerst je e-mailadres in.',
        ),
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
          tr(
            context,
            'Could not start password recovery.',
            'تعذر بدء استعادة كلمة المرور.',
            'Wachtwoordherstel kon niet worden gestart.',
          ),
          true,
        );
      }
    } finally {
      if (mounted) setState(() => resettingPassword = false);
    }
  }

  Future<void> submit() async {
    FocusScope.of(context).unfocus();
    if (email.text.trim().isEmpty ||
        password.text.length < 6 ||
        (create && fullName.text.trim().isEmpty)) {
      _snack(
        tr(
          context,
          'Complete the required fields. Password must be at least 6 characters.',
          'أكمل البيانات المطلوبة. كلمة المرور 6 أحرف على الأقل.',
          'Vul de verplichte velden in. Het wachtwoord moet minimaal 6 tekens bevatten.',
        ),
        true,
      );
      return;
    }
    setState(() => busy = true);
    try {
      if (create) {
        final response = await VetBackend.instance.signUp(
          email: email.text,
          password: password.text,
          fullName: fullName.text,
          phone: phone.text,
          preferredLanguage: Localizations.localeOf(context).languageCode,
          emailSubject: tr(
            context,
            'Vet AI — Confirm your account',
            'Vet AI — أكّد حسابك',
            'Vet AI — Bevestig je account',
          ),
          emailHeading: tr(
            context,
            'Welcome to Vet AI',
            'أهلاً بيك في Vet AI',
            'Welkom bij Vet AI',
          ),
          emailBody: tr(
            context,
            'Confirm your email address to finish creating your Vet AI account and securely access your farm data.',
            'أكّد بريدك الإلكتروني علشان تكمّل إنشاء حساب Vet AI وتدخل على بيانات مزرعتك بأمان.',
            'Bevestig je e-mailadres om je Vet AI-account af te ronden en veilig toegang te krijgen tot je boerderijgegevens.',
          ),
          emailButton: tr(
            context,
            'Confirm Vet AI account',
            'تأكيد حساب Vet AI',
            'Vet AI-account bevestigen',
          ),
          emailFooter: tr(
            context,
            'If you did not create this Vet AI account, you can ignore this email.',
            'لو إنت ماعملتش حساب Vet AI ده، تجاهل الرسالة دي.',
            'Als je dit Vet AI-account niet hebt aangemaakt, kun je deze e-mail negeren.',
          ),
        );
        if (!mounted) return;
        if (response.session == null) {
          setState(() => confirmationEmail = email.text.trim());
        }
      } else {
        await VetBackend.instance.signIn(
          email: email.text,
          password: password.text,
        );
      }
    } on AuthException catch (e) {
      if (mounted) _snack(_friendlyAuth(e), true);
    } catch (_) {
      if (mounted) {
        _snack(
          tr(
            context,
            'Unable to complete account request.',
            'تعذر إكمال طلب الحساب.',
            'De accountaanvraag kon niet worden voltooid.',
          ),
          true,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _snack(String text, bool error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error
            ? Theme.of(context).colorScheme.error
            : VetColors.surface2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 34),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                const _BrandLockup(markWidth: 178),
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.topEnd,
                    child: IconButton.filledTonal(
                      tooltip: tr(context, 'Language', 'اللغة', 'Taal'),
                      style: IconButton.styleFrom(
                        backgroundColor: VetColors.surface3,
                      ),
                      icon: const Icon(
                        Icons.language_rounded,
                        size: 31,
                        color: VetColors.blue,
                      ),
                      onPressed: () => showVetLanguagePicker(context),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              tr(
                context,
                'Veterinary intelligence & smart animal monitoring',
                'ذكاء بيطري ومراقبة ذكية لصحة الحيوان',
                'Veterinaire intelligentie & slimme diermonitoring',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: VetColors.muted,
                fontSize: 16,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 28),
            if (confirmationEmail != null) ...[
              _Notice(
                icon: Icons.mark_email_read_outlined,
                title: tr(
                  context,
                  'Confirm your email',
                  'أكد بريدك الإلكتروني',
                  'Bevestig je e-mailadres',
                ),
                text: tr(
                  context,
                  'A confirmation link was sent to $confirmationEmail. The account cannot enter farm data until confirmation succeeds.',
                  'تم إرسال رابط تفعيل إلى $confirmationEmail. لن يدخل الحساب إلى بيانات المزرعة قبل نجاح التفعيل.',
                  'Er is een bevestigingslink gestuurd naar $confirmationEmail. Het account krijgt pas toegang tot boerderijgegevens na bevestiging.',
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: busy || resending ? null : resendConfirmation,
                icon: resending
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 26),
                label: Text(
                  resending
                      ? tr(context, 'Sending…', 'جاري الإرسال…', 'Verzenden…')
                      : tr(
                          context,
                          'Resend confirmation email',
                          'إعادة إرسال رسالة التفعيل',
                          'Bevestigingsmail opnieuw verzenden',
                        ),
                ),
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: busy || resending
                    ? null
                    : () => setState(() => create = false),
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
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 26),
                  label: Text(
                    tr(
                      context,
                      'Create account',
                      'إنشاء حساب',
                      'Account aanmaken',
                    ),
                  ),
                ),
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.login_rounded, size: 26),
                  label: Text(
                    tr(context, 'Sign in', 'تسجيل الدخول', 'Inloggen'),
                  ),
                ),
              ],
              selected: {create},
              onSelectionChanged: busy
                  ? null
                  : (v) => setState(() => create = v.first),
            ),
            const SizedBox(height: 22),
            if (create) ...[
              _Field(
                controller: fullName,
                label: tr(
                  context,
                  'Full name',
                  'الاسم الكامل',
                  'Volledige naam',
                ),
                icon: Icons.badge_outlined,
              ),
              const SizedBox(height: 12),
              _Field(
                controller: phone,
                label: tr(context, 'Phone', 'الهاتف', 'Telefoon'),
                icon: Icons.phone_outlined,
                keyboard: TextInputType.phone,
              ),
              const SizedBox(height: 12),
            ],
            _Field(
              controller: email,
              label: tr(context, 'Email', 'البريد الإلكتروني', 'E-mail'),
              icon: Icons.alternate_email_rounded,
              keyboard: TextInputType.emailAddress,
            ),
            const SizedBox(height: 12),
            _Field(
              controller: password,
              label: tr(context, 'Password', 'كلمة المرور', 'Wachtwoord'),
              icon: Icons.lock_outline_rounded,
              obscure: true,
              onSubmitted: (_) => submit(),
            ),
            if (!create) ...[
              const SizedBox(height: 4),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton.icon(
                  onPressed: busy || resettingPassword
                      ? null
                      : sendPasswordReset,
                  icon: resettingPassword
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.key_rounded, size: 22),
                  label: Text(
                    tr(
                      context,
                      'Forgot password?',
                      'نسيت كلمة المرور؟',
                      'Wachtwoord vergeten?',
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: busy ? null : submit,
              icon: busy
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      create
                          ? Icons.person_add_alt_1_rounded
                          : Icons.login_rounded,
                      size: 28,
                    ),
              label: Text(
                create
                    ? tr(
                        context,
                        'Create account',
                        'إنشاء حساب',
                        'Account aanmaken',
                      )
                    : tr(context, 'Sign in', 'تسجيل الدخول', 'Inloggen'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class V5PasswordRecoveryScreen extends StatefulWidget {
  const V5PasswordRecoveryScreen({super.key});

  @override
  State<V5PasswordRecoveryScreen> createState() =>
      _V5PasswordRecoveryScreenState();
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
      _snack(
        tr(
          context,
          'Use at least 8 characters.',
          'استخدم 8 أحرف على الأقل.',
          'Gebruik minimaal 8 tekens.',
        ),
        true,
      );
      return;
    }
    if (next != confirm.text) {
      _snack(
        tr(
          context,
          'The passwords do not match.',
          'كلمتا المرور غير متطابقتين.',
          'De wachtwoorden komen niet overeen.',
        ),
        true,
      );
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
        _snack(
          tr(
            context,
            'Could not update the password.',
            'تعذر تحديث كلمة المرور.',
            'Het wachtwoord kon niet worden bijgewerkt.',
          ),
          true,
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _snack(String text, bool error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error
            ? Theme.of(context).colorScheme.error
            : VetColors.surface2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            const _MiniBrand(),
            const SizedBox(width: 12),
            Text(
              tr(
                context,
                'Reset password',
                'تغيير كلمة المرور',
                'Wachtwoord wijzigen',
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: busy ? null : () => showVetLanguagePicker(context),
            icon: const Icon(Icons.language_rounded, color: VetColors.blue),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 36),
          children: [
            if (done) ...[
              _Notice(
                icon: Icons.verified_user_rounded,
                title: tr(
                  context,
                  'Password updated',
                  'تم تحديث كلمة المرور',
                  'Wachtwoord bijgewerkt',
                ),
                text: tr(
                  context,
                  'Your new password is active. Continue securely to Vet AI.',
                  'كلمة المرور الجديدة أصبحت فعالة. يمكنك المتابعة بأمان إلى Vet AI.',
                  'Je nieuwe wachtwoord is actief. Ga veilig verder naar Vet AI.',
                ),
              ),
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const V5AuthGate()),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 27),
                label: Text(
                  tr(
                    context,
                    'Continue to Vet AI',
                    'متابعة إلى Vet AI',
                    'Doorgaan naar Vet AI',
                  ),
                ),
              ),
            ] else ...[
              _StepTitle(
                icon: Icons.lock_reset_rounded,
                title: tr(
                  context,
                  'Choose a new password',
                  'اختر كلمة مرور جديدة',
                  'Kies een nieuw wachtwoord',
                ),
                subtitle: tr(
                  context,
                  'This screen is shown only after opening a valid Vet AI recovery link.',
                  'تظهر هذه الشاشة فقط بعد فتح رابط استعادة صالح من Vet AI.',
                  'Dit scherm verschijnt alleen nadat je een geldige Vet AI-herstellink hebt geopend.',
                ),
              ),
              const SizedBox(height: 20),
              _Field(
                controller: password,
                label: tr(
                  context,
                  'New password',
                  'كلمة المرور الجديدة',
                  'Nieuw wachtwoord',
                ),
                icon: Icons.lock_outline_rounded,
                obscure: true,
              ),
              const SizedBox(height: 12),
              _Field(
                controller: confirm,
                label: tr(
                  context,
                  'Confirm new password',
                  'تأكيد كلمة المرور الجديدة',
                  'Bevestig nieuw wachtwoord',
                ),
                icon: Icons.lock_reset_outlined,
                obscure: true,
                onSubmitted: (_) => save(),
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                onPressed: busy ? null : save,
                icon: busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.password_rounded, size: 28),
                label: Text(
                  tr(
                    context,
                    'Update password',
                    'تحديث كلمة المرور',
                    'Wachtwoord bijwerken',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class V5VerifyScreen extends StatelessWidget {
  const V5VerifyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 28),
          onPressed: VetBackend.instance.signOut,
        ),
        title: Text(
          tr(context, 'Verify account', 'تفعيل الحساب', 'Account bevestigen'),
        ),
        actions: [
          IconButton(
            onPressed: () => showVetLanguagePicker(context),
            icon: const Icon(Icons.language_rounded, color: VetColors.blue),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _Notice(
            icon: Icons.verified_user_outlined,
            title: tr(
              context,
              'Email confirmation required',
              'تأكيد البريد مطلوب',
              'E-mailbevestiging vereist',
            ),
            text: tr(
              context,
              'For safety and ownership control, Vet AI will not expose farm data before the email address is confirmed.',
              'للأمان وإثبات ملكية الحساب، لن يعرض Vet AI بيانات المزرعة قبل تأكيد البريد الإلكتروني.',
              'Voor veiligheid en eigendomscontrole toont Vet AI geen boerderijgegevens voordat het e-mailadres is bevestigd.',
            ),
          ),
        ),
      ),
    );
  }
}

class V5OnboardingScreen extends StatefulWidget {
  const V5OnboardingScreen({super.key});

  @override
  State<V5OnboardingScreen> createState() => _V5OnboardingScreenState();
}

class _V5OnboardingScreenState extends State<V5OnboardingScreen> {
  int step = 0;
  bool busy = false;
  String plan = 'software';
  String cycle = 'monthly';
  final selectedGroups = <String>{'livestock'};
  final selectedLivestockSpecies = <String>{'cattle'};
  final selectedBirdSpecies = <String>{'chicken'};
  final selectedDogBreeds = <String>{};

  final company = TextEditingController();
  final farmName = TextEditingController();
  final country = TextEditingController();
  final region = TextEditingController();
  final workers = TextEditingController(text: '0');
  final vets = TextEditingController(text: '0');
  final barns = TextEditingController(text: '1');
  final area = TextEditingController(text: '0');
  final livestock = TextEditingController(text: '1');
  final poultry = TextEditingController(text: '0');
  final dogs = TextEditingController(text: '0');
  final breeds = TextEditingController();
  final age = TextEditingController();
  final purpose = TextEditingController();
  final ventilation = TextEditingController();
  final vaccines = TextEditingController();
  final history = TextEditingController();

  int _i(TextEditingController c, [int fallback = 0]) =>
      int.tryParse(c.text.trim()) ?? fallback;
  double _d(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  @override
  void dispose() {
    for (final c in [
      company,
      farmName,
      country,
      region,
      workers,
      vets,
      barns,
      area,
      livestock,
      poultry,
      dogs,
      breeds,
      age,
      purpose,
      ventilation,
      vaccines,
      history,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggleGroup(String group) {
    setState(() {
      if (selectedGroups.contains(group)) {
        if (selectedGroups.length > 1) selectedGroups.remove(group);
      } else {
        selectedGroups.add(group);
      }
      if (!selectedGroups.contains('livestock')) livestock.text = '0';
      if (!selectedGroups.contains('poultry')) poultry.text = '0';
      if (!selectedGroups.contains('dogs')) dogs.text = '0';
      if (selectedGroups.contains('livestock') && _i(livestock) == 0)
        livestock.text = '1';
      if (selectedGroups.contains('poultry') && _i(poultry) == 0)
        poultry.text = '1';
      if (selectedGroups.contains('dogs') && _i(dogs) == 0) dogs.text = '1';
    });
  }

  Future<void> finish() async {
    if (farmName.text.trim().isEmpty ||
        _i(barns, 1) < 1 ||
        selectedGroups.isEmpty)
      return;
    setState(() => busy = true);
    try {
      final createdFarmId = await VetBackend.instance.createFarm(
        FarmSetupPayload(
          companyName: company.text,
          farmName: farmName.text,
          country: country.text,
          region: region.text,
          workerCount: _i(workers),
          veterinarianCount: _i(vets),
          barnCount: _i(barns, 1),
          totalIndoorAreaM2: _d(area),
          livestockCount: selectedGroups.contains('livestock')
              ? _i(livestock, 1)
              : 0,
          poultryCount: selectedGroups.contains('poultry') ? _i(poultry, 1) : 0,
          dogCount: selectedGroups.contains('dogs') ? _i(dogs, 1) : 0,
          breeds: breeds.text,
          ageRange: age.text,
          productionPurpose: purpose.text,
          ventilationSystem: ventilation.text,
          vaccinationNotes: vaccines.text,
          diseaseHistory: history.text,
          subscriptionTier: plan,
          billingCycle: cycle,
        ),
      );
      await VetBackend.instance.saveFarmAnimalProfile(
        createdFarmId,
        livestockSpecies: selectedGroups.contains('livestock')
            ? selectedLivestockSpecies
            : <String>{},
        birdSpecies: selectedGroups.contains('poultry')
            ? selectedBirdSpecies
            : <String>{},
        dogEnabled: selectedGroups.contains('dogs'),
        dogBreeds: selectedGroups.contains('dogs')
            ? selectedDogBreeds
            : <String>{},
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const V5AuthGate()),
        (_) => false,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                'The farm could not be created safely. Try again.',
                'تعذر إنشاء المزرعة بأمان. حاول مرة أخرى.',
                'De boerderij kon niet veilig worden aangemaakt. Probeer opnieuw.',
              ),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 28),
          onPressed: busy
              ? null
              : () => step > 0
                    ? setState(() => step--)
                    : VetBackend.instance.signOut(),
        ),
        title: Row(
          children: [
            const _MiniBrand(),
            const SizedBox(width: 12),
            Text(
              tr(context, 'Farm setup', 'إعداد المزرعة', 'Boerderij instellen'),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          LinearProgressIndicator(value: (step + 1) / 3, minHeight: 4),
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 36),
              children: [
                if (step == 0) _farmStep(context),
                if (step == 1) _animalsStep(context),
                if (step == 2) _planStep(context),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: busy
                      ? null
                      : () {
                          if (step == 0 && farmName.text.trim().isEmpty) return;
                          if (step < 2) {
                            setState(() => step++);
                          } else {
                            finish();
                          }
                        },
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          step < 2
                              ? Icons.arrow_forward_rounded
                              : Icons.check_circle_outline_rounded,
                          size: 29,
                        ),
                  label: Text(
                    step < 2
                        ? tr(context, 'Continue', 'متابعة', 'Doorgaan')
                        : tr(
                            context,
                            'Create farm',
                            'إنشاء المزرعة',
                            'Boerderij aanmaken',
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _farmStep(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _StepTitle(
        icon: Icons.business_rounded,
        title: tr(
          context,
          'Farm & operation',
          'المزرعة والتشغيل',
          'Boerderij & bedrijf',
        ),
        subtitle: tr(
          context,
          'These details become your editable farm profile.',
          'هذه البيانات ستظهر في ملف المزرعة ويمكن تعديلها.',
          'Deze gegevens komen in je bewerkbare boerderijprofiel.',
        ),
      ),
      const SizedBox(height: 18),
      _Field(
        controller: company,
        label: tr(context, 'Company name', 'اسم الشركة', 'Bedrijfsnaam'),
        icon: Icons.apartment_rounded,
      ),
      const SizedBox(height: 12),
      _Field(
        controller: farmName,
        label: tr(
          context,
          'Farm / site name',
          'اسم المزرعة / الموقع',
          'Boerderij / locatie',
        ),
        icon: Icons.home_work_outlined,
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _Field(
              controller: country,
              label: tr(context, 'Country', 'الدولة', 'Land'),
              icon: Icons.public_rounded,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Field(
              controller: region,
              label: tr(context, 'Region', 'المنطقة', 'Regio'),
              icon: Icons.location_on_outlined,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _Field(
              controller: workers,
              label: tr(context, 'Workers', 'العمال', 'Medewerkers'),
              icon: Icons.groups_2_outlined,
              keyboard: TextInputType.number,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Field(
              controller: vets,
              label: tr(
                context,
                'Veterinarians',
                'الأطباء البيطريون',
                'Dierenartsen',
              ),
              icon: Icons.medical_services_outlined,
              keyboard: TextInputType.number,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: _Field(
              controller: barns,
              label: tr(context, 'Barns', 'العنابر', 'Stallen'),
              icon: Icons.warehouse_outlined,
              keyboard: TextInputType.number,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Field(
              controller: area,
              label: tr(context, 'Indoor m²', 'المساحة م²', 'Binnen m²'),
              icon: Icons.square_foot_rounded,
              keyboard: const TextInputType.numberWithOptions(decimal: true),
            ),
          ),
        ],
      ),
    ],
  );

  Widget _animalsStep(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _StepTitle(
        icon: Icons.pets_rounded,
        title: tr(
          context,
          'Choose animal groups',
          'اختر أنواع الحيوانات',
          'Kies diergroepen',
        ),
        subtitle: tr(
          context,
          'Only selected groups will appear in AI Scan and plan features.',
          'فقط الأنواع المختارة ستظهر في فحص AI ومزايا الخطة.',
          'Alleen gekozen groepen verschijnen in AI-scan en planfuncties.',
        ),
      ),
      const SizedBox(height: 18),
      _AnimalChoice(
        group: 'livestock',
        label: tr(context, 'Livestock', 'المواشي', 'Vee'),
        asset: 'assets/icons/livestock_section.webp',
        selected: selectedGroups.contains('livestock'),
        onTap: () => _toggleGroup('livestock'),
      ),
      const SizedBox(height: 10),
      _AnimalChoice(
        group: 'poultry',
        label: tr(context, 'Birds', 'الطيور', 'Vogels'),
        asset: 'assets/icons/poultry_section.webp',
        selected: selectedGroups.contains('poultry'),
        onTap: () => _toggleGroup('poultry'),
      ),
      const SizedBox(height: 10),
      _AnimalChoice(
        group: 'dogs',
        label: tr(context, 'Dogs', 'الكلاب', 'Honden'),
        asset: 'assets/icons/dog_section.webp',
        selected: selectedGroups.contains('dogs'),
        onTap: () => _toggleGroup('dogs'),
      ),
      const SizedBox(height: 14),
      if (selectedGroups.contains('livestock')) ...[
        _SpeciesMultiSelect(
          title: tr(context, 'Livestock types', 'أنواع المواشي', 'Veetypen'),
          options: vetLivestockSpecies,
          selected: selectedLivestockSpecies,
          onChanged: (next) => setState(() {
            selectedLivestockSpecies
              ..clear()
              ..addAll(next);
          }),
        ),
        const SizedBox(height: 12),
      ],
      if (selectedGroups.contains('poultry')) ...[
        _SpeciesMultiSelect(
          title: tr(context, 'Bird types', 'أنواع الطيور', 'Vogeltypen'),
          options: vetBirdSpecies,
          selected: selectedBirdSpecies,
          onChanged: (next) => setState(() {
            selectedBirdSpecies
              ..clear()
              ..addAll(next);
          }),
        ),
        const SizedBox(height: 12),
      ],
      if (selectedGroups.contains('dogs')) ...[
        _DogBreedMultiSelect(
          title: tr(context, 'Dog breeds', 'سلالات الكلاب', 'Hondenrassen'),
          selected: selectedDogBreeds,
          onChanged: (next) => setState(() {
            selectedDogBreeds
              ..clear()
              ..addAll(next);
          }),
        ),
        const SizedBox(height: 12),
      ],
      const SizedBox(height: 6),
      if (selectedGroups.contains('livestock'))
        _Field(
          controller: livestock,
          label: tr(context, 'Livestock count', 'عدد المواشي', 'Aantal vee'),
          icon: Icons.tag_rounded,
          keyboard: TextInputType.number,
        ),
      if (selectedGroups.contains('livestock')) const SizedBox(height: 10),
      if (selectedGroups.contains('poultry'))
        _Field(
          controller: poultry,
          label: tr(context, 'Bird count', 'عدد الطيور', 'Aantal vogels'),
          icon: Icons.tag_rounded,
          keyboard: TextInputType.number,
        ),
      if (selectedGroups.contains('poultry')) const SizedBox(height: 10),
      if (selectedGroups.contains('dogs'))
        _Field(
          controller: dogs,
          label: tr(context, 'Dog count', 'عدد الكلاب', 'Aantal honden'),
          icon: Icons.tag_rounded,
          keyboard: TextInputType.number,
        ),
      const SizedBox(height: 12),
      _Field(
        controller: breeds,
        label: tr(context, 'Breeds / strains', 'السلالات', 'Rassen / lijnen'),
        icon: Icons.category_outlined,
      ),
      const SizedBox(height: 12),
      _Field(
        controller: age,
        label: tr(
          context,
          'Age / production cycle',
          'العمر / دورة الإنتاج',
          'Leeftijd / productiecyclus',
        ),
        icon: Icons.calendar_month_outlined,
      ),
      const SizedBox(height: 12),
      _Field(
        controller: purpose,
        label: tr(
          context,
          'Production purpose',
          'غرض التربية',
          'Productiedoel',
        ),
        icon: Icons.flag_outlined,
      ),
      const SizedBox(height: 12),
      _Field(
        controller: ventilation,
        label: tr(
          context,
          'Ventilation / housing',
          'التهوية / الإيواء',
          'Ventilatie / huisvesting',
        ),
        icon: Icons.air_rounded,
      ),
      const SizedBox(height: 12),
      _Field(
        controller: vaccines,
        label: tr(
          context,
          'Vaccination program',
          'برنامج التحصينات',
          'Vaccinatieprogramma',
        ),
        icon: Icons.vaccines_outlined,
        lines: 3,
      ),
      const SizedBox(height: 12),
      _Field(
        controller: history,
        label: tr(
          context,
          'Disease / mortality history',
          'تاريخ الأمراض / النفوق',
          'Ziekte- / sterftegeschiedenis',
        ),
        icon: Icons.history_edu_outlined,
        lines: 3,
      ),
    ],
  );

  Widget _planStep(BuildContext context) {
    final groupsText = [
      if (selectedGroups.contains('livestock'))
        tr(context, 'Livestock', 'مواشي', 'Vee'),
      if (selectedGroups.contains('poultry'))
        tr(context, 'Poultry', 'دواجن', 'Pluimvee'),
      if (selectedGroups.contains('dogs'))
        tr(context, 'Dogs', 'كلاب', 'Honden'),
    ].join(' • ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _StepTitle(
          icon: Icons.workspace_premium_outlined,
          title: tr(context, 'Choose your plan', 'اختر الخطة', 'Kies je plan'),
          subtitle: groupsText,
        ),
        const SizedBox(height: 18),
        _PlanCard(
          selected: plan == 'software',
          icon: Icons.health_and_safety_outlined,
          title: tr(
            context,
            'Software only',
            'البرنامج فقط',
            'Alleen software',
          ),
          lines: [
            tr(
              context,
              'AI image assessment and health history',
              'فحص الصور بالذكاء الاصطناعي والسجل الصحي',
              'AI-beeldbeoordeling en gezondheidshistorie',
            ),
            tr(
              context,
              'Alerts from AI assessments',
              'إنذارات ناتجة عن فحوصات AI',
              'Meldingen uit AI-beoordelingen',
            ),
            tr(
              context,
              'Sensors and continuous monitoring are locked',
              'الحساسات والمراقبة المستمرة غير متاحة',
              'Sensoren en continue monitoring zijn vergrendeld',
            ),
          ],
          onTap: () => setState(() => plan = 'software'),
        ),
        const SizedBox(height: 12),
        _PlanCard(
          selected: plan == 'smart_monitoring',
          icon: Icons.sensors_rounded,
          title: tr(
            context,
            'Software + smart monitoring',
            'البرنامج + المراقبة الذكية',
            'Software + slimme monitoring',
          ),
          lines: [
            tr(
              context,
              'Everything in Software only',
              'كل مزايا البرنامج فقط',
              'Alles uit Alleen software',
            ),
            tr(
              context,
              'Real sensor devices and live readings when hardware is connected',
              'أجهزة حساسات حقيقية وقراءات مباشرة عند توصيل الهاردوير',
              'Echte sensoren en live metingen zodra hardware is gekoppeld',
            ),
            tr(
              context,
              'No demo sensor readings',
              'بدون أي قراءات حساسات وهمية',
              'Geen demo-sensormetingen',
            ),
          ],
          onTap: () => setState(() => plan = 'smart_monitoring'),
        ),
        const SizedBox(height: 16),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: 'monthly',
              icon: const Icon(Icons.calendar_view_month_rounded, size: 27),
              label: Text(tr(context, 'Monthly', 'شهري', 'Maandelijks')),
            ),
            ButtonSegment(
              value: 'annual',
              icon: const Icon(Icons.event_repeat_rounded, size: 27),
              label: Text(tr(context, 'Annual', 'سنوي', 'Jaarlijks')),
            ),
          ],
          selected: {cycle},
          onSelectionChanged: (v) => setState(() => cycle = v.first),
        ),
        const SizedBox(height: 16),
        _Notice(
          icon: Icons.credit_card_off_outlined,
          title: tr(
            context,
            'Billing status',
            'حالة الدفع',
            'Factureringsstatus',
          ),
          text: tr(
            context,
            'Plan selection is saved and controls features. Paid billing is not activated yet, so Vet AI will not pretend a payment was collected.',
            'اختيار الخطة يتم حفظه ويتحكم في المزايا. الدفع المدفوع غير مفعّل بعد، لذلك Vet AI لن يدّعي أنه تم تحصيل أي مبلغ.',
            'De plankiezer wordt opgeslagen en bepaalt functies. Betaalde facturering is nog niet actief; Vet AI doet dus niet alsof er betaald is.',
          ),
        ),
      ],
    );
  }
}

class V5Dashboard extends StatefulWidget {
  const V5Dashboard({super.key, required this.initialFarm});
  final Map<String, dynamic> initialFarm;

  @override
  State<V5Dashboard> createState() => _V5DashboardState();
}

class _V5DashboardState extends State<V5Dashboard> {
  int index = 0;
  late Map<String, dynamic> farm;
  StreamSubscription<List<Map<String, dynamic>>>? _alertSubscription;
  late final DateTime _alertListeningSince;
  String? _lastNotifiedAlertId;

  @override
  void initState() {
    super.initState();
    farm = Map<String, dynamic>.from(widget.initialFarm);
    _alertListeningSince = DateTime.now().toUtc();
    final farmId = farm['id']?.toString();
    if (farmId != null && farmId.isNotEmpty) {
      _alertSubscription = VetBackend.instance
          .alertsStream(farmId)
          .listen(_handleAlertRows);
    }
  }

  void _handleAlertRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return;
    final row = rows.first;
    final id = row['id']?.toString();
    if (id == null || id.isEmpty || id == _lastNotifiedAlertId) return;
    final created = DateTime.tryParse(row['created_at']?.toString() ?? '');
    if (created == null || created.toUtc().isBefore(_alertListeningSince)) {
      _lastNotifiedAlertId = id;
      return;
    }
    _lastNotifiedAlertId = id;
    final title = row['title']?.toString().trim();
    final details = row['details']?.toString().trim();
    final threshold = row['threshold_text']?.toString().trim();
    VetAlertNotificationService.instance.showSensorAlert(
      alertId: id,
      title: (title == null || title.isEmpty) ? 'Vet AI sensor alert' : title,
      body: (details != null && details.isNotEmpty)
          ? details
          : ((threshold != null && threshold.isNotEmpty)
                ? threshold
                : 'A real sensor threshold was crossed.'),
      payload: id,
    );
  }

  @override
  void dispose() {
    _alertSubscription?.cancel();
    super.dispose();
  }

  Future<void> refreshFarm() async {
    final current = await VetBackend.instance.myFarm();
    if (mounted && current != null) setState(() => farm = current);
  }

  Future<void> openAccount() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => V5AccountHub(farm: farm)));
    await refreshFarm();
  }

  @override
  Widget build(BuildContext context) {
    final farmId = farm['id'] as String;
    final smart = farm['subscription_tier'] == 'smart_monitoring';
    final pages = <Widget>[
      V5Home(farm: farm, onAccount: openAccount, smart: smart),
      V5ScanPanel(farm: farm),
      V5SensorsPanel(farm: farm, unlocked: smart),
      V5AlertsPanel(farmId: farmId),
      V5HistoryPanel(farmId: farmId),
    ];
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: index, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        height: 78,
        selectedIndex: index,
        onDestinationSelected: (v) => setState(() => index = v),
        destinations: [
          _nav(
            Icons.home_outlined,
            Icons.home_rounded,
            tr(context, 'Home', 'الرئيسية', 'Home'),
            VetColors.green,
          ),
          _nav(
            Icons.document_scanner_outlined,
            Icons.document_scanner_rounded,
            tr(context, 'AI Scan', 'فحص AI', 'AI-scan'),
            VetColors.blue,
          ),
          _nav(
            smart ? Icons.sensors_outlined : Icons.lock_outline_rounded,
            smart ? Icons.sensors_rounded : Icons.lock_rounded,
            tr(context, 'Sensors', 'الحساسات', 'Sensoren'),
            VetColors.purple,
          ),
          _nav(
            Icons.warning_amber_outlined,
            Icons.warning_rounded,
            tr(context, 'Alerts', 'الإنذارات', 'Meldingen'),
            VetColors.orange,
          ),
          _nav(
            Icons.history_rounded,
            Icons.manage_history_rounded,
            tr(context, 'History', 'السجل', 'Historie'),
            VetColors.history,
          ),
        ],
      ),
    );
  }

  NavigationDestination _nav(
    IconData icon,
    IconData selected,
    String label,
    Color color,
  ) => NavigationDestination(
    icon: Icon(icon, size: 32, color: color.withValues(alpha: .78)),
    selectedIcon: Container(
      width: 52,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(selected, size: 34, color: color),
    ),
    label: label,
  );
}

class V5Home extends StatelessWidget {
  const V5Home({
    super.key,
    required this.farm,
    required this.onAccount,
    required this.smart,
  });
  final Map<String, dynamic> farm;
  final VoidCallback onAccount;
  final bool smart;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const _HeaderBrand(),
                const Spacer(),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filledTonal(
                      tooltip: tr(context, 'Language', 'اللغة', 'Taal'),
                      style: IconButton.styleFrom(
                        backgroundColor: VetColors.surface3,
                      ),
                      icon: const Icon(
                        Icons.language_rounded,
                        size: 30,
                        color: VetColors.blue,
                      ),
                      onPressed: () => showVetLanguagePicker(context),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      tooltip: tr(
                        context,
                        'Account & settings',
                        'الحساب والإعدادات',
                        'Account & instellingen',
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: VetColors.surface3,
                      ),
                      icon: const Icon(
                        Icons.account_circle_outlined,
                        size: 31,
                        color: VetColors.primary,
                      ),
                      onPressed: onAccount,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              farm['farm_name']?.toString() ?? 'Vet AI',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            if ((farm['company_name']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                farm['company_name'].toString(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: VetColors.muted,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 14),
        _Notice(
          icon: Icons.shield_outlined,
          title: tr(
            context,
            'Real data policy',
            'سياسة البيانات الحقيقية',
            'Echte-data beleid',
          ),
          text: tr(
            context,
            'No demo sensor readings and no definitive diagnosis from one image.',
            'لا توجد قراءات حساسات وهمية ولا تشخيص نهائي من صورة واحدة.',
            'Geen demo-sensormetingen en geen definitieve diagnose op basis van één beeld.',
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            if ((farm['livestock_count'] as num?)?.toInt() != null &&
                (farm['livestock_count'] as num).toInt() > 0)
              Expanded(
                child: _AnimalCount(
                  asset: 'assets/icons/livestock_section.webp',
                  label: tr(context, 'Livestock', 'المواشي', 'Vee'),
                  value: farm['livestock_count'],
                ),
              ),
            if ((farm['livestock_count'] as num?)?.toInt() != null &&
                (farm['livestock_count'] as num).toInt() > 0 &&
                (((farm['poultry_count'] as num?)?.toInt() ?? 0) > 0 ||
                    ((farm['dog_count'] as num?)?.toInt() ?? 0) > 0))
              const SizedBox(width: 10),
            if (((farm['poultry_count'] as num?)?.toInt() ?? 0) > 0)
              Expanded(
                child: _AnimalCount(
                  asset: 'assets/icons/poultry_section.webp',
                  label: tr(context, 'Birds', 'الطيور', 'Vogels'),
                  value: farm['poultry_count'],
                ),
              ),
            if (((farm['poultry_count'] as num?)?.toInt() ?? 0) > 0 &&
                ((farm['dog_count'] as num?)?.toInt() ?? 0) > 0)
              const SizedBox(width: 10),
            if (((farm['dog_count'] as num?)?.toInt() ?? 0) > 0)
              Expanded(
                child: _AnimalCount(
                  asset: 'assets/icons/dog_section.webp',
                  label: tr(context, 'Dogs', 'الكلاب', 'Honden'),
                  value: farm['dog_count'],
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        if (smart) ...[
          SmartHomeVitals(
            farmId: farm['id'] as String,
            translate: (en, ar, nl) => tr(context, en, ar, nl),
          ),
          const SizedBox(height: 18),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.monitor_heart_outlined,
                      color: VetColors.primary,
                      size: 32,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        tr(
                          context,
                          'Health monitoring overview',
                          'نظرة عامة على المراقبة الصحية',
                          'Overzicht gezondheidsmonitoring',
                        ),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _metric(
                  Icons.warehouse_outlined,
                  tr(context, 'Barns', 'العنابر', 'Stallen'),
                  farm['barn_count'],
                ),
                _metric(
                  Icons.groups_2_outlined,
                  tr(context, 'Workers', 'العمال', 'Medewerkers'),
                  farm['worker_count'],
                ),
                _metric(
                  Icons.medical_services_outlined,
                  tr(
                    context,
                    'Veterinarians',
                    'الأطباء البيطريون',
                    'Dierenartsen',
                  ),
                  farm['veterinarian_count'],
                ),
                _metric(
                  Icons.workspace_premium_outlined,
                  tr(context, 'Plan', 'الخطة', 'Plan'),
                  farm['subscription_tier'] == 'smart_monitoring'
                      ? tr(
                          context,
                          'Smart monitoring',
                          'مراقبة ذكية',
                          'Slimme monitoring',
                        )
                      : tr(
                          context,
                          'Software only',
                          'البرنامج فقط',
                          'Alleen software',
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _metric(IconData icon, String label, dynamic value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Icon(icon, color: VetColors.muted, size: 27),
        const SizedBox(width: 12),
        Text('$label: ', style: const TextStyle(color: VetColors.muted)),
        Expanded(
          child: Text(
            '$value',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    ),
  );
}

class V5ScanPanel extends StatefulWidget {
  const V5ScanPanel({super.key, required this.farm});
  final Map<String, dynamic> farm;

  @override
  State<V5ScanPanel> createState() => _V5ScanPanelState();
}

class _V5ScanPanelState extends State<V5ScanPanel> {
  final picker = ImagePicker();
  final notes = TextEditingController();
  XFile? file;
  Uint8List? bytes;
  bool busy = false;
  Map<String, dynamic>? result;
  String? assessmentId;
  late String group;
  late String speciesCode;
  late String dogBreedCode;

  List<String> get groups => [
    if (((widget.farm['livestock_count'] as num?)?.toInt() ?? 0) > 0)
      'livestock',
    if (((widget.farm['poultry_count'] as num?)?.toInt() ?? 0) > 0) 'poultry',
    if (((widget.farm['dog_count'] as num?)?.toInt() ?? 0) > 0) 'dogs',
  ];

  List<String> _speciesCodesForGroup(String g) {
    if (g == 'dogs') return const ['dog'];
    final supported = vetSpeciesForGroup(g).map((e) => e.code).toSet();
    final key = g == 'poultry' ? 'bird_species' : 'livestock_species';
    final configured = ((widget.farm[key] as List?) ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty && supported.contains(e))
        .toList();
    if (configured.isNotEmpty) return configured;
    return supported.toList();
  }

  List<VetDogBreed> get _availableDogBreeds {
    final configured = ((widget.farm['dog_breeds'] as List?) ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (configured.isEmpty) return vetDogBreeds;
    final filtered = vetDogBreeds
        .where((breed) => configured.contains(breed.code))
        .toList();
    return filtered.isEmpty ? vetDogBreeds : filtered;
  }

  List<VetAnimalSpecies> get _currentSpeciesOptions {
    final allowed = _speciesCodesForGroup(group).toSet();
    return vetSpeciesForGroup(
      group,
    ).where((e) => allowed.contains(e.code)).toList();
  }

  @override
  void initState() {
    super.initState();
    group = groups.isEmpty ? 'livestock' : groups.first;
    final initialSpecies = _speciesCodesForGroup(group);
    speciesCode = initialSpecies.isEmpty
        ? (group == 'dogs'
              ? 'dog'
              : group == 'poultry'
              ? 'chicken'
              : 'cattle')
        : initialSpecies.first;
    dogBreedCode = _availableDogBreeds.first.code;
  }

  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  Future<bool> _confirmAccess({
    required String title,
    required String message,
    required IconData icon,
  }) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(icon, size: 38, color: VetColors.primary),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(height: 1.45),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(tr(context, 'Cancel', 'إلغاء', 'Annuleren')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(tr(context, 'Allow', 'سماح', 'Toestaan')),
          ),
        ],
      ),
    );
    return approved == true;
  }

  Future<bool> _confirmMedia(ImageSource source) async {
    final userId = VetBackend.instance.currentUser?.id;
    final prefs = await SharedPreferences.getInstance();
    final key = 'vet_ai_scan_privacy_ack_${userId ?? 'signed_out'}';
    if (prefs.getBool(key) == true) return true;

    try {
      if (await VetBackend.instance.scanPrivacyAcknowledged()) {
        await prefs.setBool(key, true);
        return true;
      }
    } catch (_) {
      // A temporary profile read problem must not block the picker.
    }

    final isCamera = source == ImageSource.camera;
    final approved = await _confirmAccess(
      title: tr(
        context,
        'Before your first Vet AI scan',
        'قبل أول فحص على Vet AI',
        'Voor je eerste Vet AI-scan',
      ),
      message: tr(
        context,
        'This one-time explanation is saved to your Vet AI account. Vet AI only uploads an animal image after you choose it and start analysis. iOS or Android may still show their own camera or photo permission when required by the operating system.',
        'الرسالة دي هتظهر مرة واحدة بس للحساب ده وهنحفظ الموافقة على حساب Vet AI نفسه. Vet AI مش بيرفع صورة الحيوان إلا بعد ما تختارها وتبدأ التحليل بنفسك. iOS أو Android ممكن يعرضوا إذن النظام للكاميرا أو الصور وقت ما نظام التشغيل يحتاجه.',
        'Deze uitleg verschijnt één keer per Vet AI-account en wordt op het account opgeslagen. Vet AI uploadt een dierenfoto pas nadat je die kiest en zelf de analyse start. iOS of Android kan nog een systeempop-up voor camera of foto’s tonen wanneer dat nodig is.',
      ),
      icon: isCamera ? Icons.photo_camera_rounded : Icons.photo_library_rounded,
    );
    if (approved) {
      await prefs.setBool(key, true);
      try {
        await VetBackend.instance.acknowledgeScanPrivacy();
      } catch (_) {
        // Local acknowledgement still prevents repeated dialogs on this device.
      }
    }
    return approved;
  }

  Future<void> pick(ImageSource source) async {
    if (!await _confirmMedia(source)) return;
    final chosen = await picker.pickImage(
      source: source,
      imageQuality: 82,
      maxWidth: 1400,
      maxHeight: 1400,
    );
    if (chosen == null) return;
    final data = await chosen.readAsBytes();
    if (mounted)
      setState(() {
        file = chosen;
        bytes = data;
        result = null;
      });
  }

  Future<String> _scanCacheKey() async {
    final language = Localizations.localeOf(context).languageCode.toLowerCase();
    final metadata = utf8.encode(
      '|$group|$speciesCode|$dogBreedCode|$language|${notes.text.trim().toLowerCase()}',
    );
    final digest = sha256.convert(<int>[...bytes!, ...metadata]).toString();
    return 'vet_ai_exact_scan_v3_$digest';
  }

  Future<Map<String, dynamic>?> _readExactScanCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final savedAt = DateTime.tryParse((decoded['saved_at'] ?? '').toString());
      if (savedAt == null || DateTime.now().difference(savedAt).inHours > 72) {
        await prefs.remove(key);
        return null;
      }
      final cachedResult = decoded['result'];
      final cachedAssessmentId = (decoded['assessment_id'] ?? '').toString();
      if (cachedResult is! Map ||
          cachedResult['code']?.toString() != 'AI_ANALYSIS_COMPLETE' ||
          cachedAssessmentId.isEmpty) {
        return null;
      }
      return {
        'assessment_id': cachedAssessmentId,
        'result': Map<String, dynamic>.from(cachedResult),
      };
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeExactScanCache(
    String key,
    String assessmentId,
    Map<String, dynamic> response,
  ) async {
    if (response['code']?.toString() != 'AI_ANALYSIS_COMPLETE') return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        key,
        jsonEncode({
          'saved_at': DateTime.now().toIso8601String(),
          'assessment_id': assessmentId,
          'result': response,
        }),
      );
    } catch (_) {
      // Cache failure must never block a real veterinary assessment.
    }
  }

  Future<void> analyze() async {
    if (file == null || bytes == null) return;
    setState(() {
      busy = true;
      result = null;
    });
    try {
      final cacheKey = await _scanCacheKey();
      final cached = await _readExactScanCache(cacheKey);
      if (cached != null) {
        assessmentId = cached['assessment_id'] as String;
        final cachedResult = Map<String, dynamic>.from(
          cached['result'] as Map<String, dynamic>,
        );
        cachedResult['cache_reused_on_device'] = true;
        if (mounted) {
          setState(() {
            result = cachedResult;
            busy = false;
          });
        }
        return;
      }

      final extension = file!.name.contains('.')
          ? file!.name.split('.').last
          : 'jpg';
      final farmId = widget.farm['id'] as String;
      final path = await VetBackend.instance.uploadDiagnosticMedia(
        farmId: farmId,
        bytes: bytes!,
        extension: extension,
      );
      final newAssessmentId = await VetBackend.instance.createDraftAssessment(
        farmId: farmId,
        mediaPath: path,
        symptomNotes: group == 'dogs'
            ? '[Dog breed: $dogBreedCode]\n${notes.text}'
            : notes.text,
        animalGroup: group,
        speciesCode: speciesCode,
        birdType: group == 'poultry' ? speciesCode : null,
      );
      assessmentId = newAssessmentId;
      final response = await VetBackend.instance.analyzeAssessment(
        newAssessmentId,
        language: Localizations.localeOf(context).languageCode,
      );
      // Do not automatically hammer the AI provider after a 429/timeout.
      // One explicit user action now produces one provider request.
      await _writeExactScanCache(cacheKey, newAssessmentId, response);
      if (mounted) setState(() => result = response);
    } catch (_) {
      if (mounted) {
        setState(
          () => result = {
            'code': 'NETWORK_OR_SERVICE_ERROR',
            'risk': 'insufficient_data',
            'message': tr(
              context,
              'The protected analysis service could not be reached.',
              'تعذر الوصول إلى خدمة التحليل المحمية.',
              'De beveiligde analyseservice kon niet worden bereikt.',
            ),
          },
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String label(String g) {
    if (g == 'poultry') return tr(context, 'Birds', 'الطيور', 'Vogels');
    if (g == 'dogs') return tr(context, 'Dogs', 'الكلاب', 'Honden');
    return tr(context, 'Livestock', 'المواشي', 'Vee');
  }

  int groupSpriteIndex(String g) => g == 'poultry'
      ? 2
      : g == 'dogs'
      ? 1
      : 0;

  @override
  Widget build(BuildContext context) {
    final code = result?['code']?.toString();
    final complete =
        code == 'AI_ANALYSIS_COMPLETE' || code == 'FINAL_REPORT_COMPLETE';
    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.all(20),
      children: [
        _StepTitle(
          icon: Icons.document_scanner_rounded,
          title: tr(
            context,
            'AI health scan',
            'الفحص الصحي بالذكاء الاصطناعي',
            'AI-gezondheidsscan',
          ),
          subtitle: tr(
            context,
            'Image + symptoms + reviewed veterinary knowledge. Not a definitive diagnosis.',
            'صورة + أعراض + معرفة بيطرية مراجعة. ليست تشخيصًا نهائيًا.',
            'Beeld + symptomen + beoordeelde veterinaire kennis. Geen definitieve diagnose.',
          ),
        ),
        const SizedBox(height: 16),
        if (groups.length > 1)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: groups
                .map(
                  (g) => ChoiceChip(
                    avatar: _AnimalSprite(
                      index: groupSpriteIndex(g),
                      size: 46,
                      radius: 8,
                    ),
                    label: Text(label(g)),
                    selected: group == g,
                    onSelected: busy
                        ? null
                        : (_) => setState(() {
                            group = g;
                            final choices = _speciesCodesForGroup(g);
                            speciesCode = choices.isEmpty
                                ? (g == 'dogs'
                                      ? 'dog'
                                      : g == 'poultry'
                                      ? 'chicken'
                                      : 'cattle')
                                : choices.first;
                            if (g == 'dogs' &&
                                !_availableDogBreeds.any(
                                  (breed) => breed.code == dogBreedCode,
                                )) {
                              dogBreedCode = _availableDogBreeds.first.code;
                            }
                            result = null;
                          }),
                  ),
                )
                .toList(),
          ),
        if (groups.length > 1) const SizedBox(height: 12),
        _AnimalGroupBanner(
          spriteIndex: groupSpriteIndex(group),
          title: label(group),
          text: tr(
            context,
            'This is the animal group selected for this scan.',
            'ده قسم الحيوان المختار للفحص ده.',
            'Dit is de diergroep die voor deze scan is geselecteerd.',
          ),
        ),
        const SizedBox(height: 12),
        if (group == 'dogs')
          _DogBreedSingleSelect(
            title: tr(
              context,
              'Choose dog breed',
              'اختار نوع الكلب',
              'Kies hondenras',
            ),
            options: _availableDogBreeds,
            selectedCode: dogBreedCode,
            enabled: !busy,
            onChanged: (code) => setState(() {
              dogBreedCode = code;
              result = null;
            }),
          )
        else
          _SpeciesSingleSelect(
            title: group == 'livestock'
                ? tr(
                    context,
                    'Choose livestock type',
                    'اختار نوع المواشي',
                    'Kies veetype',
                  )
                : tr(
                    context,
                    'Choose bird type',
                    'اختار نوع الطير',
                    'Kies vogeltype',
                  ),
            options: _currentSpeciesOptions,
            selectedCode: speciesCode,
            enabled: !busy,
            onChanged: (code) => setState(() {
              speciesCode = code;
              result = null;
            }),
          ),
        const SizedBox(height: 16),
        Container(
          height: 285,
          decoration: BoxDecoration(
            color: VetColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: VetColors.border),
          ),
          child: bytes == null
              ? Center(
                  child: Icon(
                    Icons.add_a_photo_outlined,
                    size: 78,
                    color: VetColors.muted.withValues(alpha: .8),
                  ),
                )
              : ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Image.memory(
                    bytes!,
                    fit: BoxFit.cover,
                    width: double.infinity,
                  ),
                ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : () => pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined, size: 29),
                label: Text(tr(context, 'Camera', 'الكاميرا', 'Camera')),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: busy ? null : () => pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library_outlined, size: 29),
                label: Text(tr(context, 'Photos', 'الصور', 'Foto’s')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _Field(
          controller: notes,
          label: tr(
            context,
            'Symptoms / history / recent changes',
            'الأعراض / التاريخ / التغيّرات الأخيرة',
            'Symptomen / historie / recente veranderingen',
          ),
          icon: Icons.description_outlined,
          lines: 4,
        ),
        const SizedBox(height: 14),
        ElevatedButton.icon(
          onPressed: file == null || busy ? null : analyze,
          icon: busy
              ? const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.health_and_safety_outlined, size: 30),
          label: Text(
            busy
                ? tr(
                    context,
                    'Analyzing safely…',
                    'جاري التحليل بأمان…',
                    'Veilig analyseren…',
                  )
                : tr(
                    context,
                    'Analyze case',
                    'تحليل الحالة',
                    'Casus analyseren',
                  ),
          ),
        ),
        if (result != null) ...[
          const SizedBox(height: 16),
          if (complete)
            VetAnalysisReportCard(
              initialResult: result!,
              assessmentId:
                  assessmentId ?? result!['assessment_id']?.toString() ?? '',
              languageCode: Localizations.localeOf(context).languageCode,
              translate: (en, ar, nl) => tr(context, en, ar, nl),
              onFinalized: (finalReport) {
                if (mounted) setState(() => result = finalReport);
              },
              onBack: () {
                FocusManager.instance.primaryFocus?.unfocus();
                if (mounted) setState(() => result = null);
              },
            )
          else
            _Notice(
              icon: code == 'AI_PROVIDER_NOT_CONFIGURED'
                  ? Icons.key_off_outlined
                  : Icons.info_outline_rounded,
              title: tr(
                context,
                'Analysis not completed',
                'لم يكتمل التحليل',
                'Analyse niet voltooid',
              ),
              text: code == 'AI_PROVIDER_RATE_LIMIT'
                  ? _errorMessage(code)
                  : (result!['message'] ?? _errorMessage(code)).toString(),
              danger: true,
            ),
        ],
      ],
    );
  }

  String _errorMessage(String? code) {
    switch (code) {
      case 'AI_PROVIDER_NOT_CONFIGURED':
        return tr(
          context,
          'The protected AI provider key is not available to the Edge Function.',
          'مفتاح مزود الذكاء الاصطناعي غير متاح لخدمة Edge Function.',
          'De beveiligde AI-providersleutel is niet beschikbaar voor de Edge Function.',
        );
      case 'AI_PROVIDER_RATE_LIMIT':
        return tr(
          context,
          'The AI provider temporarily rejected this request because the API account reached a provider limit. This is not evidence of Vet AI user traffic. Try again in about a minute.',
          'مزود الذكاء الاصطناعي رفض الطلب مؤقتًا لأن حساب الـ API وصل لحد من المزود. ده مش معناه إن فيه ضغط مستخدمين على Vet AI. جرّب تاني بعد حوالي دقيقة.',
          'De AI-provider heeft dit verzoek tijdelijk geweigerd omdat het API-account een providerlimiet heeft bereikt. Dit betekent niet dat Vet AI veel gebruikersverkeer heeft. Probeer het over ongeveer een minuut opnieuw.',
        );
      case 'AI_PROVIDER_AUTH_ERROR':
        return tr(
          context,
          'The AI provider rejected the server credential. The server key needs attention.',
          'مزود الذكاء الاصطناعي رفض بيانات اعتماد السيرفر. يجب مراجعة المفتاح.',
          'De AI-provider heeft de serverreferentie geweigerd. De serversleutel moet worden gecontroleerd.',
        );
      case 'SPECIES_GROUP_MISMATCH':
        return tr(
          context,
          'The image does not appear compatible with the selected animal group. No disease guess was produced.',
          'الصورة لا تبدو متوافقة مع نوع الحيوان المختار، لذلك لم يتم تخمين مرض.',
          'Het beeld lijkt niet overeen te komen met de gekozen diergroep. Er is geen ziekte gegokt.',
        );
      default:
        return tr(
          context,
          'The case could not be analyzed. No diagnosis was invented.',
          'تعذر تحليل الحالة ولم يتم اختراع تشخيص.',
          'De casus kon niet worden geanalyseerd. Er is geen diagnose verzonnen.',
        );
    }
  }
}

class V5SensorsPanel extends StatefulWidget {
  const V5SensorsPanel({super.key, required this.farm, required this.unlocked});
  final Map<String, dynamic> farm;
  final bool unlocked;

  @override
  State<V5SensorsPanel> createState() => _V5SensorsPanelState();
}

class _V5SensorsPanelState extends State<V5SensorsPanel> {
  late Future<List<Map<String, dynamic>>> devicesFuture;

  String get farmId => widget.farm['id'] as String;

  @override
  void initState() {
    super.initState();
    devicesFuture = widget.unlocked
        ? _loadDevices()
        : Future.value(const <Map<String, dynamic>>[]);
  }

  @override
  void didUpdateWidget(covariant V5SensorsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.unlocked != widget.unlocked ||
        oldWidget.farm['id'] != widget.farm['id']) {
      devicesFuture = widget.unlocked
          ? _loadDevices()
          : Future.value(const <Map<String, dynamic>>[]);
    }
  }

  Future<List<Map<String, dynamic>>> _loadDevices() {
    return VetBackend.instance
        .sensorDevices(farmId)
        .timeout(const Duration(seconds: 12));
  }

  void _retry() {
    setState(() => devicesFuture = _loadDevices());
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.unlocked) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _StepTitle(
            icon: Icons.lock_rounded,
            title: tr(
              context,
              'Smart sensors',
              'الحساسات الذكية',
              'Slimme sensoren',
            ),
            subtitle: tr(
              context,
              'Unavailable on the Software only plan.',
              'غير متاحة على خطة البرنامج فقط.',
              'Niet beschikbaar met het Alleen software-plan.',
            ),
          ),
          const SizedBox(height: 18),
          _Notice(
            icon: Icons.workspace_premium_outlined,
            title: tr(
              context,
              'Plan locked',
              'الميزة مقفلة حسب الخطة',
              'Functie vergrendeld',
            ),
            text: tr(
              context,
              'Choose Software + smart monitoring from Subscription to unlock real hardware data. No fake sensor values are shown.',
              'اختر البرنامج + المراقبة الذكية من صفحة الاشتراك لفتح بيانات الأجهزة الحقيقية. لن نعرض أرقام حساسات وهمية.',
              'Kies Software + slimme monitoring bij Abonnement om echte hardwaredata te ontgrendelen. Er worden geen nepwaarden getoond.',
            ),
          ),
        ],
      );
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: devicesFuture,
      builder: (context, devices) {
        final rows = devices.data ?? const <Map<String, dynamic>>[];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _StepTitle(
              icon: Icons.sensors_rounded,
              title: tr(
                context,
                'Smart monitoring',
                'المراقبة الذكية',
                'Slimme monitoring',
              ),
              subtitle: tr(
                context,
                'Only real connected hardware is shown.',
                'يتم عرض الهاردوير الحقيقي المتصل فقط.',
                'Alleen echt gekoppelde hardware wordt getoond.',
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SensorAlertRulesScreen(farmId: farmId),
                ),
              ),
              icon: const Icon(Icons.notifications_active_outlined, size: 29),
              label: Text(
                tr(
                  context,
                  'Configure real sensor alert rules',
                  'ضبط قواعد إنذارات الحساسات الحقيقية',
                  'Echte sensorwaarschuwingsregels instellen',
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (devices.connectionState != ConnectionState.done)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ),
              ),
            if (devices.connectionState == ConnectionState.done &&
                devices.hasError) ...[
              _Notice(
                icon: Icons.cloud_off_rounded,
                title: tr(
                  context,
                  'Could not load sensors',
                  'تعذر تحميل الحساسات',
                  'Sensoren konden niet worden geladen',
                ),
                text: tr(
                  context,
                  'Vet AI stopped waiting instead of showing an endless loader. Check the connection and try again.',
                  'Vet AI وقف التحميل بدل ما يفضل يلف للأبد. تحقق من الاتصال وجرّب تاني.',
                  'Vet AI is gestopt met wachten in plaats van eindeloos te laden. Controleer de verbinding en probeer opnieuw.',
                ),
                danger: true,
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(
                  tr(context, 'Retry', 'إعادة المحاولة', 'Opnieuw proberen'),
                ),
              ),
            ],
            if (devices.connectionState == ConnectionState.done &&
                !devices.hasError &&
                rows.isEmpty)
              _Notice(
                icon: Icons.sensors_off_outlined,
                title: tr(
                  context,
                  'No sensors connected',
                  'لا توجد حساسات متصلة',
                  'Geen sensoren gekoppeld',
                ),
                text: tr(
                  context,
                  'The plan allows sensors, but no device has been provisioned yet.',
                  'الخطة تسمح بالحساسات لكن لم يتم ربط أي جهاز حتى الآن.',
                  'Het plan ondersteunt sensoren, maar er is nog geen apparaat ingericht.',
                ),
              ),
            if (!devices.hasError)
              for (final device in rows)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: const Icon(
                      Icons.sensors_rounded,
                      size: 35,
                      color: VetColors.primary,
                    ),
                    title: Text(device['device_uid']?.toString() ?? ''),
                    subtitle: Text(
                      '${device['device_type'] ?? ''}\n${device['last_seen_at'] ?? tr(context, 'Never seen', 'لم يتصل بعد', 'Nog nooit gezien')}',
                    ),
                    isThreeLine: true,
                  ),
                ),
          ],
        );
      },
    );
  }
}

class V5AlertsPanel extends StatefulWidget {
  const V5AlertsPanel({super.key, required this.farmId});
  final String farmId;

  @override
  State<V5AlertsPanel> createState() => _V5AlertsPanelState();
}

class _V5AlertsPanelState extends State<V5AlertsPanel> {
  final seen = <String>{};
  bool initialized = false;
  late Stream<List<Map<String, dynamic>>> alerts;

  @override
  void initState() {
    super.initState();
    alerts = VetBackend.instance.alertsStream(widget.farmId);
  }

  @override
  void didUpdateWidget(covariant V5AlertsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.farmId != widget.farmId) {
      initialized = false;
      seen.clear();
      alerts = VetBackend.instance.alertsStream(widget.farmId);
    }
  }

  void _retry() {
    setState(() {
      initialized = false;
      alerts = VetBackend.instance.alertsStream(widget.farmId);
    });
  }

  void _onRows(List<Map<String, dynamic>> rows) {
    final ids = rows
        .map((e) => e['id']?.toString())
        .whereType<String>()
        .toSet();
    if (!initialized) {
      seen.addAll(ids);
      initialized = true;
      return;
    }
    final fresh = ids.difference(seen);
    if (fresh.isNotEmpty) {
      seen.addAll(fresh);
      SystemSound.play(SystemSoundType.alert);
      HapticFeedback.heavyImpact();
    }
  }

  String _metric(String value) => switch (value) {
    'body_temperature_c' => tr(
      context,
      'Body temperature',
      'حرارة جسم الحيوان',
      'Lichaamstemperatuur',
    ),
    'ambient_temperature_c' => tr(
      context,
      'Barn temperature',
      'حرارة العنبر',
      'Staltemperatuur',
    ),
    'humidity_percent' => tr(
      context,
      'Humidity',
      'الرطوبة',
      'Luchtvochtigheid',
    ),
    'activity_index' => tr(context, 'Activity', 'النشاط', 'Activiteit'),
    'steps' => tr(context, 'Steps', 'الخطوات', 'Stappen'),
    'distance_from_herd_m' => tr(
      context,
      'Distance from herd',
      'البعد عن القطيع',
      'Afstand tot kudde',
    ),
    'lying_minutes' => tr(
      context,
      'Lying / resting',
      'الرقاد / الراحة',
      'Liggen / rusten',
    ),
    'feeding_minutes' => tr(context, 'Feeding', 'الأكل', 'Voeren'),
    'rumination_minutes' => tr(context, 'Rumination', 'الاجترار', 'Herkauwen'),
    _ => value.replaceAll('_', ' '),
  };

  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<List<Map<String, dynamic>>>(
    stream: alerts,
    builder: (context, snapshot) {
      final rows = snapshot.data ?? const <Map<String, dynamic>>[];
      if (snapshot.hasData)
        WidgetsBinding.instance.addPostFrameCallback((_) => _onRows(rows));
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _StepTitle(
            icon: Icons.warning_amber_rounded,
            title: tr(
              context,
              'Health & sensor alerts',
              'إنذارات الصحة والحساسات',
              'Gezondheids- & sensormeldingen',
            ),
            subtitle: tr(
              context,
              'AI risk alerts plus real configured sensor thresholds. New alerts make a sound while Vet AI is active.',
              'إنذارات خطورة AI + حدود الحساسات الحقيقية اللي إنت ضابطها. الإنذار الجديد يطلع صوت واهتزاز وVet AI مفتوح.',
              'AI-risicomeldingen plus echte ingestelde sensordrempels. Nieuwe meldingen geven geluid/trilling terwijl Vet AI actief is.',
            ),
          ),
          const SizedBox(height: 18),
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            ),
          if (snapshot.hasError) ...[
            _Notice(
              icon: Icons.cloud_off_rounded,
              title: tr(
                context,
                'Could not load alerts',
                'تعذر تحميل الإنذارات',
                'Meldingen konden niet worden geladen',
              ),
              text: tr(
                context,
                'The live alert connection failed. Vet AI will not leave this page loading forever; retry the connection.',
                'فشل اتصال الإنذارات المباشر. Vet AI مش هيسيب الصفحة تحمل للأبد؛ جرّب إعادة الاتصال.',
                'De live meldingsverbinding is mislukt. Vet AI blijft niet eindeloos laden; probeer opnieuw te verbinden.',
              ),
              danger: true,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(
                tr(context, 'Reconnect', 'إعادة الاتصال', 'Opnieuw verbinden'),
              ),
            ),
          ],
          if (!snapshot.hasError && snapshot.hasData && rows.isEmpty)
            _Notice(
              icon: Icons.check_circle_outline_rounded,
              title: tr(
                context,
                'No active alerts',
                'لا توجد إنذارات حالية',
                'Geen actieve meldingen',
              ),
              text: tr(
                context,
                'No AI or configured real-sensor alert is stored for this farm.',
                'مفيش إنذار AI أو إنذار حساس حقيقي متضبط محفوظ للمزرعة دي.',
                'Er is geen AI- of ingestelde echte-sensormelding voor deze boerderij opgeslagen.',
              ),
            ),
          if (!snapshot.hasError)
            for (final a in rows)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: Icon(
                    a['risk'] == 'red'
                        ? Icons.error_rounded
                        : Icons.warning_rounded,
                    size: 36,
                    color: a['risk'] == 'red'
                        ? VetColors.red
                        : a['risk'] == 'orange'
                        ? VetColors.orange
                        : VetColors.history,
                  ),
                  title: Text(
                    a['title']?.toString() ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  subtitle: a['source'] == 'sensor'
                      ? Text(
                          '${_metric(a['metric']?.toString() ?? '')}: ${a['value_numeric'] ?? '—'}\n${tr(context, 'Configured threshold', 'الحد المتضبط', 'Ingestelde drempel')}: ${a['threshold_text'] ?? '—'}',
                        )
                      : Text(a['details']?.toString() ?? ''),
                  isThreeLine: a['source'] == 'sensor',
                ),
              ),
          const SizedBox(height: 10),
          Text(
            tr(
              context,
              'Background push notifications when the app is fully closed require APNs/push credentials and are a separate deployment step. This screen never fabricates sensor alerts.',
              'الإشعارات في الخلفية والتطبيق مقفول تمامًا محتاجة إعداد APNs/Push منفصل. الشاشة دي ما بتختلقش إنذارات حساسات.',
              'Achtergrond-pushmeldingen wanneer de app volledig gesloten is vereisen aparte APNs/pushconfiguratie. Dit scherm verzint nooit sensormeldingen.',
            ),
            style: const TextStyle(
              color: VetColors.muted,
              fontSize: 11.5,
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      );
    },
  );
}

class V5HistoryPanel extends StatelessWidget {
  const V5HistoryPanel({super.key, required this.farmId});
  final String farmId;

  @override
  Widget build(
    BuildContext context,
  ) => FutureBuilder<List<Map<String, dynamic>>>(
    future: VetBackend.instance.recentAssessments(farmId),
    builder: (context, s) => ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _StepTitle(
          icon: Icons.manage_history_rounded,
          title: tr(
            context,
            'Assessment history',
            'سجل الفحوصات',
            'Beoordelingshistorie',
          ),
          subtitle: tr(
            context,
            'Stored cases and their real processing status.',
            'الحالات المحفوظة وحالة معالجتها الحقيقية.',
            'Opgeslagen casussen en hun echte verwerkingsstatus.',
          ),
        ),
        const SizedBox(height: 18),
        if (s.connectionState != ConnectionState.done)
          const Center(child: CircularProgressIndicator()),
        if (s.connectionState == ConnectionState.done && (s.data ?? []).isEmpty)
          _Notice(
            icon: Icons.inbox_outlined,
            title: tr(
              context,
              'No assessments yet',
              'لا توجد فحوصات حتى الآن',
              'Nog geen beoordelingen',
            ),
            text: tr(
              context,
              'Your first AI Scan case will appear here.',
              'أول حالة من فحص AI ستظهر هنا.',
              'Je eerste AI-scan verschijnt hier.',
            ),
          ),
        for (final a in s.data ?? [])
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: const Icon(
                Icons.description_outlined,
                size: 32,
                color: VetColors.primary,
              ),
              title: Text(
                '${a['species_code'] ?? a['animal_group'] ?? ''} • ${a['risk'] ?? ''}',
              ),
              subtitle: Text('${a['status'] ?? ''}\n${a['created_at'] ?? ''}'),
              isThreeLine: true,
            ),
          ),
      ],
    ),
  );
}

class V5AccountHub extends StatelessWidget {
  const V5AccountHub({super.key, required this.farm});
  final Map<String, dynamic> farm;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const _MiniBrand(),
            const SizedBox(width: 12),
            Text(tr(context, 'Account', 'الحساب', 'Account')),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _MenuTile(
            icon: Icons.account_circle_outlined,
            title: tr(
              context,
              'Profile & farm data',
              'الملف الشخصي وبيانات المزرعة',
              'Profiel & boerderijgegevens',
            ),
            subtitle: tr(
              context,
              'View and edit the information you entered.',
              'عرض وتعديل كل البيانات التي أدخلتها.',
              'Bekijk en wijzig de ingevoerde gegevens.',
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => V5ProfileScreen(farm: farm)),
            ),
          ),
          _MenuTile(
            icon: Icons.workspace_premium_outlined,
            title: tr(context, 'Subscription', 'الاشتراك', 'Abonnement'),
            subtitle: tr(
              context,
              'Animal groups, monthly/annual and sensor access.',
              'أنواع الحيوانات والشهري/السنوي وصلاحية الحساسات.',
              'Diergroepen, maandelijks/jaarlijks en sensortoegang.',
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => V5SubscriptionScreen(farm: farm),
              ),
            ),
          ),
          _MenuTile(
            icon: Icons.language_rounded,
            title: tr(context, 'Language', 'اللغة', 'Taal'),
            subtitle: tr(
              context,
              'Automatic device language or choose manually.',
              'تلقائي حسب لغة الهاتف أو اختر اللغة يدويًا.',
              'Automatisch volgens het toestel of handmatig kiezen.',
            ),
            onTap: () => showVetLanguagePicker(context),
          ),
          _MenuTile(
            icon: Icons.support_agent_rounded,
            title: tr(context, 'Support chat', 'شات الدعم', 'Supportchat'),
            subtitle: tr(
              context,
              'Realtime private chat with photos, marked images and files.',
              'شات خاص مباشر مع الصور والتعديل عليها والملفات.',
              'Privé realtime chat met foto’s, gemarkeerde beelden en bestanden.',
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => V6SupportScreen(farmId: farm['id'] as String),
              ),
            ),
          ),
          FutureBuilder<bool>(
            future: VetBackend.instance.isSupportAgent(),
            builder: (context, agent) => agent.data == true
                ? _MenuTile(
                    icon: Icons.admin_panel_settings_outlined,
                    title: tr(
                      context,
                      'Company support console',
                      'كونسول دعم الشركة',
                      'Bedrijfssupportconsole',
                    ),
                    subtitle: tr(
                      context,
                      'See customer support threads and reply as Vet AI Support.',
                      'شوف محادثات العملاء ورد عليهم باسم دعم Vet AI.',
                      'Bekijk klantgesprekken en antwoord als Vet AI Support.',
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const VetSupportConsoleScreen(),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          _MenuTile(
            icon: Icons.info_outline_rounded,
            title: tr(
              context,
              'Vet AI information & legal',
              'معلومات وسياسات Vet AI',
              'Vet AI informatie & juridisch',
            ),
            subtitle: tr(
              context,
              'About, mission, safety, knowledge, privacy and terms.',
              'عن Vet AI والهدف والأمان والمعرفة والخصوصية والشروط.',
              'Over Vet AI, missie, veiligheid, kennis, privacy en voorwaarden.',
            ),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const VetLegalHubScreen()),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () async {
              await VetBackend.instance.signOut();
              if (context.mounted)
                Navigator.of(context).popUntil((r) => r.isFirst);
            },
            icon: const Icon(Icons.logout_rounded, size: 29),
            label: Text(tr(context, 'Sign out', 'تسجيل الخروج', 'Uitloggen')),
          ),
        ],
      ),
    );
  }
}

class V5ProfileScreen extends StatefulWidget {
  const V5ProfileScreen({super.key, required this.farm});
  final Map<String, dynamic> farm;

  @override
  State<V5ProfileScreen> createState() => _V5ProfileScreenState();
}

class _V5ProfileScreenState extends State<V5ProfileScreen> {
  bool loading = true;
  bool saving = false;
  Map<String, dynamic>? profile;
  late final Map<String, TextEditingController> c;
  late final Set<String> profileSelectedGroups;
  late final Set<String> profileLivestockSpecies;
  late final Set<String> profileBirdSpecies;
  late final Set<String> profileDogBreeds;

  @override
  void initState() {
    super.initState();
    final f = widget.farm;
    profileLivestockSpecies = ((f['livestock_species'] as List?) ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toSet();
    profileBirdSpecies = ((f['bird_species'] as List?) ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toSet();
    profileDogBreeds = ((f['dog_breeds'] as List?) ?? const [])
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toSet();
    final livestockCount = ((f['livestock_count'] as num?)?.toInt() ?? 0);
    final birdCount = ((f['poultry_count'] as num?)?.toInt() ?? 0);
    final dogCount = ((f['dog_count'] as num?)?.toInt() ?? 0);
    profileSelectedGroups = <String>{
      if (livestockCount > 0 || profileLivestockSpecies.isNotEmpty) 'livestock',
      if (birdCount > 0 || profileBirdSpecies.isNotEmpty) 'poultry',
      if (dogCount > 0 || f['dog_enabled'] == true) 'dogs',
    };
    if (profileSelectedGroups.isEmpty) profileSelectedGroups.add('livestock');
    if (profileLivestockSpecies.isEmpty && livestockCount > 0)
      profileLivestockSpecies.add('cattle');
    if (profileBirdSpecies.isEmpty && birdCount > 0)
      profileBirdSpecies.add('chicken');
    c = {
      'full_name': TextEditingController(),
      'phone': TextEditingController(),
      'job_title': TextEditingController(),
      'company_name': TextEditingController(text: '${f['company_name'] ?? ''}'),
      'farm_name': TextEditingController(text: '${f['farm_name'] ?? ''}'),
      'country': TextEditingController(text: '${f['country'] ?? ''}'),
      'region': TextEditingController(text: '${f['region'] ?? ''}'),
      'worker_count': TextEditingController(text: '${f['worker_count'] ?? 0}'),
      'veterinarian_count': TextEditingController(
        text: '${f['veterinarian_count'] ?? 0}',
      ),
      'barn_count': TextEditingController(text: '${f['barn_count'] ?? 1}'),
      'area': TextEditingController(text: '${f['total_indoor_area_m2'] ?? 0}'),
      'livestock_count': TextEditingController(
        text: '${f['livestock_count'] ?? 0}',
      ),
      'poultry_count': TextEditingController(
        text: '${f['poultry_count'] ?? 0}',
      ),
      'dog_count': TextEditingController(text: '${f['dog_count'] ?? 0}'),
      'breeds': TextEditingController(text: '${f['breeds'] ?? ''}'),
      'age_range': TextEditingController(text: '${f['age_range'] ?? ''}'),
      'production_purpose': TextEditingController(
        text: '${f['production_purpose'] ?? ''}',
      ),
      'ventilation_system': TextEditingController(
        text: '${f['ventilation_system'] ?? ''}',
      ),
      'vaccination_notes': TextEditingController(
        text: '${f['vaccination_notes'] ?? ''}',
      ),
      'disease_history': TextEditingController(
        text: '${f['disease_history'] ?? ''}',
      ),
    };
    load();
  }

  Future<void> load() async {
    profile = await VetBackend.instance.myProfile();
    if (!mounted) return;
    c['full_name']!.text = '${profile?['full_name'] ?? ''}';
    c['phone']!.text = '${profile?['phone'] ?? ''}';
    c['job_title']!.text = '${profile?['job_title'] ?? ''}';
    setState(() => loading = false);
  }

  int _i(String key, [int fallback = 0]) =>
      int.tryParse(c[key]!.text.trim()) ?? fallback;
  double _d(String key) =>
      double.tryParse(c[key]!.text.trim().replaceAll(',', '.')) ?? 0;

  void _toggleProfileGroup(String group) {
    setState(() {
      if (profileSelectedGroups.contains(group)) {
        if (profileSelectedGroups.length <= 1) return;
        profileSelectedGroups.remove(group);
        if (group == 'livestock') {
          c['livestock_count']!.text = '0';
          profileLivestockSpecies.clear();
        } else if (group == 'poultry') {
          c['poultry_count']!.text = '0';
          profileBirdSpecies.clear();
        } else if (group == 'dogs') {
          c['dog_count']!.text = '0';
          profileDogBreeds.clear();
        }
      } else {
        profileSelectedGroups.add(group);
        if (group == 'livestock') {
          if (_i('livestock_count') == 0) c['livestock_count']!.text = '1';
          if (profileLivestockSpecies.isEmpty)
            profileLivestockSpecies.add('cattle');
        } else if (group == 'poultry') {
          if (_i('poultry_count') == 0) c['poultry_count']!.text = '1';
          if (profileBirdSpecies.isEmpty) profileBirdSpecies.add('chicken');
        } else if (group == 'dogs') {
          if (_i('dog_count') == 0) c['dog_count']!.text = '1';
        }
      }
    });
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      await VetBackend.instance.updateProfile(
        fullName: c['full_name']!.text,
        phone: c['phone']!.text,
        jobTitle: c['job_title']!.text,
        preferredLanguage: Localizations.localeOf(context).languageCode,
      );
      final updatedFarm = await VetBackend.instance.updateFarm(
        widget.farm['id'] as String,
        companyName: c['company_name']!.text,
        farmName: c['farm_name']!.text,
        country: c['country']!.text,
        region: c['region']!.text,
        workerCount: _i('worker_count'),
        veterinarianCount: _i('veterinarian_count'),
        barnCount: _i('barn_count', 1),
        totalIndoorAreaM2: _d('area'),
        livestockCount: profileSelectedGroups.contains('livestock')
            ? (_i('livestock_count') == 0 ? 1 : _i('livestock_count'))
            : 0,
        poultryCount: profileSelectedGroups.contains('poultry')
            ? (_i('poultry_count') == 0 ? 1 : _i('poultry_count'))
            : 0,
        dogCount: profileSelectedGroups.contains('dogs')
            ? (_i('dog_count') == 0 ? 1 : _i('dog_count'))
            : 0,
        breeds: c['breeds']!.text,
        ageRange: c['age_range']!.text,
        productionPurpose: c['production_purpose']!.text,
        ventilationSystem: c['ventilation_system']!.text,
        vaccinationNotes: c['vaccination_notes']!.text,
        diseaseHistory: c['disease_history']!.text,
      );
      await VetBackend.instance.saveFarmAnimalProfile(
        widget.farm['id'] as String,
        livestockSpecies: profileSelectedGroups.contains('livestock')
            ? profileLivestockSpecies
            : <String>{},
        birdSpecies: profileSelectedGroups.contains('poultry')
            ? profileBirdSpecies
            : <String>{},
        dogEnabled: profileSelectedGroups.contains('dogs'),
        dogBreeds: profileSelectedGroups.contains('dogs')
            ? profileDogBreeds
            : <String>{},
      );
      widget.farm
        ..addAll(updatedFarm)
        ..['livestock_species'] = profileSelectedGroups.contains('livestock')
            ? (profileLivestockSpecies.toList()..sort())
            : <String>[]
        ..['bird_species'] = profileSelectedGroups.contains('poultry')
            ? (profileBirdSpecies.toList()..sort())
            : <String>[]
        ..['dog_enabled'] = profileSelectedGroups.contains('dogs')
        ..['dog_breeds'] = profileSelectedGroups.contains('dogs')
            ? (profileDogBreeds.toList()..sort())
            : <String>[];
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                context,
                'Profile saved.',
                'تم حفظ الملف.',
                'Profiel opgeslagen.',
              ),
            ),
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${tr(context, 'Could not save the profile', 'تعذر حفظ الملف', 'Profiel kon niet worden opgeslagen')}: ${e.toString()}',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (loading)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(
        title: Text(
          tr(
            context,
            'Profile & farm',
            'الملف والمزرعة',
            'Profiel & boerderij',
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _ProfileHeroCard(
            name: c['full_name']!.text,
            email: VetBackend.instance.currentUser?.email ?? '',
            farmName: c['farm_name']!.text,
          ),
          const SizedBox(height: 18),
          _StepTitle(
            icon: Icons.account_circle_outlined,
            title: tr(
              context,
              'Personal details',
              'البيانات الشخصية',
              'Persoonlijke gegevens',
            ),
            subtitle: VetBackend.instance.currentUser?.email ?? '',
          ),
          const SizedBox(height: 16),
          _Field(
            controller: c['full_name']!,
            label: tr(context, 'Full name', 'الاسم الكامل', 'Volledige naam'),
            icon: Icons.badge_outlined,
          ),
          const SizedBox(height: 10),
          _Field(
            controller: c['phone']!,
            label: tr(context, 'Phone', 'الهاتف', 'Telefoon'),
            icon: Icons.phone_outlined,
          ),
          const SizedBox(height: 10),
          _Field(
            controller: c['job_title']!,
            label: tr(
              context,
              'Role / title',
              'الصفة / الوظيفة',
              'Rol / functie',
            ),
            icon: Icons.work_outline_rounded,
          ),
          const SizedBox(height: 22),
          _StepTitle(
            icon: Icons.home_work_outlined,
            title: tr(
              context,
              'Farm details',
              'بيانات المزرعة',
              'Boerderijgegevens',
            ),
            subtitle: tr(
              context,
              'All onboarding data is editable here.',
              'كل بيانات التسجيل قابلة للتعديل هنا.',
              'Alle onboardinggegevens zijn hier bewerkbaar.',
            ),
          ),
          const SizedBox(height: 16),
          _AnimalGroupMultiSelect(
            selected: profileSelectedGroups,
            onToggle: _toggleProfileGroup,
          ),
          const SizedBox(height: 14),
          if (profileSelectedGroups.contains('livestock')) ...[
            _SpeciesMultiSelect(
              title: tr(
                context,
                'Livestock types used by AI',
                'أنواع المواشي المستخدمة في الفحص',
                'Veetypen voor AI',
              ),
              options: vetLivestockSpecies,
              selected: profileLivestockSpecies,
              onChanged: (next) => setState(() {
                profileLivestockSpecies
                  ..clear()
                  ..addAll(next);
              }),
            ),
            const SizedBox(height: 10),
            _Field(
              controller: c['livestock_count']!,
              label: tr(
                context,
                'Livestock count',
                'عدد المواشي',
                'Aantal vee',
              ),
              icon: Icons.pets_rounded,
              keyboard: TextInputType.number,
            ),
            const SizedBox(height: 12),
          ],
          if (profileSelectedGroups.contains('poultry')) ...[
            _SpeciesMultiSelect(
              title: tr(
                context,
                'Bird types used by AI',
                'أنواع الطيور المستخدمة في الفحص',
                'Vogeltypen voor AI',
              ),
              options: vetBirdSpecies,
              selected: profileBirdSpecies,
              onChanged: (next) => setState(() {
                profileBirdSpecies
                  ..clear()
                  ..addAll(next);
              }),
            ),
            const SizedBox(height: 10),
            _Field(
              controller: c['poultry_count']!,
              label: tr(context, 'Bird count', 'عدد الطيور', 'Aantal vogels'),
              icon: Icons.egg_alt_rounded,
              keyboard: TextInputType.number,
            ),
            const SizedBox(height: 12),
          ],
          if (profileSelectedGroups.contains('dogs')) ...[
            _DogBreedMultiSelect(
              title: tr(context, 'Dog breeds', 'سلالات الكلاب', 'Hondenrassen'),
              selected: profileDogBreeds,
              onChanged: (next) => setState(() {
                profileDogBreeds
                  ..clear()
                  ..addAll(next);
              }),
            ),
            const SizedBox(height: 10),
            _Field(
              controller: c['dog_count']!,
              label: tr(context, 'Dog count', 'عدد الكلاب', 'Aantal honden'),
              icon: Icons.pets_rounded,
              keyboard: TextInputType.number,
            ),
            const SizedBox(height: 12),
          ],
          for (final spec in <(String, String, IconData)>[
            (
              'company_name',
              tr(context, 'Company', 'الشركة', 'Bedrijf'),
              Icons.apartment_rounded,
            ),
            (
              'farm_name',
              tr(context, 'Farm name', 'اسم المزرعة', 'Boerderijnaam'),
              Icons.home_work_outlined,
            ),
            (
              'country',
              tr(context, 'Country', 'الدولة', 'Land'),
              Icons.public_rounded,
            ),
            (
              'region',
              tr(context, 'Region', 'المنطقة', 'Regio'),
              Icons.location_on_outlined,
            ),
            (
              'worker_count',
              tr(context, 'Workers', 'العمال', 'Medewerkers'),
              Icons.groups_2_outlined,
            ),
            (
              'veterinarian_count',
              tr(context, 'Veterinarians', 'الأطباء البيطريون', 'Dierenartsen'),
              Icons.medical_services_outlined,
            ),
            (
              'barn_count',
              tr(context, 'Barns', 'العنابر', 'Stallen'),
              Icons.warehouse_outlined,
            ),
            (
              'area',
              tr(
                context,
                'Indoor area m²',
                'المساحة الداخلية م²',
                'Binnenoppervlak m²',
              ),
              Icons.square_foot_rounded,
            ),
            (
              'breeds',
              tr(context, 'Breeds / strains', 'السلالات', 'Rassen / lijnen'),
              Icons.category_outlined,
            ),
            (
              'age_range',
              tr(
                context,
                'Age / production cycle',
                'العمر / دورة الإنتاج',
                'Leeftijd / productiecyclus',
              ),
              Icons.calendar_month_outlined,
            ),
            (
              'production_purpose',
              tr(context, 'Production purpose', 'غرض التربية', 'Productiedoel'),
              Icons.flag_outlined,
            ),
            (
              'ventilation_system',
              tr(
                context,
                'Ventilation / housing',
                'التهوية / الإيواء',
                'Ventilatie / huisvesting',
              ),
              Icons.air_rounded,
            ),
            (
              'vaccination_notes',
              tr(
                context,
                'Vaccination program',
                'برنامج التحصينات',
                'Vaccinatieprogramma',
              ),
              Icons.vaccines_outlined,
            ),
            (
              'disease_history',
              tr(
                context,
                'Disease / mortality history',
                'تاريخ الأمراض / النفوق',
                'Ziekte- / sterftegeschiedenis',
              ),
              Icons.history_edu_outlined,
            ),
          ]) ...[
            _Field(
              controller: c[spec.$1]!,
              label: spec.$2,
              icon: spec.$3,
              lines:
                  spec.$1 == 'vaccination_notes' || spec.$1 == 'disease_history'
                  ? 3
                  : 1,
              keyboard:
                  [
                    'worker_count',
                    'veterinarian_count',
                    'barn_count',
                    'livestock_count',
                    'poultry_count',
                    'dog_count',
                    'area',
                  ].contains(spec.$1)
                  ? TextInputType.number
                  : null,
            ),
            const SizedBox(height: 10),
          ],
          const SizedBox(height: 10),
          ElevatedButton.icon(
            onPressed: saving ? null : save,
            icon: saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined, size: 29),
            label: Text(
              tr(
                context,
                'Save changes',
                'حفظ التعديلات',
                'Wijzigingen opslaan',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class V5SubscriptionScreen extends StatefulWidget {
  const V5SubscriptionScreen({super.key, required this.farm});
  final Map<String, dynamic> farm;
  @override
  State<V5SubscriptionScreen> createState() => _V5SubscriptionScreenState();
}

class _V5SubscriptionScreenState extends State<V5SubscriptionScreen> {
  late String tier;
  late String cycle;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    tier = widget.farm['subscription_tier']?.toString() ?? 'software';
    cycle = widget.farm['billing_cycle']?.toString() ?? 'monthly';
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      await VetBackend.instance.updateSubscription(
        widget.farm['id'] as String,
        subscriptionTier: tier,
        billingCycle: cycle,
      );
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = [
      if (((widget.farm['livestock_count'] as num?)?.toInt() ?? 0) > 0)
        tr(context, 'Livestock', 'مواشي', 'Vee'),
      if (((widget.farm['poultry_count'] as num?)?.toInt() ?? 0) > 0)
        tr(context, 'Poultry', 'دواجن', 'Pluimvee'),
      if (((widget.farm['dog_count'] as num?)?.toInt() ?? 0) > 0)
        tr(context, 'Dogs', 'كلاب', 'Honden'),
    ].join(' • ');
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(context, 'Subscription', 'الاشتراك', 'Abonnement')),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _StepTitle(
            icon: Icons.workspace_premium_outlined,
            title: tr(
              context,
              'Plan for $groups',
              'الخطة لـ $groups',
              'Plan voor $groups',
            ),
            subtitle: tr(
              context,
              'Feature access is enforced immediately. Billing collection is still not active.',
              'صلاحيات المزايا تتطبق فورًا. تحصيل الدفع غير مفعّل بعد.',
              'Functietoegang wordt direct toegepast. Betalingen worden nog niet geïnd.',
            ),
          ),
          const SizedBox(height: 18),
          _PlanCard(
            selected: tier == 'software',
            icon: Icons.health_and_safety_outlined,
            title: tr(
              context,
              'Software only',
              'البرنامج فقط',
              'Alleen software',
            ),
            lines: [
              tr(
                context,
                'AI Scan + history + alerts',
                'فحص AI + السجل + الإنذارات',
                'AI-scan + historie + meldingen',
              ),
              tr(
                context,
                'Sensors locked',
                'الحساسات مقفلة',
                'Sensoren vergrendeld',
              ),
            ],
            onTap: () => setState(() => tier = 'software'),
          ),
          const SizedBox(height: 12),
          _PlanCard(
            selected: tier == 'smart_monitoring',
            icon: Icons.sensors_rounded,
            title: tr(
              context,
              'Software + smart monitoring',
              'البرنامج + المراقبة الذكية',
              'Software + slimme monitoring',
            ),
            lines: [
              tr(
                context,
                'Software features + real connected sensors',
                'مزايا البرنامج + الحساسات الحقيقية المتصلة',
                'Softwarefuncties + echte gekoppelde sensoren',
              ),
              tr(
                context,
                'No simulated telemetry',
                'بدون بيانات حساسات محاكاة',
                'Geen gesimuleerde telemetrie',
              ),
            ],
            onTap: () => setState(() => tier = 'smart_monitoring'),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(
                value: 'monthly',
                icon: const Icon(Icons.calendar_view_month_rounded, size: 27),
                label: Text(tr(context, 'Monthly', 'شهري', 'Maandelijks')),
              ),
              ButtonSegment(
                value: 'annual',
                icon: const Icon(Icons.event_repeat_rounded, size: 27),
                label: Text(tr(context, 'Annual', 'سنوي', 'Jaarlijks')),
              ),
            ],
            selected: {cycle},
            onSelectionChanged: (v) => setState(() => cycle = v.first),
          ),
          const SizedBox(height: 18),
          _Notice(
            icon: Icons.info_outline_rounded,
            title: tr(
              context,
              'Payment integration',
              'تكامل الدفع',
              'Betalingsintegratie',
            ),
            text: tr(
              context,
              'This page currently saves the selected entitlement. A payment provider still has to be integrated before charging customers.',
              'هذه الصفحة تحفظ صلاحية الخطة المختارة حاليًا. ما زال يجب ربط مزود دفع قبل تحصيل أموال من العملاء.',
              'Deze pagina slaat nu de gekozen rechten op. Er moet nog een betaalprovider worden geïntegreerd voordat klanten worden belast.',
            ),
          ),
          const SizedBox(height: 18),
          ElevatedButton.icon(
            onPressed: saving ? null : save,
            icon: saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline_rounded, size: 29),
            label: Text(tr(context, 'Save plan', 'حفظ الخطة', 'Plan opslaan')),
          ),
        ],
      ),
    );
  }
}

class V5SupportScreen extends StatefulWidget {
  const V5SupportScreen({super.key, required this.farmId});
  final String farmId;
  @override
  State<V5SupportScreen> createState() => _V5SupportScreenState();
}

class _V5SupportScreenState extends State<V5SupportScreen> {
  final message = TextEditingController();
  String? threadId;
  bool sending = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final id = await VetBackend.instance.getOrCreateSupportThread(
      widget.farmId,
    );
    if (mounted) setState(() => threadId = id);
  }

  Future<void> send() async {
    if (threadId == null || message.text.trim().isEmpty) return;
    final text = message.text;
    message.clear();
    setState(() => sending = true);
    try {
      await VetBackend.instance.sendSupportMessage(threadId!, text);
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(
              Icons.support_agent_rounded,
              size: 32,
              color: VetColors.primary,
            ),
            const SizedBox(width: 10),
            Text(tr(context, 'Vet AI Support', 'دعم Vet AI', 'Vet AI Support')),
          ],
        ),
      ),
      body: threadId == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: _Notice(
                    icon: Icons.verified_outlined,
                    title: tr(
                      context,
                      'Real support inbox',
                      'صندوق دعم حقيقي',
                      'Echte support-inbox',
                    ),
                    text: tr(
                      context,
                      'Messages are stored in your account and update live. A system receipt is automatic; a human reply appears only when a support operator answers.',
                      'الرسائل محفوظة في حسابك وتتحدث مباشرة. تأكيد الاستلام آلي، والرد البشري يظهر فقط عندما يرد موظف دعم.',
                      'Berichten worden in je account opgeslagen en live bijgewerkt. De ontvangstbevestiging is automatisch; een menselijk antwoord verschijnt alleen wanneer support reageert.',
                    ),
                  ),
                ),
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: VetBackend.instance.supportMessagesStream(
                      threadId!,
                    ),
                    builder: (context, s) {
                      final rows = s.data ?? [];
                      if (!s.hasData)
                        return const Center(child: CircularProgressIndicator());
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final m = rows[i];
                          final mine = m['sender_role'] == 'user';
                          return Align(
                            alignment: mine
                                ? AlignmentDirectional.centerEnd
                                : AlignmentDirectional.centerStart,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 11,
                              ),
                              constraints: const BoxConstraints(maxWidth: 310),
                              decoration: BoxDecoration(
                                color: mine
                                    ? VetColors.surface3
                                    : VetColors.surface2,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m['message']?.toString() ?? '',
                                    style: const TextStyle(height: 1.35),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    m['sender_role'] == 'support'
                                        ? tr(
                                            context,
                                            'Support',
                                            'الدعم',
                                            'Support',
                                          )
                                        : m['sender_role'] == 'system'
                                        ? tr(
                                            context,
                                            'System',
                                            'النظام',
                                            'Systeem',
                                          )
                                        : tr(context, 'You', 'أنت', 'Jij'),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: VetColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: message,
                            maxLines: 3,
                            minLines: 1,
                            onSubmitted: (_) => send(),
                            decoration: InputDecoration(
                              hintText: tr(
                                context,
                                'Write a message…',
                                'اكتب رسالة…',
                                'Schrijf een bericht…',
                              ),
                              prefixIcon: const Icon(
                                Icons.chat_bubble_outline_rounded,
                                size: 27,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: sending ? null : send,
                          icon: const Icon(Icons.send_rounded, size: 29),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class V5AboutScreen extends StatelessWidget {
  const V5AboutScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr(context, 'About Vet AI', 'عن Vet AI', 'Over Vet AI')),
    ),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Center(child: _BrandLockup(markWidth: 150)),
        const SizedBox(height: 20),
        _Notice(
          icon: Icons.favorite_outline_rounded,
          title: tr(context, 'Purpose', 'الهدف', 'Doel'),
          text: tr(
            context,
            'Vet AI is being built to detect health changes earlier, organize evidence and help farmers and veterinarians act faster.',
            'يتم بناء Vet AI لاكتشاف التغيرات الصحية مبكرًا وتنظيم الأدلة ومساعدة المربين والأطباء البيطريين على التصرف أسرع.',
            'Vet AI wordt gebouwd om gezondheidsveranderingen eerder te signaleren, bewijs te structureren en boeren en dierenartsen sneller te laten handelen.',
          ),
        ),
        const SizedBox(height: 12),
        _Notice(
          icon: Icons.health_and_safety_outlined,
          title: tr(
            context,
            'Safety boundary',
            'حدود الأمان',
            'Veiligheidsgrens',
          ),
          text: tr(
            context,
            'One image is never treated as a definitive diagnosis. High-consequence disease patterns trigger conservative triage, biosecurity advice and veterinary/laboratory confirmation.',
            'لا يتم اعتبار صورة واحدة تشخيصًا نهائيًا. أنماط الأمراض عالية الخطورة تؤدي إلى فرز حذر وإرشادات أمان حيوي وتأكيد بيطري/معملي.',
            'Eén beeld geldt nooit als definitieve diagnose. Patronen van ernstige ziekten leiden tot conservatieve triage, bioveiligheidsadvies en veterinaire/laboratoriumbevestiging.',
          ),
        ),
        const SizedBox(height: 12),
        _Notice(
          icon: Icons.menu_book_outlined,
          title: tr(context, 'Knowledge base', 'قاعدة المعرفة', 'Kennisbank'),
          text: tr(
            context,
            'Production knowledge is source-backed and versioned. Conditions are added only after source review; the system will not claim to contain every disease in the world until that is genuinely true.',
            'معرفة الإنتاج مرتبطة بمصادر ومُصدّرة بإصدارات. لا تتم إضافة الحالات إلا بعد مراجعة المصدر، ولن يدّعي النظام احتواء كل أمراض العالم قبل أن يكون ذلك حقيقيًا.',
            'Productiekennis is brononderbouwd en geversioneerd. Aandoeningen worden pas na broncontrole toegevoegd; het systeem claimt niet alle ziekten ter wereld te bevatten voordat dat werkelijk zo is.',
          ),
        ),
      ],
    ),
  );
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboard,
    this.lines = 1,
    this.obscure = false,
    this.onSubmitted,
  });
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboard;
  final int lines;
  final bool obscure;
  final ValueChanged<String>? onSubmitted;
  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    keyboardType: keyboard,
    maxLines: obscure ? 1 : lines,
    obscureText: obscure,
    onSubmitted: onSubmitted,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, size: 28),
    ),
  );
}

class _StepTitle extends StatelessWidget {
  const _StepTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: VetColors.surface3,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, size: 31, color: VetColors.primary),
      ),
      const SizedBox(width: 13),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: VetColors.muted, height: 1.4),
            ),
          ],
        ),
      ),
    ],
  );
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.icon,
    required this.title,
    required this.text,
    this.danger = false,
  });
  final IconData icon;
  final String title;
  final String text;
  final bool danger;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: danger ? VetColors.softRed : VetColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: danger ? VetColors.red : VetColors.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 30, color: danger ? VetColors.red : VetColors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                text,
                style: const TextStyle(color: VetColors.muted, height: 1.42),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AnimalSprite extends StatelessWidget {
  const _AnimalSprite({
    required this.index,
    required this.size,
    this.radius = 10,
  });

  final int index;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    const columns = 5;
    const rows = 5;
    final col = index % columns;
    final row = index ~/ columns;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              left: -col * size,
              top: -row * size,
              width: size * columns,
              height: size * rows,
              child: Image.asset(
                'assets/icons/animal_sprite_v26.webp',
                fit: BoxFit.fill,
                filterQuality: FilterQuality.high,
                isAntiAlias: true,
                gaplessPlayback: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimalGroupBanner extends StatelessWidget {
  const _AnimalGroupBanner({
    required this.spriteIndex,
    required this.title,
    required this.text,
  });
  final int spriteIndex;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    decoration: BoxDecoration(
      color: VetColors.surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: VetColors.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _AnimalSprite(index: spriteIndex, size: 142, radius: 16),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                text,
                style: const TextStyle(
                  color: VetColors.muted,
                  height: 1.4,
                  fontSize: 13.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _AnimalChoice extends StatelessWidget {
  const _AnimalChoice({
    required this.group,
    required this.label,
    required this.asset,
    required this.selected,
    required this.onTap,
  });
  final String group;
  final String label;
  final String asset;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(18),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: selected ? VetColors.surface3 : VetColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? VetColors.primary : VetColors.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Row(
        children: [
          _AnimalSprite(
            index: group == 'poultry'
                ? 2
                : group == 'dogs'
                ? 1
                : 0,
            size: 86,
            radius: 12,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          Icon(
            selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded,
            size: 29,
            color: selected ? VetColors.primary : VetColors.muted,
          ),
        ],
      ),
    ),
  );
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.lines,
    required this.onTap,
  });
  final bool selected;
  final IconData icon;
  final String title;
  final List<String> lines;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: selected ? VetColors.surface3 : VetColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? VetColors.primary : VetColors.border,
          width: selected ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 34, color: VetColors.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 29,
                color: selected ? VetColors.primary : VetColors.muted,
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.check_rounded,
                    size: 21,
                    color: VetColors.muted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(
                        color: VetColors.muted,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    ),
  );
}

class _AnimalCount extends StatelessWidget {
  const _AnimalCount({
    required this.asset,
    required this.label,
    required this.value,
  });
  final String asset;
  final String label;
  final dynamic value;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      child: Column(
        children: [
          Center(
            child: _AnimalSprite(
              index: asset.contains('poultry')
                  ? 2
                  : asset.contains('dog')
                  ? 1
                  : 0,
              size: 164,
              radius: 14,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '$value',
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: VetColors.muted, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 11),
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      leading: Icon(icon, size: 34, color: VetColors.primary),
      title: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(subtitle),
      ),
      trailing: const Icon(Icons.chevron_right_rounded, size: 31),
      onTap: onTap,
    ),
  );
}

class _MiniBrand extends StatelessWidget {
  const _MiniBrand();
  @override
  Widget build(BuildContext context) => SvgPicture.asset(
    'assets/vet_ai_logo.svg',
    width: 64,
    height: 46,
    colorFilter: const ColorFilter.mode(VetColors.primary, BlendMode.srcIn),
  );
}

class _HeaderBrand extends StatelessWidget {
  const _HeaderBrand();
  @override
  Widget build(BuildContext context) => Row(
    textDirection: TextDirection.ltr,
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      Transform.translate(
        offset: const Offset(2, 0),
        child: SvgPicture.asset(
          'assets/vet_ai_logo.svg',
          width: 82,
          height: 56,
          colorFilter: const ColorFilter.mode(
            VetColors.primary,
            BlendMode.srcIn,
          ),
        ),
      ),
      const SizedBox(width: 0),
      Text.rich(
        TextSpan(
          children: [
            const TextSpan(
              text: 'Vet ',
              style: TextStyle(color: VetColors.text),
            ),
            const TextSpan(
              text: 'AI',
              style: TextStyle(color: VetColors.primary),
            ),
          ],
        ),
        style: const TextStyle(
          fontSize: 29,
          fontWeight: FontWeight.w900,
          letterSpacing: .1,
        ),
      ),
    ],
  );
}

class _BrandLockup extends StatelessWidget {
  const _BrandLockup({required this.markWidth});
  final double markWidth;
  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [
      SvgPicture.asset(
        'assets/vet_ai_logo.svg',
        width: markWidth,
        height: markWidth * .66,
        colorFilter: const ColorFilter.mode(VetColors.primary, BlendMode.srcIn),
      ),
      const SizedBox(height: 7),
      Text.rich(
        TextSpan(
          children: [
            const TextSpan(
              text: 'Vet ',
              style: TextStyle(color: VetColors.text),
            ),
            TextSpan(
              text: 'AI',
              style: TextStyle(color: VetColors.primary),
            ),
          ],
        ),
        style: const TextStyle(
          fontSize: 31,
          fontWeight: FontWeight.w900,
          letterSpacing: .2,
        ),
      ),
    ],
  );
}

class _FatalState extends StatelessWidget {
  const _FatalState({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 58,
              color: VetColors.red,
            ),
            const SizedBox(height: 14),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: VetBackend.instance.signOut,
              icon: const Icon(Icons.logout_rounded),
              label: Text(tr(context, 'Sign out', 'تسجيل الخروج', 'Uitloggen')),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProfileHeroCard extends StatelessWidget {
  const _ProfileHeroCard({
    required this.name,
    required this.email,
    required this.farmName,
  });

  final String name;
  final String email;
  final String farmName;

  @override
  Widget build(BuildContext context) {
    final displayName = name.trim().isEmpty
        ? tr(context, 'My profile', 'ملفي الشخصي', 'Mijn profiel')
        : name.trim();
    final displayFarm = farmName.trim().isEmpty
        ? tr(context, 'Farm profile', 'ملف المزرعة', 'Boerderijprofiel')
        : farmName.trim();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [
            VetColors.surface3,
            VetColors.softBlue.withValues(alpha: .72),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: VetColors.primary.withValues(alpha: .22)),
      ),
      child: Row(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .92),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: VetColors.primary.withValues(alpha: .20),
              ),
            ),
            child: const Icon(
              Icons.account_circle_rounded,
              size: 53,
              color: VetColors.primary,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  displayFarm,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: VetColors.primary,
                  ),
                ),
                if (email.trim().isNotEmpty) ...[
                  const SizedBox(height: 5),
                  Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: VetColors.muted,
                      fontSize: 13.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Icon(Icons.edit_outlined, color: VetColors.muted, size: 24),
        ],
      ),
    );
  }
}

class _AnimalVisualTile extends StatelessWidget {
  const _AnimalVisualTile({
    required this.spriteIndex,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
    this.imageSize = 86,
  });

  final int spriteIndex;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;
  final double imageSize;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: enabled ? 1 : .55,
    child: InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(18),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.fromLTRB(9, 10, 9, 11),
        decoration: BoxDecoration(
          color: selected
              ? VetColors.primary.withValues(alpha: .10)
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? VetColors.primary : VetColors.border,
            width: selected ? 2.2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: VetColors.primary.withValues(alpha: .08),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : const [],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _AnimalSprite(index: spriteIndex, size: imageSize, radius: 13),
                PositionedDirectional(
                  top: -3,
                  end: -3,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 120),
                    opacity: selected ? 1 : 0,
                    child: Container(
                      width: 27,
                      height: 27,
                      decoration: const BoxDecoration(
                        color: VetColors.primary,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 19,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14.5,
                height: 1.15,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _AnimalGroupVisualCard extends StatelessWidget {
  const _AnimalGroupVisualCard({
    required this.spriteIndex,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final int spriteIndex;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(20),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: selected
            ? VetColors.primary.withValues(alpha: .10)
            : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected ? VetColors.primary : VetColors.border,
          width: selected ? 2.2 : 1,
        ),
      ),
      child: Row(
        children: [
          _AnimalSprite(index: spriteIndex, size: 104, radius: 14),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: VetColors.muted,
                    fontSize: 12.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            selected ? Icons.check_circle_rounded : Icons.circle_outlined,
            size: 30,
            color: selected ? VetColors.primary : VetColors.muted,
          ),
        ],
      ),
    ),
  );
}

class _SpeciesMultiSelect extends StatelessWidget {
  const _SpeciesMultiSelect({
    required this.title,
    required this.options,
    required this.selected,
    required this.onChanged,
  });
  final String title;
  final List<VetAnimalSpecies> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VetColors.surface2,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: VetColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 560 ? 3 : 2;
              const gap = 10.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: options.map((item) {
                  final active = selected.contains(item.code);
                  final label = locale == 'ar'
                      ? item.ar
                      : locale == 'nl'
                      ? item.nl
                      : item.en;
                  return SizedBox(
                    width: width,
                    child: _AnimalVisualTile(
                      spriteIndex: item.spriteIndex,
                      label: label,
                      selected: active,
                      onTap: () {
                        final next = Set<String>.from(selected);
                        if (active) {
                          if (next.length > 1) next.remove(item.code);
                        } else {
                          next.add(item.code);
                        }
                        onChanged(next);
                      },
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AnimalGroupMultiSelect extends StatelessWidget {
  const _AnimalGroupMultiSelect({
    required this.selected,
    required this.onToggle,
  });
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    final groups =
        <(String, String, String, String, int, String, String, String)>[
          (
            'livestock',
            'Livestock',
            'المواشي',
            'Vee',
            0,
            'Cattle, buffalo, sheep, goats and horses',
            'أبقار وجاموس وأغنام وماعز وأحصنة',
            'Runderen, buffels, schapen, geiten en paarden',
          ),
          (
            'poultry',
            'Birds',
            'الطيور',
            'Vogels',
            2,
            'Chickens, chicks, ducks, turkeys and geese',
            'فراخ وكتاكيت وبط وديك رومي وأوز',
            'Kippen, kuikens, eenden, kalkoenen en ganzen',
          ),
          (
            'dogs',
            'Dogs',
            'الكلاب',
            'Honden',
            1,
            'Dog breeds used by the farm',
            'سلالات الكلاب الموجودة بالمزرعة',
            'Hondenrassen op de boerderij',
          ),
        ];
    final locale = Localizations.localeOf(context).languageCode;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VetColors.softBlue,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: VetColors.blue.withValues(alpha: .28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(
              context,
              'Animal sections',
              'أقسام الحيوانات',
              'Diercategorieën',
            ),
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < groups.length; i++) ...[
            _AnimalGroupVisualCard(
              spriteIndex: groups[i].$5,
              title: locale == 'ar'
                  ? groups[i].$3
                  : locale == 'nl'
                  ? groups[i].$4
                  : groups[i].$2,
              subtitle: locale == 'ar'
                  ? groups[i].$7
                  : locale == 'nl'
                  ? groups[i].$8
                  : groups[i].$6,
              selected: selected.contains(groups[i].$1),
              onTap: () => onToggle(groups[i].$1),
            ),
            if (i != groups.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _DogBreedMultiSelect extends StatelessWidget {
  const _DogBreedMultiSelect({
    required this.title,
    required this.selected,
    required this.onChanged,
  });
  final String title;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VetColors.surface2,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: VetColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 560 ? 3 : 2;
              const gap = 10.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: vetDogBreeds.map((breed) {
                  final active = selected.contains(breed.code);
                  final label = locale == 'ar'
                      ? breed.ar
                      : locale == 'nl'
                      ? breed.nl
                      : breed.en;
                  return SizedBox(
                    width: width,
                    child: _AnimalVisualTile(
                      spriteIndex: breed.spriteIndex,
                      label: label,
                      selected: active,
                      imageSize: 88,
                      onTap: () {
                        final next = Set<String>.from(selected);
                        active ? next.remove(breed.code) : next.add(breed.code);
                        onChanged(next);
                      },
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SpeciesSingleSelect extends StatelessWidget {
  const _SpeciesSingleSelect({
    required this.title,
    required this.options,
    required this.selectedCode,
    required this.enabled,
    required this.onChanged,
  });
  final String title;
  final List<VetAnimalSpecies> options;
  final String selectedCode;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VetColors.softBlue,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: VetColors.blue.withValues(alpha: .24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pets_outlined, color: VetColors.blue, size: 31),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = options.length == 1
                  ? 1
                  : constraints.maxWidth >= 560
                  ? 3
                  : 2;
              const gap = 10.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: options.map((item) {
                  final label = locale == 'ar'
                      ? item.ar
                      : locale == 'nl'
                      ? item.nl
                      : item.en;
                  return SizedBox(
                    width: width,
                    child: _AnimalVisualTile(
                      spriteIndex: item.spriteIndex,
                      label: label,
                      selected: selectedCode == item.code,
                      enabled: enabled,
                      imageSize: options.length == 1 ? 102 : 88,
                      onTap: () => onChanged(item.code),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DogBreedSingleSelect extends StatelessWidget {
  const _DogBreedSingleSelect({
    required this.title,
    required this.options,
    required this.selectedCode,
    required this.enabled,
    required this.onChanged,
  });

  final String title;
  final List<VetDogBreed> options;
  final String selectedCode;
  final bool enabled;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: VetColors.softBlue,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: VetColors.blue.withValues(alpha: .24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pets_rounded, color: VetColors.blue, size: 31),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = options.length == 1
                  ? 1
                  : constraints.maxWidth >= 560
                  ? 3
                  : 2;
              const gap = 10.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: options.map((breed) {
                  final label = locale == 'ar'
                      ? breed.ar
                      : locale == 'nl'
                      ? breed.nl
                      : breed.en;
                  return SizedBox(
                    width: width,
                    child: _AnimalVisualTile(
                      spriteIndex: breed.spriteIndex,
                      label: label,
                      selected: selectedCode == breed.code,
                      enabled: enabled,
                      imageSize: options.length == 1 ? 102 : 88,
                      onTap: () => onChanged(breed.code),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
