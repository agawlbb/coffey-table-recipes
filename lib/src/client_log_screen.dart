import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'client_log.dart';

class ClientLogScreen extends StatefulWidget {
  const ClientLogScreen({super.key, this.log});
  final ClientLog? log;

  @override
  State<ClientLogScreen> createState() => _ClientLogScreenState();
}

class _ClientLogScreenState extends State<ClientLogScreen> {
  late final log = widget.log ?? clientLog;
  @override
  void initState() {
    super.initState();
    log.start();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: log,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: const Text('Error log'),
        actions: [
          IconButton(
            tooltip: 'Clear log',
            icon: const Icon(Icons.delete_outline),
            onPressed: log.clear,
          ),
          IconButton(
            tooltip: 'Copy to clipboard',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () async {
              await log.start();
              await Clipboard.setData(ClipboardData(text: log.text));
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: SelectableText(
          log.text,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        ),
      ),
    ),
  );
}
