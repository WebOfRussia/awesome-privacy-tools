# Contributing

Contributions are welcome — bug reports, new tools, documentation improvements, and everything in between.

## What belongs here

This repo collects **self-hosted network privacy tools**: scripts, configs, and helpers for running proxies, VPNs, DNS resolvers, and similar infrastructure privately on your own hardware.

Good additions:
- A new manager script for a different proxy/VPN/DNS daemon
- Improvements to existing scripts (robustness, portability, new subcommands)
- Documentation or usage examples

Out of scope:
- Traffic analysis, interception, or surveillance tools
- Anything designed to violate someone else's network policies without authorization

## How to contribute

1. Fork the repo and create a branch from `main`.
2. Make your changes.
3. Open a pull request with a clear description of what changed and why.

## Script conventions

Existing scripts follow these patterns — new scripts should do the same:

- `#!/usr/bin/env bash` shebang, `set -euo pipefail`
- Gate destructive or privileged operations behind a `need_root` check
- Validate required commands with `require_cmd` before using them
- Print a `usage` / `print_usage` function for `-h`, `--help`, and bare invocations
- Keep credentials out of process arguments where possible (prefer files or prompts)
- No hardcoded secrets or personal data

## Reporting bugs

Open a GitHub issue. Include:
- OS and Docker version
- The command you ran
- The full error output
