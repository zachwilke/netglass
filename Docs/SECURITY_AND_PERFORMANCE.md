# Security and performance review

Review of Netglass on this branch. Severity uses **critical / high / medium / low / note**. “Fixed” means the code on this branch changed. “Accepted” means the risk remains on purpose.

This file is the reliability overview Zach asked for. It is not a pentest of Homebrew binaries themselves.

## How the app runs a tool

```
Form → InputValidator / ArgumentPolicy → CommandSpec
     → preflight (regular file, not tmp/world-writable)
     → Process (argv only, allowlisted environment, cwd = NSTemporaryDirectory)
     → coalesced stdout/stderr → ToolSession ring buffer → ConsoleView
```

There is still no `/bin/sh -c`. Stop sends `SIGTERM` to the **process group**, then `SIGKILL`.

---

## Findings

### High — environment inheritance leaked secrets into children

**Status: fixed**

`ProcessRunner.diagnosticEnvironment()` used to copy the entire user environment (shell tokens, `AWS_*`, `SSH_*`, `DYLD_*`, `PYTHONPATH`, …) into ping/nmap/curl/tcpdump.

It now starts empty and copies only `HOME`, `TMPDIR`, `USER`, `LOGNAME`, `LANG`, `LC_CTYPE`, then sets `LC_ALL=C` and a **trusted PATH** of system + Homebrew prefixes. Child tools can no longer inherit credentials from the GUI’s environment.

### High — PATH / Homebrew binary hijack

**Status: fixed (defense in depth; extras still exist)**

Locator walked Homebrew prefixes before `/sbin`, then the raw `PATH`. A user-writable `/opt/homebrew/bin/ping` or a `PATH` entry of `/tmp` would win.

Changes:

- System tools (ping, traceroute, nc, tcpdump, whois, curl) search `/usr` and `/sbin` **first**.
- nmap and dig still prefer Homebrew, because that is where they usually live.
- Extra Settings paths and `PATH` entries must be absolute, must not contain `..`, and must not be `/tmp` or `/var/tmp`.
- World-writable directories and binaries are skipped.
- Symlinks that resolve into tmp are skipped.
- `CommandSpec.preflightError()` refuses to exec a missing, non-regular, or rejected-location binary at run time.

**Remaining:** a compromised Homebrew cellar can still replace `nmap` or `dig`. That is the Homebrew trust model, not something a GUI wrapper can solve without signatures.

### High — tcpdump filter argument smuggling

**Status: fixed**

The BPF field was appended as the last argv token **without `--`**. A filter of `-w` or `-F …` could be parsed as tcpdump options. The keyword allowlist was also bypassed by a catch-all that accepted any `[-A-Za-z0-9._]` token, including `-w`.

Changes:

- Filters must not start with `-`; individual tokens may not start with `-`.
- `=` was removed from the allowed character set.
- The filter is passed as `tcpdump … -- <expr>` so it cannot become an option.

### High — nmap extra flags allowed full-range scans

**Status: fixed**

`--top-ports 65535` and `-p 1-65535` / `-p-` satisfied the old digit/comma/hyphen check. That is a mass scan from the “advanced” box.

Changes:

- `--top-ports` capped at 100.
- Explicit port lists capped at 64 ports; a single range may span at most 256 ports.
- `-p-`, `-A`, `-O`, `-sU`, `-S…`, `--script*`, and output-file flags stay blocked (now including glued forms like `-S1.2.3.4`).

Default presets were already tame (`-sn` / `-sT -T3`). That was not the bug.

### High — console unbounded growth and main-thread flood

**Status: fixed**

Hunches confirmed:

- Each stdout line scheduled `Task { @MainActor }` immediately. nmap and tcpdump could flood the UI thread.
- `maxLines` was 8,000 but **line length was unlimited**; a single newline-free dump could grow `Data` and one `String` without bound.
- After the cap, `removeFirst` ran on every extra line (O(n)).
- ANSI / control bytes were shown raw.

Changes:

- `ProcessRunner` coalesces up to 48 lines or 33 ms into one event.
- Incomplete-line buffer capped at 64 KiB (forced flush).
- `ConsoleText` strips ANSI, replaces other control characters, and caps each line at 4,096 characters.
- `ToolSession` applies a 5,000-line suffix ring buffer in one array assignment per batch (one Observation update).
- Live tcpdump packet count max is 10,000 (50,000 for pcap files).

