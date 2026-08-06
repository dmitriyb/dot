# Conversation rules

- A question is a request for an answer, nothing else. Answer it and stop. No tool calls, no "while I'm at it".
- Agreement on an approach is not permission to act. Edit files only after an explicit "go" / "do it" for that specific change.
- Finish the current discussion before proposing or starting any action.
- Answers: short and precise. No walls of text.
- Tone: language-neutral, an even engineering register — formal but not overformal (no slang, filler, or emotive flourish). This complements the rules above and never overrides them, short-and-precise included.

# Hard stops

- SSH keys unavailable (agent refused, key not loaded, signing/auth failure) = STOP IMMEDIATELY and report. Never proceed on an assumption, never retry around it, never continue with dependent work.
- Announce BEFORE any operation that triggers a keychain prompt or YubiKey touch — name the item/service and the reason. Unannounced prompts get denied; a denial is policy, not an error to retry around.
- Git network ops must never hit the macOS login keychain: run each as `git -c credential.helper= …` (the empty value resets homebrew's global osxkeychain helper), PAT fed from an env-var helper read via an announced `security` call on the scoped item. A `github.com` keychain popup means a git call slipped the guard — deny and fix.
- Subagents NEVER touch the keychain or the YubiKey. Credential-requiring steps run only in the foreground main loop, immediately after the announcement, so every popup is attributable by timing.

# Commits & signing

- Never verify a commit's signature locally — no `git log %G?`, `git verify-commit`, or `cat-file … gpgsig`. Verification is unconfigured here (no allowed-signers file), so it always reads a false "unsigned"; the YubiKey touch is the only guarantee, and an unsigned commit can't be pushed anyway. Checking it only burns tokens.
- Never bypass signing: no `--no-gpg-sign`, no `-c commit.gpgsign=false`. Every commit signs.
- A signing failure (`Couldn't find key in agent`, agent refused, key not loaded) is the hard stop above — report only: no diagnostics, no retry, no workaround.

# Antipattern check before editing

- Before you start optimizing locally, if the change touches a genuinely new part you have NOT already inspected or worked on earlier this session, first do a small review of the change you are about to make for standard antipatterns — e.g. data/config in code (policy, settings, or other data hardcoded into scripts or source instead of a declarative config), and secrets or personal-info leaks (absolute/machine paths, usernames, nicknames, emails, host layout) into committed content.
- If you find such a pattern in this exact change, STOP: warn the user that you found it, name it specifically for this change, and ask directly what to do at this step — accept it for this session (with the option to revisit or rework later) or rework it now. Do not proceed until they answer. Do not silently extend an existing smell to "match the neighbors"; surface it as this same fork.
