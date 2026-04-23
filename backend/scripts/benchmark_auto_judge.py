"""Benchmark the room auto-jump-in judge across models and prompt variants.

Run with:

    cd backend
    uv run python scripts/benchmark_auto_judge.py

Edit ``MODELS``, ``PROMPT_VARIANTS``, or ``SCENARIOS`` below to extend.

Each scenario specifies an agent persona, recent transcript, and the
ground-truth ``expected`` decision (True = agent should jump in). For each
model × prompt-variant we call the judge once per scenario, compare to
``expected``, and report accuracy + per-scenario hits.
"""

from __future__ import annotations

import asyncio
import json
import time
from dataclasses import dataclass, field

from app.core.config import get_settings
from app.schemas.chat import ChatOptions
from app.services.llm_provider import Message as LLMMessage
from app.services.ollama_provider import OllamaProvider

JUDGE_SCHEMA = {
    "type": "object",
    "properties": {
        "should_respond": {
            "type": "boolean",
            "description": "True only if the agent should reply to the most recent message right now.",
        },
        "reason": {"type": "string", "description": "Short justification (one sentence)."},
    },
    "required": ["should_respond", "reason"],
}


# ---------------------------------------------------------------------- prompts

def _transcript(history: list[tuple[str, str]]) -> str:
    return "\n".join(f"[{who}]: {text}" for who, text in history)


def _peer_line(others: list[str]) -> str:
    return (
        f"Other agents present: {', '.join(others)}."
        if others
        else "You are the only agent in the room."
    )


def _persona_line(persona: str | None) -> str:
    if persona:
        return f'Persona/instructions: "{persona[:400]}"'
    return "No specific persona — general-purpose assistant."


def prompt_v1_strict(agent: Agent, scenario: Scenario) -> tuple[str, str]:
    """Original prompt — biased toward NO."""
    sys = (
        "You are a routing classifier for a multi-participant chat room. "
        "Decide whether one specific AI agent should reply to the most recent "
        "message. Respond as JSON matching the provided schema.\n\n"
        f"Agent name: {agent.name}\n"
        f"{_persona_line(agent.persona)}\n"
        f"{_peer_line(scenario.other_agents)}\n\n"
        "Set should_respond=true ONLY IF replying would clearly add value: the "
        "most recent message asks a question this agent can answer, explicitly "
        "invites this agent, or directly relates to its expertise. Set "
        "should_respond=false for small-talk between humans, off-topic chatter, "
        "anything already handled by another agent, or messages that simply "
        "don't need a reply."
    )
    usr = (
        f"Recent conversation:\n{_transcript(scenario.history)}\n\n"
        f"Should '{agent.name}' reply to the most recent message?"
    )
    return sys, usr


def prompt_v2_balanced(agent: Agent, scenario: Scenario) -> tuple[str, str]:
    """Balanced prompt — clearer YES rules, still respects expertise."""
    sys = (
        "You decide whether an AI assistant in a group chat should reply to "
        "the latest message. Output JSON matching the schema.\n\n"
        f"Assistant name: {agent.name}\n"
        f"{_persona_line(agent.persona)}\n"
        f"{_peer_line(scenario.other_agents)}\n\n"
        "Default behavior: an AI assistant SHOULD answer when a human asks any "
        "question — factual, opinion, recommendation, how-to, etc. — unless a "
        "more specialized assistant is clearly the better fit.\n\n"
        "Set should_respond=true if the latest message:\n"
        "  • is a question (factual, how-to, recommendation, opinion)\n"
        "  • asks for help, explanation, or information\n"
        "  • invites this assistant by name or @-mention\n"
        "  • is on a topic this assistant can handle well\n\n"
        "Set should_respond=false if the latest message:\n"
        "  • is small-talk strictly between humans (greetings, banter, "
        "personal logistics with no question)\n"
        "  • is clearly outside this assistant's persona AND another listed "
        "assistant is a much better fit\n"
        "  • is just an acknowledgement (\"thanks\", \"ok\", \"got it\")\n"
        "  • has already been answered fully by another assistant in the "
        "transcript and adds nothing"
    )
    usr = (
        f"Recent conversation:\n{_transcript(scenario.history)}\n\n"
        f"Should '{agent.name}' reply to the LAST message?"
    )
    return sys, usr


