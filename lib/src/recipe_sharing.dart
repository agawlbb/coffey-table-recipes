import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

String recipeShareLink(String recipeId) {
  if (!RegExp(r'^[1-9][0-9]{0,18}$').hasMatch(recipeId)) {
    throw ArgumentError('Invalid recipe ID');
  }
  return 'https://ctr.coffeybean.com/recipes/$recipeId';
}

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
