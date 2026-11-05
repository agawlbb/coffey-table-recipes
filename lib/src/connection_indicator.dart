import 'package:flutter/material.dart';

// Updated from the same household sockets used by the account header.
final connectedHouseholds = ValueNotifier<Set<String>>({});

// The active account's durable queue, shared by every screen's indicator.
final pendingSyncMessage = ValueNotifier<String?>(null);

class ConnectionIndicator extends StatelessWidget {
  const ConnectionIndicator({super.key, required this.householdId});
  final String householdId;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Set<String>>(
    valueListenable: connectedHouseholds,
    builder: (_, households, _) {
      if (householdId.isEmpty) return const SizedBox.shrink();
      final connected = households.contains(householdId);
      final label = connected
          ? 'Connected to server'
          : 'Not connected to server';
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Tooltip(
          message: label,
          child: Icon(
            connected ? Icons.cloud_done : Icons.cloud_off_outlined,
            color: connected ? Colors.green : Colors.orange,
            size: 18,
            semanticLabel: label,
          ),
        ),
      );
    },
  );
}
