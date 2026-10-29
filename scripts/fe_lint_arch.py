#!/usr/bin/env python3
"""Static architecture and localization lint gate for the Flutter frontend.

Enforces three invariants that `flutter analyze` does not check:
1. Localization parity: `lib/l10n/app_en.arb` and `lib/l10n/app_es.arb` must
   define the exact same message keys and ICU `{placeholder}` parameter names.
2. UI layer & cross-feature boundaries:
   - `models/`, `services/`, and `providers/` must never import `widgets/` or
     `pages/` (data/state layers stay independent of Flutter widget trees).
   - Features must never import another feature's `pages/` (route wiring lives
     in `lib/core/router.dart`).
   - Cross-feature `widgets/` imports are restricted to documented shared UI
     surfaces; genuinely generic primitives belong in `lib/core/widgets/`.
3. File-size ceiling: non-generated `lib/**/*.dart` files must stay at or below
   `DEFAULT_MAX_LINES` (800), with a ratcheted ceiling map for legacy files so
   mega-files cannot regrow or proliferate.
"""

from __future__ import annotations

import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parent.parent
LIB_DIR = ROOT / "lib"
FEATURES_DIR = LIB_DIR / "features"
EN_ARB = LIB_DIR / "l10n" / "app_en.arb"
ES_ARB = LIB_DIR / "l10n" / "app_es.arb"

DEFAULT_MAX_LINES = 800

# Ratcheted ceilings for the few remaining files over 800 lines. Lower or
# remove entries as these files shrink; never raise them or add new entries.
LEGACY_LINE_CEILINGS: dict[str, int] = {
    "lib/features/chat/providers/chat_provider.dart": 1050,
    "lib/features/rooms/widgets/room_chat_view.dart": 960,
    "lib/features/topics/widgets/topic_context_empty_state.dart": 885,
    "lib/features/chat/widgets/chat_page.dart": 815,
}

# Shared feature widget subtrees intentionally reused by sibling features
# (e.g. rooms reusing chat composer/message building blocks).
ALLOWED_CROSS_FEATURE_WIDGET_PREFIXES: tuple[str, ...] = (
    "features/chat/widgets/input/",
    "features/chat/widgets/message/",
    "features/mentions/widgets/",
)

ALLOWED_CROSS_FEATURE_WIDGET_FILES: frozenset[str] = frozenset(
    {
        "features/admin/widgets/mcp_server_dialog.dart",
        "features/chat/widgets/tool_bubble_widget.dart",
        "features/folders/widgets/chat_folder_attachments.dart",
        "features/folders/widgets/folder_download_button.dart",
        "features/friends/widgets/friend_picker_field.dart",
        "features/friends/widgets/share_with_friend_dialog.dart",
        "features/microapps/widgets/micro_app_panel.dart",
        "features/reports/widgets/submit_report_dialog.dart",
        "features/rooms/widgets/create_room_dialog.dart",
        "features/rooms/widgets/room_chat_view.dart",
        "features/rooms/widgets/rooms_list_view.dart",
        "features/settings/widgets/settings_drawer.dart",
        "features/topics/widgets/active_context_panel.dart",
        "features/topics/widgets/topic_context_empty_state.dart",
        "features/topics/widgets/topic_greeting_card.dart",
        "features/topics/widgets/topic_landing.dart",
    }
)

_FEATURE_UI_IMPORT_RE = re.compile(
    r"""^\s*(?:import|export)\s+['"]package:garbanzo_ai/(features/([^/]+)/(widgets|pages)/[^'"]+)['"]""",
    re.MULTILINE,
)
_IDENT_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def _extract_icu_placeholders(text: str) -> set[str]:
    """Extract ICU message parameter names, handling nested plural/select forms."""
    found: set[str] = set()
    n = len(text)

    def parse_segment(start: int, stop_on_close: bool) -> int:
        i = start
        while i < n:
            ch = text[i]
            if stop_on_close and ch == "}":
                return i + 1
            if ch == "{":
                i = parse_placeholder(i + 1)
                continue
            i += 1
        return i

    def parse_placeholder(start: int) -> int:
        # Read `{name}` or `{name, type, ...}`.
        comma = text.find(",", start)
        close = text.find("}", start)
        if close == -1:
            return n
        if comma == -1 or close < comma:
            token = text[start:close].strip()
            if _IDENT_RE.match(token):
                found.add(token)
            return close + 1
        token = text[start:comma].strip()
        if _IDENT_RE.match(token):
            found.add(token)
        # Scan until matching `}`, recursing into nested `{...}` option bodies.
        i = comma + 1
        while i < n:
            if text[i] == "}":
                return i + 1
            if text[i] == "{":
                i = parse_segment(i + 1, stop_on_close=True)
            else:
                i += 1
        return n

    parse_segment(0, stop_on_close=False)
    return found


