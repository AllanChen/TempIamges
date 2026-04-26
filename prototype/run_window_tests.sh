#!/bin/bash
set -e

PROTOTYPE_DIR="/Users/allan/Desktop/TempImages/prototype"
EVIDENCE_DIR="/Users/allan/Desktop/TempImages/.sisyphus/evidence"

test_app() {
    local app_name="$1"
    local evidence_file="$2"
    local setup_cmd="$3"
    local get_bounds_cmd="$4"
    
    echo "========================================" > "$evidence_file"
    echo "APP: $app_name" >> "$evidence_file"
    echo "DATE: $(date)" >> "$evidence_file"
    echo "" >> "$evidence_file"
    
    eval "$setup_cmd" >/dev/null 2>&1 || true
    sleep 3
    
    local bounds=$(eval "$get_bounds_cmd" 2>/dev/null || echo "")
    if [ -z "$bounds" ]; then
        echo "Could not get window bounds" >> "$evidence_file"
        echo "--- END ---" >> "$evidence_file"
        return
    fi
    
    echo "Window bounds: $bounds" >> "$evidence_file"
    
    local x=$(echo "$bounds" | awk '{print int($1 + ($3 - $1) / 2)}')
    local y=$(echo "$bounds" | awk '{print int($2 + ($4 - $2) / 2)}')
    echo "Mouse target: ($x, $y)" >> "$evidence_file"
    echo "" >> "$evidence_file"
    
    "$PROTOTYPE_DIR/movemouse" "$x" "$y"
    sleep 1
    
    "$PROTOTYPE_DIR/diagnose" >> "$evidence_file" 2>> "$evidence_file"
    
    echo "" >> "$evidence_file"
    echo "--- END ---" >> "$evidence_file"
}

test_app "Safari" "$EVIDENCE_DIR/task-0-safari-extraction.txt" \
    'osascript -e "tell application \"Safari\" to if not (exists window 1) then make new document" -e "tell application \"Safari\" to set URL of document 1 to \"https://example.com\""' \
    'osascript -e "tell application \"Safari\" to get bounds of window 1"'

test_app "Google Chrome" "$EVIDENCE_DIR/task-0-chrome-extraction.txt" \
    'osascript -e "tell application \"Google Chrome\" to if not (exists window 1) then make new window" -e "tell application \"Google Chrome\" to set URL of active tab of window 1 to \"https://example.com\""' \
    'osascript -e "tell application \"Google Chrome\" to get bounds of window 1"'

test_app "Visual Studio Code" "$EVIDENCE_DIR/task-0-vscode-extraction.txt" \
    'open -a "Visual Studio Code" /Users/allan/Desktop/TempImages/prototype/main.swift' \
    'osascript -e "tell application \"System Events\" to tell process \"Visual Studio Code\" to get position of window 1" -e "tell application \"System Events\" to tell process \"Visual Studio Code\" to get size of window 1" | tr "\n" " " | awk "{print \$1, \$2, \$1+\$3, \$2+\$4}"'

test_app "Finder" "$EVIDENCE_DIR/task-0-finder-extraction.txt" \
    'osascript -e "tell application \"Finder\" to open folder (path to home folder)"' \
    'osascript -e "tell application \"Finder\" to get bounds of window 1"'

test_app "Terminal" "$EVIDENCE_DIR/task-0-terminal-extraction.txt" \
    'osascript -e "tell application \"Terminal\" to do script \"echo hello world text extraction test\" in window 1"' \
    'osascript -e "tell application \"Terminal\" to get bounds of window 1"'

echo "All tests completed."
