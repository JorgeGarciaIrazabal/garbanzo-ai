import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:garbanzo_ai/features/chat/widgets/mermaid_diagram.dart';
import 'package:highlight/languages/all.dart';
import 'package:markdown/markdown.dart' as md;

/// A reusable widget for rendering markdown content with CommonMark support.
///
/// Supports:
/// - Basic formatting (bold, italic, strikethrough)
/// - Links (opens in external browser)
/// - Code blocks with syntax highlighting and copy button
/// - Inline code
/// - Tables (GitHub Flavored Markdown)
/// - Task lists (checkboxes)
/// - Ordered and unordered lists
/// - Blockquotes
/// - Headings
/// - Inline math ($...$)
/// - Block math ($$...$$)
class MarkdownWidget extends StatefulWidget {
  const MarkdownWidget({
    super.key,
    required this.content,
    required this.colorScheme,
    required this.textTheme,
    this.isSelectable = true,
  });

  final String content;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final bool isSelectable;

  @override
  State<MarkdownWidget> createState() => _MarkdownWidgetState();
}

class _MarkdownWidgetState extends State<MarkdownWidget> {
  // MarkdownBody re-parses whenever its `data` or `styleSheet` differ from
  // the previous build. Caching both per content/theme keeps parent
  // rebuilds (streaming chunks, isSending toggles, scrolling) from
  // re-parsing every visible message's markdown on each frame.
  MarkdownStyleSheet? _styleSheet;
  Map<String, MarkdownElementBuilder>? _builders;
  bool? _cachedIsDark;
  ColorScheme? _cachedColorScheme;
  TextTheme? _cachedTextTheme;
  String? _cachedContent;
  String _processedContent = '';

  ColorScheme get colorScheme => widget.colorScheme;
  TextTheme get textTheme => widget.textTheme;

  @override
  Widget build(BuildContext context) {
    if (widget.content.isEmpty) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_styleSheet == null ||
        _cachedIsDark != isDark ||
        !identical(_cachedColorScheme, widget.colorScheme) ||
        !identical(_cachedTextTheme, widget.textTheme)) {
      _cachedIsDark = isDark;
      _cachedColorScheme = widget.colorScheme;
      _cachedTextTheme = widget.textTheme;
      _styleSheet = _buildStyleSheet(isDark);
      _builders = _buildBuilders(isDark);
    }

    if (_cachedContent != widget.content) {
      _cachedContent = widget.content;
      // Pre-process content to convert multi-line block math to
      // single-line format.
      _processedContent = _preprocessBlockMath(widget.content);
    }

