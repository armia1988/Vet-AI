import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../theme/app_theme.dart';

typedef VetPdfTranslate = String Function(String en, String ar, String nl);

class VetPdfReportScreen extends StatelessWidget {
  const VetPdfReportScreen({
    super.key,
    required this.report,
    required this.languageCode,
    required this.translate,
  });

  final Map<String, dynamic> report;
  final String languageCode;
  final VetPdfTranslate translate;

  @override
  Widget build(BuildContext context) {
    final title = translate('Vet AI final report', 'تقرير Vet AI النهائي', 'Definitief Vet AI-rapport');
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => Navigator.pop(context)),
        title: Text(title),
      ),
      body: PdfPreview(
        build: (format) => buildVetReportPdf(
          format: format,
          report: report,
          languageCode: languageCode,
          translate: translate,
        ),
        canChangePageFormat: false,
        canChangeOrientation: false,
        canDebug: false,
        allowPrinting: true,
        allowSharing: true,
        pdfFileName: 'Vet-AI-${report['assessment_id'] ?? 'report'}.pdf',
      ),
    );
  }
}

Future<Uint8List> buildVetReportPdf({
  required PdfPageFormat format,
  required Map<String, dynamic> report,
  required String languageCode,
  required VetPdfTranslate translate,
}) async {
  final isArabic = languageCode.toLowerCase().startsWith('ar');
  final regular = isArabic ? await PdfGoogleFonts.notoNaskhArabicRegular() : await PdfGoogleFonts.openSansRegular();
  final bold = isArabic ? await PdfGoogleFonts.notoNaskhArabicBold() : await PdfGoogleFonts.openSansBold();
  final pdf = pw.Document(
    title: translate('Vet AI final veterinary report', 'تقرير Vet AI البيطري النهائي', 'Definitief veterinair Vet AI-rapport'),
    author: 'Vet AI',
    creator: 'Vet AI',
  );

  final primary = report['primary_condition'] is Map ? Map<String, dynamic>.from(report['primary_condition'] as Map) : <String, dynamic>{};
  final direction = isArabic ? pw.TextDirection.rtl : pw.TextDirection.ltr;
  final align = isArabic ? pw.TextAlign.right : pw.TextAlign.left;
  final risk = (report['risk'] ?? 'insufficient_data').toString();
  final generatedAt = DateTime.tryParse(report['generated_at']?.toString() ?? '')?.toLocal();

  PdfColor riskColor() => switch (risk) {
        'red' => PdfColors.red600,
        'orange' => PdfColors.orange600,
        'yellow' => PdfColors.amber700,
        'none' => PdfColors.green600,
        _ => PdfColors.blueGrey500,
      };

  String riskLabel() => switch (risk) {
        'red' => translate('RED — urgent', 'أحمر — عاجل', 'ROOD — urgent'),
        'orange' => translate('ORANGE — veterinary review', 'برتقالي — مراجعة بيطرية', 'ORANJE — veterinaire controle'),
        'yellow' => translate('YELLOW — monitor / follow up', 'أصفر — متابعة ومراقبة', 'GEEL — volgen'),
        'none' => translate('GREEN — no current high-risk signal', 'أخضر — مفيش إشارة خطر عالية حاليًا', 'GROEN — geen actueel hoog risico'),
        _ => translate('INSUFFICIENT DATA', 'البيانات مش كفاية', 'ONVOLDOENDE GEGEVENS'),
      };

  String vetNeed() => switch ((report['vet_required'] ?? '').toString()) {
        'now' => translate('Veterinarian: NOW / emergency', 'الطبيب البيطري: فورًا / طوارئ', 'Dierenarts: NU / spoed'),
        'today' => translate('Veterinarian: today', 'الطبيب البيطري: النهارده', 'Dierenarts: vandaag'),
        'soon' => translate('Veterinarian: arrange soon', 'الطبيب البيطري: احجز مراجعة قريب', 'Dierenarts: binnenkort regelen'),
        'not_routinely' => translate('Veterinarian: not routinely required unless the condition changes', 'الطبيب البيطري: مش ضروري بشكل روتيني إلا لو الحالة اتغيرت', 'Dierenarts: niet routinematig nodig tenzij de situatie verandert'),
        _ => translate('Veterinary requirement: depends on confirmation', 'الحاجة لطبيب: حسب التأكيد وتطور الحالة', 'Veterinaire noodzaak: afhankelijk van bevestiging'),
      };

  pw.Widget text(String value, {double size = 10.5, bool strong = false, PdfColor? color}) => pw.Text(
        value,
        textDirection: direction,
        textAlign: align,
        style: pw.TextStyle(font: strong ? bold : regular, fontSize: size, color: color ?? PdfColors.blueGrey900, lineSpacing: 3),
      );

  pw.Widget sectionTitle(String value, PdfColor color) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 12, bottom: 5),
        padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: pw.BoxDecoration(color: color.shade(0.08), borderRadius: pw.BorderRadius.circular(6)),
        child: text(value, size: 12.5, strong: true, color: color),
      );

  pw.Widget bullets(dynamic value) {
    final items = value is List ? value.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList() : <String>[];
    if (items.isEmpty) return pw.SizedBox();
    return pw.Column(
      crossAxisAlignment: isArabic ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start,
      children: items.map((item) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          textDirection: direction,
          children: [
            pw.Container(width: 5, height: 5, margin: const pw.EdgeInsets.only(top: 5), decoration: const pw.BoxDecoration(color: PdfColors.teal600, shape: pw.BoxShape.circle)),
            pw.SizedBox(width: 7),
            pw.Expanded(child: text(item)),
          ],
        ),
      )).toList(),
    );
  }

  pdf.addPage(
    pw.MultiPage(
      pageFormat: format,
      textDirection: direction,
      margin: const pw.EdgeInsets.fromLTRB(34, 34, 34, 42),
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      header: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 10),
        decoration: const pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: PdfColors.teal300, width: 1))),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          textDirection: direction,
          children: [
            text('Vet AI', size: 18, strong: true, color: PdfColors.teal700),
            text(translate('Veterinary decision-support report', 'تقرير دعم القرار البيطري', 'Veterinair beslissingsondersteunend rapport'), size: 9, color: PdfColors.blueGrey500),
          ],
        ),
      ),
      footer: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(top: 8),
        decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.blueGrey100))),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          textDirection: direction,
          children: [
            text(translate('Vet AI • decision support, not a laboratory confirmation', 'Vet AI • دعم قرار بيطري، مش بديل عن التأكيد المعملي', 'Vet AI • beslissingsondersteuning, geen laboratoriumbevestiging'), size: 7.5, color: PdfColors.blueGrey500),
            text('${context.pageNumber}/${context.pagesCount}', size: 7.5, color: PdfColors.blueGrey500),
          ],
        ),
      ),
      build: (context) => [
        pw.SizedBox(height: 15),
        text((report['report_title'] ?? translate('Final veterinary report', 'التقرير البيطري النهائي', 'Definitief veterinair rapport')).toString(), size: 23, strong: true),
        if (generatedAt != null) ...[
          pw.SizedBox(height: 4),
          text('${translate('Generated', 'وقت التقرير', 'Aangemaakt')}: ${generatedAt.year}-${generatedAt.month.toString().padLeft(2, '0')}-${generatedAt.day.toString().padLeft(2, '0')} ${generatedAt.hour.toString().padLeft(2, '0')}:${generatedAt.minute.toString().padLeft(2, '0')}', size: 8.5, color: PdfColors.blueGrey500),
        ],
        pw.SizedBox(height: 14),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(color: riskColor().shade(0.09), border: pw.Border.all(color: riskColor()), borderRadius: pw.BorderRadius.circular(8)),
          child: pw.Column(crossAxisAlignment: isArabic ? pw.CrossAxisAlignment.end : pw.CrossAxisAlignment.start, children: [
            text(riskLabel(), strong: true, size: 13, color: riskColor()),
            if ((report['risk_reason'] ?? '').toString().trim().isNotEmpty) ...[pw.SizedBox(height: 4), text(report['risk_reason'].toString())],
          ]),
        ),
        sectionTitle(translate('Summary', 'الخلاصة', 'Samenvatting'), PdfColors.teal700),
        text((report['summary'] ?? '').toString(), size: 12, strong: true),
        sectionTitle(translate('Most likely condition', 'الحالة الأكثر احتمالًا', 'Meest waarschijnlijke aandoening'), PdfColors.blue700),
        text((primary['name'] ?? '').toString(), size: 14, strong: true),
        if ((primary['why'] ?? '').toString().trim().isNotEmpty) text(primary['why'].toString()),
        sectionTitle(translate('Cause', 'السبب', 'Oorzaak'), PdfColors.purple700),
        text((report['cause'] ?? '').toString()),
        sectionTitle(translate('Does this need a veterinarian?', 'هل الحالة محتاجة طبيب بيطري؟', 'Is een dierenarts nodig?'), PdfColors.orange700),
        text(vetNeed(), strong: true),
        if ((report['vet_required_reason'] ?? '').toString().trim().isNotEmpty) ...[pw.SizedBox(height: 4), text(report['vet_required_reason'].toString())],
        if ((report['topical_or_external_care'] is List) && (report['topical_or_external_care'] as List).isNotEmpty) ...[
          sectionTitle(translate('External / topical care', 'العناية أو العلاج الخارجي الموضعي', 'Uitwendige / lokale verzorging'), PdfColors.green700),
          bullets(report['topical_or_external_care']),
        ],
        sectionTitle(translate('Treatment & management', 'العلاج والتعامل', 'Behandeling & management'), PdfColors.green700),
        bullets(report['treatment_and_management']),
        sectionTitle(translate('What to do now', 'تعمل إيه دلوقتي؟', 'Wat nu te doen'), PdfColors.orange700),
        bullets(report['what_to_do_now']),
        sectionTitle(translate('Prevention', 'الوقاية', 'Preventie'), PdfColors.amber800),
        bullets(report['prevention']),
        sectionTitle(translate('Veterinary next steps', 'الخطوات البيطرية التالية', 'Volgende veterinaire stappen'), PdfColors.blue700),
        bullets(report['veterinary_next_steps']),
        if ((report['red_flags'] is List) && (report['red_flags'] as List).isNotEmpty) ...[
          sectionTitle(translate('Danger signs', 'علامات الخطر', 'Alarmsignalen'), PdfColors.red700),
          bullets(report['red_flags']),
        ],
        sectionTitle(translate('How to confirm', 'إزاي نتأكد؟', 'Hoe te bevestigen'), PdfColors.purple700),
        bullets(report['confirmation_plan']),
        if ((report['food_animal_medicine_note'] ?? '').toString().trim().isNotEmpty) ...[
          sectionTitle(translate('Medicine safety note', 'تنبيه مهم بخصوص الأدوية', 'Veiligheidsnotitie medicijnen'), PdfColors.blueGrey700),
          text(report['food_animal_medicine_note'].toString()),
        ],
        pw.SizedBox(height: 16),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(color: PdfColors.teal50, borderRadius: pw.BorderRadius.circular(7)),
          child: text(translate('This report was cross-checked against authoritative veterinary and regulatory evidence. Raw website links are intentionally not shown in the customer report.', 'التقرير ده اتراجع على أدلة بيطرية ورقابية موثوقة. روابط المواقع الخام مش بتظهر في تقرير العميل.', 'Dit rapport is gecontroleerd aan de hand van gezaghebbende veterinaire en regelgevende bronnen. Ruwe websitelinks worden bewust niet in het klantverslag getoond.'), size: 8.5, color: PdfColors.teal800),
        ),
        if ((report['confidence_statement'] ?? '').toString().trim().isNotEmpty) ...[
          pw.SizedBox(height: 10),
          text(report['confidence_statement'].toString(), size: 8.5, color: PdfColors.blueGrey600),
        ],
      ],
    ),
  );

  return pdf.save();
}
