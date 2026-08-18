# Nothung

**English** | [简体中文](README.zh-CN.md)

Nothung is a local-first iOS tool for cleaning shared links. It removes tracking parameters, rewrites links with configurable rules, and expands supported short links.

This project was inspired by the public features of the Android app [Tarnhelm](https://github.com/lz233/Tarnhelm), but its Swift code, interface, and icon are independent implementations. Nothung is not an official Tarnhelm port and is not affiliated with Tarnhelm.

## Three ways to use Nothung

### 1. Use “Copy with Nothung”

Open the Share Sheet for a link in Safari or another app, then choose **Copy with Nothung** (`使用 Nothung 复制`). Nothung cleans the shared content and writes the result to the system clipboard. You can finish immediately or share the cleaned result again.

<p align="center">
  <img src="docs/screenshots/use-nothung-copy.png" alt="Copy with Nothung from the iOS Share Sheet" width="360">
</p>

### 2. Copy elsewhere, then paste with the Nothung keyboard

Copy a link in another app, switch to the Nothung keyboard, and tap its paste key. Nothung cleans the current clipboard and inserts the result into the active text field. While the keyboard is visible and Full Access is enabled, new clipboard content is also cleaned and added to the recent list automatically.

<p align="center">
  <img src="docs/screenshots/keyboard-paste.png" alt="Clean and paste with the Nothung keyboard" width="360">
</p>

### 3. Paste into Nothung and clean

Open the main app, paste a URL or text containing a link, and tap **Clean Link**. Nothung shows the content before and after cleaning, along with removed fields and applied rules when relevant. The result can then be copied or shared.

<p align="center">
  <img src="docs/screenshots/app-cleaning.png" alt="Paste and clean a link in the Nothung app" width="360">
</p>

## Other features

- Custom query-parameter, regular-expression, and redirect rules
- Shortcuts support with URL input and URL output
- Built-in cleanup for common tracking parameters and shared links from X/Twitter and Bilibili
- Built-in expansion for `b23.tv`
- Recent cleaned items in the Nothung keyboard: tap to insert, or long-press to view the original content
- Local parameter and regular-expression processing; no ads or analytics SDKs
- Clipboard monitoring only while the Nothung keyboard is visible and Full Access is enabled, never in the background

Nothung requires iOS 17 or later.

## Build

```sh
open iOS/Nothung.xcodeproj
```

Select the `Nothung` scheme and your own development team in Xcode. Other developers may need to replace the `dev.nothung.*` bundle identifiers and the `group.dev.nothung.shared` App Group before running on a physical device.

The Xcode project is generated with XcodeGen 2.46.0. After editing `iOS/project.yml`, run:

```sh
xcodegen generate --spec iOS/project.yml
```

Core tests:

```sh
cd Packages/NothungCore
swift test
```

The current baseline is Xcode 26.6 with the iOS 26.5 SDK. The project has 45 passing core tests plus 40 iOS integration and security tests.

## Rules and licensing

Nothung does not include Tarnhelm’s complete rule library by default. An optional converted rule pack is available in [`RulePacks/Tarnhelm-GPL-3.0`](RulePacks/Tarnhelm-GPL-3.0). It is converted from the [TarnhelmDocument](https://github.com/lz233/TarnhelmDocument) rules, distributed separately under GPL-3.0-only, and imported manually by the user.

Nothung’s own code is currently not offered under an open-source license; all rights are reserved by default. See [License and source notices](LICENSES.md) and the [Privacy Policy](PRIVACY.md).