    return MarkdownBody(
      data: _processedContent,
      selectable: widget.isSelectable,
      onTapLink: _handleLinkTap,
      extensionSet: md.ExtensionSet.gitHubWeb,
      styleSheet: _styleSheet,
      inlineSyntaxes: _inlineSyntaxes,
      blockSyntaxes: _blockSyntaxes,
      builders: _builders!,
    );
  }

  /// Pre-processes content to convert multi-line block math ($$...\n...$$)
  /// into single-line format ($$...$$) for easier parsing.
  String _preprocessBlockMath(String content) {
    // Replace multi-line block math with single-line format
    // Pattern: $$ followed by content (possibly with newlines) followed by $$
    final blockMathPattern = RegExp(
      r'\$\$\s*\n([\s\S]*?)\n\s*\$\$',
      multiLine: true,
    );

    return content.replaceAllMapped(blockMathPattern, (match) {
      final mathContent = match.group(1)?.trim() ?? '';
      // Convert to single-line block math format
      return '\$\$$mathContent\$\$';
    });
  }

  void _handleLinkTap(String text, String? href, String title) {
    // Links are handled automatically by flutter_markdown when using
    // MarkdownBody, but we can add custom handling here if needed.
    debugPrint('Link tapped: $href');
  }

  MarkdownStyleSheet _buildStyleSheet(bool isDark) {
    return MarkdownStyleSheet(
      // Text styles
      p: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
        height: 1.5,
      ),
      h1: textTheme.headlineLarge?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.bold,
      ),
      h2: textTheme.headlineMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.bold,
      ),
      h3: textTheme.headlineSmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.bold,
      ),
      h4: textTheme.titleLarge?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.bold,
      ),
      h5: textTheme.titleMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.bold,
      ),
      h6: textTheme.titleSmall?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.bold,
      ),
      // Emphasis
      em: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontStyle: FontStyle.italic,
      ),
      strong: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.bold,
      ),
      // Strikethrough
      del: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
        decoration: TextDecoration.lineThrough,
      ),
      // Blockquotes
      blockquote: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
        fontStyle: FontStyle.italic,
      ),
      blockquoteDecoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: colorScheme.primary.withValues(alpha: 0.5),
            width: 4,
          ),
        ),
      ),
      blockquotePadding: const EdgeInsets.all(12),
      // Code
      code: textTheme.bodyMedium?.copyWith(
        fontFamily: 'monospace',
        fontSize: (textTheme.bodyMedium?.fontSize ?? 14) * 0.9,
        backgroundColor: isDark
            ? colorScheme.surfaceContainerHighest
            : colorScheme.surfaceContainerHigh,
        color: colorScheme.onSurfaceVariant,
      ),
      codeblockPadding: EdgeInsets.zero,
      codeblockDecoration: const BoxDecoration(),
      // Lists
      listBullet: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
      listIndent: 24,
      // Tables
      tableHead: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
        fontWeight: FontWeight.bold,
      ),
      tableBody: textTheme.bodyMedium?.copyWith(
        color: colorScheme.onSurfaceVariant,
      ),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      tableBorder: TableBorder.all(
        color: colorScheme.outline.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      tableHeadAlign: TextAlign.left,
      // Links
      a: textTheme.bodyMedium?.copyWith(
        color: colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
      // Checkbox styling (for task lists)
      checkbox: textTheme.bodyMedium?.copyWith(
        color: colorScheme.primary,
      ),
      // Horizontal rule
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
    );
  }

  Map<String, MarkdownElementBuilder> _buildBuilders(bool isDark) {
    return {
      'pre': _CodeBlockBuilder(
        colorScheme: colorScheme,
        textTheme: textTheme,
        isDark: isDark,
      ),
      'inlineMath': _MathBuilder(
        colorScheme: colorScheme,
        textTheme: textTheme,
        isBlock: false,
      ),
      'blockMath': _MathBuilder(
        colorScheme: colorScheme,
        textTheme: textTheme,
        isBlock: true,
      ),
    };
  }

  // Syntax instances are stateless pattern holders (the parser carries the
  // parse state), so they're safe to share across all instances and parses.
  static final List<md.InlineSyntax> _inlineSyntaxes = [
    // Strikethrough support (~~text~~)
    md.StrikethroughSyntax(),
    // Block math support ($$...$$) - must come before inline math
    BlockMathInlineSyntax(),
    // Inline math support ($...$)
    InlineMathSyntax(),
  ];

  static final List<md.BlockSyntax> _blockSyntaxes = [
    // Table support
    md.TableSyntax(),
    // Task list support (unordered with checkboxes)
    md.UnorderedListWithCheckboxSyntax(),
    // Task list support (ordered with checkboxes)
    md.OrderedListWithCheckboxSyntax(),
  ];
}

/// Custom builder for code blocks that applies syntax highlighting
/// and adds a copy button overlay. For mermaid diagrams, renders as SVG.
class _CodeBlockBuilder extends MarkdownElementBuilder {
  _CodeBlockBuilder({
    required this.colorScheme,
    required this.textTheme,
    required this.isDark,
  });

  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final bool isDark;

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // The element content contains the code block text
    // The language is specified in the element's 'info-string' attribute
    // or can be parsed from the first line of the content
    final codeContent = element.textContent;
    final language = _extractLanguage(element);

    // Check if this is a mermaid diagram
    if (language?.toLowerCase() == 'mermaid') {
      return _MermaidCodeBlock(
        mermaidCode: codeContent,
        colorScheme: colorScheme,
        textTheme: textTheme,
      );
    }

    return _HighlightedCodeBlock(
      code: codeContent,
      language: language,
      colorScheme: colorScheme,
      textTheme: textTheme,
      isDark: isDark,
    );
  }

  String? _extractLanguage(md.Element element) {
    // Check for info-string attribute (standard markdown code block info)
    final infoString = element.attributes['info-string'];
    if (infoString != null && infoString.isNotEmpty) {
      // Extract language from info string (e.g., "dart" from "dart linenums")
      final parts = infoString.split(' ');
      if (parts.isNotEmpty) {
        return parts[0].toLowerCase();
      }
    }
    return null;
  }
}

/// Widget that renders highlighted code with a copy button.
class _HighlightedCodeBlock extends StatefulWidget {
  const _HighlightedCodeBlock({
    required this.code,
    this.language,
    required this.colorScheme,
    required this.textTheme,
    required this.isDark,
  });

  final String code;
  final String? language;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final bool isDark;

