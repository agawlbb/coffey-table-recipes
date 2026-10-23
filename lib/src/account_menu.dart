import 'child_mode.dart';

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A consistently sized account menu, anchored to the profile badge.
class AccountMenu extends StatelessWidget {
  const AccountMenu({
    super.key,
    required this.name,
    this.email,
    required this.onSelected,
    this.enabled = true,
    this.canEditTableName = false,
    this.showTimers = false,
    this.administrator = false,
  });

  final String name;
  final String? email;
  final ValueChanged<String> onSelected;
  final bool enabled;
  final bool canEditTableName;
  final bool showTimers;
  final bool administrator;

  @override
  Widget build(BuildContext context) {
    childModeOf(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final width = math.min(320.0, MediaQuery.sizeOf(context).width - 24);
    final initial = name.trim().isEmpty
        ? '?'
        : name.trim().characters.first.toUpperCase();
    PopupMenuItem<String> action(
      String value,
      String label,
      IconData icon, {
      bool enabled = true,
    }) => PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Icon(
            icon,
            size: 22,
            color: enabled
                ? colors.onSurfaceVariant
                : colors.onSurface.withValues(alpha: .38),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: enabled
                    ? colors.onSurface
                    : colors.onSurface.withValues(alpha: .38),
              ),
            ),
          ),
        ],
      ),
    );
    return PopupMenuButton<String>(
      tooltip: 'User menu',
      enabled: enabled,
      position: PopupMenuPosition.under,
      offset: const Offset(-8, 8),
      constraints: BoxConstraints(minWidth: width, maxWidth: width),
      color: colors.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      onSelected: onSelected,
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: colors.primaryContainer,
                foregroundColor: colors.onPrimaryContainer,
                child: Text(initial),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: colors.onSurface,
                      ),
                    ),
                    if (email != null)
                      Text(
                        email!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        action(
          'childMode',
          childMode.value ? 'Child mode: On' : 'Child mode: Off',
          Icons.lock_outline,
        ),
        action(
          'name',
          'Account display name',
          Icons.person_outline,
          enabled: !childMode.value,
        ),
        action(
          'tableName',
          'Name at the table',
          Icons.badge_outlined,
          enabled: canEditTableName && !childMode.value,
        ),
        action('household', 'Household & people', Icons.people_outline),
        if (showTimers && !childMode.value)
          action('timers', 'Timer settings', Icons.alarm_outlined),
        if (administrator && !childMode.value)
          action(
            'administration',
            'Administration',
            Icons.admin_panel_settings_outlined,
          ),
        const PopupMenuDivider(),
        action('logout', 'Log out', Icons.logout),
      ],
      icon: CircleAvatar(
        radius: 16,
        backgroundColor: colors.primaryContainer,
        foregroundColor: colors.onPrimaryContainer,
        child: Text(initial),
      ),
    );
  }
}
