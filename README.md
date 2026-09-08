# Netglass

A native macOS SwiftUI app for everyday network diagnostics. It is a calm control surface over tools you already have on `PATH` — ping, dig, traceroute, nmap, nc, and tcpdump — with live output, presets, and no cloud account.

Repository: [github.com/zachwilke/netglass](https://github.com/zachwilke/netglass)

Netglass does not bundle nmap or tcpdump. It discovers system and Homebrew binaries, runs them as subprocesses, and streams stdout/stderr into a console.

## Clone, open, run

```bash
git clone https://github.com/zachwilke/netglass.git
cd netglass
open Netglass.xcodeproj
```

Requirements: a Mac with **macOS 14 Sonoma** or later, **Xcode 16** or later.

1. Select the **Netglass** scheme and **My Mac**.
2. Let Xcode resolve the Sparkle 2 package the first time you open the project.
3. Signing: local Debug uses ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`). For your Apple ID, set a Development Team on the Netglass target.
4. Press Run (⌘R).

Command-line build:

```bash
xcodebuild -project Netglass.xcodeproj -scheme Netglass -configuration Debug build
```

The built app is under DerivedData:

`~/Library/Developer/Xcode/DerivedData/Netglass-*/Build/Products/Debug/Netglass.app`

This project can be authored on Linux, but it **must be compiled on a Mac**.

## Install the tools

| Panel      | Binary                            | Usually present | Homebrew            |
|------------|-----------------------------------|-----------------|---------------------|
| Ping       | `ping`, `ping6`                   | Yes             | —                   |
| Dig        | `dig`, fallback `host`/`nslookup` | Sometimes       | `brew install bind` |
| Traceroute | `traceroute`, `traceroute6`       | Yes             | —                   |
| Nmap       | `nmap`                            | No              | `brew install nmap` |
| Netcat     | `nc`                              | Yes             | —                   |
| Tcpdump    | `tcpdump`                         | Yes             | —                   |
| Whois      | `whois`                           | Yes             | `brew install whois` |
| Headers    | `curl`                            | Yes             | —                   |

Search order: system `/usr` and `/sbin` first for Apple tools; Homebrew first for nmap and dig; then extra Settings directories and sanitized `PATH`. Temporary and world-writable locations are skipped.

If a tool is missing, the panel says so and shows the brew formula. It never fails silently.

## Using it

- The sidebar picks a tool. The inspector is the form; the lower pane is a streaming console.
- **⌘R** runs, **⌘.** stops, **⌘K** clears output.
- Copy or save the log from the console. The argv preview is copyable.
- Nmap defaults are tame: host-up (`-sn`) or TCP connect (`-sT -T3`) on a short port list.

## Auto-updates (Sparkle 2)

Netglass is wired for Sparkle 2. The expected feed is:

`https://github.com/zachwilke/netglass/releases/latest/download/appcast.xml`

Automatic checks stay off until you generate an EdDSA key pair and paste the **public** key into `Netglass/Info.plist`. **Do not commit the private key.**

One-time setup and the archive → notarize → `sign_update` → GitHub Release workflow: [Docs/SPARKLE.md](Docs/SPARKLE.md). Example appcast: [Docs/appcast.example.xml](Docs/appcast.example.xml).

## Privileges and safety

No setuid helper, no password prompt in the app. tcpdump often needs [ChmodBPF](https://www.wireshark.org/) or a reviewed `sudo` in Terminal.

App Sandbox is **off** in the default entitlements so Homebrew nmap and BPF can work. Treat this as a local developer utility. See [Docs/SECURITY_AND_PERFORMANCE.md](Docs/SECURITY_AND_PERFORMANCE.md) for the security and performance review, residual risks, and Mac verification steps.

Tools launch with `Process.arguments` (argv only). Host, URL, port, filter, and extra nmap flags are validated. Secret curl headers and URL userinfo are refused. Netcat listen defaults to localhost.

## Tests

```bash
xcrun swift test
```

## Layout

```
Config/                 entitlements
Docs/                   architecture, Sparkle, security review, marketing icon
Netglass.xcodeproj/
Netglass/               SwiftUI app (Sparkle lives here)
Tests/NetglassCoreTests
```
