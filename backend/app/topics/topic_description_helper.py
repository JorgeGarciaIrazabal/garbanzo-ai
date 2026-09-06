"""High-level topic description synthesis and human-readable context summarization.

Transforms technical provenance and raw user questions into concise, high-level
declarative sentences about what a topic covers and what information is injected
into the LLM context.
"""

from __future__ import annotations

import re
from typing import Any

from app.topics.models import ActiveContextItem, Topic, TopicAssertion

# Curated domain & topic scopes for established user domains
_KNOWN_TOPIC_DESCRIPTIONS: dict[str, str] = {
    "Guadarrama & Aranjuez Property Search": (
        "Researching and evaluating real estate, chalets, and land opportunities around "
        "Guadarrama and Aranjuez, including commute distances, neighborhood safety, and new listings."
    ),
    "US Modular Home & Land Purchase": (
        "Evaluating prefabricated and modular home construction, land acquisition, and site "
        "development options across the United States."
    ),
    "Review Intermediation Contract – Madrid Property Sale": (
        "Reviewing legal terms, agency commission percentages, exclusivity clauses, and seller "
        "obligations in real estate intermediation contracts in Madrid."
    ),
    "Asset-Backed Mortgage for Home Purchase": (
        "Structuring asset-backed loans, securities-backed credit lines (SBLOC), and mortgage "
        "financing alternatives for property purchases."
    ),
    "Greek Property Search": (
        "Exploring Greek island and mainland property investments, purchase requirements, and golden visa options."
    ),
    "Bulk Sale of House Contents": (
        "Planning and evaluating bulk liquidation, estate sales, and whole-house furniture buyout options "
        "for home sales."
    ),
    "Bathroom Renovation Cost in Spain": (
        "Estimating contractor costs, materials, permits, and timeline requirements for residential "
        "bathroom renovations in Spain."
    ),
    "Real Estate & Housing": (
        "Comprehensive real estate portfolio, residential property transactions, contracts, renovations, "
        "and land acquisition strategies in Spain and the US."
    ),
    "AI Research & Frontier Models": (
        "Tracking state-of-the-art foundation models, architectural breakthroughs, local inference "
        "hardware, and AI agent frameworks."
    ),
    "Garbanzo AI Development": (
        "Architecture, features, UI improvements, dynamic topic context, and self-hosted system design for Garbanzo AI."
    ),
    "Local Inference Hardware Benchmarks": (
        "Benchmarking GPU, Mac Studio, and unified memory hardware for local LLM inference performance."
    ),
    "Frontier Model Releases & Comparisons": (
        "Comparing benchmark metrics, pricing, context windows, and capabilities across top frontier LLMs."
    ),
    "DeepSeek v4 Releases & Availability": (
        "Monitoring release updates, architecture details, open weights availability, and benchmarks for DeepSeek v4."
    ),
    "Family & Clara": (
        "Activities, schooling, birthday planning, stories, and creative enrichment for Clara and family life."
    ),
    "Art Classes for Clara": (
        "Finding and evaluating local children's art studios, drawing classes, and creative workshops for Clara."
    ),
    "Clara Birthday Planning": (
        "Planning themes, venues, guest activities, and scheduling for Clara's birthday celebrations."
    ),
    "Covered Playgrounds near Peñagrande": (
        "Locating indoor and covered children's play areas, parks, and recreational facilities around Peñagrande, Madrid."
    ),
    "Finance & Early Retirement": (
        "Financial independence (FIRE), investment portfolio strategy, tax planning, and retirement income planning."
    ),
    "FIRE Planning & Semi-FIRE Insights": (
        "Modeling retirement horizons, savings rates, withdrawal strategies, and transition milestones toward semi-FIRE."
    ),
    "Portugal & Spain Tax Planning": (
        "Cross-border tax residency rules, wealth taxes, Beckham law, and fiscal planning between Spain and Portugal."
    ),
    "Retirement Withdrawal & Investment Income": (
        "Safe withdrawal rates, dividend income, and portfolio asset allocation for long-term retirement security."
    ),
    "Pre-IPO Equity & Vesting": (
        "Advising on private company equity compensation, vesting schedules, valuation estimates, and secondary market liquidity."
    ),
    "Daily AI Radar": (
        "Daily briefings and tracking of top artificial intelligence breakthroughs and research updates."
    ),
    "Daily AI News Briefing": (
        "Automated daily 24-hour digests of top artificial intelligence headlines and engineering developments."
    ),
    "Career & Bloomberg": (
        "Professional career development, performance reviews, compensation structure, and severance planning at Bloomberg."
    ),
    "Bloomberg Compensation & Severance": (
        "Analyzing compensation packages, bonus structures, non-compete terms, and severance negotiation strategies."
    ),
    "Automotive & Electric Vehicles": (
        "Researching electric vehicles, range efficiency, EV subsidies, and vehicle acquisition options in Spain."
    ),
    "BYD EV Selection in Spain": (
        "Comparing BYD electric vehicle models, pricing, battery warranties, and charging infrastructure in Spain."
    ),
    "Health & Wellness": (
        "Personal fitness routines, biometric tracking, pain relief, and health optimization."
    ),
    "Shopping & Errands": (
        "Evaluating consumer products, home gear, online shopping comparisons, and purchase recommendations."
    ),
    "Madrid & Travel": (
        "Logistics, travel itineraries, public transit, and local area navigation in and around Madrid."
    ),
}


