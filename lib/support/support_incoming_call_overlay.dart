import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n/vet_locale.dart';
import '../services/vet_backend.dart';
import '../theme/app_theme.dart';
import 'support_call_service.dart';
import 'support_call_tone.dart';
import 'support_webrtc_call_page.dart';

String _ict(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

/// Keeps support calls visible and audible even when the user is not currently
/// on the support-chat screen. RLS still decides which calls this account can
/// see; the widget only reacts to fresh incoming calls from the opposite role.
class VetIncomingSupportCallLayer extends StatefulWidget {
  const VetIncomingSupportCallLayer({
    super.key,
    required this.role,
    required this.child,
  });

  final String role;
  final Widget child;

  @override
  State<VetIncomingSupportCallLayer> createState() =>
      _VetIncomingSupportCallLayerState();
}

class _VetIncomingSupportCallLayerState
    extends State<VetIncomingSupportCallLayer> {
  final calls = VetSupportCallService.instance;
  String? audibleCallId;
  bool handling = false;

  Map<String, dynamic>? _freshIncoming(
    List<Map<String, dynamic>> rows,
  ) {
    final me = VetBackend.instance.currentUser?.id;
    final cutoff = DateTime.now().toUtc().subtract(const Duration(seconds: 75));
    final candidates = rows.where((row) {
      if (row['status'] != 'ringing') return false;
      if ('${row['caller_role']}' == widget.role) return false;
      if (me != null && '${row['initiated_by']}' == me) return false;
      final created = DateTime.tryParse('${row['created_at'] ?? ''}')?.toUtc();
      return created != null && created.isAfter(cutoff);
    }).toList(growable: true)
      ..sort((a, b) {
        final at = DateTime.tryParse('${a['created_at'] ?? ''}') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bt = DateTime.tryParse('${b['created_at'] ?? ''}') ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return bt.compareTo(at);
      });
    return candidates.isEmpty ? null : candidates.first;
  }

  void _syncTone(Map<String, dynamic>? call) {
    final nextId = call?['id']?.toString();
    if (nextId == audibleCallId) return;
    final previous = audibleCallId;
    audibleCallId = nextId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (previous != null) {
        unawaited(VetSupportCallTone.stopIncoming(previous));
      }
      if (nextId != null && mounted) {
        unawaited(VetSupportCallTone.startIncoming(nextId));
      }
    });
  }

  Future<void> _decline(Map<String, dynamic> call) async {
    if (handling) return;
    setState(() => handling = true);
    final id = '${call['id']}';
    await VetSupportCallTone.stopIncoming(id);
    try {
      await calls.decline(id);
    } finally {
      if (mounted) setState(() => handling = false);
    }
  }

  Future<void> _answer(Map<String, dynamic> call) async {
    if (handling) return;
    setState(() => handling = true);
    final id = '${call['id']}';
    await VetSupportCallTone.stopIncoming(id);
    try {
      await calls.accept(id);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VetWebRtcCallPage(
            call: {...call, 'status': 'accepted'},
            role: widget.role,
            isCaller: false,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: VetColors.red,
            content: Text(
              '${_ict(context, 'Could not answer the call.', 'تعذر الرد على المكالمة.', 'De oproep kon niet worden opgenomen.')} $error',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => handling = false);
    }
  }

  @override
  void dispose() {
    final id = audibleCallId;
    if (id != null) unawaited(VetSupportCallTone.stopIncoming(id));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: calls.accessibleCallsStream(),
      builder: (context, snapshot) {
        final call = _freshIncoming(
          snapshot.data ?? const <Map<String, dynamic>>[],
        );
        _syncTone(call);

        return Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (call != null)
              Positioned.fill(
                child: Material(
                  color: const Color(0xAA07181B),
                  child: SafeArea(
                    child: Center(
                      child: Container(
                        width: 360,
                        constraints: const BoxConstraints(maxWidth: 360),
                        margin: const EdgeInsets.all(20),
                        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(28),
                          boxShadow: const [
                            BoxShadow(
                              blurRadius: 34,
                              offset: Offset(0, 14),
                              color: Color(0x33000000),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 82,
                              height: 82,
                              decoration: const BoxDecoration(
                                color: Color(0xFFE1F5EF),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                call['call_type'] == 'video'
                                    ? Icons.videocam_rounded
                                    : Icons.call_rounded,
                                size: 43,
                                color: VetColors.green,
                              ),
                            ),
                            const SizedBox(height: 17),
                            Text(
                              widget.role == 'user'
                                  ? _ict(
                                      context,
                                      'Vet AI Support',
                                      'دعم Vet AI',
                                      'Vet AI Support',
                                    )
                                  : _ict(
                                      context,
                                      'Customer',
                                      'العميل',
                                      'Klant',
                                    ),
                              style: const TextStyle(
                                fontSize: 23,
                                fontWeight: FontWeight.w900,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 5),
                            Text(
                              call['call_type'] == 'video'
                                  ? _ict(
                                      context,
                                      'Incoming video call…',
                                      'مكالمة فيديو واردة…',
                                      'Inkomend videogesprek…',
                                    )
                                  : _ict(
                                      context,
                                      'Incoming voice call…',
                                      'مكالمة صوتية واردة…',
                                      'Inkomende spraakoproep…',
                                    ),
                              style: const TextStyle(
                                color: VetColors.muted,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 25),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _CallChoice(
                                  background: const Color(0xFFDC3545),
                                  icon: Icons.call_end_rounded,
                                  label: _ict(
                                    context,
                                    'Decline',
                                    'رفض',
                                    'Weigeren',
                                  ),
                                  onTap: handling ? null : () => _decline(call),
                                ),
                                _CallChoice(
                                  background: const Color(0xFF24A148),
                                  icon: Icons.call_rounded,
                                  label: _ict(
                                    context,
                                    'Answer',
                                    'رد',
                                    'Opnemen',
                                  ),
                                  onTap: handling ? null : () => _answer(call),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CallChoice extends StatelessWidget {
  const _CallChoice({
    required this.background,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Color background;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: background,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: 64,
              height: 64,
              child: Icon(icon, color: Colors.white, size: 31),
            ),
          ),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}
