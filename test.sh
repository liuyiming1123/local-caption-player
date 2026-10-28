#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
run_test() { local name="$1"; shift; swiftc -parse-as-library "Tests/${name}.swift" "$@" -o "$test_dir/$name"; "$test_dir/$name"; }
run_test caption_test Sources/CaptionFormatter.swift
run_test controls_test Sources/ControlsVisibilityPolicy.swift
run_test timeline_test Sources/SubtitleTimeline.swift
run_test timed_text_test Sources/TimedCueBuilder.swift Sources/SubtitleTimeline.swift
run_test transcript_test Sources/TranscriptStore.swift
swiftc -parse-as-library Tests/default_open_test.swift Sources/MediaOpenPolicy.swift -o "$test_dir/default_open_test"
"$test_dir/default_open_test" Resources/Info.plist
swiftc -parse-as-library Tests/platform_test.swift -o "$test_dir/platform_test"
"$test_dir/platform_test" Resources/Info.plist
