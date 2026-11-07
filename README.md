# Filetor

A fast, native dual-pane file manager for macOS, written in Swift and SwiftUI.

Filetor is built for moving files around: two panes side by side, a flat and
quiet interface, and a toolbar you can shape to your own workflow.

## Features

- Dual-pane browsing with tabs in each pane
- List, icon and column views
- Drag and drop between panes, the sidebar and the Drop Stack (copy by default, hold Command to move)
- Copy and move with a progress indicator and conflict handling
- Batch rename with live preview (replace text, add text, numbering)
- Quick Look on the space bar, copy and paste of files, rename with Return
- Info panel with details and preview
- Favorites you can reorder by dragging, mounted disks with eject
- Network servers (SMB and AFP) found automatically under Shared, plus Connect to Server for any address
- AirDrop from the toolbar
- Customizable toolbar, accent colour, text size, light and dark appearance

## Requirements

- macOS 14 or newer

## Install

1. Download the latest `Filetor.zip` from [Releases](https://github.com/davidpraznik/Filetor/releases).
2. Unzip it and move Filetor to Applications.
3. Filetor is not signed with a paid Apple Developer account, so macOS will warn you on first launch. Right-click the app, choose Open, then Open again. You only need to do this once.

## Build from source

1. Open `Filetor.xcodeproj` in Xcode 26 or newer.
2. Select the Filetor scheme and press Run.

## Safety

Filetor moves and renames real files. It is early software (version 0.1.0).
Try it on a test folder first and keep backups of anything important.

## License

MIT, see [LICENSE](LICENSE).

Copyright (c) 2026 David Praznik
