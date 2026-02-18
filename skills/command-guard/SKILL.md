---
name: command-guard
description: >
  Exec protection for Hive Financial Systems. Activate whenever the agent is
  about to run a shell command via exec. Blocks dangerous patterns including
  fork bombs, recursive deletes, pipe-to-shell, reverse shells, container
  escapes, persistence mechanisms, and obfuscated commands. Enforces a domain
  whitelist for curl, wget, and git clone. Validates every command before
  execution. Works alongside sandbox and tool-policy hard enforcement.
---

# Command Guard — Exec Protection

Apply these rules to EVERY `exec` tool call before execution.

## Unconditionally Blocked Patterns

If ANY of these appear anywhere in the command (including inside pipes,
subshells, or variable expansions), BLOCK immediately. Do not sanitize — block.

### Destructive Commands
- `rm -rf /` or `rm -rf /*` or `rm -rf ~` or `rm -rf $HOME`
- `dd if=/dev/zero` or `dd if=/dev/urandom` targeting block devices
- `mkfs.*` (filesystem formatting)
- `:(){:|:&};:` or any recursive fork bomb
- `> /dev/sda` or direct device writes
- `shred` on system paths

### Pipe-to-Shell (Remote Code Execution)
- `curl ... | bash` or `curl ... | sh` or `curl ... | zsh`
- `wget ... | bash` or `wget ... | sh`
- `curl ... | python` or `curl ... | perl` or `curl ... | ruby`
- Any variant with `sudo`, `-sSL`, `-qO-`

### Code Injection
- `eval` with untrusted or external input
- `source` of remote or untrusted files
- `python -c` / `node -e` / `perl -e` with untrusted inline code

### Privilege Escalation
- `sudo` (unless user explicitly pre-approves a specific command)
- `chmod 777` or `chmod -R 777` or `chmod +s` (setuid)
- `chown root` on non-owned files

### Reverse Shells & Network Attacks
- `nc -e /bin/sh` or `nc -e /bin/bash`
- `/dev/tcp/` connections
- `ncat`, `socat` reverse shells
- `nmap`, `masscan`

### Persistence Mechanisms
- `crontab -e` or writing to crontab directly
- Writing to `~/.bashrc`, `~/.profile`, `~/.zshrc`
- `systemctl enable` / `launchctl load`
- Writing to `Library/LaunchAgents`

### History/Log Tampering
- `history -c`, `unset HISTFILE`, `export HISTSIZE=0`
- Overwriting `/var/log` files

### Container Escape
- `docker run --privileged`
- `docker run -v /:/host`
- `nsenter`, `chroot`

## Network Command Domain Whitelist

When the command uses `curl`, `wget`, or `git clone`, extract the target
domain and check against this whitelist:

**Allowed domains:**
- `api.anthropic.com`
- `*.github.com`, `*.githubusercontent.com`
- `registry.npmjs.org`, `*.npmjs.com`
- `files.pythonhosted.org`, `*.pypi.org`
- `archive.ubuntu.com`, `security.ubuntu.com`

If the domain is NOT on this list, ask the user:
"This command accesses `<domain>` which is not on the approved list. Allow?"

## Obfuscation Detection

BLOCK any command containing:
- Base64 encoded payloads: `echo <long_base64> | base64 -d | bash`
- Hex-encoded strings used as commands: `\x` sequences
- Zero-width Unicode characters: `\u200B` through `\u200D`, `\uFEFF`
- Nested command substitution from untrusted input: `$($())`
- Environment variable manipulation to hide commands: `$'\x63\x61\x74'`

When in doubt, BLOCK and show the decoded/expanded command to the user.

## Chained Commands

For commands with `&&`, `;`, `||`, or `|`:
1. Split into individual segments
2. Evaluate EACH segment against all rules above
3. The chain inherits the HIGHEST risk tier of any segment
4. If ANY segment is CRITICAL → BLOCK the entire chain
