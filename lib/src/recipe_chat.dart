import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ai_progress.dart';
import 'api.dart';
import 'child_mode.dart';
import 'offline_recipes.dart';
import 'recipe_editor.dart';

enum RecipeChatOutcome { create, variation, edit }

class RecipeChat extends StatefulWidget {
  const RecipeChat({
    super.key,
    required this.householdId,
    required this.request,
    this.recipeId,
    this.recipeTitle,
  });

  final String householdId;
  final RecipeSave request;
  final String? recipeId;
  final String? recipeTitle;

  @override
  State<RecipeChat> createState() => _RecipeChatState();
}

class _RecipeChatState extends State<RecipeChat> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final _inputFocus = FocusNode(onKeyEvent: _handleKey);
  int _tab = 0;
  String _workingRecipe = '', _previousRecipe = '';
  bool _recipeChanged = false;
  final _progress = AiRunProgress();
  final _messages = <({bool user, String text})>[];
  late final String _session = _identity();
  late RecipeChatOutcome _outcome = widget.recipeId == null
      ? RecipeChatOutcome.create
      : RecipeChatOutcome.variation;
  int _revision = 0;
  bool _busy = false, _ready = false, _leaving = false, _reviewing = false;
  bool _closing = false, _retryRequired = false;
  String? _error;
  Map<String, dynamic>? _attempt;
  Map<String, dynamic>? _draft;

  String _identity() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  String get _title => switch (_outcome) {
    RecipeChatOutcome.create => 'Create a dish with AI',
    RecipeChatOutcome.variation => 'Create a new variation',
    RecipeChatOutcome.edit => 'Edit this recipe with AI',
  };

  String get _outcomeHelp => switch (_outcome) {
    RecipeChatOutcome.create => 'Save will create a new recipe.',
    RecipeChatOutcome.variation => 'Save will create a linked variation. The original recipe stays unchanged.',
    RecipeChatOutcome.edit =>
      'Save will update ${widget.recipeTitle ?? 'the current recipe'}.',
  };

  @override
  void initState() {
    super.initState();
    offlineStatus.addListener(_changed);
    _input.addListener(_changed);
    _inputFocus.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    offlineStatus.removeListener(_changed);
    _inputFocus.dispose();
    _input.dispose();
    _scroll.dispose();
    _progress.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return KeyEventResult.ignored;
    }
    // Let the input method finish composition before treating Enter as Send.
    if (_input.value.composing.isValid && !_input.value.composing.isCollapsed) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) {
      if (HardwareKeyboard.instance.isShiftPressed) {
        if (!_busy && !_reviewing && !_retryRequired) {
          final selection = _input.selection;
          final start = selection.isValid
              ? selection.start
              : _input.text.length;
          final end = selection.isValid ? selection.end : start;
          _input.value = TextEditingValue(
            text: _input.text.replaceRange(start, end, '\n'),
            selection: TextSelection.collapsed(offset: start + 1),
          );
        }
      } else {
        _submit();
      }
    }
    return KeyEventResult.handled;
  }

  void _selectTab(int tab) {
    if (tab == 1) _inputFocus.unfocus();
    setState(() => _tab = tab);
  }

  Widget _workingRecipeView() {
    if (_workingRecipe.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Your working recipe will appear here as you chat.'),
        ),
      );
    }
    final previousLines = _previousRecipe.split('\n').toSet();
    return SingleChildScrollView(
      key: const PageStorageKey('working-recipe'),
      padding: const EdgeInsets.all(16),
      child: SelectableText.rich(
        TextSpan(
          children: [
            for (final line in _workingRecipe.split('\n'))
              TextSpan(
                text: '$line\n',
                style:
                    _previousRecipe.isNotEmpty &&
                        line.trim().isNotEmpty &&
                        !previousLines.contains(line)
                    ? TextStyle(
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .secondaryContainer,
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _submit({bool prepare = false}) async {
    if (_busy ||
        _reviewing ||
        _leaving ||
        childMode.value ||
        offlineStatus.value) {
      return;
    }
    final text = _input.text.trim();
    if (!prepare && text.isEmpty) return;
    if (prepare && (!_ready || text.isNotEmpty)) return;
    final action = prepare ? 'prepare' : 'message';
    if (_attempt?['action'] != action ||
        _attempt?['message'] != (prepare ? '' : text)) {
      _attempt = {
        'request_id': _session,
        'turn_id': _identity(),
        'revision': _revision,
        'mode': _outcome.name,
        'action': action,
        'draft_view': true,
        'message': prepare ? '' : text,
        if (widget.recipeId != null) 'recipe_id': widget.recipeId,
      };
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    _scrollToLatest();
    try {
      final response = await _progress.run(
        () => widget.request(
          '/households/${widget.householdId}/recipe-chat',
          _attempt!,
        ),
      );
      if (!mounted || _leaving) return;
      final message = response['message'];
      final revision = response['revision'];
      final ready = response['ready'];
      final draft = response['draft'];
      final recipeText = response['recipe_text'];
      if (recipeText is! String ||
          message is! String ||
          message.trim().isEmpty ||
          revision is! int ||
          revision != _revision + 1 ||
          ready is! bool ||
          (draft != null &&
              (draft is! Map<String, dynamic> ||
                  draft['recipe'] is! Map<String, dynamic> ||
                  draft['recipe']['title'] is! String ||
                  draft['recipe']['ingredients'] is! List ||
                  draft['recipe']['steps'] is! List))) {
        throw ApiException(
          502,
          'AI returned an incomplete reply. Please try again.',
        );
      }
      if (draft != null) {
        final recipe = draft['recipe'] as Map<String, dynamic>;
        if (_outcome == RecipeChatOutcome.edit) {
          if (recipe['id']?.toString() != widget.recipeId) {
            throw ApiException(
              502,
              'AI could not prepare the selected recipe for editing.',
            );
          }
        } else {
          recipe.remove('id');
          if (_outcome == RecipeChatOutcome.variation &&
              recipe['parent_recipe_id']?.toString() != widget.recipeId) {
            throw ApiException(
              502,
              'AI could not prepare the selected variation.',
            );
          }
        }
      }
      setState(() {
        if (!prepare) _messages.add((user: true, text: text));
        _messages.add((user: false, text: message));
        _recipeChanged = recipeText != _workingRecipe;
        if (_recipeChanged) _previousRecipe = _workingRecipe;
        _workingRecipe = recipeText;
        _revision = revision;
        _ready = ready;
        _draft = draft == null
            ? null
            : jsonDecode(jsonEncode(draft)) as Map<String, dynamic>;
        _attempt = null;
        _retryRequired = false;
        _busy = false;
        if (!prepare) _input.clear();
      });
      _scrollToLatest();
      if (draft != null && !_closing) await _review();
    } catch (error) {
      if (mounted && !_leaving) {
        setState(() {
          // An uncertain response may already be committed on the VPS. Recover
          // that exact turn before accepting a different message/revision.
          _retryRequired =
              !(error is ApiException &&
                  [
                    'ai_unavailable',
                    'ai_timeout',
                    'invalid_ai_reply',
                    'invalid_recipe_chat',
                    'invalid_import',
                    'chat_not_ready',
                  ].contains(error.code));
          _error = error is ApiException ? error.message : 'Could not reach AI. Your conversation and message are still here; please try again.';
          if (_retryRequired) {
            _error =
                '$_error Retry the last request before changing your message.';
          }
        });
      }
    } finally {
      if (mounted && !_leaving) setState(() => _busy = false);
    }
  }

  Future<void> _review() async {
    if (_draft == null || _reviewing || _leaving || childMode.value) return;
    setState(() => _reviewing = true);
    final saved = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeEditor(
          recipe: _draft!['recipe'] as Map<String, dynamic>,
          householdId: widget.householdId,
          save: widget.request,
          variationParentTitle: _outcome == RecipeChatOutcome.variation
              ? widget.recipeTitle
              : null,
          variationChangeDescription: _outcome == RecipeChatOutcome.variation
              ? _draft!['change_description'] as String?
              : null,
        ),
      ),
    );
    if (!mounted || _leaving) return;
    setState(() => _reviewing = false);
    if (saved != null) {
      await _leave(saved);
    }
  }

  Future<void> _leave([Map<String, dynamic>? saved]) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.pop(context, saved);
  }

  Future<void> _close() async {
    if (_leaving || _closing) return;
    if (_messages.isNotEmpty || _input.text.trim().isNotEmpty || _busy) {
      _closing = true;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Discard recipe chat?'),
          content: const Text(
            'This conversation has not been saved as a recipe.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep chatting'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      _closing = false;
      if (discard != true || !mounted) return;
    }
    await _leave();
  }

  Widget _bubble(bool user, String text) => Align(
    alignment: user ? Alignment.centerRight : Alignment.centerLeft,
    child: FractionallySizedBox(
      widthFactor: .9,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: user
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              user ? 'You' : 'AI',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            SelectableText(text),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (childModeOf(context)) {
      return const Scaffold(
        body: SafeArea(
          child: Center(child: Text('Unavailable in child mode.')),
        ),
      );
    }
    final canSend =
        !_busy &&
        !_reviewing &&
        !offlineStatus.value &&
        _input.text.trim().isNotEmpty;
    return PopScope(
      canPop: _leaving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: DefaultTabController(
        length: 2,
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            title: Text(_title),
            leading: BackButton(onPressed: _close),
            bottom: TabBar(
              onTap: _selectTab,
              tabs: const [
                Tab(text: 'Chat'),
                Tab(text: 'Working recipe'),
              ],
            ),
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  children: [
                    Expanded(
                      child: IndexedStack(
                        index: _tab,
                        children: [
                          ListView(
                            controller: _scroll,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  8,
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (widget.recipeId != null &&
                                        _revision == 0 &&
                                        !_busy &&
                                        _attempt == null)
                                      DropdownButtonFormField<
                                        RecipeChatOutcome
                                      >(
                                        initialValue: _outcome,
                                        isExpanded: true,
                                        decoration: const InputDecoration(
                                          labelText:
                                              'What should this chat produce?',
                                        ),
                                        items: const [
                                          DropdownMenuItem(
                                            value: RecipeChatOutcome.variation,
                                            child: Text(
                                              'Create a new variation',
                                            ),
                                          ),
                                          DropdownMenuItem(
                                            value: RecipeChatOutcome.edit,
                                            child: Text('Edit this recipe'),
                                          ),
                                        ],
                                        onChanged: (value) {
                                          if (value != null) {
                                            setState(() => _outcome = value);
                                          }
                                        },
                                      ),
                                    Text(_outcomeHelp),
                                  ],
                                ),
                              ),
                              _bubble(
                                false,
                                widget.recipeId == null
                                    ? 'What would you like to make? Describe your dish, or ask me to help develop one. We can explore ideas and discuss how changes would affect it.'
                                    : 'What would you like to improve about ${widget.recipeTitle ?? 'this recipe'}? Ask for suggestions, explore a change, or tell me what to adjust. We’ll try changes in the working draft as we discuss them. Say ‘just explain’ to leave it unchanged.',
                              ),
                              for (final message in _messages)
                                _bubble(message.user, message.text),
                              if (_busy && _attempt?['action'] == 'message')
                                _bubble(true, _attempt!['message'] as String),
                              if (_busy)
                                Semantics(
                                  liveRegion: true,
                                  child: _bubble(false, 'AI is thinking…'),
                                ),
                              if (_recipeChanged && _workingRecipe.isNotEmpty)
                                Builder(
                                  builder: (tabContext) => TextButton(
                                    onPressed: () {
                                      DefaultTabController.of(tabContext)
                                          .animateTo(1);
                                      _selectTab(1);
                                    },
                                    child: const Text('View changes'),
                                  ),
                                ),
                              AiProgressText(_progress),
                              if (offlineStatus.value)
                                const Text(
                                  'Connect to the internet to continue chatting.',
                                ),
                              if (_error != null)
                                Semantics(
                                  liveRegion: true,
                                  child: Text(
                                    _error!,
                                    style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          _workingRecipeView(),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_ready)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: OutlinedButton.icon(
                                onPressed:
                                    _busy ||
                                        offlineStatus.value ||
                                        _input.text.trim().isNotEmpty
                                    ? null
                                    : _draft != null
                                    ? _review
                                    : () => _submit(prepare: true),
                                icon: const Icon(Icons.rate_review_outlined),
                                label: const Text('Review recipe'),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_tab == 0)
                      Padding(
                        // The app's floating keyboard-dismiss control occupies the
                        // lower right while the software keyboard is visible.
                        padding: EdgeInsets.fromLTRB(
                          12,
                          12,
                          MediaQuery.viewInsetsOf(context).bottom > 0 ? 68 : 12,
                          12 +
                              (Theme.of(context).platform ==
                                          TargetPlatform.iOS &&
                                      _inputFocus.hasFocus
                                  ? (64 -
                                            MediaQuery.viewInsetsOf(context)
                                                .bottom)
                                        .clamp(0, 64)
                                        .toDouble()
                                  : 0),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _input,
                                focusNode: _inputFocus,
                                readOnly: _busy || _reviewing || _retryRequired,
                                keyboardType: TextInputType.multiline,
                                textInputAction: TextInputAction.send,
                                onEditingComplete: () {},
                                onSubmitted: (_) => _submit(),
                                minLines: 1,
                                maxLines: 4,
                                maxLength: 4000,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                decoration: const InputDecoration(
                                  labelText: 'Message AI',
                                  hintText:
                                      'Ask a question or describe a change…',
                                  border: OutlineInputBorder(),
                                  counterText: '',
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton.filled(
                              onPressed: canSend ? () => _submit() : null,
                              tooltip: 'Send',
                              icon: const Icon(Icons.send),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
