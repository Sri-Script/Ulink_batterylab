import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/app_tokens.dart';

class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.accent = false, this.padding});

  final Widget child;
  final bool accent;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.extension<UlinkThemeTokens>()!;
    return Container(
    padding: padding,
    decoration: BoxDecoration(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(AppTokens.r16),
      border: Border.all(
        color: accent ? theme.colorScheme.primary.withValues(alpha: .55) : theme.colorScheme.outlineVariant,
      ),
      boxShadow: accent && tokens.glow.alpha > 0
          ? [BoxShadow(color: tokens.glow, blurRadius: 18)]
          : tokens.cardShadow.alpha > 0
          ? [BoxShadow(color: tokens.cardShadow, blurRadius: 16, offset: const Offset(0, 6))]
          : null,
    ),
    child: child,
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.label,
    required this.icon,
    this.color,
  });

  final String label;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? Theme.of(context).extension<UlinkThemeTokens>()!.textMuted;
    return Semantics(
    label: label,
    child: Container(
      constraints: const BoxConstraints(minHeight: 28),
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.s8, vertical: AppTokens.s4),
      decoration: BoxDecoration(
        color: resolvedColor.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: resolvedColor.withValues(alpha: .42)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: resolvedColor),
          const SizedBox(width: AppTokens.s4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: AppTokens.labelStyle.copyWith(color: resolvedColor),
            ),
          ),
        ],
      ),
    ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            if (subtitle != null) ...[
              const SizedBox(height: AppTokens.s4),
              Text(subtitle!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).extension<UlinkThemeTokens>()!.textMuted)),
            ],
          ],
        ),
      ),
      if (trailing != null) trailing!,
    ],
  );
}

class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => AppCard(
    padding: const EdgeInsets.all(AppTokens.s12),
    child: SizedBox(
      height: 118,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary.withValues(alpha: .12), shape: BoxShape.circle),
            child: Icon(icon, color: Theme.of(context).colorScheme.primary, size: 18),
          ),
          const Spacer(),
          Text(value, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 2),
          Text(label, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTokens.labelStyle.copyWith(color: Theme.of(context).extension<UlinkThemeTokens>()!.textMuted)),
        ],
      ),
    ),
  );
}

class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    this.value,
    required this.onTap,
    required this.enabled,
  });

  final String label;
  final String? value;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    enabled: enabled,
    child: Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0),
      child: InkWell(
        key: key,
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(AppTokens.r12),
        child: Container(
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: AppTokens.s12, vertical: AppTokens.s8),
          decoration: BoxDecoration(
            color: enabled ? Theme.of(context).extension<UlinkThemeTokens>()!.surfaceElevated : Theme.of(context).colorScheme.surface.withValues(alpha: .6),
            borderRadius: BorderRadius.circular(AppTokens.r12),
            border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: enabled ? 1 : .45)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value ?? label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: value == null ? TextStyle(color: Theme.of(context).extension<UlinkThemeTokens>()!.textMuted.withValues(alpha: enabled ? 1 : .55)) : null,
                ),
              ),
              Icon(Icons.expand_more, color: enabled ? Theme.of(context).colorScheme.primary : Theme.of(context).extension<UlinkThemeTokens>()!.textMuted),
            ],
          ),
        ),
      ),
    ),
  );
}

class SearchablePickerBottomSheet<T> extends StatefulWidget {
  const SearchablePickerBottomSheet({
    super.key,
    required this.title,
    required this.items,
    required this.labelFor,
    required this.onSelected,
  });

  final String title;
  final List<T> items;
  final String Function(T item) labelFor;
  final ValueChanged<T> onSelected;

  @override
  State<SearchablePickerBottomSheet<T>> createState() => _SearchablePickerBottomSheetState<T>();
}

