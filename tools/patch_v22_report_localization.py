from pathlib import Path


def replace_once(path: str, old: str, new: str, label: str):
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"Missing patch target: {label} in {path}")
    text = text.replace(old, new, 1)
    p.write_text(text)
    print(f"patched {label}")


# 1) Dashboard / approved animal artwork: keep the exact approved PNGs, only enlarge their presentation.
replace_once(
    "lib/v5_app.dart",
    """          SizedBox(width: 112, height: 84, child: Image.asset(asset, fit: BoxFit.contain, filterQuality: FilterQuality.high, isAntiAlias: true)),""",
    """          SizedBox(
            width: 138,
            height: 102,
            child: ClipRect(
              child: Center(
                child: Transform.scale(
                  scale: 1.25,
                  child: Image.asset(asset, fit: BoxFit.contain, filterQuality: FilterQuality.high, isAntiAlias: true),
                ),
              ),
            ),
          ),""",
    "animal group banner artwork",
)
replace_once(
    "lib/v5_app.dart",
    """SizedBox(width:92,height:68,child:Image.asset(asset,fit:BoxFit.contain))""",
    """SizedBox(width:112,height:82,child:ClipRect(child:Center(child:Transform.scale(scale:1.2,child:Image.asset(asset,fit:BoxFit.contain,filterQuality:FilterQuality.high,isAntiAlias:true)))))""",
    "animal choice artwork",
)
replace_once(
    "lib/v5_app.dart",
    """              SizedBox(
                width: double.infinity,
                height: 112,
                child: Center(
                  child: Image.asset(asset, width: 146, height: 96, fit: BoxFit.contain, filterQuality: FilterQuality.high, isAntiAlias: true),
                ),
              ),
              const SizedBox(height: 8),
              Text('$value', style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w900)),""",
    """              SizedBox(
                width: double.infinity,
                height: 174,
                child: ClipRect(
                  child: Center(
                    child: Transform.scale(
                      scale: 1.9,
                      child: Image.asset(
                        asset,
                        width: 220,
                        height: 145,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        isAntiAlias: true,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text('$value', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900)),""",
    "dashboard animal artwork",
)

