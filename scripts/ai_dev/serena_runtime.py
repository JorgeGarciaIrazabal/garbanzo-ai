"""Pinned Serena adapter: run the project's Dart SDK instead of bundled Dart 3.7.

The pinned upstream DartLanguageServer has no executable override. Its one
runtime-dependency hook is replaced here, before Serena constructs a server.
This adapter never downloads or patches a Dart SDK or upstream source file.
"""

import shlex
import shutil
from pathlib import Path

from serena.cli import top_level
from solidlsp.language_servers.dart_language_server import DartLanguageServer


def dart_command(_settings):
    executable = shutil.which("dart")
    if executable is None:
        raise RuntimeError("Install the project Flutter SDK before starting Serena")
    return f"{shlex.quote(str(Path(executable).resolve()))} language-server --client-id garbanzo.serena"


DartLanguageServer._setup_runtime_dependencies = staticmethod(dart_command)

if __name__ == "__main__":
    top_level()
