source $SCRIPTSDIR/common/get_translation_path.sh

TEST_DIR=$HOME/$WORKSPACE_NAME/projects/$PROJECT/test
RESULT_JSON=$HOME/$WORKSPACE_NAME/projects/$PROJECT/result.jsonl

function test_accuracy {
    # Set when any single locale's checks fail, so one bad locale is
    # logged and skipped instead of aborting every remaining
    # locale/component via `exit` (mirrors create_weblate_components.sh).
    local had_failure=0

    if [ ! -d "$TEST_DIR" ]; then
        echo "[INFO] TEST_DIR does not exist. Create new one."
        mkdir -p $TEST_DIR
    fi

    cd $TEST_DIR
    # Download translation file from Weblate
    python3 -u $SCRIPTSDIR/common/weblate_utils.py download-translation-file \
        --project $PROJECT \
        --po-path $TEST_DIR/$PROJECT.zip
    unzip -o $PROJECT.zip
    rm -f $PROJECT.zip
    
    for component in "${COMPONENTS[@]}"; do
        echo ""
        echo "============================================================"
        echo " Target: $PROJECT / $ZANATA_VERSION / $component"
        echo "============================================================"
        
        # Get translation path list as an array
        local translation_path_array=($(get_translation_path_list $component))
        
        for translation_path in "${translation_path_array[@]}"; do
            local locale=$(extract_locale_from_path $translation_path)
            echo ""
            echo "[INFO] Testing locale: $locale"
            
            # the directory name did not support .,
            # so we need to replace . with -
            local version_dir=${ZANATA_VERSION//./-}
            local weblate_po_path=$(get_po_path $component $locale $TEST_DIR/$PROJECT/$version_dir true)

            echo "[INFO] Step 1/6: Check the component/locale existence..."
            if ! python3 -u $SCRIPTSDIR/common/weblate_utils.py check-translation-existence \
                --project $PROJECT \
                --category $ZANATA_VERSION \
                --component $component \
                --locale $locale \
                --zanata-po-path $translation_path \
                --weblate-po-path $weblate_po_path \
                --result-json $RESULT_JSON
            then
                echo "[ERROR] Component/locale does not exist: $PROJECT, $ZANATA_VERSION, $component, $locale, $translation_path"
                had_failure=1
                continue
            fi

            # Runs before the sentence count check (which fails
            # outright on any translated-count difference) so this
            # classification - fuzzy re-marking vs possible real loss
            # - is always recorded to help triage that failure.
            echo "[INFO] Step 2/6: Check fuzzy/untranslated counts..."
            if ! python3 -u $SCRIPTSDIR/common/weblate_utils.py check-fuzzy-untranslated \
                --project $PROJECT \
                --category $ZANATA_VERSION \
                --component $component \
                --locale $locale \
                --zanata-po-path $translation_path \
                --weblate-po-path $weblate_po_path \
                --result-json $RESULT_JSON
            then
                echo "[ERROR] Untranslated count increased (possible translation loss): $PROJECT, $ZANATA_VERSION, $component, $locale, $translation_path"
                had_failure=1
                continue
            fi

            # Runs before the sentence count/detail checks (which stop
            # the batch on the first content difference) so a
            # placeholder regression is always classified and recorded
            # even if those later checks fail on the same entries.
            echo "[INFO] Step 3/6: Check placeholder consistency..."
            if ! python3 -u $SCRIPTSDIR/common/weblate_utils.py check-placeholder-consistency \
                --project $PROJECT \
                --category $ZANATA_VERSION \
                --component $component \
                --locale $locale \
                --zanata-po-path $translation_path \
                --weblate-po-path $weblate_po_path \
                --result-json $RESULT_JSON
            then
                echo "[ERROR] Placeholder regression detected: $PROJECT, $ZANATA_VERSION, $component, $locale, $translation_path"
                had_failure=1
                continue
            fi

            echo "[INFO] Step 4/6: Check the sentence count..."
            if ! python3 -u $SCRIPTSDIR/common/weblate_utils.py check-sentence-count \
                --project $PROJECT \
                --category $ZANATA_VERSION \
                --component $component \
                --locale $locale \
                --zanata-po-path $translation_path \
                --weblate-po-path $weblate_po_path \
                --result-json $RESULT_JSON
            then
                echo "[ERROR] Check the sentence failed: $PROJECT, $ZANATA_VERSION, $component, $locale, $translation_path"
                had_failure=1
                continue
            fi

            echo "[INFO] Step 5/6: Check the sentence detail..."
            if ! python3 -u $SCRIPTSDIR/common/weblate_utils.py check-sentence-detail \
                --project $PROJECT \
                --category $ZANATA_VERSION \
                --component $component \
                --locale $locale \
                --zanata-po-path $translation_path \
                --weblate-po-path $weblate_po_path \
                --result-json $RESULT_JSON
            then
                echo "[ERROR] Check the sentence detail failed: $PROJECT, $ZANATA_VERSION, $component, $locale, $translation_path"
                had_failure=1
                continue
            fi

            echo "[INFO] Step 6/6: Check the PO format (msgfmt --check)..."
            if ! python3 -u $SCRIPTSDIR/common/weblate_utils.py check-po-format \
                --project $PROJECT \
                --category $ZANATA_VERSION \
                --component $component \
                --locale $locale \
                --weblate-po-path $weblate_po_path \
                --result-json $RESULT_JSON
            then
                echo "[ERROR] PO format check failed: $PROJECT, $ZANATA_VERSION, $component, $locale, $weblate_po_path"
                had_failure=1
                continue
            fi

        done
        echo "[INFO] ✓ Component '$component' completed - tested ${#translation_path_array[@]} locales"
    done

    echo ""

    cd - > /dev/null

    if [ "$had_failure" -eq 1 ]; then
        return 1
    fi
}