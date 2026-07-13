#!/bin/bash
#
# GitHub Projects V2 Integration Script
# Purpose: Automatically manage GitHub Projects status for Issues
# Design: Zero-config, auto-detection, graceful degradation
#

set -euo pipefail

# ========================================
# Global Variables (Session State)
# ========================================

PROJECT_ID=""
PROJECT_NUMBER=""
STATUS_FIELD_ID=""
TODO_OPTION_ID=""
IN_PROGRESS_OPTION_ID=""
DONE_OPTION_ID=""

# Date field IDs
CREATED_FIELD_ID=""
START_FIELD_ID=""
COMPLETED_FIELD_ID=""

# Cache detection results for session
DETECTION_DONE=false
DATE_FIELDS_DETECTED=false

# ========================================
# Utility Functions
# ========================================

log_info() {
    echo "ℹ️  $*" >&2
}

log_success() {
    echo "✅ $*" >&2
}

log_warn() {
    echo "⚠️  $*" >&2
}

log_error() {
    echo "❌ $*" >&2
}

# Check if gh CLI is available
check_gh_cli() {
    if ! command -v gh &> /dev/null; then
        log_error "GitHub CLI (gh) not found. Please install it first."
        log_info "Install: https://cli.github.com/"
        return 1
    fi
    return 0
}

# Get repository owner and name
get_repo_info() {
    local owner name
    owner=$(gh repo view --json owner -q '.owner.login' 2>/dev/null || echo "")
    name=$(gh repo view --json name -q '.name' 2>/dev/null || echo "")

    if [[ -z "$owner" || -z "$name" ]]; then
        log_error "Failed to get repository info. Are you in a git repository?"
        return 1
    fi

    echo "$owner/$name"
}

# ========================================
# Project Detection
# ========================================

# Detect GitHub Project linked to this repository
detect_project() {
    if [[ "$DETECTION_DONE" == "true" ]]; then
        return 0
    fi

    log_info "Detecting GitHub Project..."

    local repo_info
    repo_info=$(get_repo_info) || return 1

    local owner="${repo_info%/*}"
    local repo="${repo_info#*/}"

    # GraphQL query to find project linked to this repository
    local query='
    query($owner: String!, $repo: String!) {
      repository(owner: $owner, name: $repo) {
        projectsV2(first: 1, orderBy: {field: CREATED_AT, direction: DESC}) {
          nodes {
            id
            number
            title
          }
        }
      }
    }'

    local result
    result=$(gh api graphql \
        -f query="$query" \
        -f owner="$owner" \
        -f repo="$repo" 2>/dev/null || echo "")

    if [[ -z "$result" ]]; then
        log_warn "Failed to query GitHub Projects API"
        return 1
    fi

    PROJECT_ID=$(echo "$result" | jq -r '.data.repository.projectsV2.nodes[0].id // empty')
    PROJECT_NUMBER=$(echo "$result" | jq -r '.data.repository.projectsV2.nodes[0].number // empty')

    if [[ -z "$PROJECT_ID" || -z "$PROJECT_NUMBER" ]]; then
        log_warn "No GitHub Project found for repository $repo_info"
        log_info "Creating a new project..."
        create_default_project "$owner" "$repo" || return 1
    else
        local project_title
        project_title=$(echo "$result" | jq -r '.data.repository.projectsV2.nodes[0].title')
        log_success "Found project: $project_title (#$PROJECT_NUMBER)"
    fi

    # Detect status field
    detect_status_field || return 1

    DETECTION_DONE=true
    return 0
}

