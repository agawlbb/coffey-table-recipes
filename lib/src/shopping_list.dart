import 'offline_recipes.dart';
import 'child_mode.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import 'api.dart';
import 'local_data.dart';
import 'shopping_item_id.dart';
import 'shopping_list_cache.dart';
import 'shopping_photo.dart';

const shoppingDepartments = [
  'Other',
  'Produce',
  'Dairy & eggs',
  'Meat & seafood',
  'Bakery',
  'Pantry',
  'Frozen',
  'Deli',
  'Drinks',
  'Household',
];

typedef ShoppingRequest = Future<Map<String, dynamic>> Function(
  String path, {
  Map<String, dynamic>? body,
});

class ShoppingListScreen extends StatefulWidget {
  const ShoppingListScreen({
    super.key,
    required this.householdId,
    required this.householdName,
    required this.request,
    this.embedded = false,
    this.active = true,
    this.cache,
    this.localFirst = false,
    this.requestSynchronization,
    this.pickPhoto,
  });
  final String householdId;
  final String householdName;
  final ShoppingRequest request;
  final Future<Uint8List?> Function(ShoppingPhotoSource)? pickPhoto;
  final bool embedded;
  final bool active;
  final ShoppingListCache? cache;
  final bool localFirst;
  final Future<void> Function()? requestSynchronization;

  @override
  State<ShoppingListScreen> createState() => _ShoppingListScreenState();
}

