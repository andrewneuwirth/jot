# Security

Please report vulnerabilities privately through GitHub: the repository's **Security** tab → **Report a vulnerability**,
or email hello@newitools.app. Don't open a public issue for a security problem.

Include what you found, how to reproduce it, and the affected version or commit. We'll acknowledge the report as soon as we
can and credit you in the fix unless you'd rather not be named.

In scope: anything that could expose audio, transcripts or notes, or let another process drive Jot: the global keyboard
tap and Accessibility text insertion, the clipboard paste fallback, the system-audio tap used by Record Call, the
`jot://` URL scheme (that `jot://toggle` needs no confirmation is intentional), `Jot --transcribe`, model downloads and their integrity checks (including the cleanup model's SHA-256 check), the built-in cleanup model
(llama.cpp parsing a downloaded GGUF file, and dictated text that tries to act as instructions), and the optional cloud
cleanup request and API keys kept in the Keychain.
Jot has no servers, so there is no hosted service to test.
