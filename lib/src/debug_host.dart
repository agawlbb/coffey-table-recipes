// Temporary debug tool. Remove this file and its hooks in api.dart, app.dart,
// and main.dart, then remove shared_preferences when testing no longer needs it.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const debugHostEnabled = kDebugMode && !kIsWeb;
const _preferenceKey = 'debug_api_base_url';
final debugApiOverride = ValueNotifier<String?>(null);

String? normalizeDebugApiUrl(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment) {
    return null;
  }
  return uri.toString().replaceFirst(RegExp(r'/+$'), '');
}

Future<void> loadDebugApiOverride() async {
  if (!debugHostEnabled) return;
  try {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_preferenceKey);
    debugApiOverride.value = saved == null ? null : normalizeDebugApiUrl(saved);
  } catch (_) {
    // Preference failures must not prevent the app from starting.
  }
}

class DebugHostPanel extends StatefulWidget {
  const DebugHostPanel({super.key, required this.currentUrl});
  final String currentUrl;

  @override
  State<DebugHostPanel> createState() => _DebugHostPanelState();
}

class _DebugHostPanelState extends State<DebugHostPanel> {
  late final _address = TextEditingController(text: widget.currentUrl);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final url = normalizeDebugApiUrl(_address.text);
    if (url == null) {
      setState(() => _error = 'Enter a full http:// or https:// API URL.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.setString(_preferenceKey, url)) {
        throw StateError('Could not save address');
      }
      if (!mounted) return;
      debugApiOverride.value = url;
      if (mounted) setState(() => _address.text = url);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not save the address. Try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: ExpansionTile(
      title: const Text('Debug: server address'),
      childrenPadding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _address,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          decoration: InputDecoration(
            labelText: 'API base URL',
            helperText: 'http://<laptop-IP>/CoffeyTableRecipes/api/v1',
            helperMaxLines: 2,
            errorText: _error,
            errorMaxLines: 2,
          ),
        ),
        const SizedBox(height: 12),
        const Text('Saved on this device. Applying reloads the home screen.'),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _saving ? null : _apply,
          child: Text(_saving ? 'Saving…' : 'Save and apply'),
        ),
      ],
    ),
  );
}
