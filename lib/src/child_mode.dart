import 'package:flutter/material.dart';

final childMode = ValueNotifier<bool>(false);

bool childModeWriteAllowed(String path) =>
    path == '/me/child-mode' ||
    RegExp(r'^/households/[^/]+/recipes/[^/]+/favorites$').hasMatch(path);

void requireChildModeWrite(String path) {
  if (childMode.value && !childModeWriteAllowed(path)) {
    throw StateError('Child mode allows viewing and favorites only.');
  }
}

Future<void> changeChildMode(
  BuildContext context,
  Future<Map<String, dynamic>> Function(Map<String, dynamic>) save,
) async {
  final enabling = !childMode.value;
  final pin = TextEditingController();
  final confirm = TextEditingController();
  String? error;
  var busy = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: Text(enabling ? 'Enable child mode' : 'Disable child mode'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 8,
              enabled: !busy,
              decoration: const InputDecoration(labelText: 'PIN (4–8 digits)'),
            ),
            if (enabling)
              TextField(
                controller: confirm,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                enabled: !busy,
                decoration: const InputDecoration(labelText: 'Confirm PIN'),
              ),
            if (error != null) Text(error!),
          ],
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    if (!RegExp(r'^[0-9]{4,8}$').hasMatch(pin.text) ||
                        (enabling && pin.text != confirm.text)) {
                      update(
                        () => error = 'Enter matching PINs of 4 to 8 digits.',
                      );
                      return;
                    }
                    update(() {
                      busy = true;
                      error = null;
                    });
                    try {
                      final result = await save({
                        'enabled': enabling,
                        'pin': pin.text,
                      });
                      childMode.value = result['enabled'] == true;
                      if (context.mounted) Navigator.pop(context);
                    } catch (_) {
                      if (context.mounted) {
                        update(() {
                          busy = false;
                          error = 'Could not change child mode. Check the PIN and connection.';
                        });
                      }
                    }
                  },
            child: Text(enabling ? 'Enable' : 'Disable'),
          ),
        ],
      ),
    ),
  );
  // Controllers remain alive through the dialog's closing animation.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  pin.dispose();
  confirm.dispose();
}

class ChildModeScope extends InheritedNotifier<ValueNotifier<bool>> {
  ChildModeScope({super.key, required super.child})
    : super(notifier: childMode);
}

bool childModeOf(BuildContext context) {
  context.dependOnInheritedWidgetOfExactType<ChildModeScope>();
  return childMode.value;
}
