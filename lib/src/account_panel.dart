import 'account_menu.dart';

import 'dart:async';
import 'dart:convert';

import 'offline_store.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'native_timers.dart';
import 'app_version_label.dart';
import 'administration.dart';
import 'administration_window.dart';
import 'auth.dart';
import 'email_access.dart';
import 'email_verification_screen.dart';
import 'invitation_dialogs.dart';
import 'invitation_entry.dart';
import 'recipe_browser.dart';
import 'recipe_trash.dart';
import 'shopping_list.dart';
import 'shopping_list_cache.dart';
import 'local_data.dart';
import 'shopping_departments.dart';
import 'recipe_import.dart';
import 'shared_recipe_import.dart';
import 'offline_recipes.dart';

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
  late final InvitationEntry _entry = InvitationEntry(Uri.base);
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
      return Scaffold(
        appBar: AppBar(title: const Text('Coffey Table')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              widget.initializationError ??
                  'Sign-in is not configured for this build.',
            ),
          ),
        ),
      );
    }

    return StreamBuilder<User?>(
      stream: _authChanges,
      initialData: FirebaseAuth.instance.currentUser,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            snapshot.data == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final user = snapshot.data;
        if (user != null) {
          if (!user.emailVerified) {
            return EmailVerificationScreen(
              key: ValueKey('verify-${user.uid}'),
              user: user,
              refresh: () async {
                await user.reload();
                final current = FirebaseAuth.instance.currentUser;
                if (current?.emailVerified == true) {
                  await current!.getIdToken(true);
                }
              },
              registerAccount: () async {
                final api = RecipeApi(baseUrl: apiBaseUrl);
                try {
                  final token = await user.getIdToken(true);
                  await api.request('/me', token!);
                } finally {
                  api.close();
                }
              },
              signOut: FirebaseAuth.instance.signOut,
            );
          }
          return HouseholdPanel(key: ValueKey(user.uid), user: user);
        }
        final loginForm = Card(
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
                const SizedBox(height: 20),
                EmailAccess(
                  initialEmail: _entry.email,
                  register: _entry.register,
                ),
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
        return Scaffold(
          appBar: AppBar(title: const Text('Coffey Table')),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: loginForm,
              ),
            ),
          ),
        );
      },
    );
  }
}

class HouseholdPanel extends StatefulWidget {
  const HouseholdPanel({
    super.key,
    required this.user,
    this.request,
    this.signOut,
    this.cachedRequest,
  });
  final Future<void> Function()? signOut;
  final Future<Map<String, dynamic>> Function(
    String path, {
    Map<String, dynamic>? body,
  })?
  request;
  final User user;
  final Future<Map<String, dynamic>?> Function(String path)? cachedRequest;
  @override
  State<HouseholdPanel> createState() => _HouseholdPanelState();
}

class _HouseholdPanelState extends State<HouseholdPanel> {
  final _api = RecipeApi(baseUrl: apiBaseUrl);
  OfflineRecipes? _offline;
  LocalData? _local;
  void _localChanged() {
    if (mounted && localDataChanges.value.startsWith('/me#')) {
      unawaited(_load(reviewInvitations: false));
    }
  }

  Future<Map<String, dynamic>?> _cachedRead(String path) =>
      widget.cachedRequest?.call(path) ??
      _local?.cachedView(path) ??
      _offline?.cachedRead(path) ??
      Future.value(null);
  final _householdName = TextEditingController();
  final _personName = TextEditingController();
  List<Map<String, dynamic>> _households = [];
  List<Map<String, dynamic>> _people = [];
  String? _selected;
  String? _error;
  bool _settings = false;
  bool _shopping = false;
  bool _shoppingOpened = false;
  int _shoppingRefresh = 0;
  int _recipeRefresh = 0;
  bool _busy = true;
  List<Map<String, dynamic>> _invitations = [];
  bool _invitationVerificationRequired = false;
  bool _reviewingInvitations = false;
  String? _displayName;
  bool _accountBusy = false;
  String? _userId;
  bool _administrator = false;

