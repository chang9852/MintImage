import 'package:flutter/material.dart';

import '../../core/models/generation_request.dart';
import '../../shared/theme.dart';

class QualitySelector extends StatelessWidget {
  const QualitySelector({
    super.key,
    required this.selectedQuality,
    required this.onSelected,
    this.qualities = ImageQuality.values,
  });

  final ImageQuality selectedQuality;
  final ValueChanged<ImageQuality> onSelected;

  /// 可供选择的档位，用于按模型能力收窄选项。
  ///
  /// 例如 Grok Imagine 只有低/中两档，不提供高清。
  final List<ImageQuality> qualities;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showSheet(context),
      child: Container(
        constraints: const BoxConstraints(minHeight: 28),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: AppThemeTokens.surfaceSoft,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppThemeTokens.border.withValues(alpha: 0.7),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_rounded,
              size: 13,
              color: AppThemeTokens.primaryStrong,
            ),
            const SizedBox(width: 4),
            Text(
              selectedQuality.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AppThemeTokens.primaryStrong,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSheet(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus(
      disposition: UnfocusDisposition.scope,
    );
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: qualities.map((q) {
              final active = q == selectedQuality;
              return ListTile(
                leading: Icon(
                  active ? Icons.check_circle_rounded : Icons.circle_outlined,
                  color: active ? AppThemeTokens.primary : Colors.grey,
                ),
                title: Text(q.label),
                onTap: () {
                  Navigator.of(ctx).pop();
                  onSelected(q);
                },
              );
            }).toList(),
          ),
        );
      },
    );
    if (context.mounted) {
      FocusManager.instance.primaryFocus?.unfocus(
        disposition: UnfocusDisposition.scope,
      );
    }
  }
}
