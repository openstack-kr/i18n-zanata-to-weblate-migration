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
    # Components whose creation itself failed, so the translation loop
    # below can skip them outright instead of attempting (and failing)
    # every one of their locales individually.
    local failed_components=()

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
    # Create components with the pot file for Weblate component initialization.
    for component in ${COMPONENTS[@]}; do
        CURRENT_COMPONENT="$component"
        pot_path=$(get_pot_path $component)

        if ! run_tagged python3 -u $SCRIPTSDIR/common/weblate_utils.py create-component \
                --project $PROJECT \
                --category $ZANATA_VERSION \
                --component $component \
                --pot-path $pot_path; then
            tagged_colorize "$RED" "[ERROR] Failed to create component: $component - skipping this component"
            had_failure=1
            failed_components+=("$component")
            continue
        fi
    done
    CURRENT_COMPONENT="-"

    for component in ${COMPONENTS[@]}; do
        CURRENT_COMPONENT="$component"

        if [[ " ${failed_components[@]} " == *" $component "* ]]; then
            tagged_colorize "$RED" "[ERROR] Skipping translations for $component - component creation failed earlier"
            continue
        fi

        translation_path_list=$(get_translation_path_list $component)

        for translation_path in $translation_path_list; do
            locale=$(extract_locale_from_path $translation_path)
            CURRENT_LOCALE="$locale"
            log "[INFO] Creating translation, locale: $locale, component: $component"

            if ! run_tagged python3 -u $SCRIPTSDIR/common/weblate_utils.py create-translation \
                    --project $PROJECT \
                    --category $ZANATA_VERSION \
                    --component $component \
                    --locale $locale; then
                tagged_colorize "$RED" "[ERROR] Failed to create translation: $component / $locale - skipping this locale"
                had_failure=1
                CURRENT_LOCALE="-"
                continue
            fi
            sleep 10

            log "[INFO] Check plural forms..."
            if ! run_tagged python3 -u $SCRIPTSDIR/04-prepare-weblate-components/lang_plural_check.py $translation_path; then
                tagged_colorize "$RED" "[ERROR] Plural form check failed: $component / $locale - skipping this locale"
                had_failure=1
                CURRENT_LOCALE="-"
                continue
            fi

            log "[INFO] Uploading PO filse: $translation_path"
            if ! run_tagged python3 -u $SCRIPTSDIR/common/weblate_utils.py upload-po-file \
                    --project $PROJECT \
                    --category $ZANATA_VERSION \
                    --component $component \
                    --locale $locale \
                    --po-path $translation_path; then
                tagged_colorize "$RED" "[ERROR] Failed to upload PO file: $component / $locale - skipping this locale"
                had_failure=1
                CURRENT_LOCALE="-"
                continue
            fi
            sleep 10

            CURRENT_LOCALE="-"
        done

    done
    CURRENT_COMPONENT="-"

    if [ "$had_failure" -eq 1 ]; then
        return 1
    fi
}
