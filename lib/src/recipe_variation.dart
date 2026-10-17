import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';

import 'api.dart';
import 'offline_recipes.dart';
import 'recipe_editor.dart';

/// Prepares a separate recipe draft. Only RecipeEditor's Save persists it.
class RecipeVariation extends StatefulWidget {
  const RecipeVariation({
    super.key,
    required this.householdId,
    required this.parentRecipeId,
    required this.parentTitle,
    required this.request,
  });

  final String householdId;
  final String parentRecipeId;
  final String parentTitle;
  final RecipeSave request;

  @override
  State<RecipeVariation> createState() => _RecipeVariationState();
}

class _RecipeVariationState extends State<RecipeVariation> {
  final _changes = TextEditingController();
  final _answerFields = <TextEditingController>[];
  final _answers = <Map<String, String>>[];
  late String _requestId;
  String? _attemptedChanges;
  List<String> _questions = [];
  Map<String, dynamic>? _draft;
  String? _changeDescription;
  String? _submittedChanges;
  String? _error;
  bool _busy = false, _reviewing = false, _leaving = false, _closing = false;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _requestId = _newRequestId();
    offlineStatus.addListener(_connectionChanged);
  }

  String _newRequestId() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  void _connectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    offlineStatus.removeListener(_connectionChanged);
    _changes.dispose();
    for (final field in _answerFields) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> _prepare() async {
    if (_busy || _reviewing || _leaving || offlineStatus.value) return;
    final changes = _submittedChanges ?? _changes.text.trim();
    if (changes.isEmpty) {
      setState(() => _error = 'Describe what you would like to change.');
      return;
    }
    if (_answerFields.any((field) => field.text.trim().isEmpty)) {
      setState(() => _error = 'Answer each question, or enter “unknown”.');
      return;
    }
    // A changed request is a new attempt; an unchanged retry remains idempotent.
    if (_attemptedChanges != null && _attemptedChanges != changes) {
      _requestId = _newRequestId();
    }
    _attemptedChanges = changes;
    final answers = [
      ..._answers,
      for (var i = 0; i < _questions.length; i++)
        {'question': _questions[i], 'answer': _answerFields[i].text.trim()},
    ];
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final data = await widget.request(
        '/households/${widget.householdId}/recipes/${widget.parentRecipeId}/variation',
        {
          'changes': changes,
          'request_id': _requestId,
          if (answers.isNotEmpty) 'answers': answers,
        },
      );
      if (!mounted || _leaving || generation != _generation) return;
      final questions = (data['questions'] as List).cast<String>();
      // Deep-copy before adding client safeguards: never mutate the source.
      final draft =
          jsonDecode(jsonEncode(data['recipe'])) as Map<String, dynamic>;
      draft.remove('id');
      draft['parent_recipe_id'] = widget.parentRecipeId;
      for (final field in _answerFields) {
        field.dispose();
      }
      setState(() {
        _submittedChanges = changes;
        _answers
          ..clear()
          ..addAll(answers);
        _draft = draft;
        _changeDescription = data['change_description'] is String
            ? (data['change_description'] as String).trim()
            : null;
        _questions = questions;
        _answerFields
          ..clear()
          ..addAll(questions.map((_) => TextEditingController()));
        _busy = false;
      });
      if (questions.isEmpty && !_closing) await _review();
    } catch (error) {
      if (mounted && !_leaving && generation == _generation) {
        setState(
          () => _error = error is ApiException ? error.message : 'Could not prepare your variation. Your input is still here; try again.',
        );
      }
    } finally {
      if (mounted && !_leaving && generation == _generation) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _review() async {
    if (_draft == null || _busy || _reviewing || _leaving) return;
    setState(() => _reviewing = true);
    final saved = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeEditor(
          recipe: _draft!,
          householdId: widget.householdId,
          variationParentTitle: widget.parentTitle,
          variationChangeDescription: _changeDescription,
          save: widget.request,
        ),
      ),
    );
    // Match the existing import approval flow: Cancel or Back ends the draft.
    if (mounted) await _leave(saved);
  }

  Future<void> _leave([Map<String, dynamic>? saved]) async {
    if (_leaving) return;
    ++_generation;
    setState(() => _leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, saved);
  }

  Future<void> _close() async {
    if (_closing || _leaving || _reviewing) return;
    if (_changes.text.isEmpty && _draft == null && !_busy) {
      await _leave();
      return;
    }
    _closing = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard recipe variation?'),
        content: const Text(
          'This variation has not been saved. Your original recipe is unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep working'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    _closing = false;
    if (discard == true && mounted) await _leave();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _leaving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Request variation'),
        leading: BackButton(onPressed: _close),
        actions: [TextButton(onPressed: _close, child: const Text('Cancel'))],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Variation of ${widget.parentTitle}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const SizedBox(height: 20),
              if (_submittedChanges == null)
                TextField(
                  controller: _changes,
                  enabled: !_busy,
                  minLines: 4,
                  maxLines: 10,
                  maxLength: 4000,
                  decoration: const InputDecoration(
                    labelText: 'What would you like to change?',
                    hintText: 'For example: make it dairy-free, use chicken instead, or adapt it for the slow cooker.',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                )
              else ...[
                Text(_submittedChanges!),
                const SizedBox(height: 20),
                Text(
                  _questions.isEmpty
                      ? 'Variation ready to review'
                      : 'A few details about your variation',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (var i = 0; i < _questions.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: TextField(
                      controller: _answerFields[i],
                      enabled: !_busy,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 2000,
                      decoration: InputDecoration(
                        labelText: _questions[i],
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
              ],
              if (offlineStatus.value)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text(
                    'Connect to the internet to request a variation.',
                  ),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _busy || _reviewing || offlineStatus.value
                    ? null
                    : _draft != null && _questions.isEmpty
                    ? _review
                    : _prepare,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  _busy
                      ? 'Preparing variation…'
                      : _draft != null && _questions.isEmpty
                      ? 'Review variation'
                      : _draft != null
                      ? 'Continue'
                      : 'Prepare variation',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