class _ShoppingListScreenState extends State<ShoppingListScreen>
    with WidgetsBindingObserver {
  final _name = TextEditingController();
  final _focus = FocusNode();
  final _editName = TextEditingController();
  final _editFocus = FocusNode();
  final _editNote = TextEditingController();
  final _noteFocus = FocusNode();
  final _editGroup = Object();
  String? _editingId;
  String _editPhoto = '';
  bool _photoBusy = false;
  String? _photoError;

  void _editFocusChanged() {
    scheduleMicrotask(() {
      if (mounted &&
          !_photoBusy &&
          !_editFocus.hasFocus &&
          !_noteFocus.hasFocus) {
        _finishEditing();
      }
    });
  }

  void _startEditing(Map<String, dynamic> item) {
    if (childMode.value || _displayPause != null || _photoBusy) return;
    if (_heldItemId == item['id']) return;
    _finishEditing();
    _editPhoto = item['photo'] as String? ?? '';
    _photoError = null;
    _editName.text = item['name'] as String;
    _editNote.text = item['note'] as String? ?? '';
    _editName.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _editName.text.length,
    );
    setState(() => _editingId = item['id'] as String);
    _editFocus.requestFocus();
  }

  void _finishEditing() {
    final id = _editingId;
    if (id == null || _photoBusy) return;
    final name = _editName.text.trim();
    final note = _editNote.text.trim();
    final photo = _editPhoto;
    setState(() => _editingId = null);
    _editFocus.unfocus();
    _noteFocus.unfocus();
    final item = _items.where((i) => i['id'] == id).firstOrNull;
    if (item == null ||
        name.isEmpty ||
        (name == item['name'] &&
            note == (item['note'] ?? '') &&
            photo == (item['photo'] ?? ''))) {
      return;
    }
    _save([
      for (final i in _items)
        i['id'] == id
            ? {
                ...i,
                'name': name,
                if (note.isNotEmpty || i.containsKey('note')) 'note': note,
                if (photo.isNotEmpty || i.containsKey('photo')) 'photo': photo,
              }
            : i,
    ]);
  }

  Future<void> _attachPhoto() async {
    if (_photoBusy || _editingId == null || childMode.value) return;
    final id = _editingId;
    setState(() {
      _photoBusy = true;
      _photoError = null;
    });
    try {
      final source = await showModalBottomSheet<ShoppingPhotoSource>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt_outlined),
                title: const Text('Camera'),
                onTap: () => Navigator.pop(context, ShoppingPhotoSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: const Text('Choose file'),
                onTap: () => Navigator.pop(context, ShoppingPhotoSource.file),
              ),
              ListTile(
                leading: const Icon(Icons.content_paste),
                title: const Text('Paste image'),
                onTap: () =>
                    Navigator.pop(context, ShoppingPhotoSource.clipboard),
              ),
            ],
          ),
        ),
      );
      if (source == null || !mounted) return;
      final bytes =
          await (widget.pickPhoto?.call(source) ??
              pickShoppingPhoto(context, source));
      if (bytes == null || !mounted || _editingId != id || childMode.value) {
        return;
      }
      if (bytes.length > 5 * 1024 * 1024) {
        throw const FormatException('Choose an image of at most 5 MB.');
      }
      final result = await widget.request(
        '$_path/photos',
        body: {'image_base64': base64Encode(bytes)},
      );
      final photo = result['photo'];
      if (photo is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(photo)) {
        throw const FormatException(
          'The photo could not be saved. Please try again.',
        );
      }
      if (mounted && _editingId == id) setState(() => _editPhoto = photo);
    } catch (error) {
      if (mounted && _editingId == id) {
        setState(
          () => _photoError = error is FormatException ? error.message : 'Could not attach the photo. Check permissions and your connection, then try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _photoBusy = false);
        if (_editingId == id) _noteFocus.requestFocus();
      }
    }
  }

  Future<void> _viewPhoto(String photo, String id) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ShoppingPhotoViewer(
            load: () => widget.request('$_path/photos/$photo'),
            onDelete: childMode.value
                ? null
                : () async {
                    if (childMode.value || !mounted) return false;
                    final item = _items.where((i) => i['id'] == id).firstOrNull;
                    final saved =
                        item == null ||
                        item['photo'] != photo ||
                        await _save([
                          for (final i in _items)
                            i['id'] == id ? {...i, 'photo': ''} : i,
                        ]);
                    if (saved &&
                        mounted &&
                        _editingId == id &&
                        _editPhoto == photo) {
                      setState(() => _editPhoto = '');
                    }
                    return saved;
                  },
          ),
        ),
      );

  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _confirmedItems = [];
  bool _holding = false;
  String? _heldItemId;
  Timer? _holdTimer;
  int? _holdPointer;
  Offset? _holdOrigin;
  Offset _pressAnchor = Offset.zero;
  bool _dropMoved = false;
  List<String> _departments = [
    ...shoppingDepartments.where((d) => d != 'Other'),
    'Other',
  ];
  int _revision = 0;
  int _saveGeneration = 0;
  bool _loading = true, _saving = false, _reading = false;
  bool _reloadAfterSave = false;
  bool _dragging = false;
  bool _routeVisible = false;
  bool _rateLimited = false;
  bool _disconnected = false, _accessDenied = false, _serverLoaded = false;
  final _listController = ScrollController();
  final _listKey = GlobalKey();
  Timer? _autoScroll;
  double _scrollStep = 0;
  Offset? _dragPosition;
  String? _error;
  bool _saveNotice = false;
  final _offlineChecks = <String, bool>{};
  Timer? _displayPause;
  final _pendingCompletion = <String, Timer>{};

  bool _atBottom(Map<String, dynamic> item) =>
      item['checked'] == true && !_pendingCompletion.containsKey(item['id']);

  void _setItems(
    List<Map<String, dynamic>> items, {
    bool remote = false,
    bool initial = false,
  }) {
    final previouslyChecked = {
      for (final item in _items)
        if (item['checked'] == true) item['id'],
    };
    final checked = {
      for (final item in items)
        if (item['checked'] == true) item['id'] as String,
    };
    for (final id in _pendingCompletion.keys.toList()) {
      if (!checked.contains(id)) _pendingCompletion.remove(id)?.cancel();
    }
    if (!initial) {
      for (final id in checked.difference(previouslyChecked)) {
        _pendingCompletion[id] = Timer(const Duration(seconds: 5), () {
          if (!mounted) return;
          setState(() {
            _pendingCompletion.remove(id);
            // The delayed move is still a remote display change when the
            // check arrived from another device. Keep an active inline
            // editor intact, as incoming refreshes do while editing.
            if (remote && _editingId == null) _pauseEdits();
          });
        });
      }
    }
    _items = items;
  }

  // A changed row can put a different item under an incoming tap. Only actual
  // incoming display changes restart the pause; local saves never do so.
  void _pauseAfterDisplayChange(Object before) {
    if (before == jsonEncode([_items, _departments])) return;
    _pauseEdits();
  }

  void _pauseEdits() {
    _displayPause?.cancel();
    _displayPause = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _displayPause = null);
    });
  }

  String get _path => '/households/${widget.householdId}/shopping-list';

  @override
  void initState() {
    super.initState();
    _editFocus.addListener(_editFocusChanged);
    _noteFocus.addListener(_editFocusChanged);
    WidgetsBinding.instance.addObserver(this);
    if (widget.localFirst) localDataChanges.addListener(_localChanged);
    _restoreCache();
    if (widget.active) _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible = ModalRoute.of(context)?.isCurrent ?? true;
    final opening = visible && !_routeVisible;
    _routeVisible = visible;
    if (opening && widget.active) _opened();
  }

  @override
  void didUpdateWidget(covariant ShoppingListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active && _routeVisible) _opened();
  }

  void _opened() {
    _load();
    unawaited(_requestSynchronization());
  }

  Future<void> _requestSynchronization() async {
    try {
      await widget.requestSynchronization?.call();
    } catch (_) {
      // External synchronization is best effort and must not block the list.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (widget.active && _routeVisible && state == AppLifecycleState.resumed) {
      _load();
    }
  }

  void _accept(Map<String, dynamic> data, {bool remote = true}) {
    final before = jsonEncode([_items, _departments]);
    final wasDisplayed = !_loading;
    _departments =
        (data['departments'] as List?)?.cast<String>() ?? _departments;
    _revision = data['revision'] as int;
    _setItems(
      (data['items'] as List)
          .map(
            (item) => {
              ...Map<String, dynamic>.from(item as Map),
              if (_offlineChecks.containsKey(item['id']))
                'checked': _offlineChecks[item['id']],
            },
          )
          .toList(),
      remote: remote,
      initial: !wasDisplayed,
    );
    _confirmedItems = _items;
    if (remote && wasDisplayed) _pauseAfterDisplayChange(before);
  }

  void _localChanged() {
    if (_saving) {
      _reloadAfterSave = true;
      return;
    }
    if (mounted &&
        (localDataChanges.value.startsWith(_path) ||
            localDataChanges.value.startsWith('/me#'))) {
      _load();
    }
  }

  Future<void> _restoreCache() async {
    if (widget.localFirst) return; // LocalData is the single durable source.
    final data = await widget.cache?.read();
    if (data != null &&
        mounted &&
        !_serverLoaded &&
        !_saving &&
        !_accessDenied) {
      setState(() {
        _accept(data);
        _loading = false;
      });
    }
  }

  void _cacheConfirmed() {
    if (widget.localFirst) return;
    unawaited(
      widget.cache?.save({
        'revision': _revision,
        'items': _confirmedItems,
        'departments': _departments,
      }),
    );
  }

  bool _connectionFailure(Object error) =>
      error is! ApiException || isTemporaryCommunicationFailure(error);

  Future<Map<String, dynamic>> _requestWithRetry({
    Map<String, dynamic>? body,
  }) => widget.request(_path, body: body);

  Future<void> _load() async {
    if (_saving || _reading || _dragging || _holding || _editingId != null) {
      return;
    }
    _reading = true;
    final generation = _saveGeneration;
    try {
      final data = await _requestWithRetry();
      if (!mounted) return;
      final firstResponse = !_serverLoaded;
      _serverLoaded = true;
      if (!_saving &&
          !_holding &&
          !_dragging &&
          _editingId == null &&
          generation == _saveGeneration) {
        final changed =
            firstResponse ||
            _loading ||
            data['revision'] != _revision ||
            jsonEncode(data['items']) != jsonEncode(_items) ||
            jsonEncode(data['departments']) != jsonEncode(_departments);
        if (changed ||
            (_disconnected && !widget.localFirst) ||
            _accessDenied ||
            _error != null) {
          setState(() {
            if (changed) _accept(data);
            _disconnected = false;
            _rateLimited = false;
            _accessDenied = false;
            if (!_saveNotice) _error = null;
          });
        }
        if (changed) _cacheConfirmed();
      }
    } catch (error) {
      if (!mounted) return;
      if (_connectionFailure(error)) {
        setState(() {
          _disconnected = true;
          _rateLimited = error is ApiException && error.status == 429;
        });
      } else {
        final denied =
            error is ApiException && [401, 403, 404].contains(error.status);
        if (denied) unawaited(widget.cache?.clear());
        setState(() {
          _disconnected = false;
          if (denied) {
            _accessDenied = true;
            _setItems([]);
            _confirmedItems = [];
            _revision = 0;
          }
          _saveNotice = false;
          _error = (error as ApiException).message;
        });
      }
    } finally {
      _reading = false;
      if (mounted && _loading) setState(() => _loading = false);
    }
  }

  Future<bool> _save(List<Map<String, dynamic>> items) async {
    if (childMode.value || _displayPause != null || _saving || _accessDenied) {
      return false;
    }
    if (widget.localFirst && offlineStatus.value) {
      // Checkboxes prepare the items to remove; only Remove checked off queues a removal.
      final before = {for (final item in _items) item['id']: item};
      final checksOnly =
          items.length == _items.length &&
          items.every(
            (item) =>
                before.containsKey(item['id']) &&
                jsonEncode({...item, 'checked': false}) ==
                    jsonEncode({...before[item['id']]!, 'checked': false}),
          );
      if (checksOnly) {
        for (final item in items) {
          _offlineChecks[item['id'] as String] = item['checked'] as bool;
        }
        setState(() => _setItems(items));
        return true;
      }
      setState(
        () => _error = 'Only item removals can be saved offline. Reconnect to make other shopping changes.',
      );
      return false;
    }
    _saveGeneration++;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final data = await widget.request(_path, body: {'items': items});
      if (!mounted) return true;
      setState(() {
        _accept(data, remote: false);
        _disconnected = false;
        _offlineChecks.clear();
      });
      _cacheConfirmed();
      return true;
    } catch (error) {
      if (mounted) {
        setState(() {
          _saveNotice = _connectionFailure(error);
          _error = _saveNotice
              ? 'Your change wasn’t saved. Reconnect and try again.'
              : error is ApiException
              ? error.message
              : 'Could not save the shopping list.';
        });
      }
      return false;
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        if (_reloadAfterSave) {
          _reloadAfterSave = false;
          unawaited(_load());
        }
      }
    }
  }

  Future<void> _removeChecked() async {
    if (_saving || childMode.value) return;
    final ids = _items
        .where((i) => i['checked'] == true)
        .map((i) => i['id'] as String)
        .toList();
    if (ids.isEmpty) return;
    setState(() => _saving = true);
    try {
      final data = await widget.request(_path, body: {'remove_ids': ids});
      if (!mounted) return;
      setState(() {
        for (final id in ids) {
          _offlineChecks.remove(id);
        }
        _accept(data, remote: false);
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : 'These items couldn’t be removed. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        if (_reloadAfterSave) {
          _reloadAfterSave = false;
          unawaited(_load());
        }
      }
    }
  }

  Future<void> _add() async {
    if (childMode.value || _displayPause != null) return;
    final name = _name.text.trim();
    if (name.isEmpty) {
      _focus.requestFocus();
      return;
    }
    if (name.length > 200 || _items.length >= 500) return;
    final saved = await _save([
      ..._items,
      {
        'id': newShoppingItemId(),
        'name': name,
        'department': '',
        'checked': false,
      },
    ]);
    if (saved && mounted) {
      _name.clear();
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _dragging = false;
    _holding = false;
    _holdTimer?.cancel();
    localDataChanges.removeListener(_localChanged);
    _displayPause?.cancel();
    for (final timer in _pendingCompletion.values) {
      timer.cancel();
    }
    _pendingCompletion.clear();
    _autoScroll?.cancel();
    _listController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _editFocus.removeListener(_editFocusChanged);
    _editFocus.dispose();
    _editName.dispose();
    _noteFocus.removeListener(_editFocusChanged);
    _noteFocus.dispose();
    _editNote.dispose();
    _name.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _rows => [
    {'heading': ''},
    ..._items.where((item) => item['department'] == '' && !_atBottom(item)),
    for (final department in _departments)
      if (_holding ||
          _dragging ||
          _items.any(
            (item) => item['department'] == department && !_atBottom(item),
          )) ...[
        {'heading': department},
        ..._items.where(
          (item) => item['department'] == department && !_atBottom(item),
        ),
      ],
    if (_items.any((item) => _atBottom(item))) ...[
      {'completed': true},
      ..._items.where((item) => _atBottom(item)),
    ],
  ];

  void _pressItem(PointerDownEvent event, String id, BuildContext rowContext) {
    if (_displayPause != null ||
        _editingId == id ||
        _loading ||
        (_disconnected && !widget.localFirst) ||
        _accessDenied ||
        event.buttons != kPrimaryButton ||
        _holdPointer != null) {
      return;
    }
    _heldItemId = null;
    _dropMoved = false;
    final box = rowContext.findRenderObject() as RenderBox;
    _pressAnchor = box.globalToLocal(event.position);
    _holdPointer = event.pointer;
    _holdOrigin = event.position;
    _holdTimer?.cancel();
    _holdTimer = Timer(kLongPressTimeout, () {
      if (!mounted || _holdPointer == null) return;
      setState(() {
        _holding = true;
        _heldItemId = id;
      });
    });
  }

  void _movePress(PointerMoveEvent event) {
    if (event.pointer == _holdPointer &&
        _holdOrigin != null &&
        (event.position - _holdOrigin!).distance > kTouchSlop) {
      _dropMoved = true;
    }
    if (event.pointer == _holdPointer &&
        !_holding &&
        _holdOrigin != null &&
        (event.position - _holdOrigin!).distance > kTouchSlop) {
      _holdTimer?.cancel();
    }
  }

  void _endPress(PointerEvent event) {
    if (event.pointer != _holdPointer) return;
    _holdTimer?.cancel();
    _holdPointer = null;
    _holdOrigin = null;
    if (_holding && mounted) setState(() => _holding = false);
  }

  void _dragStarted() {
    _holdTimer?.cancel();
    setState(() => _dragging = true);
    _dragPosition = null;
    _autoScroll?.cancel();
    _autoScroll = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!_listController.hasClients || _scrollStep == 0) return;
      final position = _listController.position;
      _listController.jumpTo(
        (_listController.offset + _scrollStep).clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
    });
  }

  void _dragUpdated(DragUpdateDetails details) {
    _updateDragPosition(details.globalPosition);
  }

  void _updateDragPosition(Offset position) {
    _dragPosition = position;
    final box = _listKey.currentContext?.findRenderObject();
    if (box is! RenderBox) return;
    final y = box.globalToLocal(position).dy;
    _scrollStep = y < 48
        ? -12
        : y > box.size.height - 48
        ? 12
        : 0;
  }

  void _dragFinished() {
    final wasDragging = _dragging;
    _dragging = false;
    _scrollStep = 0;
    _autoScroll?.cancel();
    _autoScroll = null;
    _dragPosition = null;
    if (mounted && wasDragging) setState(() {});
  }

  void _dropItem(
    String id,
    String department, {
    String? target,
    bool after = false,
  }) {
    final original = _items.where((item) => item['id'] == id).firstOrNull;
    if (_displayPause != null ||
        !_dropMoved ||
        original == null ||
        target == id ||
        (_disconnected && !widget.localFirst) ||
        _accessDenied) {
      return;
    }
    final items = _items.where((item) => item['id'] != id).toList();
    final targetIndex = target == null
        ? -1
        : items.indexWhere((item) => item['id'] == target);
    final index = targetIndex >= 0
        ? targetIndex + (after ? 1 : 0)
        : items.lastIndexWhere((item) => item['department'] == department) + 1;
    items.insert(index, {
      ...original,
      'department': original['checked'] == true
          ? original['department']
          : department,
    });
    if (List.generate(
      items.length,
      (i) =>
          items[i]['id'] == _items[i]['id'] &&
          items[i]['department'] == _items[i]['department'],
    ).every((same) => same)) {
      return;
    }
    _save(items);
  }

  Widget _itemCard(
    Map<String, dynamic> item,
    bool busy, {
    bool highlighted = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final checked = item['checked'] == true;
    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      child: Semantics(
        toggled: checked,
        child: Card(
          margin: EdgeInsets.only(
            left: !_atBottom(item) && item['department'] != '' ? 16 : 0,
            bottom: 6,
          ),
          clipBehavior: Clip.antiAlias,
          color: highlighted ? colors.primaryContainer : null,
          child: _editingId == item['id'] && !busy
              ? Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  child: TextFieldTapRegion(
                    groupId: _editGroup,
                    onTapOutside: (_) => _finishEditing(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          groupId: _editGroup,
                          key: ValueKey('edit-${item['id']}'),
                          controller: _editName,
                          focusNode: _editFocus,
                          autofocus: true,
                          maxLength: 200,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Item',
                            counterText: '',
                          ),
                          onSubmitted: (_) => _noteFocus.requestFocus(),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                groupId: _editGroup,
                                key: ValueKey('note-${item['id']}'),
                                controller: _editNote,
                                focusNode: _noteFocus,
                                maxLength: 500,
                                minLines: 1,
                                maxLines: 3,
                                textCapitalization:
                                    TextCapitalization.sentences,
                                textInputAction: TextInputAction.done,
                                decoration: const InputDecoration(
                                  labelText: 'Note',
                                  counterText: '',
                                ),
                                onSubmitted: (_) => _finishEditing(),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Save item',
                              onPressed: _photoBusy ? null : _finishEditing,
                              icon: const Icon(Icons.check),
                            ),
                          ],
                        ),
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: _photoBusy ? null : _attachPhoto,
                              icon: const Icon(
                                Icons.add_photo_alternate_outlined,
                              ),
                              label: Text(
                                _photoBusy
                                    ? 'Attaching photo…'
                                    : _editPhoto.isEmpty
                                    ? 'Attach photo'
                                    : 'Replace photo',
                              ),
                            ),
                            if (_editPhoto.isNotEmpty) ...[
                              TextButton(
                                onPressed: _photoBusy
                                    ? null
                                    : () => _viewPhoto(_editPhoto, _editingId!),
                                child: const Text('View photo'),
                              ),
                            ],
                          ],
                        ),
                        if (_photoError != null)
                          Text(
                            _photoError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                      ],
                    ),
                  ),
                )
              : InkWell(
                  onDoubleTap: busy ? null : () => _startEditing(item),
                  onTap: busy
                      ? null
                      : () {
                          if (_heldItemId == item['id']) return;
                          _save([
                            for (final i in _items)
                              i['id'] == item['id']
                                  ? {...i, 'checked': !checked}
                                  : i,
                          ]);
                        },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item['name'] as String,
                            style: TextStyle(
                              decoration: checked
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                              color: checked
                                  ? colors.onSurfaceVariant
                                  : colors.onSurface,
                            ),
                          ),
                          if ((item['note'] as String? ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Text(
                                item['note'] as String,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ),
                          if ((item['photo'] as String? ?? '').isNotEmpty)
                            TextButton(
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                minimumSize: const Size(48, 48),
                                textStyle: Theme.of(context)
                                    .textTheme
                                    .bodySmall,
                                alignment: Alignment.centerLeft,
                              ),
                              onPressed: () => _viewPhoto(
                                item['photo'] as String,
                                item['id'] as String,
                              ),
                              child: const Text('View photo'),
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

  Widget _shoppingList(bool busy) {
    final colors = Theme.of(context).colorScheme;
    final rows = _rows;
    final rowIndices = <Key, int>{
      for (var i = 0; i < rows.length; i++)
        ValueKey<String>(
          rows[i].containsKey('heading')
              ? 'department-${rows[i]['heading']}'
              : rows[i]['completed'] == true
              ? 'completed-section'
              : rows[i]['id'] as String,
        ): i,
    };
    return Listener(
      onPointerUp: _endPress,
      onPointerCancel: _endPress,
      onPointerMove: (event) {
        if (_dragging && event.pointer == _holdPointer) {
          _updateDragPosition(event.position);
        }
      },
      child: ListView.builder(
        key: _listKey,
        controller: _listController,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        itemCount: rows.length,
        // Preserve the drag recognizer when an item changes its sliver index.
        findChildIndexCallback: (key) => rowIndices[key],
        itemBuilder: (context, index) {
          final item = rows[index];
          if (item['completed'] == true) {
            return const Divider(
              key: ValueKey('completed-section'),
              height: 24,
            );
          }
          if (item.containsKey('heading')) {
            final department = item['heading'] as String;
            return DragTarget<String>(
              key: ValueKey('department-$department'),
              hitTestBehavior: HitTestBehavior.opaque,
              onWillAcceptWithDetails: (details) =>
                  _displayPause == null &&
                  !_loading &&
                  (!_disconnected || widget.localFirst) &&
                  !_accessDenied &&
                  _items.any(
                    (i) => i['id'] == details.data && i['checked'] != true,
                  ),
              onAcceptWithDetails: (details) {
                _dragFinished();
                _dropItem(details.data, department);
              },
              builder: (context, candidates, rejected) => Container(
                height: department.isEmpty
                    ? 16
                    : (MediaQuery.textScalerOf(context).scale(22) * 1.15 + 4)
                          .clamp(30, double.infinity),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: candidates.isEmpty ? null : colors.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Semantics(
                  header: department.isNotEmpty,
                  label: department.isEmpty ? 'No department' : null,
                  child: Text(
                    department,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: colors.primary,
                      fontSize: 22,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            );
          }
          return LayoutBuilder(
            key: ValueKey(item['id'] as String),
            builder: (rowContext, constraints) => DragTarget<String>(
              hitTestBehavior: HitTestBehavior.opaque,
              onWillAcceptWithDetails: (details) =>
                  _displayPause == null &&
                  !_loading &&
                  (!_disconnected || widget.localFirst) &&
                  !_accessDenied &&
                  details.data != item['id'] &&
                  _items.any(
                    (i) =>
                        i['id'] == details.data &&
                        i['checked'] == item['checked'],
                  ),
              onAcceptWithDetails: (details) {
                final box = rowContext.findRenderObject() as RenderBox;
                final after =
                    box.globalToLocal(_dragPosition ?? details.offset).dy >
                    box.size.height / 2;
                _dragFinished();
                _dropItem(
                  details.data,
                  item['department'] as String,
                  target: item['id'] as String,
                  after: after,
                );
              },
              builder: (context, candidates, rejected) {
                final feedback = Material(
                  color: Colors.transparent,
                  child: SizedBox(
                    width: constraints.maxWidth,
                    child: IgnorePointer(child: _itemCard(item, true)),
                  ),
                );
                final placeholder = Opacity(
                  opacity: .3,
                  child: _itemCard(item, true),
                );
                Widget source(bool touch, Widget child) => _ShoppingDragSource(
                  touch: touch,
                  data: item['id'] as String,
                  maxSimultaneousDrags:
                      _displayPause != null ||
                          childMode.value ||
                          _editingId == item['id'] ||
                          _loading ||
                          (_disconnected && !widget.localFirst) ||
                          _accessDenied
                      ? 0
                      : 1,
                  dragAnchorStrategy: (_, _, _) => _pressAnchor,
                  onDragStarted: _dragStarted,
                  onDragUpdate: _dragUpdated,
                  onDragCompleted: _dragFinished,
                  onDraggableCanceled: (_, _) => _dragFinished(),
                  feedback: feedback,
                  childWhenDragging: placeholder,
                  child: child,
                );
                return Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (event) =>
                      _pressItem(event, item['id'] as String, rowContext),
                  onPointerMove: _movePress,
                  onPointerUp: _endPress,
                  onPointerCancel: _endPress,
                  child: source(
                    false,
                    source(
                      true,
                      _itemCard(item, busy, highlighted: candidates.isNotEmpty),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    childModeOf(context);
    final colors = Theme.of(context).colorScheme;
    final busy =
        _displayPause != null ||
        childMode.value ||
        _loading ||
        _saving ||
        (_disconnected && !widget.localFirst) ||
        _accessDenied;
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: const Text('Shopping list'),
              actions: [
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: _loading || _saving ? null : () => _load(),
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_disconnected)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Tooltip(
                        message: 'No server connection',
                        child: Semantics(
                          liveRegion: true,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.cloud_off_outlined,
                                size: 16,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _rateLimited ? 'Updates paused' : 'Offline',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                const SizedBox(height: 8),
              if (!childMode.value)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _name,
                              focusNode: _focus,
                              enabled:
                                  !_loading &&
                                  !_saving &&
                                  _displayPause == null,
                              maxLength: 200,
                              textInputAction: TextInputAction.done,
                              decoration: const InputDecoration(
                                hintText: 'Add an item',
                                counterText: '',
                              ),
                              onSubmitted: (_) => _add(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filled(
                            tooltip: 'Add item',
                            onPressed: busy || _items.length >= 500
                                ? null
                                : _add,
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_saving) const LinearProgressIndicator(minHeight: 2),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: _saveNotice
                                ? colors.onSurfaceVariant
                                : colors.error,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: _loading || _saving
                            ? null
                            : _saveNotice
                            ? () => setState(() {
                                _error = null;
                                _saveNotice = false;
                              })
                            : () => _load(),
                        child: Text(_saveNotice ? 'Dismiss' : 'Retry'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _shoppingList(busy),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed:
                            busy || !_items.any((i) => i['checked'] == true)
                            ? null
                            : _removeChecked,
                        icon: const Icon(Icons.delete_sweep_outlined),
                        label: const Text('Remove checked off'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Mouse gestures should use normal click-and-drag; touch retains a long press
// so a normal swipe can still scroll. Each recognizer filters its own devices.
class _ShoppingDragSource extends Draggable<String> {
  const _ShoppingDragSource({
    required this.touch,
    required super.data,
    required super.child,
    required super.feedback,
    required super.childWhenDragging,
    super.dragAnchorStrategy,
    super.maxSimultaneousDrags,
    super.onDragStarted,
    super.onDragUpdate,
    super.onDragCompleted,
    super.onDraggableCanceled,
  }) : super(hitTestBehavior: HitTestBehavior.opaque);

  final bool touch;

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) {
    final MultiDragGestureRecognizer recognizer = touch
        ? DelayedMultiDragGestureRecognizer(
            supportedDevices: const {
              PointerDeviceKind.touch,
              PointerDeviceKind.stylus,
              PointerDeviceKind.invertedStylus,
            },
          )
        : ImmediateMultiDragGestureRecognizer(
            supportedDevices: const {PointerDeviceKind.mouse},
          );
    return recognizer..onStart = onStart;
  }
}