class _SearchablePickerBottomSheetState<T> extends State<SearchablePickerBottomSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final normalized = _query.trim().toLowerCase();
    final items = widget.items.where((item) => widget.labelFor(item).toLowerCase().contains(normalized)).toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppTokens.s16, AppTokens.s16, AppTokens.s16, AppTokens.s24),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .68,
          child: Column(
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: AppTokens.s12),
              TextField(
                autofocus: true,
                onChanged: (value) => setState(() => _query = value),
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search'),
              ),
              const SizedBox(height: AppTokens.s12),
              Expanded(
                child: items.isEmpty
                    ? const EmptyState(icon: Icons.search_off_outlined, message: 'No matching items found.')
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (_, index) => ListTile(
                          title: Text(widget.labelFor(items[index])),
                          onTap: () => widget.onSelected(items[index]),
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

class StepCard extends StatelessWidget {
  const StepCard({
    super.key,
    required this.number,
    required this.title,
    required this.child,
    required this.unlocked,
    this.completed = false,
    this.summary,
  });

  final int number;
  final String title;
  final Widget child;
  final bool unlocked;
  final bool completed;
  final String? summary;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: unlocked ? 1 : .5,
    child: AppCard(
      accent: completed,
      padding: const EdgeInsets.all(AppTokens.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: completed ? Theme.of(context).colorScheme.primary : Theme.of(context).extension<UlinkThemeTokens>()!.surfaceElevated,
                child: Icon(completed ? Icons.check : Icons.lock_outline, size: 16, color: completed ? Theme.of(context).colorScheme.onPrimary : Theme.of(context).extension<UlinkThemeTokens>()!.textMuted),
              ),
              const SizedBox(width: AppTokens.s8),
              Expanded(child: Text('$number. $title', style: Theme.of(context).textTheme.titleMedium)),
            ],
          ),
          if (summary != null) ...[
            const SizedBox(height: AppTokens.s4),
            Text(summary!, style: AppTokens.labelStyle.copyWith(color: Theme.of(context).colorScheme.primary)),
          ],
          const SizedBox(height: AppTokens.s12),
          IgnorePointer(ignoring: !unlocked, child: child),
        ],
      ),
    ),
  );
}

class SelectableOptionCard extends StatelessWidget {
  const SelectableOptionCard({
    super.key,
    required this.title,
    required this.selected,
    required this.onTap,
    required this.icon,
  });

  final String title;
  final bool selected;
  final VoidCallback? onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Semantics(
      label: '$title deployment type',
      button: true,
      selected: selected,
      child: Material(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTokens.r12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
            constraints: const BoxConstraints(minHeight: 88),
            padding: const EdgeInsets.all(AppTokens.s12),
            decoration: BoxDecoration(
              color: selected ? Theme.of(context).colorScheme.primary.withValues(alpha: .13) : Theme.of(context).extension<UlinkThemeTokens>()!.surfaceElevated,
              borderRadius: BorderRadius.circular(AppTokens.r12),
              border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.outlineVariant),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [Icon(icon, color: selected ? Theme.of(context).colorScheme.primary : Theme.of(context).extension<UlinkThemeTokens>()!.textMuted), const SizedBox(height: AppTokens.s8), Text(title)],
            ),
          ),
        ),
      ),
    ),
  );
}

class PrimaryActionButton extends StatelessWidget {
  const PrimaryActionButton({super.key, required this.label, required this.onPressed, this.loading = false, this.icon = Icons.flash_on_outlined});

  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<UlinkThemeTokens>()!;
    return SizedBox(
    width: double.infinity,
    height: 52,
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: onPressed == null ? null : LinearGradient(colors: [tokens.primaryGradientStart, tokens.primaryGradientEnd]),
        borderRadius: BorderRadius.circular(AppTokens.r12),
      ),
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: onPressed == null ? null : Theme.of(context).colorScheme.surface.withValues(alpha: 0),
          foregroundColor: tokens.onPrimaryAction,
        ),
        onPressed: loading ? null : onPressed,
        icon: loading ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: tokens.onPrimaryAction)) : Icon(icon),
        label: Text(label),
      ),
    ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppTokens.s24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 36, color: Theme.of(context).extension<UlinkThemeTokens>()!.textMuted), const SizedBox(height: AppTokens.s12), Text(message, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).extension<UlinkThemeTokens>()!.textMuted))],
      ),
    ),
  );
}

class ErrorState extends StatelessWidget {
  const ErrorState({super.key, required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(AppTokens.s24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off_outlined, size: 36, color: Theme.of(context).extension<UlinkThemeTokens>()!.warning),
          const SizedBox(height: AppTokens.s12),
          const Text('Unable to load this information. Please try again.', textAlign: TextAlign.center),
          const SizedBox(height: AppTokens.s12),
          OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Retry')),
        ],
      ),
    ),
  );
}

class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.height = 72});

  final double height;

  @override
  Widget build(BuildContext context) => Container(
    height: height,
    decoration: BoxDecoration(color: Theme.of(context).extension<UlinkThemeTokens>()!.surfaceElevated, borderRadius: BorderRadius.circular(AppTokens.r12)),
  );
}
