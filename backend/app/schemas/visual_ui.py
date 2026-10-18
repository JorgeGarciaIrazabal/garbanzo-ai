"""The small, shared GenUI catalog and main-chat presentation contract."""

import json
from datetime import date
from pathlib import Path
from typing import Any, Literal

from jsonschema import Draft202012Validator
from pydantic import BaseModel, ConfigDict, Field, model_validator

CATALOG = json.loads((Path(__file__).parent / "visual_ui_catalog.json").read_text())
CATALOG_ID = CATALOG["catalog_id"]
RENDER_UI_TOOL = "render_ui"
MAX_PRESENTATION_BYTES = 96_000


class UIAction(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str = Field(min_length=1, max_length=80)
    kind: Literal["follow_up", "tool"]
    prompt: str = Field(default="", max_length=2000)
    tool: str | None = None
    arguments: dict[str, Any] = Field(default_factory=dict)
    bindings: dict[str, str] = Field(default_factory=dict)

    @model_validator(mode="after")
    def check_target(self):
        if self.kind == "tool" and (not self.tool or self.tool == RENDER_UI_TOOL):
            raise ValueError("Tool actions require an existing non-presentation tool")
        if self.kind == "follow_up" and not self.prompt.strip():
            raise ValueError("Follow-up actions require a prompt")
        return self


class Presentation(BaseModel):
    """One self-contained surface; no cross-message state or executable code."""

    model_config = ConfigDict(extra="forbid")

    summary: str = Field(min_length=1, max_length=4000)
    surface_id: str = Field(min_length=1, max_length=80, pattern=r"^[a-zA-Z0-9_-]+$")
    components: list[dict[str, Any]] = Field(min_length=1, max_length=60)
    actions: list[UIAction] = Field(default_factory=list, max_length=12)

    @model_validator(mode="after")
    def validate_catalog(self):
        json.dumps(self.model_dump(), allow_nan=False)
        if len(self.model_dump_json().encode()) > MAX_PRESENTATION_BYTES:
            raise ValueError("Presentation exceeds 96 KB; reduce the data before rendering")
        by_id = {}
        actions = {a.id: a for a in self.actions}
        if len(actions) != len(self.actions):
            raise ValueError("Action IDs must be unique")
        for component in self.components:
            name = component.get("component")
            schema = CATALOG["components"].get(name) if isinstance(name, str) else None
            if schema is None:
                raise ValueError(f"Unsupported component: {name}")
            errors = list(Draft202012Validator(schema).iter_errors(component))
            if errors:
                raise ValueError(f"Invalid {name}: {errors[0].message}")
            cid = component["id"]
            if cid in by_id:
                raise ValueError("Component IDs must be unique")
            by_id[cid] = component
            if name in ("Form", "Choices") and component["action"] not in actions:
                raise ValueError("Interactive components must reference a declared action")
            if name == "Form":
                names = [f["name"] for f in component["fields"]]
                if len(set(names)) != len(names):
                    raise ValueError("Form field names must be unique")
                for field in component["fields"]:
                    if field["type"] == "select" and not field.get("options"):
                        raise ValueError("Select fields require options")
                    value = field.get("value")
                    kind = field["type"]
                    if value is not None:
                        if kind == "number" and type(value) not in (int, float):
                            raise ValueError("Number defaults must be numbers")
                        if kind == "checkbox" and not isinstance(value, bool):
                            raise ValueError("Checkbox defaults must be booleans")
                        if kind in ("text", "date", "select") and not isinstance(value, str):
                            raise ValueError("Text, date and select defaults must be strings")
                    if kind == "select":
                        options = field["options"]
                        if len(set(options)) != len(options):
                            raise ValueError("Select options must be unique")
                        if value not in (None, "") and value not in options:
                            raise ValueError("Select defaults must belong to the displayed options")
                    if kind == "date" and value:
                        date.fromisoformat(value)
            if name == "Table" and any(
                len(row) != len(component["columns"]) for row in component["rows"]
            ):
                raise ValueError("Table rows must match the columns")
            if name == "Chart":
                series = component["series"]
                if any(len(s["values"]) != len(component["labels"]) for s in series):
                    raise ValueError("Chart values must match the labels")
                if component["kind"] == "pie" and (
                    len(series) != 1 or any(v < 0 for v in series[0]["values"])
                ):
                    raise ValueError("Pie charts require one nonnegative series")
        if "root" not in by_id:
            raise ValueError("A root component is required")
        visited, visiting = set(), set()

        def walk(cid, depth=0):
            if cid not in by_id or cid in visiting or depth > 8:
                raise ValueError("Component tree has a missing child, cycle, or excessive depth")
            if cid in visited:
                raise ValueError("Components must have only one parent")
            visiting.add(cid)
            for child in by_id[cid].get("children", []):
                walk(child, depth + 1)
            visiting.remove(cid)
            visited.add(cid)

        walk("root")
        if len(visited) != len(by_id):
            raise ValueError("All components must be reachable from root")
        bound = set()
        for component in self.components:
            if component["component"] not in ("Form", "Choices"):
                continue
            aid = component["action"]
            if aid in bound:
                raise ValueError("Each action must belong to exactly one interactive component")
            bound.add(aid)
            field_names = (
                {f["name"] for f in component["fields"]}
                if component["component"] == "Form"
                else {"choice"}
            )
            if not set(actions[aid].bindings.values()) <= field_names:
                raise ValueError("Action bindings must reference fields in its component")
        if bound != set(actions):
            raise ValueError("All actions must be attached to an interactive component")
        return self

    def result(self) -> dict:
        return {
            "ok": True,
            "presentation": self.model_dump(),
        }


class UISubmission(BaseModel):
    model_config = ConfigDict(extra="forbid")

    tool_call_id: str = Field(min_length=1, max_length=100)
    surface_id: str = Field(min_length=1, max_length=80)
    action_id: str = Field(min_length=1, max_length=80)
    submission_id: str = Field(min_length=1, max_length=80)
    values: dict[str, Any] = Field(default_factory=dict)


RENDER_UI_DESCRIPTOR = {
    "type": "function",
    "function": {
        "name": RENDER_UI_TOOL,
        "description": (
            "Present an interactive native visual answer when it makes a comparison, data, "
            "explanation, plan, or task easier to understand or use. Use plain text for simple "
            "answers. Compose components as a tree with id='root'. Only layout components "
            "have children (component IDs). Forms submit actions once; submitting executes "
            "the named enabled tool without another confirmation. Tool arguments are fixed "
            "in arguments; bindings maps tool argument names to form field names. Choices "
            "submit a value named choice. Use follow_up with a prompt for conversational "
            "exploration. Include a readable summary with the key information for speech "
            "and copying. Do not repeat the full visual in your following text. "
            "Component schemas: " + json.dumps(CATALOG["components"], separators=(",", ":"))
        ),
        "parameters": Presentation.model_json_schema(),
    },
}

VISUAL_UI_NUDGE = (
    "Use render_ui automatically when interactive charts, comparisons, metrics, timelines, "
    "checklists or forms improve this answer. Prefer concise text otherwise. Base visuals "
    "on known data; never invent measurements. Use labeled form buttons explaining the "
    "change they apply. Presentation is available even when data-changing tools are disabled; "
    "only attach tool actions for enabled tools. After rendering, finish with a brief text "
    "conclusion or guidance without repeating the full visual."
)