  @override
  State<_HighlightedCodeBlock> createState() => _HighlightedCodeBlockState();
}

class _HighlightedCodeBlockState extends State<_HighlightedCodeBlock> {
  bool _copied = false;

  Future<void> _copyCode() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    setState(() => _copied = true);
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) {
      setState(() => _copied = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = widget.isDark
        ? widget.colorScheme.surfaceContainerHighest
        : widget.colorScheme.surfaceContainerHigh;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: widget.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with language label and copy button
          _buildHeader(backgroundColor),
          // Code content with syntax highlighting
          _buildCodeContent(),
        ],
      ),
    );
  }

  Widget _buildHeader(Color backgroundColor) {
    final languageLabel = widget.language ?? 'code';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor.withValues(alpha: 0.5),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(8),
        ),
        border: Border(
          bottom: BorderSide(
            color: widget.colorScheme.outline.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            languageLabel,
            style: widget.textTheme.labelSmall?.copyWith(
              color: widget.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              fontFamily: 'monospace',
            ),
          ),
          _CopyButton(
            onTap: _copyCode,
            copied: _copied,
            colorScheme: widget.colorScheme,
          ),
        ],
      ),
    );
  }

  Widget _buildCodeContent() {
    // Apply syntax highlighting
    final highlightTheme = widget.isDark ? _darkTheme : _lightTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: HighlightView(
          widget.code,
          language: _normalizeLanguage(widget.language),
          theme: highlightTheme,
          textStyle: widget.textTheme.bodyMedium?.copyWith(
            fontFamily: 'monospace',
            fontSize: (widget.textTheme.bodyMedium?.fontSize ?? 14) * 0.85,
          ),
          padding: EdgeInsets.zero,
        ),
      ),
    );
  }

  String? _normalizeLanguage(String? language) {
    if (language == null) return null;

    // Map common language aliases to their canonical names
    final languageMap = {
      'js': 'javascript',
      'ts': 'typescript',
      'py': 'python',
      'rb': 'ruby',
      'sh': 'bash',
      'shell': 'bash',
      'yml': 'yaml',
      'md': 'markdown',
      'dockerfile': 'docker',
      'docker': 'docker',
    };

    final normalized = languageMap[language.toLowerCase()] ?? language.toLowerCase();

    // Check if the language is supported by the highlight package
    if (allLanguages.containsKey(normalized)) {
      return normalized;
    }

    // Fall back to 'plaintext' if language not supported
    return 'plaintext';
  }

  /// Dark theme for syntax highlighting
  static final Map<String, TextStyle> _darkTheme = {
    'root': TextStyle(
      color: const Color(0xFFE0E0E0),
      backgroundColor: Colors.transparent,
    ),
    'keyword': TextStyle(color: const Color(0xFFCF9DFF), fontWeight: FontWeight.w500),
    'built_in': TextStyle(color: const Color(0xFFCF9DFF)),
    'type': TextStyle(color: const Color(0xFF82AAFF)),
    'function': TextStyle(color: const Color(0xFF82AAFF)),
    'string': TextStyle(color: const Color(0xFFC3E88D)),
    'number': TextStyle(color: const Color(0xFFF78C6C)),
    'comment': TextStyle(color: const Color(0xFF546E7A), fontStyle: FontStyle.italic),
    'class': TextStyle(color: const Color(0xFFFFCB6B)),
    'constant': TextStyle(color: const Color(0xFFF78C6C)),
    'variable': TextStyle(color: const Color(0xFFE0E0E0)),
    'title': TextStyle(color: const Color(0xFF82AAFF)),
    'attribute': TextStyle(color: const Color(0xFFC3E88D)),
    'params': TextStyle(color: const Color(0xFFE0E0E0)),
    'symbol': TextStyle(color: const Color(0xFFC3E88D)),
    'meta': TextStyle(color: const Color(0xFF546E7A)),
    'meta-keyword': TextStyle(color: const Color(0xFFCF9DFF)),
    'meta-string': TextStyle(color: const Color(0xFFC3E88D)),
    'addition': TextStyle(color: const Color(0xFFC3E88D)),
    'deletion': TextStyle(color: const Color(0xFFFF5370)),
    'emphasis': TextStyle(fontStyle: FontStyle.italic),
    'strong': TextStyle(fontWeight: FontWeight.bold),
    'operator': TextStyle(color: const Color(0xFF89DDFF)),
    'punctuation': TextStyle(color: const Color(0xFFE0E0E0)),
    'selector-tag': TextStyle(color: const Color(0xFFFF5370)),
    'selector-id': TextStyle(color: const Color(0xFFFAD33D)),
    'selector-class': TextStyle(color: const Color(0xFFC3E88D)),
    'selector-attr': TextStyle(color: const Color(0xFFC3E88D)),
    'selector-pseudo': TextStyle(color: const Color(0xFFC3E88D)),
    'template-variable': TextStyle(color: const Color(0xFFE0E0E0)),
    'regexp': TextStyle(color: const Color(0xFFC3E88D)),
    'subst': TextStyle(color: const Color(0xFFE0E0E0)),
    'literal': TextStyle(color: const Color(0xFFF78C6C)),
    'name': TextStyle(color: const Color(0xFFE0E0E0)),
    'quote': TextStyle(color: const Color(0xFF546E7A)),
    'bullet': TextStyle(color: const Color(0xFF82AAFF)),
    'code': TextStyle(color: const Color(0xFFC3E88D)),
    'section': TextStyle(color: const Color(0xFF82AAFF)),
    'tag': TextStyle(color: const Color(0xFFFF5370)),
    'attr': TextStyle(color: const Color(0xFFC3E88D)),
    'link': TextStyle(color: const Color(0xFF82AAFF)),
    'formula': TextStyle(color: const Color(0xFFE0E0E0)),
  };

  /// Light theme for syntax highlighting
  static final Map<String, TextStyle> _lightTheme = {
    'root': TextStyle(
      color: const Color(0xFF37474F),
      backgroundColor: Colors.transparent,
    ),
    'keyword': TextStyle(color: const Color(0xFF7B1FA2), fontWeight: FontWeight.w500),
    'built_in': TextStyle(color: const Color(0xFF7B1FA2)),
    'type': TextStyle(color: const Color(0xFF1565C0)),
    'function': TextStyle(color: const Color(0xFF1565C0)),
    'string': TextStyle(color: const Color(0xFF2E7D32)),
    'number': TextStyle(color: const Color(0xFFE65100)),
    'comment': TextStyle(color: const Color(0xFF9E9E9E), fontStyle: FontStyle.italic),
    'class': TextStyle(color: const Color(0xFFBF360C)),
    'constant': TextStyle(color: const Color(0xFFE65100)),
    'variable': TextStyle(color: const Color(0xFF37474F)),
    'title': TextStyle(color: const Color(0xFF1565C0)),
    'attribute': TextStyle(color: const Color(0xFF2E7D32)),
    'params': TextStyle(color: const Color(0xFF37474F)),
    'symbol': TextStyle(color: const Color(0xFF2E7D32)),
    'meta': TextStyle(color: const Color(0xFF9E9E9E)),
    'meta-keyword': TextStyle(color: const Color(0xFF7B1FA2)),
    'meta-string': TextStyle(color: const Color(0xFF2E7D32)),
    'addition': TextStyle(color: const Color(0xFF2E7D32)),
    'deletion': TextStyle(color: const Color(0xFFC62828)),
    'emphasis': TextStyle(fontStyle: FontStyle.italic),
    'strong': TextStyle(fontWeight: FontWeight.bold),
    'operator': TextStyle(color: const Color(0xFF6A1B9A)),
    'punctuation': TextStyle(color: const Color(0xFF37474F)),
    'selector-tag': TextStyle(color: const Color(0xFFC62828)),
    'selector-id': TextStyle(color: const Color(0xFFF57C00)),
    'selector-class': TextStyle(color: const Color(0xFF2E7D32)),
    'selector-attr': TextStyle(color: const Color(0xFF2E7D32)),
    'selector-pseudo': TextStyle(color: const Color(0xFF2E7D32)),
    'template-variable': TextStyle(color: const Color(0xFF37474F)),
    'regexp': TextStyle(color: const Color(0xFF2E7D32)),
    'subst': TextStyle(color: const Color(0xFF37474F)),
    'literal': TextStyle(color: const Color(0xFFE65100)),
    'name': TextStyle(color: const Color(0xFF37474F)),
    'quote': TextStyle(color: const Color(0xFF9E9E9E)),
    'bullet': TextStyle(color: const Color(0xFF1565C0)),
    'code': TextStyle(color: const Color(0xFF2E7D32)),
    'section': TextStyle(color: const Color(0xFF1565C0)),
    'tag': TextStyle(color: const Color(0xFFC62828)),
    'attr': TextStyle(color: const Color(0xFF2E7D32)),
    'link': TextStyle(color: const Color(0xFF1565C0)),
    'formula': TextStyle(color: const Color(0xFF37474F)),
  };
}

