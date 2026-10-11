import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'recipe_browser.dart';
import 'offline_recipes.dart';

typedef RecipeSave = Future<Map<String, dynamic>> Function(
  String path,
  Map<String, dynamic> body,
);

class RecipeEditor extends StatefulWidget {
  const RecipeEditor({
    super.key,
    required this.recipe,
    required this.householdId,
    required this.save,
    this.pickImage,
  });
  final Map<String, dynamic> recipe;
  final String householdId;
  final RecipeSave save;
  final Future<XFile?> Function(ImageSource source)? pickImage;
  @override
  State<RecipeEditor> createState() => _RecipeEditorState();
}

class _RecipeEditorState extends State<RecipeEditor> {
  final _form = GlobalKey<FormState>();
  late final Map<String, dynamic> _draft;
  bool _dirty = false, _saving = false, _picking = false, _leaving = false;
  String? _error;
  String? _photoError;
  bool _revealingErrors = false;
  AnimationStyle? get _expansionStyle =>
      _revealingErrors ? AnimationStyle.noAnimation : null;
  int _nextId = 0;
  final _sections = <String, GlobalKey>{};
  final _expansions = <String, ExpansibleController>{};
  final _fields = <String, GlobalKey<FormFieldState<String>>>{};
  ExpansibleController _controller(String key) =>
      _expansions.putIfAbsent(key, ExpansibleController.new);

