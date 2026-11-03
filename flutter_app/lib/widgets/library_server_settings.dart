import 'package:flutter/material.dart';

import '../services/library_connection.dart';

class LibraryServerSettings extends StatefulWidget {
  const LibraryServerSettings({required this.onCatalogue, super.key});
  final Future<void> Function(String) onCatalogue;
  @override
  State<LibraryServerSettings> createState() => _LibraryServerSettingsState();
}

class _LibraryServerSettingsState extends State<LibraryServerSettings> {
  final _url = TextEditingController(
    text: LibraryConnection.instance.address ?? 'http://localhost:8766',
  );
  final _token = TextEditingController();
  bool _busy = false;
  String? _message;
  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _connect({bool refresh = false}) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final yaml = refresh
          ? await LibraryConnection.instance.refresh()
          : await LibraryConnection.instance.connect(
              _url.text,
              _token.text.trim(),
            );
      await widget.onCatalogue(yaml);
      if (mounted) {
        setState(
          () => _message = 'Library connected. Audio, transcripts and indexes are read-only.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Could not connect. Check the address, read token and server availability.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Divider(),
      const Text('Central library'),
      TextField(
        controller: _url,
        decoration: const InputDecoration(labelText: 'Server address'),
        autocorrect: false,
      ),
      TextField(
        controller: _token,
        decoration: const InputDecoration(labelText: 'Read token'),
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
      ),
      Wrap(
        spacing: 8,
        children: [
          TextButton(
            onPressed: _busy ? null : _connect,
            child: const Text('Connect'),
          ),
          if (LibraryConnection.instance.address != null) ...[
            TextButton(
              onPressed: _busy ? null : () => _connect(refresh: true),
              child: const Text('Refresh library'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      await LibraryConnection.instance.disconnect();
                      if (mounted) {
                        setState(
                          () => _message = 'Disconnected. Saved catalogue remains available.',
                        );
                      }
                    },
              child: const Text('Disconnect'),
            ),
          ],
        ],
      ),
      if (_busy) const LinearProgressIndicator(),
      if (_message ?? LibraryConnection.instance.error case final message?)
        Text(message),
    ],
  );
}
