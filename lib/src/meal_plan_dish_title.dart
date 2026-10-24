import 'package:flutter/material.dart';

/// Keeps meal names readable without breaking a word between lines.
class MealPlanDishTitle extends StatelessWidget {
  const MealPlanDishTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleSmall!
        .copyWith(fontSize: 13, fontWeight: FontWeight.w500);
    return Tooltip(
      message: title,
      triggerMode: TooltipTriggerMode.manual,
      excludeFromSemantics: true,
      child: Semantics(
        label: title,
        excludeSemantics: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final painter = TextPainter(
              textDirection: Directionality.of(context),
              textScaler: MediaQuery.textScalerOf(context),
            );
            bool fits(String text) {
              painter.text = TextSpan(text: text, style: style);
              painter.layout();
              return painter.width <= constraints.maxWidth;
            }

            final lines = <String>[];
            var line = '';
            for (final word in title.trim().split(RegExp(r'\s+'))) {
              final candidate = line.isEmpty ? word : '$line $word';
              if (line.isNotEmpty && !fits(candidate)) {
                lines.add(line);
                line = word;
              } else {
                line = candidate;
              }
            }
            lines.add(line);
            if (lines.length > 2) {
              final words = lines[1].split(' ');
              while (words.isNotEmpty && !fits('${words.join(' ')}…')) {
                words.removeLast();
              }
              lines[1] = '${words.join(' ')}…';
            }
            painter.dispose();
            return Text(
              lines.take(2).join('\n'),
              style: style,
              textAlign: TextAlign.center,
              softWrap: false,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            );
          },
        ),
      ),
    );
  }
}