# Create default project if none exists
create_default_project() {
    local owner="$1"
    local repo="$2"

    log_info "Creating default GitHub Project..."

    # Get owner's node ID (try user first, then organization)
    local owner_query='
    query($login: String!) {
      user(login: $login) {
        id
      }
    }'

    local owner_result
    owner_result=$(gh api graphql -f query="$owner_query" -f login="$owner" 2>/dev/null || echo "")

    local owner_id
    owner_id=$(echo "$owner_result" | jq -r '.data.user.id // empty')

    # If user query failed, try organization (requires read:org scope)
    if [[ -z "$owner_id" ]]; then
        local org_query='
        query($login: String!) {
          organization(login: $login) {
            id
          }
        }'
        owner_result=$(gh api graphql -f query="$org_query" -f login="$owner" 2>/dev/null || echo "")
        owner_id=$(echo "$owner_result" | jq -r '.data.organization.id // empty')
    fi

    if [[ -z "$owner_id" ]]; then
        log_error "Failed to get owner ID for $owner"
        return 1
    fi

    # Create project
    local create_mutation='
    mutation($ownerId: ID!, $title: String!) {
      createProjectV2(input: {ownerId: $ownerId, title: $title}) {
        projectV2 {
          id
          number
          title
        }
      }
    }'

    local project_title="${repo} Issues"
    local create_result
    create_result=$(gh api graphql \
        -f query="$create_mutation" \
        -f ownerId="$owner_id" \
        -f title="$project_title" 2>/dev/null || echo "")

    PROJECT_ID=$(echo "$create_result" | jq -r '.data.createProjectV2.projectV2.id // empty')
    PROJECT_NUMBER=$(echo "$create_result" | jq -r '.data.createProjectV2.projectV2.number // empty')

    if [[ -z "$PROJECT_ID" || -z "$PROJECT_NUMBER" ]]; then
        log_error "Failed to create project"
        return 1
    fi

    log_success "Created project: $project_title (#$PROJECT_NUMBER)"

    # Link project to repository (optional, best effort)
    link_project_to_repo "$owner" "$repo" || log_warn "Could not link project to repository (continuing anyway)"

    return 0
}

# Link project to repository
link_project_to_repo() {
    local owner="$1"
    local repo="$2"

    # Get repository node ID
    local repo_query='
    query($owner: String!, $name: String!) {
      repository(owner: $owner, name: $name) {
        id
      }
    }'

    local repo_result
    repo_result=$(gh api graphql \
        -f query="$repo_query" \
        -f owner="$owner" \
        -f name="$repo" 2>/dev/null || echo "")

    local repo_id
    repo_id=$(echo "$repo_result" | jq -r '.data.repository.id // empty')

    if [[ -z "$repo_id" ]]; then
        return 1
    fi

    # Link mutation
    local link_mutation='
    mutation($projectId: ID!, $repositoryId: ID!) {
      linkProjectV2ToRepository(input: {projectId: $projectId, repositoryId: $repositoryId}) {
        repository {
          id
        }
      }
    }'

    gh api graphql \
        -f query="$link_mutation" \
        -f projectId="$PROJECT_ID" \
        -f repositoryId="$repo_id" &>/dev/null || return 1

    return 0
}

# ========================================
# Status Field Detection
# ========================================

