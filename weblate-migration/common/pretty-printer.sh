#!/bin/bash
# Pretty print to show readable and standardize the output
# pretty-printer.sh

# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations
# under the License.

# Tracks whether a stage() is currently open (1) or was closed by a
# matching endstage() (0). Used by _stage_exit_trap below so a stage
# that fails and exits without ever calling endstage still gets its
# closing separator - callers (e.g. migration_resources.sh) exit
# directly from many places, including from deep inside sourced
# functions in other files, so relying on every call site to
# remember to call endstage before exit is not reliable.
_STAGE_OPEN=0

# Color codes for TTY-only status output. Same values as the
# RED/GREEN/YELLOW/NC constants in migration/save_lang.sh, duplicated
# here rather than sourced from there - save_lang.sh is a standalone
# executable script (runs migration logic as soon as it's invoked,
# `set -e` and all), not a library meant to be sourced.
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Whether *this process's* stdout is an actual terminal, as opposed to
# a pipe or a file redirect. Deliberately evaluated once here, at
# source time, by whichever process sources pretty-printer.sh -
# that's what makes it correct in both of this repo's entry points:
#   - migration_resources.sh sources this directly, so when it's run
#     standalone in an interactive shell, IS_TTY reflects that; when
#     it's run as `migration_resources.sh ... | while read line; do
#     ... done` (as migration_projects.sh does), its stdout is a pipe,
#     so IS_TTY is correctly 0 there even though a human may be
#     watching migration_projects.sh's own terminal.
#   - migration_projects.sh sources this too, and checks IS_TTY in its
#     *own* process, which is the process actually connected to the
#     user's terminal (or to a log file, if the whole batch run itself
#     was redirected/piped by the caller).
if [ -t 1 ]; then
    IS_TTY=1
else
    IS_TTY=0
fi

# Which (component, locale) the pipeline is currently working on, for
# tagging every project.log/error.log line - not just the final
# summary line a stage prints on failure - so a person can tell which
# component/locale a line belongs to without scrolling up to the last
# "Creating translation..." line. "-" means not yet known (e.g. before
# create_weblate_components.sh's loops start). migration_projects.sh
# adds the outer project/category fields separately; these two cover
# the inner fields that only create_weblate_components.sh/test.sh
# know. Set/reset by those two files' loops - see phase-1-log-tagging.md.
CURRENT_COMPONENT="-"
CURRENT_LOCALE="-"

# Short human-readable reason for the most recent fatal failure in a
# stage whose own progress/error detail is now quiet (setup, clone) -
# set by the failing function right before it returns 1, and read by
# migration_resources.sh's single visible error line for that stage,
# so the console still says *why* even though the granular [INFO]/
# [ERROR] trail is project.log-only. Without this, a bare
# "[ERROR] Failed to setup environment..." on console wouldn't
# distinguish "Python 3 missing" from "pip install failed" from
# "zanata.ini not found" - all six of setup.sh's distinct failure
# points, and clone_project's two, would look identical from the
# console alone.
FATAL_REASON=""

# Print $1 tagged with the current component/locale context, for
# bash-authored [INFO]-style lines (the plain-echo equivalent of
# colorize() below, for lines that aren't success/failure/warning).
function log() {
    echo "${CURRENT_COMPONENT} | ${CURRENT_LOCALE} | $1"
}

# Print $2, wrapped in the color code $1, only when stdout is a real
# terminal (IS_TTY=1); otherwise print $2 unchanged. Use this for any
# success/failure/warning line that might also be written to a log
# file (directly, or via `tee`/redirect by the caller) - callers must
# never let a colorized string reach a log file, since that leaves raw
# ANSI escape bytes in it and breaks tools (e.g. grep on error.*.log)
# and the README's `version | message` log format.
#
# Deliberately NOT tagged with CURRENT_COMPONENT/CURRENT_LOCALE here,
# unlike log()/run_tagged() - migration_projects.sh sources this file
# too and calls colorize() for two things that must stay untagged: its
# own project/version-level success/failure summary (never had a
# component/locale, and isn't written to project.log/error.log at
# all), and re-coloring a $plain_line that migration_resources.sh's
# process already tagged in full - tagging either here would add a
# spurious second "- | - | " (migration_projects.sh never touches
# CURRENT_COMPONENT/CURRENT_LOCALE, so they'd always read "-" there).
# Call sites inside migration_resources.sh's own process that want the
# tag use tagged_colorize() below instead.
function colorize() {
    local color=$1
    local text=$2
    if [ "$IS_TTY" -eq 1 ]; then
        echo -e "${color}${text}${NC}"
    else
        echo "${text}"
    fi
}

