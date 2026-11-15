# Jot Privacy Policy

_Last updated: November 2026_

Jot is an open-source dictation, notes and recording app that runs on your Mac. This policy covers the Jot app built from
this repository.

## The short version

Your voice is transcribed on your Mac. No audio or text is sent to the authors or to any transcription service. The one
exception is optional and off by default: if you choose cloud cleanup with your own API key, the finished transcript text
(never audio) goes to the provider you picked. Jot has no server, account, analytics, tracking, crash reporting or
advertising.

## Audio

- **Dictation**: while you dictate, the microphone audio is written to a recovery file in
  `~/Library/Application Support/Jot/Recordings/`. When the dictation succeeds the file is deleted, unless you turn on
  Settings › "Keep audio of successful dictations". Failed, cancelled and interrupted dictations keep their audio so you
  can retry; delete them from History.
- **Record Class** and **Record Call**: audio is saved continuously to
  `~/Library/Application Support/Jot/Classes/<recording>/` and kept until you delete the recording (it goes to the Trash).
  Record Call also captures what your Mac plays (the other side of a call) through a private Core Audio tap that exists
  only while recording. Jot shows no consent notice by design: recording people may require their consent where you
  live, so tell them.

## Transcription: who receives your audio

Nobody. Speech is turned into text by models running on your Mac:

- **Parakeet** models (NVIDIA, Core ML conversions by FluidInference) through the FluidAudio library, on the Neural Engine.
- **Apple's on-device speech** (SpeechAnalyzer) for live words and class/call transcripts.

## Text

- Transcripts, notes, folders, spelling rules and benchmarks are stored in
  `~/Library/Application Support/Jot/library.json`; class and call transcripts next to their audio.
- **Typing into other apps** uses Accessibility to read the focused text field (to insert at the right place and to stop
  if you change it) and to write your words. When an app doesn't allow that, Jot pastes: the transcript is put on the
  clipboard and stays there.
- **Cleanup on this Mac** (the default once its model is downloaded): the finished transcript runs through Qwen3 4B
  Instruct inside Jot, with llama.cpp. Nothing is sent anywhere. Turn it off in Settings › Cleanup.

## Cloud cleanup (optional, your own API key)

Off unless you pick Settings › Cleanup › Runs on › Cloud and paste a key. Then, after each dictation (not hold-to-talk,
not quoted text, not class or call recordings), Jot sends one HTTPS request to the provider you chose:

| Provider | Address | Default model |
|---|---|---|
| Groq | `api.groq.com/openai/v1/chat/completions` | `llama-3.1-8b-instant` |
| OpenAI | `api.openai.com/v1/chat/completions` | `gpt-5-nano` |
| Anthropic | `api.anthropic.com/v1/messages` | `claude-haiku-5-5` |
| Google Gemini | `generativelanguage.googleapis.com/v1beta/models/<model>:generateContent` | `gemini-2.5-flash-lite` |

The request contains exactly: the cleanup instructions (fixed text, the same for everyone), the finished transcript text
of that dictation, the model name and a few generation settings. Your API key is sent in a request header to that
provider only. No audio, no notes, no history, no other transcripts, no device or account details. Redirects are refused,
so the request and key can't be forwarded to another host. What the provider does with the text is governed by its own
terms and your account settings with it.

Your API keys are stored in your login Keychain (service `app.newitools.Jot.cleanup`, one item per provider), never in
files or user defaults. Clearing the key field removes the item.

## Network requests

- **Model downloads**: when you download a model, Jot fetches its files from `huggingface.co`
  (the FluidInference repositories linked on each model card, and the Qwen3 4B Instruct GGUF file for cleanup, whose
  SHA-256 is checked before it's used). Nothing about you or your audio is sent.
- **Apple speech assets**: macOS may download its own on-device speech model the first time it's needed.
- **Cloud cleanup**, only if you set it up (above).
- Nothing else. Jot does not check for updates or phone home.

## Other local data

- `~/Library/Application Support/Jot/runtime.json`: a small status file (ready/recording, window position, current page)
  rewritten every few seconds, for troubleshooting.
- While recording, Jot posts the distributed notification `app.newitools.jot.recording` (only "active: true/false") that
  other apps on your Mac can observe.
- Settings live in macOS user defaults: `defaults delete app.newitools.Jot` (or your own bundle id) removes them.
- Deleting `~/Library/Application Support/Jot` removes notes, history, recordings and models.

## Changes and contact

Changes to this policy are made in this file and visible in the repository history. Questions: hello@newitools.app or open
an issue.
