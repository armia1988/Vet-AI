import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'services/vet_backend.dart';
import 'theme/app_theme.dart';
import 'v2_app.dart' show BrandMark, V2Text;
import 'v3_app.dart' show V3DashboardScreen;

class VetAIAppV4 extends StatelessWidget {
  const VetAIAppV4({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Vet AI',
      theme: buildVetTheme(),
      supportedLocales: V2Text.supportedLocales,
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
      home: const V4AuthGate(),
    );
  }
}

String _copy(BuildContext context, String en, String ar, String nl) {
  switch (Localizations.localeOf(context).languageCode) {
    case 'ar':
      return ar;
    case 'nl':
      return nl;
    default:
      return en;
  }
}

class V4AuthGate extends StatefulWidget {
  const V4AuthGate({super.key});

  @override
  State<V4AuthGate> createState() => _V4AuthGateState();
}

class _V4AuthGateState extends State<V4AuthGate> {
  late final Stream<AuthState> stream;

  @override
  void initState() {
    super.initState();
    stream = VetBackend.instance.authChanges;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: stream,
      builder: (context, _) {
        if (!VetBackend.instance.signedIn) return const V4WelcomeAuthScreen();
        if (!VetBackend.instance.emailConfirmed) return const V4UnverifiedScreen();

        return FutureBuilder<Map<String, dynamic>?>(
          future: VetBackend.instance.myFarm(),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (snapshot.hasError) {
              return Scaffold(
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text('${snapshot.error}'),
                  ),
                ),
              );
            }
            if (snapshot.data == null) return const V4FarmSetupScreen();
            return V3DashboardScreen(farm: snapshot.data!);
          },
        );
      },
    );
  }
}

class V4WelcomeAuthScreen extends StatefulWidget {
  const V4WelcomeAuthScreen({super.key});

  @override
  State<V4WelcomeAuthScreen> createState() => _V4WelcomeAuthScreenState();
}

class _V4WelcomeAuthScreenState extends State<V4WelcomeAuthScreen> {
  bool createMode = true;
  bool busy = false;
  String? pendingEmail;

  final name = TextEditingController();
  final email = TextEditingController();
  final phone = TextEditingController();
  final password = TextEditingController();

  @override
  void dispose() {
    name.dispose();
    email.dispose();
    phone.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (email.text.trim().isEmpty || password.text.length < 6 || (createMode && name.text.trim().isEmpty)) {
      _show(_copy(
        context,
        'Complete the required fields. Password must be at least 6 characters.',
        'أكمل البيانات المطلوبة. كلمة المرور يجب أن تكون 6 أحرف على الأقل.',
        'Vul de verplichte velden in. Het wachtwoord moet minimaal 6 tekens bevatten.',
      ));
      return;
    }

    setState(() => busy = true);
    try {
      if (createMode) {
        final response = await VetBackend.instance.signUp(
          email: email.text,
          password: password.text,
          fullName: name.text,
          phone: phone.text,
          preferredLanguage: Localizations.localeOf(context).languageCode,
        );
        if (!mounted) return;
        if (response.session == null) {
          setState(() {
            pendingEmail = email.text.trim();
            createMode = false;
          });
        }
      } else {
        await VetBackend.instance.signIn(email: email.text, password: password.text);
      }
    } on AuthException catch (error) {
      if (mounted) _show(error.message, error: true);
    } catch (error) {
      if (mounted) _show('$error', error: true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _show(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Theme.of(context).colorScheme.error : VetColors.surface2,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = V2Text.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 30),
          children: [
            const Center(child: BrandMark(size: 132)),
            const SizedBox(height: 12),
            Text(
              t.t('tagline'),
              textAlign: TextAlign.center,
              style: const TextStyle(color: VetColors.muted, fontSize: 16, height: 1.45),
            ),
            const SizedBox(height: 28),
            if (pendingEmail != null) ...[
              _InfoPanel(
                icon: Icons.mark_email_read_outlined,
                title: _copy(context, 'Confirm your email', 'أكد بريدك الإلكتروني', 'Bevestig je e-mailadres'),
                body: _copy(
                  context,
                  'We sent a confirmation link to $pendingEmail. Tap it, then return to Vet AI. The link will open the app after the redirect setting is completed.',
                  'أرسلنا رابط تفعيل إلى $pendingEmail. اضغط عليه ثم ارجع إلى Vet AI. بعد ضبط التحويل سيفتح الرابط التطبيق مباشرة.',
                  'We hebben een bevestigingslink gestuurd naar $pendingEmail. Tik erop en keer daarna terug naar Vet AI. Na het instellen van de redirect opent de link de app direct.',
                ),
              ),
              const SizedBox(height: 18),
            ],
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, label: Text(t.t('create'))),
                ButtonSegment(value: false, label: Text(t.t('signin'))),
              ],
              selected: {createMode},
              onSelectionChanged: busy ? null : (value) => setState(() => createMode = value.first),
            ),
            const SizedBox(height: 20),
            if (createMode) ...[
              TextField(
                controller: name,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: t.t('name')),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(labelText: t.t('phone')),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              decoration: InputDecoration(labelText: t.t('email')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              obscureText: true,
              onSubmitted: (_) => submit(),
              decoration: InputDecoration(labelText: t.t('password')),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: busy ? null : submit,
              child: busy
                  ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(createMode ? t.t('create') : t.t('signin')),
            ),
          ],
        ),
      ),
    );
  }
}

