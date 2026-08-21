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

# Print $2, wrapped in the color code $1, only when stdout is a real
# terminal (IS_TTY=1); otherwise print $2 unchanged. Use this for any
# success/failure/warning line that might also be written to a log
# file (directly, or via `tee`/redirect by the caller) - callers must
# never let a colorized string reach a log file, since that leaves raw
# ANSI escape bytes in it and breaks tools (e.g. grep on error.*.log)
# and the README's `version | message` log format.
function colorize() {
    local color=$1
    local text=$2
    if [ "$IS_TTY" -eq 1 ]; then
        echo -e "${color}${text}${NC}"
    else
        echo "${text}"
    fi
}

# title is a description of the stage
function stage() {
    local title=$1
    _STAGE_OPEN=1
    echo "# ${title}"
}

function fail() {
    local message=$1
    colorize "$RED" "[Failed] ${message}"
}

function debug() {
    local message=$1
    echo "[Debug] ${message}"
}

function endstage() {
    _STAGE_OPEN=0
    echo "=========================================="
}

# Prints the closing separator for a stage left open by a process exit
# (normal or via `exit N`) that never reached endstage. Registered as
# an EXIT trap below so it runs regardless of where in the script - or
# in a sourced function from another file - the exit happens.
function _stage_exit_trap() {
    if [ "$_STAGE_OPEN" -eq 1 ]; then
        _STAGE_OPEN=0
        echo "=========================================="
    fi
}
trap _stage_exit_trap EXIT