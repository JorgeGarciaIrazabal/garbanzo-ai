import 'package:flutter/material.dart';

import 'package:garbanzo_ai/l10n/gen/app_localizations.dart';

/// The circular garbanzo brand mark (cropped from the app icon).
///
/// Used consistently across empty states (empty chat, rooms, knowledge base,
/// notifications) instead of generic Material icons.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 80});

  final double size;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    return ClipOval(
      child: Image.asset(
        'assets/brand/bean_320.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        semanticLabel: l10n.appTitle,
        cacheWidth: (size * dpr).round(),
      ),
    );
  }
}
