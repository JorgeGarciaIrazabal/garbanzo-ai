import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:garbanzo_ai/features/chat/providers/search_provider.dart';
import 'package:garbanzo_ai/features/chat/widgets/search_results_widget.dart';
import 'package:garbanzo_ai/features/chat/widgets/search_widget.dart';

/// Full-height conversation search for narrow layouts, reusing the same
/// [SearchProvider] flow as the desktop sidebar. Selecting a result loads
/// the conversation and dismisses the sheet.
Future<void> showMobileSearchSheet(BuildContext context) {
  final searchProvider = context.read<SearchProvider>();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) {
      final height = MediaQuery.of(sheetContext).size.height * 0.85;
      return Padding(
        // Keep the field above the on-screen keyboard.
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: SizedBox(
          height: height,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(sheetContext).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SearchWidget(autofocus: true),
              Expanded(
                child: SearchResultsWidget(
                  onResultSelected: () => Navigator.of(sheetContext).pop(),
                ),
              ),
            ],
          ),
        ),
      );
    },
  ).whenComplete(() {
    // Dismissed without picking a result: don't leave stale search state
    // behind for the wide-layout sidebar to render later.
    if (searchProvider.searchQuery.isNotEmpty) {
      searchProvider.clearSearch();
    }
  });
}