def check_arb_parity() -> list[str]:
    errors: list[str] = []
    en_data = json.loads(EN_ARB.read_text(encoding="utf-8"))
    es_data = json.loads(ES_ARB.read_text(encoding="utf-8"))

    en_keys = {k for k in en_data if not k.startswith("@")}
    es_keys = {k for k in es_data if not k.startswith("@")}

    missing_es = sorted(en_keys - es_keys)
    missing_en = sorted(es_keys - en_keys)
    if missing_es:
        errors.append(
            f"ARB parity: keys in app_en.arb missing from app_es.arb: {', '.join(missing_es)}"
        )
    if missing_en:
        errors.append(
            f"ARB parity: keys in app_es.arb missing from app_en.arb: {', '.join(missing_en)}"
        )

    for key in sorted(en_keys & es_keys):
        en_ph = _extract_icu_placeholders(str(en_data[key]))
        es_ph = _extract_icu_placeholders(str(es_data[key]))
        if en_ph != es_ph:
            errors.append(
                f"ARB placeholder mismatch for '{key}': en={sorted(en_ph)} vs es={sorted(es_ph)}"
            )
    return errors


def check_ui_import_boundaries() -> list[str]:
    errors: list[str] = []
    for path in sorted(FEATURES_DIR.rglob("*.dart")):
        if path.name.endswith((".freezed.dart", ".g.dart")):
            continue
        rel = path.relative_to(ROOT).as_posix()
        parts = path.relative_to(FEATURES_DIR).parts
        if len(parts) < 2:
            continue
        src_feature = parts[0]
        src_layer = parts[1]
        content = path.read_text(encoding="utf-8")

        for match in _FEATURE_UI_IMPORT_RE.finditer(content):
            target_path, dst_feature, dst_layer = match.groups()
            if src_layer in {"models", "services", "providers"}:
                errors.append(
                    f"{rel}: non-UI layer '{src_layer}/' must not import UI file '{target_path}'"
                )
                continue
            if dst_feature == src_feature:
                continue
            if dst_layer == "pages":
                errors.append(
                    f"{rel}: cross-feature page import '{target_path}' is forbidden (navigate via GoRouter instead)"
                )
                continue
            allowed = target_path in ALLOWED_CROSS_FEATURE_WIDGET_FILES or any(
                target_path.startswith(prefix)
                for prefix in ALLOWED_CROSS_FEATURE_WIDGET_PREFIXES
            )
            if not allowed:
                errors.append(
                    f"{rel}: undocumented cross-feature widget import '{target_path}' "
                    "(extract shared UI to lib/core/widgets/ or register intentional shared surface in scripts/fe_lint_arch.py)"
                )
    return errors


def check_file_sizes() -> list[str]:
    errors: list[str] = []
    for path in sorted(LIB_DIR.rglob("*.dart")):
        rel = path.relative_to(ROOT).as_posix()
        if (
            rel.startswith("lib/l10n/gen/")
            or rel.endswith(".freezed.dart")
            or rel.endswith(".g.dart")
        ):
            continue
        line_count = sum(1 for _ in path.open(encoding="utf-8"))
        ceiling = LEGACY_LINE_CEILINGS.get(rel, DEFAULT_MAX_LINES)
        if line_count > ceiling:
            errors.append(
                f"{rel}: {line_count} lines exceeds ceiling of {ceiling} lines "
                "(split into focused widgets/controllers)"
            )
    return errors


def main() -> int:
    errors = [
        *check_arb_parity(),
        *check_ui_import_boundaries(),
        *check_file_sizes(),
    ]
    if errors:
        print("Frontend architecture lint failed:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1
    print("Frontend architecture lint passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