/// Copy button widget for code blocks.
class _CopyButton extends StatelessWidget {
  const _CopyButton({
    required this.onTap,
    required this.copied,
    required this.colorScheme,
  });

  final VoidCallback onTap;
  final bool copied;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              copied ? Icons.check : Icons.copy_outlined,
              size: 14,
              color: copied
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 4),
            Text(
              copied ? 'Copied!' : 'Copy',
              style: TextStyle(
                fontSize: 12,
                color: copied
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget that renders mermaid diagrams with error fallback.
class _MermaidCodeBlock extends StatelessWidget {
  const _MermaidCodeBlock({
    required this.mermaidCode,
    required this.colorScheme,
    required this.textTheme,
  });

  final String mermaidCode;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return MermaidDiagram(
      mermaidCode: mermaidCode,
      colorScheme: colorScheme,
    );
  }
}

/// Custom inline syntax for detecting inline math ($...$).
/// Handles escaped dollar signs by not matching \$.
class InlineMathSyntax extends md.InlineSyntax {
  // Pattern explanation:
  // - (?<!\\)\$ - match $ not preceded by \ (escaped dollar)
  // - (?!\$) - not followed by $ (avoid matching $$ for block math)
  // - (.+?) - content (non-greedy, allows backslashes for LaTeX commands)
  // - (?<!\\)\$ - closing $ not preceded by \
  // - (?!\$) - not followed by $ (avoid matching $$)
  InlineMathSyntax() : super(r'(?<!\\)\$(?!\$)(.+?)(?<!\\)\$(?!\$)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final mathContent = match.group(1);
    if (mathContent == null || mathContent.isEmpty) {
      return false;
    }

    final element = md.Element('inlineMath', [md.Text(mathContent)]);
    parser.addNode(element);
    return true;
  }
}

/// Custom inline syntax for detecting block math ($$...$$).
/// Handles both single-line and multi-line (after preprocessing) block math.
class BlockMathInlineSyntax extends md.InlineSyntax {
  // Pattern explanation:
  // - (?<!\\)\$\$ - match $$ not preceded by \ (escaped)
  // - ([\s\S]+?) - content (non-greedy, allows newlines and backslashes)
  // - (?<!\\)\$\$ - closing $$ not preceded by \
  BlockMathInlineSyntax() : super(r'(?<!\\)\$\$([\s\S]+?)(?<!\\)\$\$');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final mathContent = match.group(1);
    if (mathContent == null || mathContent.isEmpty) {
      return false;
    }

    final element = md.Element('blockMath', [md.Text(mathContent.trim())]);
    parser.addNode(element);
    return true;
  }
}

