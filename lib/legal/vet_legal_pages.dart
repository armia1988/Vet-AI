// ignore_for_file: unused_element_parameter

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../i18n/vet_locale.dart';
import '../theme/app_theme.dart';

String _lt(BuildContext context, String en, String ar, String nl) => VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetLegalHubScreen extends StatelessWidget {
  const VetLegalHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final pages = <_LegalEntry>[
      _LegalEntry(Icons.info_outline_rounded, VetColors.primary, _lt(context, 'About Vet AI', 'عن Vet AI', 'Over Vet AI'), _lt(context, 'Who we are, what the platform does and how it is designed.', 'إحنا مين، البرنامج بيعمل إيه، واتصمم إزاي.', 'Wie we zijn, wat het platform doet en hoe het is ontworpen.'), LegalPageType.about),
      _LegalEntry(Icons.favorite_outline_rounded, VetColors.red, _lt(context, 'Mission & purpose', 'الهدف والرسالة', 'Missie & doel'), _lt(context, 'Why Vet AI exists and the problems it is built to solve.', 'ليه Vet AI موجود وإيه المشاكل اللي بنحاول نحلها.', 'Waarom Vet AI bestaat en welke problemen het helpt oplossen.'), LegalPageType.mission),
      _LegalEntry(Icons.health_and_safety_outlined, VetColors.orange, _lt(context, 'Safety boundaries', 'حدود الأمان', 'Veiligheidsgrenzen'), _lt(context, 'What AI can and cannot safely decide in animal health.', 'إيه اللي الذكاء يقدر يعمله بأمان وإيه اللي لازم يفضل للطبيب والمعمل.', 'Wat AI wel en niet veilig kan beslissen bij diergezondheid.'), LegalPageType.safety),
      _LegalEntry(Icons.menu_book_outlined, VetColors.blue, _lt(context, 'Knowledge & evidence', 'قاعدة المعرفة والأدلة', 'Kennis & bewijs'), _lt(context, 'How reviewed veterinary knowledge is curated and used.', 'إزاي بنراجع المعرفة البيطرية والمصادر قبل استخدامها.', 'Hoe veterinaire kennis en bronnen worden beoordeeld en gebruikt.'), LegalPageType.knowledge),
      _LegalEntry(Icons.privacy_tip_outlined, VetColors.purple, _lt(context, 'Privacy policy', 'سياسة الخصوصية', 'Privacybeleid'), _lt(context, 'How account, farm, image, sensor and support data is handled.', 'إزاي بنتعامل مع بيانات الحساب والمزرعة والصور والحساسات والشات.', 'Hoe account-, boerderij-, beeld-, sensor- en supportgegevens worden verwerkt.'), LegalPageType.privacy),
      _LegalEntry(Icons.gavel_outlined, VetColors.history, _lt(context, 'Terms & conditions', 'الشروط والأحكام', 'Algemene voorwaarden'), _lt(context, 'Rules for using Vet AI, subscriptions, safety and responsibilities.', 'قواعد استخدام Vet AI والاشتراكات والسلامة والمسؤوليات.', 'Regels voor gebruik, abonnementen, veiligheid en verantwoordelijkheden.'), LegalPageType.terms),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(_lt(context, 'Vet AI information center', 'مركز معلومات Vet AI', 'Vet AI informatiecentrum'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          const _BrandHeader(),
          const SizedBox(height: 18),
          Text(_lt(context, 'Built for serious animal-health decisions', 'مصمم لقرارات صحة الحيوان بجدية', 'Gebouwd voor serieuze diergezondheidsbeslissingen'), style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(_lt(context, 'These pages explain how Vet AI works, where its limits are, how information is protected and what you agree to when using the service.', 'الصفحات دي بتشرح بالتفصيل Vet AI بيشتغل إزاي، حدوده فين، بياناتك بتتحمى إزاي، وإيه الشروط اللي بتوافق عليها لما تستخدم الخدمة.', 'Deze pagina’s leggen uit hoe Vet AI werkt, waar de grenzen liggen, hoe gegevens worden beschermd en welke voorwaarden gelden bij gebruik.'), style: const TextStyle(color: VetColors.muted, height: 1.55, fontSize: 15.5)),
          const SizedBox(height: 18),
          for (final page in pages) Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              child: ListTile(
                leading: Container(width: 48, height: 48, decoration: BoxDecoration(color: page.color.withValues(alpha: .1), borderRadius: BorderRadius.circular(14)), child: Icon(page.icon, color: page.color, size: 28)),
                title: Text(page.title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
                subtitle: Padding(padding: const EdgeInsets.only(top: 5), child: Text(page.subtitle, style: const TextStyle(height: 1.35))),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => VetLegalPageScreen(type: page.type))),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: VetColors.softBlue, borderRadius: BorderRadius.circular(16)),
            child: Text(_lt(context, 'Policy version: 4 September 2026. Before a public commercial launch, jurisdiction-specific legal entity, address, tax and governing-law details should be reviewed by qualified legal counsel and inserted into the final public terms.', 'إصدار السياسات: 4 سبتمبر 2026. قبل الإطلاق التجاري العام لازم بيانات الكيان القانوني والعنوان والضرائب والقانون المختص تتراجع مع محامي مؤهل وتتضاف للنسخة النهائية المنشورة من الشروط.', 'Beleidsversie: 4 september 2026. Voor een openbare commerciële lancering moeten rechtsvorm, adres, belasting- en toepasselijk-rechtgegevens door gekwalificeerd juridisch advies worden beoordeeld en in de definitieve voorwaarden worden opgenomen.'), style: const TextStyle(color: VetColors.muted, height: 1.45, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

class VetLegalPageScreen extends StatelessWidget {
  const VetLegalPageScreen({super.key, required this.type});
  final LegalPageType type;

  @override
  Widget build(BuildContext context) {
    final data = _data(context, type);
    return Scaffold(
      appBar: AppBar(title: Text(data.title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 34),
        children: [
          const _BrandHeader(compact: true),
          const SizedBox(height: 18),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: data.color.withValues(alpha: .1), borderRadius: BorderRadius.circular(22)),
            child: Icon(data.icon, size: 38, color: data.color),
          ),
          const SizedBox(height: 14),
          Text(data.title, style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w900, height: 1.15)),
          const SizedBox(height: 9),
          Text(data.intro, style: const TextStyle(fontSize: 16, color: VetColors.muted, height: 1.55)),
          const SizedBox(height: 18),
          for (final section in data.sections) _SectionCard(section: section, color: data.color),
          const SizedBox(height: 14),
          Text(_lt(context, 'Vet AI • Veterinary decision support and smart animal monitoring', 'Vet AI • دعم القرار البيطري والمراقبة الذكية للحيوان', 'Vet AI • Veterinaire beslissingsondersteuning en slimme diermonitoring'), textAlign: TextAlign.center, style: const TextStyle(color: VetColors.muted, fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({this.compact = false});
  final bool compact;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.all(compact ? 14 : 18),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: VetColors.border)),
        child: Row(children: [
          SvgPicture.asset('assets/vet_ai_logo.svg', width: compact ? 68 : 88),
          const SizedBox(width: 13),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Vet AI', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900)),
            SizedBox(height: 2),
            Text('Veterinary Intelligence', style: TextStyle(color: VetColors.muted, fontWeight: FontWeight.w700)),
          ])),
        ]),
      );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.section, required this.color});
  final _LegalSection section;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 13),
        child: Padding(
          padding: const EdgeInsets.all(17),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(section.title, style: TextStyle(fontSize: 19, fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 9),
            Text(section.body, style: const TextStyle(fontSize: 15, height: 1.6)),
            if (section.bullets.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final item in section.bullets) Padding(
                padding: const EdgeInsets.only(bottom: 7),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(width: 7, height: 7, margin: const EdgeInsets.only(top: 7), decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  const SizedBox(width: 9),
                  Expanded(child: Text(item, style: const TextStyle(fontSize: 14.5, height: 1.5))),
                ]),
              ),
            ],
          ]),
        ),
      );
}

