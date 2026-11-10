import 'combined_cooking.dart';
import 'local_sqlite.dart';
import 'connection_notice.dart';
import 'app_connection.dart';
import 'client_log.dart';
import 'client_log_screen.dart';
import 'notification_settings.dart';
import 'work_calendar_setting.dart';
import 'connection_indicator.dart';
import 'cooking_sessions.dart';
import 'cooking_session_ui.dart';
import 'child_mode.dart';
import 'meal_plan_actions.dart';
import 'restaurant_manager.dart';
import 'account_menu.dart';
import 'recipe_menu.dart';

import 'dart:async';
import 'dart:convert';

import 'offline_store.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

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
    } catch (error, stack) {
      clientLog.record(
        'account',
        'operation_failed',
        error: error,
        stack: stack,
        status: error is ApiException ? error.status : null,
        code: error is ApiException ? error.code : null,
      );
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
    this.socketConnect,
    this.storage,
  });
  @visibleForTesting
  final WebSocketChannel Function(Uri)? socketConnect;
  final LocalSqlite? storage;
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
    connection: widget.socketConnect == null
        ? appConnection
        : AppConnection(
            connect: widget.socketConnect!,
            refreshToken: (refresh) => _idToken(refresh),
          ),
  );
  Timer? _offlineRetry;
  bool _reviewingOffline = false;
  final _reviewedOffline = <String>{};
  String _decisionKey(Map entry) =>
      '${entry['id']}:${entry['confirmation'] ?? 'offline'}';
  final _reportedOffline = <String>{};
  bool get _connected =>
      widget.request != null || (_api.liveConnection?.connected ?? false);

  void _offlineChanged() {
    if (!mounted) return;
    localDataChanges.value =
        '/me#offline-${DateTime.now().microsecondsSinceEpoch}';
    _scheduleOffline();
    if (_connected && (_local?.decisions.isNotEmpty ?? false)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_resumeOffline());
      });
    }
  }

  void _scheduleOffline() {
    _offlineRetry?.cancel();
    if (!mounted) return;
    var delay = _local?.untilRemovalExpiry;
    if (_connected &&
        (_local?.hasAutomatic ?? false) &&
        (delay == null || delay > const Duration(seconds: 30))) {
      delay = const Duration(seconds: 30);
    }
    if (delay == null) return;
    _offlineRetry = Timer(delay, () async {
      try {
        await _local?.expire();
        if (mounted && _connected) await _resumeOffline();
      } catch (error) {
        clientLog.record('offline', 'retry_failed', error: error);
      }
      if (mounted) _scheduleOffline();
    });
  }

  Future<void> _resumeOffline() async {
    if (!_connected || !mounted) return;
    // Never await this work from the socket snapshot callback.
    // Delivery runs independently from prompts and incoming snapshots.
    unawaited(_local?.synchronize() ?? Future.value());
    if (mounted) _scheduleOffline();
    if (!mounted || !_connected || _reviewingOffline) return;
    _reviewingOffline = true;
    try {
      for (final entry in _local?.decisions ?? <Map<String, dynamic>>[]) {
        if (!_connected || !mounted) break;
        if (!_reviewedOffline.add(_decisionKey(entry))) continue;
        final body = entry['body'] as Map;
        final meal = (entry['path'] as String).endsWith('/meal-plan');
        final shared = entry['confirmation'] == 'shared_confirmation_required';
        final past = entry['confirmation'] == 'past_confirmation_required';
        String? failure;
        var saving = false;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialog) => StatefulBuilder(
            builder: (dialog, update) {
              Future<void> decide(bool save) async {
                if (saving) return;
                if (!save && (shared || past)) {
                  Navigator.pop(dialog);
                  return;
                }
                if (save && !_connected) {
                  update(
                    () => failure = 'You’re not connected. Your changes are still on this device. Reconnect to send them.',
                  );
                  return;
                }
                update(() {
                  saving = true;
                  failure = null;
                });
                try {
                  await _local!.decide(entry['id'] as String, save);
                  if (dialog.mounted) Navigator.pop(dialog);
                } catch (error) {
                  clientLog.record(
                    'offline',
                    'recipe_edit_send_failed',
                    error: error,
                    path: entry['path'] as String,
                  );
                  if (dialog.mounted) {
                    update(() {
                      saving = false;
                      failure = 'Your changes are still on this device. They couldn’t be submitted. Please try again.';
                    });
                  }
                }
              }

              return AlertDialog(
                title: Text(
                  shared
                      ? 'Save recipe changes?'
                      : past
                      ? 'Change this past meal?'
                      : meal
                      ? 'Save meal-plan changes?'
                      : 'Save your offline changes?',
                ),
                content: Text(
                  shared
                      ? 'Your changes update the same recipe in every household that has added it.'
                      : past
                      ? 'This will update your cooking history.'
                      : meal
                      ? '${entry['description']}\n\nSave this change to the shared meal plan, or discard it and use the server’s plan.${failure == null ? '' : '\n\n$failure'}'
                      : 'You changed “${body['title']}” while offline. These changes haven’t been saved to the server. Saving now will replace the recipe currently on the server.${failure == null ? '' : '\n\n$failure'}',
                ),
                actions: [
                  TextButton(
                    onPressed: saving ? null : () => decide(false),
                    child: Text(
                      shared || past ? 'Cancel' : 'Discard my changes',
                    ),
                  ),
                  FilledButton(
                    onPressed: saving ? null : () => decide(true),
                    child: Text(
                      shared
                          ? 'Save for all households'
                          : past
                          ? 'Change'
                          : meal
                          ? 'Save meal-plan changes'
                          : 'Save to server',
                    ),
                  ),
                ],
              );
            },
          ),
        );
      }
    } finally {
      _reviewingOffline = false;
      if (mounted &&
          _connected &&
          (_local?.decisions.any(
                (e) => !_reviewedOffline.contains(_decisionKey(e)),
              ) ??
              false)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(_resumeOffline());
        });
      }
    }
  }

  LocalData? _local;
  String? _lastSyncReason;
  Future<void>? _accountLoading;
  Map<String, dynamic>? _pushedAccount;

  Future<void> _receiveAppState(Map<String, dynamic> state) async {
    if (!mounted) return;
    final account = state['account'];
    if (account is Map) {
      await _local?.acceptAccountSnapshot(Map<String, dynamic>.from(account));
    }
    final households = state['households'];
    if (households is Map) {
      for (final row in households.entries) {
        final id = '${row.key}';
        final data = row.value as Map;
        await _local?.acceptShopping(
          id,
          Map<String, dynamic>.from(data['shopping'] as Map),
        );
        await _local?.installSnapshot(
          Map<String, dynamic>.from(data['library'] as Map),
        );
        _readyHouseholds.add(id);
      }
      if (mounted) {
        setState(() {
          _databaseChecking = false;
          _databaseError = null;
        });
      }
    }
    if (account is Map && mounted) {
      unawaited(
        _load(
          reviewInvitations: false,
          account: Map<String, dynamic>.from(account),
        ),
      );
    }
    _syncStatusChanged();
  }

  void _syncStatusChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      scheduleMicrotask(() {
        if (mounted) _syncStatusChanged();
      });
      return;
    }
    final connected =
        widget.request != null || (_api.liveConnection?.connected ?? false);
    offlineStatus.value = !connected;
    final households = _api.liveConnection?.data['households'] as Map? ?? {};
    connectedHouseholds.value = connected
        ? households.keys.map((id) => '$id').toSet()
        : {};
    if (!connected) {
      _reviewedOffline.clear();
      _reportedOffline.clear();
    }
    if (_lastSyncReason != (connected ? 'connected' : 'disconnected')) {
      _scheduleOffline();
    }
    if (connected && _lastSyncReason != 'connected') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_resumeOffline());
      });
    }
    final reason = connected ? 'connected' : 'disconnected';
    if (_lastSyncReason != reason) {
      _lastSyncReason = reason;
      clientLog.record('sync', reason, connected: connected);
    }
    setState(() {});
  }

  void _localChanged() {
    if (!mounted) return;
    if (_selected != null &&
        localDataChanges.value.startsWith('/households/$_selected/people#')) {
      unawaited(_loadPeople());
    }
  }

  Future<Map<String, dynamic>?> _cachedRead(String path) =>
      widget.cachedRequest?.call(path) ??
      _local?.cachedView(path) ??
      Future.value(null);
  final _householdName = TextEditingController();
  final _personName = TextEditingController();
  List<Map<String, dynamic>> _households = [];
  List<Map<String, dynamic>> _people = [];
  final _peopleChildModes = <String, bool>{};
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

  Future<void> _changeName() async {
    if (childMode.value) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(
        title: 'Full name',
        label: 'Full name',
        initialName: _name,
      ),
    );
    if (!mounted || name == null) return;
    setState(() => _accountBusy = true);
    try {
      final data = await _request('/me/name', body: {'display_name': name});
      if (!mounted) return;
      final savedName = (data['user'] as Map)['display_name'] as String;
      setState(() {
        _displayName = savedName;
      });
      _settingsChanges.value++;
      if (_local != null) {
        unawaited(
          _local!
              .refresh('/me', force: true)
              .catchError((Object _) => <String, dynamic>{}),
        );
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Name updated.')));
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is ApiException
                  ? error.message
                  : 'Could not update your name. Please try again.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _accountBusy = false);
    }
  }

  bool _canEditMember(Map<String, dynamic> person) {
    if (childMode.value || person['user_id'] == null) return false;
    if (person['user_id'] == _userId) return true;
    final selected = _households.where((h) => h['id'] == _selected).firstOrNull;
    final isChild =
        _peopleChildModes[person['id']] ?? person['child_mode'] == true;
    return isChild && ['owner', 'admin'].contains(selected?['role']);
  }

  Future<void> _changeMemberName(
    BuildContext pageContext,
    Map<String, dynamic> person,
  ) async {
    if (!_canEditMember(person) || _selected == null) return;
    final householdId = _selected!;
    final name = await showDialog<String>(
      context: pageContext,
      builder: (_) => _NameDialog(
        title: 'Display name',
        label: 'Display name',
        initialName: person['display_name'] as String,
      ),
    );
    if (!mounted || name == null || !_canEditMember(person)) return;
    await _perform(() async {
      final result = await _request(
        '/households/$householdId/people/${person['id']}/name',
        body: {'display_name': name},
      );
      person['display_name'] = (result['person'] as Map)['display_name'];
      if (mounted) setState(() => _recipeRefresh++);
    });
  }

  String get _name =>
      _displayName ??
      widget.user.displayName ??
      widget.user.email ??
      'Your account';

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
    _api.refreshSocketToken = () => _idToken(true);
    _api.onAppSnapshot = _receiveAppState;
    _api.onConnectionChanged = _syncStatusChanged;
    WidgetsBinding.instance.addObserver(this);
    sharedRecipeInbox.addListener(_sharedRecipeChanged);
    cookingSessions.addListener(_cookingChanged);
    _personName.text = widget.user.displayName ?? '';
    if (widget.request == null) {
      _local = LocalData(
        key: '$apiStorageNamespace|${widget.user.uid}',
        fetch: (path) => _onlineRequest(path),
        send: (path, body) => _onlineRequest(path, body: body),
        readStore: widget.storage?.read ?? readLocalSqlite,
        writeStore: widget.storage?.write ?? writeLocalSqlite,
      );
      _local!.connected = () => mounted && _connected;
      unawaited(cookingSessions.bindLocal(_local!, widget.user.uid));
      _local!.onSendError = (path, error) {
        if (mounted && _reportedOffline.add(path)) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Saved on this device. ${error is ApiException ? error.message : 'The change could not be sent.'} It will retry while connected.',
              ),
            ),
          );
        }
      };
      _local!.addListener(_offlineChanged);
      _local!.addListener(_syncStatusChanged);
      localDataChanges.addListener(_localChanged);
    }
    unawaited(_restoreSectionAndLoad());
    if (widget.request == null) {
      unawaited(
        _idToken()
            .then((token) async {
              if (token != null && mounted) await _api.connect(token);
            })
            .catchError((Object error) {
              clientLog.record('sync', 'connect_failed', error: error);
            }),
      );
    }
  }

  @override
  void dispose() {
    _offlineRetry?.cancel();
    _local?.removeListener(_offlineChanged);
    WidgetsBinding.instance.removeObserver(this);
    sharedRecipeInbox.removeListener(_sharedRecipeChanged);
    cookingSessions.removeListener(_cookingChanged);
    cookingMenuBuilder = null;
    cookingRecipeBrowser = null;
    connectedHouseholds.value = {};
    localDataChanges.removeListener(_localChanged);
    _local?.removeListener(_syncStatusChanged);
    _local?.dispose();
    _api.close();
    if (widget.socketConnect != null) _api.liveConnection?.dispose();
    _householdName.dispose();
    _personName.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    clientLog.record('lifecycle', state.name);
  }

  bool _cookingInvitationOpen = false;
  String? _lastCookingError;
  void _cookingChanged() {
    final message = cookingSessions.error;
    if (mounted && message != null && message != _lastCookingError) {
      _lastCookingError = message;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(message)));
        }
      });
    }
    if (!mounted ||
        _cookingInvitationOpen ||
        childMode.value ||
        cookingSessions.invitations.isEmpty) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _cookingInvitationOpen || childMode.value) return;
      final invitations = cookingSessions.invitations;
      if (invitations.isEmpty) return;
      _cookingInvitationOpen = true;
      cookingSessions.offered.addAll(invitations.map((s) => '${s['id']}'));
      final chosen = await showDialog<String>(
        context: context,
        builder: (dialog) => SimpleDialog(
          title: const Text('Mirror cooking?'),
          children: [
            for (final session in invitations)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialog, '${session['id']}'),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('${(session['recipe'] as Map)['title']}'),
                    ),
                    const Text('Join'),
                  ],
                ),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Not now'),
            ),
          ],
        ),
      );
      _cookingInvitationOpen = false;
      if (mounted && chosen != null) {
        final session = cookingSessions.session(chosen);
        if (session != null) {
          await openCookingSession(context, session, menuBuilder: _buildMenu);
        }
      }
    });
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
    await connectionNotice(context, 'add');
    if (!mounted) return;
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
                  (data['recipe'] as Map)['id'] != null) {}
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
  ) => _request(path, body: body);

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (body != null) requireChildModeWrite(path);
    if (widget.request != null) return widget.request!(path, body: body);
    if (_local != null) {
      if (path.endsWith('/recipe-blank')) return _local!.blank(path);
      if (body == null) return _local!.request(path);
      if (_local!.ownsWrite(path)) return _local!.save(path, body);
    }
    return _onlineRequest(path, body: body);
  }

  Future<Map<String, dynamic>> _onlineRequest(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    return _sendOnlineRequest(path, body: body);
  }

  Future<Map<String, dynamic>> _sendOnlineRequest(
    String path, {
    Map<String, dynamic>? body,
  }) async {
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
    _settingsChanges.value++;
    try {
      await action();
    } catch (error, stack) {
      clientLog.record(
        'account',
        'load_or_action_failed',
        error: error,
        stack: stack,
        status: error is ApiException ? error.status : null,
        code: error is ApiException ? error.code : null,
      );
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
        _settingsChanges.value++;
        _sharedRecipeChanged();
      }
    }
  }

  final _readyHouseholds = <String>{};
  bool _databaseChecking = true;
  String? _databaseError;
  final String _databaseProgress = 'Connecting to server';
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
    final token = await _idToken();
    if (token == null) throw ApiException(401, 'Please sign in again.');
    await _api.request('/me', token);
  }

  Future<void> _load({
    bool reviewInvitations = true,
    Map<String, dynamic>? account,
  }) {
    if (account != null) _pushedAccount = account;
    final loading = _accountLoading ??= () async {
      do {
        final pushed = _pushedAccount;
        _pushedAccount = null;
        await _loadAccount(
          reviewInvitations: reviewInvitations,
          account: pushed,
        );
      } while (mounted && _pushedAccount != null);
    }().whenComplete(() => _accountLoading = null);
    return loading.then((_) async {
      if (mounted &&
          _error == null &&
          reviewInvitations &&
          !offlineStatus.value) {
        await _reviewInvitations();
      }
    });
  }

  Future<void> _loadAccount({
    bool reviewInvitations = true,
    Map<String, dynamic>? account,
  }) async {
    // This cache chooses public browsing only. It never authorizes a mutation,
    // exposes account data, or substitutes for authenticated /me responses.
    final browseKey =
        'browse-households|$apiStorageNamespace|${widget.user.uid}';
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
        if (await _local!.cached('/households/$id/recipe-blank') != null &&
            await _local!.cached('/households/$id/meal-plan') != null) {
          _readyHouseholds.add(id);
        }
      }
      if (mounted) setState(() => _databaseChecking = false);
    }
    await _perform(() async {
      final data =
          account ??
          (_local == null
              ? await _request('/me')
              : await _local!.request('/me'));
      if (!mounted) return;
      if (widget.request != null) {
        childMode.value = (data['user'] as Map?)?['child_mode'] == true;
      } else {
        await _refreshChildPolicy(data);
      }
      _userId = (data['user'] as Map?)?['id'] as String?;
      _displayName = (data['user'] as Map?)?['display_name'] as String?;
      if (_displayName != null && _households.isEmpty) {
        _personName.text = _displayName!;
      }
      _administrator =
          (data['user'] as Map?)?['account_role'] == 'administrator';
      final households = List<Map<String, dynamic>>.from(
        data['households'] as List,
      );
      if (!mounted) return;
      _households = households;
      _syncStatusChanged();
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
      await _loadPeople();
    });
    _sharedRecipeChanged();
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
      if (widget.request != null) {
        _households.add(household);
      } else {
        final account = _api.liveConnection?.data['account'] as Map?;
        if (account != null) {
          await _load(
            reviewInvitations: false,
            account: Map<String, dynamic>.from(account),
          );
        }
      }
      _selected = household['id'] as String;
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

  Future<void> _refreshChildPolicy([Map<String, dynamic>? account]) async {
    try {
      final policy =
          account != null && account.containsKey('people_child_modes')
          ? {
              'enabled': (account['user'] as Map)['child_mode'],
              'people_child_modes': account['people_child_modes'],
            }
          : {
              'enabled':
                  (account?['user'] as Map?)?['child_mode'] ?? childMode.value,
              'people_child_modes': account?['people_child_modes'] ?? {},
            };
      if (!mounted) return;
      childMode.value = policy['enabled'] == true;
      if (policy['people_child_modes'] is Map) {
        final flags = policy['people_child_modes'] as Map;
        setState(() {
          _peopleChildModes
            ..clear()
            ..addAll(
              flags.map((id, enabled) => MapEntry('$id', enabled == true)),
            );
        });
      }
      try {
        await writeOfflineStore(
          'ctr-child-mode:${widget.user.uid}',
          '${childMode.value}',
        );
        await writeOfflineStore(
          'ctr-people-child-modes:${widget.user.uid}',
          jsonEncode(_peopleChildModes),
        );
      } catch (_) {}
    } catch (_) {
      /* Retain this device's last confirmed policy offline. */
    }
  }

  String get _sectionKey =>
      'ctr-last-section-v1:$apiStorageNamespace|${widget.user.uid}';
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
    if (widget.request == null) {
      try {
        final saved = await readOfflineStore(
          'ctr-people-child-modes:${widget.user.uid}',
        ).timeout(const Duration(seconds: 2));
        if (saved != null) {
          _peopleChildModes.addAll(
            (jsonDecode(saved) as Map).map(
              (id, enabled) => MapEntry('$id', enabled == true),
            ),
          );
        }
      } catch (_) {
        /* Keep account-policy badges at their last confirmed values. */
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
    if (_selected == null) return;
    await connectionNotice(context, 'add');
    if (!mounted) return;
    mealPlanNotices.dismiss();
    final householdId = _selected!;
    final saved = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeImport(
          householdId: householdId,
          request: (path, body) async {
            final data = await _request(path, body: body);
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
      if (saved['_offline_pending'] != true &&
          saved['source_type'] == 'ai_created') {
        await Navigator.push<void>(
          context,
          MaterialPageRoute(
            builder: (_) => RecipeDetail(
              householdId: householdId,
              recipeId: saved['id'].toString(),
              title: saved['title'] as String,
              request: (path) => _request(path),
              cachedRequest: _cachedRead,
              localRead: _local?.readView,
              save: _saveRecipe,
              menuBuilder: _buildMenu,
              onViewMealPlan: _openMealPlan,
              onChanged: () {
                if (mounted) setState(() => _recipeRefresh++);
              },
            ),
          ),
        );
      }
    }
  }

  void _leaveMenu() {
    mealPlanNotices.dismiss();
    final navigator = Navigator.of(context);
    navigator.pop(); // Close the current route's drawer first.
    navigator.popUntil((route) => route.isFirst);
  }

  void _openRecipeBrowser() {
    if (!mounted) return;
    mealPlanNotices.dismiss();
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      _settings = false;
      _shopping = false;
      _planning = false;
      _recipeRefresh++;
      _rememberSection('recipes');
    });
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
    cookingMenuBuilder = _buildMenu;
    cookingRecipeBrowser = _openRecipeBrowser;
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
                        : () async {
                            _leaveMenu();
                            await connectionNotice(context, 'shopping');
                            if (!mounted) return;
                            setState(() {
                              _rememberSection('shopping');
                              _shopping = true;
                              _planning = false;
                              _shoppingOpened = true;
                              _settings = false;
                            });
                          },
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.settings_outlined),
                    title: const Text('Settings'),
                    onTap: () {
                      Navigator.of(menuContext).pop();
                      _openSettings();
                      if (!_busy) _perform(_loadPeople);
                    },
                  ),
                  if (_administrator && !childMode.value)
                    ListTile(
                      leading: const Icon(Icons.admin_panel_settings_outlined),
                      title: const Text('Administration'),
                      onTap: () {
                        Navigator.of(menuContext).pop();
                        _openAdministration();
                      },
                    ),
                  CookingSessionMenu(menuBuilder: _buildMenu),
                ],
              ),
            ),
            const AppVersionLabel(),
          ],
        ),
      ),
    );
  }

  final _settingsChanges = ValueNotifier<int>(0);

  Future<void> _openSettings() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (routeContext) => ValueListenableBuilder<int>(
          valueListenable: _settingsChanges,
          builder: (_, value, child) => Scaffold(
            appBar: AppBar(
              title: const Text('Settings'),
              leading: const RecipeMenuLeading(),
              leadingWidth: 96,
            ),
            drawer: _buildMenu(routeContext),
            body: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    ListTile(
                      title: Text(
                        _households
                                    .where((h) => h['id'] == _selected)
                                    .firstOrNull?['name']
                                as String? ??
                            'Household',
                        style: Theme.of(routeContext).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 24),
                      child: Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.people_outline),
                            title: const Text('Household members'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(routeContext).push<void>(
                              MaterialPageRoute(
                                builder: (_) => ValueListenableBuilder<int>(
                                  valueListenable: _settingsChanges,
                                  builder: (context, value, child) => Scaffold(
                                    appBar: AppBar(
                                      title: const Text('Household members'),
                                      leading: const RecipeMenuLeading(),
                                      leadingWidth: 96,
                                    ),
                                    drawer: _buildMenu(context),
                                    body: Center(
                                      child: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 720,
                                        ),
                                        child: ListView(
                                          padding: const EdgeInsets.all(16),
                                          children: [
                                            _householdSettings(context),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_selected != null && !childMode.value)
                            WorkCalendarSetting(
                              key: ValueKey('work-calendar-$_selected'),
                              householdId: _selected!,
                              request: _request,
                              save: _saveRecipe,
                            ),
                          ..._householdControls(routeContext),
                        ],
                      ),
                    ),
                    const Divider(),
                    const ListTile(title: Text('This device')),
                    ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: const Text('Error log'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(routeContext).push<void>(
                        MaterialPageRoute(
                          builder: (_) => const ClientLogScreen(),
                        ),
                      ),
                    ),
                    if (!childMode.value) const DinnerTimeSetting(),
                    if (NativeTimers.supported && !childMode.value) ...[
                      ListTile(
                        leading: const Icon(Icons.notifications_outlined),
                        title: const Text('Notifications'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(routeContext).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const NotificationSettingsScreen(),
                          ),
                        ),
                      ),
                      ListTile(
                        leading: const Icon(Icons.alarm_outlined),
                        title: const Text('Cooking timers'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(routeContext).push<void>(
                          MaterialPageRoute(
                            builder: (_) => const TimerSettings(),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _householdControls(BuildContext context) {
    childModeOf(context);
    final selected = _households.where((h) => h['id'] == _selected).firstOrNull;
    return [
      ListTile(
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
                      request: (path, {body}) => _request(path, body: body),
                    ),
                  ),
                );
                if (mounted) setState(() => _shoppingRefresh++);
              },
      ),
      ListTile(
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
    ];
  }

  Widget _householdSettings(BuildContext context) {
    childModeOf(context);
    final selected = _households.where((h) => h['id'] == _selected).firstOrNull;
    final canAdd =
        !childMode.value &&
        selected != null &&
        ['owner', 'admin'].contains(selected['role']);
    return Card(
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
                decoration: const InputDecoration(labelText: 'Display name'),
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
                  trailing: _canEditMember(person)
                      ? IconButton(
                          tooltip: 'Edit display name',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: _busy || _accountBusy
                              ? null
                              : () => _changeMemberName(context, person),
                        )
                      : null,
                  title: Row(
                    children: [
                      Flexible(child: Text(person['display_name'] as String)),
                      if (person['user_id'] != null &&
                          (_peopleChildModes[person['id']] ??
                                  person['child_mode']) ==
                              true) ...[
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
            ],
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
    final name = _name;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _planning
              ? 'Meal planner'
              : _shopping
              ? 'Shopping list'
              : _settings
              ? 'Household members'
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
          ConnectionIndicator(householdId: _selected ?? ''),
          AccountMenu(
            name: name,
            email: widget.user.email,
            enabled: !_accountBusy,
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
              if (value == 'name') _changeName();
              if (value == 'logout') _logOut();
            },
          ),
        ],
      ),
      drawer: _buildMenu(context),
      body: Column(
        children: [
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
                      children: [_householdSettings(context)],
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
                      server: apiStorageNamespace,
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