def prompt_v3_helpful(agent: Agent, scenario: Scenario) -> tuple[str, str]:
    """Helpful-default prompt — strongly biased toward answering questions."""
    sys = (
        "You are a router for a chat room with humans and AI assistants. For "
        "the assistant described below, decide whether it should reply to the "
        "most recent message. Output JSON matching the schema.\n\n"
        f"Assistant: {agent.name}\n"
        f"{_persona_line(agent.persona)}\n"
        f"{_peer_line(scenario.other_agents)}\n\n"
        "Rule of thumb: AI assistants exist to be helpful. If a human asks any "
        "question or requests information/help, the assistant SHOULD reply "
        "(should_respond=true) — even general-knowledge questions like travel "
        "times, definitions, recipes, etc. — UNLESS another listed assistant "
        "with a more specific persona is obviously a better match.\n\n"
        "Reply with should_respond=false ONLY when:\n"
        "  • the latest message is humans chatting with each other (no "
        "question, no request)\n"
        "  • it's a brief acknowledgement (\"thanks\", \"ok\")\n"
        "  • another assistant in the room has already answered it completely\n"
        "  • the message is clearly off-topic for THIS assistant AND a more "
        "specialized assistant is present"
    )
    usr = (
        f"Conversation so far:\n{_transcript(scenario.history)}\n\n"
        f"Should '{agent.name}' reply to the latest message?"
    )
    return sys, usr


def prompt_v4_explicit(agent: Agent, scenario: Scenario) -> tuple[str, str]:
    """v4 — explicit list of request types the assistant should handle, plus
    clarifies that "off-topic" is meaningless when no other assistant exists."""
    has_others = bool(scenario.other_agents)
    others_clause = (
        f"Other AI assistants in this room: {', '.join(scenario.other_agents)}."
        if has_others
        else (
            "There is NO other AI assistant in this room — this assistant is "
            "the only one available, so it should handle anything an AI can "
            "reasonably help with, regardless of topic."
        )
    )
    sys = (
        "You are a router for a multi-participant chat room. For the AI "
        "assistant described below, decide whether it should reply to the "
        "LAST message. Output JSON matching the schema.\n\n"
        f"Assistant name: {agent.name}\n"
        f"{_persona_line(agent.persona)}\n"
        f"{others_clause}\n\n"
        "Set should_respond=TRUE for ANY of these in the latest message:\n"
        "  • a question (factual, opinion, recommendation, how-to, "
        "definition, calculation, translation)\n"
        "  • a request for help, advice, suggestions, or a recommendation\n"
        "  • a request to GENERATE content (write a story/poem/joke, "
        "summarize, brainstorm, roleplay, draft an email, continue a "
        "passage, code snippet, etc.)\n"
        "  • addressed to this assistant by name or @-mention\n"
        "  • addressed to the room generally (\"anyone\", \"can someone\")\n\n"
        "Set should_respond=FALSE only when the latest message is:\n"
        "  • humans chatting with each other with no question/request "
        "(small-talk, banter, personal logistics, complaints, sarcasm)\n"
        "  • a brief acknowledgement (\"thanks\", \"ok\", \"got it\")\n"
        "  • already answered in full by another assistant earlier in the "
        "transcript\n"
        "  • clearly outside this assistant's persona AND another listed "
        "assistant in this room is obviously a much better fit\n\n"
        "IMPORTANT: \"off-topic\" only applies when there is another "
        "assistant who fits better. If this assistant is the only one in the "
        "room, it should answer ANY reasonable AI request."
    )
    usr = (
        f"Conversation:\n{_transcript(scenario.history)}\n\n"
        f"Should '{agent.name}' reply to the LAST message?"
    )
    return sys, usr


