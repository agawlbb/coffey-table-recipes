import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'parent_categories.dart';

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
  List<Map<String, dynamic>> _people = [];
  List<Map<String, dynamic>> _households = [];
  bool _deletedSelf = false;
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
        _households = List<Map<String, dynamic>>.from(
          data['households'] as List? ?? [],
        );
        _people = List<Map<String, dynamic>>.from(
          data['people'] as List? ?? [],
        );
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _users = [];
          _people = [];
          _households = [];
          _error = _message(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> user, {bool person = false}) async {
    final label = user['email'] ?? user['display_name'] ?? 'User ${user['id']}';
    final own = !person && user['id'] == _actorId;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          person ? 'Permanently delete person?' : 'Permanently delete user?',
        ),
        content: Text(
          person
              ? 'Remove $label from ${user['household_name']}? Their table entry, favorites and invitations will be permanently deleted. They have no linked login account. Shared recipes and cooking history will remain. This cannot be undone.'
              : 'Delete $label from the database and Firebase? Their household memberships, table entries, favorites and related invitations will be removed. Shared recipes and cooking history will remain. This cannot be undone.${own ? ' This is your own administrator account. You will lose access to administration.' : ''}',
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
        '/admin/${person
            ? 'people'
            : user['firebase_only'] == true
            ? 'firebase'
            : 'users'}/${user['firebase_only'] == true ? Uri.encodeComponent(user['firebase_uid'] as String) : user['id']}/delete',
        body: {'confirm': true},
      );
      if (!mounted) return;
      setState(() {
        (person ? _people : _users).removeWhere(
          (row) => row['id'] == user['id'],
        );
        if (own) {
          _deletedSelf = true;
          _users = [];
          _people = [];
        }
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$label deleted.')));
      if (!own) await _load();
    } catch (error) {
      if (mounted) setState(() => _error = _message(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setAiImages(
    Map<String, dynamic> household,
    bool enabled,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.request(
        '/admin/households/${household['id']}/ai-images',
        body: {'enabled': enabled},
      );
      if (!mounted) return;
      final updated = result['household'] as Map;
      setState(
        () => household['ai_images_enabled'] =
            updated['ai_images_enabled'] == true,
      );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'AI images ${enabled ? 'enabled' : 'disabled'} for ${household['name']}.',
          ),
        ),
      );
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
          onPressed: _busy || _deletedSelf ? null : _load,
          tooltip: 'Refresh administration',
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
            if (_deletedSelf)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Your account has been permanently deleted. Close this window.',
                ),
              ),
            Expanded(
              child: ListView(
                children: [
                  if (!_deletedSelf) ...[
                    ListTile(
                      leading: const Icon(Icons.category_outlined),
                      title: const Text('Manage parent categories'),
                      subtitle: const Text('Shared across all households'),
                      trailing: const Icon(Icons.chevron_right),
                      enabled: !_busy && _actorId != null && _error == null,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ParentCategories(request: widget.request),
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Registered households',
                        style: TextStyle(fontSize: 24),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'AI images start disabled. Enabling a household allows all its members to generate recipe and category images.',
                      ),
                    ),
                    if (_households.isEmpty && !_busy && _error == null)
                      const ListTile(title: Text('No registered households.')),
                    for (final household in _households)
                      SwitchListTile(
                        title: Text(household['name'] as String),
                        subtitle: Text(
                          '${household['member_count']} members · Allow AI image generation',
                        ),
                        value: household['ai_images_enabled'] == true,
                        onChanged: _busy
                            ? null
                            : (enabled) => _setAiImages(household, enabled),
                      ),
                  ],
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Users & table people',
                      style: TextStyle(fontSize: 24),
                    ),
                  ),
                  ...List.generate(_users.length + _people.length, (index) {
                    final person = index >= _users.length;
                    final user = person
                        ? _people[index - _users.length]
                        : _users[index];
                    final own = !person && user['id'] == _actorId;
                    return ListTile(
                      title: Text(
                        user['display_name'] as String? ??
                            user['email'] as String? ??
                            'User ${user['id']}',
                      ),
                      subtitle: Text(
                        person
                            ? '${user['household_name']} · No linked account'
                            : '${user['email'] ?? 'No email'} · ${user['email_verified'] == true ? 'Verified' : 'Unverified'} · ${user['account_role']}${own ? ' (you)' : ''}',
                      ),
                      trailing: IconButton(
                        tooltip: person ? 'Delete person' : 'Delete user',
                        onPressed: _busy || _deletedSelf
                            ? null
                            : () => _delete(user, person: person),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    );
                  }),
                ],
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
