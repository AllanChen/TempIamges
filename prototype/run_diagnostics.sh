#!/bin/bash
set -e

PROTOTYPE_DIR="/Users/allan/Desktop/TempImages/prototype"
EVIDENCE_DIR="/Users/allan/Desktop/TempImages/.sisyphus/evidence"
SCREEN_W=1470
SCREEN_H=956

run_diagnostic() {
    local app_name="$1"
    local app_path="$2"
    local mouse_x="$3"
    local mouse_y="$4"
    local evidence_file="$5"
    
    echo "========================================" > "$evidence_file"
    echo "APP: $app_name" >> "$evidence_file"
    echo "DATE: $(date)" >> "$evidence_file"
    echo "MOUSE: ($mouse_x, $mouse_y)" >> "$evidence_file"
    echo "" >> "$evidence_file"
    
    if [ -n "$app_path" ]; then
        open "$app_path" 2>/dev/null || true
    fi
    
    osascript -e "tell application \"$app_name\" to activate" 2>/dev/null || true
    sleep 2
    
    "$PROTOTYPE_DIR/movemouse" "$mouse_x" "$mouse_y"
    sleep 1
    
    "$PROTOTYPE_DIR/diagnose" >> "$evidence_file" 2>> "$evidence_file"
    
    echo "" >> "$evidence_file"
    echo "--- END ---" >> "$evidence_file"
    echo "" >> "$evidence_file"
}

run_diagnostic "Safari" "" $((SCREEN_W/2)) $((SCREEN_H/2-50)) "$EVIDENCE_DIR/task-0-safari-extraction.txt"
run_diagnostic "Google Chrome" "" $((SCREEN_W/2)) $((SCREEN_H/2-50)) "$EVIDENCE_DIR/task-0-chrome-extraction.txt"
run_diagnostic "Visual Studio Code" "/Applications/Visual Studio Code.app" $((SCREEN_W/2)) $((SCREEN_H/2)) "$EVIDENCE_DIR/task-0-vscode-extraction.txt"
run_diagnostic "Finder" "" $((SCREEN_W/2)) $((SCREEN_H/2-100)) "$EVIDENCE_DIR/task-0-finder-extraction.txt"
run_diagnostic "Terminal" "/System/Applications/Utilities/Terminal.app" $((SCREEN_W/2)) $((SCREEN_H/2)) "$EVIDENCE_DIR/task-0-terminal-extraction.txt"

echo "All diagnostics completed."
