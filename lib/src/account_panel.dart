import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'administration.dart';
import 'administration_window.dart';
import 'auth.dart';
import 'email_access.dart';
import 'invitation_dialogs.dart';
import 'invitation_entry.dart';
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
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final user = snapshot.data;
        if (user != null) {
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
                const Text(
                  'Sign in to bring your household’s recipes and dinner plans together.',
                ),
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
  });
  final Future<void> Function()? signOut;
  final Future<Map<String, dynamic>> Function(
    String path, {
    Map<String, dynamic>? body,
  })?
  request;
  final User user;
  @override
  State<HouseholdPanel> createState() => _HouseholdPanelState();
}

class _HouseholdPanelState extends State<HouseholdPanel> {
  final _api = RecipeApi(baseUrl: apiBaseUrl);
  final _householdName = TextEditingController();
  final _personName = TextEditingController();
  List<Map<String, dynamic>> _households = [];
  List<Map<String, dynamic>> _people = [];
  String? _selected;
  String? _error;
  bool _settings = false;
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
    super.dispose();
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (widget.request != null) return widget.request!(path, body: body);
    final token = await widget.user.getIdToken();
    if (token == null) throw ApiException(401, 'Please sign in again.');
    try {
      return await _api.request(
        path,
        token,
        body: body,
        timeout: Duration(seconds: path.startsWith('/admin/') ? 60 : 20),
      );
    } on ApiException catch (error) {
      if (error.status != 401) rethrow;
      final refreshed = await widget.user.getIdToken(true);
      if (refreshed == null) rethrow;
      return _api.request(
        path,
        refreshed,
        body: body,
        timeout: Duration(seconds: path.startsWith('/admin/') ? 60 : 20),
      );
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

  Future<void> _load({bool reviewInvitations = true}) async {
    await _perform(() async {
      if (widget.request == null && _entryReturnedFromVerification) {
        await widget.user.reload();
        await widget.user.getIdToken(true);
      }
      final data = await _request('/me');
      _userId = (data['user'] as Map?)?['id'] as String?;
      _administrator =
          (data['user'] as Map?)?['account_role'] == 'administrator';
      final households = List<Map<String, dynamic>>.from(
        data['households'] as List,
      );
      if (!mounted) return;
      _households = households;
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
    if (mounted && _error == null && reviewInvitations) {
      await _reviewInvitations();
    }
  }

  bool get _entryReturnedFromVerification =>
      kIsWeb && Uri.base.queryParameters['account'] == 'signin';

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
        title: Text(_settings ? 'Household & people' : 'Recipes'),
        actions: [
          if (MediaQuery.sizeOf(context).width >= 600)
            Center(
              child: SizedBox(
                width: 120,
                child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ),
          PopupMenuButton<String>(
            tooltip: 'User menu',
            enabled: !_accountBusy,
            position: PopupMenuPosition.under,
            onSelected: (value) {
              if (value == 'name') _changeDisplayName();
              if (value == 'tableName') _changeTableName();
              if (value == 'administration') _openAdministration();
              if (value == 'logout') _logOut();
              if (value == 'household') {
                setState(() => _settings = true);
                if (!_busy) _perform(_loadPeople);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem<String>(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.titleSmall),
                    if (widget.user.email != null) Text(widget.user.email!),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'tableName',
                enabled: !_busy && _ownPerson != null,
                child: const ListTile(
                  leading: Icon(Icons.badge_outlined),
                  title: Text('Change name at the table'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'name',
                child: ListTile(
                  leading: Icon(Icons.person_outline),
                  title: Text('Change account display name'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuItem(
                value: 'household',
                child: ListTile(
                  leading: Icon(Icons.people_outline),
                  title: Text('Household & people'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              if (_administrator)
                const PopupMenuItem(
                  value: 'administration',
                  child: ListTile(
                    leading: Icon(Icons.admin_panel_settings_outlined),
                    title: Text('Administration'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: ListTile(
                  leading: Icon(Icons.logout),
                  title: Text('Log out'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
            icon: CircleAvatar(
              radius: 16,
              child: Text(
                name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
              ),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.local_dining_outlined),
                title: Text('Coffey Table'),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('Recipes'),
                selected: !_settings,
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _settings = false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.settings_outlined),
                title: const Text('Household & people'),
                selected: _settings,
                onTap: () {
                  Navigator.pop(context);
                  setState(() => _settings = true);
                  _perform(_loadPeople);
                },
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(
        index: _settings ? 1 : 0,
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
                      TextButton(onPressed: _load, child: const Text('Retry')),
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
                  key: ValueKey(_selected),
                  embedded: true,
                  householdId: _selected!,
                  householdName: selected['name'] as String,
                  request: (path) => _request(path),
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
