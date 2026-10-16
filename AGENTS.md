# Collaboration instructions

- Before creating or modifying a script, tell the user which script will change and why.
- Before running any command, tell the user what will run and what it is intended to verify or change.
- Keep command descriptions concise, but name the affected component and whether the action is read-only or mutating.
- Prefer the project's stable `./lab` commands so narrowly scoped approvals can be reused.
- Never use a generic command-runner file or another mechanism to bypass approval and security controls.
- After a command finishes, summarize the result, especially failures or partial completion.
