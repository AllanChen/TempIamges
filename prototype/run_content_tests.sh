#!/bin/bash
set -e

PROTOTYPE_DIR="/Users/allan/Desktop/TempImages/prototype"
EVIDENCE_DIR="/Users/allan/Desktop/TempImages/.sisyphus/evidence"

test_app() {
    local app_name="$1"
    local evidence_file="$2"
    local setup_cmd="$3"
    local mouse_x="$4"
    local mouse_y="$5"
    
    echo "========================================" > "$evidence_file"
    echo "APP: $app_name" >> "$evidence_file"
    echo "DATE: $(date)" >> "$evidence_file"
    echo "" >> "$evidence_file"
    
    eval "$setup_cmd" >/dev/null 2>&1 || true
    sleep 3
    
    "$PROTOTYPE_DIR/movemouse" "$mouse_x" "$mouse_y"
    sleep 1
    
    "$PROTOTYPE_DIR/diagnose" >> "$evidence_file" 2>> "$evidence_file"
    
    echo "" >> "$evidence_file"
    echo "--- END ---" >> "$evidence_file"
}

test_app "Safari" "$EVIDENCE_DIR/task-0-safari-extraction.txt" \
    'osascript -e "tell application \"Safari\" to set URL of front document to \"https://example.com\""' \
    700 400

test_app "Google Chrome" "$EVIDENCE_DIR/task-0-chrome-extraction.txt" \
    'osascript -e "tell application \"Google Chrome\" to set URL of active tab of front window to \"https://example.com\""' \
    700 400

test_app "Visual Studio Code" "$EVIDENCE_DIR/task-0-vscode-extraction.txt" \
    'open -a "Visual Studio Code" /Users/allan/Desktop/TempImages/prototype/main.swift' \
    700 450

test_app "Finder" "$EVIDENCE_DIR/task-0-finder-extraction.txt" \
    'osascript -e "tell application \"Finder\" to open folder (path to home folder)"' \
    700 400

test_app "Terminal" "$EVIDENCE_DIR/task-0-terminal-extraction.txt" \
    'osascript -e "tell application \"Terminal\" to do script \"echo hello world text extraction test\" in front window"' \
    700 450

echo "All tests completed."