def prompt_v5_targeted(agent: Agent, scenario: Scenario) -> tuple[str, str]:
    """v5 — short and targeted at the specific failure patterns we saw."""
    has_others = bool(scenario.other_agents)
    others_clause = (
        f"Other AI assistants in this room: {', '.join(scenario.other_agents)}."
        if has_others
        else "This is the ONLY AI assistant in the room."
    )
    sys = (
        "You decide whether one AI assistant should reply to the latest "
        "message in a group chat. Output JSON matching the schema.\n\n"
        f"Assistant: {agent.name}\n"
        f"{_persona_line(agent.persona)}\n"
        f"{others_clause}\n\n"
        "Reply with should_respond=true when the latest message is a "
        "request the assistant CAN handle. AI assistants can handle: "
        "questions, calculations, definitions, translations, advice, "
        "brainstorming, recommendations, AND ALL CREATIVE TASKS — "
        "writing stories, poems, jokes, roleplay, drafts, summaries, "
        "code. \"Entertain me\" or \"tell me a joke\" counts.\n\n"
        "Reply with should_respond=false ONLY when:\n"
        "  1. Humans are chatting with each other and there is no "
        "request for the assistant (small-talk, banter, sarcasm, "
        "complaints, logistics like \"meet at 7\").\n"
        "  2. The latest message is just an acknowledgement (\"thanks\", "
        "\"ok\", \"got it\").\n"
        "  3. Another AI assistant in this same room has ALREADY fully "
        "answered this exact question in the transcript above.\n"
        "  4. The latest message uses @name to address a specific HUMAN "
        "(not this assistant, not another assistant in the room).\n"
        "  5. There is a more specialized AI assistant in this room "
        "whose persona is a much better fit AND this assistant's "
        "persona explicitly excludes the topic.\n\n"
        "If unsure, lean toward should_respond=true — being unhelpful "
        "is worse than being slightly redundant."
    )
    usr = (
        f"Conversation:\n{_transcript(scenario.history)}\n\n"
        f"Should '{agent.name}' reply to the LAST message above?"
    )
    return sys, usr


PROMPT_VARIANTS = {
    "v1_strict": prompt_v1_strict,
    "v2_balanced": prompt_v2_balanced,
    "v3_helpful": prompt_v3_helpful,
    "v4_explicit": prompt_v4_explicit,
    "v5_targeted": prompt_v5_targeted,
}


# -------------------------------------------------------------------- scenarios


@dataclass
class Agent:
    name: str
    persona: str | None = None


@dataclass
class Scenario:
    name: str
    agent: Agent
    history: list[tuple[str, str]]
    other_agents: list[str] = field(default_factory=list)
    expected: bool = True
    notes: str = ""


