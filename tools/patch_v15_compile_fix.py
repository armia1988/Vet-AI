from pathlib import Path

# Keep localized V5 email content while allowing legacy source files to compile.
p = Path('lib/services/vet_backend.dart')
s = p.read_text()
old = """    required String preferredLanguage,
    required String emailSubject,
    required String emailHeading,
    required String emailBody,
    required String emailButton,
    required String emailFooter,
"""
new = """    required String preferredLanguage,
    String emailSubject = 'Vet AI — Confirm your account',
    String emailHeading = 'Welcome to Vet AI',
    String emailBody = 'Confirm your email address to finish creating your Vet AI account and securely access your farm data.',
    String emailButton = 'Confirm Vet AI account',
    String emailFooter = 'If you did not create this Vet AI account, you can ignore this email.',
"""
if old not in s:
    raise SystemExit('VetBackend signup parameters not found')
p.write_text(s.replace(old, new, 1))

# The compact brand mode is no longer used after the new direction-aware header.
p = Path('lib/v5_app.dart')
s = p.read_text()
old = """class _BrandLockup extends StatelessWidget {
  const _BrandLockup({required this.markWidth,this.compact=false}); final double markWidth; final bool compact;
  @override Widget build(BuildContext context)=>Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:compact?CrossAxisAlignment.start:CrossAxisAlignment.center,children:[SvgPicture.asset('assets/vet_ai_logo.svg',width:markWidth,height:markWidth*.66,colorFilter:const ColorFilter.mode(VetColors.primary,BlendMode.srcIn)),SizedBox(height:compact?2:7),Text.rich(TextSpan(children:[const TextSpan(text:'Vet ',style:TextStyle(color:VetColors.text)),TextSpan(text:'AI',style:TextStyle(color:VetColors.primary))]),style:TextStyle(fontSize:compact?25:31,fontWeight:FontWeight.w900,letterSpacing:.2))]);
}
"""
new = """class _BrandLockup extends StatelessWidget {
  const _BrandLockup({required this.markWidth}); final double markWidth;
  @override Widget build(BuildContext context)=>Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.center,children:[SvgPicture.asset('assets/vet_ai_logo.svg',width:markWidth,height:markWidth*.66,colorFilter:const ColorFilter.mode(VetColors.primary,BlendMode.srcIn)),const SizedBox(height:7),Text.rich(TextSpan(children:[const TextSpan(text:'Vet ',style:TextStyle(color:VetColors.text)),TextSpan(text:'AI',style:TextStyle(color:VetColors.primary))]),style:const TextStyle(fontSize:31,fontWeight:FontWeight.w900,letterSpacing:.2))]);
}
"""
if old not in s:
    raise SystemExit('BrandLockup block not found')
p.write_text(s.replace(old, new, 1))