# 2) Report UI: larger, readable typography and no raw English catalog prose on non-English preliminary screens.
replace_once(
    "lib/analysis/vet_analysis_report.dart",
    """  bool get _isFinal => _result['code'] == 'FINAL_REPORT_COMPLETE';""",
    """  bool get _isFinal => _result['code'] == 'FINAL_REPORT_COMPLETE';
  bool get _isEnglish => widget.languageCode.toLowerCase().startsWith('en');""",
    "report language helper",
)
replace_once(
    "lib/analysis/vet_analysis_report.dart",
    """                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),""",
    """                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, height: 1.2),""",
    "report heading size",
)
replace_once(
    "lib/analysis/vet_analysis_report.dart",
    """          if ((top['cause'] ?? '').toString().trim().isNotEmpty)
            _KeyValueSection(icon: Icons.science_outlined, color: VetColors.purple, title: widget.translate('Cause', 'السبب', 'Oorzaak'), text: top['cause'].toString()),
          if ((top['treatment_summary'] ?? '').toString().trim().isNotEmpty)
            _KeyValueSection(icon: Icons.medical_services_outlined, color: VetColors.green, title: widget.translate('Treatment / management', 'العلاج / التعامل', 'Behandeling / management'), text: top['treatment_summary'].toString()),
          if ((top['prevention_summary'] ?? '').toString().trim().isNotEmpty)
            _KeyValueSection(icon: Icons.shield_outlined, color: VetColors.history, title: widget.translate('Prevention', 'الوقاية', 'Preventie'), text: top['prevention_summary'].toString()),""",
    """          if (_isEnglish && (top['cause'] ?? '').toString().trim().isNotEmpty)
            _KeyValueSection(icon: Icons.science_outlined, color: VetColors.purple, title: widget.translate('Cause', 'السبب', 'Oorzaak'), text: top['cause'].toString()),
          if (_isEnglish && (top['treatment_summary'] ?? '').toString().trim().isNotEmpty)
            _KeyValueSection(icon: Icons.medical_services_outlined, color: VetColors.green, title: widget.translate('Treatment / management', 'العلاج / التعامل', 'Behandeling / management'), text: top['treatment_summary'].toString()),
          if (_isEnglish && (top['prevention_summary'] ?? '').toString().trim().isNotEmpty)
            _KeyValueSection(icon: Icons.shield_outlined, color: VetColors.history, title: widget.translate('Prevention', 'الوقاية', 'Preventie'), text: top['prevention_summary'].toString()),
          if (!_isEnglish)
            _KeyValueSection(
              icon: Icons.translate_rounded,
              color: VetColors.primary,
              title: widget.translate('Localized details', 'التفاصيل بنفس لغة الهاتف', 'Details in de taal van je telefoon'),
              text: widget.translate(
                'Cause, treatment and prevention details are shown in the final verified report after they are localized into your phone language.',
                'تفاصيل السبب والعلاج والوقاية هتظهر كاملة في التقرير النهائي الموثق بعد تحويلها لنفس لغة الهاتف، من غير خلط إنجليزي.',
                'Oorzaak, behandeling en preventie verschijnen volledig in het definitieve rapport nadat ze naar de taal van je telefoon zijn omgezet.',
              ),
            ),""",
    "preliminary mixed-language guard",
)
replace_once(
    "lib/analysis/vet_analysis_report.dart",
    """        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: VetColors.surface3, borderRadius: BorderRadius.circular(17)),
        child: Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.45)),""",
    """        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: VetColors.surface3, borderRadius: BorderRadius.circular(17)),
        child: Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, height: 1.55)),""",
    "summary typography",
)
replace_once(
    "lib/analysis/vet_analysis_report.dart",
    """      padding: const EdgeInsets.only(top: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 25)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          const SizedBox(height: 4),
          Text(text, style: const TextStyle(height: 1.45)),""",
    """      padding: const EdgeInsets.only(top: 18),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 48, height: 48, decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color, size: 29)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 19, height: 1.25)),
          const SizedBox(height: 6),
          Text(text, style: const TextStyle(fontSize: 16.5, height: 1.55)),""",
    "key-value typography",
)
replace_once(
    "lib/analysis/vet_analysis_report.dart",
    """      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: color, size: 27), const SizedBox(width: 8), Expanded(child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)))]),
        const SizedBox(height: 7),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 7), child: Icon(Icons.circle, size: 7, color: color)),
              const SizedBox(width: 9),
              Expanded(child: Text(item, style: const TextStyle(height: 1.42))),""",
    """      padding: const EdgeInsets.only(top: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: color, size: 30), const SizedBox(width: 10), Expanded(child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900, height: 1.25)))]),
        const SizedBox(height: 9),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.only(top: 9), child: Icon(Icons.circle, size: 8, color: color)),
              const SizedBox(width: 10),
              Expanded(child: Text(item, style: const TextStyle(fontSize: 16.5, height: 1.52))),""",
    "list typography",
)
replace_once(
    "lib/analysis/vet_analysis_report.dart",
    """        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: VetColors.surface2, borderRadius: BorderRadius.circular(16), border: Border.all(color: VetColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(question, style: const TextStyle(fontWeight: FontWeight.w800, height: 1.35)),""",
    """        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: VetColors.surface2, borderRadius: BorderRadius.circular(16), border: Border.all(color: VetColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(question, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, height: 1.45)),""",
    "question typography",
)
replace_once(
    "lib/analysis/vet_analysis_report.dart",
    """          style: const TextStyle(color: VetColors.muted, fontStyle: FontStyle.italic, height: 1.4),""",
    """          style: const TextStyle(color: VetColors.muted, fontSize: 15, fontStyle: FontStyle.italic, height: 1.5),""",
    "confidence typography",
)

