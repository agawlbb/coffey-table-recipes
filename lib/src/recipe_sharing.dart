import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api.dart';

String recipeShareLink(String recipeId) => Uri.parse(apiBaseUrl)
    .replace(
      path: Uri.parse(apiBaseUrl).path
          .replaceFirst(RegExp(r'/api/v1/?$'), '/share.php'),
      queryParameters: {'id': recipeId},
    )
    .toString();

String recipeShareHtml(String recipeId, String title) {
  const escape = HtmlEscape(HtmlEscapeMode.attribute);
  return '<a href="${escape.convert(recipeShareLink(recipeId))}">${escape.convert(title)}</a>';
}

Future<bool> shareRecipeHtml(
  String recipeId,
  String title, {
  Rect? origin,
}) async {
  if (kIsWeb ||
      ![
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform)) {
    return false;
  }
  try {
    return await const MethodChannel(
          'coffey_table_recipes/share_link',
        ).invokeMethod<bool>('share', {
          'html': recipeShareHtml(recipeId, title),
          'text': '$title\n${recipeShareLink(recipeId)}',
          'title': title,
          if (origin != null)
            'origin': [origin.left, origin.top, origin.width, origin.height],
        }) ??
        false;
  } on MissingPluginException {
    return false;
  } on PlatformException {
    return false;
  }
}
