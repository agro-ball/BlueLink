import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Store.load();
  runApp(const BlueLinkApp());
}

const kBlue = Color(0xFF0057FF);

// ---------------------------------------------------------------- модели

class Item {
  final String name;
  final String path;
  final int size;
  Item(this.name, this.path, this.size);
}

class Rec {
  final String name;
  final bool sent;
  final int time;
  final String? path;
  Rec(this.name, this.sent, this.time, this.path);

  Map<String, dynamic> toJson() =>
      {'name': name, 'sent': sent, 'time': time, 'path': path};

  factory Rec.fromJson(Map<String, dynamic> j) =>
      Rec(j['name'], j['sent'], j['time'], j['path']);
}

class Store {
  static List<Rec> items = [];

  static Future<File> _file() async {
    final d = await getApplicationDocumentsDirectory();
    return File('${d.path}/history.json');
  }

  static Future<void> load() async {
    try {
      final f = await _file();
      if (await f.exists()) {
        final l = jsonDecode(await f.readAsString()) as List;
        items = l.map((e) => Rec.fromJson(Map<String, dynamic>.from(e))).toList();
      }
    } catch (_) {}
  }

  static Future<void> save() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode(items.map((e) => e.toJson()).toList()));
    } catch (_) {}
  }

  static Future<void> add(Rec r) async {
    items.insert(0, r);
    await save();
  }

  static Future<void> remove(Rec r) async {
    items.remove(r);
    await save();
  }

  static Future<Directory> inbox() async {
    Directory? d;
    if (Platform.isAndroid) d = await getExternalStorageDirectory();
    d ??= await getApplicationDocumentsDirectory();
    final x = Directory('${d.path}/BlueLink');
    await x.create(recursive: true);
    return x;
  }
}

String fmtSize(int b) {
  if (b < 1024) return '$b Б';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} КБ';
  if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} МБ';
  return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} ГБ';
}

String fmtTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String t(int n) => n.toString().padLeft(2, '0');
  return '${t(d.day)}.${t(d.month)} ${t(d.hour)}:${t(d.minute)}';
}

Future<String> localIp() async {
  final ifs = await NetworkInterface.list(type: InternetAddressType.IPv4);
  String? any;
  for (final i in ifs) {
    for (final a in i.addresses) {
      if (a.isLoopback) continue;
      final n = i.name.toLowerCase();
      if (n.contains('wlan') || n.startsWith('ap') || n.startsWith('en') || n.contains('wi')) {
        return a.address;
      }
      any ??= a.address;
    }
  }
  return any ?? '0.0.0.0';
}

// ---------------------------------------------------------------- приложение

