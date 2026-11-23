import 'package:flutter/material.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

class RecorderView extends StatefulWidget {
  const RecorderView({super.key, required this.name, required this.initialChannel,
    required this.channelCount, required this.streamFor, required this.username,
    required this.password, required this.detail});
  final String name, username, password;
  final int initialChannel;
  final int? channelCount;
  final String Function(int) streamFor;
  final Widget Function(int) detail;
  @override
  State<RecorderView> createState() => _RecorderViewState();
}

class _RecorderViewState extends State<RecorderView> with WidgetsBindingObserver {
  int slots = 4;
  late int first;
  bool covered = false;
  bool foreground = true;
  int get limit => (widget.channelCount ?? 64).clamp(widget.initialChannel, 64);
  @override
  void initState() {
    super.initState();
    first = ((widget.initialChannel - 1) ~/ slots) * slots + 1;
    WidgetsBinding.instance.addObserver(this);
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() => foreground = state == AppLifecycleState.resumed);
  }
  Future<void> open(int channel) async {
    setState(() => covered = true);
    try {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => widget.detail(channel)));
    } finally {
      if (mounted) setState(() => covered = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    final label = locale == 'ar' ? 'قناة' : locale == 'nl' ? 'Kanaal' : 'Channel';
    final end = (first + slots - 1).clamp(first, limit);
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(12), children: [
        SegmentedButton<int>(
          segments: [for (final n in [1,4,9,16]) ButtonSegment(value:n,label:Text('$n'))],
          selected:{slots},
          onSelectionChanged:(values) => setState(() {
            slots = values.single;
            first = ((first - 1) ~/ slots) * slots + 1;
          }),
        ),
        const SizedBox(height:12),
        if (!covered && foreground)
          GridView.count(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),
            crossAxisCount: slots == 1 ? 1 : slots == 4 ? 2 : slots == 9 ? 3 : 4,
            childAspectRatio: 1.45,mainAxisSpacing:4,crossAxisSpacing:4,
            children:[for(int n=first;n<=end;n++) _ChannelPreview(key:ValueKey(n),
              stream:widget.streamFor(n),username:widget.username,password:widget.password,
              label:'$label $n',open:()=>open(n))]),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,children:[
          IconButton(onPressed:first>1?()=>setState(()=>first-=slots):null,icon:const Icon(Icons.chevron_left)),
          Text('$label $first–$end'),
          IconButton(onPressed:end<limit?()=>setState(()=>first+=slots):null,icon:const Icon(Icons.chevron_right)),
        ]),
      ])),
    );
  }
}

class _ChannelPreview extends StatefulWidget {
  const _ChannelPreview({super.key,required this.stream, required this.username,
    required this.password, required this.label, required this.open});
  final String stream, username, password, label;
  final VoidCallback open;
  @override
  State<_ChannelPreview> createState()=>_ChannelPreviewState();
}

class _ChannelPreviewState extends State<_ChannelPreview> {
  late final player=VlcPlayerController.network(widget.stream,hwAcc:HwAcc.auto,
    allowBackgroundPlayback:false,autoPlay:true,options:VlcPlayerOptions(extras:[
      ':no-audio', ':rtsp-tcp', ':network-caching=1000',
      if(widget.username.isNotEmpty) ':rtsp-user=${widget.username}',
      if(widget.username.isNotEmpty) ':rtsp-pwd=${widget.password}',
    ]));
  @override
  void dispose(){player.dispose();super.dispose();}
  @override
  Widget build(BuildContext context)=>ClipRRect(borderRadius:BorderRadius.circular(10),
    child: ColoredBox(color:const Color(0xff13282b),child:Stack(fit:StackFit.expand,children:[
      VlcPlayer(controller:player,aspectRatio:16/9,placeholder:const SizedBox.shrink()),
      PositionedDirectional(start:4,bottom:4,child:ColoredBox(color:Colors.black87,
        child:Padding(padding:const EdgeInsets.symmetric(horizontal:5,vertical:2),
          child:Text(widget.label,style:const TextStyle(color:Colors.white,fontSize:11))))),
      Semantics(button:true,label:widget.label,child:GestureDetector(behavior:HitTestBehavior.opaque,onTap:widget.open)),
    ])));
}
