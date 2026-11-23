import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'v5_app.dart' show tr;

typedef _Row = Map<String, dynamic>;

class AlertTeamPage extends StatefulWidget {
  const AlertTeamPage({super.key, required this.farmId});
  final String farmId;
  @override
  State<AlertTeamPage> createState() => _AlertTeamPageState();
}

class _AlertTeamPageState extends State<AlertTeamPage> {
  final db = Supabase.instance.client;
  int tab = 0;
  int page = 0;
  late Future<List<_Row>> result;
  String t(String en,String ar,String nl) => tr(context,en,ar,nl);

  @override
  void initState() {
    super.initState();
    result = load();
  }

  Future<List<_Row>> load() async {
    if (tab == 2) {
      return await db.from('alert_team_comparison').select().order('farm_id').order('barn').range(page*50,page*50+49);
    }
    var query = db.from('alert_team_summary').select().eq('farm_id',widget.farmId);
    if (tab == 1) query = query.eq('closed',false);
    return await query.order('created_at',ascending:false).order('id').range(page*50,page*50+49);
  }

  void refresh() => setState(() {result = load();});

  Future<void> edit(_Row row) async {
    String owner = row['assignee']?.toString() ?? '';
    String note = '';
    bool closed = row['closed'] == true;
    final saved = await showDialog<bool>(context:context,builder:(ctx) => StatefulBuilder(builder:(ctx,update) => AlertDialog(
      title: Text(row['title']?.toString() ?? ''),
      content: SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextFormField(initialValue:owner,maxLength:160,decoration:InputDecoration(labelText:t('Assigned to','المسؤول','Verantwoordelijke')),onChanged:(v)=>update((){owner=v;})),
        TextField(maxLength:4000,maxLines:3,decoration:InputDecoration(labelText:t('Action or handoff note','الإجراء أو ملاحظة التسليم','Actie of overdracht')),onChanged:(v)=>update((){note=v;})),
        SwitchListTile(title:Text(t('Closed','مغلق','Gesloten')),value:closed,onChanged:(v)=>update((){closed=v;})),
      ])),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:Text(MaterialLocalizations.of(ctx).cancelButtonLabel)),
        FilledButton(onPressed:owner.trim().isEmpty||note.trim().isEmpty?null:()=>Navigator.pop(ctx,true),child:Text(t('Save','حفظ','Opslaan')))],
    )));
    if(saved != true || !mounted) return;
    await db.from('alert_followups').insert({'alert_id':row['id'],'assignee':owner.trim(),'note':note.trim(),'closed':closed});
    if(mounted) refresh();
  }

  Future<void> report(_Row row) async {
    final alert = await db.from('alerts').select().eq('id',row['id']).single();
    final history = <_Row>[];
    for(var offset=0;;offset+=200) {
      final batch=await db.from('alert_followups').select().eq('alert_id',row['id']).order('id').range(offset,offset+199);
      history.addAll(batch);
      if(batch.length<200) break;
    }
    if(!mounted) return;
    final attach = await showDialog<bool>(context:context,builder:(ctx)=>SimpleDialog(title:Text(t('Veterinary report','تقرير الطبيب','Dierenartsrapport')),children:[
      SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,false),child:Text(t('Share PDF','مشاركة التقرير','PDF delen'))),
      SimpleDialogOption(onPressed:()=>Navigator.pop(ctx,true),child:Text(t('Add a case photo and share','إضافة صورة للحالة ومشاركة التقرير','Voeg foto toe en deel'))),
    ]));
    if(attach==null)return;
    pw.MemoryImage? photo;
    if(attach){
      final file=await ImagePicker().pickImage(source:ImageSource.gallery,maxWidth:1600,imageQuality:80);
      if(file==null)return;
      photo=pw.MemoryImage(await file.readAsBytes());
    }
    final font=await PdfGoogleFonts.notoNaskhArabicRegular();
    final pdf=pw.Document();
    final lines=[
      row['farm_name'],alert['title'],alert['created_at'],alert['details'],
      if(alert['metric']!=null) '${alert['metric']}: ${alert['value_numeric'] ?? ''} (${alert['threshold_text'] ?? ''})',
      for(final e in history) "${e['at']} · ${e['assignee']} · ${e['closed']==true?'Closed':'Open'}\n${e['note']}",
    ].whereType<String>();
    pdf.addPage(pw.MultiPage(build:(_)=>[
      pw.Header(text:'Vet AI | Case report'),
      for(final line in lines) pw.Text(line,style:pw.TextStyle(font:font),textDirection:RegExp(r'[\u0600-\u06FF]').hasMatch(line)?pw.TextDirection.rtl:pw.TextDirection.ltr),
      if(photo!=null) pw.Image(photo,height:220),
    ]));
    await Printing.sharePdf(bytes:await pdf.save(),filename:'vet-ai-case-${row['id']}.pdf');
  }

  Future<void> run(Future<void> Function() action) async {
    try {await action();} catch (_) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(t('Action failed. Check access and connection.','تعذرت العملية. راجع الصلاحيات والاتصال.','Actie mislukt. Controleer toegang en verbinding.'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final labels=[t('Cases','الحالات','Zaken'),t('Shift handoff','تسليم الوردية','Overdracht'),t('Compare','مقارنة','Vergelijken')];
    return Scaffold(appBar:AppBar(title:Text(labels[tab]),actions:[IconButton(onPressed:refresh,icon:const Icon(Icons.refresh))]),
      bottomNavigationBar:NavigationBar(selectedIndex:tab,onDestinationSelected:(i){tab=i;page=0;refresh();},destinations:[
        for(final (i,icon) in [Icons.assignment,Icons.groups,Icons.bar_chart].indexed) NavigationDestination(icon:Icon(icon),label:labels[i]),
      ]),
      body:FutureBuilder<List<_Row>>(future:result,builder:(ctx,snap){
        if(snap.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());
        if(snap.hasError)return Center(child:OutlinedButton(onPressed:refresh,child:Text(t('Could not load. Retry','تعذر التحميل. إعادة المحاولة','Opnieuw proberen'))));
        final rows=snap.data!;
        return ListView.builder(itemCount:rows.length+1,itemBuilder:(ctx,i){
          if(i==rows.length)return Column(children:[
            if(rows.isEmpty) Text(t('No records','لا توجد سجلات','Geen gegevens')),
            Row(mainAxisAlignment:MainAxisAlignment.center,children:[
              IconButton(onPressed:page==0?null:(){page--;refresh();},icon:const Icon(Icons.navigate_before)),
              Text('${page+1}'),
              IconButton(onPressed:rows.length<50?null:(){page++;refresh();},icon:const Icon(Icons.navigate_next)),
            ]),
          ]);
          final r=rows[i];
          if(tab==2)return ListTile(title:Text([r['farm_name'],r['barn']].whereType<String>().join(' · ')),
            subtitle:Text("${t('Open','مفتوح','Open')}: ${r['pending']} / ${r['total']}\n${t('Last 7 days / preceding 7 days','آخر ٧ أيام / السبعة السابقة','Laatste 7 dagen / vorige 7 dagen')}: ${r['this_week']} / ${r['last_week']}"));
          return Card(child:ListTile(title:Text(r['title']?.toString()??''),subtitle:Text([
            r['closed']==true?t('Closed','مغلق','Gesloten'):t('Open','مفتوح','Open'),
            r['assignee']??t('Unassigned','لم يُعيّن مسؤول','Niet toegewezen'),r['note']
          ].whereType<String>().join(' · ')),onTap:()=>run(()=>edit(r)),trailing:IconButton(tooltip:t('Share report','مشاركة التقرير','Rapport delen'),icon:const Icon(Icons.picture_as_pdf),onPressed:()=>run(()=>report(r)))));
        });
      }));
  }
}
