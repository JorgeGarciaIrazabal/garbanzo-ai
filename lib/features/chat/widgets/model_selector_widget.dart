import 'package:flutter/material.dart';

import '../models/model_info.dart';

/// Dropdown for selecting the LLM model.
class ModelSelectorWidget extends StatelessWidget {
  const ModelSelectorWidget({
    super.key,
    required this.models,
    required this.selectedId,
    required this.onSelect,
    this.isEnabled = true,
  });

  final List<ModelInfo> models;
  final String? selectedId;
  final ValueChanged<String> onSelect;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (models.isEmpty) {
      return const SizedBox.shrink();
    }

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: selectedId,
        isDense: true,
        isExpanded: false,
        icon: Icon(
          Icons.arrow_drop_down,
          color: colorScheme.onSurfaceVariant,
        ),
        style: theme.textTheme.labelMedium?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
        onChanged: isEnabled
            ? (value) {
                if (value != null) {
                  onSelect(value);
                }
              }
            : null,
        items: models.map((model) {
          return DropdownMenuItem<String>(
            value: model.id,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    model.name,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (model.description != null)
                    Text(
                      model.description!,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          );
        }).toList(),
        selectedItemBuilder: (context) {
          return models.map((model) {
            final isSelected = model.id == selectedId;
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.memory,
                  size: 16,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  model.name,
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
          }).toList();
        },
      ),
    );
  }
}
