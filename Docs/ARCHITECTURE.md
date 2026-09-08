# Architecture

Netglass is a local-only macOS SwiftUI app. The UI never builds a shell string. Every run is a discovered executable plus an argv array.

```
Sidebar / form  →  AppModel.makeSpec()  →  CommandSpec
                         ↓
                   InputValidator
                   ArgumentPolicy
                         ↓
        ToolSession + ProcessRunner (Foundation.Process)
                         ↓
              stdout / stderr line stream → ConsoleView
                         ↓
              ReportFormatter (txt / md / csv / AI copy)
```

## Process runner

`ProcessRunner` starts `Foundation.Process` on a private queue.

- `executableURL` is the located binary.
- `arguments` is a `[String]` built by the active form.
- stdin is an optional short payload (netcat), then closed.
- stdout and stderr are read through `Pipe` file-handle callbacks, split on `\n`, and hopped to the main actor.
- Stop sends `SIGTERM` to the process group, then `SIGKILL` after ~1.6s.
- stdout/stderr are coalesced (~33 ms / 48 lines) before hopping to the main actor.
- Child environment is an allowlist (`HOME`, `TMPDIR`, `USER`, locale) plus a trusted `PATH`. The GUI environment is not inherited.
- Working directory is the system temp directory.

See [SECURITY_AND_PERFORMANCE.md](SECURITY_AND_PERFORMANCE.md) for the review and remaining risks.

## Binary discovery

`BinaryLocator` walks system prefixes first for Apple tools, Homebrew first for nmap/dig, then extra Settings directories and sanitized `PATH` entries. Temporary, relative, `..`, and world-writable locations are skipped. A binary counts only if it exists, is not a directory, and is executable. Missing tools produce a visible empty state with a brew formula — they do not produce a failed `Process` with a mystery path.

## Validation

`InputValidator` is the gate for hostnames, IPv4/IPv6 (including zones), ports, interfaces, BPF-like filters, http(s) URLs, whois queries, and header lines.

Rules of thumb:

- Reject shell metacharacters and control characters.
- Reject credentials in URLs.
- Cap nmap targets at `/24` IPv4 and `/120` IPv6.
- Tokenize extra nmap flags; allow a short list (`-sT`, `-sn`, `-v`, `-p`, `--top-ports`, …). Block `--script`, `-oN`, `-sS`, spoofing, and file input.

Validation errors become console system lines. They never reach `Process`.

## Privileges

There is no helper tool and no Authorization Services prompt. Privilege-sensitive panels (tcpdump, nmap) explain the limit up front. Stderr that looks like `Permission denied` / `BIOCSETIF` / “are you root” flips a lock card.

The safe v1 choice is user-guided elevation outside the app (ChmodBPF or a reviewed `sudo` in Terminal). A future `SMAppService` helper could exec a fixed tcpdump argv after a system prompt; that is a codesign and installer project of its own.

## Sandbox

Debug and Release use `Config/Netglass.entitlements` with App Sandbox **off**. A sandboxed sibling file exists only to document what a store-shaped entitlement list would look like, including temporary absolute-path reads. Those exceptions do not restore BPF or raw sockets.

Release enables Hardened Runtime. Library validation stays on; Netglass does not load third-party dylibs.

## UI

`GlassChrome` uses `ultraThinMaterial`, hairline gradients, and `NSVisualEffectView` so Sonoma and Sequoia already look like frosted glass. When the project is compiled with a macOS 26 SDK (Swift 6.2+), `glassEffect` is applied behind `#if compiler(>=6.2)` and `#available(macOS 26.0, *)`.

Each tool keeps its own `ToolSession` so switching sidebar items does not wipe output. The console keeps a 5,000-line ring buffer and sanitizes ANSI/control characters.

## Export

`ReportFormatter` renders the current buffer plus session metadata. It never re-runs a tool. Saves go through `NSSavePanel` and `InputValidator.userWritePath`. CSV parses ping timing lines, dig answer/authority/additional sections, and nmap port rows when those patterns are present; otherwise it writes `line_number,text`.

## What this is not

No iOS target, no accounts, no bundled GPL binaries, no exploit presets, no mass-scan defaults.
