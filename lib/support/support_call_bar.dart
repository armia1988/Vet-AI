import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import '../theme/app_theme.dart';
import 'support_call_service.dart';
import 'support_webrtc_call_page.dart';

String _cbt(BuildContext context, String en, String ar, String nl) => VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class SupportCallBar extends StatelessWidget {
  const SupportCallBar({super.key, required this.threadId, required this.role});
  final String threadId;
  final String role;

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Map<String, dynamic>>>(
        stream: VetSupportCallService.instance.callsStream(threadId),
        builder: (context, snapshot) {
          final active = (snapshot.data ?? const <Map<String, dynamic>>[])
              .where((c) => c['status'] == 'ringing')
              .toList();
          if (active.isEmpty) return const SizedBox.shrink();
          final call = active.first;
          final incoming = '${call['caller_role']}' != role;
          if (!incoming) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: VetColors.softGreen,
              child: Row(children: [
                Icon(call['call_type'] == 'video' ? Icons.videocam_rounded : Icons.call_rounded, color: VetColors.green),
                const SizedBox(width: 8),
                Expanded(child: Text(_cbt(context, 'Calling…', 'جاري الاتصال…', 'Bellen…'), style: const TextStyle(fontWeight: FontWeight.w900))),
                TextButton(
                  onPressed: () => VetSupportCallService.instance.end(call['id'].toString()),
                  child: Text(_cbt(context, 'End', 'إنهاء', 'Stop')),
                ),
              ]),
            );
          }
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: VetColors.softGreen,
            child: Row(children: [
              Icon(call['call_type'] == 'video' ? Icons.video_call_rounded : Icons.call_rounded, color: VetColors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  call['call_type'] == 'video'
                      ? _cbt(context, 'Incoming video call', 'مكالمة فيديو واردة', 'Inkomend videogesprek')
                      : _cbt(context, 'Incoming voice call', 'مكالمة صوتية واردة', 'Inkomende spraakoproep'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              TextButton(
                onPressed: () => VetSupportCallService.instance.decline(call['id'].toString()),
                child: Text(_cbt(context, 'Decline', 'رفض', 'Weigeren')),
              ),
              const SizedBox(width: 5),
              FilledButton.icon(
                onPressed: () async {
                  await VetSupportCallService.instance.accept(call['id'].toString());
                  if (!context.mounted) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => VetWebRtcCallPage(
                        call: call,
                        role: role,
                        isCaller: false,
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.call_rounded),
                label: Text(_cbt(context, 'Answer', 'رد', 'Opnemen')),
              ),
            ]),
          );
        },
      );
}