/// Builder for math elements (both inline and block).
class _MathBuilder extends MarkdownElementBuilder {
  _MathBuilder({
    required this.colorScheme,
    required this.textTheme,
    required this.isBlock,
  });

  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final bool isBlock;

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final mathContent = element.textContent;

    return _MathWidget(
      mathContent: mathContent,
      colorScheme: colorScheme,
      textTheme: textTheme,
      isBlock: isBlock,
    );
  }
}

/// Widget that renders LaTeX math using flutter_math_fork.
/// Falls back to showing raw text if parsing fails.
class _MathWidget extends StatelessWidget {
  const _MathWidget({
    required this.mathContent,
    required this.colorScheme,
    required this.textTheme,
    required this.isBlock,
  });

  final String mathContent;
  final ColorScheme colorScheme;
  final TextTheme textTheme;
  final bool isBlock;

  @override
  Widget build(BuildContext context) {
    final textColor = colorScheme.onSurfaceVariant;

    Widget mathWidget;
    try {
      mathWidget = Math.tex(
        mathContent,
        textStyle: textTheme.bodyMedium?.copyWith(
          color: textColor,
        ),
        onErrorFallback: (error) {
          // Fallback to showing raw text on parse error
          return Text(
            isBlock ? '\$\$$mathContent\$\$' : '\$$mathContent\$',
            style: textTheme.bodyMedium?.copyWith(
              color: textColor,
              fontFamily: 'monospace',
            ),
          );
        },
      );
    } catch (e) {
      // Fallback to showing raw text on any error
      return Text(
        isBlock ? '\$\$$mathContent\$\$' : '\$$mathContent\$',
        style: textTheme.bodyMedium?.copyWith(
          color: textColor,
          fontFamily: 'monospace',
        ),
      );
    }

    if (isBlock) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: mathWidget,
        ),
      );
    }

    // For inline math, just return the widget directly
    return mathWidget;
  }
}