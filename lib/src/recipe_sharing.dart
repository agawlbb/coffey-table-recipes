import 'api.dart';

String recipeShareLink(String recipeId) => Uri.parse(apiBaseUrl)
    .replace(
      path: Uri.parse(apiBaseUrl).path.replaceFirst(
        RegExp(r'/api/v1/?$'),
        '/share.php',
      ),
      queryParameters: {'id': recipeId},
    )
    .toString();