# colorize(), but tagged with the current component/locale context -
# for success/failure/warning lines from within migration_resources.sh
# and its sourced functions (e.g. create_weblate_components.sh),
# mirroring log() above. Do not use this from migration_projects.sh -
# see the note on colorize() above.
function tagged_colorize() {
    colorize "$1" "${CURRENT_COMPONENT} | ${CURRENT_LOCALE} | $2"
}

# Run $@, tagging every line of its combined stdout+stderr with the
# current component/locale context, while still returning the
# command's real exit code. A plain `cmd | while read ...` would lose
# that - the pipeline's exit status is the *last* command's (the while
# loop, always 0) - so PIPESTATUS[0] is read immediately after, same
# technique migration_projects.sh uses for the same reason. Use this
# for external commands (python3/git/zanata-cli) whose own stdout
# isn't already routed through log()/colorize().
#
# The `|| [ -n "$line" ]` on the read is required: without it, a final
# line with no trailing newline (read still fills $line but returns
# non-zero) is silently dropped instead of tagged and printed - same
# guard migration_projects.sh's own file-reading loops use below.
function run_tagged() {
    "$@" 2>&1 | while IFS= read -r line || [ -n "$line" ]; do
        echo "${CURRENT_COMPONENT} | ${CURRENT_LOCALE} | ${line}"
    done
    return "${PIPESTATUS[0]}"
}

# --- Live console tree (phase 2) ---------------------------------
#
# migration_projects.sh's live console used to echo every tagged line
# verbatim - the same density for a locale that succeeded in one
# request as one that took 3 retries and failed. create_weblate_components.sh
# now instead builds a compressed project/category -> component ->
# locale tree (success collapsed to one line, only failures expand),
# while project.log/error.log keep the full detail from phase 1
# unchanged. Since the child process (migration_resources.sh) and the
# parent (migration_projects.sh) only share one pipe, the child tags
# each line with one of the two markers below so the parent knows
# what to do with it - see phase-2-console-tree.md for the full
# design.

# A line already fully formatted for the live console (built by
# tree_line() below) - the parent prints it as-is (after stripping the
# marker) instead of tagging it and appending it to project.log. This
# is a compressed *view* over facts already recorded via
# log()/tagged_colorize()/run_tagged_quiet(), not new information, so
# it deliberately doesn't also go to the log file.
TREE_MARKER="##TREE## "

# A line tagged and meant for project.log/error.log only (phase 1
# behavior), but that the parent should NOT echo to the live console -
# create_weblate_components.sh's per-locale steps use this instead of
# log()/run_tagged()/tagged_colorize(), since the console now shows
# only the compressed tree built from tree_line() calls. Other stages
# keep using log()/run_tagged() unchanged, so their console output is
# unaffected by phase 2.
QUIET_MARKER="##QUIET## "

# A tree line that replaces the immediately preceding tree line on a
# real terminal (e.g. "⏳ 환경설정 진행중..." -> "✓ 환경설정 완료" on
# the same row), instead of appending a new one - migration_projects.sh
# only does this when its own stdout is a TTY (see colorize()'s
# IS_TTY, same reasoning: an ANSI cursor-up/clear-line sequence is
# meaningless - and corrupts the byte stream - when stdout is
# redirected to a file or captured by another process). When not a
# TTY, the parent falls back to printing this as a normal new line, so
# a start/done pair always reads correctly either way. Only use this
# for a stage with exactly one such pair (the ⏳ line is immediately
# followed by exactly one done line, nothing else printed in between) -
# create_weblate_components.sh/test.sh's multi-line trees don't fit
# this and keep using plain tree_line() for their own "⏳ ... 진행중"
# header instead.
TREE_UPDATE_MARKER="##TREE_UPDATE## "

# Print $1 as a ready-to-display tree line - see TREE_MARKER above.
function tree_line() {
    echo "${TREE_MARKER}$1"
}

# Print $1 as a tree line that updates the previous one - see
# TREE_UPDATE_MARKER above.
function tree_line_update() {
    echo "${TREE_UPDATE_MARKER}$1"
}

# log(), but marked quiet - see QUIET_MARKER above.
function log_quiet() {
    echo "${QUIET_MARKER}${CURRENT_COMPONENT} | ${CURRENT_LOCALE} | $1"
}

