#!/bin/bash

LIST_FILE="$1"
VERSION_FILE="${2:-version.txt}"

# Check the usage of the script
if [ $# -eq 0 ]; then
    echo "사용법: $0 <list_file> [version_file]"
    echo "예시: $0 list.txt"
    echo "예시: $0 list.txt version.txt"
    exit 1
fi

if [ ! -f "$LIST_FILE" ]; then
    echo "Error: File '$LIST_FILE' does not exist."
    exit 1
fi

if [ ! -f "$VERSION_FILE" ]; then
    echo "Error: File '$VERSION_FILE' does not exist."
    exit 1
fi

MIGRATION_SCRIPT="$(dirname "$0")/migration_resources.sh"

if [ ! -f "$MIGRATION_SCRIPT" ]; then
    echo "Error: migration_resources.sh file does not exist in '$MIGRATION_SCRIPT'."
    exit 1
fi

# Provides colorize()/RED/GREEN/YELLOW/NC/IS_TTY for the status lines
# below. Sourced here (in this process) rather than relying on
# migration_resources.sh's copy, because IS_TTY must reflect *this*
# process's own stdout - migration_resources.sh is invoked below as
# `"$MIGRATION_SCRIPT" ... | while read line; do ... done`, so its
# stdout is always a pipe, even during an interactive batch run at a
# real terminal.
source "$(dirname "$0")/common/pretty-printer.sh"

# Check the execution permission of the script
if [ ! -x "$MIGRATION_SCRIPT" ]; then
    colorize "$YELLOW" "Warning: migration_resources.sh does not have execution permission. Granting execution permission."
    chmod +x "$MIGRATION_SCRIPT"
fi

# Root directory for all log output, referenced in the startup banner
# below. Other log paths in this script (mkdir -p logs, SUMMARY_LOG,
# per-project log/error files, aggregate_report.py's --logs-dir) keep
# using the literal "logs" directly rather than $LOG_DIR - this
# variable exists only so the banner doesn't print an empty value.
LOG_DIR="logs"

# Make logs directory
mkdir -p logs

# Per (project, version) verdict, one line per run, appended across
# batch invocations. aggregate_report.py reads this as the source of
# truth for success/failure instead of re-deriving it from raw logs.
# Columns: completed_at, project, version, exit_code, run_id, started_at
SUMMARY_LOG="logs/summary.tsv"

# Count non-empty (post-trim) lines in a file, using the exact same
# blank-line test the main loops below use ([[ -z "${line// }" ]]) so
# this count always matches the number of iterations the loops will
# actually perform.
count_valid_lines() {
    local file="$1"
    local count=0
    local line
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ -z "${line// }" ]]; then
            continue
        fi
        count=$((count + 1))
    done < "$file"
    echo "$count"
}

# Precompute the total number of (project, version) pairs so the
# progress percentage has a known denominator from the very first
# item, instead of only being derivable after the batch finishes.
project_count=$(count_valid_lines "$LIST_FILE")
version_count=$(count_valid_lines "$VERSION_FILE")
total_pairs=$((project_count * version_count))
# Defensive fallback: this should be unreachable in practice (the
# main loops below can only iterate if total_pairs > 0), but avoids a
# division by zero if that invariant is ever violated.
if [ "$total_pairs" -eq 0 ]; then
    total_pairs=1
fi

# Convert a whole number of seconds into a short Korean duration
# string for the ETA display.
format_duration() {
    local total_seconds=$1
    local hours=$((total_seconds / 3600))
    local minutes=$(((total_seconds % 3600) / 60))
    local seconds=$((total_seconds % 60))

    if [ "$hours" -gt 0 ]; then
        echo "${hours}시간 ${minutes}분"
    elif [ "$minutes" -gt 0 ]; then
        echo "${minutes}분 ${seconds}초"
    else
        echo "${seconds}초"
    fi
}

echo "=== Migration starts ==="
echo "Project file: $LIST_FILE"
echo "Version file: $VERSION_FILE"
echo "Log directory: $LOG_DIR"
echo "====================="

total_count=0
# Cumulative wall-clock time (seconds) spent on items completed so
# far in this run, and how many items that covers. Used to compute
# the average per-item time for the ETA estimate below.
total_elapsed=0
completed_items=0

