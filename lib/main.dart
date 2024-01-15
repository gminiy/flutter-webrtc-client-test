import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final IO.Socket socket;
  final _localRenderer = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();
  final mediaConstraints = {
    'audio': true,
    'video': {
      'mandatory': {
        'minWidth': '640', // 최소 너비
        'minHeight': '480', // 최소 높이
        'minFrameRate': '30', // 최소 프레임 속도
      },
      'facingMode': 'user',
    },
  };

  MediaStream? _localStream;
  RTCPeerConnection? pc;

  @override
  void initState() {
    // TODO: implement initState
    super.initState();
    initRenderers();
  }

  @override
  void dispose() {
    _localStream?.dispose();
    _localRenderer.srcObject = null;
    super.dispose();
  }

  Future initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    _localRenderer.srcObject = _localStream;
    await connectSocket();
    await joinRoom();

    setState(() {});
  }

  Future connectSocket() async{
    socket = IO.io('http://172.30.1.18:3000', IO.OptionBuilder().setTransports(['websocket']).build());
    socket.onConnect((data) => print('연결 완료 !'));

    socket.on('joined', (data){
      _sendOffer();
    });


    socket.on('offer', (data) async{
      data = jsonDecode(data);
      await _gotOffer(RTCSessionDescription(data['sdp'], data['type']));
      await _sendAnswer();
    });


    socket.on('answer', (data){
      data = jsonDecode(data);
      _gotAnswer(RTCSessionDescription(data['sdp'], data['type']));
    });


    socket.on('ice', (data){
      data = jsonDecode(data);
      _gotIce(RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']));
    });
  }

  Future joinRoom() async{
    final config = {
      'iceServers': [
        {"url": "stun:stun.l.google.com:19302"},
      ]
    };

    final sdpConstraints = {
      'mandatory':{
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': true,
      },
      'optional':[]
    };

    pc = await createPeerConnection(config, sdpConstraints);

    _localStream!.getTracks().forEach((track) {
      pc!.addTrack(track, _localStream!);
    });
    _localRenderer.srcObject = _localStream;
    pc!.onIceCandidate = (ice) {
      print('ice Candidate');
      print(ice);
      _sendIce(ice);
    };

    pc!.onAddStream = (stream){
      _remoteRenderer.srcObject = stream;
      setState(() {});
    };

    socket.emit('join');
  }

  Future _sendOffer() async{
    print('send offer');
    var offer = await pc!.createOffer();
    pc!.setLocalDescription(offer);
    socket.emit('offer', jsonEncode(offer.toMap()));
  }

  Future _gotOffer(RTCSessionDescription offer) async{
    print('got offer');
    pc!.setRemoteDescription(offer);
  }
  Future _sendAnswer() async{
    print('send answer');
    var answer = await pc!.createAnswer();
    pc!.setLocalDescription(answer);
    socket.emit('answer', jsonEncode(answer.toMap()));
  }

  Future _gotAnswer(RTCSessionDescription answer) async{
    print('got answer');
    pc!.setRemoteDescription(answer);
  }

  Future _sendIce(RTCIceCandidate ice) async{
    socket.emit('ice', jsonEncode(ice.toMap()));
  }
  Future _gotIce(RTCIceCandidate ice) async{
    pc!.addCandidate(ice);
  }

  @override
  Widget build(BuildContext context) {
    // TODO: implement build
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              children: [
                Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(color: Colors.white),
                  child: RTCVideoView(_localRenderer),
                ),
                Container(
                  width: 300,
                  height: 300,
                  decoration: BoxDecoration(color: Colors.white),
                  child: RTCVideoView(_remoteRenderer),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
