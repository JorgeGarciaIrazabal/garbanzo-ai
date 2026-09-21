"""Build an offline blind listening sheet, or score an exported rating file."""

import argparse
import html
import json
import random
import secrets
import shutil
from pathlib import Path

RUBRICS = ("naturalness", "pronunciation", "accent", "consistency")
BASE = Path(__file__).resolve().parents[2] / ".ai/local/read-aloud"


def build(reports):
    candidates = {}
    corpus_hash = None
    for report_path in reports:
        report = json.loads(report_path.read_text())
        if report["status"] != "completed" or len(report["samples"]) != 20:
            raise ValueError(f"Report is not a completed 20-passage run: {report_path}")
        if corpus_hash is not None and report["corpus_sha256"] != corpus_hash:
            raise ValueError("Reports use different comparison corpora")
        corpus_hash = report["corpus_sha256"]
        key = (report["language"], report["candidate"])
        if key in candidates:
            raise ValueError(f"Duplicate candidate: {key}")
        candidates[key] = (report_path, report)
    if len(candidates) < 2:
        raise ValueError("At least two completed candidate reports are required")
    output = BASE / f"listening-{secrets.token_hex(5)}"
    samples = output / "samples"
    samples.mkdir(parents=True)
    mapping = {}
    groups = []
    languages = sorted({language for language, _ in candidates})
    for language in languages:
        language_candidates = [(key, *candidates[key]) for key in candidates if key[0] == language]
        if len(language_candidates) < 2:
            continue
        for index in range(20):
            options = []
            text = language_candidates[0][2]["samples"][index]["text"]
            for (_, candidate), report_path, report in language_candidates:
                sample = report["samples"][index]
                if sample["text"] != text:
                    raise ValueError("Candidate passage text or order differs")
                token = secrets.token_hex(8)
                filename = f"{token}.wav"
                shutil.copyfile(report_path.parent / sample["file"], samples / filename)
                mapping[token] = {
                    "candidate": candidate,
                    "language": language,
                    "passage": index + 1,
                    "source_report": str(report_path),
                }
                options.append({"id": token, "file": f"samples/{filename}"})
            random.SystemRandom().shuffle(options)
            groups.append(
                {"language": language, "passage": index + 1, "text": text, "options": options}
            )
    if not groups:
        raise ValueError("Each language needs at least two candidates")
    (output / "mapping.json").write_text(json.dumps(mapping, indent=2) + "\n")
    data = json.dumps(groups, ensure_ascii=False).replace("<", "\\u003c")
    (output / "index.html").write_text(f"""<!doctype html>
<html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Read-aloud blind listening</title>
<style>
body {{font: 16px system-ui; max-width: 940px; margin: 2rem auto; padding: 0 1rem; background: #f8f7f3; color: #202020}}
section {{background: white; padding: 1rem; margin: 1rem 0; border: 1px solid #ccc; border-radius: 8px}}
.clip {{padding: .7rem; border-top: 1px solid #ddd}} audio {{width: 100%; margin: .4rem 0}}
label {{display: inline-block; margin: .3rem .6rem .3rem 0}} select {{font-size: 1rem}}
button {{font-size: 1rem; padding: .6rem}} small {{color: #555}}
</style>
<h1>Read-aloud blind listening</h1>
<p>Listen through headphones. Score each clip from 1 (poor) to 5 (excellent) for the four qualities.
For Spanish, score a Spain accent rather than Spanish in general. You may replay clips. Your ratings
stay in this browser until you export them; model identities are kept in the separate mapping file.</p>
<p id="progress"></p><button id="export">Export ratings JSON</button><main id="trials"></main>
<script>
const groups = {data}; const rubrics = {json.dumps(RUBRICS)};
const storageKey = 'garbanzo-read-aloud-{html.escape(output.name)}';
let ratings = JSON.parse(localStorage.getItem(storageKey) || '{{}}');
const main = document.getElementById('trials');
for (const group of groups) {{
  const section = document.createElement('section');
  const heading = document.createElement('h2');
  heading.textContent = `${{group.language.toUpperCase()}} · Passage ${{group.passage}}`;
  section.append(heading);
  const passage = document.createElement('p'); passage.textContent = group.text; section.append(passage);
  for (const [index, option] of group.options.entries()) {{
    const clip = document.createElement('div'); clip.className = 'clip';
    const label = document.createElement('strong'); label.textContent = `Clip ${{String.fromCharCode(65 + index)}}`;
    clip.append(label);
    const audio = document.createElement('audio'); audio.controls = true; audio.preload = 'none'; audio.src = option.file;
    clip.append(audio, document.createElement('br'));
    for (const rubric of rubrics) {{
      const wrapper = document.createElement('label'); wrapper.textContent = `${{rubric}} `;
      const select = document.createElement('select');
      select.append(new Option('—', ''));
      for (let score = 1; score <= 5; score++) select.append(new Option(String(score), String(score)));
      select.value = ratings[option.id]?.[rubric] || '';
      select.onchange = () => {{
        ratings[option.id] ||= {{}}; ratings[option.id][rubric] = Number(select.value) || null;
        localStorage.setItem(storageKey, JSON.stringify(ratings)); updateProgress();
      }};
      wrapper.append(select); clip.append(wrapper);
    }}
    section.append(clip);
  }}
  main.append(section);
}}
function updateProgress() {{
  const ids = groups.flatMap(group => group.options.map(option => option.id));
  const done = ids.filter(id => rubrics.every(rubric => ratings[id]?.[rubric] >= 1)).length;
  document.getElementById('progress').textContent = `${{done}} of ${{ids.length}} clips rated`;
}}
document.getElementById('export').onclick = () => {{
  const blob = new Blob([JSON.stringify({{schema: 1, ratings}}, null, 2)], {{type: 'application/json'}});
  const link = document.createElement('a'); link.href = URL.createObjectURL(blob);
  link.download = 'read-aloud-ratings.json'; link.click(); URL.revokeObjectURL(link.href);
}};
updateProgress();
</script></html>""")
    print(output / "index.html")
    print(f"{len(groups)} passages, {len(mapping)} blinded clips")


