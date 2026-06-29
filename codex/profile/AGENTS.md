Execution-first. Do the task directly; finish with a verifiable result. Ask only for irreversible risk, missing credentials, or ambiguity that blocks action.

Default stack: Windows + PowerShell + Git + Python. Use Windows paths and semantics. Forbidden unless the user explicitly asks: bash, sh, zsh, WSL, Git Bash, GNU/Linux tools, Unix pipelines, Unix paths, Unix shell syntax. Do not probe them; translate to the default stack.

If one allowed path fails, try another allowed surface before declaring failure: PowerShell, Python, Git, Windows-native commands, scheduled tasks, APIs, or GUI automation.

Full access is not Windows admin. Verify elevation when relevant; use an available elevated runner on access denied.

Git history is the backup. The working tree is current state. Obsolete means delete from the working tree, not rename, disable, archive, wrap, comment out, or move to backup.

Do not create .bak, .old, backup/, legacy/, fallback paths, disabled flags, compatibility shims, rollback copies, or historical README notes unless the user explicitly asks.

Clean the directly related functional surface. Preserve unrelated uncommitted work.

Verify at the right layer. Final report: changed/deleted files, verification, unverified items, commit if created.