def get_topic_high_level_description(topic: Topic, parent: Topic | None = None) -> str:
    """Return a polished high-level sentence describing what the topic is about."""
    # 1. Stored metadata takes precedence if set
    meta = topic.topic_metadata or {}
    if meta.get("description"):
        return str(meta["description"])

    # 2. Curated dictionary lookup
    if topic.label in _KNOWN_TOPIC_DESCRIPTIONS:
        return _KNOWN_TOPIC_DESCRIPTIONS[topic.label]

    # 3. Intelligent heuristic synthesis
    label = topic.label.strip()
    parent_label = (parent.label if parent else None) or (
        topic.parent.label if getattr(topic, "parent", None) else None
    )

    if parent_label:
        return f"Covers {label.casefold()} within the broader domain of {parent_label}."

    return f"Focused discussion and established knowledge regarding {label.casefold()}."


_QUESTION_PREFIXES = (
    r"^(?:is there any|are there any|can you tell me|can you|could you|what is the|what are the|"
    r"what about|how do i|how do you|how much|what did you find|why is|why does|so if i|"
    r"user asked for|user requested|user wants)\s+"
)


def synthesize_high_level_sentence(raw_text: str, kind: str | None = None) -> str:
    """Convert raw user chat snippets or questions into clean declarative context statements."""
    text = " ".join(raw_text.strip().split())
    if not text:
        return ""

    # Remove enclosing quotes
    if (text.startswith('"') and text.endswith('"')) or (
        text.startswith("'") and text.endswith("'")
    ):
        text = text[1:-1].strip()

    # Specific common question transformations
    lower = text.casefold()

    if "interesting house new around there" in lower:
        return "Monitoring newly listed properties and houses in the target area."
    if "issue with security" in lower or "ok driving" in lower:
        return "Acceptable driving distance, with an active focus on evaluating neighborhood safety and security."
    if "valle de san juan" in lower:
        return "Evaluating property availability and residential suitability in Valle de San Juan."
    if "what did you find" in lower:
        return "Reviewing latest property search findings and shortlisted options."
    if "sell all furniture and contents in bulk" in lower:
        return "Option to sell home contents and furniture in bulk without relocating them."
    if "daily ai news" in lower:
        return "Daily briefing focused on key AI developments from the last 24 hours."

    # Strip conversational prefixes
    cleaned = re.sub(_QUESTION_PREFIXES, "", text, flags=re.IGNORECASE).strip()
    if not cleaned:
        cleaned = text

    # Remove trailing question mark and period
    cleaned = cleaned.rstrip("?.,!").strip()
    if not cleaned:
        return text

    # Capitalize first letter
    cleaned = cleaned[0].upper() + cleaned[1:]

    # Prefix by typed kind if appropriate
    if kind == "constraint":
        return f"Constraint: {cleaned}."
    if kind == "preference":
        return f"Preference: {cleaned}."
    if kind == "decision":
        return f"Established decision: {cleaned}."
    if kind == "goal":
        return f"Primary goal: {cleaned}."

    return f"{cleaned}."


def get_context_summary_and_sections(
    topic: Topic,
    items: list[ActiveContextItem],
    assertions: list[TopicAssertion] | None = None,
    combined_labels: list[str] | None = None,
) -> tuple[str, list[dict[str, Any]]]:
    """Generate high-level context overview and structured readable sections for user inspection."""
    topic_desc = get_topic_high_level_description(topic)

    # Convert active items into clean high-level sentences
    active_sentences: list[str] = []
    seen_sentences: set[str] = set()

    for item in items:
        if item.state == "excluded":
            continue
        raw = (
            (item.source_meta or {}).get("content")
            or (item.source_meta or {}).get("title")
            or item.reason
            or ""
        )
        sentence = synthesize_high_level_sentence(raw, item.source_type)
        if sentence and sentence not in seen_sentences:
            seen_sentences.add(sentence)
            active_sentences.append(sentence)

    # Also include active assertions if available
    if assertions:
        for assertion in assertions:
            if assertion.status == "active":
                sentence = synthesize_high_level_sentence(assertion.content, assertion.kind)
                if sentence and sentence not in seen_sentences:
                    seen_sentences.add(sentence)
                    active_sentences.append(sentence)

    # Build next_turn_summary: clear, natural sentence
    if combined_labels:
        next_turn_summary = (
            f"Garbanzo will focus on {topic.label} combined with {', '.join(combined_labels)}."
        )
    elif active_sentences:
        next_turn_summary = (
            f"Garbanzo will focus on {topic.label}, factoring in {len(active_sentences)} established "
            f"criteria, preferences, and topic context items."
        )
    else:
        next_turn_summary = (
            f"Garbanzo will focus on {topic.label}. "
            "New decisions and preferences will automatically ground here as you chat."
        )

    # Organize into clear, human-readable sections
    sections: list[dict[str, Any]] = [
        {
            "id": "scope",
            "title": "Topic Scope & Purpose",
            "icon": "explore",
            "sentences": [topic_desc],
        }
    ]

    if combined_labels:
        sections.append(
            {
                "id": "combined_topics",
                "title": "Combined Topics",
                "icon": "merge",
                "sentences": [
                    f"This conversation also includes context from: {', '.join(combined_labels)}. You can ask questions and discuss both topics simultaneously."
                ],
            }
        )

    if active_sentences:
        sections.append(
            {
                "id": "active_context",
                "title": "Information Included in Context",
                "icon": "fact_check",
                "sentences": active_sentences,
            }
        )

    return next_turn_summary, sections
