import 'package:flutter/material.dart';
import 'package:flutter_vlc_player/flutter_vlc_player.dart';

class CameraLiveViewPage extends StatefulWidget {
  const CameraLiveViewPage({
    super.key,
    required this.streamUri,
    required this.username,
    required this.password,
    this.cameraName = 'IP Camera',
  });

  final String streamUri;
  final String username;
  final String password;
  final String cameraName;

  @override
  State<CameraLiveViewPage> createState() => _CameraLiveViewPageState();
}

class _CameraLiveViewPageState extends State<CameraLiveViewPage> {
  late final VlcPlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = VlcPlayerController.network(
      _authenticatedRtspUri(widget.streamUri, widget.username, widget.password),
      hwAcc: HwAcc.full,
      autoPlay: true,
      allowBackgroundPlayback: false,
    );
  }

  static String _authenticatedRtspUri(
    String source,
    String username,
    String password,
  ) {
    final parsed = Uri.parse(source);
    if (parsed.scheme.toLowerCase() != 'rtsp' || username.isEmpty) return source;
    return Uri(
      scheme: parsed.scheme,
      userInfo:
          '${Uri.encodeComponent(username)}:${Uri.encodeComponent(password)}',
      host: parsed.host,
      port: parsed.hasPort ? parsed.port : null,
      path: parsed.path,
      query: parsed.hasQuery ? parsed.query : null,
      fragment: parsed.hasFragment ? parsed.fragment : null,
    ).toString();
  }

  @override
  void dispose() {
    _controller.stop();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.cameraName),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Center(
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: VlcPlayer(
              controller: _controller,
              aspectRatio: 16 / 9,
              placeholder: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
