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
        log "[INFO] TEST_DIR does not exist. Create new one."
        mkdir -p $TEST_DIR
    fi

    cd $TEST_DIR
    # Download translation file from Weblate
    run_tagged python3 -u $SCRIPTSDIR/common/weblate_utils.py download-translation-file \
        --project $PROJECT \
        --po-path $TEST_DIR/$PROJECT.zip
    run_tagged unzip -o $PROJECT.zip
    rm -f $PROJECT.zip

    for component in "${COMPONENTS[@]}"; do
        CURRENT_COMPONENT="$component"
        log ""
        log "============================================================"
        log " Target: $PROJECT / $ZANATA_VERSION / $component"
        log "============================================================"

        # Get translation path list as an array
        local translation_path_array=($(get_translation_path_list $component))

        for translation_path in "${translation_path_array[@]}"; do
            local locale=$(extract_locale_from_path $translation_path)
            CURRENT_LOCALE="$locale"
            log ""
            log "[INFO] Testing locale: $locale"

            # the directory name did not support .,
            # so we need to replace . with -
            local version_dir=${ZANATA_VERSION//./-}
            local weblate_po_path=$(get_po_path $component $locale $TEST_DIR/$PROJECT/$version_dir true)

            log "[INFO] Step 1/6: Check the component/locale existence..."
            if ! run_tagged python3 -u $SCRIPTSDIR/common/weblate_utils.py check-translation-existence \
                --project $PROJECT \
                --category $ZANATA_VERSION \
                --component $component \
                --locale $locale \
                --zanata-po-path $translation_path \
                --weblate-po-path $weblate_po_path \
                --result-json $RESULT_JSON
            then
                log "[ERROR] Component/locale does not exist: $PROJECT, $ZANATA_VERSION, $component, $locale, $translation_path"
                had_failure=1
                CURRENT_LOCALE="-"
                continue
            fi

            # Runs before the sentence count check (which fails
            # outright on any translated-count difference) so this
            # classification - fuzzy re-marking vs possible real loss
            # - is always recorded to help triage that failure.
            log "[INFO] Step 2/6: Check fuzzy/untranslated counts..."
            if ! run_tagged python3 -u $SCRIPTSDIR/common/weblate_utils.py check-fuzzy-untranslated \
                --project $PROJECT \
                --category $ZANATA_VERSION \
                --component $component \
                --locale $locale \
                --zanata-po-path $translation_path \
                --weblate-po-path $weblate_po_path \
                --result-json $RESULT_JSON
            then
                log "[ERROR] Untranslated count increased (possible translation loss): $PROJECT, $ZANATA_VERSION, $component, $locale, $translation_path"
                had_failure=1
                CURRENT_LOCALE="-"
                continue
            fi

            # Runs before the sentence count/detail checks (which stop
            # the batch on the first content difference) so a
            # placeholder regression is always classified and recorded
            # even if those later checks fail on the same entries.
            log "[INFO] Step 3/6: Check placeholder consistency..."
            if ! run_tagged python3 -u $SCRIPTSDIR/common/weblate_utils.py check-placeholder-consistency \
                --project $PROJECT \
                --category $ZANATA_VERSION \
                --component $component \
                --locale $locale \
                --zanata-po-path $translation_path \
                --weblate-po-path $weblate_po_path \
                --result-json $RESULT_JSON
            then
                log "[ERROR] Placeholder regression detected: $PROJECT, $ZANATA_VERSION, $component, $locale, $translation_path"
                had_failure=1
                CURRENT_LOCALE="-"
                continue
            fi

            log "[INFO] Step 4/6: Check the sentence count..."
            if ! run_tagged python3 -u $SCRIPTSDIR/common/weblate_utils.py check-sentence-count \
                --project $PROJECT \
                --category $ZANATA_VERSION \
                --component $component \
                --locale $locale \
                --zanata-po-path $translation_path \
                --weblate-po-path $weblate_po_path \
                --result-json $RESULT_JSON
            then
                log "[ERROR] Check the sentence failed: $PROJECT, $ZANATA_VERSION, $component, $locale, $translation_path"
                had_failure=1
                CURRENT_LOCALE="-"
                continue
            fi

            log "[INFO] Step 5/6: Check the sentence detail..."
            if ! run_tagged python3 -u $SCRIPTSDIR/common/weblate_utils.py check-sentence-detail \
                --project $PROJECT \
                --category $ZANATA_VERSION \
                --component $component \
                --locale $locale \
                --zanata-po-path $translation_path \
                --weblate-po-path $weblate_po_path \
                --result-json $RESULT_JSON
            then
                log "[ERROR] Check the sentence detail failed: $PROJECT, $ZANATA_VERSION, $component, $locale, $translation_path"
                had_failure=1
                CURRENT_LOCALE="-"
                continue
            fi

            log "[INFO] Step 6/6: Check the PO format (msgfmt --check)..."
            if ! run_tagged python3 -u $SCRIPTSDIR/common/weblate_utils.py check-po-format \
                --project $PROJECT \
                --category $ZANATA_VERSION \
                --component $component \
                --locale $locale \
                --weblate-po-path $weblate_po_path \
                --result-json $RESULT_JSON
            then
                log "[ERROR] PO format check failed: $PROJECT, $ZANATA_VERSION, $component, $locale, $weblate_po_path"
                had_failure=1
                CURRENT_LOCALE="-"
                continue
            fi

            CURRENT_LOCALE="-"
        done
        log "[INFO] ✓ Component '$component' completed - tested ${#translation_path_array[@]} locales"
        CURRENT_COMPONENT="-"
    done

    log ""

    cd - > /dev/null

    if [ "$had_failure" -eq 1 ]; then
        return 1
    fi
}