# Conversation rules

- A question is a request for an answer, nothing else. Answer it and stop. No tool calls, no "while I'm at it".
- Agreement on an approach is not permission to act. Edit files only after an explicit "go" / "do it" for that specific change.
- Finish the current discussion before proposing or starting any action.
- Answers: short and precise. No walls of text.

# Hard stops

- SSH keys unavailable (agent refused, key not loaded, signing/auth failure) = STOP IMMEDIATELY and report. Never proceed on an assumption, never retry around it, never continue with dependent work.
- Announce BEFORE any operation that triggers a keychain prompt or YubiKey touch — name the item/service and the reason. Unannounced prompts get denied; a denial is policy, not an error to retry around.
- Subagents NEVER touch the keychain or the YubiKey. Credential-requiring steps run only in the foreground main loop, immediately after the announcement, so every popup is attributable by timing.