_LegalPageData _data(BuildContext c, LegalPageType type) {
  switch (type) {
    case LegalPageType.about:
      return _LegalPageData(Icons.info_outline_rounded, VetColors.primary, _lt(c, 'About Vet AI', 'عن Vet AI', 'Over Vet AI'), _lt(c, 'Vet AI is a veterinary decision-support and smart-monitoring platform for livestock, poultry/chicks and dogs. It combines case images, history, reviewed veterinary knowledge and—where a farm has connected hardware—real sensor data.', 'Vet AI منصة لدعم القرار البيطري والمراقبة الذكية للمواشي والدواجن والكتاكيت والكلاب. بتجمع صور الحالة والتاريخ والمعرفة البيطرية المراجعة، ومع الخطة اللي فيها أجهزة بتستخدم قراءات حساسات حقيقية.', 'Vet AI is een platform voor veterinaire beslissingsondersteuning en slimme monitoring voor vee, pluimvee/kuikens en honden. Het combineert casusbeelden, voorgeschiedenis, beoordeelde veterinaire kennis en—waar hardware is gekoppeld—echte sensordata.'), [
        _LegalSection(_lt(c, 'What the product is', 'البرنامج عبارة عن إيه؟', 'Wat het product is'), _lt(c, 'Vet AI is designed to help farmers, animal-care teams and veterinarians organize evidence faster. An AI scan can describe visible findings, combine them with symptoms and propose cautious differential possibilities. It does not convert a photograph into a guaranteed diagnosis.', 'Vet AI معمول علشان يساعد المزارع وفريق الرعاية والطبيب يجمعوا الأدلة أسرع. فحص AI يقدر يوصف العلامات الظاهرة ويجمعها مع الأعراض ويقترح احتمالات تفريقية بحذر، لكنه ما بيحوّلش صورة واحدة لتشخيص مضمون.', 'Vet AI helpt boeren, dierverzorgingsteams en dierenartsen om bewijs sneller te organiseren. Een AI-scan kan zichtbare bevindingen beschrijven, symptomen meenemen en voorzichtige differentiële mogelijkheden voorstellen. Een foto wordt niet omgezet in een gegarandeerde diagnose.')),
        _LegalSection(_lt(c, 'Animal groups', 'مجموعات الحيوانات', 'Diergroepen'), _lt(c, 'The current product scope is livestock, poultry/chicks and dogs. Farm setup controls which groups appear in scan and monitoring features.', 'النطاق الحالي هو المواشي والدواجن/الكتاكيت والكلاب. إعداد المزرعة هو اللي بيحدد المجموعات اللي تظهر في الفحص والمراقبة.', 'De huidige scope is vee, pluimvee/kuikens en honden. De boerderij-instellingen bepalen welke groepen zichtbaar zijn in scan- en monitoringfuncties.')),
        _LegalSection(_lt(c, 'Software and smart monitoring', 'البرنامج والمراقبة الذكية', 'Software en slimme monitoring'), _lt(c, 'Software-only accounts use records, AI case support and reporting. Smart-monitoring plans can additionally display readings from provisioned devices. Vet AI deliberately shows an empty state instead of fabricated sensor values when no real device has reported data.', 'حساب البرنامج فقط بيستخدم السجلات ودعم الحالات والتقارير. خطة المراقبة الذكية بتضيف قراءات الأجهزة المتوصلة. لو مفيش جهاز حقيقي بعت بيانات، Vet AI يعرض إن مفيش قراءة بدل ما يخترع أرقام.', 'Software-only accounts gebruiken dossiers, AI-casusondersteuning en rapportage. Slimme-monitoringplannen kunnen daarnaast metingen van ingerichte apparaten tonen. Zonder echte apparaatdata toont Vet AI bewust een lege status in plaats van verzonnen waarden.')),
      ]);
    case LegalPageType.mission:
      return _LegalPageData(Icons.favorite_outline_rounded, VetColors.red, _lt(c, 'Mission & purpose', 'الهدف والرسالة', 'Missie & doel'), _lt(c, 'The mission is to reduce avoidable delay, missed warning signs and fragmented information in animal health while keeping veterinarians and laboratory confirmation in the loop.', 'هدفنا نقلل التأخير اللي ممكن نتفاداه، والعلامات الخطرة اللي ممكن تتفوت، وتشتت معلومات صحة الحيوان، مع الحفاظ على دور الطبيب والتأكيد المعملي.', 'De missie is vermijdbare vertraging, gemiste waarschuwingssignalen en versnipperde informatie in diergezondheid te verminderen, met behoud van de rol van dierenarts en laboratoriumbevestiging.'), [
        _LegalSection(_lt(c, 'Earlier awareness', 'اكتشاف التغيرات بدري', 'Eerder signaleren'), _lt(c, 'Images, history and real monitoring data can reveal change earlier than disconnected manual notes. Vet AI is intended to surface patterns for human review, not to silently make treatment decisions.', 'الصور والتاريخ وبيانات المراقبة الحقيقية ممكن يوضحوا التغير بدري عن ملاحظات متفرقة. Vet AI هدفه يطلع النمط للإنسان يراجعه، مش ياخد قرار علاج لوحده.', 'Beelden, voorgeschiedenis en echte monitoringdata kunnen veranderingen eerder zichtbaar maken dan losse handmatige notities. Vet AI brengt patronen naar voren voor menselijke beoordeling en neemt niet zelfstandig behandelbeslissingen.')),
        _LegalSection(_lt(c, 'Clear action', 'تصرف واضح', 'Duidelijke actie'), _lt(c, 'Each serious case should end with a practical summary: what was seen, likely possibilities, what can safely be done now, whether veterinary review is needed, what red flags matter and how confirmation should happen.', 'كل حالة مهمة لازم تنتهي بخلاصة عملية: إيه اللي ظهر، أهم الاحتمالات، إيه اللي ممكن يتعمل بأمان دلوقتي، هل محتاج طبيب، إيه علامات الخطر، وإزاي يحصل التأكيد.', 'Elke serieuze casus hoort te eindigen met een praktische samenvatting: wat is gezien, waarschijnlijke mogelijkheden, wat nu veilig kan, of veterinaire beoordeling nodig is, welke alarmsignalen tellen en hoe bevestiging moet plaatsvinden.')),
        _LegalSection(_lt(c, 'Operational memory', 'ذاكرة تشغيلية للمزرعة', 'Operationeel geheugen'), _lt(c, 'Farm details, animal history, assessments, support conversations and sensor trends are structured so teams can work from the same record instead of relying on memory alone.', 'بيانات المزرعة وتاريخ الحيوان والفحوصات والشات واتجاهات الحساسات بتتجمع بشكل منظم علشان الفريق يشتغل من نفس السجل بدل الاعتماد على الذاكرة بس.', 'Boerderijgegevens, dierhistorie, beoordelingen, supportgesprekken en sensortrends worden gestructureerd zodat teams vanuit hetzelfde dossier werken in plaats van alleen op geheugen te vertrouwen.')),
      ]);
    case LegalPageType.safety:
      return _LegalPageData(Icons.health_and_safety_outlined, VetColors.orange, _lt(c, 'Safety boundaries', 'حدود الأمان', 'Veiligheidsgrenzen'), _lt(c, 'Animal health is high-stakes. Vet AI is built with explicit limits so uncertainty is visible instead of hidden.', 'صحة الحيوان مجال حساس. Vet AI متصمم بحدود واضحة علشان عدم اليقين يظهر بدل ما يستخبى.', 'Diergezondheid is risicovol. Vet AI heeft expliciete grenzen zodat onzekerheid zichtbaar blijft.'), [
        _LegalSection(_lt(c, 'No diagnosis from one image', 'مفيش تشخيص نهائي من صورة واحدة', 'Geen diagnose uit één foto'), _lt(c, 'A photograph can support recognition of visible patterns, but many diseases overlap visually. Temperature, appetite, behavior, production changes, exposure history, physical examination and laboratory testing can materially change the conclusion.', 'الصورة ممكن تساعد في التعرف على النمط الظاهر، لكن أمراض كتير شكلها بيتشابه. الحرارة والشهية والسلوك والإنتاج والتعرض والفحص السريري والتحاليل ممكن يغيروا النتيجة تمامًا.', 'Een foto kan zichtbare patronen ondersteunen, maar veel aandoeningen lijken visueel op elkaar. Temperatuur, eetlust, gedrag, productie, blootstelling, lichamelijk onderzoek en laboratoriumtests kunnen de conclusie wezenlijk veranderen.')),
        _LegalSection(_lt(c, 'Risk colors are triage signals', 'ألوان الخطورة للفرز مش للتشخيص', 'Risicokleuren zijn triagesignalen'), _lt(c, 'Red, orange, yellow and green indicate urgency and follow-up need; they do not prove a disease. “Insufficient data” is a valid result when evidence is weak.', 'الأحمر والبرتقالي والأصفر والأخضر بيوضحوا الاستعجال والحاجة للمتابعة، مش إثبات مرض. ولو الأدلة ضعيفة فالنتيجة الصحيحة ممكن تكون «البيانات غير كافية».', 'Rood, oranje, geel en groen geven urgentie en opvolgingsbehoefte aan en bewijzen geen ziekte. “Onvoldoende gegevens” is een geldige uitkomst als het bewijs zwak is.')),
        _LegalSection(_lt(c, 'Medicines and food animals', 'الأدوية وحيوانات الغذاء', 'Geneesmiddelen en voedselproducerende dieren'), _lt(c, 'Vet AI must not invent prescription doses, injection schedules or meat/milk withdrawal periods. Product approval and withdrawal requirements depend on jurisdiction, species, product and veterinarian instructions.', 'Vet AI ممنوع يخترع جرعات أدوية وصفية أو جداول حقن أو فترات سحب اللبن واللحوم. الاعتماد وفترة السحب بيعتمدوا على البلد والنوع والمنتج وتعليمات الطبيب.', 'Vet AI mag geen receptdoseringen, injectieschema’s of vlees-/melkwachttijden verzinnen. Goedkeuring en wachttijden hangen af van land, diersoort, product en dierenartsinstructies.')),
        _LegalSection(_lt(c, 'Emergency and reportable disease patterns', 'الطوارئ وأنماط الأمراض الواجب الإبلاغ عنها', 'Spoed en meldingsplichtige patronen'), _lt(c, 'If a pattern suggests a high-consequence or reportable disease, the safe response is conservative: limit movement/contact, use biosecurity and contact a veterinarian or competent authority according to local rules. Vet AI does not replace official notification.', 'لو النمط ممكن يشير لمرض شديد الخطورة أو واجب الإبلاغ عنه، التصرف الآمن بيكون محافظ: تقليل الحركة والاختلاط، أمان حيوي، والتواصل مع الطبيب أو الجهة المختصة حسب القواعد المحلية. Vet AI مش بديل للإبلاغ الرسمي.', 'Bij een patroon dat kan passen bij een ernstige of meldingsplichtige ziekte is de veilige reactie conservatief: beweging/contact beperken, bioveiligheid toepassen en volgens lokale regels dierenarts of bevoegde autoriteit inschakelen. Vet AI vervangt officiële melding niet.')),
      ]);
    case LegalPageType.knowledge:
      return _LegalPageData(Icons.menu_book_outlined, VetColors.blue, _lt(c, 'Knowledge & evidence', 'قاعدة المعرفة والأدلة', 'Kennis & bewijs'), _lt(c, 'Production reasoning should use reviewed veterinary records with source, review status and date—not random social posts or uncontrolled images.', 'الاستدلال في النسخة الحقيقية لازم يعتمد على سجلات بيطرية مراجعة فيها المصدر وحالة المراجعة والتاريخ، مش بوستات سوشيال أو صور عشوائية.', 'Productieredenering hoort beoordeelde veterinaire records met bron, status en datum te gebruiken—geen willekeurige sociale posts of ongecontroleerde beelden.'), [
        _LegalSection(_lt(c, 'Source-linked records', 'معلومات مرتبطة بالمصدر', 'Brongekoppelde records'), _lt(c, 'Disease entries can carry cause, transmission, clinical phases, visible signs, sensor indicators, differentials, tests, biosecurity, prevention, management/treatment guidance, zoonotic/reportable flags and source metadata.', 'سجل المرض يقدر يحتوي على السبب والانتقال والمراحل والعلامات الظاهرة ومؤشرات الحساسات والاحتمالات التفريقية والفحوصات والأمان الحيوي والوقاية والتعامل/العلاج وهل هو حيواني المنشأ أو واجب الإبلاغ، مع بيانات المصدر.', 'Ziekterecords kunnen oorzaak, overdracht, klinische fasen, zichtbare tekenen, sensorindicatoren, differentiëlen, tests, bioveiligheid, preventie, behandeling/management, zoönose-/meldingsstatus en bronmetadata bevatten.')),
        _LegalSection(_lt(c, 'Reviewed before production use', 'مراجعة قبل الاستخدام الحقيقي', 'Beoordeeld vóór productiegebruik'), _lt(c, 'Records marked draft or rejected should not drive production recommendations. A reviewed status means the record passed the Vet AI curation workflow; it does not mean every possible disease worldwide is already covered.', 'السجل المسودة أو المرفوض ماينفعش يقود توصيات الإنتاج. حالة «مراجع» معناها إنه عدى سير مراجعة Vet AI، لكنها ما تعنيش إن كل أمراض العالم اتغطت بالفعل.', 'Concept- of afgewezen records mogen productieadvies niet sturen. “Beoordeeld” betekent dat een record de Vet AI-curatieworkflow heeft doorlopen; het betekent niet dat elke ziekte wereldwijd al is opgenomen.')),
        _LegalSection(_lt(c, 'Reference media', 'الصور والفيديو المرجعي', 'Referentiemedia'), _lt(c, 'Clinical images intended for reference or model evaluation require known provenance, appropriate rights/licensing and diagnostic confirmation metadata. Random internet images should not be treated as verified training truth.', 'الصور السريرية المرجعية أو المستخدمة للتقييم لازم يكون أصلها معروف وحقوق استخدامها واضحة ومعاها مستوى تأكيد التشخيص. الصور العشوائية من الإنترنت ماينفعش تتعامل كحقيقة تدريب مؤكدة.', 'Klinische beelden voor referentie of modelevaluatie vereisen bekende herkomst, passende rechten/licentie en metadata over diagnostische bevestiging. Willekeurige internetbeelden zijn geen geverifieerde trainingswaarheid.')),
        _LegalSection(_lt(c, 'Evidence can change', 'المعرفة ممكن تتغير', 'Bewijs kan veranderen'), _lt(c, 'Veterinary guidance, disease distribution, approved products and reporting requirements change over time and by country. Records therefore need review dates and versioning.', 'الإرشادات البيطرية وانتشار الأمراض والمنتجات المعتمدة ومتطلبات الإبلاغ بتتغير مع الوقت ومن بلد لبلد، علشان كده السجلات لازم يبقى ليها تاريخ مراجعة وإصدار.', 'Veterinaire richtlijnen, ziekteverspreiding, toegelaten producten en meldingsregels veranderen in de tijd en per land. Daarom zijn herzieningsdata en versiebeheer nodig.')),
      ]);
    case LegalPageType.privacy:
      return _LegalPageData(Icons.privacy_tip_outlined, VetColors.purple, _lt(c, 'Privacy policy', 'سياسة الخصوصية', 'Privacybeleid'), _lt(c, 'Vet AI is designed around purpose-specific access: the app asks before location, camera, photos or files are used, and protected farm data is separated by account and farm permissions.', 'Vet AI مبني على صلاحيات مرتبطة بالغرض: البرنامج يطلب إذنك قبل الموقع أو الكاميرا أو الصور أو الملفات، وبيانات المزرعة المحمية بتتفصل بصلاحيات الحساب والمزرعة.', 'Vet AI is ontworpen rond doelgebonden toegang: de app vraagt toestemming voordat locatie, camera, foto’s of bestanden worden gebruikt en beschermde boerderijdata wordt gescheiden via account- en boerderijrechten.'), [
        _LegalSection(_lt(c, 'Data we may process', 'البيانات اللي ممكن نعالجها', 'Gegevens die we kunnen verwerken'), _lt(c, 'Depending on the features you use, Vet AI may process account/profile details, company and farm details, animal records, assessment images, symptom/history notes, final reports, sensor/device readings, location/region information, alerts and private support messages/attachments.', 'حسب المميزات اللي بتستخدمها، Vet AI ممكن يعالج بيانات الحساب والملف الشخصي والشركة والمزرعة والحيوانات وصور الفحص وملاحظات الأعراض والتاريخ والتقارير وقراءات الأجهزة والحساسات ومعلومات الموقع/المنطقة والإنذارات ورسائل ومرفقات الدعم الخاص.', 'Afhankelijk van gebruikte functies kan Vet AI account-/profielgegevens, bedrijfs- en boerderijgegevens, dierdossiers, beoordelingsbeelden, symptoom-/historienotities, rapporten, apparaat-/sensormetingen, locatie-/regio-informatie, meldingen en privé supportberichten/bijlagen verwerken.')),
        _LegalSection(_lt(c, 'Why we use data', 'ليه بنستخدم البيانات', 'Waarom we gegevens gebruiken'), _lt(c, 'Data is used to provide account access, maintain farm records, perform requested case analysis, generate reports, display real monitoring data, create configured alerts, provide support, secure the service and improve reliability. Vet AI should not upload a selected image or file for analysis/support until the user confirms the relevant action.', 'البيانات بتستخدم لتسجيل الدخول وحفظ سجل المزرعة وتنفيذ تحليل الحالة اللي طلبته وإنشاء التقارير وعرض المراقبة الحقيقية وعمل الإنذارات المضبوطة وتقديم الدعم وتأمين الخدمة وتحسين الاعتمادية. الصورة أو الملف المختار ماينفعش يترفع للتحليل أو الدعم قبل تأكيد المستخدم للعملية.', 'Gegevens worden gebruikt voor accounttoegang, boerderijdossiers, aangevraagde casusanalyse, rapporten, echte monitoring, ingestelde meldingen, support, beveiliging en betrouwbaarheid. Een gekozen afbeelding/bestand hoort niet voor analyse/support te worden geüpload voordat de gebruiker die actie bevestigt.')),
        _LegalSection(_lt(c, 'Permissions', 'الصلاحيات', 'Toestemmingen'), _lt(c, 'Camera, photo library, files and location remain controlled by the device operating system. Refusing a permission may limit a feature but does not authorize Vet AI to bypass the choice.', 'الكاميرا والصور والملفات والموقع بيفضلوا تحت تحكم نظام الهاتف. رفض الصلاحية ممكن يمنع ميزة معينة لكنه مايديش Vet AI حق يتجاوز اختيارك.', 'Camera, fotobibliotheek, bestanden en locatie blijven onder controle van het besturingssysteem. Weigering kan een functie beperken maar geeft Vet AI geen recht de keuze te omzeilen.')),
        _LegalSection(_lt(c, 'Storage and access control', 'التخزين والتحكم في الوصول', 'Opslag en toegangscontrole'), _lt(c, 'Protected application data is stored in the Vet AI backend with row-level access rules and private storage where configured. Support agents require an explicit company support-agent authorization; ordinary farm accounts do not receive global access to other farms.', 'بيانات التطبيق المحمية بتتخزن في Backend Vet AI مع قواعد وصول على مستوى الصفوف وتخزين خاص حسب الميزة. موظف الدعم لازم يبقى مصرح له صراحة كموظف دعم للشركة؛ حساب المزرعة العادي ماياخدش وصول عام لمزارع تانية.', 'Beschermde applicatiegegevens worden opgeslagen in de Vet AI-backend met rij-niveau toegangsregels en waar nodig privé-opslag. Supportmedewerkers vereisen expliciete supportautorisatie; gewone boerderijaccounts krijgen geen globale toegang tot andere boerderijen.')),
        _LegalSection(_lt(c, 'Service providers', 'مزودي الخدمة', 'Dienstverleners'), _lt(c, 'Vet AI may rely on infrastructure providers for authentication, databases, storage, AI processing, app distribution and communications. These providers process data only as needed to operate the relevant function under their own contractual/security terms.', 'Vet AI ممكن يعتمد على مزودي بنية تحتية لتسجيل الدخول وقواعد البيانات والتخزين ومعالجة AI وتوزيع التطبيق والاتصالات. المزود بيعالج البيانات بالقدر اللازم لتشغيل الوظيفة وتحت شروطه التعاقدية والأمنية.', 'Vet AI kan infrastructuurleveranciers gebruiken voor authenticatie, databases, opslag, AI-verwerking, appdistributie en communicatie. Zij verwerken gegevens voor zover nodig voor die functie onder hun contractuele/beveiligingsvoorwaarden.')),
        _LegalSection(_lt(c, 'Retention, correction and deletion', 'الاحتفاظ والتصحيح والحذف', 'Bewaren, corrigeren en verwijderen'), _lt(c, 'Operational records may need retention for continuity, safety, audit and legal obligations. Users should be able to request correction/export/deletion through authorized support, subject to records that must lawfully or safely be retained. The final commercial privacy notice should state jurisdiction-specific retention periods and controller contact details.', 'بعض السجلات التشغيلية ممكن تحتاج تتخزن للاستمرارية والسلامة والتدقيق والالتزامات القانونية. المستخدم يقدر يطلب التصحيح أو التصدير أو الحذف من الدعم المصرح، مع استثناء السجلات اللي لازم قانونيًا أو أمنيًا تفضل محفوظة. النسخة التجارية النهائية لازم تحدد مدد الاحتفاظ وبيانات جهة التحكم حسب الدولة.', 'Operationele records kunnen moeten worden bewaard voor continuïteit, veiligheid, audit en wettelijke verplichtingen. Gebruikers kunnen via geautoriseerde support correctie/export/verwijdering aanvragen, behalve waar bewaring wettelijk of veilig vereist is. De definitieve commerciële privacyverklaring moet land-specifieke termijnen en contactgegevens van de verwerkingsverantwoordelijke vermelden.')),
        _LegalSection(_lt(c, 'No advertising sale commitment', 'عدم بيع البيانات للإعلانات', 'Geen verkoop voor advertenties'), _lt(c, 'Vet AI is not designed to sell farm, animal-health, diagnostic image or support-chat data to advertisers. If the business model changes materially, the privacy notice and consent requirements must be updated before such processing begins.', 'Vet AI مش متصمم لبيع بيانات المزرعة أو صحة الحيوان أو صور الفحص أو شات الدعم للمعلنين. لو نموذج العمل اتغير بشكل جوهري لازم سياسة الخصوصية ومتطلبات الموافقة تتحدث قبل أي معالجة جديدة.', 'Vet AI is niet ontworpen om boerderij-, diergezondheids-, diagnosebeeld- of supportchatgegevens aan adverteerders te verkopen. Bij een wezenlijke wijziging moeten privacyverklaring en toestemming vooraf worden aangepast.')),
      ]);
    case LegalPageType.terms:
      return _LegalPageData(Icons.gavel_outlined, VetColors.history, _lt(c, 'Terms & conditions', 'الشروط والأحكام', 'Algemene voorwaarden'), _lt(c, 'These product terms describe the operating rules for Vet AI. Jurisdiction-specific company identity, registered address, taxes, consumer terms and governing law must be finalized before a public commercial launch.', 'الشروط دي بتوضح قواعد تشغيل واستخدام Vet AI. بيانات الكيان القانوني والعنوان المسجل والضرائب وشروط المستهلك والقانون المختص لازم تتحدد نهائيًا قبل الإطلاق التجاري العام.', 'Deze productvoorwaarden beschrijven de gebruiksregels van Vet AI. Rechtsvorm, geregistreerd adres, belastingen, consumentenvoorwaarden en toepasselijk recht moeten vóór openbare commerciële lancering definitief worden gemaakt.'), [
        _LegalSection(_lt(c, '1. Service scope', '1. نطاق الخدمة', '1. Omvang van de dienst'), _lt(c, 'Vet AI provides veterinary decision support, farm records, reporting, support communication and—where subscribed and connected—smart monitoring. Features may differ by plan, country, device availability and product maturity.', 'Vet AI بيقدم دعم قرار بيطري وسجلات للمزرعة وتقارير وتواصل دعم، ومع الاشتراك والأجهزة المناسبة مراقبة ذكية. المميزات ممكن تختلف حسب الخطة والبلد وتوفر الأجهزة ومرحلة المنتج.', 'Vet AI levert veterinaire beslissingsondersteuning, boerderijdossiers, rapportage, supportcommunicatie en—bij passend abonnement en gekoppelde hardware—slimme monitoring. Functies kunnen verschillen per plan, land, hardwarebeschikbaarheid en productfase.')),
        _LegalSection(_lt(c, '2. Not a substitute for a veterinarian', '2. مش بديل للطبيب البيطري', '2. Geen vervanging voor de dierenarts'), _lt(c, 'The service does not establish a veterinarian-client-patient relationship and does not replace physical examination, laboratory testing, emergency care, official disease reporting or local veterinary judgment. Users remain responsible for obtaining appropriate professional help.', 'الخدمة ما بتنشئش علاقة طبيب-عميل-حيوان ومش بديل للكشف المباشر أو التحاليل أو الطوارئ أو الإبلاغ الرسمي أو حكم الطبيب المحلي. المستخدم مسؤول عن طلب المساعدة المهنية المناسبة.', 'De dienst creëert geen dierenarts-cliënt-patiëntrelatie en vervangt geen lichamelijk onderzoek, laboratoriumtests, spoedzorg, officiële ziektemelding of lokaal veterinair oordeel. De gebruiker blijft verantwoordelijk voor passende professionele hulp.')),
        _LegalSection(_lt(c, '3. Account and data accuracy', '3. الحساب ودقة البيانات', '3. Account en gegevensnauwkeurigheid'), _lt(c, 'Users must protect account access and provide materially accurate farm, animal and case information. Incorrect animal group, history, sensor assignment or symptom answers can change output quality.', 'المستخدم لازم يحافظ على حسابه ويدخل بيانات مزرعة وحيوان وحالة صحيحة قدر الإمكان. اختيار نوع حيوان غلط أو تاريخ غلط أو ربط حساس غلط أو إجابات أعراض غير دقيقة ممكن يغير النتيجة.', 'Gebruikers moeten accounttoegang beschermen en wezenlijk juiste boerderij-, dier- en casusgegevens geven. Een verkeerde diergroep, historie, sensorkoppeling of symptoomantwoord kan de uitkomst veranderen.')),
        _LegalSection(_lt(c, '4. Sensor limitations', '4. حدود الحساسات', '4. Sensorbeperkingen'), _lt(c, 'Sensors can fail, drift, disconnect, be attached incorrectly or report delayed data. Alert thresholds must be configured for the relevant species, age, environment, device placement and veterinary plan. Vet AI intentionally does not invent a universal medical threshold for every animal.', 'الحساس ممكن يتعطل أو ينحرف أو يفصل أو يتركب غلط أو يبعت بيانات متأخرة. حدود الإنذار لازم تتظبط حسب النوع والعمر والبيئة ومكان الجهاز والخطة البيطرية. Vet AI متعمد ما يخترعش حد طبي عالمي لكل الحيوانات.', 'Sensoren kunnen defect raken, driften, loskoppelen, verkeerd worden geplaatst of vertraagde data leveren. Drempels moeten passen bij soort, leeftijd, omgeving, plaatsing en veterinair plan. Vet AI verzint bewust geen universele medische drempel voor elk dier.')),
        _LegalSection(_lt(c, '5. Medication safety', '5. سلامة الأدوية', '5. Medicatieveiligheid'), _lt(c, 'Users must follow applicable veterinary prescribing rules, product labels, contraindications and food-animal withdrawal requirements. Vet AI output must not be used to bypass prescription or regulatory controls.', 'لازم تتبع قواعد الوصف البيطري والملصق وموانع الاستخدام وفترات السحب لحيوانات الغذاء. مخرجات Vet AI ماينفعش تستخدم لتجاوز وصفة الطبيب أو القواعد الرقابية.', 'Gebruikers moeten voorschrijfregels, productlabels, contra-indicaties en wachttijden voor voedselproducerende dieren volgen. Vet AI mag niet worden gebruikt om recept- of regelgevingscontroles te omzeilen.')),
        _LegalSection(_lt(c, '6. Subscriptions and hardware', '6. الاشتراكات والأجهزة', '6. Abonnementen en hardware'), _lt(c, 'Software-only and smart-monitoring plans may have different billing, device and service entitlements. Hardware delivery, installation, connectivity, replacement, warranty and maintenance terms must be stated in the commercial order applicable to that customer.', 'خطة البرنامج فقط وخطة المراقبة الذكية ممكن يختلفوا في الفاتورة والأجهزة والخدمات. شروط تسليم وتركيب واتصال واستبدال وضمان وصيانة الأجهزة لازم تتحدد في الطلب التجاري الخاص بالعميل.', 'Software-only en slimme-monitoringplannen kunnen verschillen in facturering, apparatuur en rechten. Levering, installatie, connectiviteit, vervanging, garantie en onderhoud horen in de commerciële bestelling van de klant te staan.')),
        _LegalSection(_lt(c, '7. Acceptable use', '7. الاستخدام المقبول', '7. Toegestaan gebruik'), _lt(c, 'Users may not attempt unauthorized access, upload unlawful content, misuse another farm’s data, deliberately falsify health cases, interfere with service security or use the system to evade animal-welfare or disease-reporting obligations.', 'ممنوع محاولة دخول غير مصرح أو رفع محتوى غير قانوني أو إساءة استخدام بيانات مزرعة تانية أو تزوير حالات صحية عمدًا أو تعطيل الأمان أو استخدام النظام للهروب من التزامات الرفق بالحيوان أو الإبلاغ عن الأمراض.', 'Gebruikers mogen geen ongeautoriseerde toegang proberen, onrechtmatige inhoud uploaden, gegevens van andere boerderijen misbruiken, casussen opzettelijk vervalsen, beveiliging verstoren of dierenwelzijns-/meldplichten omzeilen.')),
        _LegalSection(_lt(c, '8. Service availability', '8. توفر الخدمة', '8. Beschikbaarheid'), _lt(c, 'Cloud, AI, network, app-store and hardware dependencies can temporarily fail. Safety-critical farm procedures must not rely on Vet AI as the only monitoring or emergency channel. Planned and unplanned maintenance may affect availability.', 'السحابة والذكاء والشبكة ومتجر التطبيقات والأجهزة ممكن يحصل فيهم عطل مؤقت. إجراءات المزرعة الحرجة ماينفعش تعتمد على Vet AI كقناة المراقبة أو الطوارئ الوحيدة. الصيانة المخططة أو الطارئة ممكن تأثر على الخدمة.', 'Cloud-, AI-, netwerk-, appstore- en hardwareafhankelijkheden kunnen tijdelijk uitvallen. Veiligheidskritische bedrijfsprocedures mogen Vet AI niet als enig monitoring- of noodkanaal gebruiken. Onderhoud kan beschikbaarheid beïnvloeden.')),
        _LegalSection(_lt(c, '9. Intellectual property and customer content', '9. الملكية الفكرية ومحتوى العميل', '9. Intellectueel eigendom en klantinhoud'), _lt(c, 'Vet AI software, interface, models, curated database structure and branding remain protected intellectual property. Customers retain rights they lawfully hold in their own farm records, images and uploaded materials and grant the service the operational permissions necessary to process them for requested features.', 'برنامج وواجهة ونماذج وهيكل قاعدة المعرفة وعلامة Vet AI تفضل ملكية فكرية محمية. العميل يحتفظ بحقوقه القانونية في سجلات مزرعته وصوره ومواده المرفوعة ويدي الخدمة الصلاحيات التشغيلية اللازمة لمعالجتها للمميزات اللي طلبها.', 'Vet AI-software, interface, modellen, gecureerde databasestructuur en merk blijven beschermd intellectueel eigendom. Klanten behouden hun rechtmatige rechten op eigen dossiers, beelden en uploads en verlenen de operationele toestemming die nodig is voor gevraagde functies.')),
        _LegalSection(_lt(c, '10. Suspension and termination', '10. الإيقاف وإنهاء الخدمة', '10. Opschorting en beëindiging'), _lt(c, 'Access may be suspended for serious security abuse, unlawful use, non-payment where applicable, or behavior that creates material risk to the platform or other customers. Account closure and data handling remain subject to applicable law and the privacy policy.', 'الوصول ممكن يتوقف في حالات إساءة أمنية خطيرة أو استخدام غير قانوني أو عدم سداد حسب الاتفاق أو سلوك يعمل خطر فعلي على المنصة أو عملاء تانيين. غلق الحساب والتعامل مع البيانات يفضل خاضع للقانون وسياسة الخصوصية.', 'Toegang kan worden opgeschort bij ernstige beveiligingsmisbruik, onrechtmatig gebruik, wanbetaling waar van toepassing, of materieel risico voor platform/klanten. Accountsluiting en gegevensverwerking blijven onderworpen aan wet en privacybeleid.')),
        _LegalSection(_lt(c, '11. Responsibility and liability', '11. المسؤولية', '11. Verantwoordelijkheid en aansprakelijkheid'), _lt(c, 'Vet AI should be operated as a support tool with professional oversight appropriate to the risk. The final commercial liability wording, statutory rights, exclusions and caps must be drafted for the customer type and governing jurisdiction; this in-app product description does not remove non-waivable legal rights.', 'Vet AI لازم يستخدم كأداة مساعدة مع إشراف مهني يناسب مستوى الخطر. صياغة المسؤولية التجارية النهائية والحقوق القانونية والاستثناءات والحدود لازم تتكتب حسب نوع العميل والدولة؛ وصف المنتج داخل التطبيق مايلغيش أي حقوق قانونية ماينفعش التنازل عنها.', 'Vet AI hoort als ondersteunend hulpmiddel te worden gebruikt met professioneel toezicht passend bij het risico. Definitieve aansprakelijkheid, wettelijke rechten, uitsluitingen en limieten moeten voor klanttype en jurisdictie worden opgesteld; deze producttekst neemt geen dwingende rechten weg.')),
        _LegalSection(_lt(c, '12. Changes', '12. التعديلات', '12. Wijzigingen'), _lt(c, 'Features, policies and safety controls may evolve. Material changes should be versioned and, where law or risk requires, communicated before they take effect.', 'المميزات والسياسات وضوابط الأمان ممكن تتطور. التغييرات الجوهرية لازم يبقى ليها إصدار واضح، ولو القانون أو مستوى الخطر يتطلب يتم إبلاغ المستخدم قبل ما تدخل حيز التنفيذ.', 'Functies, beleid en veiligheidsmaatregelen kunnen evolueren. Materiële wijzigingen horen te worden geversioneerd en waar wet/risico dit vereist vooraf te worden gecommuniceerd.')),
      ]);
  }
}

enum LegalPageType { about, mission, safety, knowledge, privacy, terms }

class _LegalEntry {
  const _LegalEntry(this.icon, this.color, this.title, this.subtitle, this.type);
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final LegalPageType type;
}

class _LegalPageData {
  const _LegalPageData(this.icon, this.color, this.title, this.intro, this.sections);
  final IconData icon;
  final Color color;
  final String title;
  final String intro;
  final List<_LegalSection> sections;
}

class _LegalSection {
  const _LegalSection(this.title, this.body, [this.bullets = const []]);
  final String title;
  final String body;
  final List<String> bullets;
}
