import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:garbanzo_ai/features/chat/providers/search_provider.dart';

class SearchWidget extends StatefulWidget {
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;

  const SearchWidget({
    Key? key,
    this.onChanged,
    this.onClear,
  }) : super(key: key);

  @override
  State<SearchWidget> createState() => _SearchWidgetState();
}

class _SearchWidgetState extends State<SearchWidget> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<SearchProvider>(
      builder: (context, searchProvider, _) {
        return Padding(
          padding: const EdgeInsets.all(12.0),
          child: TextField(
            controller: _controller,
            decoration: InputDecoration(
              hintText: 'Search conversations...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _controller.clear();
                        searchProvider.clearSearch();
                        widget.onClear?.call();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            onChanged: (value) {
              setState(() {});
              widget.onChanged?.call(value);
              if (value.isNotEmpty) {
                searchProvider.search(value);
              } else {
                searchProvider.clearSearch();
              }
            },
          ),
        );
      },
    );
  }
}
