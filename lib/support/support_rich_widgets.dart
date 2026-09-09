import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/vet_locale.dart';
import '../services/vet_backend.dart';
import 'support_rich_service.dart';

String _rt(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetSupportAvatar extends StatelessWidget {
  const VetSupportAvatar({super.key, this.radius = 19});

  final double radius;

  Future<void> _open(BuildContext context) => showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierColor: Colors.black87,
        builder: (dialogContext) => Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 190,
                          height: 190,
                          padding: const EdgeInsets.all(18),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: SvgPicture.asset(
                            'assets/vet_ai_app_icon.svg',
                            fit: BoxFit.contain,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          _rt(context, 'Vet AI Support', 'دعم Vet AI', 'Vet AI Support'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _rt(
                            context,
                            'Official support account',
                            'حساب الدعم الرسمي',
                            'Officieel supportaccount',
                          ),
                          style: const TextStyle(
                            color: Color(0xFFB6BEC4),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                PositionedDirectional(
                  top: 8,
                  start: 8,
                  child: IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: Colors.black54),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _open(context),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: CircleAvatar(
            radius: radius,
            backgroundColor: const Color(0xFFD9FDD3),
            child: Icon(
              Icons.support_agent_rounded,
              color: const Color(0xFF00A884),
              size: radius * 1.22,
            ),
          ),
        ),
      );
}

class VetFarmAvatar extends StatelessWidget {
  const VetFarmAvatar({
    super.key,
    required this.photoPath,
    this.radius = 20,
    this.fallbackIcon = Icons.business_rounded,
  });

  final String? photoPath;
  final double radius;
  final IconData fallbackIcon;

  Future<void> _openPhoto(BuildContext context, String url) => showDialog<void>(
        context: context,
        useRootNavigator: true,
        barrierColor: Colors.black87,
        builder: (dialogContext) => Dialog.fullscreen(
          backgroundColor: Colors.black,
          child: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    minScale: .8,
                    maxScale: 5,
                    child: Center(
                      child: Image.network(url, fit: BoxFit.contain),
                    ),
                  ),
                ),
                PositionedDirectional(
                  top: 8,
                  start: 8,
                  child: IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: Colors.black54),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: VetSupportRichService.instance.signedFarmPhotoUrl(photoPath),
      builder: (context, snapshot) {
        final url = snapshot.data;
        final avatar = CircleAvatar(
          radius: radius,
          backgroundColor: const Color(0xFFD9FDD3),
          backgroundImage: url == null ? null : NetworkImage(url),
          child: url == null
              ? Icon(
                  fallbackIcon,
                  color: const Color(0xFF00A884),
                  size: radius * 1.08,
                )
              : null,
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: url == null ? null : () => _openPhoto(context, url),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: avatar,
          ),
        );
      },
    );
  }
}

class SupportAttachmentGrid extends StatelessWidget {
  const SupportAttachmentGrid({
    super.key,
    required this.onPhotos,
    required this.onCamera,
    required this.onLocation,
    required this.onDocument,
    required this.onPoll,
    required this.onEvent,
  });

  final VoidCallback onPhotos;
  final VoidCallback onCamera;
  final VoidCallback onLocation;
  final VoidCallback onDocument;
  final VoidCallback onPoll;
  final VoidCallback onEvent;