**Remaining:** a determined user can still run several tools at once. Each session is isolated; we did not add a global process cap.

### High — netcat listen bound all interfaces

**Status: fixed (default)**

Listen mode was `nc -l PORT`, which on macOS listens on every address. That is a wider socket than a “careful” diagnostic needs.

Listen now defaults to `nc -l 127.0.0.1 PORT`. A “Bind localhost only” toggle remains for the rare LAN check. Still no `-e` / `-c` / `-k`.

### Medium — process tree not killed

**Status: fixed**

`Process.terminate()` signalled only the direct child. traceroute/nmap helpers could be left behind.

Stop now `killpg(SIGTERM)` and, after 1.6 s, `killpg(SIGKILL)` on the child’s process group (`setpgid` after `run()`).

**Remaining:** a child that calls `setsid()` can still escape the group. We will not chase that with a setuid helper.

### Medium — curl secret headers still exec’d

**Status: fixed (fail closed)**

Authorization / Cookie were redacted in the preview but still passed as argv (visible in `ps`). Those header names are now **rejected** before exec. Userinfo in URLs was already rejected.

**Remaining:** response bodies/headers from the server can still contain secrets. The console is local; do not save logs you would not put on disk.

### Medium — cwd inherited from Xcode / Finder

**Status: fixed**

Children now start in `FileManager.default.temporaryDirectory` unless a spec sets `workingDirectory` (nothing in v1 does).

### Medium — Settings rescan on every keystroke

**Status: fixed**

`refreshBinaries()` ran on each extra-path character (dozens of `stat`s). It is debounced 400 ms. Invalid lines are listed as ignored.

### Medium — ifconfig subprocess on the main thread

**Status: fixed**

Interface names come from `getifaddrs` (no subprocess, no wait). Fallback remains `any` / `en0` / `lo0`.

### Medium — App Sandbox off

**Status: accepted, messaging clarified**

Default entitlements still disable App Sandbox. That is the only practical way to exec Homebrew nmap and talk to BPF. About, privilege cards, README, and this document now say so in fail-closed language: this is a **local developer utility**, not a Mac App Store shape.

`Config/Netglass-Sandboxed.entitlements` remains a study file. Temporary path-read exceptions do **not** restore raw sockets. Do not flip sandbox on and expect tcpdump to work.

Release keeps Hardened Runtime. Debug does not (local unsigned runs). Library validation stays on.

### Medium — privilege model is user-guided only

**Status: accepted**

No sudo, no Authorization Services, no `SMAppService` helper, no setuid. tcpdump will often fail until ChmodBPF or a reviewed Terminal `sudo`. That is the v1 safety choice.

TCC: only the local-network usage string is declared. The app does not request Apple Events, Full Disk Access, or Accessibility.

### Low — save log / pcap overwrite

**Status: partially fixed**

`NSSavePanel` is still the chooser (the system overwrite prompt). pcap paths are resolved and rejected if they land in `/tmp`, `/etc`, `/usr`, `/System`, `/Library`, or other blocked prefixes.

**Remaining:** a user can still overwrite a file in their home directory. That is the save panel’s job.

### Low — binary / ANSI garbage in the console

**Status: fixed** (sanitize + line cap). pcap is written with `-w`, not streamed as text.

### Low — whois / host leading-dash flags

**Status: already OK**

Queries and hosts that start with `-` were already rejected. No extra `--` needed after that check.

### Note — supply chain

No SPM/CocoaPods dependencies in the app target. `scripts/generate-icon.py` is local, offline, stdlib-only. `Package.swift` exists only so validator tests can run; it is not linked into the `.app`.

No tokens or API keys in the tree.

### Note — startup cost

Launch still `stat`s a few hundred candidate paths (8 tools × names × prefixes). That is cheap on a Mac. Binary discovery is not repeated unless Settings change.

### Note — SwiftUI body work

Sidebar and panels are light. The console is the hot path; it now updates per **batch**, not per line. `LazyVStack` still virtualizes. We did not add a custom Metal console — not worth it for v1.

