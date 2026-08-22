source $SCRIPTSDIR/common/get_translation_path.sh

TEST_DIR=$HOME/$WORKSPACE_NAME/projects/$PROJECT/test
RESULT_JSON=$HOME/$WORKSPACE_NAME/projects/$PROJECT/result.jsonl

function test_accuracy {
    # Set when any single locale's checks fail, so one bad locale is
    # logged and skipped instead of aborting every remaining
    # locale/component via `exit` (mirrors create_weblate_components.sh).
    local had_failure=0

    # No component/locale is known yet for the project-level download
    # below - reset in case an earlier (project, version) run in the
    # same process left these set (see create_weblate_components.sh).
    CURRENT_COMPONENT="-"
    CURRENT_LOCALE="-"

    if [ ! -d "$TEST_DIR" ]; then
        log_quiet "[INFO] TEST_DIR does not exist. Create new one."
        mkdir -p $TEST_DIR
    fi

    cd $TEST_DIR
    # Download translation file from Weblate
    run_tagged_quiet python3 -u $SCRIPTSDIR/common/weblate_utils.py download-translation-file \
        --project $PROJECT \
        --po-path $TEST_DIR/$PROJECT.zip
    run_tagged_quiet unzip -o $PROJECT.zip
    rm -f $PROJECT.zip

    tree_line "▸ 정확도 테스트"

    local total_components=${#COMPONENTS[@]}
    local component_index=0

    for component in "${COMPONENTS[@]}"; do
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

        # Get translation path list as an array
        local translation_path_array=($(get_translation_path_list $component))
        local total_locales=${#translation_path_array[@]}
        local success_count=0
        # One rendered "<locale>  <failed step>  <status reason>" entry
        # per failed locale, printed as this component's tree children
        # once the loop below finishes - mirrors
        # create_weblate_components.sh's failed_locale_lines.
        local failed_locale_lines=()

        for translation_path in "${translation_path_array[@]}"; do
            local locale=$(extract_locale_from_path $translation_path)
            CURRENT_LOCALE="$locale"

            # the directory name did not support .,
            # so we need to replace . with -
            local version_dir=${ZANATA_VERSION//./-}
            local weblate_po_path=$(get_po_path $component $locale $TEST_DIR/$PROJECT/$version_dir true)

            log_quiet "[INFO] Step 1/6: Check the component/locale existence..."
            if ! run_tagged_quiet python3 -u $SCRIPTSDIR/common/weblate_utils.py check-translation-existence \
                --project $PROJECT \
                --category $ZANATA_VERSION \
                --component $component \
                --locale $locale \
                --zanata-po-path $translation_path \
                --weblate-po-path $weblate_po_path \
                --result-json $RESULT_JSON
            then
                had_failure=1
                failed_locale_lines+=("$(printf '%-8s%-24s%s' "$locale" "existence" "$(extract_status_reason "$LAST_TAGGED_LINE")")")
                CURRENT_LOCALE="-"
                continue
            fi

            # Runs before the sentence count check (which fails
            # outright on any translated-count difference) so this
            # classification - fuzzy re-marking vs possible real loss
            # - is always recorded to help triage that failure.
            log_quiet "[INFO] Step 2/6: Check fuzzy/untranslated counts..."
            if ! run_tagged_quiet python3 -u $SCRIPTSDIR/common/weblate_utils.py check-fuzzy-untranslated \
                --project $PROJECT \
                --category $ZANATA_VERSION \
                --component $component \
                --locale $locale \
                --zanata-po-path $translation_path \
                --weblate-po-path $weblate_po_path \
                --result-json $RESULT_JSON
            then
                had_failure=1
                failed_locale_lines+=("$(printf '%-8s%-24s%s' "$locale" "fuzzy-untranslated" "$(extract_status_reason "$LAST_TAGGED_LINE")")")
                CURRENT_LOCALE="-"
                continue
            fi

            # Runs before the sentence count/detail checks (which stop
            # the batch on the first content difference) so a
            # placeholder regression is always classified and recorded
            # even if those later checks fail on the same entries.
            log_quiet "[INFO] Step 3/6: Check placeholder consistency..."
            if ! run_tagged_quiet python3 -u $SCRIPTSDIR/common/weblate_utils.py check-placeholder-consistency \
                --project $PROJECT \
                --category $ZANATA_VERSION \
                --component $component \
                --locale $locale \
                --zanata-po-path $translation_path \
                --weblate-po-path $weblate_po_path \
                --result-json $RESULT_JSON
            then
                had_failure=1
                failed_locale_lines+=("$(printf '%-8s%-24s%s' "$locale" "placeholder" "$(extract_status_reason "$LAST_TAGGED_LINE")")")
                CURRENT_LOCALE="-"
                continue
            fi

            log_quiet "[INFO] Step 4/6: Check the sentence count..."
            if ! run_tagged_quiet python3 -u $SCRIPTSDIR/common/weblate_utils.py check-sentence-count \
                --project $PROJECT \
                --category $ZANATA_VERSION \
                --component $component \
                --locale $locale \
                --zanata-po-path $translation_path \
                --weblate-po-path $weblate_po_path \
                --result-json $RESULT_JSON
            then
                had_failure=1
                failed_locale_lines+=("$(printf '%-8s%-24s%s' "$locale" "sentence-count" "$(extract_status_reason "$LAST_TAGGED_LINE")")")
                CURRENT_LOCALE="-"
                continue
            fi

            log_quiet "[INFO] Step 5/6: Check the sentence detail..."
            if ! run_tagged_quiet python3 -u $SCRIPTSDIR/common/weblate_utils.py check-sentence-detail \
                --project $PROJECT \
                --category $ZANATA_VERSION \
                --component $component \
                --locale $locale \
                --zanata-po-path $translation_path \
                --weblate-po-path $weblate_po_path \
                --result-json $RESULT_JSON
            then
                had_failure=1
                failed_locale_lines+=("$(printf '%-8s%-24s%s' "$locale" "sentence-detail" "$(extract_status_reason "$LAST_TAGGED_LINE")")")
                CURRENT_LOCALE="-"
                continue
            fi

            log_quiet "[INFO] Step 6/6: Check the PO format (msgfmt --check)..."
            if ! run_tagged_quiet python3 -u $SCRIPTSDIR/common/weblate_utils.py check-po-format \
                --project $PROJECT \
                --category $ZANATA_VERSION \
                --component $component \
                --locale $locale \
                --weblate-po-path $weblate_po_path \
                --result-json $RESULT_JSON
            then
                had_failure=1
                failed_locale_lines+=("$(printf '%-8s%-24s%s' "$locale" "po-format" "$(extract_status_reason "$LAST_TAGGED_LINE")")")
                CURRENT_LOCALE="-"
                continue
            fi

            success_count=$((success_count + 1))
            CURRENT_LOCALE="-"
        done

        # See create_weblate_components.sh's identical check for why
        # "0/0" gets its own neutral symbol instead of a plain ✓.
        local component_symbol="✓"
        if [ "$total_locales" -eq 0 ]; then
            component_symbol="○"
        elif [ "${#failed_locale_lines[@]}" -gt 0 ]; then
            component_symbol="✗"
        fi
        if [ "$total_locales" -eq 0 ]; then
            tree_line "$(printf '%s %s %-28s (테스트할 번역 파일 없음)' "$component_connector" "$component_symbol" "$component")"
        else
            tree_line "$(printf '%s %s %-28s %d/%d' "$component_connector" "$component_symbol" "$component" "$success_count" "$total_locales")"
        fi

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
        CURRENT_COMPONENT="-"
    done

    cd - > /dev/null

    if [ "$had_failure" -eq 1 ]; then
        return 1
    fi
}