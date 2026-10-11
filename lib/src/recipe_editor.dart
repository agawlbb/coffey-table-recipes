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
  int _nextId = 0;
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
    Navigator.pop(context);
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_form.currentState!.validate()) {
      setState(() => _error = 'Check the highlighted fields before saving.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = await widget.save(
        '/households/${widget.householdId}/recipes/${_draft['id']}',
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

  Widget _field(
    Map<String, dynamic> row,
    String key,
    String label, {
    bool required = false,
    int lines = 1,
    String? numeric,
    int? maxLength,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      key: ValueKey(
        '${row['id'] ?? row['_key'] ?? identityHashCode(row)}-$key',
      ),
      initialValue: row[key]?.toString() ?? '',
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: lines > 1,
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
        key: ValueKey('${identityHashCode(row)}-$key-$value'),
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
    margin: const EdgeInsets.only(bottom: 16),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      maintainState: true,
      initiallyExpanded: open,
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: children,
    ),
  );
  Widget _add(String label, VoidCallback action) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
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
  }) {
    final index = rows.indexOf(row);
    return Card(
      key: ValueKey('item-${row['id'] ?? row['_key']}'),
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        maintainState: true,
        initiallyExpanded:
            row['id']?.toString().startsWith('new-') == true ||
            row['_key'] != null,
        title: Text(title),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
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
          ],
        ),
        childrenPadding: const EdgeInsets.all(16),
        children: children,
      ),
    );
  }

  Map<String, String> get _recipeChoices => {
    for (final r in _options('recipes')) '${r['id']}': '${r['title']}',
  };
  Widget _ingredient(Map<String, dynamic> row) => _item(
    '${_rows('ingredients').indexOf(row) + 1}. ${row['ingredient_name'] ?? 'New ingredient'}',
    _rows('ingredients'),
    row,
    [
      _field(
        row,
        'original_text',
        'Ingredient line (as displayed)',
        required: true,
        lines: 2,
      ),
      _field(
        row,
        'ingredient_name',
        'Ingredient',
        required: true,
        maxLength: 300,
      ),
      _field(row, 'quantity_text', 'Quantity as written', maxLength: 120),
      _field(row, 'original_unit', 'Unit', maxLength: 80),
      _field(
        row,
        'preparation',
        'Preparation (e.g. finely chopped)',
        maxLength: 300,
      ),
      _choice(row, 'group_id', 'Ingredient group', {
        for (final g in _rows('groups'))
          '${g['id']}': '${g['title'] ?? 'New group'}',
      }, nullable: true),
      _toggle(row, 'is_optional', 'Optional ingredient'),
      _toggle(row, 'is_main_ingredient', 'Main ingredient'),
      _toggle(row, 'scale_quantity', 'Adjust quantity when scaling servings'),
      ExpansionTile(
        maintainState: true,
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
  );
  Widget _action(Map<String, dynamic> row, List<Map<String, dynamic>> rows) =>
      _item(row['label']?.toString() ?? 'Cooking action', rows, row, [
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
      ], remove: () => _rows('actions').remove(row));
  Widget _step(Map<String, dynamic> row) {
    final actions = _rows('actions')
        .where((a) => a['step_id'] == row['id'])
        .toList();
    return _item(
      'Step ${_rows('steps').indexOf(row) + 1}',
      _rows('steps'),
      row,
      [
        _field(row, 'section_title', 'Section heading', maxLength: 200),
        _field(row, 'instruction', 'Instructions', required: true, lines: 3),
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
      remove: () {
        _rows('actions').removeWhere((a) => a['step_id'] == row['id']);
        _rows('steps').remove(row);
      },
    );
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
          MediaQuery.sizeOf(context).width < 480 ? 'Edit' : 'Edit recipe',
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
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
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
                      _field(
                        _draft,
                        'prep_minutes',
                        'Preparation time (minutes)',
                        numeric: 'integer',
                      ),
                      _field(
                        _draft,
                        'cook_minutes',
                        'Cooking time (minutes)',
                        numeric: 'integer',
                      ),
                      _field(
                        _draft,
                        'total_minutes',
                        'Total time (minutes)',
                        numeric: 'integer',
                      ),
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
                    ], open: true),
                    _section('Ingredients', Icons.shopping_basket_outlined, [
                      ExpansionTile(
                        maintainState: true,
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
                    _section('Photos', Icons.photo_library_outlined, [
                      ..._rows('photos').map(_photoItem),
                      Wrap(
                        spacing: 12,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _picking || _rows('photos').length >= 20
                                ? null
                                : () => _photo(ImageSource.gallery),
                            icon: const Icon(Icons.upload_outlined),
                            label: const Text('Upload image'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _picking || _rows('photos').length >= 20
                                ? null
                                : () => _photo(ImageSource.camera),
                            icon: const Icon(Icons.camera_alt_outlined),
                            label: const Text('Use camera'),
                          ),
                        ],
                      ),
                      if (_picking) const LinearProgressIndicator(),
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: Text(
                          'JPEG, PNG or WebP · up to 5 MB each · 20 photos maximum',
                        ),
                      ),
                    ], subtitle: '${_rows('photos').length} photos'),
                    _section('Categories & tags', Icons.label_outline, [
                      ..._rows('category_assignments').map(
                        (r) => _item(
                          'Browse category',
                          _rows('category_assignments'),
                          r,
                          [
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
