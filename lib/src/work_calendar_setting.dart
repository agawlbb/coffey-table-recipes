import 'package:flutter/material.dart';

import 'api.dart';
import 'local_data.dart';
import 'recipe_browser.dart';
import 'recipe_editor.dart';

class WorkCalendarSetting extends StatefulWidget {
  const WorkCalendarSetting({
    super.key,
    required this.householdId,
    required this.request,
    required this.save,
  });
  final String householdId;
  final RecipeRequest request;
  final RecipeSave save;
  @override
  State<WorkCalendarSetting> createState() => _WorkCalendarSettingState();
}

class _WorkCalendarSettingState extends State<WorkCalendarSetting> {
  String _color = '#E09F3E';
  String? _error;
  String get _path => '/households/${widget.householdId}/work-calendar';
  @override
  void initState() {
    super.initState();
    localDataChanges.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    localDataChanges.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (localDataChanges.value.startsWith(_path)) _load();
  }

  Future<void> _load() async {
    try {
      final state = await widget.request(_path);
      final color = state['color']?.toString();
      if (mounted &&
          color != null &&
          RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
        setState(() {
          _color = color;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : 'Could not load the workday color. Reopen Settings to retry.',
        );
      }
    }
  }

  Future<void> _choose() async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Workday color'),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final entry in const {
                  'Amber': '#E09F3E',
                  'Blue': '#1976D2',
                  'Green': '#388E3C',
                  'Purple': '#7B1FA2',
                  'Red': '#D32F2F',
                  'Teal': '#00796B',
                  'Pink': '#C2185B',
                  'Gray': '#616161',
                }.entries)
                  Semantics(
                    selected: entry.value == _color,
                    child: IconButton(
                      tooltip: entry.key,
                      icon: Icon(
                        Icons.circle,
                        color: Color(
                          0xff000000 |
                              int.parse(entry.value.substring(1), radix: 16),
                        ),
                        size: 36,
                      ),
                      onPressed: () => Navigator.pop(context, entry.value),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (chosen == null || !mounted) return;
    try {
      await widget.save(_path, {'color': chosen});
      if (mounted) {
        setState(() {
          _color = chosen;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException ? error.message : 'Could not save the workday color. Select the color again to retry.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    title: const Text('Workday color'),
    subtitle: _error == null ? null : Text(_error!),
    trailing: Icon(
      Icons.circle,
      color: Color(0xff000000 | int.parse(_color.substring(1), radix: 16)),
    ),
    onTap: _choose,
  );
}