  Future<void> _jumpTo(String title) async {
    _controller(title).expand();
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final target = _sections[title]?.currentContext;
    if (target != null && target.mounted) {
      await Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 250),
        alignment: 0,
      );
    }
  }

  String _id() => 'new-${_nextId++}';
  List<Map<String, dynamic>> _rows(String key) =>
      (_draft[key] as List).cast<Map<String, dynamic>>();
  List<Map<String, dynamic>> _options(String key) =>
      recipeRows((_draft['edit_options'] as Map?)?[key]);
  @override
  void initState() {
    super.initState();
    _draft = jsonDecode(jsonEncode(widget.recipe)) as Map<String, dynamic>;
    for (final key in [
      'ingredients',
      'groups',
      'steps',
      'actions',
      'photos',
      'tags',
      'pairings',
      'category_assignments',
    ]) {
      _draft[key] ??= <Map<String, dynamic>>[];
    }
    for (final key in ['tags', 'category_assignments']) {
      for (final row in _rows(key)) {
        row['_key'] = _id();
      }
    }
    _draft['original_language'] ??= 'en';
    _draft['measurement_system'] ??= 'unspecified';
    offlineStatus.addListener(_connectionChanged);
    _recoverPhoto();
  }

  void _connectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    offlineStatus.removeListener(_connectionChanged);
    for (final controller in _expansions.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _recoverPhoto() async {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        widget.pickImage != null) {
      return;
    }
    try {
      final lost = await ImagePicker().retrieveLostData();
      if (lost.files?.isNotEmpty == true) await _acceptPhoto(lost.files!.first);
      if (lost.exception != null && mounted) {
        setState(
          () => _error =
              'The camera photo could not be recovered. Please try again.',
        );
      }
    } catch (_) {
      /* Recovery is unavailable on some platforms. */
    }
  }

  void _change(void Function() action) => setState(() {
    action();
    _dirty = true;
    _error = null;
  });
  Future<void> _close() async {
    if (_saving || _picking) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text('Your recipe changes have not been saved.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep editing'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    if (!mounted) return;
    setState(() => _leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) {
      final field = _fields.values
          .where((key) => key.currentState?.hasError == true)
          .firstOrNull;
      final ancestors = <ExpansibleController>[];
      field?.currentContext?.visitAncestorElements((element) {
        final widget = element.widget;
        if (widget is ExpansionTile && widget.controller != null) {
          ancestors.add(widget.controller!);
        }
        return true;
      });
      setState(() {
        _error = 'Check the highlighted fields before saving.';
        _revealingErrors = true;
      });
      // Hidden nested tiles pause their animations. Reveal the error's path
      // without animation so its final geometry is ready before scrolling.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      for (final controller in ancestors.reversed) {
        controller.expand();
      }
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final target = field?.currentContext;
      if (target != null && target.mounted) {
        await Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 250),
          alignment: .15,
        );
      }
      if (mounted) setState(() => _revealingErrors = false);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = await widget.save(
        '/households/${widget.householdId}/recipes${_draft['id'] == null ? '' : '/${_draft['id']}'}',
        _draft,
      );
      if (!mounted) return;
      setState(() {
        _leaving = true;
        _dirty = false;
        _saving = false;
      });
      Navigator.pop(context, data['recipe'] as Map<String, dynamic>);
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = error is ApiException ? error.message : 'Could not save the recipe. Check your connection and try again. Your changes are still here.';
        });
      }
    }
  }

  Future<void> _acceptPhoto(XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      throw const FormatException('Choose a photo smaller than 5 MB.');
    }
    if (!mounted) return;
    _change(
      () => _rows('photos').add({
        'id': _id(),
        'image_base64': base64Encode(bytes),
        'is_cover': _rows('photos').isEmpty ? 1 : 0,
      }),
    );
  }

  Future<void> _photo(ImageSource source) async {
    setState(() {
      _picking = true;
      _error = null;
      _photoError = null;
    });
    try {
      final file =
          await (widget.pickImage?.call(source) ??
              ImagePicker().pickImage(
                source: source,
                maxWidth: 2400,
                maxHeight: 2400,
                imageQuality: 85,
              ));
      if (file != null) await _acceptPhoto(file);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException ? error.message : 'Could not open the photo picker or camera. Check device permissions and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _generatePhoto() async {
    if (_picking || _saving || _rows('photos').isNotEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _picking = true;
      _error = null;
      _photoError = null;
    });
    try {
      final data = await widget.save(
        '/households/${widget.householdId}/recipe-photo',
        {
          'recipe': {
            if (_draft['id'] != null) 'id': _draft['id'],
            'title': _draft['title'],
            'ingredients': _rows('ingredients')
                .map((r) => {'original_text': r['original_text']})
                .toList(),
            'steps': _rows('steps')
                .map((r) => {'instruction': r['instruction']})
                .toList(),
            'photos': [],
          },
        },
      );
      final photo = data['photo'] as Map<String, dynamic>;
      final encoded = photo['image_base64'] as String;
      if (encoded.isEmpty || encoded.length > 7000000) {
        throw const FormatException('AI returned an invalid photo.');
      }
      if (!mounted) return;
      _change(
        () => _rows('photos').add({...photo, 'id': _id(), 'is_cover': 1}),
      );
    } catch (error) {
      if (mounted) {
        setState(
          () => _photoError = error is ApiException
              ? error.message
              : 'Could not generate a photo. Your recipe is still here.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Widget _field(
    Map<String, dynamic> row,
    String key,
    String label, {
    bool required = false,
    int lines = 1,
    String? numeric,
    int? maxLength,
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      key: _fields.putIfAbsent(
        '${identityHashCode(row)}-$key',
        () => GlobalKey<FormFieldState<String>>(),
      ),
      initialValue: row[key]?.toString() ?? '',
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: lines > 1,
        hintText: hint,
      ),
      minLines: lines,
      maxLines: lines > 1 ? lines + 3 : 1,
      keyboardType: numeric != null
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : lines > 1
          ? TextInputType.multiline
          : TextInputType.text,
      validator: (value) {
        final text = value?.trim() ?? '';
        if (required && text.isEmpty) return 'Enter $label';
        if (maxLength != null && text.length > maxLength) {
          return 'Use at most $maxLength characters';
        }
        if (key == 'quantity_decimal' ||
            key == 'quantity_numerator' ||
            key == 'quantity_denominator') {
          final decimal = row['quantity_decimal']?.toString().trim() ?? '';
          final numerator = row['quantity_numerator']?.toString().trim() ?? '';
          final denominator =
              row['quantity_denominator']?.toString().trim() ?? '';
          if (decimal.isNotEmpty &&
              (numerator.isNotEmpty || denominator.isNotEmpty)) {
            return 'Use decimal OR fraction; clear the other quantity fields.';
          }
          if (numerator.isNotEmpty != denominator.isNotEmpty ||
              (denominator.isNotEmpty &&
                  (num.tryParse(denominator) ?? 0) <= 0)) {
            return 'Enter both fraction fields with a denominator greater than zero.';
          }
        }
        if (text.isEmpty || numeric == null) return null;
        final number = num.tryParse(text);
        if (number == null ||
            !number.isFinite ||
            (numeric == 'positive' && number <= 0) ||
            (numeric == 'nonnegative' && number < 0) ||
            (numeric == 'integer' && !RegExp(r'^\d+$').hasMatch(text))) {
          return 'Enter a valid ${numeric == 'integer' ? 'whole number' : 'number'}';
        }
        return null;
      },
      onChanged: (value) {
        _change(() => row[key] = value.trim().isEmpty ? null : value);
      },
    ),
  );
  bool _bool(Object? value) => value == true || value == 1 || value == '1';
  Widget _toggle(Map<String, dynamic> row, String key, String label) =>
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        value: _bool(row[key]),
        onChanged: (value) => _change(() => row[key] = value),
      );
  Widget _choice(
    Map<String, dynamic> row,
    String key,
    String label,
    Map<String, String> options, {
    bool nullable = false,
  }) {
    final value = row[key]?.toString();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: DropdownButtonFormField<String>(
        key: _fields.putIfAbsent(
          '${identityHashCode(row)}-$key-$value',
          () => GlobalKey<FormFieldState<String>>(),
        ),
        initialValue: options.containsKey(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          if (nullable) const DropdownMenuItem(value: '', child: Text('None')),
          ...options.entries.map(
            (e) => DropdownMenuItem(
              value: e.key,
              child: Text(e.value, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (value) => _change(() {
          row[key] = value == '' ? null : value;
          if (key == 'action_type') {
            final timed = ['timer', 'rest'].contains(value);
            final temperature = [
              'appliance_temperature',
              'internal_temperature',
            ].contains(value);
            row['duration_seconds'] = timed ? 60 : null;
            row['temperature_value'] = null;
            row['temperature_unit'] = temperature ? 'F' : null;
          }
        }),
        validator: nullable
            ? null
            : (value) =>
                  value == null || value.isEmpty ? 'Choose $label' : null,
      ),
    );
  }

  Widget _section(
    String title,
    IconData icon,
    List<Widget> children, {
    bool open = false,
    String? subtitle,
  }) => Card(
    key: _sections.putIfAbsent(title, GlobalKey.new),
    margin: const EdgeInsets.only(bottom: 16),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      maintainState: true,
      controller: _controller(title),
      expansionAnimationStyle: _expansionStyle,
      initiallyExpanded: open,
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primary
            .withValues(alpha: .09),
        child: Icon(icon, color: Theme.of(context).colorScheme.primary),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: subtitle == null ? null : Text(subtitle),
      childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: children,
    ),
  );
  Widget _columns(List<Widget> children, {double minWidth = 220}) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final count = (constraints.maxWidth / minWidth).floor().clamp(
            1,
            children.length,
          );
          final width = (constraints.maxWidth - 12 * (count - 1)) / count;
          return Wrap(
            spacing: 12,
            children: [
              for (final child in children)
                SizedBox(width: width, child: child),
            ],
          );
        },
      );

  Widget _help(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
    ),
  );
  Widget _add(String label, VoidCallback action) => Align(
    alignment: Alignment.centerLeft,
    child: OutlinedButton.icon(
      onPressed: action,
      icon: const Icon(Icons.add),
      label: Text(label),
    ),
  );
  void _move(
    List<Map<String, dynamic>> rows,
    Map<String, dynamic> row,
    int target,
  ) {
    final source = row.containsKey('step_id') ? _rows('actions') : rows;
    final neighbor = rows[target];
    final before = target < rows.indexOf(row);
    source.remove(row);
    final index = source.indexOf(neighbor);
    source.insert(before ? index : index + 1, row);
  }

  Widget _item(
    String title,
    List<Map<String, dynamic>> rows,
    Map<String, dynamic> row,
    List<Widget> children, {
    VoidCallback? remove,
    String? preview,
    bool? initiallyExpanded,
    Widget? summary,
  }) {
    final index = rows.indexOf(row);
    return Card(
      key: ValueKey('item-${row['id'] ?? row['_key']}'),
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        maintainState: true,
        controller: _controller('item-${identityHashCode(row)}'),
        expansionAnimationStyle: _expansionStyle,
        initiallyExpanded:
            initiallyExpanded ??
            (row['id']?.toString().startsWith('new-') == true ||
                row['_key'] != null),
        title: Text(title),
        subtitle: summary == null && (preview == null || preview.trim().isEmpty)
            ? null
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (preview != null && preview.trim().isNotEmpty)
                    Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ?summary,
                ],
              ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          ...children,
          const Divider(),
          Row(
            children: [
              IconButton(
                tooltip: 'Move up',
                onPressed: index == 0
                    ? null
                    : () => _change(() {
                        _move(rows, row, index - 1);
                      }),
                icon: const Icon(Icons.arrow_upward, size: 20),
              ),
              IconButton(
                tooltip: 'Move down',
                onPressed: index == rows.length - 1
                    ? null
                    : () => _change(() {
                        _move(rows, row, index + 1);
                      }),
                icon: const Icon(Icons.arrow_downward, size: 20),
              ),
              IconButton(
                tooltip: 'Remove',
                onPressed: () => _change(remove ?? () => rows.remove(row)),
                icon: const Icon(Icons.delete_outline),
              ),
              const Flexible(
                child: Text(
                  'Reorder or remove',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Map<String, String> get _recipeChoices => {
    for (final r in _options('recipes')) '${r['id']}': '${r['title']}',
  };
  Widget _ingredient(Map<String, dynamic> row) => _item(
    row['original_text']?.toString().trim().isNotEmpty == true
        ? row['original_text'].toString()
        : '${row['ingredient_name'] ?? 'New ingredient'}',
    _rows('ingredients'),
    row,
    [
      _field(
        row,
        'original_text',
        'Ingredient line (as displayed)',
        required: true,
        lines: 2,
        hint: 'e.g. 2 cups milk, warmed',
      ),
      _help(
        'This line is shown while viewing and cooking. The fields below describe the ingredient for search and serving adjustments.',
      ),
      _field(
        row,
        'ingredient_name',
        'Ingredient',
        required: true,
        maxLength: 300,
      ),
      _columns([
        _field(row, 'quantity_text', 'Quantity as written', maxLength: 120),
        _field(row, 'original_unit', 'Unit', maxLength: 80),
      ], minWidth: 140),
      _field(
        row,
        'preparation',
        'Preparation (e.g. finely chopped)',
        maxLength: 300,
      ),
      ExpansionTile(
        maintainState: true,
        controller: _controller('ingredient-settings-${identityHashCode(row)}'),
        expansionAnimationStyle: _expansionStyle,
        title: const Text('Grouping & scaling'),
        children: [
          _choice(row, 'group_id', 'Ingredient group', {
            for (final g in _rows('groups'))
              '${g['id']}': '${g['title'] ?? 'New group'}',
          }, nullable: true),
          _toggle(row, 'is_optional', 'Optional ingredient'),
          _toggle(row, 'is_main_ingredient', 'Main ingredient'),
          _toggle(
            row,
            'scale_quantity',
            'Adjust quantity when scaling servings',
          ),
        ],
      ),
      ExpansionTile(
        maintainState: true,
        controller: _controller('quantities-${identityHashCode(row)}'),
        expansionAnimationStyle: _expansionStyle,
        title: const Text('Exact quantities'),
        children: [
          _field(
            row,
            'quantity_decimal',
            'Decimal quantity',
            numeric: 'nonnegative',
          ),
          _field(
            row,
            'quantity_numerator',
            'Fraction numerator',
            numeric: 'integer',
          ),
          _field(
            row,
            'quantity_denominator',
            'Fraction denominator',
            numeric: 'integer',
          ),
          _field(
            row,
            'quantity_max_decimal',
            'Maximum quantity (for ranges)',
            numeric: 'nonnegative',
          ),
          _field(row, 'unit_code', 'Standard unit code', maxLength: 40),
        ],
      ),
    ],
    initiallyExpanded: (row['original_text']?.toString().trim().isEmpty ?? true)
        ? null
        : false,
  );
  Widget _action(Map<String, dynamic> row, List<Map<String, dynamic>> rows) =>
      _item(
        row['label']?.toString() ?? 'Cooking action',
        rows,
        row,
        [
          _choice(row, 'action_type', 'Action type', const {
            'timer': 'Timer',
            'rest': 'Rest',
            'appliance_temperature': 'Appliance temperature',
            'internal_temperature': 'Internal temperature',
            'reminder': 'Reminder',
          }),
          _field(row, 'label', 'Label', maxLength: 300),
          if (['timer', 'rest'].contains(row['action_type']) ||
              row['duration_seconds'] != null)
            _field(
              row,
              'duration_seconds',
              'Duration (seconds)',
              required: ['timer', 'rest'].contains(row['action_type']),
              numeric: 'integer',
            ),
          if ([
                'appliance_temperature',
                'internal_temperature',
              ].contains(row['action_type']) ||
              row['temperature_value'] != null) ...[
            _field(
              row,
              'temperature_value',
              'Temperature',
              required: true,
              numeric: 'number',
            ),
            _choice(row, 'temperature_unit', 'Temperature unit', const {
              'F': 'Fahrenheit (°F)',
              'C': 'Celsius (°C)',
            }),
          ],
          _field(row, 'appliance', 'Appliance', maxLength: 80),
        ],
        initiallyExpanded: false,
        remove: () => _rows('actions').remove(row),
      );
  Widget _step(Map<String, dynamic> row) {
    final actions = _rows('actions')
        .where((a) => a['step_id'] == row['id'])
        .toList();
    return _item(
      'Step ${_rows('steps').indexOf(row) + 1}',
      _rows('steps'),
      row,
      [
        _field(row, 'instruction', 'Instructions', required: true, lines: 3),
        _field(
          row,
          'section_title',
          'Section heading (optional)',
          maxLength: 200,
        ),
        ...actions.map((a) => _action(a, actions)),
        _add(
          'Add action',
          () => _change(
            () => _rows('actions').add({
              'id': _id(),
              'step_id': row['id'],
              'action_type': 'timer',
              'duration_seconds': 60,
            }),
          ),
        ),
      ],
      preview: row['instruction']?.toString(),
      summary: actions.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${actions.length} ${actions.length == 1 ? 'action' : 'actions'}',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  for (final action in actions)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            ['timer', 'rest'].contains(action['action_type'])
                                ? Icons.timer_outlined
                                : action['temperature_value'] != null
                                ? Icons.thermostat
                                : Icons.notifications_outlined,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Expanded(child: Text(_actionSummary(action))),
                        ],
                      ),
                    ),
                ],
              ),
            ),
      initiallyExpanded: false,
      remove: () {
        _rows('actions').removeWhere((a) => a['step_id'] == row['id']);
        _rows('steps').remove(row);
      },
    );
  }

  String _actionSummary(Map<String, dynamic> action) {
    const types = {
      'timer': 'Timer',
      'rest': 'Rest',
      'appliance_temperature': 'Appliance temperature',
      'internal_temperature': 'Internal temperature',
      'reminder': 'Reminder',
    };
    final details = <String>[];
    if (action['label']?.toString().trim().isNotEmpty == true) {
      details.add(action['label'].toString());
    }
    final seconds = int.tryParse('${action['duration_seconds']}');
    if (seconds != null) {
      final minutes = seconds ~/ 60, remainder = seconds % 60;
      details.add(
        minutes == 0
            ? '$seconds sec'
            : '$minutes min${remainder == 0 ? '' : ' $remainder sec'}',
      );
    }
    if (action['temperature_value'] != null) {
      details.add(
        '${recipeValue(action['temperature_value'])}°${action['temperature_unit'] ?? ''}',
      );
    }
    if (action['appliance']?.toString().trim().isNotEmpty == true) {
      details.add(action['appliance'].toString());
    }
    return '${types[action['action_type']] ?? 'Action'}${details.isEmpty ? '' : ': ${details.join(' · ')}'}';
  }

  Widget _photoItem(Map<String, dynamic> row) => _item(
    'Photo ${_rows('photos').indexOf(row) + 1}${_bool(row['is_cover']) ? ' · Cover' : ''}',
    _rows('photos'),
    row,
    [
      SizedBox(
        height: 180,
        width: double.infinity,
        child: row['image_base64'] != null
            ? Image.memory(
                base64Decode(row['image_base64'] as String),
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    const Center(child: Text('Image format not supported')),
              )
            : RecipePhoto(
                url: row['source_url'] as String?,
                fit: BoxFit.contain,
              ),
      ),
      const SizedBox(height: 16),
      _field(row, 'caption', 'Caption', lines: 2),
      _field(row, 'attribution', 'Photo credit', lines: 2),
      RadioGroup<String>(
        groupValue: _rows('photos')
            .where((p) => _bool(p['is_cover']))
            .firstOrNull?['id']
            ?.toString(),
        onChanged: (value) => _change(() {
          for (final p in _rows('photos')) {
            p['is_cover'] = p['id'] == value;
          }
        }),
        child: RadioListTile<String>(
          value: row['id'].toString(),
          title: const Text('Use as cover photo'),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _leaving || (!_dirty && !_saving && !_picking),
    onPopInvokedWithResult: (didPop, result) {
      if (!didPop) _close();
    },
    child: Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _close),
        title: Text(
          _draft['id'] == null
              ? 'Review recipe'
              : MediaQuery.sizeOf(context).width < 480
              ? 'Edit'
              : 'Edit recipe',
        ),
        actions: [
          TextButton(
            onPressed: _saving || _picking ? null : _close,
            child: const Text('Cancel'),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _saving || _picking || offlineStatus.value
                  ? null
                  : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            children: [
              Icon(
                _error != null
                    ? Icons.error_outline
                    : _dirty
                    ? Icons.edit_outlined
                    : Icons.check_circle_outline,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _error ??
                      (_saving
                          ? 'Saving your recipe…'
                          : _dirty
                          ? 'Unsaved changes · Save when you’re ready'
                          : 'No unsaved changes'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _error == null
                        ? null
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _saving,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Form(
              key: _form,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      widget.recipe['title']?.toString() ?? 'Your recipe',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    _help(
                      'Make it your own. Edit a section below, then save your changes together.',
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in const {
                          'Recipe details': 'Details',
                          'Ingredients': 'Ingredients',
                          'Steps & actions': 'Method',
                          'Photos': 'Photos',
                          'Categories & tags': 'Categories',
                          'Notes & source': 'Notes',
                          'Related recipes': 'Related',
                          'Nutrition': 'Nutrition',
                        }.entries)
                          ActionChip(
                            label: Text(entry.value),
                            tooltip: 'Go to ${entry.key.toLowerCase()}',
                            onPressed: () => _jumpTo(entry.key),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    if (offlineStatus.value)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text('Reconnect to save recipe changes.'),
                      ),
                    _section('Recipe details', Icons.restaurant_outlined, [
                      _field(
                        _draft,
                        'title',
                        'Recipe name',
                        required: true,
                        maxLength: 300,
                      ),
                      _field(_draft, 'description', 'Description', lines: 3),
                      _columns([
                        _field(
                          _draft,
                          'servings',
                          'Servings',
                          numeric: 'positive',
                        ),
                        _field(
                          _draft,
                          'yield_text',
                          'Yield (e.g. 12 muffins)',
                          maxLength: 200,
                        ),
                      ]),
                      _columns([
                        _field(
                          _draft,
                          'prep_minutes',
                          'Prep (minutes)',
                          numeric: 'integer',
                        ),
                        _field(
                          _draft,
                          'cook_minutes',
                          'Cook (minutes)',
                          numeric: 'integer',
                        ),
                        _field(
                          _draft,
                          'total_minutes',
                          'Total (minutes)',
                          numeric: 'integer',
                        ),
                      ], minWidth: 150),
                      ExpansionTile(
                        maintainState: true,
                        controller: _controller('recipe-settings'),
                        expansionAnimationStyle: _expansionStyle,
                        tilePadding: EdgeInsets.zero,
                        title: const Text('Language & measurements'),
                        children: [
                          _choice(
                            _draft,
                            'measurement_system',
                            'Measurement system',
                            const {
                              'us': 'US customary',
                              'metric': 'Metric',
                              'mixed': 'Mixed',
                              'unspecified': 'Unspecified',
                            },
                          ),
                          _field(
                            _draft,
                            'original_language',
                            'Original language (e.g. en)',
                            required: true,
                            maxLength: 35,
                          ),
                        ],
                      ),
                    ], open: true),
                    _section('Ingredients', Icons.shopping_basket_outlined, [
                      _help(
                        'Open an ingredient to edit its displayed line, quantities or preparation.',
                      ),
                      ExpansionTile(
                        maintainState: true,
                        controller: _controller('ingredient-groups'),
                        expansionAnimationStyle: _expansionStyle,
                        title: const Text('Ingredient groups'),
                        children: [
                          ..._rows('groups').map(
                            (g) => _item(
                              g['title']?.toString() ?? 'New group',
                              _rows('groups'),
                              g,
                              [
                                _field(
                                  g,
                                  'title',
                                  'Group name',
                                  required: true,
                                  maxLength: 200,
                                ),
                              ],
                              remove: () {
                                for (final i in _rows('ingredients')) {
                                  if (i['group_id'] == g['id']) {
                                    i['group_id'] = null;
                                  }
                                }
                                _rows('groups').remove(g);
                              },
                            ),
                          ),
                          _add(
                            'Add group',
                            () => _change(
                              () =>
                                  _rows('groups')
                                      .add({'id': _id(), 'title': ''}),
                            ),
                          ),
                        ],
                      ),
                      ..._rows('ingredients').map(_ingredient),
                      _add(
                        'Add ingredient',
                        () => _change(
                          () => _rows('ingredients').add({
                            'id': _id(),
                            'ingredient_name': '',
                            'original_text': '',
                            'scale_quantity': true,
                          }),
                        ),
                      ),
                    ], subtitle: '${_rows('ingredients').length} ingredients'),
                    _section('Steps & actions', Icons.format_list_numbered, [
                      _help(
                        'Open a step to edit the instructions. Add timers, temperatures or reminders when helpful.',
                      ),
                      ..._rows('steps').map(_step),
                      _add(
                        'Add step',
                        () => _change(
                          () =>
                              _rows('steps')
                                  .add({'id': _id(), 'instruction': ''}),
                        ),
                      ),
                    ], subtitle: '${_rows('steps').length} steps'),
                    _section(
                      'Photos',
                      Icons.photo_library_outlined,
                      [
                        _help(
                          'Choose a cover for the recipe, then add captions or photo credits.',
                        ),
                        ..._rows('photos').map(_photoItem),
                        Wrap(
                          spacing: 12,
                          children: [
                            OutlinedButton.icon(
                              onPressed:
                                  _picking || _rows('photos').length >= 20
                                  ? null
                                  : () => _photo(ImageSource.gallery),
                              icon: const Icon(Icons.upload_outlined),
                              label: const Text('Upload image'),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  _picking || _rows('photos').length >= 20
                                  ? null
                                  : () => _photo(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('Use camera'),
                            ),
                            if (_rows('photos').isEmpty &&
                                recipeRows(widget.recipe['photos']).isEmpty)
                              OutlinedButton.icon(
                                onPressed: _picking || _saving
                                    ? null
                                    : _generatePhoto,
                                icon: const Icon(Icons.auto_awesome_outlined),
                                label: const Text('Generate AI photo'),
                              ),
                          ],
                        ),
                        if (_picking) const LinearProgressIndicator(),
                        if (_photoError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _photoError!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        if (_rows('photos').isEmpty &&
                            recipeRows(widget.recipe['photos']).isEmpty)
                          _help(
                            'Generate a small illustrative photo from this recipe using paid AI. Review it before saving.',
                          ),
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text(
                            'JPEG, PNG or WebP · up to 5 MB each · 20 photos maximum',
                          ),
                        ),
                      ],
                      subtitle:
                          '${_rows('photos').length} ${_rows('photos').length == 1 ? 'photo' : 'photos'}',
                    ),
                    _section('Categories & tags', Icons.label_outline, [
                      ..._rows('category_assignments').map(
                        (r) => _item(
                          r['label'] == null
                              ? 'Browse category'
                              : '${r['parent_label'] == null || r['parent_label'] == '' ? '' : '${r['parent_label']} / '}${r['label']}',
                          _rows('category_assignments'),
                          r,
                          [
                            if (r['label'] != null) ...[
                              _field(
                                r,
                                'label',
                                'Category name',
                                required: true,
                                maxLength: 120,
                              ),
                              _choice(r, 'parent_label', 'Parent category', {
                                for (final c in _options(
                                  'categories',
                                ).where((c) => c['parent_label'] == null))
                                  '${c['label']}': '${c['label']}',
                              }, nullable: true),
                            ] else
                              _choice(r, 'category_id', 'Category', {
                                for (final c in _options('categories'))
                                  '${c['id']}':
                                      '${c['parent_label'] == null ? '' : '${c['parent_label']} / '}${c['label']}',
                              }),
                          ],
                        ),
                      ),
                      _add(
                        'Add browse category',
                        () => _change(
                          () =>
                              _rows('category_assignments')
                                  .add({'_key': _id()}),
                        ),
                      ),
                      ..._rows('tags').map(
                        (r) => _item(
                          r['label']?.toString() ?? 'New tag',
                          _rows('tags'),
                          r,
                          [
                            _choice(r, 'kind', 'Tag type', const {
                              'cuisine': 'Cuisine',
                              'category': 'Category tag',
                              'technique': 'Technique',
                              'equipment': 'Equipment',
                            }),
                            _field(
                              r,
                              'label',
                              'Tag',
                              required: true,
                              maxLength: 120,
                            ),
                          ],
                        ),
                      ),
                      _add(
                        'Add tag',
                        () => _change(
                          () => _rows('tags').add({
                            '_key': _id(),
                            'kind': 'cuisine',
                            'label': '',
                          }),
                        ),
                      ),
                    ]),
                    _section('Notes & source', Icons.notes_outlined, [
                      _field(_draft, 'notes', 'Recipe notes', lines: 3),
                      _field(
                        _draft,
                        'source_type',
                        'Source type',
                        maxLength: 40,
                      ),
                      _field(
                        _draft,
                        'source_title',
                        'Source title',
                        maxLength: 500,
                      ),
                      _field(
                        _draft,
                        'source_author',
                        'Source author',
                        maxLength: 300,
                      ),
                      _field(
                        _draft,
                        'source_url',
                        'Source URL',
                        maxLength: 4000,
                      ),
                      _field(
                        _draft,
                        'source_reference',
                        'Source reference',
                        lines: 2,
                      ),
                    ]),
                    _section('Related recipes', Icons.link, [
                      _choice(
                        _draft,
                        'parent_recipe_id',
                        'Original recipe (for a variation)',
                        _recipeChoices,
                        nullable: true,
                      ),
                      ..._rows('pairings').map(
                        (r) => _item(
                          r['title']?.toString() ?? 'Pairing',
                          _rows('pairings'),
                          r,
                          [
                            _choice(r, 'id', 'Pairs with', _recipeChoices),
                            _field(r, 'notes', 'Pairing notes', lines: 2),
                          ],
                        ),
                      ),
                      _add(
                        'Add pairing',
                        () => _change(
                          () => _rows('pairings').add({'_key': _id()}),
                        ),
                      ),
                    ]),
                    _section('Nutrition', Icons.monitor_heart_outlined, [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Include nutrition information'),
                        value: _draft['nutrition'] != null,
                        onChanged: (value) => _change(
                          () => _draft['nutrition'] = value
                              ? {
                                  'basis': 'per_serving',
                                  'method': 'manual',
                                  'is_estimate': true,
                                }
                              : null,
                        ),
                      ),
                      if (_draft['nutrition']
                          case final Map<String, dynamic> n) ...[
                        _choice(n, 'basis', 'Nutrition basis', const {
                          'per_serving': 'Per serving',
                          'whole_recipe': 'Whole recipe',
                        }),
                        for (final entry in const {
                          'calories_kcal': 'Calories (kcal)',
                          'protein_g': 'Protein (g)',
                          'carbohydrate_g': 'Carbohydrates (g)',
                          'fat_g': 'Fat (g)',
                          'saturated_fat_g': 'Saturated fat (g)',
                          'fiber_g': 'Fiber (g)',
                          'sugar_g': 'Sugar (g)',
                          'sodium_mg': 'Sodium (mg)',
                        }.entries)
                          _field(
                            n,
                            entry.key,
                            entry.value,
                            numeric: 'nonnegative',
                          ),
                        _field(
                          n,
                          'method',
                          'Calculation method',
                          required: true,
                          maxLength: 100,
                        ),
                        _field(
                          n,
                          'source_reference',
                          'Nutrition source',
                          lines: 2,
                        ),
                        _toggle(n, 'is_estimate', 'Estimated values'),
                        _toggle(
                          _draft,
                          'nutrition_confirmed',
                          'These values apply to the edited recipe',
                        ),
                      ],
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