class V4UnverifiedScreen extends StatelessWidget {
  const V4UnverifiedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => VetBackend.instance.signOut(),
        ),
        title: Text(_copy(context, 'Verify account', 'تفعيل الحساب', 'Account bevestigen')),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _InfoPanel(
            icon: Icons.verified_user_outlined,
            title: _copy(context, 'Email confirmation required', 'تأكيد البريد مطلوب', 'E-mailbevestiging vereist'),
            body: _copy(
              context,
              'This account cannot continue to farm data until the email address is confirmed.',
              'لن يمكن للحساب الدخول إلى بيانات المزرعة قبل تأكيد البريد الإلكتروني.',
              'Dit account kan niet doorgaan naar boerderijgegevens voordat het e-mailadres is bevestigd.',
            ),
          ),
        ),
      ),
    );
  }
}

class V4FarmSetupScreen extends StatefulWidget {
  const V4FarmSetupScreen({super.key});

  @override
  State<V4FarmSetupScreen> createState() => _V4FarmSetupScreenState();
}

class _V4FarmSetupScreenState extends State<V4FarmSetupScreen> {
  bool busy = false;
  String plan = 'software';
  String cycle = 'monthly';

  final company = TextEditingController();
  final farmName = TextEditingController();
  final country = TextEditingController();
  final region = TextEditingController();
  final workers = TextEditingController(text: '0');
  final vets = TextEditingController(text: '0');
  final barns = TextEditingController(text: '1');
  final area = TextEditingController(text: '0');
  final livestock = TextEditingController(text: '0');
  final poultry = TextEditingController(text: '0');
  final dogs = TextEditingController(text: '0');
  final breeds = TextEditingController();
  final age = TextEditingController();
  final purpose = TextEditingController();
  final ventilation = TextEditingController();
  final vaccines = TextEditingController();
  final diseaseHistory = TextEditingController();

  int _int(TextEditingController c, [int fallback = 0]) => int.tryParse(c.text.trim()) ?? fallback;
  double _double(TextEditingController c) => double.tryParse(c.text.trim().replaceAll(',', '.')) ?? 0;

