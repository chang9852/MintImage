import 'package:flutter/material.dart';

import '../../core/models/xai_imagine_params.dart';
import '../../shared/theme.dart';
import 'size_picker_modal.dart';

class SizeSelector extends StatelessWidget {
  const SizeSelector({
    super.key,
    required this.currentWidth,
    required this.currentHeight,
    required this.onSizeSelected,
    this.xaiImagine = false,
  });

  final int currentWidth;
  final int currentHeight;
  final void Function(int width, int height) onSizeSelected;

  /// 是否为 Grok Imagine 模式。
  ///
  /// xAI 只接受宽高比加分辨率，不接受任意像素尺寸，
  /// 因此按钮上展示的是换算后的宽高比与分辨率，而不是像素值。
  final bool xaiImagine;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        FocusManager.instance.primaryFocus?.unfocus(
          disposition: UnfocusDisposition.scope,
        );
        final result = await showSizePickerModal(
          context,
          currentWidth: currentWidth,
          currentHeight: currentHeight,
          xaiImagine: xaiImagine,
        );
        if (result != null) {
          onSizeSelected(result.$1, result.$2);
        }
        if (context.mounted) {
          FocusManager.instance.primaryFocus?.unfocus(
            disposition: UnfocusDisposition.scope,
          );
        }
      },
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
              Icons.aspect_ratio_rounded,
              size: 13,
              color: AppThemeTokens.primaryStrong,
            ),
            const SizedBox(width: 4),
            Text(
              _label,
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

  String get _label {
    if (xaiImagine) {
      return xaiImagineSizeLabel(currentWidth, currentHeight);
    }
    return currentWidth == 0 ? '自动' : '$currentWidth×$currentHeight';
  }
}
