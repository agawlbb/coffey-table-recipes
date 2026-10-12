import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api.dart';
import 'offline_recipes.dart';
import 'recipe_editor.dart';
import 'recipe_image_editor.dart';
import 'shared_recipe_import.dart';

class RecipeImport extends StatefulWidget {
  const RecipeImport({
    super.key,
    required this.householdId,
    required this.request,
    this.pickFile,
    this.takePhoto,
    this.sharedInput,
  });
  final String householdId;
  final SharedRecipeInput? sharedInput;
  final RecipeSave request;
  final Future<XFile?> Function()? pickFile;
  final Future<XFile?> Function()? takePhoto;
  @override
  State<RecipeImport> createState() => _RecipeImportState();
}

class _RecipeImportState extends State<RecipeImport> {
  final _text = TextEditingController(), _url = TextEditingController();
  final _answerFields = <TextEditingController>[];
  String _kind = 'text';
  XFile? _file;
  bool _busy = false;
  bool _leaving = false;
  String? _error;
  Map<String, dynamic>? _draft;
  List<String> _questions = [];
  String? _identity;
  List<Map<String, dynamic>> _photoSuggestions = [];
  List<Map<String, dynamic>> _importPhotos = [];
  @override
  void initState() {
    super.initState();
    offlineStatus.addListener(_connectionChanged);
    final shared = widget.sharedInput;
    if (shared != null) {
      _file = shared.file;
      _text.text = shared.text ?? '';
      _url.text = shared.url ?? '';
      _kind = shared.file != null
          ? 'file'
          : shared.url != null
          ? 'website'
          : 'text';
      _error = shared.error;
      if (shared.error == null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _analyze();
        });
      }
    } else {
      _recoverCamera();
    }
  }

  void _connectionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _recoverCamera() async {
    if (kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android ||
        widget.takePhoto != null) {
      return;
    }
    try {
      final result = await ImagePicker().retrieveLostData();
      if (mounted && result.files?.isNotEmpty == true) {
        setState(() {
          _kind = 'camera';
          _file = result.files!.first;
        });
      }
    } catch (_) {
      /* The user can take the picture again. */
    }
  }

  @override
  void dispose() {
    offlineStatus.removeListener(_connectionChanged);
    _text.dispose();
    _url.dispose();
    for (final c in _answerFields) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(bool camera) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = camera
          ? await (widget.takePhoto?.call() ??
                ImagePicker().pickImage(
                  source: ImageSource.camera,
                  maxWidth: 2400,
                  maxHeight: 2400,
                  imageQuality: 85,
                ))
          : await (widget.pickFile?.call() ??
                openFile(
                  acceptedTypeGroups: const [
                    XTypeGroup(
                      label: 'Recipe document',
                      extensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp', 'txt'],
                      mimeTypes: [
                        'application/pdf',
                        'image/jpeg',
                        'image/png',
                        'image/webp',
                        'text/plain',
                      ],
                      uniformTypeIdentifiers: [
                        'com.adobe.pdf',
                        'public.jpeg',
                        'public.png',
                        'org.webmproject.webp',
                        'public.plain-text',
                      ],
                    ),
                  ],
                ));
      if (file != null) {
        if (await file.length() > 5 * 1024 * 1024) {
          throw const FormatException('Choose a file up to 5 MB.');
        }
        if (mounted) setState(() => _file = file);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is FormatException ? error.message : 'Could not open the file or camera. Check device permissions and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _editInputPicture() async {
    final file = _file;
    if (file == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final edited = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(builder: (_) => RecipeImageEditor(bytes: bytes)),
      );
      if (edited != null && mounted) {
        final name =
            '${file.name.replaceFirst(RegExp(r'\.[^.]+$'), '')}-edited.png';
        setState(
          () => _file = XFile.fromData(
            edited,
            name: name,
            path: name,
            mimeType: 'image/png',
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not open this picture for editing.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _analyze() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = <String, dynamic>{
        'kind': _draft == null
            ? (_kind == 'description' ? 'text' : _kind)
            : 'answers',
      };
      if (_draft != null) {
        if (_answerFields.any((c) => c.text.trim().isEmpty)) {
          throw const FormatException(
            'Answer each question, or enter “unknown”.',
          );
        }
        body.addAll({
          'recipe': Map<String, dynamic>.from(_draft!)
            ..remove('photo_suggestions')
            ..remove('photos'),
          'text': _draft!['source_text'] ?? '',
          'url': _draft!['source_url'],
          'import_identity': _identity,
          'answers': [
            for (var i = 0; i < _questions.length; i++)
              {
                'question': _questions[i],
                'answer': _answerFields[i].text.trim(),
              },
          ],
        });
      } else if (_kind == 'text' || _kind == 'description') {
        body['input_source'] = _kind == 'description'
            ? 'written_description'
            : 'pasted_text';
        if (_text.text.trim().isEmpty) {
          throw const FormatException(
            'Paste a recipe or describe how you make your dish.',
          );
        }
        body['text'] = _text.text.trim();
      } else if (_kind == 'website') {
        final uri = Uri.tryParse(_url.text.trim());
        if (uri == null ||
            !['http', 'https'].contains(uri.scheme) ||
            uri.host.isEmpty) {
          throw const FormatException(
            'Enter a full http:// or https:// website link.',
          );
        }
        body['url'] = uri.toString();
      } else {
        if (_file == null) {
          throw const FormatException('Choose a file or take a picture first.');
        }
        if (await _file!.length() > 5 * 1024 * 1024) {
          throw const FormatException('Choose a file up to 5 MB.');
        }
        final bytes = await _file!.readAsBytes();
        if (_file!.name.toLowerCase().endsWith('.txt')) {
          body['kind'] = 'text';
          body['input_source'] = 'uploaded_text';
          body['text'] = utf8.decode(bytes);
        } else {
          body['file_base64'] = base64Encode(bytes);
        }
      }
      final data = await widget.request(
        '/households/${widget.householdId}/recipe-import',
        body,
      );
      if (!mounted) return;
      final questions = (data['questions'] as List).cast<String>();
      final draft = data['recipe'] as Map<String, dynamic>;
      if (draft['photos'] is List && (draft['photos'] as List).isNotEmpty) {
        _importPhotos = List<Map<String, dynamic>>.from(
          draft['photos'] as List,
        );
      }
      if (_importPhotos.isNotEmpty) draft['photos'] = _importPhotos;
      if (draft['photo_suggestions'] is List &&
          (draft['photo_suggestions'] as List).isNotEmpty) {
        _photoSuggestions = List<Map<String, dynamic>>.from(
          draft['photo_suggestions'] as List,
        );
      }
      draft['photo_suggestions'] = _photoSuggestions;
      for (final c in _answerFields) {
        c.dispose();
      }
      _answerFields.clear();
      setState(() {
        _draft = draft;
        _questions = questions;
        _identity ??= draft['import_key'] as String?;
        _answerFields.addAll(questions.map((_) => TextEditingController()));
      });
      if (questions.isEmpty) await _review();
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ApiException
              ? error.message
              : error is FormatException
              ? error.message
              : 'Could not prepare your recipe. Your input is still here; try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review() async {
    final saved = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => RecipeEditor(
          recipe: _draft!,
          householdId: widget.householdId,
          save: widget.request,
        ),
      ),
    );
    if (mounted) {
      setState(() => _leaving = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context, saved);
    }
  }

  Future<void> _close() async {
    if (_busy) return;
    if (_file != null ||
        _text.text.isNotEmpty ||
        _url.text.isNotEmpty ||
        _draft != null) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Discard recipe import?'),
          content: const Text('Your recipe has not been saved.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep working'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Discard'),
            ),
          ],
        ),
      );
      if (discard != true) return;
    }
    if (mounted) {
      setState(() => _leaving = true);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _leaving,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _close();
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Add recipe'),
        leading: BackButton(onPressed: _busy ? null : _close),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Import a recipe, or tell us how you make a dish. AI will organize it and may ask about missing details. Review and edit before saving.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Your input is sent to the recipe AI service when you continue.',
              ),
              if (offlineStatus.value)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'An internet connection is required to import a recipe.',
                  ),
                ),
              if (_draft == null) ...[
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: _kind,
                  decoration: const InputDecoration(labelText: 'Import from'),
                  items: const [
                    DropdownMenuItem(
                      value: 'text',
                      child: Text('Pasted recipe text'),
                    ),
                    DropdownMenuItem(
                      value: 'description',
                      child: Text('Describe how I make a dish'),
                    ),
                    DropdownMenuItem(
                      value: 'file',
                      child: Text('Upload a file'),
                    ),
                    DropdownMenuItem(
                      value: 'camera',
                      child: Text('Device camera'),
                    ),
                    DropdownMenuItem(
                      value: 'website',
                      child: Text('Website link'),
                    ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                          _kind = v!;
                          _file = null;
                          _error = null;
                        }),
                ),
                const SizedBox(height: 16),
                if (_kind == 'text' || _kind == 'description')
                  TextField(
                    controller: _text,
                    enabled: !_busy,
                    minLines: 6,
                    maxLines: 14,
                    maxLength: 60000,
                    decoration: const InputDecoration(
                      labelText: 'Recipe or description',
                      hintText: 'For example: I sauté onions in butter, add rice and broth, then simmer…',
                      border: OutlineInputBorder(),
                    ),
                  ),
                if (_kind == 'website')
                  TextField(
                    controller: _url,
                    enabled: !_busy,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(
                      labelText: 'Recipe website link',
                      hintText: 'https://…',
                    ),
                  ),
                if (_kind == 'file' || _kind == 'camera') ...[
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _pick(_kind == 'camera'),
                    icon: Icon(
                      _kind == 'camera'
                          ? Icons.camera_alt_outlined
                          : Icons.upload_file,
                    ),
                    label: Text(
                      _kind == 'camera'
                          ? 'Take a picture'
                          : 'Choose PDF, image, or text file',
                    ),
                  ),
                  Text(_file?.name ?? 'No file selected (maximum 5 MB).'),
                  if (_file != null &&
                      (_kind == 'camera' ||
                          _file!.mimeType?.startsWith('image/') == true ||
                          RegExp(
                            r'\.(png|jpe?g|webp|heic|heif)$',
                            caseSensitive: false,
                          ).hasMatch(_file!.name)))
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _editInputPicture,
                      icon: const Icon(Icons.crop_rotate),
                      label: const Text('Edit picture'),
                    ),
                ],
              ] else ...[
                const SizedBox(height: 20),
                Text(
                  _questions.isEmpty
                      ? 'Draft ready to review'
                      : 'A few details about your recipe',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (var i = 0; i < _questions.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: TextField(
                      controller: _answerFields[i],
                      enabled: !_busy,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 4000,
                      decoration: InputDecoration(
                        labelText: _questions[i],
                        helperText: 'Enter “unknown” if you are unsure.',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                if (_questions.isNotEmpty)
                  TextButton(
                    onPressed: _busy ? null : _review,
                    child: const Text('Review with missing details'),
                  ),
              ],
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _busy || offlineStatus.value
                    ? null
                    : _draft != null && _questions.isEmpty
                    ? _review
                    : _analyze,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(
                  _busy
                      ? 'Preparing recipe…'
                      : _draft != null && _questions.isEmpty
                      ? 'Review recipe'
                      : 'Continue',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