# Detect Status field and option IDs
detect_status_field() {
    log_info "Detecting Status field..."

    # Query project fields
    local fields_query='
    query($projectId: ID!) {
      node(id: $projectId) {
        ... on ProjectV2 {
          fields(first: 20) {
            nodes {
              ... on ProjectV2SingleSelectField {
                id
                name
                options {
                  id
                  name
                }
              }
            }
          }
        }
      }
    }'

    local fields_result
    fields_result=$(gh api graphql \
        -f query="$fields_query" \
        -f projectId="$PROJECT_ID" 2>/dev/null || echo "")

    if [[ -z "$fields_result" ]]; then
        log_error "Failed to query project fields"
        return 1
    fi

    # Find Status field (case-insensitive, multi-language support)
    local status_field
    status_field=$(echo "$fields_result" | jq -c '
        .data.node.fields.nodes[] |
        select(.name != null) |
        select(.name | test("status|ステータス|状態"; "i"))
    ' 2>/dev/null | head -n1)

    if [[ -z "$status_field" ]]; then
        log_warn "No Status field found in project"
        log_info "Please create a Status field manually in GitHub Projects"
        return 1
    fi

    STATUS_FIELD_ID=$(echo "$status_field" | jq -r '.id')

    # Map status options using flexible regex patterns
    TODO_OPTION_ID=$(echo "$status_field" | jq -r '
        .options[]? |
        select(.name | test("todo|未着手|バックログ|backlog"; "i")) |
        .id
    ' 2>/dev/null | head -n1)

    IN_PROGRESS_OPTION_ID=$(echo "$status_field" | jq -r '
        .options[]? |
        select(.name | test("progress|進行中|作業中|doing|in progress"; "i")) |
        .id
    ' 2>/dev/null | head -n1)

    DONE_OPTION_ID=$(echo "$status_field" | jq -r '
        .options[]? |
        select(.name | test("done|完了|終了|finished|closed"; "i")) |
        .id
    ' 2>/dev/null | head -n1)

    # Check if all required options were found
    local missing=()
    [[ -z "$TODO_OPTION_ID" ]] && missing+=("Todo")
    [[ -z "$IN_PROGRESS_OPTION_ID" ]] && missing+=("In Progress")
    [[ -z "$DONE_OPTION_ID" ]] && missing+=("Done")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "Missing status options: ${missing[*]}"
        log_info "Please ensure your Status field has: Todo, In Progress, Done options"
        return 1
    fi

    log_success "Status field detected with all options"
    return 0
}

# Detect date fields in project
detect_date_fields() {
    if [[ "$DATE_FIELDS_DETECTED" == "true" ]]; then
        return 0
    fi

    log_info "Detecting date fields..."

    # Query project fields
    local fields_query='
    query($projectId: ID!) {
      node(id: $projectId) {
        ... on ProjectV2 {
          fields(first: 20) {
            nodes {
              ... on ProjectV2Field {
                id
                name
                dataType
              }
            }
          }
        }
      }
    }'

    local fields_result
    fields_result=$(gh api graphql -f query="$fields_query" -f projectId="$PROJECT_ID" 2>/dev/null || echo "")

    if [[ -z "$fields_result" ]]; then
        log_warn "Failed to query date fields"
        return 1
    fi

    # Extract DATE type fields
    # Note: "Created" alone is reserved, use "Created at" or "Creation date"
    CREATED_FIELD_ID=$(echo "$fields_result" | jq -r '
        .data.node.fields.nodes[] |
        select(.dataType == "DATE" and (.name | test("creation|created at|作成日"; "i"))) |
        .id
    ' 2>/dev/null | head -n1)

    START_FIELD_ID=$(echo "$fields_result" | jq -r '
        .data.node.fields.nodes[] |
        select(.dataType == "DATE" and (.name | test("start|開始"; "i"))) |
        .id
    ' 2>/dev/null | head -n1)

    COMPLETED_FIELD_ID=$(echo "$fields_result" | jq -r '
        .data.node.fields.nodes[] |
        select(.dataType == "DATE" and (.name | test("complet|終了|完了|done"; "i"))) |
        .id
    ' 2>/dev/null | head -n1)

    # Check if at least one date field exists
    if [[ -n "$CREATED_FIELD_ID" ]] || [[ -n "$START_FIELD_ID" ]] || [[ -n "$COMPLETED_FIELD_ID" ]]; then
        DATE_FIELDS_DETECTED=true
        log_success "Date fields detected (Created: ${CREATED_FIELD_ID:0:8}..., Start: ${START_FIELD_ID:0:8}..., Completed: ${COMPLETED_FIELD_ID:0:8}...)"
        return 0
    else
        log_warn "No date fields found in project. Roadmap view requires date fields."
        log_info "Create date fields in GitHub Projects UI:"
        log_info "  - 'Created at' or 'Creation date' (Date type)"
        log_info "  - 'Start date' (Date type)"
        log_info "  - 'Completed' or 'Completion date' (Date type)"
        DATE_FIELDS_DETECTED=false
        return 1
    fi
}

# ========================================
# Issue Operations
# ========================================

# Add issue to project
add_issue_to_project() {
    local issue_number="$1"

    # Get issue URL
    local issue_url
    issue_url=$(gh issue view "$issue_number" --json url -q '.url' 2>/dev/null || echo "")

    if [[ -z "$issue_url" ]]; then
        log_error "Failed to get URL for issue #$issue_number"
        return 1
    fi

    log_info "Adding issue #$issue_number to project..."

    # Add item mutation
    local add_mutation='
    mutation($projectId: ID!, $contentId: ID!) {
      addProjectV2ItemById(input: {projectId: $projectId, contentId: $contentId}) {
        item {
          id
        }
      }
    }'

    # Get issue node ID
    local issue_id
    issue_id=$(gh issue view "$issue_number" --json id -q '.id' 2>/dev/null || echo "")

    if [[ -z "$issue_id" ]]; then
        log_error "Failed to get node ID for issue #$issue_number"
        return 1
    fi

    local add_result
    add_result=$(gh api graphql \
        -f query="$add_mutation" \
        -f projectId="$PROJECT_ID" \
        -f contentId="$issue_id" 2>/dev/null || echo "")

    if [[ -z "$add_result" ]] || ! echo "$add_result" | jq -e '.data.addProjectV2ItemById.item.id' &>/dev/null; then
        # Check if already added
        if echo "$add_result" | grep -q "already exists"; then
            log_info "Issue already in project"
            return 0
        fi
        log_error "Failed to add issue to project"
        return 1
    fi

    log_success "Added issue #$issue_number to project"
    return 0
}

# Get project item ID for an issue
get_project_item_id() {
    local issue_number="$1"

    # Get issue node ID
    local issue_id
    issue_id=$(gh issue view "$issue_number" --json id -q '.id' 2>/dev/null || echo "")

    if [[ -z "$issue_id" ]]; then
        return 1
    fi

    # Query to find item
    local item_query='
    query($projectId: ID!) {
      node(id: $projectId) {
        ... on ProjectV2 {
          items(first: 100) {
            nodes {
              id
              content {
                ... on Issue {
                  id
                  number
                }
              }
            }
          }
        }
      }
    }'

    local items_result
    items_result=$(gh api graphql \
        -f query="$item_query" \
        -f projectId="$PROJECT_ID" 2>/dev/null || echo "")

    local item_id
    item_id=$(echo "$items_result" | jq -r "
        .data.node.items.nodes[] |
        select(.content.id == \"$issue_id\") |
        .id
    ")

    echo "$item_id"
}

# Update issue status in project
update_issue_status() {
    local issue_number="$1"
    local target_status="$2"  # "Todo"|"In Progress"|"Done"

    log_info "Updating issue #$issue_number status to $target_status..."

    # Get project item ID
    local item_id
    item_id=$(get_project_item_id "$issue_number")

    if [[ -z "$item_id" ]]; then
        log_warn "Issue not in project, adding it first..."
        add_issue_to_project "$issue_number" || return 1

        # Wait for GitHub API to propagate the change
        sleep 2

        item_id=$(get_project_item_id "$issue_number")

        if [[ -z "$item_id" ]]; then
            log_error "Failed to get project item ID"
            return 1
        fi
    fi

    # Resolve option ID
    local option_id
    case "$target_status" in
        "Todo")
            option_id="$TODO_OPTION_ID"
            ;;
        "In Progress")
            option_id="$IN_PROGRESS_OPTION_ID"
            ;;
        "Done")
            option_id="$DONE_OPTION_ID"
            ;;
        *)
            log_error "Invalid status: $target_status"
            return 1
            ;;
    esac

    if [[ -z "$option_id" ]]; then
        log_error "No option ID for status: $target_status"
        return 1
    fi

    # Update status using gh CLI
    local update_result
    update_result=$(gh project item-edit "$PROJECT_NUMBER" \
        --id "$item_id" \
        --project-id "$PROJECT_ID" \
        --field-id "$STATUS_FIELD_ID" \
        --single-select-option-id "$option_id" \
        --format json 2>&1)

    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_error "Failed to update status: $update_result"
        return 1
    fi

    log_success "Updated status to $target_status"
    return 0
}

# ========================================
# Date Field Management
# ========================================

# Update date field value
update_date_field() {
    local item_id="$1"
    local field_id="$2"
    local date_value="$3"  # YYYY-MM-DD format

    if [[ -z "$field_id" ]]; then
        # Field not configured, skip silently
        return 0
    fi

    # GraphQL mutation to update date field
    local mutation='
    mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!, $date: Date!) {
      updateProjectV2ItemFieldValue(
        input: {
          projectId: $projectId
          itemId: $itemId
          fieldId: $fieldId
          value: { date: $date }
        }
      ) {
        projectV2Item {
          id
        }
      }
    }'

    local result
    result=$(gh api graphql \
        -f query="$mutation" \
        -f projectId="$PROJECT_ID" \
        -f itemId="$item_id" \
        -f fieldId="$field_id" \
        -f date="$date_value" 2>&1)

    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_warn "Failed to update date field: $result"
        return 1
    fi

    return 0
}

# Get current date field value
get_date_field_value() {
    local item_id="$1"
    local field_id="$2"

    if [[ -z "$field_id" ]]; then
        echo ""
        return 0
    fi

    local query='
    query($itemId: ID!) {
      node(id: $itemId) {
        ... on ProjectV2Item {
          fieldValueByName(name: "dummy") {
            ... on ProjectV2ItemFieldDateValue {
              date
            }
          }
        }
      }
    }'

    # Note: This query approach doesn't work well for generic field lookup
    # We'll use a simpler approach: always update if field exists
    echo ""
    return 0
}

# Set Created date (Issue creation time)
set_created_date() {
    local issue_number="$1"

    # Only proceed if Created field is configured
    if [[ -z "$CREATED_FIELD_ID" ]]; then
        return 0
    fi

    # Get project item ID
    local item_id
    item_id=$(get_project_item_id "$issue_number")

    if [[ -z "$item_id" ]]; then
        log_warn "Cannot set Created date: Issue not in project"
        return 1
    fi

    # Get Issue creation date
    local created_at
    created_at=$(gh issue view "$issue_number" --json createdAt -q '.createdAt' 2>/dev/null | cut -d'T' -f1)

    if [[ -z "$created_at" ]]; then
        log_warn "Cannot get Issue creation date"
        return 1
    fi

    update_date_field "$item_id" "$CREATED_FIELD_ID" "$created_at"
    log_info "Set Created date: $created_at"
    return 0
}

# Set Start date (when work begins)
set_start_date() {
    local issue_number="$1"
    local use_creation_date="${2:-false}"  # Optional: use Issue creation date as fallback

    # Only proceed if Start field is configured
    if [[ -z "$START_FIELD_ID" ]]; then
        return 0
    fi

    # Get project item ID
    local item_id
    item_id=$(get_project_item_id "$issue_number")

    if [[ -z "$item_id" ]]; then
        log_warn "Cannot set Start date: Issue not in project"
        return 1
    fi

    local start_date
    if [[ "$use_creation_date" == "true" ]]; then
        # Use Issue creation date (for backfilling closed issues)
        local created_at
        created_at=$(gh issue view "$issue_number" --json createdAt -q '.createdAt' 2>/dev/null | cut -d'T' -f1 || echo "")

        if [[ -n "$created_at" ]] && [[ "$created_at" != "null" ]]; then
            start_date="$created_at"
        else
            # Fallback to current date
            start_date=$(date +%Y-%m-%d)
        fi
    else
        # Use current date (normal In Progress flow)
        start_date=$(date +%Y-%m-%d)
    fi

    update_date_field "$item_id" "$START_FIELD_ID" "$start_date"
    log_info "Set Start date: $start_date"
    return 0
}

# Set Completed date (when Issue closes)
set_completed_date() {
    local issue_number="$1"

    # Only proceed if Completed field is configured
    if [[ -z "$COMPLETED_FIELD_ID" ]]; then
        return 0
    fi

    # Get project item ID
    local item_id
    item_id=$(get_project_item_id "$issue_number")

    if [[ -z "$item_id" ]]; then
        log_warn "Cannot set Completed date: Issue not in project"
        return 1
    fi

    # Get Issue state and closedAt
    local issue_info
    issue_info=$(gh issue view "$issue_number" --json state,closedAt 2>/dev/null || echo "")

    local completion_date
    if [[ -n "$issue_info" ]]; then
        local state
        local closed_at
        state=$(echo "$issue_info" | jq -r '.state' 2>/dev/null || echo "")
        closed_at=$(echo "$issue_info" | jq -r '.closedAt' 2>/dev/null | cut -d'T' -f1 || echo "")

        # If Issue is closed and has closedAt, use it
        if [[ "$state" == "CLOSED" ]] && [[ -n "$closed_at" ]] && [[ "$closed_at" != "null" ]]; then
            completion_date="$closed_at"
        else
            # Use current date as fallback (for Status:Done but Issue not closed)
            completion_date=$(date +%Y-%m-%d)
        fi
    else
        # Fallback to current date if Issue info can't be retrieved
        completion_date=$(date +%Y-%m-%d)
    fi

    update_date_field "$item_id" "$COMPLETED_FIELD_ID" "$completion_date"
    log_info "Set Completed date: $completion_date"
    return 0
}

# Clear date field (set to null/empty)
clear_date_field() {
    local item_id="$1"
    local field_id="$2"

    if [[ -z "$field_id" ]]; then
        # Field not configured, skip silently
        return 0
    fi

    # GraphQL mutation to clear date field
    local mutation='
    mutation($projectId: ID!, $itemId: ID!, $fieldId: ID!) {
      clearProjectV2ItemFieldValue(
        input: {
          projectId: $projectId
          itemId: $itemId
          fieldId: $fieldId
        }
      ) {
        projectV2Item {
          id
        }
      }
    }'

    local result
    result=$(gh api graphql \
        -f query="$mutation" \
        -f projectId="$PROJECT_ID" \
        -f itemId="$item_id" \
        -f fieldId="$field_id" 2>&1)

    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        log_warn "Failed to clear date field: $result"
        return 1
    fi

    return 0
}

# Clear Start date
clear_start_date() {
    local issue_number="$1"

    # Only proceed if Start field is configured
    if [[ -z "$START_FIELD_ID" ]]; then
        return 0
    fi

    # Get project item ID
    local item_id
    item_id=$(get_project_item_id "$issue_number")

    if [[ -z "$item_id" ]]; then
        log_warn "Cannot clear Start date: Issue not in project"
        return 1
    fi

    clear_date_field "$item_id" "$START_FIELD_ID"
    log_info "Cleared Start date"
    return 0
}

# Clear Completed date
clear_completed_date() {
    local issue_number="$1"

    # Only proceed if Completed field is configured
    if [[ -z "$COMPLETED_FIELD_ID" ]]; then
        return 0
    fi

    # Get project item ID
    local item_id
    item_id=$(get_project_item_id "$issue_number")

    if [[ -z "$item_id" ]]; then
        log_warn "Cannot clear Completed date: Issue not in project"
        return 1
    fi

    clear_date_field "$item_id" "$COMPLETED_FIELD_ID"
    log_info "Cleared Completed date"
    return 0
}

# ========================================
# Public API Functions
# ========================================

# Initialize GitHub Projects integration
# Returns 0 if successful, 1 if failed
gh_projects_init() {
    if [[ "$DETECTION_DONE" == "true" ]]; then
        return 0
    fi

    check_gh_cli || {
        log_error "GitHub CLI not available"
        return 1
    }

    detect_project || {
        log_error "Project detection failed"
        return 1
    }

    # Detect date fields (optional, won't fail if not found)
    detect_date_fields || true

    return 0
}

# Set issue status to "Todo"
gh_projects_set_todo() {
    local issue_number="$1"

    gh_projects_init || return 1

    update_issue_status "$issue_number" "Todo"

    # Set Created date if this is first time adding to project
    set_created_date "$issue_number" || true

    # Clear Start date and Completion date (Todo = not started)
    clear_start_date "$issue_number" || true
    clear_completed_date "$issue_number" || true
}

# Set issue status to "In Progress"
gh_projects_set_in_progress() {
    local issue_number="$1"

    gh_projects_init || return 1

    update_issue_status "$issue_number" "In Progress"

    # Set Start date when work begins
    set_start_date "$issue_number" || true

    # Clear Completion date (not yet completed)
    clear_completed_date "$issue_number" || true
}

# Set issue status to "Done"
gh_projects_set_done() {
    local issue_number="$1"

    gh_projects_init || return 1

    update_issue_status "$issue_number" "Done"

    # Set Completed date when closing
    set_completed_date "$issue_number" || true
}

# ========================================
# Main (for testing)
# ========================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Script is being run directly (for testing)

    if [[ $# -lt 2 ]]; then
        echo "Usage: $0 <issue_number> <status>"
        echo "  status: todo|in-progress|done"
        exit 1
    fi

    issue_number="$1"
    status="$2"

    case "$status" in
        todo)
            gh_projects_set_todo "$issue_number"
            ;;
        in-progress)
            gh_projects_set_in_progress "$issue_number"
            ;;
        done)
            gh_projects_set_done "$issue_number"
            ;;
        *)
            echo "Invalid status: $status"
            echo "Valid values: todo, in-progress, done"
            exit 1
            ;;
    esac
fi
