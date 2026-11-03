import 'dart:async';

import 'package:flutter/material.dart';

import 'api.dart';
import 'child_mode.dart';
import 'cooking_mode.dart';
import 'cooking_sessions.dart';

WidgetBuilder? cookingMenuBuilder;

void cookingError(BuildContext context, Object error) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        error is ApiException
            ? error.message
            : 'Could not update cooking. Check your connection.',
      ),
    ),
  );
}

Future<void> openCookingSession(
  BuildContext context,
  Map<String, dynamic> session, {
  WidgetBuilder? menuBuilder,
  CookingSessions? sessions,
}) async {
  if (childMode.value) return;
  final coordinator = sessions ?? CookingSessionsScope.of(context);
  try {
    final s = coordinator.joined(session)
        ? session
        : await coordinator.join('${session['id']}');
    if (!context.mounted) return;
    final route = MaterialPageRoute<void>(
      settings: const RouteSettings(name: 'cooking'),
      builder: (_) => CookingMode(
        recipe: Map<String, dynamic>.from(s['recipe'] as Map),
        sessionId: '${s['id']}',
        sessions: coordinator,
        menuBuilder: menuBuilder ?? cookingMenuBuilder,
      ),
    );
    if (ModalRoute.of(context)?.settings.name == 'cooking') {
      final previous = coordinator.visibleSession;
      if (previous != null) {
        unawaited(
          coordinator.presence(previous, false).catchError((Object _) {}),
        );
      }
      await Navigator.of(context).pushReplacement(route);
    } else {
      await Navigator.of(context).push(route);
    }
  } catch (e) {
    if (context.mounted) cookingError(context, e);
  }
}

Future<void> startCooking(
  BuildContext context, {
  required Map<String, dynamic> recipe,
  required String householdId,
  WidgetBuilder? menuBuilder,
}) async {
  if (childMode.value) return;
  final coordinator = CookingSessionsScope.of(context);
  if (!coordinator.available) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Sign in to start cooking.')));
    return;
  }
  try {
    final existing = coordinator.sessions
        .where((s) => '${(s['recipe'] as Map)['id']}' == '${recipe['id']}')
        .toList();
    if (existing.isNotEmpty) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (sheet) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final s in existing)
                ListTile(
                  title: Text(
                    existing.length == 1
                        ? 'Open existing session'
                        : '${(s['recipe'] as Map)['title']} · ${DateTime.fromMillisecondsSinceEpoch(s['created_at'] as int).toLocal().toString().substring(0, 16)}',
                  ),
                  onTap: () => Navigator.pop(sheet, '${s['id']}'),
                ),
              ListTile(
                title: const Text('Start another session'),
                onTap: () => Navigator.pop(sheet, 'new'),
              ),
            ],
          ),
        ),
      );
      if (choice == null || !context.mounted) return;
      if (choice != 'new') {
        await openCookingSession(
          context,
          coordinator.session(choice)!,
          menuBuilder: menuBuilder,
          sessions: coordinator,
        );
        return;
      }
    }
    final s = await coordinator.create(householdId, recipe);
    if (context.mounted) {
      await openCookingSession(
        context,
        s,
        menuBuilder: menuBuilder,
        sessions: coordinator,
      );
    }
  } catch (e) {
    if (context.mounted) cookingError(context, e);
  }
}

class CookingSessionMenu extends StatelessWidget {
  const CookingSessionMenu({
    super.key,
    required this.menuBuilder,
    this.sessions,
  });
  final CookingSessions? sessions;
  CookingSessions get coordinator => sessions ?? cookingSessions;
  final WidgetBuilder menuBuilder;
  Future<void> _share(BuildContext context, String id) async {
    try {
      final people = await coordinator.people(id);
      if (!context.mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        builder: (sheet) => ListView(
          shrinkWrap: true,
          children: [
            const ListTile(title: Text('Share with')),
            if (people.isEmpty)
              const ListTile(title: Text('No other household members')),
            for (final person in people)
              ListTile(
                title: Text('${person['display_name']}'),
                onTap: () async {
                  Navigator.pop(sheet);
                  try {
                    await coordinator.share(id, '${person['id']}');
                  } catch (e) {
                    if (context.mounted) cookingError(context, e);
                  }
                },
              ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) cookingError(context, e);
    }
  }

  Future<bool> _end(BuildContext context, String id) async {
    final session = coordinator.session(id);
    if (session == null || childMode.value) return false;
    final steps = ((session['recipe'] as Map)['steps'] as List? ?? []);
    final completed = (session['completed'] as List? ?? []).toSet();
    final count = steps.where((s) => completed.contains('${s['id']}')).length;
    final hasTimers = coordinator.timers(id).any((t) => t['cancelled'] != true);
    if (hasTimers || (count > 0 && count < steps.length)) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('End cooking session?'),
          content: hasTimers
              ? const Text('Running timers will be canceled.')
              : null,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('End'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return false;
    }
    try {
      await coordinator.end(id);
    } catch (e) {
      if (context.mounted) cookingError(context, e);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: coordinator,
    builder: (context, _) {
      if (childModeOf(context) || coordinator.sessions.isEmpty) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(),
          const ListTile(title: Text('Cooking sessions')),
          for (final session in coordinator.sessions)
            Dismissible(
              key: ValueKey('cooking-session-${session['id']}'),
              confirmDismiss: (_) => _end(context, '${session['id']}'),
              background: Container(
                color: Theme.of(context).colorScheme.errorContainer,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: const Icon(Icons.stop_circle_outlined),
              ),
              secondaryBackground: Container(
                color: Theme.of(context).colorScheme.errorContainer,
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: const Icon(Icons.stop_circle_outlined),
              ),
              child: ListTile(
                title: Text('${(session['recipe'] as Map)['title']}'),
                trailing: Text(coordinator.joined(session) ? 'Open' : 'Join'),
                onTap: () {
                  final navigator = Navigator.of(context);
                  final routeContext = Scaffold.of(context).context;
                  navigator.pop();
                  // Navigate from the page beneath the drawer, retaining its route identity.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (routeContext.mounted) {
                      openCookingSession(
                        routeContext,
                        session,
                        menuBuilder: menuBuilder,
                        sessions: coordinator,
                      );
                    }
                  });
                },
                onLongPress: () => _share(context, '${session['id']}'),
              ),
            ),
        ],
      );
    },
  );
}