class BlueLinkApp extends StatelessWidget {
  const BlueLinkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BlueLink',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: kBlue),
        scaffoldBackgroundColor: const Color(0xFFF3F7FF),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Future<void> _go(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() {});
  }

  Widget _btn(String asset, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: SizedBox(
          height: 84,
          child: Image.asset(asset, fit: BoxFit.contain),
        ),
      );

  Future<void> _openFiles() async {
    final r = await FilePicker.platform.pickFiles();
    if (r != null && r.files.single.path != null) {
      await OpenFilex.open(r.files.single.path!);
    }
  }

  Future<void> _menu(Rec r, Offset pos) async {
    final v = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: const [PopupMenuItem(value: 'del', child: Text('Удалить'))],
    );
    if (v == 'del') {
      await Store.remove(r);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = Store.items;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset('assets/icon.png', width: 32, height: 32),
                  ),
                  const SizedBox(width: 8),
                  const Text('BlueLink',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: kBlue)),
                ],
              ),
            ),
            const SizedBox(height: 4),
            _btn('assets/send.png', () => _go(const SendPage())),
            _btn('assets/receive.png', () => _go(const ReceivePage())),
            _btn('assets/files.png', _openFiles),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('История', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Пока пусто', style: TextStyle(color: Colors.black45)))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final r = list[i];
                        return GestureDetector(
                          onLongPressStart: (d) => _menu(r, d.globalPosition),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: kBlue.withOpacity(0.12),
                              child: Icon(r.sent ? Icons.arrow_upward : Icons.arrow_downward, color: kBlue),
                            ),
                            title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${r.sent ? 'Отправлено' : 'Получено'} • ${fmtTime(r.time)}'),
                            onTap: r.path != null ? () => OpenFilex.open(r.path!) : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- отправка

class SendPage extends StatefulWidget {
  const SendPage({super.key});
  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  final List<Item> items = [];
  final Set<int> done = {};
  HttpServer? server;
  String? url;

  @override
  void dispose() {
    server?.close(force: true);
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final r = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (r == null) return;
    for (final f in r.files) {
      if (f.path != null) items.add(Item(f.name, f.path!, f.size));
    }
    setState(() {});
  }

  Future<void> _pickApps() async {
    final res = await Navigator.push<List<Item>>(
        context, MaterialPageRoute(builder: (_) => const AppsPage()));
    if (res != null) setState(() => items.addAll(res));
  }

  Future<void> _start() async {
    final ip = await localIp();
    final s = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    server = s;
    s.listen(_handle);
    setState(() => url = 'http://$ip:${s.port}');
  }

  Future<void> _stop() async {
    await server?.close(force: true);
    server = null;
    done.clear();
    setState(() => url = null);
  }

  Future<void> _handle(HttpRequest r) async {
    try {
      final p = r.uri.path;
      if (p == '/list') {
        r.response.headers.contentType = ContentType.json;
        r.response.write(jsonEncode([
          for (var i = 0; i < items.length; i++)
            {'i': i, 'name': items[i].name, 'size': items[i].size}
        ]));
      } else if (p.startsWith('/f/')) {
        final i = int.parse(p.substring(3));
        final it = items[i];
        r.response.headers.contentType = ContentType.binary;
        r.response.headers.set('content-disposition',
            "attachment; filename*=UTF-8''${Uri.encodeComponent(it.name)}");
        r.response.contentLength = it.size;
        await r.response.addStream(File(it.path).openRead());
        if (done.add(i)) {
          await Store.add(Rec(it.name, true, DateTime.now().millisecondsSinceEpoch, null));
          if (mounted) setState(() {});
        }
      } else {
        // страница для тех, у кого нет приложения (браузер)
        r.response.headers.contentType = ContentType.html;
        final sb = StringBuffer(
            '<html><head><meta name="viewport" content="width=device-width,initial-scale=1"></head>'
            '<body style="font-family:sans-serif;padding:16px"><h2 style="color:#0057FF">BlueLink</h2>');
        for (var i = 0; i < items.length; i++) {
          sb.write(
              '<p><a href="/f/$i" style="font-size:18px">${const HtmlEscape().convert(items[i].name)}</a> '
              '(${fmtSize(items[i].size)})</p>');
        }
        sb.write('</body></html>');
        r.response.write(sb.toString());
      }
    } catch (_) {}
    try {
      await r.response.close();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final started = url != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Отправить')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            if (!started) ...[
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _pickFiles,
                      icon: const Icon(Icons.insert_drive_file),
                      label: const Text('Файлы'),
                    ),
                  ),
                  if (Platform.isAndroid) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _pickApps,
                        icon: const Icon(Icons.android),
                        label: const Text('Приложения'),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
            ] else ...[
              Container(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: QrImageView(data: url!, size: 220),
              ),
              const SizedBox(height: 8),
              SelectableText(url!, style: const TextStyle(fontWeight: FontWeight.w600)),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'Оба телефона в одной Wi-Fi сети (или раздай точку доступа). '
                  'Получатель сканирует QR в BlueLink или обычной камерой.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            ],
            Expanded(
              child: items.isEmpty
                  ? const Center(child: Text('Выбери что отправить'))
                  : ListView.builder(
                      itemCount: items.length,
                      itemBuilder: (_, i) => ListTile(
                        dense: true,
                        leading: Icon(done.contains(i) ? Icons.check_circle : Icons.insert_drive_file,
                            color: done.contains(i) ? Colors.green : kBlue),
                        title: Text(items[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(fmtSize(items[i].size)),
                        trailing: started
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close),
                                onPressed: () => setState(() => items.removeAt(i)),
                              ),
                      ),
                    ),
            ),
            SizedBox(
              width: double.infinity,
              child: started
                  ? OutlinedButton(onPressed: _stop, child: const Text('Остановить'))
                  : FilledButton(
                      onPressed: items.isEmpty ? null : _start,
                      child: const Text('Начать отправку'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- выбор приложений (Android)

class AppsPage extends StatefulWidget {
  const AppsPage({super.key});
  @override
  State<AppsPage> createState() => _AppsPageState();
}

class _AppsPageState extends State<AppsPage> {
  static const ch = MethodChannel('bluelink/apps');
  List<Map<String, dynamic>> apps = [];
  final Set<int> sel = {};
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await ch.invokeMethod<List<dynamic>>('getApps');
      apps = (r ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (_) {}
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Приложения'),
        actions: [
          TextButton(
            onPressed: sel.isEmpty
                ? null
                : () {
                    final out = <Item>[];
                    for (final i in sel) {
                      final a = apps[i];
                      final f = File(a['path']);
                      out.add(Item('${a['name']}.apk', a['path'], f.lengthSync()));
                    }
                    Navigator.pop(context, out);
                  },
            child: Text('Готово (${sel.length})'),
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: apps.length,
              itemBuilder: (_, i) => CheckboxListTile(
                value: sel.contains(i),
                title: Text(apps[i]['name']),
                subtitle: Text(apps[i]['pkg'], style: const TextStyle(fontSize: 11)),
                onChanged: (v) => setState(() => v == true ? sel.add(i) : sel.remove(i)),
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------- получение

class ReceivePage extends StatefulWidget {
  const ReceivePage({super.key});
  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> {
  bool busy = false;
  String status = 'Наведи камеру на QR отправителя';
  double? progress;

  Future<void> _download(String base) async {
    if (busy) return;
    busy = true;
    base = base.trim().replaceAll(RegExp(r'/+$'), '');
    if (!base.startsWith('http')) base = 'http://$base';
    setState(() {
      status = 'Подключение...';
      progress = null;
    });
    final c = HttpClient();
    try {
      final res = await (await c.getUrl(Uri.parse('$base/list'))).close();
      final list = jsonDecode(await res.transform(utf8.decoder).join()) as List;
      final dir = await Store.inbox();
      for (var n = 0; n < list.length; n++) {
        final e = list[n];
        var name = (e['name'] as String).replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
        var out = File('${dir.path}/$name');
        if (await out.exists()) {
          out = File('${dir.path}/${DateTime.now().millisecondsSinceEpoch}_$name');
        }
        final total = (e['size'] as num).toInt();
        final rs = await (await c.getUrl(Uri.parse('$base/f/${e['i']}'))).close();
        final sink = out.openWrite();
        var got = 0;
        await for (final chunk in rs) {
          sink.add(chunk);
          got += chunk.length;
          if (mounted) {
            setState(() {
              status = 'Файл ${n + 1} из ${list.length}: $name';
              progress = total > 0 ? got / total : null;
            });
          }
        }
        await sink.close();
        await Store.add(Rec(name, false, DateTime.now().millisecondsSinceEpoch, out.path));
      }
      if (mounted) {
        setState(() {
          status = 'Готово! Получено файлов: ${list.length}';
          progress = 1;
        });
      }
    } catch (e) {
      if (mounted) setState(() => status = 'Ошибка подключения. Проверь, что оба в одной сети.');
    } finally {
      c.close(force: true);
      busy = false;
    }
  }

  Future<void> _manual() async {
    final ctrl = TextEditingController();
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Адрес отправителя'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: '192.168.1.5:40000')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, ctrl.text), child: const Text('OK')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) _download(v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Получить')),
      body: Column(
        children: [
          Expanded(
            child: MobileScanner(
              onDetect: (cap) {
                if (busy) return;
                final v = cap.barcodes.isNotEmpty ? cap.barcodes.first.rawValue : null;
                if (v != null && v.startsWith('http')) _download(v);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(status, textAlign: TextAlign.center),
                if (progress != null || busy) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: progress),
                ],
                TextButton(onPressed: _manual, child: const Text('Ввести адрес вручную')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
