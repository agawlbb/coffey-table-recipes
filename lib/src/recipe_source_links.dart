import 'package:flutter/material.dart';
import 'package:url_launcher/link.dart';

/// Recognizes website addresses only; never launches arbitrary URI schemes.
Uri? recipeSourceWebsite(String value, {bool allowBareDomain = true}) {
  final text = value.trim();
  if (text.isEmpty ||
      text.length > 4000 ||
      RegExp(r'''[\x00-\x20\x7f<>"\\]''').hasMatch(text) ||
      RegExp(
        r'%(?![0-9a-f]{2})|%(?:0[0-9a-f]|1[0-9a-f]|7f)',
        caseSensitive: false,
      ).hasMatch(text)) {
    return null;
  }
  final explicit = RegExp(r'^https?://', caseSensitive: false).hasMatch(text);
  if (!explicit) {
    if (text.startsWith('/') ||
        (RegExp(r'^[a-z][a-z0-9+.-]*:', caseSensitive: false).hasMatch(text) &&
            !RegExp(r'^[^/:]+:\d+(?:[/?#]|$)').hasMatch(text)) ||
        (!allowBareDomain && !text.toLowerCase().startsWith('www.'))) {
      return null;
    }
  }
  try {
    final uri = Uri.parse(explicit ? text : 'https://$text');
    if (!['http', 'https'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        uri.host.length > 253 ||
        (uri.hasPort && (uri.port < 1 || uri.port > 65535))) {
      return null;
    }
    final labels = uri.host.split('.');
    if (labels.length < 2 ||
        labels.any(
          (label) => !RegExp(
            r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
            caseSensitive: false,
          ).hasMatch(label),
        )) {
      return null;
    }
    final ipv4 =
        labels.length == 4 &&
        labels.every(
          (label) =>
              RegExp(r'^\d{1,3}$').hasMatch(label) && int.parse(label) <= 255,
        );
    if (!(explicit && ipv4) &&
        !RegExp(
          r'^(?:[a-z]{2,63}|xn--[a-z0-9-]+)$',
          caseSensitive: false,
        ).hasMatch(labels.last)) {
      return null;
    }
    // A filename in a citation is not an unqualified website address.
    if (!explicit &&
        !text.toLowerCase().startsWith('www.') &&
        {
          'pdf',
          'doc',
          'docx',
          'txt',
          'jpg',
          'jpeg',
          'png',
          'gif',
          'xlsx',
          'zip',
        }.contains(labels.last.toLowerCase())) {
      return null;
    }
    return uri;
  } on FormatException {
    return null;
  }
}

typedef RecipeSourcePart = ({String text, Uri? uri});

/// Preserves every character, linking whole URLs and clear website tokens.
List<RecipeSourcePart> recipeSourceParts(String text) {
  final whole = recipeSourceWebsite(text);
  if (whole != null) {
    final start = text.indexOf(text.trim());
    final end = start + text.trim().length;
    return [
      if (start > 0) (text: text.substring(0, start), uri: null),
      (text: text.substring(start, end), uri: whole),
      if (end < text.length) (text: text.substring(end), uri: null),
    ];
  }
  final tokens = RegExp(r'\S+').allMatches(text).toList();
  final result = <RecipeSourcePart>[];
  var cursor = 0;
  for (final token in tokens) {
    var start = token.start;
    var end = token.end;
    while (start < end && '([{"\''.contains(text[start])) {
      start++;
    }
    while (end > start) {
      final last = text[end - 1];
      final candidate = text.substring(start, end);
      final opening = {')': '(', ']': '[', '}': '{'}[last];
      if ('.;,!?"\''.contains(last) ||
          (opening != null &&
              opening.allMatches(candidate).length <
                  last.allMatches(candidate).length)) {
        end--;
      } else {
        break;
      }
    }
    final candidate = text.substring(start, end);
    final uri = recipeSourceWebsite(
      candidate,
      allowBareDomain: tokens.length == 1 || candidate.contains('/'),
    );
    if (uri == null) continue;
    if (start > cursor) {
      result.add((text: text.substring(cursor, start), uri: null));
    }
    result.add((text: candidate, uri: uri));
    cursor = end;
  }
  if (cursor < text.length || result.isEmpty) {
    result.add((text: text.substring(cursor), uri: null));
  }
  return result;
}

class RecipeSourceText extends StatelessWidget {
  const RecipeSourceText(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final parts = recipeSourceParts(text);
    if (parts.every((part) => part.uri == null)) return SelectableText(text);
    final style = DefaultTextStyle.of(context).style;
    return SelectionArea(
      child: Text.rich(
        TextSpan(
          children: [
            for (final part in parts)
              if (part.uri == null)
                TextSpan(text: part.text)
              else
                WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: Link(
                    uri: part.uri,
                    target: LinkTarget.blank,
                    builder: (context, followLink) => Semantics(
                      link: true,
                      child: InkWell(
                        onTap: followLink,
                        child: Text(
                          part.text,
                          style: style.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
          ],
        ),
        style: style,
      ),
    );
  }
}