while IFS= read -r project || [ -n "$project" ]; do
    if [[ -z "${project// }" ]]; then
        continue
    fi

    # Trim before creating the log directory - otherwise a leading/
    # trailing space in list.txt makes this word-split into the wrong
    # path, and every later log write for this project silently goes
    # missing (aggregate_report.py then can't classify its failures).
    project=$(echo "$project" | xargs)
    mkdir -p "logs/$project"

    # Generate timestamp for error log filename. Includes the date (not
    # just HH:MM:SS) since this value is also used as summary.tsv's
    # run_id, which aggregate_report.py relies on to find the exact
    # log file for a run - two runs of the same project at the same
    # wall-clock second on different days must not collide.
    TIMESTAMP=$(date +%Y%m%d%H%M%S)

    # Iterate over the versions
    while IFS= read -r version || [ -n "$version" ]; do
        # Skip empty lines or lines with only whitespace
        if [[ -z "${version// }" ]]; then
            continue
        fi
        
        # Remove leading and trailing whitespace
        version=$(echo "$version" | xargs)
        
        ((total_count++))

        percent=$((total_count * 100 / total_pairs))
        if [ "$completed_items" -gt 0 ]; then
            avg_seconds=$((total_elapsed / completed_items))
            remaining_items=$((total_pairs - total_count + 1))
            eta_seconds=$((avg_seconds * remaining_items))
            eta_display="예상 남은 시간: $(format_duration "$eta_seconds")"
        else
            # No item has finished yet in this run, so there's no
            # average processing time to base an estimate on.
            eta_display="예상 남은 시간: 계산 중..."
        fi
        echo "[$total_count/$total_pairs] (${percent}%) 처리 중: '$project' (버전: $version) ($eta_display)"
        # Tree root (phase 2): replaces the old "=== Project: X ==="
        # header - one root line per (project, version), closed below
        # once migration_exit_code is known.
        colorize "$YELLOW" "$project / $version  ⏳ 진행중"
        item_start_epoch=$(date +%s)

        # path for log files
        LOG_FILE="logs/$project/project.${TIMESTAMP}.log"
        ERROR_LOG="logs/$project/error.${TIMESTAMP}.log"

        # Recorded alongside the verdict below so aggregate_report.py
        # can tell which result.jsonl entries (timestamped by
        # weblate_utils.py's check_sentence_count/detail) were
        # actually produced by *this* run, instead of trusting stale
        # entries left over from an earlier run of the same
        # (project, version).
        run_started_at=$(date '+%Y-%m-%dT%H:%M:%S')

        # run migration.sh and save the log to the log file
        #
        # NOTE: We deliberately do not wrap this pipeline in an
        # `if ... ; then` check. The exit status of a pipeline is the
        # exit status of its *last* command (the `while` loop here),
        # which almost always exits 0 regardless of whether
        # MIGRATION_SCRIPT failed. PIPESTATUS[0] captures the actual
        # exit code of MIGRATION_SCRIPT, and must be read immediately
        # after the pipeline, before any other command runs.
        "$MIGRATION_SCRIPT" "$project" "$version" 2>&1 | while IFS= read -r line || [ -n "$line" ]; do
            # create_weblate_components.sh/test.sh/every other stage now
            # tag each line with one of two markers instead of always
            # being both logged and echoed the same way - see
            # TREE_MARKER/QUIET_MARKER in common/pretty-printer.sh for
            # the full protocol. Lines carrying neither marker (there
            # should be none left in normal operation - every stage now
            # routes through log_quiet()/run_tagged_quiet()/tree_line(),
            # or a still-visible fatal-error tagged_colorize()) fall
            # through to the phase-1 behavior unchanged: tagged, logged,
            # and echoed - a safety net, not the expected path.
            if [[ "$line" == "${TREE_MARKER}"* ]]; then
                tree_content="${line#$TREE_MARKER}"
                if [[ "$tree_content" == *"✗"* ]]; then
                    colorize "$RED" "$tree_content"
                elif [[ "$tree_content" == *"⏳"* ]]; then
                    colorize "$YELLOW" "$tree_content"
                elif [[ "$tree_content" == *"✓"* ]]; then
                    colorize "$GREEN" "$tree_content"
                else
                    # A plain informational line (e.g. the "다음 5단계
                    # 진행 예정: ..." roadmap) with no status symbol of
                    # its own - print as-is, neither red/yellow/green
                    # nor forced green by
                    # default like a real success line would be.
                    echo "$tree_content"
                fi
                continue
            fi
            if [[ "$line" == "${QUIET_MARKER}"* ]]; then
                line="${line#$QUIET_MARKER}"
                plain_line="$project | $version | $line"
                echo "$plain_line" >> "$LOG_FILE"
                if [[ "$line" == *" | [ERROR]"* ]]; then
                    echo "$plain_line" >> "$ERROR_LOG"
                fi
                continue
            fi

            plain_line="$project | $version | $line"
            # Log file writes must always stay plain text - never
            # colorize this, or error.*.log/project.*.log end up with
            # raw ANSI escape bytes in them, which breaks grep and the
            # README's `version | message` log format. (This replaces
            # the previous `tee -a "$LOG_FILE"`, which piped the same
            # string to both the file and stdout at once and so had no
            # way to make the two diverge.)
            echo "$plain_line" >> "$LOG_FILE"
            # migration_resources.sh's own [ERROR]/[Failed] lines
            # arrive here as plain text regardless of whether *it* was
            # run at a real terminal, because its stdout is always a
            # pipe in this context (see the IS_TTY comment on the
            # `source pretty-printer.sh` line above) - so it's safe to
            # colorize purely by matching the tag text. Since phase-1
            # log tagging, every line from migration_resources.sh's
            # log()/colorize()/run_tagged() (common/pretty-printer.sh)
            # is prefixed "component | locale | ", so the [ERROR]/
            # [Failed] tag itself no longer starts the line - match it
            # right after that prefix's trailing " | " instead of
            # anchoring at the start of the line.
            if [[ "$line" == *" | [ERROR]"* || "$line" == *" | [Failed]"* ]]; then
                colorize "$RED" "$plain_line"
            else
                echo "$plain_line"
            fi
            # save the error line to the error log file
            if [[ "$line" == *" | [ERROR]"* ]]; then
                echo "$plain_line" >> "$ERROR_LOG"
            fi
        done
        migration_exit_code=${PIPESTATUS[0]}

        # Tree root, closed (phase 2) - replaces the old bare Success/
        # Failed summary line. Kept as its own colorize() call (not a
        # QUIET_MARKER/TREE_MARKER line from the child) since it's
        # this process's own project/version-level verdict, derived
        # from $migration_exit_code which only this process has.
        if [ "$migration_exit_code" -eq 0 ]; then
            colorize "$GREEN" "$project / $version  ✓ SUCCESS"
        else
            colorize "$RED" "$project / $version  ✗ FAILED (exit code: $migration_exit_code)"
        fi
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
            "$(date '+%Y-%m-%dT%H:%M:%S')" "$project" "$version" \
            "$migration_exit_code" "$TIMESTAMP" "$run_started_at" \
            >> "$SUMMARY_LOG"
        sleep 15

        # Roll this item's wall-clock time (migration run + the fixed
        # sleep above, since every remaining item pays that same cost)
        # into the running average used for the next item's ETA.
        item_end_epoch=$(date +%s)
        total_elapsed=$((total_elapsed + item_end_epoch - item_start_epoch))
        completed_items=$((completed_items + 1))

        echo "---"
    done < "$VERSION_FILE"
    