SCENARIOS: list[Scenario] = [
    # ----------------------- Should JUMP IN -----------------------
    Scenario(
        name="madrid_granada_general_assistant",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "I would like to know how long it takes to go from madrid to granada in spain"),
        ],
        expected=True,
        notes="The exact failure case the user reported. Generic assistant, factual question.",
    ),
    Scenario(
        name="direct_at_mention_question",
        agent=Agent(name="Helper", persona="You are a friendly general-purpose assistant."),
        history=[
            ("alice", "Hey @Helper, what's the capital of Mongolia?"),
        ],
        expected=True,
    ),
    Scenario(
        name="coding_question_for_coder",
        agent=Agent(name="Coder", persona="You are a senior Python engineer."),
        history=[
            ("alice", "How do I sort a list of dicts by a nested key in Python?"),
        ],
        other_agents=["Designer"],
        expected=True,
    ),
    Scenario(
        name="recipe_question_to_general",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "I want to make paella tonight, can someone share a quick recipe?"),
        ],
        expected=True,
    ),
    Scenario(
        name="opinion_question",
        agent=Agent(name="Critic", persona="You give honest opinions on books and films."),
        history=[
            ("alice", "Is The Brothers Karamazov worth reading? It looks long."),
        ],
        expected=True,
    ),
    Scenario(
        name="follow_up_question_after_human_chat",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "I had a busy day at work today"),
            ("bob", "same here, totally drained"),
            ("alice", "btw can someone tell me what time the sun sets in Lisbon today?"),
        ],
        expected=True,
        notes="Mixed transcript ending in a clear question.",
    ),
    Scenario(
        name="explicit_help_request",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "could anyone help me figure out a 15% tip on $42?"),
        ],
        expected=True,
    ),
    Scenario(
        name="multi_message_question",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "I'm planning a trip"),
            ("alice", "I want to go from Madrid to Granada"),
            ("alice", "how long is the train ride?"),
        ],
        expected=True,
    ),
    # ----------------------- Should STAY QUIET -----------------------
    Scenario(
        name="human_small_talk",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "did you watch the game last night?"),
            ("bob", "yeah it was insane, that last goal!"),
            ("alice", "haha I screamed"),
        ],
        expected=False,
    ),
    Scenario(
        name="acknowledgement_only",
        agent=Agent(name="Helper"),
        history=[
            ("Helper", "The capital of Mongolia is Ulaanbaatar."),
            ("alice", "thanks!"),
        ],
        expected=False,
    ),
    Scenario(
        name="off_topic_for_specialized_agent",
        agent=Agent(name="Coder", persona="You are a senior Python engineer. ONLY discuss code."),
        history=[
            ("alice", "where should we get dinner tonight?"),
            ("bob", "italian sounds good"),
        ],
        other_agents=["Helper"],
        expected=False,
        notes="Coder agent shouldn't jump into dinner chat when general Helper exists.",
    ),
    Scenario(
        name="already_answered_by_other_agent",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "what's the boiling point of water in Celsius?"),
            ("Coder", "100 °C at sea level."),
            ("alice", "got it, thanks!"),
        ],
        other_agents=["Coder"],
        expected=False,
    ),
    Scenario(
        name="humans_planning_logistics",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "let's meet at 7"),
            ("bob", "works for me, see you at the usual spot"),
        ],
        expected=False,
    ),
    Scenario(
        name="human_to_human_named",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "hey @bob did you finish that report?"),
            ("bob", "almost, sending in 10"),
        ],
        expected=False,
    ),
    # ----------------------- Edge cases -----------------------
    Scenario(
        name="travel_question_with_travel_agent",
        agent=Agent(
            name="TravelExpert",
            persona="You are a travel-planning assistant; you love sharing tips on transit, hotels, and itineraries.",
        ),
        history=[
            ("alice", "I would like to know how long it takes to go from madrid to granada in spain"),
        ],
        other_agents=["Helper"],
        expected=True,
    ),
    Scenario(
        name="travel_question_with_competing_specialist",
        agent=Agent(name="Coder", persona="Senior Python engineer. ONLY discuss code."),
        history=[
            ("alice", "how long does it take to drive from madrid to granada?"),
        ],
        other_agents=["TravelExpert"],
        expected=False,
        notes="Coder should defer to TravelExpert for a travel question.",
    ),
    # ----------------------- Harder cases -----------------------
    Scenario(
        name="rhetorical_question",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "ugh why is the weather so terrible today??"),
            ("bob", "tell me about it, can't even go for a run"),
        ],
        expected=False,
        notes="Rhetorical complaint, not a real question for the assistant.",
    ),
    Scenario(
        name="implicit_request_no_question_mark",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "I have no idea how to convert 350 fahrenheit to celsius"),
        ],
        expected=True,
        notes="No '?' but clearly wants help.",
    ),
    Scenario(
        name="question_buried_in_long_chat",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "had such a long day"),
            ("bob", "what happened"),
            ("alice", "back-to-back meetings, six straight hours"),
            ("bob", "brutal"),
            ("alice", "anyway, quick q — what's the difference between TCP and UDP again? someone asked me at lunch and I blanked"),
        ],
        expected=True,
        notes="Real question is the last line of a long human chat.",
    ),
    Scenario(
        name="agent_started_but_did_not_finish",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "what's the largest moon of saturn?"),
            ("Helper", "The largest moon of Saturn is"),
            ("alice", "?"),
        ],
        expected=True,
        notes="Agent's previous reply was cut off; should follow up.",
    ),
    Scenario(
        name="non_english_question",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "¿cuál es la capital de Argentina?"),
        ],
        expected=True,
        notes="Spanish question should still trigger a YES.",
    ),
    Scenario(
        name="human_named_at_mention_for_human",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "@charlie did you push the fix?"),
        ],
        expected=False,
        notes="@-mention is at a human, not the agent.",
    ),
    Scenario(
        name="agent_explicitly_invited_in_prose",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "hey, would love to hear what Helper thinks about whether we should switch to typescript"),
        ],
        expected=True,
        notes="Invited by name without using @.",
    ),
    Scenario(
        name="follow_up_clarifying_question",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "what's the speed of light?"),
            ("Helper", "About 299,792,458 m/s in a vacuum."),
            ("alice", "and in glass?"),
        ],
        expected=True,
        notes="Follow-up question to the agent's own answer.",
    ),
    Scenario(
        name="sarcastic_question",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "ohhh great, ANOTHER deploy at 5pm on a Friday, who thought THAT was a good idea?"),
            ("bob", "lol classic"),
        ],
        expected=False,
        notes="Sarcastic rant, not a real question.",
    ),
    Scenario(
        name="vague_complaint_no_request",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "this is so frustrating"),
        ],
        expected=False,
        notes="Statement of feeling, no question or request.",
    ),
    Scenario(
        name="question_already_being_answered_streaming_unaware",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "what year did WW2 end?"),
            ("Coder", "1945."),
        ],
        other_agents=["Coder"],
        expected=False,
        notes="Coder already answered; Helper should not duplicate.",
    ),
    Scenario(
        name="ambiguous_addressed_to_room",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "anyone here ever tried sourdough? my starter keeps dying"),
        ],
        expected=True,
        notes="Question addressed to whole room — assistant should respond.",
    ),
    # ---------------- Creative / generative requests (the new failure cases)
    Scenario(
        name="story_request_no_persona_single_agent",
        agent=Agent(name="agent"),
        history=[
            ("alice", "I'm planning a road trip from Madrid to Granada"),
            ("alice", "can you create a super story about people doing this trip?"),
        ],
        expected=True,
        notes="The exact failure case the user reported (creative story request, single agent, no persona).",
    ),
    Scenario(
        name="poem_request",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "write me a short poem about rain"),
        ],
        expected=True,
    ),
    Scenario(
        name="brainstorm_ideas_request",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "give me 5 ideas for a 7-year-old's birthday party"),
        ],
        expected=True,
    ),
    Scenario(
        name="joke_request",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "tell me a joke about cats"),
        ],
        expected=True,
    ),
    Scenario(
        name="roleplay_request",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "pretend you're a 19th century pirate and greet me"),
        ],
        expected=True,
    ),
    Scenario(
        name="multi_step_creative_request",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "first describe a dragon, then write a haiku about it"),
        ],
        expected=True,
    ),
    Scenario(
        name="advice_request_no_persona",
        agent=Agent(name="agent"),
        history=[
            ("alice", "what should I cook tonight if I have chicken, rice and broccoli?"),
        ],
        expected=True,
    ),
    Scenario(
        name="summarize_request",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "can you summarize the plot of Pride and Prejudice in 3 sentences?"),
        ],
        expected=True,
    ),
    Scenario(
        name="translation_request",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "how do you say 'I love you' in Japanese?"),
        ],
        expected=True,
    ),
    Scenario(
        name="continue_my_story_request",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "the rain fell heavy on the cobblestones as Maria stepped out…"),
            ("alice", "can you continue this for a few more sentences?"),
        ],
        expected=True,
    ),
    Scenario(
        name="creative_request_with_specialist_present",
        agent=Agent(name="agent"),
        history=[
            ("alice", "write a haiku about the ocean"),
        ],
        other_agents=["Coder"],
        expected=True,
        notes="Generic agent should still answer — Coder isn't a better fit for haikus.",
    ),
    Scenario(
        name="generic_creative_with_truly_better_specialist",
        agent=Agent(name="Coder", persona="You ONLY write Python code. Never anything else."),
        history=[
            ("alice", "write a short story about a dragon"),
        ],
        other_agents=["Helper"],
        expected=False,
        notes="Coder explicitly only does Python — Helper is a better fit.",
    ),
    Scenario(
        name="open_ended_request_to_room",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "I'm bored, entertain me"),
        ],
        expected=True,
    ),
    Scenario(
        name="long_form_request_with_context",
        agent=Agent(name="agent"),
        history=[
            ("alice", "I'm working on a fantasy novel"),
            ("alice", "the protagonist is a baker who discovers her flour is actually fairy dust"),
            ("alice", "can you write a dramatic opening paragraph?"),
        ],
        expected=True,
    ),
    Scenario(
        name="please_help_me_with",
        agent=Agent(name="Helper"),
        history=[
            ("alice", "please help me write a thank-you note to my landlord"),
        ],
        expected=True,
    ),
]