  @override
  Widget build(BuildContext context) {
    final items = <_AttachItem>[
      _AttachItem(Icons.photo_library_rounded, const Color(0xFF2F80ED), _rt(context, 'Photos', 'الصور', "Foto's"), onPhotos),
      _AttachItem(Icons.photo_camera_rounded, const Color(0xFF4B5563), _rt(context, 'Camera', 'الكاميرا', 'Camera'), onCamera),
      _AttachItem(Icons.location_on_rounded, const Color(0xFF00A884), _rt(context, 'Location', 'الموقع', 'Locatie'), onLocation),
      _AttachItem(Icons.insert_drive_file_rounded, const Color(0xFF2997D6), _rt(context, 'Document', 'مستند', 'Document'), onDocument),
      _AttachItem(Icons.poll_rounded, const Color(0xFFF3B63A), _rt(context, 'Poll', 'استطلاع', 'Peiling'), onPoll),
      _AttachItem(Icons.calendar_month_rounded, const Color(0xFFE54868), _rt(context, 'Event', 'حدث', 'Evenement'), onEvent),
    ];
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            mainAxisSpacing: 18,
            crossAxisSpacing: 12,
            childAspectRatio: 1.02,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: item.onTap,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 27,
                    backgroundColor: Colors.white,
                    child: Icon(item.icon, color: item.color, size: 31),
                  ),
                  const SizedBox(height: 8),
                  Text(item.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _AttachItem {
  const _AttachItem(this.icon, this.color, this.label, this.onTap);
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;
}

class SupportRichMessageBody extends StatelessWidget {
  const SupportRichMessageBody({super.key, required this.row});
  final Map<String, dynamic> row;

  Map<String, dynamic> get metadata => row['metadata'] is Map
      ? Map<String, dynamic>.from(row['metadata'] as Map)
      : <String, dynamic>{};

  @override
  Widget build(BuildContext context) {
    final type = '${row['message_type'] ?? 'text'}';
    if (type == 'location') return _location(context);
    if (type == 'poll') return _poll(context);
    if (type == 'event') return _event(context);
    return const SizedBox.shrink();
  }

  Widget _location(BuildContext context) {
    final lat = (metadata['latitude'] as num?)?.toDouble();
    final lng = (metadata['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return const SizedBox.shrink();
    final label = '${metadata['label'] ?? _rt(context, 'Shared location', 'موقع مشترك', 'Gedeelde locatie')}';
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => launchUrl(
        Uri.parse('https://www.google.com/maps/search/?api=1&query=$lat,$lng'),
        mode: LaunchMode.externalApplication,
      ),
      child: Container(
        width: 280,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: const Color(0xFFE7F7F2), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            height: 92,
            decoration: BoxDecoration(color: const Color(0xFFCBEBDD), borderRadius: BorderRadius.circular(9)),
            child: const Center(child: Icon(Icons.location_on_rounded, color: Color(0xFF00A884), size: 46)),
          ),
          const SizedBox(height: 9),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text('${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}', style: const TextStyle(fontSize: 11.5, color: Color(0xFF667781))),
          const SizedBox(height: 5),
          Text(_rt(context, 'Open map', 'فتح الخريطة', 'Kaart openen'), style: const TextStyle(color: Color(0xFF008069), fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }

  Widget _poll(BuildContext context) {
    final question = '${metadata['question'] ?? row['message'] ?? ''}'.trim();
    final raw = metadata['options'];
    final options = raw is List ? raw.map((e) => '$e').where((e) => e.trim().isNotEmpty).take(12).toList() : <String>[];
    if (options.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: VetSupportRichService.instance.pollVotesStream('${row['id']}'),
      builder: (context, snapshot) {
        final votes = snapshot.data ?? const <Map<String, dynamic>>[];
        final counts = List<int>.filled(options.length, 0);
        int? mine;
        final currentUser = VetBackend.instance.currentUser?.id;
        for (final vote in votes) {
          final index = (vote['option_index'] as num?)?.toInt();
          if (index != null && index >= 0 && index < counts.length) counts[index]++;
          if ('${vote['user_id']}' == currentUser) mine = index;
        }
        return Container(
          width: 285,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: .55), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [const Icon(Icons.poll_rounded, color: Color(0xFF00A884)), const SizedBox(width: 7), Expanded(child: Text(question.isEmpty ? _rt(context, 'Poll', 'استطلاع', 'Peiling') : question, style: const TextStyle(fontWeight: FontWeight.w800)))]),
            const SizedBox(height: 9),
            for (var i = 0; i < options.length; i++)
              InkWell(
                onTap: () => VetSupportRichService.instance.votePoll('${row['id']}', i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(children: [
                    Icon(mine == i ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, size: 21, color: const Color(0xFF00A884)),
                    const SizedBox(width: 8),
                    Expanded(child: Text(options[i])),
                    Text('${counts[i]}', style: const TextStyle(color: Color(0xFF667781), fontWeight: FontWeight.w700)),
                  ]),
                ),
              ),
          ]),
        );
      },
    );
  }

  Widget _event(BuildContext context) {
    final title = '${metadata['title'] ?? row['message'] ?? _rt(context, 'Event', 'حدث', 'Evenement')}';
    final starts = DateTime.tryParse('${metadata['starts_at'] ?? ''}')?.toLocal();
    final place = '${metadata['place'] ?? ''}'.trim();
    return Container(
      width: 280,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: const Color(0xFFFFEFF2), borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CircleAvatar(backgroundColor: Color(0xFFE54868), child: Icon(Icons.calendar_month_rounded, color: Colors.white)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          if (starts != null) ...[
            const SizedBox(height: 4),
            Text('${starts.year.toString().padLeft(4, '0')}-${starts.month.toString().padLeft(2, '0')}-${starts.day.toString().padLeft(2, '0')}  ${starts.hour.toString().padLeft(2, '0')}:${starts.minute.toString().padLeft(2, '0')}', style: const TextStyle(color: Color(0xFF667781))),
          ],
          if (place.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(place, style: const TextStyle(color: Color(0xFF667781))),
          ],
        ])),
      ]),
    );
  }
}
