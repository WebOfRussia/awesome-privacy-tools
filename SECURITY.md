# Security Policy

## Scope

This repo contains shell scripts for self-hosting network privacy infrastructure. Security issues include:

- Credential exposure (plaintext passwords in logs, world-readable auth files, etc.)
- Privilege escalation via the scripts themselves
- Container escape or host compromise via unsafe Docker flags
- ACL bypasses in generated proxy configurations

## Reporting a vulnerability

Please **do not open a public GitHub issue** for security vulnerabilities.

Instead, use [GitHub's private vulnerability reporting](../../security/advisories/new) to submit details confidentially. Include:

1. A description of the vulnerability
2. Steps to reproduce
3. The potential impact
4. Any suggested fix (optional)

You can expect an acknowledgement within 72 hours and a fix or mitigation plan within 14 days for confirmed issues.

## Operational hardening tips

These scripts are starting points. In production you should also:

- Restrict `ALLOWED_NET` to the smallest subnet that covers your clients (do not leave `0.0.0.0/0` open to the internet unless intentional).
- Place the proxy behind a firewall — expose ports only to trusted hosts.
- Rotate credentials regularly and use strong passwords.
- Run Docker with `--cap-drop ALL` and add only required capabilities.
- Keep the base Docker images updated.
- Review container logs periodically for unexpected access patterns.
