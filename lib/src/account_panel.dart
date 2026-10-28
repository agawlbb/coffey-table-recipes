import 'shopping_socket.dart';
import 'child_mode.dart';
import 'meal_plan_actions.dart';
import 'restaurant_manager.dart';
import 'sync_notifications.dart';
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
import 'meal_planner.dart';
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
    childModeOf(context);
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
    this.readPreference,
    this.writePreference,
  });
  final Future<String?> Function(String)? readPreference;
  final Future<void> Function(String, String)? writePreference;
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

class _HouseholdPanelState extends State<HouseholdPanel>
    with WidgetsBindingObserver {
  late final _api = RecipeApi(
    baseUrl: apiBaseUrl,
    onServerTime: (milliseconds, receivedAt) =>
        _local?.observeServerTime(milliseconds, receivedAt),
  );
  OfflineRecipes? _offline;
  LocalData? _local;
  final _shoppingSockets = <String, ShoppingSocket>{};
  ShoppingSocket _shoppingSocket(String household) =>
      _shoppingSockets.putIfAbsent(household, () {
        final socket = ShoppingSocket(
          household: household,
          token: (refresh) => _idToken(refresh),
          onSnapshot: (state) async {
            await _local?.acceptShopping(household, state);
          },
          onTime: (time) => _local?.observeServerTime(time, DateTime.now()),
          onReady: () {
            if (mounted) unawaited(_local?.synchronize());
          },
        );
        socket.addListener(_shoppingConnectionChanged);
        socket.start();
        return socket;
      });
  void _shoppingConnectionChanged() {
    if (mounted) setState(() {});
  }

  Timer? _mirrorTimer;
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
  bool _planning = false;
  bool _plannerOpened = false;
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
    if (childMode.value) return;
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
    if (childMode.value) return;
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
    WidgetsBinding.instance.addObserver(this);
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
            downloadLibrary: false,
          )..start(() {
            if (mounted) unawaited(_load(reviewInvitations: false));
          });
    }
    if (widget.request == null) {
      _local = LocalData(
        key: '$apiBaseUrl|${widget.user.uid}',
        fetch: (path) => isShoppingPath(path)
            ? _onlineRequest(path)
            : _offline!.request(path),
        readServer: (path) => _onlineRequest(path),
        send: (path, body) => _onlineRequest(path, body: body),
        online: () => !offlineStatus.value,
        canSend: (path) => isShoppingPath(path)
            ? (_shoppingSockets[Uri.parse(path).pathSegments[1]]?.connected ??
                  false)
            : !offlineStatus.value,
        snapshotOnly: true,
        separateShopping: true,
        onPendingChanged: SyncNotifications.update,
      )..start();
      localDataChanges.addListener(_localChanged);
      _mirrorTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted &&
            !offlineStatus.value &&
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) {
          unawaited(_refreshChildPolicy());
          unawaited(
            _syncLibrary(_households.map((h) => h['id'] as String).toList()),
          );
        }
      });
    }
    unawaited(_restoreSectionAndLoad());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    sharedRecipeInbox.removeListener(_sharedRecipeChanged);
    _mirrorTimer?.cancel();
    for (final socket in _shoppingSockets.values) {
      socket.dispose();
    }
    localDataChanges.removeListener(_localChanged);
    _local?.dispose();
    _offline?.close();
    _api.close();
    _householdName.dispose();
    _personName.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      for (final socket in _shoppingSockets.values) {
        socket.reconnect();
      }
    }
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
          _planning = false;
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
    if (path.endsWith('/variation') ||
        path.contains('/meal-plan') ||
        path.contains('/shopping-list') ||
        path.contains('/restaurants')) {
      return data;
    }
    await _offline?.rememberSavedRecipe(path, data);
    if (_local != null && !_local!.canSave(path)) {
      await _local!.acceptServerRecipe(path, data);
    }
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
    if (body != null) requireChildModeWrite(path);
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
    if (isShoppingPath(path)) {
      final household = Uri.parse(path).pathSegments[1];
      return _shoppingSocket(household).request(path, body: body);
    }
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

  final _readyHouseholds = <String>{};
  bool _databaseChecking = true;
  String? _databaseError;
  String _databaseProgress = 'Checking local database';
  double? _databaseFraction;
  Future<void>? _librarySync;
  Future<void> _syncLibrary(List<String> households) async {
    final active = _librarySync;
    if (active != null) {
      await active;
      final missing = households
          .where((id) => !_readyHouseholds.contains(id))
          .toList();
      if (mounted && missing.isNotEmpty) await _syncLibrary(missing);
      return;
    }
    final task = _downloadLibraries(households);
    _librarySync = task;
    try {
      await task;
    } finally {
      _librarySync = null;
    }
  }

  Future<void> _downloadLibraries(List<String> households) async {
    for (var index = 0; index < households.length; index++) {
      final household = households[index];
      if (!mounted) return;
      setState(() {
        _databaseError = null;
        _databaseProgress =
            'Downloading household ${index + 1} of ${households.length}';
        _databaseFraction = index / households.length;
      });
      try {
        final epoch = _local!.snapshotEpoch;
        final version = await _local!.snapshotVersion(household);
        final token = await _idToken();
        if (token == null) throw ApiException(401, 'Please sign in again.');
        final snapshot = await _api.request(
          '/households/$household/snapshot${version == null ? '' : '?version=$version'}',
          token,
          timeout: const Duration(seconds: 90),
          onProgress: (received, total) {
            if (!mounted || _readyHouseholds.contains(household)) return;
            setState(() {
              _databaseProgress =
                  'Downloaded ${(received / 1024).round()} KB${total == null ? '' : ' of ${(total / 1024).round()} KB'}';
              _databaseFraction = total == null || total == 0
                  ? null
                  : (index + 0.8 * received / total) / households.length;
            });
          },
        );
        if (!mounted) return;
        if (_local!.snapshotEpoch != epoch) {
          if (!_readyHouseholds.contains(household)) index--;
          continue;
        }
        if (snapshot['unchanged'] != true) {
          if (snapshot['schema'] != 1 ||
              snapshot['household_id'] != household ||
              snapshot['version'] is! String ||
              snapshot['recipes'] is! List ||
              snapshot['categories'] is! List ||
              snapshot['responses'] is! Map ||
              snapshot['edit_options'] is! Map) {
            throw const FormatException('Incomplete database response');
          }
          final responses = snapshot['responses'] as Map;
          for (final row in snapshot['recipes'] as List) {
            if (responses['/households/$household/recipes/${row['id']}']?['recipe']
                    is! Map ||
                responses['/households/$household/recipes/${row['id']}/favorites']
                    is! Map) {
              throw const FormatException('Missing recipe data');
            }
          }
          for (final resource in [
            'people',
            'recipe-blank',
            'meal-plan',
            'meal-plan/history',
          ]) {
            if (responses['/households/$household/$resource'] is! Map) {
              throw const FormatException('Missing household data');
            }
          }
          setState(() {
            _databaseProgress =
                'Saving ${(snapshot['recipes'] as List).length} recipes on this device';
            _databaseFraction = (index + 0.8) / households.length;
          });
          await _local!.installSnapshot(snapshot);
        }
        if (await _local!.snapshotVersion(household) != null && mounted) {
          setState(() {
            _readyHouseholds.add(household);
            _databaseFraction = (index + 1) / households.length;
          });
        }
      } catch (error) {
        if (mounted) {
          setState(() {
            _databaseError = error is ApiException ? error.message : 'Database download could not finish. Your existing local data is safe. Retry to finish setup.';
          });
        }
      }
    }
  }

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
    if (_local != null) {
      for (final h in _households) {
        final id = h['id'] as String;
        if (await _local!.snapshotVersion(id) != null &&
            await _local!.cached('/households/$id/meal-plan') != null) {
          _readyHouseholds.add(id);
        }
      }
      if (mounted) setState(() => _databaseChecking = false);
    }
    if (widget.request == null && _selected != null) {
      _shoppingSocket(_selected!);
    }
    await _perform(() async {
      final data = _local == null
          ? await _request('/me')
          : await _local!.refresh('/me', force: true).catchError((
              Object error,
            ) async {
              final saved = await _local!.cached('/me');
              if (saved != null) return saved;
              throw error;
            });
      if (widget.request != null) {
        childMode.value = (data['user'] as Map?)?['child_mode'] == true;
      } else {
        await _refreshChildPolicy();
      }
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
          _shoppingSocket(household['id'] as String);
          unawaited(
            _local!
                .request(
                  '/households/${household['id']}/meal-plan?from=2000-01-01&to=2199-12-31',
                )
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
    if (_reviewingInvitations || childMode.value) return;
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
    if (childMode.value) return;
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
    if (_selected == null ||
        (_local != null && !_readyHouseholds.contains(_selected))) {
      _people = [];
      return;
    }
    final data = await _request('/households/$_selected/people');
    if (mounted) {
      _people = List<Map<String, dynamic>>.from(data['people'] as List);
    }
  }

  Future<void> _create() async {
    if (childMode.value) return;
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
      if (_local != null) {
        unawaited(
          _syncLibrary(_households.map((h) => h['id'] as String).toList()),
        );
      }
      await _loadPeople();
    });
  }

  Future<void> _editName({required bool rename}) async {
    if (childMode.value) return;
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

  Future<void> _openRecentlyDeleted() async {
    if (_selected == null) return;
    mealPlanNotices.dismiss();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeTrash(
          householdId: _selected!,
          request: (path) => _request(path),
          save: _saveRecipe,
        ),
      ),
    );
    if (mounted) setState(() => _recipeRefresh++);
  }

  Future<void> _refreshChildPolicy() async {
    try {
      final policy = await _onlineRequest('/me/child-mode');
      if (!mounted) return;
      childMode.value = policy['enabled'] == true;
      try {
        await writeOfflineStore(
          'ctr-child-mode:${widget.user.uid}',
          '${childMode.value}',
        );
      } catch (_) {}
    } catch (_) {
      /* Retain this device's last confirmed policy offline. */
    }
  }

  String get _sectionKey =>
      'ctr-last-section-v1:$apiBaseUrl|${widget.user.uid}';
  Future<void> _restoreSectionAndLoad() async {
    try {
      final reader =
          widget.readPreference ??
          (widget.request == null
              ? readOfflineStore
              : (String _) async => null);
      final section = await reader(_sectionKey)
          .timeout(const Duration(seconds: 2));
      if (!mounted) return;
      setState(() {
        _planning = section == 'planner';
        _plannerOpened = _planning;
        _shopping = section == 'shopping';
        _shoppingOpened = _shopping;
      });
    } catch (_) {
      /* Device preference failure must not block startup. */
    }
    if (widget.request == null) {
      try {
        childMode.value =
            await readOfflineStore('ctr-child-mode:${widget.user.uid}')
                .timeout(const Duration(seconds: 2)) ==
            'true';
      } catch (_) {
        childMode.value = true;
      }
    }
    if (mounted) await _load();
  }

  Future<void> _sectionWrite = Future<void>.value();
  void _rememberSection(String section) {
    if (widget.request != null && widget.writePreference == null) return;
    _sectionWrite = _sectionWrite.then((_) async {
      try {
        await (widget.writePreference ?? writeOfflineStore)(
          _sectionKey,
          section,
        );
      } catch (_) {
        /* Preference writes never block navigation. */
      }
    });
  }

  Future<void> _addRecipe() async {
    if (childMode.value) return;
    if (_selected == null || offlineStatus.value) return;
    mealPlanNotices.dismiss();
    final householdId = _selected!;
    final saved = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeImport(
          householdId: householdId,
          request: (path, body) async {
            final data = await _request(path, body: body);
            if (data['recipe'] is Map &&
                (data['recipe'] as Map)['id'] != null) {
              final id = (data['recipe'] as Map)['id'];
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
      _rememberSection('recipes');
      setState(() {
        _settings = false;
        _shopping = false;
        _planning = false;
        _recipeRefresh++;
      });
    }
  }

  void _leaveMenu() {
    mealPlanNotices.dismiss();
    final navigator = Navigator.of(context);
    navigator.pop(); // Close the current route's drawer first.
    navigator.popUntil((route) => route.isFirst);
  }

  void _openMealPlan() {
    _rememberSection('planner');
    mealPlanNotices.dismiss();
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      _settings = false;
      _shopping = false;
      _planning = true;
      _plannerOpened = true;
    });
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
                    selected: !_settings && !_shopping && !_planning,
                    onTap: () {
                      _leaveMenu();
                      setState(() {
                        _settings = false;
                        _shopping = false;
                        _recipeRefresh++;
                        _planning = false;
                        _rememberSection('recipes');
                      });
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.calendar_month_outlined),
                    title: const Text('Meal planner'),
                    selected: _planning,
                    enabled: selected != null,
                    onTap: selected == null
                        ? null
                        : () {
                            _leaveMenu();
                            _openMealPlan();
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
                              _rememberSection('shopping');
                              _shopping = true;
                              _planning = false;
                              _shoppingOpened = true;
                              _settings = false;
                            });
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
    childModeOf(context);
    if (_local != null &&
        (_databaseChecking ||
            _households.any((h) => !_readyHouseholds.contains(h['id'])))) {
      return Scaffold(
        appBar: AppBar(title: const Text('Downloading database')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Saving your household data on this device'),
                const SizedBox(height: 20),
                LinearProgressIndicator(value: _databaseFraction),
                const SizedBox(height: 12),
                Text(_databaseProgress),
                if (_databaseError != null) ...[
                  const SizedBox(height: 16),
                  Text(_databaseError!),
                ],
                TextButton(
                  onPressed: _librarySync != null
                      ? null
                      : () => unawaited(
                          _syncLibrary(
                            _households.map((h) => h['id'] as String).toList(),
                          ),
                        ),
                  child: const Text('Retry download'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final selected = _households.where((h) => h['id'] == _selected).firstOrNull;
    final canAdd =
        !childMode.value &&
        selected != null &&
        ['owner', 'admin'].contains(selected['role']);
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
                onPressed: childMode.value ? null : _create,
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
                      onPressed: _busy || childMode.value
                          ? null
                          : () => _editName(rename: true),
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
                  title: Row(
                    children: [
                      Flexible(child: Text(person['display_name'] as String)),
                      if (person['user_id'] != null &&
                          person['child_mode'] == true) ...[
                        const SizedBox(width: 8),
                        const Tooltip(
                          message: 'Child account',
                          child: Icon(
                            Icons.child_care,
                            semanticLabel: 'Child account',
                            size: 20,
                          ),
                        ),
                      ],
                    ],
                  ),
                  trailing: person == _ownPerson
                      ? IconButton(
                          tooltip: 'Change name at the table',
                          onPressed: _busy || _accountBusy || childMode.value
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
                  onPressed: _busy || childMode.value
                      ? null
                      : () => _editName(rename: false),
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
                enabled: selected != null && !_busy && !childMode.value,
                onTap: selected == null || _busy || childMode.value
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.restaurant_outlined),
                title: const Text('Manage restaurants'),
                trailing: const Icon(Icons.chevron_right),
                enabled: selected != null && !_busy && !childMode.value,
                onTap: selected == null || _busy || childMode.value
                    ? null
                    : () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RestaurantManager(
                            householdId: _selected!,
                            request: (path) => _request(path),
                            save: _saveRecipe,
                          ),
                        ),
                      ),
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
          _planning
              ? 'Meal planner'
              : _shopping
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
          if (_shopping && (_shoppingSockets[_selected]?.connected ?? false))
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.cloud_done, color: Colors.green, size: 18),
            ),
          AccountMenu(
            name: name,
            email: widget.user.email,
            enabled: !_accountBusy,
            canEditTableName: !_busy && _ownPerson != null,
            showTimers: NativeTimers.supported,
            administrator: _administrator,
            onSelected: (value) {
              if (value == 'childMode') {
                changeChildMode(context, (body) async {
                  final result = await _onlineRequest(
                    '/me/child-mode',
                    body: body,
                  );
                  childMode.value = result['enabled'] == true;
                  if (widget.request == null) {
                    try {
                      await writeOfflineStore(
                        'ctr-child-mode:${widget.user.uid}',
                        '${childMode.value}',
                      );
                    } catch (_) {}
                  }
                  try {
                    await _local?.refresh('/me', force: true);
                  } catch (_) {}
                  if (mounted) setState(() {});
                  return result;
                });
              }
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
                  mealPlanNotices.dismiss();
                  _settings = true;
                  _planning = false;
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
          if (_local != null && !_shopping) LocalSyncStatus(data: _local!),
          Expanded(
            child: IndexedStack(
              index: _planning
                  ? 3
                  : _shopping
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
                        localOnly: _local != null,
                        localRead: _local?.readView,
                        key: ValueKey('$_selected|$_recipeRefresh'),
                        embedded: true,
                        householdId: _selected!,
                        householdName: selected['name'] as String,
                        request: (path) => _request(path),
                        menuBuilder: _buildMenu,
                        cachedRequest: _cachedRead,
                        save: _saveRecipe,
                        onViewMealPlan: _openMealPlan,
                        onAddRecipe: childMode.value ? null : _addRecipe,
                        onRecentlyDeleted: childMode.value
                            ? null
                            : _openRecentlyDeleted,
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
                if (_plannerOpened && selected != null)
                  MealPlanner(
                    key: ValueKey('meal-plan-$_selected'),
                    householdId: _selected!,
                    householdName: selected['name'] as String,
                    active: _planning,
                    request: (path) => _request(path),
                    save: (path, body) => _request(path, body: body),
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
