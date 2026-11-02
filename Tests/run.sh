#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/mvdh-tests.XXXXXX)
trap 'rm -rf "$test_dir"' EXIT
sources=Sources/MacVirtualDesktopHelper
if xcrun -f swiftc >/dev/null 2>&1; then
	SWIFTC=(xcrun swiftc)
else
	SWIFTC=(/Library/Developer/CommandLineTools/usr/bin/swiftc)
fi
"${SWIFTC[@]}" Sources/MacVirtualDesktopHelper/Localization.swift -target arm64-apple-macos13.0 "$sources/RuleStore.swift" "$sources/DesktopRuleMatcher.swift" "$sources/ConfigurationBackup.swift" Tests/RuleStoreTests.swift -o "$test_dir/rules"
"$test_dir/rules"
"${SWIFTC[@]}" Sources/MacVirtualDesktopHelper/Localization.swift -target arm64-apple-macos13.0 "$sources/RuleStore.swift" "$sources/SnapshotScheduler.swift" Tests/SnapshotSchedulerTests.swift -o "$test_dir/scheduler"
"$test_dir/scheduler"
"${SWIFTC[@]}" Sources/MacVirtualDesktopHelper/Localization.swift -target arm64-apple-macos13.0 "$sources/RuleStore.swift" "$sources/GlobalHotKeys.swift" Tests/GlobalHotKeyTests.swift -o "$test_dir/hotkeys"
"$test_dir/hotkeys"
"${SWIFTC[@]}" Sources/MacVirtualDesktopHelper/Localization.swift -target arm64-apple-macos13.0 "$sources/RuleStore.swift" "$sources/Models.swift" "$sources/DesktopOverlay.swift" Tests/DesktopOverlayTests.swift -o "$test_dir/overlay"
"$test_dir/overlay"
"${SWIFTC[@]}" Sources/MacVirtualDesktopHelper/Localization.swift -target arm64-apple-macos13.0 "$sources/RuleStore.swift" "$sources/Models.swift" Tests/WindowSnapshotTests.swift -o "$test_dir/snapshot"
"$test_dir/snapshot"
"${SWIFTC[@]}" Sources/MacVirtualDesktopHelper/Localization.swift -target arm64-apple-macos13.0 "$sources/Models.swift" "$sources/CompactStatusView.swift" Tests/CompactStatusViewTests.swift -o "$test_dir/status-view"
"$test_dir/status-view"
"${SWIFTC[@]}" Sources/MacVirtualDesktopHelper/Localization.swift -target arm64-apple-macos13.0 "$sources/RuleStore.swift" "$sources/HotKeyText.swift" Tests/HotKeyTextTests.swift -o "$test_dir/hotkey-text"
"$test_dir/hotkey-text"
"${SWIFTC[@]}" Sources/MacVirtualDesktopHelper/Localization.swift -target arm64-apple-macos13.0 "$sources/Models.swift" "$sources/WindowReview.swift" Tests/WindowReviewTests.swift -o "$test_dir/window-review"
"$test_dir/window-review"
"${SWIFTC[@]}" Sources/MacVirtualDesktopHelper/Localization.swift -target arm64-apple-macos13.0 "$sources/RuleStore.swift" "$sources/Models.swift" "$sources/DesktopRuleMatcher.swift" "$sources/RuleEditor.swift" Tests/RuleEditorTests.swift -o "$test_dir/rule-editor"
"$test_dir/rule-editor"
"${SWIFTC[@]}" Sources/MacVirtualDesktopHelper/Localization.swift -target arm64-apple-macos13.0 "$sources/Models.swift" "$sources/DesktopCardView.swift" Tests/WindowListKeyboardTests.swift -o "$test_dir/list-keyboard"
"$test_dir/list-keyboard"
"${SWIFTC[@]}" Sources/MacVirtualDesktopHelper/Localization.swift -target arm64-apple-macos13.0 "$sources/RuleStore.swift" "$sources/Models.swift" "$sources/WindowSwitcherSession.swift" Tests/WindowSwitcherTests.swift -o "$test_dir/window-switcher"
"$test_dir/window-switcher"
