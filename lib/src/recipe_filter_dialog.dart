import 'package:flutter/material.dart';

class RecipeFilterSelection {
  RecipeFilterSelection({
    required this.blankOnly,
    required Set<String> favoritePeople,
  }) : favoritePeople = Set.unmodifiable(favoritePeople);
  final bool blankOnly;
  final Set<String> favoritePeople;
}

class RecipeFilterDialog extends StatefulWidget {
  const RecipeFilterDialog({
    super.key,
    required this.blankOnly,
    required this.favoritePeople,
    required this.loadPeople,
  });
  final bool blankOnly;
  final Set<String> favoritePeople;
  final Future<List<Map<String, dynamic>>> Function() loadPeople;
  @override
  State<RecipeFilterDialog> createState() => _RecipeFilterDialogState();
}

class _RecipeFilterDialogState extends State<RecipeFilterDialog> {
  late bool _blankOnly;
  late Set<String> _selected;
  late bool _favoritesExpanded;
  List<Map<String, dynamic>> _people = [];
  bool _loading = true, _failed = false;
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _blankOnly = widget.blankOnly;
    _selected = Set.from(widget.favoritePeople);
    _favoritesExpanded = _selected.isNotEmpty;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final people = await widget.loadPeople();
      if (mounted) setState(() => _people = people);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String? get _summary {
    if (_selected.isEmpty) return null;
    final names = _people
        .where((p) => _selected.contains('${p['id']}'))
        .map((p) => '${p['display_name']}')
        .toList();
    return names.length == _selected.length
        ? names.join(', ')
        : '${_selected.length} selected';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AlertDialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: MediaQuery.sizeOf(context).width < 400 ? 16 : 40,
        vertical: 24,
      ),
      title: Row(
        children: [
          const Expanded(child: Text('Filters')),
          TextButton(
            onPressed: !_blankOnly && _selected.isEmpty
                ? null
                : () => setState(() {
                    _blankOnly = false;
                    _selected.clear();
                  }),
            child: const Text('Clear'),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      content: SizedBox(
        width: 360,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * .5,
          ),
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scroll,
              child: ListTileTheme(
                data: ListTileTheme.of(context)
                    .copyWith(minLeadingWidth: 24, horizontalTitleGap: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.note_alt_outlined),
                      controlAffinity: ListTileControlAffinity.trailing,
                      title: const Text('Blank recipes only'),
                      value: _blankOnly,
                      onChanged: (value) =>
                          setState(() => _blankOnly = value == true),
                    ),
                    const Divider(height: 16),
                    ExpansionTile(
                      initiallyExpanded: _selected.isNotEmpty,
                      onExpansionChanged: (value) =>
                          setState(() => _favoritesExpanded = value),
                      trailing: SizedBox(
                        width: 48,
                        height: 48,
                        child: Icon(
                          _favoritesExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                        ),
                      ),
                      tilePadding: EdgeInsets.zero,
                      leading: Icon(
                        _selected.isEmpty
                            ? Icons.favorite_border
                            : Icons.favorite,
                        color: _selected.isEmpty ? null : colors.primary,
                      ),
                      title: const Text('Favorite'),
                      subtitle: _summary == null
                          ? null
                          : Text(
                              _summary!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      childrenPadding: const EdgeInsets.only(left: 36),
                      children: [
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: LinearProgressIndicator(),
                          )
                        else if (_failed)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: _load,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                            ),
                          )
                        else if (_people.isEmpty)
                          const ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text('No household members'),
                          )
                        else
                          for (final person in _people)
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              controlAffinity: ListTileControlAffinity.trailing,
                              title: Text('${person['display_name']}'),
                              value: _selected.contains('${person['id']}'),
                              onChanged: (value) => setState(() {
                                if (value == true) {
                                  _selected.add('${person['id']}');
                                } else {
                                  _selected.remove('${person['id']}');
                                }
                              }),
                            ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            RecipeFilterSelection(
              blankOnly: _blankOnly,
              favoritePeople: _selected,
            ),
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
