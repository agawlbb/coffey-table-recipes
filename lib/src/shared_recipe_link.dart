import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'recipe_browser.dart';

String? recipeIdFromLink(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.hasAuthority &&
          (uri.scheme != 'https' || uri.host != 'coffeybean.com')) ||
      uri.path != '/CoffeyTableRecipes/share.php') {
    return null;
  }
  final id = uri.queryParameters['id'];
  return id != null && RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(id) ? id : null;
}

/// Public display never waits for Firebase or an identity-token refresh.
class SharedRecipeLink extends StatefulWidget {
  const SharedRecipeLink({super.key, required this.recipeId});
  final String recipeId;
  @override
  State<SharedRecipeLink> createState() => _SharedRecipeLinkState();
}

class _SharedRecipeLinkState extends State<SharedRecipeLink> {
  final _api = RecipeApi(baseUrl: apiBaseUrl);
  bool _adding = false;
  String? _message;
  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _add() async {
    if (_adding) return;
    final user = Firebase.apps.isEmpty
        ? null
        : FirebaseAuth.instance.currentUser;
    if (user == null) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sign in to add this recipe'),
          content: const Text(
            'Sign in from the account menu, then open this link again to add the same recipe to your household.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep reading'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.of(this.context).popUntil((route) => route.isFirst);
              },
              child: const Text('Go to sign in'),
            ),
          ],
        ),
      );
      return;
    }
    setState(() {
      _adding = true;
      _message = null;
    });
    try {
      final token = await user.getIdToken(true);
      if (token == null) {
        throw ApiException(401, 'Please sign in again to add recipes.');
      }
      final me = await _api.request('/me', token);
      final households = recipeRows(me['households']);
      if (!mounted) return;
      if (households.isEmpty) {
        throw ApiException(
          409,
          'Set up a household from the account menu first.',
        );
      }
      final id = households.length == 1
          ? households.first['id'] as String
          : await showDialog<String>(
              context: context,
              builder: (context) => SimpleDialog(
                title: const Text('Add to household'),
                children: [
                  for (final household in households)
                    SimpleDialogOption(
                      onPressed: () =>
                          Navigator.pop(context, household['id'] as String),
                      child: Text(household['name'] as String),
                    ),
                ],
              ),
            );
      if (id == null) return;
      await _api.request(
        '/households/$id/recipes/${widget.recipeId}/attach',
        token,
        body: {},
      );
      if (mounted) {
        setState(
          () => _message =
              'Added to your household. Everyone uses the same recipe.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _message = error is ApiException
              ? error.message
              : 'Could not add the recipe. Sign in again and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Column(
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _adding ? null : _add,
                icon: const Icon(Icons.add),
                label: const Text('Add to my household'),
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_message!),
                ),
            ],
          ),
          Expanded(
            child: RecipeDetail(
              householdId: '0',
              recipeId: widget.recipeId,
              title: 'Shared recipe',
              request: (path) {
                final id = Uri.parse(path).path.split('/').last;
                return _api.request('/recipes/$id', '');
              },
            ),
          ),
        ],
      ),
    ),
  );
}
