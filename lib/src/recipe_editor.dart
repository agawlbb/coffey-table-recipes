import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'ingredient_amount.dart';
import 'recipe_browser.dart';
import 'source_photo_crop.dart';
import 'recipe_time.dart';
import 'recipe_value.dart';
import 'recipe_category_selection.dart';
import 'recipe_favorites.dart';
import 'recipe_image_editor.dart';
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
    this.allowEditSource = false,
    this.variationParentTitle,
    this.variationChangeDescription,
  });
  final Map<String, dynamic> recipe;
  final String householdId;
  final RecipeSave save;
  final bool allowEditSource;
  final String? variationParentTitle;
  // Review information only; kept outside the recipe and save payload.
  final String? variationChangeDescription;
  final Future<XFile?> Function(ImageSource source)? pickImage;
  @override
  State<RecipeEditor> createState() => _RecipeEditorState();
}

class _RecipeEditorState extends State<RecipeEditor> {
  final _form = GlobalKey<FormState>();
  late final Map<String, dynamic> _draft;
  bool get _blank => _draft['source_type'] == 'blank';
  List<Map<String, dynamic>> _favoritePeople = [];
  String? _currentPerson;
  List<Map<String, dynamic>> get _selectedCategories =>
      _rows('category_assignments')
          .where((row) => row['category_id'] != null || row['label'] != null)
          .toList();
  bool get _automaticCategory => _blank && _selectedCategories.isEmpty;
  bool _dirty = false, _saving = false, _picking = false, _leaving = false;
  bool _closing = false;
  final List<Map<String, dynamic>> _sourcePhotos = [];
  bool _loadingSourcePhotos = false;
  String? _error;
  String? _photoError;
  bool _revealingErrors = false;
  AnimationStyle? get _expansionStyle =>
      _revealingErrors ? AnimationStyle.noAnimation : null;
  int _nextId = 0;
  final _sections = <String, GlobalKey>{};
  final _expansions = <String, ExpansibleController>{};
  final _fields = <String, GlobalKey<FormFieldState<String>>>{};
  final _timeParts = <String, Map<String, dynamic>>{};
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
  List<Map<String, dynamic>> _options(String key) {
    final options = recipeRows((_draft['edit_options'] as Map?)?[key]);
    if (key == 'categories') {
      options.sort(
        (a, b) => '${a['label'] ?? ''}'.trim().toLowerCase().compareTo(
          '${b['label'] ?? ''}'.trim().toLowerCase(),
        ),
      );
    }
    return options;
  }

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
    if (_blank) {
      final favorites = (_draft['edit_options'] as Map?)?['favorites'] as Map?;
      _favoritePeople = recipeRows(favorites?['people']);
      _currentPerson = favorites?['current_person_id']?.toString();
      if (_rows('category_assignments').isEmpty) {
        _rows('category_assignments').add(<String, dynamic>{});
      }
    }
    for (final key in ['tags', 'category_assignments']) {
      for (final row in _rows(key)) {
        row['_key'] = _id();
      }
    }
    for (final row in _rows('category_assignments')) {
      normalizeRecipeCategory(row, _options('categories'));
      row['_parent_category'] ??= row['parent_label'];
      final selected = _options('categories')
          .where((c) => c['id'].toString() == row['category_id']?.toString())
          .firstOrNull;
      if (selected != null) {
        row['_parent_category'] = selected['parent_label'] ?? selected['label'];
      }
    }
    if (_draft['source_type'] != null &&
        !_blank &&
        _draft['source_type'] != 'ai_variation') {
      _draft['source_type'] = recipeSourceLabel(_draft['source_type']);
    }
    _draft.remove('photo_suggestions');
    _prepareSourcePhotos(widget.recipe['photo_suggestions']);
    _draft['original_language'] ??= 'en';
    _draft['measurement_system'] ??= 'unspecified';
    offlineStatus.addListener(_connectionChanged);
    _recoverPhoto();
  }

  Future<void> _prepareSourcePhotos(Object? suggestions) async {
    if (suggestions is! List || suggestions.isEmpty) return;
    _loadingSourcePhotos = true;
    final prepared = <Map<String, dynamic>>[];
    for (final value in suggestions.take(6)) {
      try {
        prepared.add(
          await prepareSourcePhoto(Map<String, dynamic>.from(value as Map)),
        );
      } catch (_) {
        /* A source picture must not discard the recipe draft. */
      }
    }
    if (mounted) {
      setState(() {
        for (final photo in prepared) {
          _rows('photos').add({
            ...photo,
            'id': _id(),
            'is_cover': _rows('photos').isEmpty ? 1 : 0,
          });
        }
        _loadingSourcePhotos = false;
      });
    }
  }

  void _useSourcePhoto(Map<String, dynamic> photo) => _change(() {
    _rows(
      'photos',
    ).add({...photo, 'id': _id(), 'is_cover': _rows('photos').isEmpty ? 1 : 0});
    _sourcePhotos.remove(photo);
  });
  Widget _category(Map<String, dynamic> row) {
    final parent = row['_parent_category'] ?? row['parent_label'];
    final options = _options('categories')
        .where(
          (c) =>
              c['parent_label'] == parent ||
              (c['parent_label'] == null && c['label'] == parent),
        )
        .toList();
    final selected =
        row['category_id']?.toString() ??
        (row['label'] != null ? '__new' : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _choice(
            row,
            '_parent_category',
            'Parent category',
            {
              for (final c in _options(
                'categories',
              ).where((c) => c['parent_label'] == null))
                '${c['label']}': '${c['label']}',
            },
            nullable: true,
            nullableLabel: _blank ? 'Choose automatically' : 'None',
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('${identityHashCode(row)}-$parent-$selected'),
            initialValue:
                selected == '__new' ||
                    options.any((c) => '${c['id']}' == selected)
                ? selected
                : null,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Category',
              hintText: _blank && parent == null
                  ? 'Choose a parent first'
                  : null,
            ),
            items: [
              for (final c in options)
                DropdownMenuItem(
                  value: '${c['id']}',
                  child: Text('${c['label']}'),
                ),
              const DropdownMenuItem(
                value: '__new',
                child: Text('Add new category…'),
              ),
            ],
            validator: (_) => row['category_id'] == null && row['label'] == null
                ? (_blank ? null : 'Choose a category')
                : null,
            onChanged: _blank && parent == null
                ? null
                : (value) => _change(() {
                    if (value == '__new') {
                      row.remove('category_id');
                      row['label'] = '';
                      row['parent_label'] = row['_parent_category'];
                      row['_new_category'] = true;
                    } else {
                      row['category_id'] = value;
                      row.remove('label');
                      row.remove('parent_label');
                      row.remove('_new_category');
                    }
                  }),
          ),
          if (row['label'] != null) ...[
            const SizedBox(height: 12),
            _field(
              row,
              'label',
              'New category name',
              required: true,
              maxLength: 120,
              changed: (value) => _change(() => row['label'] = value),
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              tooltip: 'Remove category',
              onPressed: () =>
                  _change(() => _rows('category_assignments').remove(row)),
              icon: const Icon(Icons.close),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _favorite({bool household = false}) async {
    if (_saving || _picking) return;
    if (household) {
      final people = await chooseHouseholdFavorites(context, _favoritePeople);
      if (people != null && mounted) _change(() => _favoritePeople = people);
    } else {
      final own = _favoritePeople
          .where((p) => '${p['id']}' == _currentPerson)
          .firstOrNull;
      if (own != null) {
        _change(() => own['favorite'] = !recipePersonFavorite(own));
      }
    }
  }

  Widget _blankFavorites() => Row(
    children: [
      IconButton(
        tooltip: 'Favorite (hold for household)',
        onPressed: _favoritePeople.isEmpty || _saving || _picking
            ? null
            : () => _favorite(),
        onLongPress: _favoritePeople.isEmpty || _saving || _picking
            ? null
            : () => _favorite(household: true),
        icon: Icon(
          _favoritePeople.any(
                (p) =>
                    '${p['id']}' == _currentPerson && recipePersonFavorite(p),
              )
              ? Icons.favorite
              : Icons.favorite_border,
        ),
      ),
      Expanded(
        child: Text(
          _favoritePeople.any(recipePersonFavorite)
              ? 'Favorite of ${_favoritePeople.where(recipePersonFavorite).map((p) => p['display_name']).join(' and ')}'
              : 'Favorite',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    ],
  );

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

  StateSetter? _panelRefresh;
  void _change(void Function() action) {
    if (_panelRefresh != null) {
      _panelRefresh!(action);
      return;
    }
    setState(() {
      action();
      _dirty = true;
      _error = null;
    });
  }

  Future<bool> _panel(
    String title,
    List<Widget> Function() children, {
    bool showErrors = false,
  }) async {
    final form = GlobalKey<FormState>();
    var active = true;
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, refresh) {
          if (active) _panelRefresh = refresh;
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 560,
              child: Form(
                key: form,
                autovalidateMode: showErrors
                    ? AutovalidateMode.always
                    : AutovalidateMode.disabled,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children(),
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  if (form.currentState!.validate()) {
                    Navigator.pop(dialogContext, true);
                  }
                },
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
    active = false;
    _panelRefresh = null;
    return accepted == true;
  }

  Future<void> _editIngredient(
    Map<String, dynamic> row, {
    bool adding = false,
    bool showErrors = false,
  }) async {
    final copy = Map<String, dynamic>.from(row);
    final input = ingredientEditingFields(row);
    final initialInput = Map<String, dynamic>.from(input);
    // Older recipes sometimes only have the complete displayed line. Preserve it
    // until the user explicitly edits the amount, rather than guessing its unit.
    final accepted = await _panel(
      adding ? 'Add ingredient' : 'Edit ingredient',
      () => [
        _columns([
          _field(
            input,
            'amount',
            'Amount',
            hint: '1/4, 1 1/2, or to taste',
            validate: (value) {
              try {
                ingredientAmount(value);
                return null;
              } on FormatException catch (e) {
                return e.message;
              }
            },
          ),
          _field(input, 'unit', 'Unit', maxLength: 80),
        ], minWidth: 130),
        _field(input, 'name', 'Ingredient', required: true, maxLength: 300),
        _field(
          input,
          'preparation',
          'Preparation (e.g. finely chopped)',
          maxLength: 300,
        ),
        _choice(copy, 'group_id', 'Ingredient group', {
          for (final g in _rows('groups')) '${g['id']}': '${g['title']}',
        }, nullable: true),
        _toggle(copy, 'scale_quantity', 'Scale with servings'),
        _toggle(copy, 'is_optional', 'Optional ingredient'),
        _toggle(copy, 'is_main_ingredient', 'Main ingredient'),
        Text(
          [
            input['amount'],
            input['unit'],
            input['name'],
          ].where((v) => v != null && '$v'.isNotEmpty).join(' '),
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
      showErrors: showErrors,
    );
    if (!accepted || !mounted) return;
    final fieldsChanged = adding || !mapEquals(input, initialInput);
    if (fieldsChanged ||
        (copy['quantity_decimal'] != null &&
            copy['quantity_numerator'] != null) ||
        '${copy['original_text'] ?? ''}'.trim().isEmpty) {
      applyIngredientFields(
        copy,
        '${input['amount'] ?? ''}',
        '${input['unit'] ?? ''}',
        '${input['name'] ?? ''}',
        '${input['preparation'] ?? ''}',
      );
    } else if ('${input['amount'] ?? ''}'.isNotEmpty) {
      copy.addAll(ingredientAmount('${input['amount']}'));
    }
    _change(() {
      row
        ..clear()
        ..addAll(copy);
      if (adding) _rows('ingredients').add(row);
    });
  }

  Future<void> _editGroup([Map<String, dynamic>? group]) async {
    final copy = <String, dynamic>{...?group, if (group == null) 'id': _id()};
    if (await _panel(
          group == null ? 'Add group' : 'Rename group',
          () => [
            _field(copy, 'title', 'Group name', required: true, maxLength: 200),
          ],
        ) &&
        mounted) {
      _change(() {
        if (group == null) {
          _rows('groups').add(copy);
        } else {
          group.addAll(copy);
        }
      });
    }
  }

  Future<void> _editStep(
    Map<String, dynamic> row, {
    bool adding = false,
    bool showErrors = false,
  }) async {
    final copy = Map<String, dynamic>.from(row);
    final actions = _rows('actions')
        .where((a) => a['step_id'] == row['id'])
        .map((a) => Map<String, dynamic>.from(a))
        .toList();
    if (!await _panel(
          adding ? 'Add step' : 'Edit step',
          () => [
            _field(
              copy,
              'instruction',
              'Instructions',
              required: true,
              lines: 4,
            ),
            _field(
              copy,
              'section_title',
              'Section heading (optional)',
              maxLength: 200,
            ),
            const Text(
              'Timers & temperatures',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            ...actions.map((a) => _action(a, actions)),
            _add(
              'Add timer or temperature',
              () => _change(
                () => actions.add({
                  'id': _id(),
                  'step_id': row['id'],
                  'action_type': 'timer',
                  'duration_seconds': 60,
                }),
              ),
            ),
          ],
          showErrors: showErrors,
        ) ||
        !mounted) {
      return;
    }
    _change(() {
      row
        ..clear()
        ..addAll(copy);
      if (adding) _rows('steps').add(row);
      _rows('actions').removeWhere((a) => a['step_id'] == row['id']);
      _rows('actions').addAll(actions);
    });
  }

  Future<void> _editSource() async {
    setState(() => _leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) {
      Navigator.pop(context, {'_edit_source': true, 'draft': _draft});
    }
  }

  Future<void> _close() async {
    if (_saving || _picking || _closing || _leaving) return;
    if (_dirty) {
      _closing = true;
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
      _closing = false;
      if (discard != true) return;
    }
    if (!mounted) return;
    setState(() => _leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _save() async {
    if (_saving || _picking || offlineStatus.value) return;
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
    for (final ingredient in _rows('ingredients')) {
      final decimal = ingredient['quantity_decimal'],
          numerator = ingredient['quantity_numerator'],
          denominator = ingredient['quantity_denominator'];
      final invalidQuantity =
          (decimal != null && (numerator != null || denominator != null)) ||
          ((numerator != null || denominator != null) &&
              (num.tryParse('$denominator') == null ||
                  (num.tryParse('$denominator') ?? 0) <= 0 ||
                  num.tryParse('$numerator') == null));
      if ('${ingredient['ingredient_name'] ?? ''}'.trim().isEmpty ||
          '${ingredient['original_text'] ?? ''}'.trim().isEmpty ||
          invalidQuantity) {
        setState(
          () => _error =
              'Check ingredient: ${ingredient['original_text'] ?? ingredient['ingredient_name'] ?? 'unnamed ingredient'}. Review its amount and name.',
        );
        await _jumpTo('Ingredients');
        await _editIngredient(ingredient, showErrors: true);
        return;
      }
    }
    for (final step in _rows('steps')) {
      final actions = _rows('actions').where((a) => a['step_id'] == step['id']);
      final invalid = actions.any(
        (a) => ['timer', 'rest'].contains(a['action_type'])
            ? (recipeSeconds(a['duration_seconds']) ?? 0) <= 0
            : [
                    'appliance_temperature',
                    'internal_temperature',
                  ].contains(a['action_type']) &&
                  (num.tryParse('${a['temperature_value']}') == null ||
                      !['F', 'C'].contains(a['temperature_unit'])),
      );
      if ('${step['instruction'] ?? ''}'.trim().isEmpty || invalid) {
        setState(
          () => _error =
              'Check step ${_rows('steps').indexOf(step) + 1}: instructions, timer duration, or temperature need attention.',
        );
        await _jumpTo('Steps & actions');
        await _editStep(step, showErrors: true);
        return;
      }
    }
    // The server rejects unconfirmed saves if sharing changes during editing.
    _draft.remove('confirm_shared_edit');
    if (_draft['id'] != null &&
        (int.tryParse('${_draft['household_count']}') ?? 1) > 1) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Save recipe changes?'),
          content: const Text(
            'This recipe may be shared across households. Your changes update the same recipe in every household that has added it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save for all households'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      _draft['confirm_shared_edit'] = true;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = await widget.save(
        '/households/${widget.householdId}/recipes${_draft['id'] == null ? '' : '/${_draft['id']}'}',
        {
          ..._draft,
          if (_blank) 'category_assignments': _selectedCategories,
          if (_blank && _favoritePeople.isNotEmpty)
            'favorite_people': [
              for (final person in _favoritePeople)
                {
                  'person_id': person['id'],
                  'favorite': recipePersonFavorite(person),
                },
            ],
        },
      );
      final savedRecipe = data['recipe'] as Map<String, dynamic>;
      for (final category
          in _blank
              ? <Map<String, dynamic>>[]
              : recipeRows(savedRecipe['category_assignments'])) {
        try {
          await widget.save(
            '/households/${widget.householdId}/category-image',
            {'category_id': category['category_id'].toString()},
          );
        } on ApiException catch (error) {
          if (error.status == 404 || error.status == 403) continue;
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Recipe saved. Category image: ${error.message}'),
              ),
            );
          }
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Recipe saved. Category image could not be generated; it will be retried when browsing.',
                ),
              ),
            );
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _leaving = true;
        _dirty = false;
        _saving = false;
      });
      Navigator.pop(context, data['recipe'] as Map<String, dynamic>);
    } catch (error) {
      if (mounted &&
          error is ApiException &&
          error.code == 'shared_confirmation_required') {
        setState(() {
          _saving = false;
          _draft['household_count'] = 2;
        });
        await _save();
        return;
      }
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

  Future<void> _editPhoto(Map<String, dynamic> row) async {
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final bytes = row['image_base64'] != null
          ? base64Decode(row['image_base64'] as String)
          : await (await recipePhotoCache.getSingleFile(
              row['source_url'] as String,
            )).readAsBytes();
      if (!mounted) return;
      final edited = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(builder: (_) => RecipeImageEditor(bytes: bytes)),
      );
      if (edited != null && mounted) {
        _change(() => row['image_base64'] = base64Encode(edited));
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not open this picture for editing. Check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
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
    if (_picking ||
        _saving ||
        _rows('photos').isNotEmpty ||
        _sourcePhotos.isNotEmpty ||
        _loadingSourcePhotos ||
        recipeRows(widget.recipe['photos']).isNotEmpty) {
      return;
    }
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
        () => _rows('photos').add({
          ...photo,
          'id': _id(),
          'is_cover': _rows('photos').isEmpty ? 1 : 0,
        }),
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
    ValueChanged<String>? changed,
    String? Function(String)? validate,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextFormField(
      onTapOutside: (_) => FocusScope.of(context).unfocus(),
      scrollPadding: const EdgeInsets.all(80),
      key: _fields.putIfAbsent(
        '${identityHashCode(row)}-$key',
        () => GlobalKey<FormFieldState<String>>(),
      ),
      initialValue: numeric == 'duration' || numeric == 'minuteDuration'
          ? recipeTimeInput(
              row[key],
              minutePrecision: numeric == 'minuteDuration',
            )
          : numeric != null && num.tryParse('${row[key]}') != null
          ? num.parse('${row[key]}')
                .toString()
                .replaceFirst(RegExp(r'\.0+$'), '')
          : row[key]?.toString() ?? '',
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: lines > 1,
        hintText: hint,
      ),
      minLines: lines,
      maxLines: lines > 1 ? lines + 3 : 1,
      keyboardType: numeric == 'duration' || numeric == 'minuteDuration'
          ? TextInputType.datetime
          : numeric != null
          ? const TextInputType.numberWithOptions(decimal: true, signed: true)
          : lines > 1
          ? TextInputType.multiline
          : TextInputType.text,
      validator: (value) {
        final text = value?.trim() ?? '';
        if (validate != null) return validate(text);
        if (required && text.isEmpty) return 'Enter $label';
        if (text.isNotEmpty &&
            (numeric == 'duration' || numeric == 'minuteDuration')) {
          final duration = parseRecipeTime(
            text,
            minutePrecision: numeric == 'minuteDuration',
          );
          if (duration == null || (required && duration == 0)) {
            return numeric == 'minuteDuration'
                ? 'Use h:mm, with minutes from 00 to 59'
                : 'Use m:ss or h:mm:ss${required ? ' greater than zero' : ''}; minutes/seconds must be 00–59';
          }
          return null;
        }
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
        if (changed != null) {
          changed(value);
          return;
        }
        _change(
          () => row[key] = value.trim().isEmpty
              ? null
              : numeric == 'duration' || numeric == 'minuteDuration'
              ? parseRecipeTime(
                      value,
                      minutePrecision: numeric == 'minuteDuration',
                    ) ??
                    value
              : value,
        );
      },
    ),
  );
  Widget _timeFields(
    Map<String, dynamic> row,
    String key,
    String label, {
    bool minutesOnly = false,
    bool required = false,
  }) {
    final parts = _timeParts.putIfAbsent('${identityHashCode(row)}-$key', () {
      final raw = num.tryParse('${row[key]}')?.toInt();
      final seconds = raw == null ? null : raw * (minutesOnly ? 60 : 1);
      return {
        'hours': seconds == null ? null : seconds ~/ 3600,
        'minutes': seconds == null ? null : seconds % 3600 ~/ 60,
        'seconds': seconds == null ? null : seconds % 60,
      };
    });
    int total() =>
        (int.tryParse('${parts['hours']}') ?? 0) * 3600 +
        (int.tryParse('${parts['minutes']}') ?? 0) * 60 +
        (int.tryParse('${parts['seconds']}') ?? 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Row(
          children: [
            for (final part in [
              'hours',
              'minutes',
              if (!minutesOnly) 'seconds',
            ]) ...[
              if (part != 'hours') const SizedBox(width: 8),
              Expanded(
                child: _field(
                  parts,
                  part,
                  '${label == 'Duration' ? '' : '$label '}${part == 'hours'
                      ? 'Hours'
                      : part == 'minutes'
                      ? 'Minutes'
                      : 'Seconds'}',
                  numeric: 'integer',
                  validate: (text) {
                    if (text.isNotEmpty &&
                        (!RegExp(r'^\d+$').hasMatch(text) ||
                            (part != 'hours' &&
                                (int.tryParse(text) ?? 60) > 59))) {
                      return part == 'hours' ? 'Use whole hours' : 'Use 0–59';
                    }
                    if (required && part == 'seconds' && total() <= 0) {
                      return 'Enter a duration greater than zero';
                    }
                    return null;
                  },
                  changed: (value) => _change(() {
                    parts[part] = value.trim().isEmpty ? null : value;
                    row[key] = parts.values.every((v) => v == null)
                        ? null
                        : minutesOnly
                        ? total() ~/ 60
                        : total();
                  }),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _compactTime(
    Map<String, dynamic> row,
    String key,
    String label, {
    bool minutesOnly = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: OutlinedButton.icon(
      icon: const Icon(Icons.schedule, size: 18),
      label: Text(
        '$label: ${row[key] == null ? 'Add time' : formatRecipeTime((recipeSeconds(row[key]) ?? 0) * 60)}',
      ),
      onPressed: () async {
        final copy = Map<String, dynamic>.from(row);
        if (await _panel(
              '$label time',
              () => [_timeFields(copy, key, label, minutesOnly: true)],
            ) &&
            mounted) {
          _change(() => row[key] = copy[key]);
        }
      },
    ),
  );

  Widget _coverPreview() {
    final photo =
        _rows('photos').where((p) => _bool(p['is_cover'])).firstOrNull ??
        _rows('photos').firstOrNull;
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        onPressed: () => _jumpTo('Photos'),
        icon: photo == null
            ? const Icon(Icons.add_photo_alternate_outlined)
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: photo['image_base64'] != null
                      ? Image.memory(
                          base64Decode('${photo['image_base64']}'),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.broken_image_outlined),
                        )
                      : RecipePhoto(
                          url: photo['source_url'] as String?,
                          fit: BoxFit.cover,
                        ),
                ),
              ),
        label: Text(
          photo == null ? 'Add a cover photo' : 'Cover photo · Edit photos',
        ),
      ),
    );
  }

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
    String nullableLabel = 'None',
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
          if (nullable) DropdownMenuItem(value: '', child: Text(nullableLabel)),
          ...options.entries.map(
            (e) => DropdownMenuItem(
              value: e.key,
              child: Text(e.value, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        onChanged: (value) => _change(() {
          row[key] = value == '' ? null : value;
          if (key == '_parent_category') {
            selectRecipeCategoryParent(row, _options('categories'));
          }
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
    bool? open,
    String? subtitle,
  }) => Card(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    key: _sections.putIfAbsent(title, GlobalKey.new),
    margin: const EdgeInsets.only(bottom: 16),
    clipBehavior: Clip.antiAlias,
    child: ExpansionTile(
      maintainState: true,
      controller: _controller(title),
      expansionAnimationStyle: _expansionStyle,
      initiallyExpanded:
          open ??
          const {
            'Ingredients',
            'Steps & actions',
            'Photos',
            'Notes & source',
          }.contains(title),
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
    bool flat = false,
    bool controls = true,
  }) {
    final index = rows.indexOf(row);
    return Card(
      elevation: 0,
      shape: flat
          ? const RoundedRectangleBorder()
          : RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      color: flat ? Colors.transparent : null,
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
                    Text(preview),
                  ?summary,
                ],
              ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          ...children,
          if (controls) const Divider(),
          if (controls)
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
  Widget _ingredient(Map<String, dynamic> row) {
    final rows = _rows('ingredients'), index = rows.indexOf(row);
    return Card(
      key: ValueKey('item-${row['id']}'),
      elevation: 0,
      child: ListTile(
        contentPadding: const EdgeInsets.only(left: 12),
        title: Text(
          '${row['original_text'] ?? row['ingredient_name'] ?? 'New ingredient'}',
        ),
        onTap: () => _editIngredient(row),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: 'Edit ingredient',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _editIngredient(row),
            ),
            IconButton(
              tooltip: 'Delete ingredient',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _change(() => rows.remove(row)),
            ),
            PopupMenuButton<String>(
              tooltip: 'Move to group',
              icon: const Icon(Icons.drive_file_move_outline),
              onSelected: (value) => _change(() {
                if (value == 'remove') {
                  rows.remove(row);
                } else if (value == 'up' || value == 'down') {
                  _move(rows, row, index + (value == 'up' ? -1 : 1));
                } else {
                  row['group_id'] = value == 'group:'
                      ? null
                      : value.substring(6);
                }
              }),
              itemBuilder: (_) => [
                const PopupMenuItem<String>(
                  enabled: false,
                  child: Text('Move to group'),
                ),
                const PopupMenuItem(value: 'group:', child: Text('Ungrouped')),
                for (final g in _rows('groups'))
                  PopupMenuItem(
                    value: 'group:${g['id']}',
                    child: Text('${g['title']}'),
                  ),
                const PopupMenuDivider(),
                if (index > 0)
                  const PopupMenuItem(value: 'up', child: Text('Move up')),
                if (index < rows.length - 1)
                  const PopupMenuItem(value: 'down', child: Text('Move down')),
                const PopupMenuItem(
                  value: 'remove',
                  child: Text('Remove ingredient'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _ingredientGroups() {
    final groups = _rows('groups');
    final result = <Widget>[];
    for (final group in <Map<String, dynamic>?>[...groups, null]) {
      final rows = _rows('ingredients')
          .where(
            (i) => group == null
                ? !groups.any((g) => '${g['id']}' == '${i['group_id']}')
                : '${i['group_id']}' == '${group['id']}',
          )
          .toList();
      if (group == null && rows.isEmpty && groups.isNotEmpty) continue;
      if (groups.isNotEmpty || group != null) {
        result.add(
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${group?['title'] ?? 'Ungrouped'} · ${rows.length}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (group != null)
                  IconButton(
                    tooltip: 'Rename group',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: () => _editGroup(group),
                  ),
                if (group != null)
                  PopupMenuButton<String>(
                    tooltip: 'Group options',
                    onSelected: (_) => _change(() {
                      for (final row in rows) {
                        row['group_id'] = null;
                      }
                      groups.remove(group);
                    }),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'remove',
                        child: Text('Remove group; keep ingredients'),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );
      }
      if (rows.isNotEmpty) {
        result.add(
          ReorderableListView(
            shrinkWrap: true,
            primary: false,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (oldIndex, newIndex) => _change(() {
              final ordered = [...rows];
              ordered.insert(newIndex, ordered.removeAt(oldIndex));
              final ingredients = _rows('ingredients');
              final positions = [
                for (var i = 0; i < ingredients.length; i++)
                  if (rows.contains(ingredients[i])) i,
              ];
              for (var i = 0; i < positions.length; i++) {
                ingredients[positions[i]] = ordered[i];
              }
            }),
            children: [
              for (var index = 0; index < rows.length; index++)
                Padding(
                  key: ValueKey(
                    'ingredient-order-${identityHashCode(rows[index])}',
                  ),
                  padding: EdgeInsets.only(left: group == null ? 0 : 12),
                  child: ReorderableDelayedDragStartListener(
                    index: index,
                    child: _ingredient(rows[index]),
                  ),
                ),
            ],
          ),
        );
      }
      result.add(
        _add(
          group == null
              ? 'Add ingredient'
              : 'Add ingredient to ${group['title']}',
          () => _editIngredient({
            'id': _id(),
            'group_id': group?['id'],
            'scale_quantity': true,
          }, adding: true),
        ),
      );
    }
    result.add(_add('Add group', () => _editGroup()));
    return result;
  }

  Widget _action(Map<String, dynamic> row, List<Map<String, dynamic>> rows) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(row['label']?.toString() ?? 'Cooking action'),
              _choice(row, 'action_type', 'Action type', {
                'timer': 'Timer',
                if (row['action_type'] == 'rest') 'rest': 'Rest',
                'appliance_temperature': 'Appliance temperature',
                if (row['action_type'] == 'internal_temperature')
                  'internal_temperature': 'Internal temperature',
                if (row['action_type'] == 'reminder') 'reminder': 'Reminder',
              }),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Move action up',
                    onPressed: rows.indexOf(row) == 0
                        ? null
                        : () => _change(() {
                            final index = rows.indexOf(row);
                            rows.removeAt(index);
                            rows.insert(index - 1, row);
                          }),
                    icon: const Icon(Icons.arrow_upward),
                  ),
                  IconButton(
                    tooltip: 'Move action down',
                    onPressed: rows.indexOf(row) == rows.length - 1
                        ? null
                        : () => _change(() {
                            final index = rows.indexOf(row);
                            rows.removeAt(index);
                            rows.insert(index + 1, row);
                          }),
                    icon: const Icon(Icons.arrow_downward),
                  ),
                ],
              ),
              _field(row, 'label', 'Label', maxLength: 300),
              if (['timer', 'rest'].contains(row['action_type']) ||
                  row['duration_seconds'] != null)
                _timeFields(
                  row,
                  'duration_seconds',
                  'Duration',
                  required: ['timer', 'rest'].contains(row['action_type']),
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
              TextButton.icon(
                onPressed: () => _change(() => rows.remove(row)),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove action'),
              ),
            ],
          ),
        ),
      );
  Widget _step(Map<String, dynamic> row) {
    final actions = _rows('actions')
        .where((a) => a['step_id'] == row['id'])
        .toList();
    return Card(
      key: ValueKey('item-${row['id']}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Step ${_rows('steps').indexOf(row) + 1}${row['section_title'] == null ? '' : ' · ${row['section_title']}'}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit step',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editStep(row),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Step options',
                  onSelected: (value) => _change(() {
                    final rows = _rows('steps'), index = rows.indexOf(row);
                    if (value == 'remove') {
                      rows.remove(row);
                      _rows('actions')
                          .removeWhere((a) => a['step_id'] == row['id']);
                    } else {
                      _move(rows, row, index + (value == 'up' ? -1 : 1));
                    }
                  }),
                  itemBuilder: (_) => [
                    if (_rows('steps').indexOf(row) > 0)
                      const PopupMenuItem(value: 'up', child: Text('Move up')),
                    if (_rows('steps').indexOf(row) < _rows('steps').length - 1)
                      const PopupMenuItem(
                        value: 'down',
                        child: Text('Move down'),
                      ),
                    const PopupMenuItem(
                      value: 'remove',
                      child: Text('Remove step'),
                    ),
                  ],
                ),
              ],
            ),
            InkWell(
              onTap: () => _editStep(row),
              child: Text('${row['instruction'] ?? ''}'),
            ),
            for (final action in actions)
              Align(
                alignment: Alignment.centerLeft,
                child: ActionChip(
                  avatar: Icon(
                    action['temperature_value'] == null
                        ? Icons.timer_outlined
                        : Icons.thermostat,
                    size: 18,
                  ),
                  label: Text(_actionSummary(action)),
                  onPressed: () => _editStep(row),
                ),
              ),
          ],
        ),
      ),
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
      details.add(formatRecipeTime(seconds));
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
      OutlinedButton.icon(
        onPressed: _saving || _picking ? null : () => _editPhoto(row),
        icon: const Icon(Icons.crop_rotate),
        label: const Text('Edit picture'),
      ),
      ExpansionTile(
        maintainState: true,
        controller: _controller('photo-options-${identityHashCode(row)}'),
        title: const Text('More options'),
        children: [
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
          Row(
            children: [
              IconButton(
                tooltip: 'Move photo up',
                onPressed: _rows('photos').indexOf(row) == 0
                    ? null
                    : () => _change(
                        () => _move(
                          _rows('photos'),
                          row,
                          _rows('photos').indexOf(row) - 1,
                        ),
                      ),
                icon: const Icon(Icons.arrow_upward),
              ),
              IconButton(
                tooltip: 'Move photo down',
                onPressed:
                    _rows('photos').indexOf(row) == _rows('photos').length - 1
                    ? null
                    : () => _change(
                        () => _move(
                          _rows('photos'),
                          row,
                          _rows('photos').indexOf(row) + 1,
                        ),
                      ),
                icon: const Icon(Icons.arrow_downward),
              ),
              IconButton(
                tooltip: 'Remove photo',
                onPressed: () => _change(() => _rows('photos').remove(row)),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ],
      ),
    ],
    controls: false,
    initiallyExpanded: true,
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
              ? (_blank ? 'Blank recipe' : 'Review recipe')
              : MediaQuery.sizeOf(context).width < 480
              ? 'Edit'
              : 'Edit recipe',
        ),
        actions: [
          if (!_blank)
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
              label: Text(_saving ? 'Saving…' : 'Save recipe'),
            ),
          ),
        ],
        bottom: _blank
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(54),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final entry
                            in const {
                              'Recipe details': 'Details',
                              'Ingredients': 'Ingredients',
                              'Steps & actions': 'Method',
                              'Photos': 'Photos',
                              'Notes & source': 'Notes',
                              'Related recipes': 'Related',
                              'Nutrition': 'Nutrition',
                            }.entries.where(
                              (e) =>
                                  !_blank ||
                                  ['Recipe details', 'Photos'].contains(e.key),
                            ))
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              label: Text(entry.value),
                              tooltip: 'Go to ${entry.key.toLowerCase()}',
                              onPressed: () => _jumpTo(entry.key),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
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
                          ? (_automaticCategory
                                ? 'Choosing a category and saving…'
                                : 'Saving your recipe…')
                          : _dirty
                          ? 'Unsaved changes'
                          : widget.variationParentTitle != null &&
                                _draft['id'] == null
                          ? 'Variation not saved'
                          : _draft['id'] == null
                          ? 'Draft—not saved yet'
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
            constraints: BoxConstraints(maxWidth: _blank ? 640 : 900),
            child: Form(
              key: _form,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _blank
                          ? (_draft['id'] == null
                                ? 'Create a blank recipe'
                                : 'Edit blank recipe')
                          : _draft['title']?.toString() ?? 'Your recipe',
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    if (widget.allowEditSource)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _editSource,
                          icon: const Icon(Icons.edit_note),
                          label: const Text('Edit source'),
                        ),
                      ),
                    _coverPreview(),
                    if (widget.variationParentTitle != null) ...[
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Chip(label: Text('Variation')),
                      ),
                      _help('Variation of ${widget.variationParentTitle}'),
                      if (widget.variationChangeDescription?.isNotEmpty == true)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'How the recipe changed',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(widget.variationChangeDescription!),
                              ],
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 20),
                    if (offlineStatus.value)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Text('Reconnect to save recipe changes.'),
                      ),
                    if (_draft['import_warnings'] is List)
                      for (final warning in _draft['import_warnings'] as List)
                        _help(warning.toString()),
                    _section('Recipe details', Icons.restaurant_outlined, [
                      _field(
                        _draft,
                        'title',
                        'Recipe name',
                        required: true,
                        maxLength: 300,
                      ),
                      if (_blank) _blankFavorites(),
                      if (!_blank) ...[
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
                          _compactTime(
                            _draft,
                            'prep_minutes',
                            'Prep',
                            minutesOnly: true,
                          ),
                          _compactTime(
                            _draft,
                            'cook_minutes',
                            'Cook',
                            minutesOnly: true,
                          ),
                          _compactTime(
                            _draft,
                            'total_minutes',
                            'Total',
                            minutesOnly: true,
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
                      ],
                      const Divider(),
                      Text(
                        _blank ? 'Category (optional)' : 'Categories & tags',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (_blank)
                        _help('Leave blank for AI to choose on save.'),
                      ..._rows('category_assignments').map(_category),
                      _add(
                        'Add category',
                        () => _change(
                          () =>
                              _rows('category_assignments')
                                  .add({'_key': _id()}),
                        ),
                      ),
                      if (!_blank) ...[
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
                      ],
                    ], open: true),
                    if (!_blank) ...[
                      _section(
                        'Ingredients',
                        Icons.shopping_basket_outlined,
                        [..._ingredientGroups()],
                        subtitle: '${_rows('ingredients').length} ingredients',
                      ),
                      _section('Steps & actions', Icons.format_list_numbered, [
                        ..._rows('steps').map(_step),
                        _add(
                          'Add step',
                          () => _editStep({
                            'id': _id(),
                            'instruction': '',
                          }, adding: true),
                        ),
                      ], subtitle: '${_rows('steps').length} steps'),
                    ],
                    _section(
                      'Photos',
                      Icons.photo_library_outlined,
                      [
                        if (_loadingSourcePhotos)
                          const LinearProgressIndicator(),
                        if (_sourcePhotos.isNotEmpty) ...[
                          const Text(
                            'Pictures found in your import',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          for (final photo in List<Map<String, dynamic>>.from(
                            _sourcePhotos,
                          ))
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  children: [
                                    Image.memory(
                                      base64Decode(
                                        photo['image_base64'] as String,
                                      ),
                                      height: 160,
                                      fit: BoxFit.contain,
                                    ),
                                    Wrap(
                                      spacing: 12,
                                      children: [
                                        OutlinedButton.icon(
                                          onPressed: _saving || _picking
                                              ? null
                                              : () => _editPhoto(photo),
                                          icon: const Icon(Icons.crop_rotate),
                                          label: const Text('Edit picture'),
                                        ),
                                        FilledButton.icon(
                                          onPressed: _saving
                                              ? null
                                              : () => _useSourcePhoto(photo),
                                          icon: const Icon(
                                            Icons.add_photo_alternate_outlined,
                                          ),
                                          label: const Text('Use this picture'),
                                        ),
                                        TextButton(
                                          onPressed: _saving
                                              ? null
                                              : () => setState(
                                                  () => _sourcePhotos.remove(
                                                    photo,
                                                  ),
                                                ),
                                          child: const Text('Skip picture'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],

                        ..._rows('photos').map(_photoItem),
                        Wrap(
                          spacing: 12,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _picking
                                  ? null
                                  : () => _photo(ImageSource.gallery),
                              icon: const Icon(Icons.upload_outlined),
                              label: const Text('Upload image'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _picking
                                  ? null
                                  : () => _photo(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: const Text('Use camera'),
                            ),
                            if (!_blank &&
                                _rows('photos').isEmpty &&
                                _sourcePhotos.isEmpty &&
                                !_loadingSourcePhotos &&
                                recipeRows(widget.recipe['photos']).isEmpty)
                              OutlinedButton.icon(
                                onPressed:
                                    _picking ||
                                        _saving ||
                                        (_draft['edit_options']
                                                as Map?)?['ai_images_enabled'] ==
                                            false
                                    ? null
                                    : _generatePhoto,
                                icon: const Icon(Icons.auto_awesome_outlined),
                                label: const Text('Generate an image with AI'),
                              ),
                          ],
                        ),
                        if (!_blank &&
                            (_draft['edit_options']
                                    as Map?)?['ai_images_enabled'] ==
                                false)
                          _help(
                            'AI image generation is disabled for this household. Ask the application administrator to enable it.',
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
                        if (!_blank &&
                            _rows('photos').isEmpty &&
                            _sourcePhotos.isEmpty &&
                            !_loadingSourcePhotos &&
                            recipeRows(widget.recipe['photos']).isEmpty)
                          const SizedBox.shrink(),
                        const Padding(
                          padding: EdgeInsets.only(top: 12),
                          child: Text('JPEG, PNG or WebP · up to 5 MB each'),
                        ),
                      ],
                      subtitle:
                          '${_rows('photos').length} ${_rows('photos').length == 1 ? 'photo' : 'photos'}${_sourcePhotos.isEmpty ? '' : ' · ${_sourcePhotos.length} suggested from import'}',
                    ),
                    if (!_blank) ...[
                      _section('Notes & source', Icons.notes_outlined, [
                        _field(_draft, 'notes', 'Recipe notes', lines: 3),
                        if (_draft['source_type'] == 'ai_variation')
                          _help(
                            'Recipe source: ${recipeSourceLabel(_draft['source_type'])}',
                          )
                        else
                          _field(
                            _draft,
                            'source_type',
                            'Recipe source',
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
                        if (widget.variationParentTitle != null)
                          _help('Parent recipe: ${widget.variationParentTitle}')
                        else
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