done < "$LIST_FILE"

echo "====================="
echo "=== Migration completed ==="

# Print the project x version x component x locale status table and
# save the same content to report.md, so a person doesn't have to
# open every logs/<project>/error.*.log by hand to see what happened.
# Both outputs come from aggregate_report.py's build_report() rows -
# --format table (stdout) and --report-md (file) render the exact
# same rows, so they can't disagree with each other.
#
# Workspace root must match the one migration_resources.sh actually
# wrote result.jsonl into. This script never passes a third
# (workspace_name) argument to migration_resources.sh, so that script
# always uses its own default, "workspace" (see migration_resources.sh
# WORKSPACE_NAME and README.rst's "Workspace Structure" section) -
# i.e. $HOME/workspace, not "$LOG_DIR" or any other variable name that
# might suggest otherwise.
REPORT_WORKSPACE="$HOME/workspace"

# aggregate_report.py imports common/weblate_utils.py, which imports
# polib/requests at module load time. Prefer the migration venv
# (README.rst: "<workspace>/.venv/: Python virtual environment
# containing migration dependencies") if it exists, and only fall
# back to the bare `python3` on PATH otherwise.
REPORT_PYTHON="$REPORT_WORKSPACE/.venv/bin/python3"
if [ ! -x "$REPORT_PYTHON" ]; then
    REPORT_PYTHON="python3"
fi

echo ""
echo "=== Migration Report ==="
if ! "$REPORT_PYTHON" "$(dirname "$0")/aggregate_report.py" \
        --logs-dir logs --workspace "$REPORT_WORKSPACE" \
        --format table --report-md report.md; then
    # Report generation is a convenience on top of the batch run, not
    # part of it - a failure here (e.g. missing polib/requests, an
    # unreadable log) must not be mistaken for the migrations
    # themselves having failed, and must not change this script's own
    # exit status.
    colorize "$YELLOW" "Warning: Failed to generate migration report (aggregate_report.py exited non-zero). logs/ and result.jsonl are still available for manual review."
fi
