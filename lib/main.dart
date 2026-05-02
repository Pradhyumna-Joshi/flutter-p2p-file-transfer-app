import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_p2p/data/providers/signaling_client.dart';
import 'package:flutter_p2p/data/providers/webrtc_manager.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: .fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const Home(),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final WebRTCManager _webrtc = WebRTCManager();
  final SignalingClient _client = SignalingClient();
  final List<String> logs = [];
  final TextEditingController _controller = TextEditingController();
  final TextEditingController _targetController = TextEditingController();
  final TextEditingController _msgController = TextEditingController();

  void handleRegister() {
    final name = _controller.text;
    if (name.isEmpty) return;

    _client.connect("ws://localhost:8080/ws", (msg) async {
      final type = msg['type'];
      final data = jsonDecode(msg['data'] ?? "{}");

      switch (type) {
        case "offer":
          await _webrtc.init(
            (t, d) => _client.send(t, name, msg['from'], jsonEncode(d)),
            msg['from'],
          );

          setupWebRTCListners();
          await _webrtc.createAnswer(
            data,
            (t, d) => _client.send(t, name, msg['from'], jsonEncode(d)),
            msg['from'],
          );
          break;
        case "answer":
          await _webrtc.peerConnection!.setRemoteDescription(
            RTCSessionDescription(data['sdp'], data['type']),
          );
          break;
        case "candidate":
          await _webrtc.peerConnection!.addCandidate(
            RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ),
          );
          break;
        case "chat":
          setState(() => logs.add("[CHAT] ${msg['from']}: ${msg['data']}"));
          break;
      }
    });

    Future.delayed(Duration(milliseconds: 500), () {
      _client.send("register", name, "", "");
      setState(() {
        logs.add("System: Sent registration for $name");
      });
    });
  }

  void setupWebRTCListners() {
    _webrtc.onMessage = (data) async {
      if (data is Map && data["type"] == "file_complete") {
        final String fileName = data['metadata']['name'];
        final List<int> bytes = data['bytes'];

        final directory = await getApplicationDocumentsDirectory();
        final filePath = '${directory.path}/$fileName';
        final file = File(filePath);

        await file.writeAsBytes(bytes);

        setState(() {
          logs.add("FILE SAVED: $filePath");
        });

        _showOpenFileDialog(filePath);
      } else {
        setState(() {
          logs.add("[P2P IN] : $data");
        });
      }
    };

    _webrtc.onLog = (data) {
      setState(() {
        logs.add("System : $data");
      });
    };
  }

  void startP2P() async {
    final name = _controller.text;
    final target = _targetController.text;

    await _webrtc.init(
      (t, d) => _client.send(t, name, target, jsonEncode(d)),
      target,
    );
    setupWebRTCListners();
    await _webrtc.createOffer(
      (t, d) => _client.send(t, name, target, jsonEncode(d)),
      target,
    );
  }

  void startP2PTransfer() {
    final msg = _msgController.text;
    if (msg.isEmpty || _webrtc.dataChannel == null) {
      setState(() => logs.add("System: Data Channel not ready!"));
      return;
    }

    _webrtc.dataChannel!.send(RTCDataChannelMessage(msg));

    setState(() {
      logs.add("[P2P OUT] Me: $msg");
      _msgController.clear();
    });
  }

  void sendMessage() {
    final target = _targetController.text;
    final msg = _msgController.text;
    final from = _controller.text;

    if (target.isEmpty || msg.isEmpty) return;

    _client.send("chat", from, target, msg);
    setState(() {
      logs.add("To $target: $msg");
      _msgController.clear();
    });
  }

  void sendFile() async {
    FilePickerResult? result = await FilePicker.pickFiles();

    if (result != null && _webrtc.dataChannel != null) {
      PlatformFile file = result.files.first;
      Uint8List fileBytes;
      if (file.bytes != null) {
        fileBytes = file.bytes!;
      } else {
        final localFile = File(file.path!);
        fileBytes = await localFile.readAsBytes();
      }

      _webrtc.dataChannel!.send(
        RTCDataChannelMessage(
          jsonEncode({
            "type": "metadata",
            "name": file.name,
            "size": file.size,
          }),
        ),
      );

      const int chunksize = 16384;
      int offset = 0;
      print("BYTES ${fileBytes!.length}");
      while (offset < fileBytes!.length) {
        int end = (offset + chunksize < fileBytes.length)
            ? offset + chunksize
            : fileBytes.length;
        final chunk = fileBytes.sublist(offset, end);

        _webrtc.dataChannel!.send(RTCDataChannelMessage.fromBinary(chunk));
        offset = end;

        setState(() {
          logs.add(
            "Sending: ${(offset / fileBytes.length * 100).toStringAsFixed(0)}%",
          );
        });

        await Future.delayed(Duration(milliseconds: 1));
      }
      setState(() {
        logs.add("File sent succesfully");
      });
    } else {
      logs.add("No such file exists");
    }
  }

  void _showOpenFileDialog(String path) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("File received!"),
        action: SnackBarAction(
          label: "Open",
          onPressed: () => OpenFilex.open(path),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text("P2P File Transfer"),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),

      body: Column(
        children: [
          _buildIdentityCard(),

          _buildActionCard(),

          Padding(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8)),

          _buildLogView(),
        ],
      ),
    );
  }

  Widget _buildIdentityCard() {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: const InputDecoration(
                  labelText: "Your Username",
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: handleRegister,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
              ),
              child: Text("Register"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard() {
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 12),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _targetController,
              decoration: const InputDecoration(
                labelText: "Target Username",
                prefixIcon: Icon(Icons.person_search),
              ),
            ),
            const SizedBox(height: 16),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _actionButton(
                  icon: Icons.link,
                  label: "Connect",
                  color: Colors.blue,
                  onPressed: startP2P,
                ),
                _actionButton(
                  icon: Icons.file_upload,
                  label: "Send File",
                  color: Colors.green,
                  onPressed: sendFile,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return Column(
      children: [
        IconButton.filled(
          onPressed: onPressed,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            backgroundColor: color,
            minimumSize: const Size(56, 56),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
      ],
    );
  }

  Widget _buildLogView() {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: logs.length,
          itemBuilder: (context, index) {
            final log = logs[index];
            // Simple color coding for logs
            Color logColor = Colors.greenAccent;
            if (log.contains("System")) logColor = Colors.blueAccent;
            if (log.contains("✅")) logColor = Colors.yellowAccent;

            return Text(
              log,
              style: TextStyle(
                color: logColor,
                fontFamily: 'Courier',
                fontSize: 13,
              ),
            );
          },
        ),
      ),
    );
  }
}