# --------------------------------------------------------------------- runner


@dataclass
class Result:
    model: str
    prompt: str
    scenario: str
    expected: bool
    decision: bool
    reason: str
    raw: str
    elapsed_ms: int
    error: str = ""


async def run_judge(
    provider: OllamaProvider,
    model: str,
    sys_prompt: str,
    user_prompt: str,
) -> tuple[str, int]:
    t0 = time.perf_counter()
    answer = await provider.chat(
        messages=[
            LLMMessage(role="system", content=sys_prompt),
            LLMMessage(role="user", content=user_prompt),
        ],
        model=model,
        options=ChatOptions(
            temperature=0.0,
            max_tokens=120,
            response_format=JUDGE_SCHEMA,
        ),
    )
    elapsed = int((time.perf_counter() - t0) * 1000)
    return answer or "", elapsed


def parse(raw: str) -> tuple[bool, str]:
    if not raw:
        return False, "<empty>"
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return False, f"<unparseable: {raw[:80]!r}>"
    if not isinstance(data, dict):
        return False, "<not object>"
    return bool(data.get("should_respond", False)), str(data.get("reason", "") or "")


async def benchmark(models: list[str], prompts: dict, scenarios: list[Scenario]) -> list[Result]:
    settings = get_settings()
    provider = OllamaProvider(base_url=settings.ollama_base_url)
    results: list[Result] = []

    for model in models:
        for prompt_name, builder in prompts.items():
            print(f"\n=== {model} | {prompt_name} ===")
            for sc in scenarios:
                sys_p, usr_p = builder(sc.agent, sc)
                # Override other_agents from scenario before building (the
                # builder already reads scenario.other_agents).
                try:
                    raw, ms = await run_judge(provider, model, sys_p, usr_p)
                    decision, reason = parse(raw)
                    err = ""
                except Exception as e:
                    raw, ms = "", 0
                    decision, reason = False, ""
                    err = repr(e)
                hit = "✅" if decision == sc.expected else "❌"
                want = "YES" if sc.expected else "NO "
                got = "YES" if decision else "NO "
                print(
                    f"  {hit} want={want} got={got}  ({ms:>4}ms)  {sc.name:<48} {reason[:80]}"
                )
                results.append(
                    Result(
                        model=model,
                        prompt=prompt_name,
                        scenario=sc.name,
                        expected=sc.expected,
                        decision=decision,
                        reason=reason,
                        raw=raw,
                        elapsed_ms=ms,
                        error=err,
                    )
                )
    return results


