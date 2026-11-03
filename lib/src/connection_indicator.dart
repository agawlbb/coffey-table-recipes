import 'package:flutter/material.dart';

// Updated from the same household sockets used by the account header.
final connectedHouseholds = ValueNotifier<Set<String>>({});

class ConnectionIndicator extends StatelessWidget {
  const ConnectionIndicator({super.key, required this.householdId});
  final String householdId;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Set<String>>(
    valueListenable: connectedHouseholds,
    builder: (_, households, child) => households.contains(householdId)
        ? const Padding(
            padding: EdgeInsets.only(right: 4),
            child: Icon(Icons.cloud_done, color: Colors.green, size: 18),
          )
        : const SizedBox.shrink(),
  );
}