# Run $@ like run_tagged(), but marked quiet (see QUIET_MARKER above)
# and captured via a temp file instead of a live pipe. The temp file
# is deliberate, not just a style choice: `cmd | while read ...; done`
# runs the while loop in a subshell (bash's default pipeline
# behavior), so a variable set inside it - which is exactly what's
# needed to hand the command's last output line back to the caller
# for the tree leaf's failure reason (see extract_status_reason()
# below) - would not survive past the pipeline. Reading from a file
# instead of a pipe keeps the loop in the current shell, so
# LAST_TAGGED_LINE assigned below is visible to the caller. This means
# output is captured in full and replayed after the command exits
# rather than streamed live, which is fine here because quiet lines
# never reach the console anyway (only project.log, written after the
# fact).
LAST_TAGGED_LINE=""
function run_tagged_quiet() {
    local tmp
    tmp=$(mktemp)
    "$@" >"$tmp" 2>&1
    local exit_code=$?
    while IFS= read -r line || [ -n "$line" ]; do
        echo "${QUIET_MARKER}${CURRENT_COMPONENT} | ${CURRENT_LOCALE} | ${line}"
    done <"$tmp"
    # Prefer the actual "[ERROR] ... (<code>)..." summary line
    # _retry_on_status prints, over a blind last-line grab - if the
    # failed response's body is itself multi-line (e.g. an HTML
    # 502/503 gateway page, which is_retryable_status/_retry_on_status
    # in weblate_utils.py are written to expect), the real file's last
    # physical line is a fragment of that body, not the summary line;
    # the status code and (for the final attempt) "not retrying"/
    # "failed after N attempts" text are always on the summary line's
    # first physical line, before the body is appended, so this still
    # finds it regardless of how many lines the body wraps onto. Falls
    # back to the literal last line for failures that don't go through
    # _retry_on_status at all (e.g. lang_plural_check.py).
    LAST_TAGGED_LINE=$(grep -E '^\[ERROR\].*\([0-9]{3}\)' "$tmp" | tail -n 1)
    if [ -z "$LAST_TAGGED_LINE" ]; then
        LAST_TAGGED_LINE=$(tail -n 1 "$tmp")
    fi
    rm -f "$tmp"
    return "$exit_code"
}

# Pull a short "<status> <reason>" (plus a retry-count suffix, if any)
# out of a weblate_utils.py CLI failure's last printed line, for a
# tree leaf's one-line failure summary. _retry_on_status
# (common/weblate_utils.py) always ends a failed call with one of:
#   "[ERROR] {action} rejected (<code>), not retrying: <body>"
#   "[ERROR] {action} failed after <n> attempts (<code>): <body>"
# and <body> is often JSON with a "code" field (e.g.
# {"errors":[{"code":"not_found",...}]}). Falls back to a truncated
# copy of the raw line when neither pattern matches - not every
# failure in create_weblate_components.sh's loop goes through
# _retry_on_status (e.g. lang_plural_check.py doesn't).
#
# Depends on PCRE support in `grep -P` (GNU grep built with
# --enable-perl-regexp, the default on Debian/Ubuntu - see
# phase-2-console-tree.md for why this wasn't verified against the
# actual batch-run host).
function extract_status_reason() {
    local text="$1"
    local status
    status=$(echo "$text" | grep -oP '\(\K[0-9]{3}(?=\))' | head -1)
    local reason
    reason=$(echo "$text" | grep -oP '"code":"\K[^"]+' | head -1)
    local attempts
    attempts=$(echo "$text" | grep -oP 'failed after \K[0-9]+(?= attempts)')
    local retry_suffix=""
    if [ -n "$attempts" ]; then
        retry_suffix=" (${attempts}회 재시도 후)"
    fi
    if [ -n "$status" ] && [ -n "$reason" ]; then
        echo "${status} ${reason}${retry_suffix}"
    elif [ -n "$status" ]; then
        echo "${status}${retry_suffix}"
    else
        echo "${text:0:60}"
    fi
}

# title is a description of the stage. Quiet (project.log only, not
# the live console) - the console now shows only the tree built from
# tree_line() calls, not every stage's raw section header/separator.
function stage() {
    local title=$1
    _STAGE_OPEN=1
    log_quiet "# ${title}"
}

function fail() {
    local message=$1
    tagged_colorize "$RED" "[Failed] ${message}"
}

function debug() {
    local message=$1
    log_quiet "[Debug] ${message}"
}

function endstage() {
    _STAGE_OPEN=0
    log_quiet "=========================================="
}

# Prints the closing separator for a stage left open by a process exit
# (normal or via `exit N`) that never reached endstage. Registered as
# an EXIT trap below so it runs regardless of where in the script - or
# in a sourced function from another file - the exit happens.
function _stage_exit_trap() {
    if [ "$_STAGE_OPEN" -eq 1 ]; then
        _STAGE_OPEN=0
        log_quiet "=========================================="
    fi
}
trap _stage_exit_trap EXIT