# 3) PDF: larger fonts and spacing so the real exported report is readable.
replace_once(
    "lib/reports/vet_pdf_report.dart",
    """  pw.Widget text(String value, {double size = 10.5, bool strong = false, PdfColor? color}) => pw.Text(
        value,
        textDirection: direction,
        textAlign: align,
        style: pw.TextStyle(font: strong ? bold : regular, fontSize: size, color: color ?? PdfColors.blueGrey900, lineSpacing: 3),
      );""",
    """  pw.Widget text(String value, {double size = 13.2, bool strong = false, PdfColor? color}) => pw.Text(
        value,
        textDirection: direction,
        textAlign: align,
        style: pw.TextStyle(font: strong ? bold : regular, fontSize: size, color: color ?? PdfColors.blueGrey900, lineSpacing: 4),
      );""",
    "pdf body font",
)
replace_once(
    "lib/reports/vet_pdf_report.dart",
    """        margin: const pw.EdgeInsets.only(top: 12, bottom: 5),
        padding: const pw.EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: pw.BoxDecoration(color: color.shade(0.08), borderRadius: pw.BorderRadius.circular(6)),
        child: text(value, size: 12.5, strong: true, color: color),""",
    """        margin: const pw.EdgeInsets.only(top: 15, bottom: 7),
        padding: const pw.EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: pw.BoxDecoration(color: color.shade(0.08), borderRadius: pw.BorderRadius.circular(7)),
        child: text(value, size: 16.5, strong: true, color: color),""",
    "pdf section headings",
)
replace_once("lib/reports/vet_pdf_report.dart", "padding: const pw.EdgeInsets.only(bottom: 5),", "padding: const pw.EdgeInsets.only(bottom: 7),", "pdf bullet spacing")
replace_once("lib/reports/vet_pdf_report.dart", "margin: const pw.EdgeInsets.only(top: 5)", "margin: const pw.EdgeInsets.only(top: 7)", "pdf bullet alignment")
replace_once("lib/reports/vet_pdf_report.dart", "margin: const pw.EdgeInsets.fromLTRB(34, 34, 34, 42),", "margin: const pw.EdgeInsets.fromLTRB(28, 30, 28, 38),", "pdf margins")
replace_once("lib/reports/vet_pdf_report.dart", "text('Vet AI', size: 18, strong: true", "text('Vet AI', size: 21, strong: true", "pdf header logo text")
replace_once("lib/reports/vet_pdf_report.dart", "size: 9, color: PdfColors.blueGrey500", "size: 11, color: PdfColors.blueGrey500", "pdf header subtitle")
replace_once("lib/reports/vet_pdf_report.dart", "size: 7.5, color: PdfColors.blueGrey500", "size: 9, color: PdfColors.blueGrey500", "pdf footer left")
replace_once("lib/reports/vet_pdf_report.dart", "size: 7.5, color: PdfColors.blueGrey500", "size: 9, color: PdfColors.blueGrey500", "pdf footer page number")
replace_once("lib/reports/vet_pdf_report.dart", "size: 23, strong: true", "size: 27, strong: true", "pdf main title")
replace_once("lib/reports/vet_pdf_report.dart", "size: 8.5, color: PdfColors.blueGrey500", "size: 10.5, color: PdfColors.blueGrey500", "pdf generated time")
replace_once("lib/reports/vet_pdf_report.dart", "size: 13, color: riskColor()", "size: 16, color: riskColor()", "pdf risk label")
replace_once("lib/reports/vet_pdf_report.dart", "size: 12, strong: true", "size: 15, strong: true", "pdf summary")
replace_once("lib/reports/vet_pdf_report.dart", "size: 14, strong: true", "size: 17, strong: true", "pdf condition name")
replace_once("lib/reports/vet_pdf_report.dart", "size: 8.5, color: PdfColors.teal800", "size: 10.5, color: PdfColors.teal800", "pdf evidence note")
replace_once("lib/reports/vet_pdf_report.dart", "size: 8.5, color: PdfColors.blueGrey600", "size: 10.5, color: PdfColors.blueGrey600", "pdf confidence note")

