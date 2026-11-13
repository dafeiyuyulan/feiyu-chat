import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const FeiyuApp());

const kDefaultServer = 'http://192.168.1.2:8790';

class FeiyuApp extends StatelessWidget {
  const FeiyuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '肥鱼小窝',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0B1220),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2B6EF2),
          surface: Color(0xFF101A2B),
        ),
      ),
      home: const ChatPage(),
    );
  }
}

class Msg {
  Msg(this.text, this.me, {this.streaming = false});
  String text;
  final bool me;
  bool streaming;
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final List<Msg> _msgs = [];
  String _server = kDefaultServer;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final sp = await SharedPreferences.getInstance();
    _server = sp.getString('server') ?? kDefaultServer;
    if (mounted) setState(() {});
    await _loadHistory();
  }

  Future<void> _loadHistory() async {
    try {
      final r = await http
          .get(Uri.parse('$_server/api/history'))
          .timeout(const Duration(seconds: 8));
      final arr = jsonDecode(utf8.decode(r.bodyBytes)) as List;
      if (!mounted) return;
      setState(() {
        _msgs
          ..clear()
          ..addAll(arr.map((m) => Msg(m['content'] as String, m['role'] == 'user')));
      });
      _jumpBottom();
    } catch (_) {
      // 拉不到历史不吵，直接空着开始聊
    }
  }

  void _jumpBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    _input.clear();
    final reply = Msg('...', false, streaming: true);
    setState(() {
      _msgs.add(Msg(text, true));
      _msgs.add(reply);
      _busy = true;
    });
    _jumpBottom();

    try {
      final req = http.Request('POST', Uri.parse('$_server/api/chat'))
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({'text': text});
      final resp = await req.send();
      final buf = StringBuffer();
      await for (final chunk in resp.stream) {
        buf.write(utf8.decode(chunk, allowMalformed: true));
        var raw = buf.toString();
        final parts = raw.split('\n\n');
        buf.clear();
        buf.write(parts.removeLast());
        for (final p in parts) {
          if (!p.startsWith('data: ')) continue;
          final data = p.substring(6);
          if (data == '[DONE]') continue;
          try {
            final j = jsonDecode(data) as Map<String, dynamic>;
            if (j['err'] != null) {
              reply.text = '出错了：${j['err']}';
            } else if (j['d'] != null) {
              reply.streaming = false;
              reply.text =
                  (reply.text == '...' ? '' : reply.text) + (j['d'] as String);
            }
            setState(() {});
            _jumpBottom();
          } catch (_) {}
        }
      }
    } catch (e) {
      reply.text = '连不上后台，看看地址对不对';
    }
    if (mounted) {
      setState(() {
        reply.streaming = false;
        if (reply.text.trim().isEmpty) reply.text = '嗯……';
        _busy = false;
      });
      _jumpBottom();
    }
  }

  Future<void> _editServer() async {
    final ctl = TextEditingController(text: _server);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('后台地址'),
        content: TextField(
          controller: ctl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'http://192.168.1.2:8790'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('算了')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('存')),
        ],
      ),
    );
    if (ok == true) {
      final sp = await SharedPreferences.getInstance();
      await sp.setString('server', ctl.text.trim());
      setState(() => _server = ctl.text.trim());
      await _loadHistory();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF12335C),
        title: GestureDetector(
          onLongPress: _editServer,
          child: const Text('肥鱼小窝', style: TextStyle(fontSize: 16, letterSpacing: 1)),
        ),
        actions: [
          IconButton(
            onPressed: _loadHistory,
            icon: const Icon(Icons.refresh),
            tooltip: '重新拉历史',
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
              itemCount: _msgs.length,
              itemBuilder: (_, i) => _bubble(_msgs[i]),
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: const BoxDecoration(
                color: Color(0xFF101A2B),
                border: Border(top: BorderSide(color: Color(0xFF1B2740))),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        hintText: '跟岚岚说点什么',
                        filled: true,
                        fillColor: const Color(0xFF182337),
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _send,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('发'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(Msg m) {
    final me = m.me;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: me ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: me ? const Color(0xFF2B6EF2) : const Color(0xFF1B2740),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(me ? 16 : 5),
                  bottomRight: Radius.circular(me ? 5 : 16),
                ),
              ),
              child: Text(
                m.text,
                style: TextStyle(
                  fontSize: 15,
                  height: 1.45,
                  color: me ? Colors.white : const Color(0xFFDFE8F5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