  void _openAdministration() {
    if (openAdministrationWindow()) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AdministrationPage(request: _request),
      ),
    );
  }

  Map<String, dynamic>? get _ownPerson => _userId == null
      ? null
      : _people.where((person) => person['user_id'] == _userId).firstOrNull;

  Future<void> _changeTableName() async {
    final person = _ownPerson;
    final householdId = _selected;
    if (person == null || householdId == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: 'Change name at the table',
        label: 'Your name at the table',
        initialName: person['display_name'] as String,
      ),
    );
    if (!mounted || name == null) return;
    setState(() => _accountBusy = true);
    try {
      final data = await _request(
        '/households/$householdId/people/me/name',
        body: {'display_name': name},
      );
      if (!mounted) return;
      setState(
        () => person['display_name'] = (data['person'] as Map)['display_name'],
      );
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Your name at the table updated.')),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ApiException ? error.message : 'Could not update your name at the table. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _accountBusy = false);
    }
  }

  Future<void> _changeDisplayName() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: 'Change account display name',
        label: 'Account display name',
        initialName: _displayName ?? widget.user.displayName ?? '',
      ),
    );
    if (!mounted || name == null) return;
    setState(() => _accountBusy = true);
    try {
      await widget.user.updateDisplayName(name);
      if (!mounted) return;
      setState(() => _displayName = name);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Display name updated.')));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not update your display name. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _accountBusy = false);
    }
  }

  Future<void> _logOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You’ll need to sign in again to access your household’s recipes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _accountBusy = true);
    try {
      await (widget.signOut ?? GoogleAuthentication.signOut)();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Log-out could not finish. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _accountBusy = false);
    }
  }

  bool _sharedImportOpen = false;
  @override
  void initState() {
    super.initState();
    sharedRecipeInbox.addListener(_sharedRecipeChanged);
    _personName.text = widget.user.displayName ?? '';
    if (widget.request == null) {
      _offline =
          OfflineRecipes(
            key: '$apiBaseUrl|${widget.user.uid}',
            fetch: (path) async {
              if (path == '/me') {
                if (kIsWeb && Uri.base.queryParameters['account'] == 'signin') {
                  await widget.user.reload().timeout(
                    const Duration(seconds: 8),
                  );
                }
                await _idToken(true);
              }
              return _onlineRequest(path);
            },
            downloadLibrary: true,
          )..start(() {
            if (mounted) unawaited(_load(reviewInvitations: false));
          });
    }
    if (widget.request == null) {
      _local = LocalData(
        key: '$apiBaseUrl|${widget.user.uid}',
        fetch: (path) => _offline!.request(path),
        readServer: (path) => _onlineRequest(path),
        send: (path, body) => _onlineRequest(path, body: body),
        fallback: (path) => _offline!.cachedRead(path),
        online: () => !offlineStatus.value,
        onRecipeSaved: (path, data) =>
            _offline!.rememberSavedRecipe(path, data),
      )..start();
      localDataChanges.addListener(_localChanged);
    }
    _load();
  }

  @override
  void dispose() {
    sharedRecipeInbox.removeListener(_sharedRecipeChanged);
    localDataChanges.removeListener(_localChanged);
    _local?.dispose();
    _offline?.close();
    _api.close();
    _householdName.dispose();
    _personName.dispose();
    super.dispose();
  }

  void _sharedRecipeChanged() {
    if (!mounted ||
        _selected == null ||
        _busy ||
        _sharedImportOpen ||
        sharedRecipeInbox.value.isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openSharedRecipe();
    });
  }

  Future<void> _openSharedRecipe() async {
    if (!mounted || _sharedImportOpen || _selected == null || _busy) return;
    _sharedImportOpen = true;
    final input = sharedRecipeInbox.take();
    if (input == null) {
      _sharedImportOpen = false;
      return;
    }
    if (input.error != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(input.error!)));
      _sharedImportOpen = false;
      _sharedRecipeChanged();
      return;
    }
    final householdId = _selected!;
    try {
      final saved = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (_) => RecipeImport(
            householdId: householdId,
            sharedInput: input,
            request: (path, body) async {
              final data = await _request(path, body: body);
              if (data['recipe'] is Map &&
                  (data['recipe'] as Map)['id'] != null) {
                await _offline?.rememberSavedRecipe(
                  '/households/$householdId/recipes/${(data['recipe'] as Map)['id']}',
                  data,
                );
              }
              return data;
            },
          ),
        ),
      );
      if (saved != null && mounted) {
        setState(() {
          _settings = false;
          _shopping = false;
          _recipeRefresh++;
        });
      }
    } finally {
      _sharedImportOpen = false;
      _sharedRecipeChanged();
    }
  }

  Future<Map<String, dynamic>> _saveRecipe(
    String path,
    Map<String, dynamic> body,
  ) async {
    final data = await _request(path, body: body);
    // Generation returns an unsaved draft, not a replacement for its parent.
    if (path.endsWith('/variation')) return data;
    await _offline?.rememberSavedRecipe(path, data);
    if (_offline != null) {
      unawaited(
        _syncLibrary(_households.map((h) => h['id'] as String).toList()),
      );
    }
    return data;
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (widget.request != null) return widget.request!(path, body: body);
    if (_local != null) {
      if (path.endsWith('/recipe-blank')) return _local!.blank(path);
      if (body == null) return _local!.request(path);
      if (_local!.canSave(path)) return _local!.save(path, body);
    }
    return _onlineRequest(path, body: body);
  }

  Future<Map<String, dynamic>> _onlineRequest(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (body == null && isPublicRecipeRead(path)) {
      return _api.request(path, '', timeout: const Duration(seconds: 8));
    }
    final token = await _idToken();
    if (token == null) throw ApiException(401, 'Please sign in again.');
    try {
      return await _api.request(
        path,
        token,
        body: body,
        timeout: Duration(
          seconds:
              (path.endsWith('/recipe-photo') ||
                  path.endsWith('/category-image') ||
                  (path == '/admin/parent-categories' &&
                      body?['action'] == 'add'))
              ? 180
              : (path.endsWith('/recipe-import') || path.endsWith('/variation'))
              ? (body?['method_selection'] == 'both' ? 190 : 110)
              : path.startsWith('/admin/')
              ? 60
              : _offline != null && body == null
              ? 8
              : 20,
        ),
      );
    } on ApiException catch (error) {
      if (error.status != 401) rethrow;
      final refreshed = await _idToken(true);
      if (refreshed == null) rethrow;
      return _api.request(
        path,
        refreshed,
        body: body,
        timeout: Duration(
          seconds:
              (path.endsWith('/recipe-photo') ||
                  path.endsWith('/category-image') ||
                  (path == '/admin/parent-categories' &&
                      body?['action'] == 'add'))
              ? 180
              : (path.endsWith('/recipe-import') || path.endsWith('/variation'))
              ? (body?['method_selection'] == 'both' ? 190 : 110)
              : path.startsWith('/admin/')
              ? 60
              : 20,
        ),
      );
    }
  }

  Future<String?> _idToken([bool refresh = false]) {
    final token = widget.user.getIdToken(refresh);
    return token.timeout(const Duration(seconds: 8));
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
        _sharedRecipeChanged();
      }
    }
  }

  Future<void>? _librarySync;
  Future<void> _syncLibrary(List<String> households) =>
      _librarySync ??= () async {
        try {
          await _offline!.sync(households);
          if (!mounted || _local == null) return;
          for (final household in households) {
            _local!.inventoryUpdated(household);
            await _local!.blank(
              '/households/$household/recipe-blank',
              refresh: true,
            );
            final root = '/households/$household/recipes';
            int? offset = 0;
            do {
              final page = await _offline!.cachedRead('$root?offset=$offset');
              if (page == null || !mounted) return;
              final rows = recipeRows(page['recipes']);
              for (var start = 0; start < rows.length; start += 3) {
                if (!mounted) return;
                await Future.wait(
                  rows
                      .skip(start)
                      .take(3)
                      .map(
                        (row) => _local!
                            .request('$root/${row['id']}/favorites')
                            .catchError((Object _) => <String, dynamic>{}),
                      ),
                );
              }
              offset = page['next_offset'] as int?;
            } while (offset != null);
          }
        } catch (_) {
          // The local store reports interrupted synchronization without blocking a screen.
        }
      }().whenComplete(() => _librarySync = null);

  Future<void> _load({bool reviewInvitations = true}) async {
    // This cache chooses public browsing only. It never authorizes a mutation,
    // exposes account data, or substitutes for authenticated /me responses.
    final browseKey = 'browse-households|$apiBaseUrl|${widget.user.uid}';
    if (_households.isEmpty && widget.request == null) {
      try {
        final cached = await readOfflineStore(browseKey)
            .timeout(const Duration(seconds: 2));
        if (cached != null && mounted) {
          final households = List<Map<String, dynamic>>.from(
            jsonDecode(cached) as List,
          );
          _households = households;
          _selected = households.isEmpty
              ? null
              : households.first['id'] as String;
        }
      } catch (_) {
        /* A missing or corrupt browsing preference needs no error. */
      }
    }
    if (_households.isEmpty) {
      try {
        final cached = await _cachedRead('/me')
            .timeout(const Duration(seconds: 2));
        final households = recipeRows(cached?['households']);
        if (mounted && households.isNotEmpty) {
          setState(() {
            // Browsing context only; roles/invitations still require /me.
            _households = households;
            _selected = households.first['id'].toString();
          });
        }
      } catch (_) {
        // A cache failure cannot block online startup.
      }
    }
    await _perform(() async {
      final data = await _request('/me');
      _userId = (data['user'] as Map?)?['id'] as String?;
      _administrator =
          (data['user'] as Map?)?['account_role'] == 'administrator';
      final households = List<Map<String, dynamic>>.from(
        data['households'] as List,
      );
      if (!mounted) return;
      _households = households;
      if (widget.request == null) {
        try {
          await writeOfflineStore(
            browseKey,
            jsonEncode(
              households
                  .map((h) => {'id': h['id'], 'name': h['name']})
                  .toList(),
            ),
          );
        } catch (_) {
          /* Browsing does not depend on local storage availability. */
        }
      }
      _invitations = List<Map<String, dynamic>>.from(
        data['invitations'] as List? ?? [],
      );
      _invitationVerificationRequired =
          data['invitation_verification_required'] == true;
      if (!_households.any((h) => h['id'] == _selected)) {
        _selected = households.isEmpty
            ? null
            : households.first['id'] as String;
      }
      if (_offline != null && !offlineStatus.value) {
        unawaited(
          _syncLibrary(households.map((h) => h['id'] as String).toList()),
        );
      }
      if (_local != null) {
        for (final household in households) {
          unawaited(
            _local!
                .request('/households/${household['id']}/shopping-list')
                .catchError((Object _) => <String, dynamic>{}),
          );
        }
      }
      await _loadPeople();
    });
    _sharedRecipeChanged();
    if (mounted &&
        _error == null &&
        reviewInvitations &&
        !offlineStatus.value) {
      await _reviewInvitations();
    }
  }

  Future<void> _reviewInvitations() async {
    if (_reviewingInvitations) return;
    _reviewingInvitations = true;
    try {
      if (_invitationVerificationRequired) {
        final verified = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => InvitationVerificationDialog(user: widget.user),
        );
        if (verified == true && mounted) {
          await _load(reviewInvitations: false);
        }
      }
      for (final invitation in List<Map<String, dynamic>>.from(_invitations)) {
        if (!mounted) return;
        final accepted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (_) => InvitationResponseDialog(
            invitation: invitation,
            respond: (decision) async {
              await _request(
                '/invitations/${invitation['id']}/respond',
                body: {'decision': decision},
              );
            },
          ),
        );
        if (!mounted) return;
        if (accepted == true) {
          await _load(reviewInvitations: false);
          return;
        }
        _invitations.removeWhere((item) => item['id'] == invitation['id']);
      }
    } finally {
      _reviewingInvitations = false;
    }
  }

  Future<void> _invitePerson(Map<String, dynamic> person) async {
    final sent = await showDialog<bool>(
      context: context,
      builder: (_) => InvitePersonDialog(
        personName: person['display_name'] as String,
        send: (email) async {
          await _request(
            '/households/$_selected/people/${person['id']}/invitations',
            body: {'email': email},
          );
        },
      ),
    );
    if (mounted && sent == true) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invitation email sent.')));
      await _perform(_loadPeople);
    }
  }

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

  Future<void> _editName({required bool rename}) async {
    final household = _households.firstWhere((h) => h['id'] == _selected);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(
        title: rename ? 'Edit household name' : 'Add household member',
        label: rename ? 'Household name' : 'Person name',
        initialName: rename ? household['name'] as String : '',
      ),
    );
    if (!mounted || name == null) return;
    await _perform(() async {
      if (rename) {
        final data = await _request(
          '/households/$_selected/name',
          body: {'name': name},
        );
        if (mounted) household['name'] = (data['household'] as Map)['name'];
      } else {
        await _request(
          '/households/$_selected/people',
          body: {'display_name': name},
        );
        await _loadPeople();
      }
    });
  }

  void _leaveMenu() {
    final navigator = Navigator.of(context);
    navigator.pop(); // Close the current route's drawer first.
    navigator.popUntil((route) => route.isFirst);
  }

  Widget _buildMenu(BuildContext menuContext) {
    final selected = _households.where((h) => h['id'] == _selected).firstOrNull;
    return Drawer(
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  const ListTile(
                    leading: Icon(Icons.local_dining_outlined),
                    title: Text('Coffey Table'),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.menu_book_outlined),
                    title: const Text('Recipes'),
                    selected: !_settings && !_shopping,
                    onTap: () {
                      _leaveMenu();
                      setState(() {
                        _settings = false;
                        _shopping = false;
                        _recipeRefresh++;
                      });
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: const Text('Add recipe'),
                    enabled: selected != null,
                    onTap: selected == null
                        ? null
                        : () async {
                            _leaveMenu();
                            final householdId = _selected!;
                            final saved =
                                await Navigator.push<Map<String, dynamic>>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => RecipeImport(
                                      householdId: householdId,
                                      request: (path, body) async {
                                        final data = await _request(
                                          path,
                                          body: body,
                                        );
                                        if (data['recipe'] is Map &&
                                            (data['recipe'] as Map)['id'] !=
                                                null) {
                                          final id =
                                              (data['recipe'] as Map)['id'];
                                          await _offline?.rememberSavedRecipe(
                                            '/households/$householdId/recipes/$id',
                                            data,
                                          );
                                        }
                                        return data;
                                      },
                                    ),
                                  ),
                                );
                            if (saved != null && mounted) {
                              setState(() {
                                _settings = false;
                                _shopping = false;
                                _recipeRefresh++;
                              });
                            }
                          },
                  ),
                  ListTile(
                    leading: const Icon(Icons.shopping_basket_outlined),
                    title: const Text('Shopping list'),
                    selected: _shopping,
                    enabled: selected != null,
                    onTap: selected == null
                        ? null
                        : () {
                            _leaveMenu();
                            setState(() {
                              _shopping = true;
                              _shoppingOpened = true;
                              _settings = false;
                            });
                          },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_outline),
                    title: const Text('Recently Deleted'),
                    enabled: selected != null,
                    onTap: selected == null
                        ? null
                        : () async {
                            final householdId = _selected!;
                            _leaveMenu();
                            await Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => RecipeTrash(
                                  householdId: householdId,
                                  request: (path) => _request(path),
                                  save: _saveRecipe,
                                ),
                              ),
                            );
                            if (mounted) setState(() => _recipeRefresh++);
                          },
                  ),
                ],
              ),
            ),
            const AppVersionLabel(),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _households.where((h) => h['id'] == _selected).firstOrNull;
    final canAdd =
        selected != null && ['owner', 'admin'].contains(selected['role']);
    final settings = Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      selected?['name'] as String? ?? '',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  if (canAdd)
                    IconButton(
                      tooltip: 'Edit household name',
                      onPressed: _busy ? null : () => _editName(rename: true),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'People at your table',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final person in _people)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: SizedBox(
                    width: 48,
                    height: 48,
                    child: person['user_id'] != null
                        ? Icon(
                            Icons.account_circle,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : IconButton(
                            tooltip: person['invitation_email'] != null
                                ? 'Invitation pending'
                                : 'Invite to household',
                            icon: const Icon(Icons.mail_outline),
                            onPressed: _busy || !canAdd
                                ? null
                                : () => _invitePerson(person),
                          ),
                  ),
                  title: Text(person['display_name'] as String),
                  trailing: person == _ownPerson
                      ? IconButton(
                          tooltip: 'Change name at the table',
                          onPressed: _busy || _accountBusy
                              ? null
                              : _changeTableName,
                          icon: const Icon(Icons.edit_outlined),
                        )
                      : null,
                ),
              if (!_busy && _people.isEmpty)
                const Text('No people have been added yet.'),
              if (canAdd) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _editName(rename: false),
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('Add household member'),
                ),
              ],
              const SizedBox(height: 24),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.category_outlined),
                title: const Text('Shopping list departments'),
                trailing: const Icon(Icons.chevron_right),
                enabled: selected != null && !_busy,
                onTap: selected == null || _busy
                    ? null
                    : () async {
                        final householdId = _selected!;
                        await Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ShoppingDepartmentsScreen(
                              menuBuilder: _buildMenu,
                              householdId: householdId,
                              request: (path, {body}) =>
                                  _request(path, body: body),
                            ),
                          ),
                        );
                        if (mounted) setState(() => _shoppingRefresh++);
                      },
              ),
            ],
          ],
        ),
      ),
    );
    final name =
        _displayName ??
        widget.user.displayName ??
        widget.user.email ??
        'Your account';
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _shopping
              ? 'Shopping list'
              : _settings
              ? 'Household & people'
              : 'Recipes',
        ),
        actions: [
          if (!kIsWeb && MediaQuery.sizeOf(context).width >= 600)
            Center(
              child: SizedBox(
                width: 120,
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          AccountMenu(
            name: name,
            email: widget.user.email,
            enabled: !_accountBusy,
            canEditTableName: !_busy && _ownPerson != null,
            showTimers: NativeTimers.supported,
            administrator: _administrator,
            onSelected: (value) {
              if (value == 'timers') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TimerSettings(),
                  ),
                );
              }
              if (value == 'name') _changeDisplayName();
              if (value == 'tableName') _changeTableName();
              if (value == 'administration') _openAdministration();
              if (value == 'logout') _logOut();
              if (value == 'household') {
                setState(() {
                  _settings = true;
                  _shopping = false;
                });
                if (!_busy) _perform(_loadPeople);
              }
            },
          ),
        ],
      ),
      drawer: _buildMenu(context),
      body: Column(
        children: [
          if (mobileOfflineEnabled &&
              _offline != null &&
              _households.isNotEmpty)
            RecipeSyncStatus(
              progress: _offline!.progress,
              retry: () => unawaited(_offline!.retry()),
            ),
          Expanded(
            child: IndexedStack(
              index: _shopping
                  ? 2
                  : _settings
                  ? 1
                  : 0,
              children: [
                _busy && _households.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null && selected == null
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(_error!),
                            ),
                            TextButton(
                              onPressed: _load,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      )
                    : selected == null
                    ? Center(
                        child: FilledButton(
                          onPressed: () => setState(() => _settings = true),
                          child: const Text('Set up household'),
                        ),
                      )
                    : RecipeBrowser(
                        key: ValueKey('$_selected|$_recipeRefresh'),
                        embedded: true,
                        householdId: _selected!,
                        householdName: selected['name'] as String,
                        request: (path) => _request(path),
                        menuBuilder: _buildMenu,
                        cachedRequest: _cachedRead,
                        save: _saveRecipe,
                      ),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [settings],
                    ),
                  ),
                ),
                if (_shoppingOpened && selected != null)
                  ShoppingListScreen(
                    key: ValueKey('shopping-$_selected-$_shoppingRefresh'),
                    embedded: true,
                    active: _shopping,
                    localFirst: _local != null,
                    cache: ShoppingListCache(
                      account: widget.user.uid,
                      household: _selected!,
                      server: apiBaseUrl,
                    ),
                    householdId: _selected!,
                    householdName: selected['name'] as String,
                    request: (path, {body}) => _request(path, body: body),
                    requestSynchronization: () async {
                      await _request(
                        '/households/$_selected/shopping-list/sync-request',
                        body: {},
                      );
                    },
                  )
                else
                  const SizedBox(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.title,
    required this.label,
    required this.initialName,
  });
  final String title;
  final String label;
  final String initialName;
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_form.currentState!.validate()) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: Form(
      key: _form,
      child: TextFormField(
        controller: _controller,
        autofocus: true,
        mouseCursor: kIsWeb
            ? SystemMouseCursors.basic
            : SystemMouseCursors.text,
        maxLength: 200,
        decoration: InputDecoration(labelText: widget.label),
        validator: (value) =>
            value == null || value.trim().isEmpty ? 'Enter a name.' : null,
        onFieldSubmitted: (_) => _save(),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Save')),
    ],
  );
}
