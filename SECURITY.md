# Security policy

## Supported versions

Only the latest release of Otakio receives fixes.

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

Report privately through GitHub:
**Security** tab → **Report a vulnerability** (GitHub Security Advisories).

Useful details:

- Otakio version and firmware of the device;
- what an attacker can do (for example: run code from an extension, write outside `ux0:data/otakio`, read data it should not);
- steps or a file that reproduces it.

You should get an answer within a few days. Once a fix is released, the advisory is published with credit to the reporter (unless you prefer to stay anonymous).

## How Otakio protects you

- Extensions downloaded from a repository are checked against the SHA-256 listed in its `index.json` before they are installed.
- Extensions run in a restricted environment: no file system, `io`, `os`, `debug` or module loading, and read-only settings.
- Adding a repository other than the official one shows a warning first.
- Release VPKs come with a `.sha256` file; compare it before installing.

Extensions you place by hand in `ux0:data/otakio/extensions/manual/` are not verified: only use files you trust.
