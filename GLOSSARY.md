# Glossary

| Term | Here it means |
|---|---|
| **Dictation** | Short capture with paste-back into the focused editor. One of the two live flows on `main`. |
| **Meeting** | Long capture of local mic plus system audio, transcribed locally to Markdown. The other live flow. |
| **Paste-back** | Writing the transcribed text into whatever editor had focus when capture started. |
| **Local-speaker review** | The optional pass for people sharing a room mic. |
| **Draft** | The earlier codebase `main` is derived from. Its drafting and ghostwriting flow is **not** active on `main`. |
| **Legacy standalone** | The pre-takeover Transcripted app, preserved on `legacy/transcripted-standalone` and tag `pre-draft-takeover-2026-04-06`. |
| **Core** | `Sources/TranscriptedCore/`, an in-repo library consumed through `Sources/Meeting/`. Keep the boundary. |
| **Agent-readable output** | Plain Markdown on disk, the point of the product: searchable by the user's own AI, with nothing leaving the Mac. |
