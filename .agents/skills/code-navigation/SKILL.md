---
name: code-navigation
description: Investigate Python and Dart symbols and structural code changes with Serena and ast-grep.
---

Read the repository documentation map before exploring. Use Serena symbol,
definition and reference tools, ast-grep for syntax-sensitive searches, and rg
for exact text. Avoid duplicate full-tree exploration across workers.
Start Serena with just ai-serena: the pinned upstream defaults to Dart 3.7.1,
which cannot analyze this app. The runtime adapter selects the actual Flutter
Dart executable; pyrightconfig.json selects backend/.venv and backend imports.
Generated *.freezed.dart/*.g.dart declarations must remain accessible to the
analyzer. Exclude generated code, dependencies and caches from routine retrieval.
Use Context7 only for installed-library version documentation when needed;
verify version-sensitive configuration against official upstream documentation.
