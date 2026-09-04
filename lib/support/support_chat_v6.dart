import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/vet_locale.dart';
import '../services/vet_backend.dart';
import '../theme/app_theme.dart';

String _t(BuildContext context, String en, String ar, String nl) => VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class V6SupportScreen extends StatefulWidget {
  const V6SupportScreen({super.key, required this.farmId});
  final String farmId;

  @override
  State<V6SupportScreen> createState() => _V6SupportScreenState();
}

class _V6SupportScreenState extends State<V6SupportScreen> {
  final message = TextEditingController();
  final picker = ImagePicker();
  String? threadId;
  bool sending = false;
  String? lastSentText;
  DateTime? lastSentAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final id = await VetBackend.instance.getOrCreateSupportThread(widget.farmId);
      if (mounted) setState(() => threadId = id);
    } catch (_) {
      if (mounted) _error(_t(context, 'Could not open the secure support inbox.', 'تعذر فتح صندوق الدعم الآمن.', 'De beveiligde support-inbox kon niet worden geopend.'));
    }
  }

  Future<void> _sendText() async {
    final text = message.text.trim();
    if (threadId == null || text.isEmpty || sending) return;
    final now = DateTime.now();
    if (lastSentText == text && lastSentAt != null && now.difference(lastSentAt!) < const Duration(seconds: 2)) {
      return;
    }
    lastSentText = text;
    lastSentAt = now;
    message.clear();
    setState(() => sending = true);
    try {
      await VetBackend.instance.sendSupportMessage(threadId!, text);
    } catch (_) {
      lastSentText = null;
      lastSentAt = null;
      if (mounted) {
        message.text = text;
        message.selection = TextSelection.collapsed(offset: message.text.length);
        _error(_t(context, 'Message could not be sent.', 'الرسالة مااتبعتتش. جرّب تاني.', 'Bericht kon niet worden verzonden.'));
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<bool> _confirmAccess({required String title, required String message, required IconData icon}) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: Icon(icon, size: 38, color: VetColors.primary),
        title: Text(title, textAlign: TextAlign.center),
        content: Text(message, textAlign: TextAlign.center, style: const TextStyle(height: 1.45)),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(_t(context, 'Cancel', 'إلغاء', 'Annuleren'))),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(_t(context, 'Allow', 'سماح', 'Toestaan'))),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _chooseAttachment() async {
    if (threadId == null || sending) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: VetColors.surface,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 42, height: 4, decoration: BoxDecoration(color: VetColors.border, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 12),
            ListTile(
              leading: const CircleAvatar(backgroundColor: VetColors.surface3, child: Icon(Icons.photo_camera_rounded, color: VetColors.blue)),
              title: Text(_t(context, 'Take photo', 'التقاط صورة', 'Foto maken'), style: const TextStyle(fontWeight: FontWeight.w800)),
              onTap: () { Navigator.pop(sheet); _pickImage(ImageSource.camera); },
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: VetColors.surface3, child: Icon(Icons.photo_library_rounded, color: VetColors.primary)),
              title: Text(_t(context, 'Choose photo', 'اختيار صورة', 'Foto kiezen'), style: const TextStyle(fontWeight: FontWeight.w800)),
              onTap: () { Navigator.pop(sheet); _pickImage(ImageSource.gallery); },
            ),
            ListTile(
              leading: const CircleAvatar(backgroundColor: VetColors.surface3, child: Icon(Icons.attach_file_rounded, color: VetColors.history)),
              title: Text(_t(context, 'Choose file', 'اختيار ملف', 'Bestand kiezen'), style: const TextStyle(fontWeight: FontWeight.w800)),
              subtitle: const Text('PDF • DOC/DOCX • XLS/XLSX • TXT/CSV'),
              onTap: () { Navigator.pop(sheet); _pickFile(); },
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    final access = await _confirmAccess(
      title: source == ImageSource.camera ? _t(context, 'Open camera?', 'فتح الكاميرا؟', 'Camera openen?') : _t(context, 'Open photos?', 'فتح الصور؟', 'Foto’s openen?'),
      message: source == ImageSource.camera
          ? _t(context, 'Vet AI Support will open the camera only after your approval. Nothing is sent until you approve the upload after editing.', 'دعم Vet AI هيفتح الكاميرا بعد موافقتك بس. مش هيتبعت أي حاجة إلا بعد ما توافق كمان على الرفع بعد التعديل.', 'Vet AI Support opent de camera pas na jouw toestemming. Er wordt niets verstuurd totdat je na het bewerken ook de upload bevestigt.')
          : _t(context, 'Vet AI Support will open your photo picker only after your approval. Nothing is sent until you approve the upload.', 'دعم Vet AI هيفتح اختيار الصور بعد موافقتك بس. مش هيتبعت أي ملف إلا لما توافق على الرفع.', 'Vet AI Support opent de fotokiezer pas na jouw toestemming. Er wordt niets verstuurd totdat je de upload bevestigt.'),
      icon: source == ImageSource.camera ? Icons.photo_camera_rounded : Icons.photo_library_rounded,
    );
    if (!access || !mounted) return;
    final selected = await picker.pickImage(source: source, imageQuality: 94, maxWidth: 2600);
    if (selected == null || !mounted) return;
    final original = await selected.readAsBytes();
    if (!mounted) return;
    final edited = await Navigator.push<Uint8List>(
      context,
      MaterialPageRoute(builder: (_) => SupportImageAnnotator(bytes: original)),
    );
    if (edited == null) return;
    final base = selected.name.contains('.') ? selected.name.substring(0, selected.name.lastIndexOf('.')) : 'photo';
    await _sendAttachment(edited, '${base}_marked.png', 'image/png');
  }

  Future<void> _pickFile() async {
    final access = await _confirmAccess(
      title: _t(context, 'Open files?', 'فتح الملفات؟', 'Bestanden openen?'),
      message: _t(context, 'Vet AI Support will open the system file picker after your approval. The chosen file is not uploaded until you confirm the upload.', 'دعم Vet AI هيفتح ملفات الجهاز بعد موافقتك. الملف اللي تختاره مش هيرتفع إلا لما تأكد الرفع.', 'Vet AI Support opent de systeembestandskiezer na jouw toestemming. Het gekozen bestand wordt pas geüpload nadat je de upload bevestigt.'),
      icon: Icons.folder_open_rounded,
    );
    if (!access || !mounted) return;
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt', 'csv'],
    );
    if (file == null) return;
    try {
      final bytes = await file.readAsBytes();
      await _sendAttachment(bytes, file.name, _mimeFor(file.name));
    } catch (_) {
      if (mounted) _error(_t(context, 'The selected file could not be read.', 'تعذر قراءة الملف المختار.', 'Het gekozen bestand kon niet worden gelezen.'));
    }
  }

  Future<void> _sendAttachment(
    Uint8List bytes,
    String fileName,
    String mimeType, {
    String? annotatedFromMessageId,
  }) async {
    if (threadId == null || sending) return;
    final upload = await _confirmAccess(
      title: _t(context, 'Upload this attachment?', 'رفع المرفق ده؟', 'Deze bijlage uploaden?'),
      message: _t(context, 'This attachment will be uploaded to your private Vet AI Support thread and shared with the support team. Continue?', 'المرفق ده هيتـرفع في شات دعم Vet AI الخاص بحسابك وهيبقى ظاهر لفريق الدعم. تكمل؟', 'Deze bijlage wordt naar je privé Vet AI Support-chat geüpload en met het supportteam gedeeld. Doorgaan?'),
      icon: Icons.cloud_upload_outlined,
    );
    if (!upload || !mounted) return;
    setState(() => sending = true);
    try {
      final attachment = await VetBackend.instance.uploadSupportAttachment(
        threadId: threadId!,
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
      );
      final caption = message.text;
      message.clear();
      await VetBackend.instance.sendSupportMessage(
        threadId!,
        caption,
        attachment: attachment,
        annotatedFromMessageId: annotatedFromMessageId,
      );
    } catch (e) {
      if (mounted) _error(_t(context, 'Attachment could not be sent. Maximum size is 25 MB and executable files are not accepted.', 'تعذر إرسال المرفق. الحد الأقصى 25 ميجابايت والملفات التنفيذية غير مسموحة.', 'Bijlage kon niet worden verzonden. Maximaal 25 MB; uitvoerbare bestanden zijn niet toegestaan.'));
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _annotateExisting(Map<String, dynamic> row) async {
    final path = row['attachment_path']?.toString();
    final mime = row['attachment_mime']?.toString() ?? '';
    if (path == null || !mime.startsWith('image/')) return;
    setState(() => sending = true);
    try {
      final bytes = await VetBackend.instance.downloadSupportAttachment(path);
      if (!mounted) return;
      setState(() => sending = false);
      final edited = await Navigator.push<Uint8List>(context, MaterialPageRoute(builder: (_) => SupportImageAnnotator(bytes: bytes)));
      if (edited == null) return;
      final originalName = row['attachment_name']?.toString() ?? 'image';
      final base = originalName.contains('.') ? originalName.substring(0, originalName.lastIndexOf('.')) : originalName;
      await _sendAttachment(edited, '${base}_marked.png', 'image/png', annotatedFromMessageId: row['id']?.toString());
    } catch (_) {
      if (mounted) _error(_t(context, 'The image could not be opened for annotation.', 'تعذر فتح الصورة للتعديل.', 'De afbeelding kon niet worden geopend om te markeren.'));
    } finally {
      if (mounted && sending) setState(() => sending = false);
    }
  }

  Future<void> _openFile(Map<String, dynamic> row) async {
    final path = row['attachment_path']?.toString();
    if (path == null) return;
    try {
      final url = await VetBackend.instance.signedSupportAttachmentUrl(path);
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) _error(_t(context, 'The secure file link could not be opened.', 'تعذر فتح رابط الملف الآمن.', 'De beveiligde bestandslink kon niet worden geopend.'));
    }
  }

  void _error(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text), backgroundColor: VetColors.red));
  }

  String _mimeFor(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf': return 'application/pdf';
      case 'doc': return 'application/msword';
      case 'docx': return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls': return 'application/vnd.ms-excel';
      case 'xlsx': return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'csv': return 'text/csv';
      default: return 'text/plain';
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
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Row(children: [
          const Icon(Icons.support_agent_rounded, size: 32, color: VetColors.primary),
          const SizedBox(width: 10),
          Text(_t(context, 'Vet AI Support', 'دعم Vet AI', 'Vet AI Support')),
        ]),
      ),
      body: threadId == null
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: VetColors.surface2, borderRadius: BorderRadius.circular(15), border: Border.all(color: VetColors.border)),
                  child: Row(children: [
                    const Icon(Icons.lock_rounded, color: VetColors.primary, size: 26),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_t(context, 'Private realtime chat • photos, marked images and documents', 'شات خاص مباشر • صور وصور معلّم عليها وملفات', 'Privé realtime chat • foto’s, gemarkeerde beelden en documenten'), style: const TextStyle(color: VetColors.muted, fontSize: 12.5))),
                  ]),
                ),
              ),
              Expanded(
                child: StreamBuilder<List<Map<String, dynamic>>>(
                  stream: VetBackend.instance.supportMessagesStream(threadId!),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final seen = <String>{};
                    final rows = snapshot.data!
                        .where((row) => seen.add(row['id']?.toString() ?? ''))
                        .toList(growable: false);
                    return ListView.builder(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      itemCount: rows.length,
                      itemBuilder: (context, i) => SupportMessageBubble(
                        row: rows[i],
                        onAnnotate: () => _annotateExisting(rows[i]),
                        onOpenFile: () => _openFile(rows[i]),
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    IconButton.filledTonal(
                      onPressed: sending ? null : _chooseAttachment,
                      style: IconButton.styleFrom(backgroundColor: VetColors.surface3),
                      icon: const Icon(Icons.add_rounded, size: 31, color: VetColors.history),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: message,
                        scrollPadding: const EdgeInsets.only(bottom: 140),
                        minLines: 1,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: _t(context, 'Write a message…', 'اكتب رسالة…', 'Schrijf een bericht…'),
                          prefixIcon: const Icon(Icons.chat_bubble_outline_rounded, size: 26),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: sending ? null : _sendText,
                      icon: sending
                          ? const SizedBox.square(dimension: 21, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded, size: 29),
                    ),
                  ]),
                ),
              ),
            ]),
    );
  }
}

