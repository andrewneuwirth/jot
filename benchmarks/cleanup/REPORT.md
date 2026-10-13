# Local dictation cleanup experiment — 2026-10-05

Tested on the user's Mac (48 GB, macOS 26.5.1). This is text-to-text cleanup, not speech recognition, live microphone testing, or end-to-end dictation latency. Jot's production pipeline was not changed. Qwen 3.5 4B was downloaded for this experiment; Qwen 3.6 35B-A3B was already installed. Models were unloaded afterward.

## Method

15 authored development examples, each run twice per configuration. Tested Apple's Foundation Models default on-device model and local Ollama models with thinking disabled, temperature 0, context 4096 and output cap 300. Apple used greedy decoding. Each call used a new conversation. Initial prompt is prompt-v1.txt; refined prompt is prompt.txt. Prompt refinement used development observations; do not treat these cases as held-out accuracy evidence. A separate 10-case holdout was authored after prompt freezing, run twice on each Qwen model. Total: 190 calls. Repeats are timing/repeatability checks, not independent accuracy samples. Inference runs were sequential. Model download overlapped early tests, so timings are indicative, not isolated hardware benchmarks.

All raw outputs and timings are retained in JSONL. summarize.py's exact-word match is intentionally strict and is not a semantic quality metric: it ignores punctuation but flags equivalent paraphrases and number formatting. Review outputs directly. The scripts currently read the refined prompt; use prompt-v1.txt to reproduce initial runs.

## Results with refined prompt

| Model | Warm median | User correction warm | First observed call including load | Main findings |
|---|---:|---:|---:|---|
| Apple on-device | 0.385 s | 0.369 s, failed | 1.076 s | Kept Tuesday/I mean Wednesday; failed numerical correction; obeyed a dictated instruction rather than transcribing it. |
| Qwen 3.5 4B | 0.360 s | 0.331 s, correct | 1.497 s | Corrected Wednesday and fifty, preserved quoted fillers and meaningful like; missed held-out Jordan-to-Morgan correction; long text removed I think and turned a question into a command. |
| Qwen 3.6 35B-A3B | 0.355 s | 0.355 s, correct | 10.310 s initial; 5.695 s reload | Corrected names/dates/negation, but refined prompt removed intentional repetition and words inside quotations. |

Apple median covers 15 cases; Qwen medians cover 25. Long paragraph warm cleanup: Qwen 4B 0.865 s, Qwen 35B 0.757 s. These are observed local HTTP/framework completion times, not just token generation. Keeping a model resident avoids most loading cost but consumes memory. 35B downloaded weights are approximately 22.6 GB; 4B approximately 3.4 GB; these are disk sizes, not measured resident memory.

User target, both Qwen models:

Input: Can we go to the store Tuesday, I mean Wednesday.
Output: Can we go to the store Wednesday?

Other observed 4B examples:
- Make it fifteen, sorry, fifty dollars. -> Make it fifty dollars.
- Can we go to the store like Tuesday? -> Can we go to the store on Tuesday?
- I like the blue one, but she likes the purple one. -> unchanged.
- I can attend, sorry, I cannot attend the meeting. -> I cannot attend the meeting.
- We could go Tuesday or Wednesday. -> unchanged.

## Recommendation

A small local text model is a practical cleanup layer: about 0.36 seconds median warm overhead in this sample. Qwen 3.5 4B is the better lightweight prototype candidate of these tests, but neither Qwen configuration is ready to promise meaning-preserving automatic cleanup on arbitrary dictation. The larger model does not justify its footprint based on these results. Apple as tested is unsuitable for the required correction behavior.

Before integration: retain the raw transcript; protect quoted spans and uncertainty/negation; detect unexpected changes; fall back to original text when validation fails; allow cleanup to be disabled and original recovered. These protections are recommendations, not implemented or proven here. Add realistic user recordings and more name/correction/long-transcript holdouts before calling the pipeline reliable. No ASR model swap is required for this cleanup step.
