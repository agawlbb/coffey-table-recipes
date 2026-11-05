import 'package:flutter/material.dart';

// Updated from the same household sockets used by the account header.
final connectedHouseholds = ValueNotifier<Set<String>>({});

// The active account's durable queue, shared by every screen's indicator.
final pendingSyncMessage = ValueNotifier<String?>(null);

class ConnectionIndicator extends StatelessWidget {
  const ConnectionIndicator({super.key, required this.householdId});
  final String householdId;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([connectedHouseholds, pendingSyncMessage]),
    builder: (_, _) {
      final pending = pendingSyncMessage.value;
      if (!connectedHouseholds.value.contains(householdId) && pending == null) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Tooltip(
          message: pending ?? 'Matches last confirmed server data',
          child: Icon(
            pending == null ? Icons.cloud_done : Icons.cloud_upload_outlined,
            color: pending == null ? Colors.green : Colors.orange,
            size: 18,
            semanticLabel: pending ?? 'Matches last confirmed server data',
          ),
        ),
      );
    },
  );
}