class SupportMessageBubble extends StatelessWidget {
  const SupportMessageBubble({super.key, required this.row, required this.onAnnotate, required this.onOpenFile});
  final Map<String, dynamic> row;
  final VoidCallback onAnnotate;
  final VoidCallback onOpenFile;

  @override
  Widget build(BuildContext context) {
    final mine = row['sender_role'] == 'user';
    final role = row['sender_role']?.toString() ?? 'system';
    final message = row['message']?.toString() ?? '';
    final path = row['attachment_path']?.toString();
    final mime = row['attachment_mime']?.toString() ?? '';
    final name = row['attachment_name']?.toString() ?? 'attachment';
    final size = (row['attachment_size_bytes'] as num?)?.toInt();
    final isImage = path != null && mime.startsWith('image/');

    return Align(
      alignment: mine ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        constraints: const BoxConstraints(maxWidth: 330),
        decoration: BoxDecoration(
          color: mine ? VetColors.softBlue : VetColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: mine ? VetColors.blue : VetColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (isImage)
            _PrivateImage(path: path, onTap: onAnnotate),
          if (path != null && !isImage)
            InkWell(
              onTap: onOpenFile,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: VetColors.surface3, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Icons.description_rounded, size: 34, color: VetColors.history),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
                    if (size != null) Text(_fileSize(size), style: const TextStyle(color: VetColors.muted, fontSize: 11)),
                  ])),
                  const Icon(Icons.open_in_new_rounded, size: 22, color: VetColors.muted),
                ]),
              ),
            ),
          if (message.isNotEmpty) ...[
            if (path != null) const SizedBox(height: 8),
            Text(message, style: const TextStyle(height: 1.35)),
          ],
          const SizedBox(height: 5),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(role == 'support' ? Icons.support_agent_rounded : role == 'system' ? Icons.settings_rounded : Icons.person_rounded, size: 14, color: VetColors.muted),
            const SizedBox(width: 4),
            Text(
              role == 'support' ? _t(context, 'Support', 'الدعم', 'Support') : role == 'system' ? _t(context, 'System', 'النظام', 'Systeem') : _t(context, 'You', 'أنت', 'Jij'),
              style: const TextStyle(fontSize: 11, color: VetColors.muted),
            ),
            if (row['annotated_from_message_id'] != null) ...[
              const SizedBox(width: 8),
              const Icon(Icons.draw_rounded, size: 14, color: VetColors.blue),
              const SizedBox(width: 3),
              Text(_t(context, 'Marked copy', 'نسخة معلّم عليها', 'Gemarkeerde kopie'), style: const TextStyle(fontSize: 10.5, color: VetColors.blue)),
            ],
          ]),
        ]),
      ),
    );
  }

  static String _fileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _PrivateImage extends StatelessWidget {
  const _PrivateImage({required this.path, required this.onTap});
  final String path;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: VetBackend.instance.signedSupportAttachmentUrl(path),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(height: 170, alignment: Alignment.center, decoration: BoxDecoration(color: VetColors.surface3, borderRadius: BorderRadius.circular(13)), child: const CircularProgressIndicator());
        }
        return GestureDetector(
          onTap: onTap,
          child: Stack(children: [
            ClipRRect(borderRadius: BorderRadius.circular(13), child: Image.network(snapshot.data!, width: 300, height: 210, fit: BoxFit.cover)),
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(color: const Color(0xCC243036), borderRadius: BorderRadius.circular(11)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.draw_rounded, size: 18, color: VetColors.blue), const SizedBox(width: 5), Text(_t(context, 'Mark', 'تعديل', 'Markeren'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800))]),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class SupportImageAnnotator extends StatefulWidget {
  const SupportImageAnnotator({super.key, required this.bytes});
  final Uint8List bytes;

  @override
  State<SupportImageAnnotator> createState() => _SupportImageAnnotatorState();
}

class _SupportImageAnnotatorState extends State<SupportImageAnnotator> {
  final captureKey = GlobalKey();
  final strokes = <_Stroke>[];
  Color selected = Colors.redAccent;
  double width = 5;
  bool saving = false;

  void _start(DragStartDetails d) => setState(() => strokes.add(_Stroke(color: selected, width: width, points: [d.localPosition])));
  void _move(DragUpdateDetails d) => setState(() { if (strokes.isNotEmpty) strokes.last.points.add(d.localPosition); });

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = captureKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Image canvas unavailable.');
      final image = await boundary.toImage(pixelRatio: 2.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Image export failed.');
      if (mounted) Navigator.pop(context, data.buffer.asUint8List());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = <Color>[Colors.redAccent, Colors.amber, Colors.lightGreenAccent, Colors.lightBlueAccent, Colors.white];
    return Scaffold(
      appBar: AppBar(
        title: Text(_t(context, 'Mark image', 'التعديل على الصورة', 'Afbeelding markeren')),
        actions: [
          IconButton(onPressed: strokes.isEmpty ? null : () => setState(() => strokes.removeLast()), icon: const Icon(Icons.undo_rounded)),
          IconButton(onPressed: strokes.isEmpty ? null : () => setState(strokes.clear), icon: const Icon(Icons.delete_sweep_outlined)),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: Center(
            child: RepaintBoundary(
              key: captureKey,
              child: AspectRatio(
                aspectRatio: 1,
                child: Stack(fit: StackFit.expand, children: [
                  Container(color: const Color(0xFF101417), child: Image.memory(widget.bytes, fit: BoxFit.contain)),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: _start,
                    onPanUpdate: _move,
                    child: CustomPaint(painter: _StrokePainter(strokes)),
                  ),
                ]),
              ),
            ),
          ),
        ),
        SafeArea(
          top: false,
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            color: VetColors.surface,
            child: Column(children: [
              Row(children: [
                const Icon(Icons.edit_rounded, color: VetColors.primary),
                const SizedBox(width: 8),
                Expanded(child: Slider(value: width, min: 2, max: 14, onChanged: (v) => setState(() => width = v))),
              ]),
              Row(children: [
                for (final color in colors)
                  Padding(
                    padding: const EdgeInsets.only(right: 9),
                    child: InkWell(
                      onTap: () => setState(() => selected = color),
                      borderRadius: BorderRadius.circular(30),
                      child: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: selected == color ? VetColors.text : Colors.transparent, width: 3)),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 260,
                  height: 50,
                  child: FilledButton.icon(
                    onPressed: saving ? null : _save,
                    icon: saving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_rounded),
                    label: Text(_t(context, 'Use image', 'استخدام الصورة', 'Afbeelding gebruiken')),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Stroke {
  _Stroke({required this.color, required this.width, required this.points});
  final Color color;
  final double width;
  final List<Offset> points;
}

class _StrokePainter extends CustomPainter {
  const _StrokePainter(this.strokes);
  final List<_Stroke> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final paint = Paint()
        ..color = stroke.color
        ..strokeWidth = stroke.width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      if (stroke.points.length == 1) {
        canvas.drawCircle(stroke.points.first, stroke.width / 2, paint..style = PaintingStyle.fill);
        continue;
      }
      final path = Path()..moveTo(stroke.points.first.dx, stroke.points.first.dy);
      for (final p in stroke.points.skip(1)) path.lineTo(p.dx, p.dy);
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StrokePainter oldDelegate) => true;
}
