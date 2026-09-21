# Read-aloud model qualification

The app currently uses in-process Kokoro. The proposed Android read-aloud
replacement is gated on a local comparison: neither a model family nor the
session/player redesign is selected until a candidate improves audibly over
Kokoro in both English and Spain Spanish, meets the five-second Android p95,
generates at least twice as fast as playback, and stays within measured 6 GiB
service RAM and 16 GiB GPU allocation. Twenty blind listening scores per
language carry equal weight; a difference within 0.25/5 favours the faster
model. A server PCM arrival time is **not** an Android tap-to-audible result.

`scripts/read_aloud/corpus.json` contains the same 20 passages per language
for every candidate, plus four mixed-language passages. The reproducible
benchmarks are:

```sh
just read-aloud-eval kokoro en --limit 20
just read-aloud-eval kokoro es --limit 20
just read-aloud-eval pocket en --limit 20
just read-aloud-eval pocket es --limit 20
just read-aloud-eval-qwen-build
just read-aloud-eval-qwen-official-pull
just read-aloud-eval-qwen-official-build
just read-aloud-eval-qwen 0.6B en --limit 20
just read-aloud-eval-qwen 0.6B es --limit 20
just read-aloud-eval-qwen 1.7B en --limit 20
just read-aloud-eval-qwen 1.7B es --limit 20
QWEN_EVAL_IMAGE=garbanzo-read-aloud-eval:qwen-official just read-aloud-eval-qwen 1.7B en --limit 20
just read-aloud-eval-test
```

If the public model CDN is slow, `just read-aloud-asset <repo> <revision>
<filename>` downloads an asset in resumable parallel ranges to the local
Hugging Face cache and verifies its advertised SHA-256 before the benchmark
can use it. Use `just read-aloud-asset-qwen` for the Qwen container's cache.
The target revision must be a full commit hash; do not use `main`.

Each run writes WAV files and a `report.json` to a new directory under
`.ai/local/read-aloud/`. That directory stays private and untracked. Reports
capture exact corpus hash, package versions, pinned model and voice hashes,
reference transcript (Qwen), first PCM availability, synthesis speed, memory and
errors. A watchdog records a failed run if synthesis stops making progress for
15 seconds. A representative passage is synthesized before measurement so
first-use ROCm kernel compilation is excluded from the warm-server results.
Qwen runs in a separate ROCm image pinned by digest. Its default
voice reference for each language must be prepared as
`.ai/local/read-aloud/references/{en,es}.wav`; the report records the clip hash.
Prepare each reference with `just read-aloud-reference pocket en` and
`just read-aloud-reference pocket es` (or `kokoro` if Pocket fails). Each
reference speaks a dedicated line outside the scored corpus. The
benchmark uses Qwen's public high-level clone API, which returns an entire
unit. Its streaming behaviour has **not** been validated by an API name.

For this machine, the isolated ROCm image passed an FP16 GPU operation on the
Radeon 8060S under Ubuntu 25.10. Pocket English has publicly accessible model
weights and an Alba voice. The Pocket Spanish 24-layer checkpoint and Lola's
source recording are gated by Hugging Face, but the non-cloning checkpoint and
precomputed Lola voice state are public. The evaluation uses that combination;
it cannot offer user voice cloning. A candidate that cannot load its intended
Spanish voice is unqualified; the benchmark surfaces that access error.

Create an offline blind listening sheet from completed report paths with
`just read-aloud-listening <report.json> <report.json> ...`. It writes an HTML
sheet with randomly ordered clips and a private `mapping.json` alongside it.
The HTML exports ratings; calculate model means with
`just read-aloud-listening --score <mapping.json> <ratings.json>`. Keep the
mapping hidden until ratings are final.

Peak process RSS and PyTorch GPU reservation are diagnostic measurements.
The Qwen container also has a 6 GiB cgroup limit and records cgroup peak memory;
the benchmark requires an AMD sysfs VRAM counter and samples its use against
a pre-run baseline. Neither
metric certifies total service/device allocation if another GPU process changes
during the run, so record its load separately before applying the 16 GiB gate.

The WAV samples require human blind scoring for naturalness, pronunciation,
Spain accent and consistency. Once a candidate passes that gate, measure the
actual Android tap-to-audible path over a controlled and public connection,
including encoding, HTTPS, player buffering and UI scheduling. Test 5,000-,
20,000- and 100,000-character messages, cancellation, backgrounding, network
loss, worker stalls and segment ordering before selecting it for delivery.

## Measurements on this machine

These are warm **server PCM** results for 20 passages per language, with four
CPU threads while the normal app services were running. They exclude encoding,
network and Android player startup. RSS is the highest measured process RSS.

| Candidate | Language | p95 first PCM | Audio generated per second | Peak RSS |
| --- | --- | ---: | ---: | ---: |
| Kokoro | English | 0.97 s | 7.44× | 2,048 MiB |
| Kokoro | Spanish | 0.92 s | 7.47× | 1,824 MiB |
| Pocket TTS | English | 0.10 s | 3.93× | 973 MiB |
| Pocket TTS 24-layer | Spanish | 0.38 s | 1.23× | 2,275 MiB |

The Pocket Spanish configuration misses the required 2× sustained rate across
all 20 passages. The isolated community ROCm/PyTorch image executed an FP16
tensor operation, but Qwen 0.6B crashed during talker generation in three
attempts, including MIOpen full-search and math-only attention variants.
It also crashed with an HSA hardware exception in [AMD's validated PyTorch
image](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/docs/install/installryz/native_linux/install-pytorch.html).
The supervised runner records exit 139 as `worker_crashed`. Qwen 1.7B completed
its talker and decoder warm-up but then produced no PCM for 15 seconds on a
measured passage in both images. The representative-passage warm-up in the
validated image did not resolve the stall. The high-level Qwen API returns a
whole waveform; actual incremental output was not demonstrated.

These results fail the plan's performance and reliability qualification gate.
No Android tap-to-audible or human blind listening scores were obtained, and
no replacement model, read-aloud service, or Android player has been shipped.
The completed Kokoro/Pocket WAVs can be compared with `just read-aloud-listening`
and the local listening sheet, but those scores cannot override the failed
Spanish speed gate. Further model/runtime investigation is needed before
proceeding to the application redesign.