# 4) Final report backend: Gemini 3.6, language-aware cache, no mixed-language fallback, larger structured response.
replace_once(
    "supabase/functions/finalize-case-report/index.ts",
    'const MODEL = Deno.env.get("VET_AI_GEMINI_FINAL_MODEL") ?? "gemini-2.5-flash";',
    'const MODEL = Deno.env.get("VET_AI_GEMINI_FINAL_MODEL") ?? "gemini-3.6-flash";\nconst REPORT_FORMAT_VERSION = 2;',
    "final Gemini model",
)
replace_once(
    "supabase/functions/finalize-case-report/index.ts",
    """const geminiText = (payload: any): string | null => {
  for (const candidate of payload?.candidates ?? []) {
    for (const part of candidate?.content?.parts ?? []) {
      if (typeof part?.text === "string" && part.text.trim()) return part.text.trim();
    }
  }
  return null;
};""",
    """const geminiText = (payload: any): string | null => {
  for (const candidate of payload?.candidates ?? []) {
    const chunks: string[] = [];
    for (const part of candidate?.content?.parts ?? []) {
      if (part?.thought === true) continue;
      if (typeof part?.text === "string" && part.text.length) chunks.push(part.text);
    }
    if (chunks.length) return chunks.join("").trim();
  }
  return null;
};""",
    "final Gemini multipart output",
)
replace_once(
    "supabase/functions/finalize-case-report/index.ts",
    """  if (assessment.status === "final_report" && assessment.ai_analysis?.code === "FINAL_REPORT_COMPLETE" && assessment.ai_usage?.follow_up_fingerprint === fingerprint) {
    return json(assessment.ai_analysis);
  }""",
    """  if (
    assessment.status === "final_report" &&
    assessment.ai_analysis?.code === "FINAL_REPORT_COMPLETE" &&
    assessment.ai_usage?.follow_up_fingerprint === fingerprint &&
    assessment.ai_usage?.report_language === language &&
    assessment.ai_usage?.report_format_version === REPORT_FORMAT_VERSION
  ) {
    return json(assessment.ai_analysis);
  }""",
    "language-aware final report cache",
)
replace_once(
    "supabase/functions/finalize-case-report/index.ts",
    """  let finalResult: any = fallback;
  let usage: any = { follow_up_fingerprint: fingerprint, mode: "catalog_fallback", provider: "catalog" };""",
    """  let finalResult: any = fallback;
  let generatedByGemini = false;
  let usage: any = {
    follow_up_fingerprint: fingerprint,
    report_language: language,
    report_format_version: REPORT_FORMAT_VERSION,
    mode: "catalog_fallback",
    provider: "catalog",
  };""",
    "final report metadata",
)
replace_once(
    "supabase/functions/finalize-case-report/index.ts",
    """    const localeRule = isArabic(language)
      ? "Write every user-facing field in clear professional Egyptian Arabic. Do not mix English explanatory sentences into Arabic. Latin scientific organism names may appear only where medically useful."
      : `Write all user-facing fields naturally in language code ${language}.`;""",
    """    const localeRule = isArabic(language)
      ? "Every user-facing string MUST be clear professional Egyptian Arabic. Translate all English catalog prose into Arabic. Do not copy English explanatory sentences. Latin scientific organism names may appear only when medically necessary."
      : `Every user-facing string MUST be written naturally in language code ${language}. Translate catalog prose into that language; never mix explanatory English sentences into a non-English report. Latin scientific organism names may appear only when medically necessary.`;""",
    "strict final report language rule",
)
replace_once("supabase/functions/finalize-case-report/index.ts", "setTimeout(() => controller.abort(), 15000)", "setTimeout(() => controller.abort(), 40000)", "final report timeout")
replace_once(
    "supabase/functions/finalize-case-report/index.ts",
    """            temperature: 0.15,
            maxOutputTokens: 2400,
            responseMimeType: "application/json",""",
    """            temperature: 0.1,
            maxOutputTokens: 7000,
            thinkingConfig: { thinkingLevel: "low" },
            responseMimeType: "application/json",""",
    "final report generation budget",
)
replace_once(
    "supabase/functions/finalize-case-report/index.ts",
    """        usage = { ...(payload?.usageMetadata ?? {}), follow_up_fingerprint: fingerprint, mode: "gemini_structured", provider: "gemini" };""",
    """        generatedByGemini = true;
        usage = {
          ...(payload?.usageMetadata ?? {}),
          follow_up_fingerprint: fingerprint,
          report_language: language,
          report_format_version: REPORT_FORMAT_VERSION,
          mode: "gemini_structured",
          provider: "gemini",
        };""",
    "final report Gemini success metadata",
)
replace_once(
    "supabase/functions/finalize-case-report/index.ts",
    """  await supabase.from("assessments").update({""",
    """  // A non-English customer report must never silently fall back to raw English catalog prose.
  // If Gemini cannot localize the final report, return a retryable error instead of saving a mixed-language document.
  if (!generatedByGemini && !language.startsWith("en")) {
    return json({ code: "FINAL_REPORT_LOCALIZATION_UNAVAILABLE", risk: "insufficient_data" }, 502);
  }

  await supabase.from("assessments").update({""",
    "no mixed-language fallback",
)

# 5) Version bump for the visible UI/PDF/icon changes.
replace_once("pubspec.yaml", "version: 0.6.7+19", "version: 0.6.8+20", "app version")

print("V22 patch complete")
