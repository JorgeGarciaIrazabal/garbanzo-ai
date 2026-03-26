import 'package:flutter/material.dart';

import '../../models/chat_attachment.dart';

/// Horizontal scrollable row of attachment preview chips shown above the input.
class AttachmentPreviewBar extends StatelessWidget {
  const AttachmentPreviewBar({
    super.key,
    required this.attachments,
    required this.onRemove,
    required this.colorScheme,
    required this.textTheme,
  });

  final List<ChatAttachment> attachments;
  final void Function(int index) onRemove;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, index) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final att = attachments[i];
          return AttachmentChip(
            attachment: att,
            onRemove: () => onRemove(i),
            colorScheme: colorScheme,
            textTheme: textTheme,
          );
        },
      ),
    );
  }
}

class AttachmentChip extends StatelessWidget {
  const AttachmentChip({
    super.key,
    required this.attachment,
    required this.onRemove,
    required this.colorScheme,
    required this.textTheme,
  });

  final ChatAttachment attachment;
  final VoidCallback onRemove;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: attachment.isImage
                ? Image.memory(
                    attachment.bytes,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) => _docIcon(),
                  )
                : _docIcon(),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: colorScheme.error,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close,
                size: 12,
                color: colorScheme.onError,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _docIcon() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.insert_drive_file_outlined,
          size: 24,
          color: colorScheme.primary,
        ),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            attachment.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              fontSize: 8,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
