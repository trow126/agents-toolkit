#!/bin/bash
# Integration test for auto_logger.py

set -e

echo "=== Testing auto_logger.py ==="
echo ""

# Setup
export CURRENT_ISSUE_NUMBER=999
export WORK_DIR=/tmp/test_work
mkdir -p $WORK_DIR
mkdir -p ~/.claude/.session

# Cleanup previous test state
rm -f ~/.claude/.session/todowrite_state.json
rm -f $WORK_DIR/issue_999_notes.md

echo "Test 1: Session start (empty → tasks)"
cat <<'JSON' | python3 auto_logger.py
[
  {"content": "Task 1: Analyze requirements", "status": "pending", "activeForm": "Analyzing requirements"},
  {"content": "Task 2: Implement feature", "status": "pending", "activeForm": "Implementing feature"}
]
JSON

echo "Expected: Session started log"
echo ""

echo "Test 2: Task start (pending → in_progress)"
cat <<'JSON' | python3 auto_logger.py
[
  {"content": "Task 1: Analyze requirements", "status": "in_progress", "activeForm": "Analyzing requirements"},
  {"content": "Task 2: Implement feature", "status": "pending", "activeForm": "Implementing feature"}
]
JSON

echo "Expected: Task started log"
echo ""

echo "Test 3: Task completion (in_progress → completed)"
cat <<'JSON' | python3 auto_logger.py
[
  {"content": "Task 1: Analyze requirements", "status": "completed", "activeForm": "Analyzing requirements"},
  {"content": "Task 2: Implement feature", "status": "pending", "activeForm": "Implementing feature"}
]
JSON

echo "Expected: Task completed log"
echo ""

echo "Test 4: Multiple changes"
cat <<'JSON' | python3 auto_logger.py
[
  {"content": "Task 1: Analyze requirements", "status": "completed", "activeForm": "Analyzing requirements"},
  {"content": "Task 2: Implement feature", "status": "completed", "activeForm": "Implementing feature"}
]
JSON

echo "Expected: Task completed log for Task 2"
echo ""

echo "=== Test Results ==="
echo "Notes file contents:"
cat $WORK_DIR/issue_999_notes.md
echo ""

echo "State file contents:"
cat ~/.claude/.session/todowrite_state.json
echo ""

echo "✅ All tests passed!"