---

## What remains (top residual risks)

1. **App Sandbox is off.** Any subprocess you run has the user’s full account. Only run tools you trust.
2. **Homebrew nmap/dig are trusted as-is.** A cellar compromise is a host compromise.
3. **Hosts, filters, and URLs still appear in `ps` and in saved logs.** Secrets in headers/URLs are blocked; ordinary hostnames are not.
4. **tcpdump still needs extra privilege** the app will not obtain for you.
5. **No automated UI/integration tests on this Linux authoring host.** Validator tests are in-tree; the app target was not compiled here.

---

## Tests

Core validation is a Swift package (does not change the Xcode app target):

```bash
swift test --package-path .
```

On a Mac with Xcode’s toolchain:

```bash
xcrun swift test
```

Coverage: host/URL/header/BPF/path validation, nmap extras, extra-root sanitization, ANSI stripping.

There is no XCTest bundle inside `Netglass.xcodeproj` (the product is an app, not a framework). Use the package tests rather than `@testable import Netglass`.

---

## Manual verification on a Mac

Build:

```bash
xcodebuild -project Netglass.xcodeproj -scheme Netglass -configuration Debug build
```

Then, in the app:

| Check | What you should see |
| --- | --- |
| Ping `1.1.1.1` count 3 | Streams, then “Finished with status 0.” |
| Ping `example.com;id` | Validation error, no process. |
| Nmap extras `-p-` or `--top-ports 1000` | Blocked in the console, nmap not launched. |
| Nmap extras `-v --reason` | Allowed; argv preview matches. |
| Tcpdump filter `-w /tmp/x` | Rejected. `port 443` becomes `… -- port 443` in the preview. |
| Tcpdump without ChmodBPF | Privilege card after `permission denied`; process exits non-zero. Stop does not hang. |
| Netcat listen | Preview contains `127.0.0.1` unless you turn off localhost bind. |
| Headers `Authorization: Bearer x` | Refused. `Accept: text/plain` runs. |
| Settings extra path `../usr/bin` or `/tmp` | Listed as ignored; no binary picked from there. |
| Long nmap/tcpdump | Console stays responsive; “trimmed to 5000 lines” if flooded; Stop ends the run in ~2 s. |
| Activity Monitor / `ps eww -p <pid>` | Child env should **not** contain random `AWS_*` / shell functions from your GUI session. `PATH` should be the short trusted list. |

Hardened Runtime (Release):

```bash
xcodebuild -project Netglass.xcodeproj -scheme Netglass -configuration Release build
codesign -d --entitlements - build/Release/Netglass.app
```

Expect `com.apple.security.app-sandbox` false (or absent as a true sandbox) and Hardened Runtime on the Release binary.

---

## Changes in this pass (code)

| Area | Change |
| --- | --- |
| `ProcessRunner` | Allowlisted env, trusted PATH, process-group kill, I/O coalescing, buffer caps, temp cwd, handle teardown |
| `ToolSession` | Batched Observation updates, 5k ring buffer |
| `ConsoleText` | ANSI/control sanitize, 4k char lines |
| `InputValidator` | BPF anti-smuggle, secret headers fail-closed, URL length, write-path checks |
| `ArgumentPolicy` | Port-range / top-ports caps, glued dangerous flags |
| `BinaryLocator` | System-first vs brew-first, extra-root policy, no tmp/world-writable |
| `NetcatForm` | Localhost listen default |
| `TcpdumpForm` | `--` before filter, safer `-w` path, live count cap |
| `AppModel` | Preflight, debounced rescan, ignored-path warnings |
| `InterfaceEnumerator` | `getifaddrs` |
| About / Settings / privilege copy | Sandbox and extra-path rules stated plainly |

---

## Follow-up (UI / Sparkle)

- Console **Save…** now runs the same user-write path check as pcap output.
- Sparkle 2 is wired with a GitHub Releases appcast. Automatic checks stay off while `SUPublicEDKey` is the `REPLACE_…` placeholder. The private key must never enter git.
- Residual: once updates are enabled, the app periodically contacts GitHub over HTTPS for `appcast.xml`. That is the only network the GUI itself initiates. Diagnostic tools still only talk to hosts you type.