  @override
  void dispose() {
    for (final c in [company, farmName, country, region, workers, vets, barns, area, livestock, poultry, dogs, breeds, age, purpose, ventilation, vaccines, diseaseHistory]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (farmName.text.trim().isEmpty || _int(barns, 1) < 1) {
      _error(_copy(context, 'Enter a farm name and at least one barn.', 'اكتب اسم المزرعة وعنبر واحد على الأقل.', 'Vul een boerderijnaam en minimaal één stal in.'));
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => busy = true);
    try {
      await VetBackend.instance.createFarm(
        FarmSetupPayload(
          companyName: company.text,
          farmName: farmName.text,
          country: country.text,
          region: region.text,
          workerCount: _int(workers),
          veterinarianCount: _int(vets),
          barnCount: _int(barns, 1),
          totalIndoorAreaM2: _double(area),
          livestockCount: _int(livestock),
          poultryCount: _int(poultry),
          dogCount: _int(dogs),
          breeds: breeds.text,
          ageRange: age.text,
          productionPurpose: purpose.text,
          ventilationSystem: ventilation.text,
          vaccinationNotes: vaccines.text,
          diseaseHistory: diseaseHistory.text,
          subscriptionTier: plan,
          billingCycle: cycle,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const V4AuthGate()),
        (_) => false,
      );
    } on PostgrestException catch (error) {
      _error(error.code == '42501'
          ? _copy(context, 'Your account session is not authorized. Sign out and sign in again.', 'جلسة الحساب غير مصرح بها. سجل الخروج ثم ادخل مرة أخرى.', 'Je accountsessie is niet geautoriseerd. Log uit en opnieuw in.')
          : error.message);
    } catch (_) {
      _error(_copy(context, 'Could not create the farm. Please try again.', 'تعذر إنشاء المزرعة. حاول مرة أخرى.', 'De boerderij kon niet worden aangemaakt. Probeer opnieuw.'));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _error(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: Theme.of(context).colorScheme.error),
    );
  }

  Widget field(TextEditingController controller, String label, {TextInputType? type, int lines = 1}) {
    return TextField(
      controller: controller,
      keyboardType: type,
      maxLines: lines,
      decoration: InputDecoration(labelText: label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = V2Text.of(context);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: busy ? null : () => VetBackend.instance.signOut(),
        ),
        title: Row(
          children: [
            SvgPicture.asset('assets/vet_ai_logo.svg', width: 38, height: 30),
            const SizedBox(width: 10),
            Text(t.t('farm')),
          ],
        ),
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 36),
        children: [
          _InfoPanel(
            icon: Icons.business_outlined,
            title: _copy(context, 'Farm profile', 'ملف المزرعة', 'Boerderijprofiel'),
            body: _copy(context, 'You can edit these details later.', 'تقدر تعدل البيانات دي بعدين.', 'Je kunt deze gegevens later wijzigen.'),
          ),
          const SizedBox(height: 18),
          field(company, t.t('company')),
          const SizedBox(height: 12),
          field(farmName, t.t('farmName')),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: field(country, t.t('country'))),
            const SizedBox(width: 10),
            Expanded(child: field(region, t.t('region'))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: field(workers, t.t('workers'), type: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(child: field(vets, t.t('vets'), type: TextInputType.number)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: field(barns, t.t('barns'), type: TextInputType.number)),
            const SizedBox(width: 10),
            Expanded(child: field(area, t.t('area'), type: const TextInputType.numberWithOptions(decimal: true))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: field(livestock, t.t('livestock'), type: TextInputType.number)),
            const SizedBox(width: 8),
            Expanded(child: field(poultry, t.t('poultry'), type: TextInputType.number)),
            const SizedBox(width: 8),
            Expanded(child: field(dogs, t.t('dogs'), type: TextInputType.number)),
          ]),
          const SizedBox(height: 12),
          field(breeds, t.t('breeds')),
          const SizedBox(height: 12),
          field(age, t.t('age')),
          const SizedBox(height: 12),
          field(purpose, t.t('purpose')),
          const SizedBox(height: 12),
          field(ventilation, t.t('ventilation')),
          const SizedBox(height: 12),
          field(vaccines, t.t('vaccines'), lines: 3),
          const SizedBox(height: 12),
          field(diseaseHistory, t.t('history'), lines: 3),
          const SizedBox(height: 20),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'software', label: Text(t.t('software'))),
              ButtonSegment(value: 'smart_monitoring', label: Text(t.t('smart'))),
            ],
            selected: {plan},
            onSelectionChanged: busy ? null : (value) => setState(() => plan = value.first),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'monthly', label: Text(t.t('monthly'))),
              ButtonSegment(value: 'annual', label: Text(t.t('annual'))),
            ],
            selected: {cycle},
            onSelectionChanged: busy ? null : (value) => setState(() => cycle = value.first),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: busy ? null : save,
            child: busy
                ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(t.t('saveFarm')),
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VetColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: VetColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: VetColors.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 4),
                Text(body, style: const TextStyle(color: VetColors.muted, height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