def score(mapping_path, rating_path):
    mapping = json.loads(mapping_path.read_text())
    ratings = json.loads(rating_path.read_text())["ratings"]
    missing = [
        token
        for token in mapping
        if any(
            not isinstance(ratings.get(token, {}).get(rubric), int)
            or not 1 <= ratings[token][rubric] <= 5
            for rubric in RUBRICS
        )
    ]
    if missing:
        raise ValueError(f"{len(missing)} clips lack complete 1–5 ratings")
    results = {}
    for token, identity in mapping.items():
        key = (identity["candidate"], identity["language"])
        results.setdefault(key, []).append(sum(ratings[token][rubric] for rubric in RUBRICS) / 4)
    for (candidate, language), values in sorted(results.items()):
        print(
            f"{candidate} {language}: {sum(values) / len(values):.3f}/5 across {len(values)} passages"
        )
    by_candidate = {}
    for (candidate, language), values in results.items():
        by_candidate.setdefault(candidate, {})[language] = sum(values) / len(values)
    for candidate, languages in sorted(by_candidate.items()):
        if "en" in languages and "es" in languages:
            print(
                f"{candidate} equal-language mean: {(languages['en'] + languages['es']) / 2:.3f}/5"
            )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("reports", nargs="*", type=Path)
    parser.add_argument("--score", nargs=2, metavar=("MAPPING", "RATINGS"), type=Path)
    args = parser.parse_args()
    if args.score:
        score(*args.score)
    elif args.reports:
        build(args.reports)
    else:
        parser.error("Provide completed report paths, or --score MAPPING RATINGS")


if __name__ == "__main__":
    main()
