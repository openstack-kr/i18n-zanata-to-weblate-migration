#!/bin/bash
# Create and setup the Weblate components.

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

source $SCRIPTSDIR/common/get_translation_path.sh

function create_weblate_components {
    # Set when any single (component, locale) step below fails, so one
    # bad locale (e.g. a Weblate-side upload conflict) is logged and
    # skipped instead of aborting every remaining component/locale for
    # this branch via `exit`.
    local had_failure=0

    cd $SCRIPTSDIR
    WORKSPACE_DIR=$HOME/workspace/projects/$PROJECT/$WORKSPACE_NAME/test
    mkdir -p $WORKSPACE_DIR

    # No component/locale is known yet for the project-level calls
    # below - reset in case an earlier (project, version) run in the
    # same process left these set (defensive; migration_resources.sh
    # currently runs one (project, version) per process, but this
    # keeps the function correct if that ever changes).
    CURRENT_COMPONENT="-"
    CURRENT_LOCALE="-"

    # Create project
    run_tagged python3 -u $SCRIPTSDIR/common/weblate_utils.py create-project --project $PROJECT || exit 1
    # Create global glossary for the project
    run_tagged python3 -u $SCRIPTSDIR/common/weblate_utils.py create-glossary --project $PROJECT || exit 1
    # Create category with the branch name
    run_tagged python3 -u $SCRIPTSDIR/common/weblate_utils.py create-category --project $PROJECT --category $ZANATA_VERSION || exit 1

    # phase 2: creation and translations used to be two separate
    # passes over COMPONENTS (create every component first, then
    # attempt translations for the ones that succeeded, skipping the
    # rest with a one-off error line). Merged into a single pass here
    # so each component's tree line (success/fail + child failures)
    # can be printed exactly once, right after that component is
    # fully done - either at creation failure or after its whole
    # translation loop - instead of needing a second "skip" branch to
    # explain why a component has no translation attempts.
    local total_components=${#COMPONENTS[@]}
    local component_index=0

    for component in ${COMPONENTS[@]}; do
        CURRENT_COMPONENT="$component"
        component_index=$((component_index + 1))
        local component_connector="├─"
        if [ "$component_index" -eq "$total_components" ]; then
            component_connector="└─"
        fi
        local child_prefix="│  "
        if [ "$component_connector" == "└─" ]; then
            child_prefix="   "
        fi

        pot_path=$(get_pot_path $component)

        if ! run_tagged_quiet python3 -u $SCRIPTSDIR/common/weblate_utils.py create-component \
                --project $PROJECT \
                --category $ZANATA_VERSION \
                --component $component \
                --pot-path $pot_path; then
            had_failure=1
            tree_line "$(printf '%s ✗ %-28s (컴포넌트 생성 실패)' "$component_connector" "$component")"
            tree_line "$(printf '%s└─ ✗ %s' "$child_prefix" "$(printf '%-8s%-20s%s' "-" "create-component" "$(extract_status_reason "$LAST_TAGGED_LINE")")")"
            continue
        fi

        translation_path_list=$(get_translation_path_list $component)
        local total_locales=0
        for translation_path in $translation_path_list; do
            total_locales=$((total_locales + 1))
        done
        local success_count=0
        # One rendered "<locale>  <operation>  <status reason>" entry
        # per failed locale, printed as this component's tree children
        # once the loop below finishes - successful locales are never
        # added here, so they never appear as their own line (only
        # reflected in success_count/total_locales above).
        local failed_locale_lines=()

        for translation_path in $translation_path_list; do
            locale=$(extract_locale_from_path $translation_path)
            CURRENT_LOCALE="$locale"
            log_quiet "[INFO] Creating translation, locale: $locale, component: $component"

            if ! run_tagged_quiet python3 -u $SCRIPTSDIR/common/weblate_utils.py create-translation \
                    --project $PROJECT \
                    --category $ZANATA_VERSION \
                    --component $component \
                    --locale $locale; then
                had_failure=1
                failed_locale_lines+=("$(printf '%-8s%-20s%s' "$locale" "create-translation" "$(extract_status_reason "$LAST_TAGGED_LINE")")")
                CURRENT_LOCALE="-"
                continue
            fi
            sleep 10

            log_quiet "[INFO] Check plural forms..."
            if ! run_tagged_quiet python3 -u $SCRIPTSDIR/04-prepare-weblate-components/lang_plural_check.py $translation_path; then
                had_failure=1
                failed_locale_lines+=("$(printf '%-8s%-20s%s' "$locale" "plural-check" "$(extract_status_reason "$LAST_TAGGED_LINE")")")
                CURRENT_LOCALE="-"
                continue
            fi

            log_quiet "[INFO] Uploading PO filse: $translation_path"
            if ! run_tagged_quiet python3 -u $SCRIPTSDIR/common/weblate_utils.py upload-po-file \
                    --project $PROJECT \
                    --category $ZANATA_VERSION \
                    --component $component \
                    --locale $locale \
                    --po-path $translation_path; then
                had_failure=1
                failed_locale_lines+=("$(printf '%-8s%-20s%s' "$locale" "upload-po-file" "$(extract_status_reason "$LAST_TAGGED_LINE")")")
                CURRENT_LOCALE="-"
                continue
            fi
            sleep 10

            success_count=$((success_count + 1))
            CURRENT_LOCALE="-"
        done

        local component_symbol="✓"
        if [ "${#failed_locale_lines[@]}" -gt 0 ]; then
            component_symbol="✗"
        fi
        tree_line "$(printf '%s %s %-28s %d/%d' "$component_connector" "$component_symbol" "$component" "$success_count" "$total_locales")"

        local failed_count=${#failed_locale_lines[@]}
        local locale_index=0
        for entry in "${failed_locale_lines[@]}"; do
            locale_index=$((locale_index + 1))
            local locale_connector="├─"
            if [ "$locale_index" -eq "$failed_count" ]; then
                locale_connector="└─"
            fi
            tree_line "$(printf '%s%s ✗ %s' "$child_prefix" "$locale_connector" "$entry")"
        done
    done
    CURRENT_COMPONENT="-"

    if [ "$had_failure" -eq 1 ]; then
        return 1
    fi
}
