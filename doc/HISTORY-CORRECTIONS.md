# History Corrections

This record corrects misleading commit subjects without rewriting signed history. It contains identifiers and intent, never key material.

## 2026-07-30: `09d2a296`

The subject `Add google-gemini to apps` is incorrect. The commit grants the Vulcan data server public-key access to John Wiegley's Darwin account by adding the `johnw@vulcan` principal to `users.users.johnw.openssh.authorizedKeys.keys`. Commit `e93939ea` subsequently updates that public key.

The Google Gemini cask was added separately by commit `06cbcb6e`.
