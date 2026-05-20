import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

class WebRTCManager {
  RTCPeerConnection? peerConnection;
  RTCDataChannel? dataChannel;

  Function(String)? onLog;
  Function(dynamic)? onMessage;

  List<int> _recievedChunks = [];
  Map<String, dynamic>? _metadata;

  final Map<String, dynamic> config = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
    ],
  };

  Future<void> init(Function(String, dynamic) sendSignal, String target) async {
    peerConnection = await createPeerConnection(config);

    peerConnection?.onIceCandidate = (candidate) {
      sendSignal("candidate", candidate.toMap());
    };

    peerConnection?.onDataChannel = (channel) {
      _setupDataChannel(channel);
    };
  }

  Future<void> createOffer(
    Function(String, dynamic) sendSignal,
    String target,
  ) async {
    RTCDataChannelInit init = RTCDataChannelInit();
    dataChannel = await peerConnection!.createDataChannel(
      "file-transfer",
      init,
    );
    _setupDataChannel(dataChannel!);

    RTCSessionDescription offer = await peerConnection!.createOffer();
    await peerConnection!.setLocalDescription(offer);
    sendSignal("offer", offer.toMap());
  }

  Future<void> createAnswer(
    dynamic offerData,
    Function(String, dynamic) sendSignal,
    String target,
  ) async {
    var offer = RTCSessionDescription(offerData['sdp'], offerData['type']);
    await peerConnection!.setRemoteDescription(offer);

    RTCSessionDescription answer = await peerConnection!.createAnswer();
    await peerConnection!.setLocalDescription(answer);
    sendSignal("answer", answer.toMap());
  }

  void _setupDataChannel(RTCDataChannel channel) {
    dataChannel = channel;

    dataChannel!.onMessage = (RTCDataChannelMessage message) {
      if (message.isBinary) {
        _recievedChunks.addAll(message.binary);

        if (_metadata != null && _recievedChunks.length >= _metadata!['size']) {
          onMessage?.call({
            "type": "file_complete",
            "bytes": _recievedChunks,
            "metadata": _metadata,
          });
          _recievedChunks = [];
          _metadata = null;
        }
      } else {
        try {
          final decoded = jsonDecode(message.text);

          if (decoded['type'] == "metadata") {
            _metadata = decoded;
            _recievedChunks = [];
            onLog?.call("Recieving file : ${decoded['name']}");
          } else {
            onMessage?.call(decoded);
          }
        } catch (e) {
          onMessage?.call(message.text);
        }
      }
    };

    dataChannel!.onDataChannelState = (state) {
      onLog?.call("Data Channel State : $state");
    };
  }
}
