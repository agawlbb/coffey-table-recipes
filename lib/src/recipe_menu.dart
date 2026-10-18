import 'package:flutter/material.dart';

/// Preserve Back while keeping household navigation available on deeper pages.
class RecipeMenuLeading extends StatelessWidget {
  const RecipeMenuLeading({super.key});

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconButton(
        tooltip: 'Open navigation menu',
        icon: const Icon(Icons.menu),
        onPressed: () => Scaffold.of(context).openDrawer(),
      ),
      const BackButton(),
    ],
  );
}