def summarize(results: list[Result]) -> None:
    print("\n" + "=" * 88)
    print("SUMMARY (accuracy / avg latency / false-positives / false-negatives)")
    print("=" * 88)
    by_combo: dict[tuple[str, str], list[Result]] = {}
    for r in results:
        by_combo.setdefault((r.model, r.prompt), []).append(r)

    rows = []
    for (model, prompt), rs in by_combo.items():
        n = len(rs)
        hits = sum(1 for r in rs if r.decision == r.expected)
        avg_ms = sum(r.elapsed_ms for r in rs) / n
        fp = sum(1 for r in rs if r.decision and not r.expected)
        fn = sum(1 for r in rs if not r.decision and r.expected)
        rows.append((model, prompt, hits / n, avg_ms, fp, fn, n))

    rows.sort(key=lambda r: (-r[2], r[3]))
    print(f"{'model':<28} {'prompt':<14} {'acc':>6} {'avg_ms':>8} {'FP':>3} {'FN':>3}")
    print("-" * 88)
    for model, prompt, acc, ms, fp, fn, n in rows:
        print(f"{model:<28} {prompt:<14} {acc * 100:>5.1f}% {ms:>7.0f}ms {fp:>3} {fn:>3}  (n={n})")


async def main() -> None:
    import sys

    # Allow filtering models / prompts via CLI args:
    #   uv run python scripts/benchmark_auto_judge.py model1 model2 ...
    args = sys.argv[1:]
    if args:
        models = args
    else:
        models = [
            "gemma3:1b",
            "gemma3:4b",
            "gemma4:e2b",
            "qwen3:1.7b",
            "qwen3:4b",
            "llama3.2:3b",
        ]

    results = await benchmark(models, PROMPT_VARIANTS, SCENARIOS)
    summarize(results)

    # Also dump per-scenario × per-(model,prompt) breakdown to JSON for
    # post-hoc analysis.
    out_path = "scripts/benchmark_auto_judge_results.json"
    with open(out_path, "w") as f:
        json.dump([r.__dict__ for r in results], f, indent=2)
    print(f"\nDetailed results written to {out_path}")


if __name__ == "__main__":
    asyncio.run(main())
