import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:garbanzo_ai/features/chat/models/search_result.dart';
import 'package:garbanzo_ai/features/chat/providers/chat_provider.dart';
import 'package:garbanzo_ai/features/chat/providers/search_provider.dart';

class SearchResultsWidget extends StatelessWidget {
  const SearchResultsWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<SearchProvider>(
      builder: (context, searchProvider, _) {
        if (searchProvider.isLoading) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (searchProvider.error != null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Error: ${searchProvider.error}',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        if (!searchProvider.hasResults) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                searchProvider.searchQuery.isEmpty
                    ? 'Enter a search query'
                    : 'No results found',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          );
        }

        final results = searchProvider.results!;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Text(
                'Found ${results.total} result${results.total == 1 ? '' : 's'}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: results.items.length,
                itemBuilder: (context, index) {
                  final result = results.items[index];
                  return _SearchResultItem(
                    result: result,
                    onTap: () {
                      context.read<ChatProvider>().loadConversation(
                            result.conversation.id,
                          );
                      // Clear search when conversation is selected
                      searchProvider.clearSearch();
                    },
                  );
                },
              ),
            ),
            if (results.totalPages > 1)
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: searchProvider.currentPage > 1
                          ? () => searchProvider.previousPage()
                          : null,
                    ),
                    Text(
                      'Page ${results.page} of ${results.totalPages}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: results.hasMore
                          ? () => searchProvider.nextPage()
                          : null,
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SearchResultItem extends StatelessWidget {
  final ConversationSearchResult result;
  final VoidCallback onTap;

  const _SearchResultItem({
    required this.result,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 4.0),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                result.conversation.displayTitle,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8.0),
              if (result.matchedMessages.isNotEmpty)
                Text(
                  'Matched messages:',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.grey,
                      ),
                ),
              const SizedBox(height: 4.0),
              ...result.matchedMessages.take(2).map((msg) {
                final snippet = msg.snippet ?? msg.content;
                final displaySnippet = snippet.length > 100
                    ? '${snippet.substring(0, 100)}...'
                    : snippet;

                return Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    displaySnippet,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey[700],
                          fontStyle: FontStyle.italic,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }),
              if (result.matchedMessages.length > 2)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    '+${result.matchedMessages.length - 2} more match${result.matchedMessages.length - 2 == 1 ? '' : 'es'}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.grey,
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
