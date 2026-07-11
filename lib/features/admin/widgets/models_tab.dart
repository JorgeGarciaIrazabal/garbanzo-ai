import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/admin/providers/admin_provider.dart';

/// Tab rendering the list of LLM models with enable/disable toggles.
class ModelsTab extends StatefulWidget {
  const ModelsTab({super.key});

  @override
  State<ModelsTab> createState() => _ModelsTabState();
}

class _ModelsTabState extends State<ModelsTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminProvider>().loadModels();
    });
  }

  Future<void> _handleSync() async {
    final provider = context.read<AdminProvider>();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Syncing models from provider…')),
    );
    await provider.syncModels();
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    if (provider.modelsError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(provider.modelsError!)));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${provider.models.length} models synced')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AdminProvider>();
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Widget body;
    if (provider.isLoadingModels && provider.models.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (provider.modelsError != null && provider.models.isEmpty) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colorScheme.error, size: 32),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(provider.modelsError!, textAlign: TextAlign.center),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: provider.loadModels,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    } else if (provider.models.isEmpty) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.memory, color: colorScheme.outline, size: 48),
            const SizedBox(height: 8),
            Text('No models synced yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Tap the sync button to discover models from the provider.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      );
    } else {
      body = RefreshIndicator(
        onRefresh: provider.loadModels,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: provider.models.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final model = provider.models[i];
            final displayName = model.name ?? model.modelId;
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: model.isEnabled
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.memory,
                  color: model.isEnabled
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSurfaceVariant,
                ),
              ),
              title: Row(
                children: [
                  Expanded(child: Text(displayName)),
                  if (model.isNew)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.tertiaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'NEW',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (model.description != null &&
                      model.description!.isNotEmpty)
                    Text(model.description!),
                  Text(
                    model.modelId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              trailing: Switch(
                value: model.isEnabled,
                onChanged: (v) {
                  provider.updateModel(model.modelId, enabled: v);
                },
              ),
            );
          },
        ),
      );
    }

    return Scaffold(
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _handleSync,
        icon: const Icon(Icons.sync),
        label: const Text('Sync'),
      ),
    );
  }
}
