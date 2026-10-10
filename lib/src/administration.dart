import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'api.dart';

typedef AdministrationRequest = Future<Map<String, dynamic>> Function(
  String path, {
  Map<String, dynamic>? body,
});

class AdministrationPage extends StatefulWidget {
  const AdministrationPage({super.key, required this.request});
  final AdministrationRequest request;

  @override
  State<AdministrationPage> createState() => _AdministrationPageState();
}

class _AdministrationPageState extends State<AdministrationPage> {
  List<Map<String, dynamic>> _users = [];
  String? _actorId;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _message(Object error) => error is ApiException
      ? error.message
      : 'Could not reach administration. Please try again.';

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final me = await widget.request('/me');
      final user = me['user'] as Map;
      if (user['account_role'] != 'administrator') {
        throw ApiException(403, 'Administrator access is required.');
      }
      final data = await widget.request('/admin/users');
      if (!mounted) return;
      setState(() {
        _actorId = user['id'] as String;
        _users = List<Map<String, dynamic>>.from(data['users'] as List);
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _users = [];
          _error = _message(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> user) async {
    final label = user['email'] ?? user['display_name'] ?? 'User ${user['id']}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permanently delete user?'),
        content: Text(
          'Delete $label from the database and Firebase? Their household membership, linked person and related invitations will be removed. Shared recipes and cooking history will remain. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.request(
        '/admin/users/${user['id']}/delete',
        body: {'confirm': true},
      );
      if (!mounted) return;
      setState(() => _users.removeWhere((row) => row['id'] == user['id']));
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$label deleted.')));
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Administration'),
      actions: [
        IconButton(
          onPressed: _busy ? null : _load,
          tooltip: 'Refresh users',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Column(
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Users', style: TextStyle(fontSize: 24)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _users.length,
                itemBuilder: (context, index) {
                  final user = _users[index];
                  final own = user['id'] == _actorId;
                  return ListTile(
                    title: Text(
                      user['display_name'] as String? ??
                          user['email'] as String? ??
                          'User ${user['id']}',
                    ),
                    subtitle: Text(
                      '${user['email'] ?? 'No email'} · ${user['account_role']}${own ? ' (you)' : ''}',
                    ),
                    trailing: IconButton(
                      tooltip: own
                          ? 'You cannot delete your own account'
                          : 'Delete user',
                      onPressed: _busy || own ? null : () => _delete(user),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Independent browser windows restore their own Firebase session; tokens never
/// travel through URLs or browser messages.
class AuthenticatedAdministration extends StatefulWidget {
  const AuthenticatedAdministration({super.key, required this.configured});
  final bool configured;
  @override
  State<AuthenticatedAdministration> createState() =>
      _AuthenticatedAdministrationState();
}

class _AuthenticatedAdministrationState
    extends State<AuthenticatedAdministration> {
  final _api = RecipeApi(baseUrl: apiBaseUrl);
  late final _auth = widget.configured
      ? FirebaseAuth.instance.userChanges()
      : null;
  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    final token = await user?.getIdToken();
    if (token == null) throw ApiException(401, 'Please sign in again.');
    try {
      return await _api.request(
        path,
        token,
        body: body,
        timeout: const Duration(seconds: 60),
      );
    } on ApiException catch (error) {
      if (error.status != 401) rethrow;
      final refreshed = await user!.getIdToken(true);
      if (refreshed == null) rethrow;
      return _api.request(
        path,
        refreshed,
        body: body,
        timeout: const Duration(seconds: 60),
      );
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: _auth,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }
      if (snapshot.data == null) {
        return Scaffold(
          appBar: AppBar(title: const Text('Administration')),
          body: const Center(
            child: Text('Sign in to Coffey Table, then reopen Administration.'),
          ),
        );
      }
      return AdministrationPage(
        key: ValueKey(snapshot.data!.uid),
        request: _request,
      );
    },
  );
}
