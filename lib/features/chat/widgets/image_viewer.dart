import 'package:flutter/material.dart';

import 'package:garbanzo_ai/features/chat/models/chat_attachment.dart';
import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// Full-screen image viewer with zoom, pan, and dismiss gestures.
class ImageViewer extends StatefulWidget {
  const ImageViewer({
    super.key,
    required this.attachment,
    required this.onDismiss,
  });

  final ChatAttachment attachment;
  final VoidCallback onDismiss;

  @override
  State<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<ImageViewer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _dismissController;
  double _scale = 1.0;
  Offset _offset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _dismissController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _dismissController.dispose();
    super.dispose();
  }

  void _handleScaleUpdate(ScaleUpdateDetails details) {
    setState(() {
      _scale = (_scale * details.scale).clamp(0.5, 5.0);
    });
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_scale > 1.0) {
      setState(() {
        _offset += details.delta;
      });
    }
  }

  void _resetTransform() {
    setState(() {
      _scale = 1.0;
      _offset = Offset.zero;
    });
  }

  void _dismiss() {
    _dismissController.forward();
    Future.delayed(const Duration(milliseconds: 200), widget.onDismiss);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black87,
      body: Stack(
        children: [
          // Close button
          Positioned(
            top: 16,
            right: 8,
            child: IconButton(
              onPressed: _dismiss,
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              padding: const EdgeInsets.all(8),
              tooltip: AppLocalizations.of(context)!.labelClose,
            ),
          ),
          // Image info overlay
          Positioned(
            top: 16,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.attachment.name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _formatFileSize(widget.attachment.bytes.length),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Interactive image
          GestureDetector(
            onTap: _dismiss,
            onScaleUpdate: _handleScaleUpdate,
            onPanUpdate: _scale > 1.0 ? _handlePanUpdate : null,
            onDoubleTap: _resetTransform,
            child: Center(
              child: AnimatedBuilder(
                animation: _dismissController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 1.0 - (_dismissController.value * 0.3),
                    child: child,
                  );
                },
                child: AnimatedBuilder(
                  animation: _dismissController,
                  builder: (context, child) {
                    return Transform.translate(
                      offset: _offset * (1.0 - _dismissController.value),
                      child: Image.memory(
                        widget.attachment.bytes,
                        semanticLabel: widget.attachment.name,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.contain,
                        errorBuilder: (ctx, err, stack) {
                          return Icon(
                            Icons.broken_image,
                            size: 100,
                            color: Colors.white54,
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          // Zoom controls
          Positioned(
            bottom: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    onPressed: _scale > 0.5
                        ? () => setState(() => _scale -= 0.5)
                        : null,
                    icon: const Icon(Icons.remove, color: Colors.white),
                    tooltip: 'Zoom out',
                    iconSize: 20,
                  ),
                  Text(
                    '${(_scale * 100).toInt()}%',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  IconButton(
                    onPressed: _scale < 5.0
                        ? () => setState(() => _scale += 0.5)
                        : null,
                    icon: const Icon(Icons.add, color: Colors.white),
                    tooltip: 'Zoom in',
                    iconSize: 20,
                  ),
                ],
              ),
            ),
          ),
          // Hint text
          Positioned(
            bottom: 24,
            left: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _scale > 1.0
                    ? 'Drag to pan • Double tap to reset'
                    : 'Pinch to zoom • Double tap to reset',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: Colors.white70,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }
}
