import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'auth.dart';
import 'email_access.dart';
import 'recipe_browser.dart';

class AccountPanel extends StatefulWidget {
  const AccountPanel({
    super.key,
    required this.configured,
    this.initializationError,
  });
  final bool configured;
  final String? initializationError;
  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> {
  bool _busy = false;
  String? _error;
  late final Stream<User?>? _authChanges = widget.configured
      ? FirebaseAuth.instance.userChanges()
      : null;

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await GoogleAuthentication.signIn();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = GoogleAuthentication.message(error);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.configured) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome to your table',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                widget.initializationError ?? 'Google sign-in setup is in progress. Your household will be ready here once it is connected.',
              ),
            ],
          ),
        ),
      );
    }
    return StreamBuilder<User?>(
      stream: _authChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final user = snapshot.data;
        if (user != null) {
          return HouseholdPanel(key: ValueKey(user.uid), user: user);
        }
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome to your table',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Sign in to bring your household’s recipes and dinner plans together.',
                ),
                const SizedBox(height: 20),
                const EmailAccess(),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _signIn,
                  icon: const Icon(Icons.login),
                  label: Text(_busy ? 'Signing in…' : 'Continue with Google'),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class HouseholdPanel extends StatefulWidget {
  const HouseholdPanel({super.key, required this.user});
  final User user;
  @override
  State<HouseholdPanel> createState() => _HouseholdPanelState();
}

class _HouseholdPanelState extends State<HouseholdPanel> {
  final _api = RecipeApi(baseUrl: apiBaseUrl);
  final _householdName = TextEditingController();
  final _personName = TextEditingController();
  final _newPerson = TextEditingController();
  List<Map<String, dynamic>> _households = [];
  List<Map<String, dynamic>> _people = [];
  String? _selected;
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _personName.text = widget.user.displayName ?? '';
    _load();
  }

  @override
  void dispose() {
    _api.close();
    _householdName.dispose();
    _personName.dispose();
    _newPerson.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final token = await widget.user.getIdToken();
    if (token == null) throw ApiException(401, 'Please sign in again.');
    try {
      return await _api.request(path, token, body: body);
    } on ApiException catch (error) {
      if (error.status != 401) rethrow;
      final refreshed = await widget.user.getIdToken(true);
      if (refreshed == null) rethrow;
      return _api.request(path, refreshed, body: body);
    }
  }

  Future<void> _perform(Future<void> Function() action) async {
    if (!mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is ApiException ? error.message : 'Could not reach your household. Check your connection and try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _load() => _perform(() async {
    final data = await _request('/me');
    final households = List<Map<String, dynamic>>.from(
      data['households'] as List,
    );
    if (!mounted) return;
    _households = households;
    if (!_households.any((h) => h['id'] == _selected)) {
      _selected = households.isEmpty ? null : households.first['id'] as String;
    }
    await _loadPeople();
  });

  Future<void> _loadPeople() async {
    if (_selected == null) {
      _people = [];
      return;
    }
    final data = await _request('/households/$_selected/people');
    if (mounted) {
      _people = List<Map<String, dynamic>>.from(data['people'] as List);
    }
  }

  Future<void> _create() async {
    if (_householdName.text.trim().isEmpty || _personName.text.trim().isEmpty) {
      setState(() {
        _error = 'Enter a household name and your name.';
      });
      return;
    }
    await _perform(() async {
      final data = await _request(
        '/households',
        body: {
          'name': _householdName.text.trim(),
          'person_name': _personName.text.trim(),
        },
      );
      if (!mounted) return;
      final household = Map<String, dynamic>.from(data['household'] as Map);
      _households.add(household);
      _selected = household['id'] as String;
      await _loadPeople();
    });
  }

  @override
  Widget build(BuildContext context) {
    final selected = _households.where((h) => h['id'] == _selected).firstOrNull;
    final canAdd =
        selected != null && ['owner', 'admin'].contains(selected['role']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  widget.user.displayName ?? 'Your account',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          try {
                            await GoogleAuthentication.signOut();
                          } catch (_) {
                            if (mounted) {
                              setState(() {
                                _error = 'Sign-out could not finish. Please try again.';
                              });
                            }
                          }
                        },
                  child: const Text('Sign out'),
                ),
              ],
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: LinearProgressIndicator(),
              ),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: _busy ? null : _load,
                child: const Text('Retry'),
              ),
            ],
            if (!_busy && _households.isEmpty && _error == null) ...[
              const SizedBox(height: 12),
              const Text(
                'Give your household a name. You can add people who do not have login accounts.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _householdName,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Household name',
                  hintText: 'The Coffey table',
                ),
              ),
              TextField(
                controller: _personName,
                maxLength: 200,
                decoration: const InputDecoration(
                  labelText: 'Your name at the table',
                ),
              ),
              FilledButton(
                onPressed: _create,
                child: const Text('Create household'),
              ),
            ],
            if (_households.isNotEmpty) ...[
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey(_selected),
                initialValue: _selected,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Your household'),
                items: _households
                    .map(
                      (h) => DropdownMenuItem(
                        value: h['id'] as String,
                        child: Text(h['name'] as String),
                      ),
                    )
                    .toList(),
                onChanged: _busy
                    ? null
                    : (id) => _perform(() async {
                        _selected = id;
                        _people = [];
                        await _loadPeople();
                      }),
              ),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xffeee8d9),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.menu_book_outlined, size: 32),
                    const SizedBox(height: 12),
                    Text(
                      'Your recipe collection',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Find a favorite. Bring something good to the table.',
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _busy || _selected == null
                          ? null
                          : () {
                              final household = _households.firstWhere(
                                (h) => h['id'] == _selected,
                              );
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => RecipeBrowser(
                                    householdId: _selected!,
                                    householdName: household['name'] as String,
                                    request: (path) => _request(path),
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.menu_book_outlined),
                      label: const Text('Browse recipes'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                leading: const Icon(Icons.people_outline),
                title: const Text('People at your table'),
                subtitle: Text('${_people.length} household members'),
                children: [
                  for (final person in _people)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.person_outline),
                      title: Text(person['display_name'] as String),
                      subtitle: Text(
                        person['user_id'] == null
                            ? 'Household person'
                            : 'Linked login account',
                      ),
                    ),
                  if (canAdd) ...[
                    TextField(
                      controller: _newPerson,
                      // Chrome's native I-beam can disappear over this light field.
                      mouseCursor: kIsWeb
                          ? SystemMouseCursors.basic
                          : SystemMouseCursors.text,
                      maxLength: 200,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Add a person',
                      ),
                    ),
                    OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () {
                              if (_newPerson.text.trim().isEmpty) return;
                              _perform(() async {
                                await _request(
                                  '/households/$_selected/people',
                                  body: {
                                    'display_name': _newPerson.text.trim(),
                                  },
                                );
                                if (!mounted) return;
                                _newPerson.clear();
                                await _loadPeople();
                              });
                            },
                      child: const Text('Add person'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
