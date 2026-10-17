import 'package:flutter/material.dart';

bool recipePersonFavorite(Map<String, dynamic> person) =>
    person['favorite'] == true ||
    person['favorite'] == 1 ||
    person['favorite'] == '1';

Future<List<Map<String, dynamic>>?> chooseHouseholdFavorites(
  BuildContext context,
  List<Map<String, dynamic>> members,
) {
  final people = members.map((p) => Map<String, dynamic>.from(p)).toList();
  return showDialog<List<Map<String, dynamic>>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('Household favorites'),
        content: SizedBox(
          width: 360,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final person in people)
                  CheckboxListTile(
                    title: Text('${person['display_name']}'),
                    value: recipePersonFavorite(person),
                    onChanged: (value) =>
                        update(() => person['favorite'] = value == true),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, people),
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
}
