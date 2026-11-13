import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() => runApp(const FeiyuApp());

const kDefaultServer = 'http://192.168.1.2:8790';
const kAppVersion = '0.1.4';

const kBlue = Color(0xFF2B6EF2);
const kBg = Color(0xFF0A1019);
const kPanel = Color(0xFF111A2A);
const kBubbleMe = Color(0xFF2B6EF2);
const kBubbleYou = Color(0xFF1A2434);
const kHint = Color(0xFF8FA3BF);

class FeiyuApp extends StatelessWidget {
  const FeiyuApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '肥鱼小窝',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(
          primary: kBlue,
          surface: kPanel,
        ),
        fontFamily: 'sans-serif',
      ),
      home: const ChatPage(),
    );
  }
}

class Msg {
  Msg(this.text, this.me, {this.streaming = false, DateTime? ts})
      : ts = ts ?? DateTime.now();
  String text;
  final bool me;
  bool streaming;
  final DateTime ts;
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
          ..addAll(arr.map((m) {
            final ts = (m['ts'] is num)
                ? DateTime.fromMillisecondsSinceEpoch(
                    ((m['ts'] as num) * 1000).round())
                : DateTime.now();
            return Msg(m['content'] as String, m['role'] == 'user', ts: ts);
          }));
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
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool _newer(String remote, String local) {
    List<int> p(String v) => v
        .split(RegExp(r'[.+-]'))
        .take(3)
        .map((e) => int.tryParse(e) ?? 0)
        .toList();
    final a = p(remote), b = p(local);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _checkUpdate() async {
    Map<String, dynamic> info;
    try {
      final r = await http
          .get(Uri.parse('$_server/api/version'))
          .timeout(const Duration(seconds: 8));
      info = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      _toast('连不上后台，可能没开');
      return;
    }
    final remote = (info['version'] ?? '').toString();
    final url = (info['url'] ?? '').toString();
    if (!_newer(remote, kAppVersion)) {
      _toast('已经是最新的啦 $kAppVersion');
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: kPanel,
        title: Text('有新版本 $remote'),
        content: Text(
          (info['notes'] ?? '').toString().isEmpty
              ? '现在装的是 $kAppVersion，要不要下新的'
              : info['notes'].toString(),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('待会儿')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final uri = Uri.tryParse(url);
              if (uri == null) {
                _toast('下载地址不对');
                return;
              }
              final ok =
                  await launchUrl(uri, mode: LaunchMode.externalApplication);
              if (!ok) _toast('打不开浏览器');
            },
            child: const Text('去下载'),
          ),
        ],
      ),
    );
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
        backgroundColor: kPanel,
        title: const Text('后台地址'),
        content: TextField(
          controller: ctl,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'http://192.168.1.2:8790'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('算了')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('存')),
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

  String _fmt(DateTime t) {
    final now = DateTime.now();
    final hm = '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
    if (sameDay) return hm;
    final yesterday = now.subtract(const Duration(days: 1));
    if (t.year == yesterday.year &&
        t.month == yesterday.month &&
        t.day == yesterday.day) {
      return '昨天 $hm';
    }
    return '${t.month}月${t.day}日 $hm';
  }

  Widget _timeChip(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(fontSize: 11, color: Color(0xFF5E7392)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kPanel,
        elevation: 0,
        titleSpacing: 14,
        title: Row(
          children: [
            const CircleAvatar(
              radius: 18,
              backgroundImage: AssetImage('assets/icon.png'),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  '岚岚',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '在线',
                  style: TextStyle(fontSize: 11, color: Color(0xFF7FB4FF)),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _checkUpdate,
            icon: const Icon(Icons.system_update_alt, size: 22),
            tooltip: '检查更新',
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_horiz),
            color: kPanel,
            onSelected: (v) {
              if (v == 'server') _editServer();
              if (v == 'reload') _loadHistory();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'reload', child: Text('重新拉记录')),
              PopupMenuItem(value: 'server', child: Text('后台地址')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
              itemCount: _msgs.length,
              itemBuilder: (_, i) {
                final m = _msgs[i];
                final showTime = i == 0 ||
                    m.ts.difference(_msgs[i - 1].ts).inMinutes.abs() >= 5;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (showTime) _timeChip(_fmt(m.ts)),
                    _bubble(m),
                  ],
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              decoration: const BoxDecoration(
                color: kPanel,
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
                        hintStyle: const TextStyle(color: kHint, fontSize: 14),
                        filled: true,
                        fillColor: const Color(0xFF182337),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: Material(
                      color: _busy ? const Color(0xFF23324A) : kBlue,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _busy ? null : _send,
                        child: Icon(
                          Icons.send_rounded,
                          size: 20,
                          color: _busy ? kHint : Colors.white,
                        ),
                      ),
                    ),
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
    final content = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.72,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: me ? kBubbleMe : kBubbleYou,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft: Radius.circular(me ? 16 : 4),
          bottomRight: Radius.circular(me ? 4 : 16),
        ),
      ),
      child: Text(
        m.text,
        style: TextStyle(
          fontSize: 15,
          height: 1.5,
          color: me ? Colors.white : const Color(0xFFE3EBF7),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: me ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!me) ...[
            const CircleAvatar(
              radius: 16,
              backgroundImage: AssetImage('assets/icon.png'),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(child: content),
          if (me) const SizedBox(width: 4),
        ],
      ),
    );
  }
}
