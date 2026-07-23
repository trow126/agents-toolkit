#!/usr/bin/env python3
"""
Issue Work Logger - Automatic TodoWrite State Logging

Monitors TodoWrite state changes and automatically logs:
- Task start (pending → in_progress)
- Task completion (in_progress → completed)
- Session start (first TodoWrite operation)
"""

import json
import sys
from datetime import datetime
from pathlib import Path
import os


class AutoLogger:
    def __init__(self):
        self.issue_number = os.environ.get('CURRENT_ISSUE_NUMBER')
        self.work_dir = Path(os.environ.get('WORK_DIR', Path.home() / 'claudedocs' / 'work'))
        self.session_dir = Path.home() / '.claude' / '.session'
        self.state_file = self.session_dir / 'todowrite_state.json'

        # Ensure directories exist
        self.session_dir.mkdir(parents=True, exist_ok=True)
        self.work_dir.mkdir(parents=True, exist_ok=True)

    def get_notes_file(self):
        """Get path to notes.md file for current Issue"""
        if not self.issue_number:
            raise ValueError("CURRENT_ISSUE_NUMBER environment variable not set")
        return self.work_dir / f"issue_{self.issue_number}_notes.md"

    def load_current_state(self):
        """Load current TodoWrite state from stdin"""
        try:
            stdin_data = sys.stdin.read().strip()
            if not stdin_data:
                return []
            return json.loads(stdin_data)
        except json.JSONDecodeError as e:
            print(f"Error: Invalid JSON input: {e}", file=sys.stderr)
            sys.exit(1)

    def load_previous_state(self):
        """Load previous TodoWrite state from session storage"""
        if not self.state_file.exists():
            return []

        try:
            with open(self.state_file, 'r') as f:
                return json.load(f)
        except json.JSONDecodeError:
            print(f"Warning: Could not parse previous state, treating as empty", file=sys.stderr)
            return []

    def save_state(self, state):
        """Save current state for next comparison"""
        with open(self.state_file, 'w') as f:
            json.dump(state, f, indent=2)

    def append_log(self, message):
        """Append message to notes.md file"""
        notes_file = self.get_notes_file()

        # Create file if it doesn't exist
        if not notes_file.exists():
            notes_file.write_text(f"# Issue #{self.issue_number}: Work Notes\n\n")

        # Append message
        with open(notes_file, 'a') as f:
            f.write(message + '\n')

        print(f"Logged to {notes_file}")

    def detect_changes(self, prev_state, curr_state):
        """Detect changes between previous and current TodoWrite states"""
        changes = {
            'session_start': len(prev_state) == 0 and len(curr_state) > 0,
            'task_started': [],
            'task_completed': []
        }

        # Build lookup by content for matching
        prev_by_content = {task.get('content'): task for task in prev_state}

        for curr_task in curr_state:
            content = curr_task.get('content')
            curr_status = curr_task.get('status')

            prev_task = prev_by_content.get(content)

            if prev_task:
                prev_status = prev_task.get('status')

                # Detect status changes
                if prev_status == 'pending' and curr_status == 'in_progress':
                    changes['task_started'].append(content)
                elif prev_status == 'in_progress' and curr_status == 'completed':
                    changes['task_completed'].append(content)

        return changes

    def log_changes(self, changes):
        """Log detected changes to notes.md"""
        timestamp = datetime.now().strftime('%Y-%m-%d %H:%M')

        if changes['session_start']:
            message = f"## [{timestamp}] Session started\n"
            if changes['task_started']:
                message += f"**Starting task**: {changes['task_started'][0]}\n"
            self.append_log(message)

        for task in changes['task_started']:
            if not changes['session_start']:  # Don't duplicate session start message
                message = f"## [{timestamp}] Task started\n**Task**: {task}\n"
                self.append_log(message)

        for task in changes['task_completed']:
            message = f"## [{timestamp}] Task completed\n**Task**: {task}\n"
            self.append_log(message)

    def run(self):
        """Main execution flow"""
        try:
            # Load states
            current_state = self.load_current_state()
            previous_state = self.load_previous_state()

            # Detect changes
            changes = self.detect_changes(previous_state, current_state)

            # Log changes
            has_changes = (
                changes['session_start'] or
                changes['task_started'] or
                changes['task_completed']
            )

            if has_changes:
                self.log_changes(changes)
                print(f"Changes detected and logged: {changes}")
            else:
                print("No changes detected")

            # Save current state
            self.save_state(current_state)

        except ValueError as e:
            print(f"Error: {e}", file=sys.stderr)
            sys.exit(1)
        except Exception as e:
            print(f"Unexpected error: {e}", file=sys.stderr)
            sys.exit(1)


if __name__ == '__main__':
    logger = AutoLogger()
    logger.run()
