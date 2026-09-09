import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../i18n/vet_locale.dart';
import 'support_rich_service.dart';
import 'support_rich_widgets.dart';

String _pt(BuildContext context, String en, String ar, String nl) =>
    VetTranslator.instance.text(
      localeCode: Localizations.localeOf(context).languageCode,
      en: en,
      ar: ar,
      nl: nl,
    );

class VetFarmProfilePhotoEditor extends StatefulWidget {
  const VetFarmProfilePhotoEditor({
    super.key,
    required this.farm,
    this.onChanged,
    this.compact = false,
  });

  final Map<String, dynamic> farm;
  final VoidCallback? onChanged;
  final bool compact;

  @override
  State<VetFarmProfilePhotoEditor> createState() => _VetFarmProfilePhotoEditorState();
}

class _VetFarmProfilePhotoEditorState extends State<VetFarmProfilePhotoEditor> {
  final picker = ImagePicker();
  bool busy = false;

  Future<void> _pick(ImageSource source) async {
    if (busy) return;
    final file = await picker.pickImage(
      source: source,
      imageQuality: 90,
      maxWidth: 1800,
      maxHeight: 1800,
    );
    if (file == null || !mounted) return;
    setState(() => busy = true);
    try {
      final bytes = await file.readAsBytes();
      final lower = file.name.toLowerCase();
      final mime = lower.endsWith('.png')
          ? 'image/png'
          : lower.endsWith('.webp')
              ? 'image/webp'
              : lower.endsWith('.heic')
                  ? 'image/heic'
                  : lower.endsWith('.heif')
                      ? 'image/heif'
                      : 'image/jpeg';
      final path = await VetSupportRichService.instance.uploadFarmPhoto(
        farmId: widget.farm['id'].toString(),
        bytes: bytes,
        fileName: file.name,
        mimeType: mime,
      );
      widget.farm['profile_photo_path'] = path;
      widget.farm['profile_photo_updated_at'] = DateTime.now().toUtc().toIso8601String();
      if (mounted) setState(() {});
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_pt(context, 'Could not save the profile photo', 'تعذر حفظ صورة البروفايل', 'Profielfoto kon niet worden opgeslagen')}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _choose() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_rounded),
              title: Text(_pt(context, 'Choose photo', 'اختيار صورة', 'Foto kiezen')),
              onTap: () {
                Navigator.pop(sheetContext);
                _pick(ImageSource.gallery);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded),
              title: Text(_pt(context, 'Take photo', 'التقاط صورة', 'Foto maken')),
              onTap: () {
                Navigator.pop(sheetContext);
                _pick(ImageSource.camera);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avatar = VetFarmAvatar(
      photoPath: widget.farm['profile_photo_path']?.toString(),
      radius: widget.compact ? 34 : 48,
      fallbackIcon: Icons.domain_rounded,
    );
    if (widget.compact) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          avatar,
          PositionedDirectional(
            end: -5,
            bottom: -5,
            child: InkWell(
              onTap: busy ? null : _choose,
              child: CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFF00A884),
                child: busy
                    ? const SizedBox.square(dimension: 13, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.camera_alt_rounded, size: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.farm['company_name'] ?? widget.farm['farm_name'] ?? ''}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _pt(context, 'Tap the photo to view it full size.', 'اضغط على الصورة لعرضها بالحجم الكامل.', 'Tik op de foto om deze volledig te bekijken.'),
                    style: const TextStyle(color: Color(0xFF667781), fontSize: 12),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: busy ? null : _choose,
                    icon: busy
                        ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add_a_photo_rounded),
                    label: Text(_pt(context, 'Change profile photo', 'تغيير صورة البروفايل', 'Profielfoto wijzigen')),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
