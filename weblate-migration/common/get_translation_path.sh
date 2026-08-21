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

function sanitize_locale {
    local locale=$1
    
    # Normalize locale code:
    # - Language code: lowercase (Th -> th, JA -> ja)
    # - Region code: uppercase (zh_tw -> zh_TW, pt_br -> pt_BR)
    
    if [[ "$locale" == *"_"* ]]; then
        # Has region code (e.g., zh_tw, pt_BR, ko_kr)
        IFS='_' read -r lang region <<< "$locale"
        # Language to lowercase, region to uppercase
        echo "${lang,,}_${region^^}"
    else
        # Single language code (e.g., Th, ja, DE)
        # Convert to lowercase
        echo "${locale,,}"
    fi
}

function get_project_package_name {
    local project=$1
    local project_package_name=""
    
    case $project in
        "designate-dashboard")
            # Remove all dashes
            # ex. designate-dashboard -> designatedashboard
            project_package_name="designatedashboard"
            ;;
        "freezer-web-ui")
            # Remove all dashes
            # ex. freezer-web-ui -> freezer_ui
            project_package_name="freezer_ui"
            ;;
        *)
            project_package_name="${project//-/_}"
    esac
    
    echo "$project_package_name"
}

function get_pot_path {
    local component=$1
    local base_dir=${2:-$HOME/$WORKSPACE_NAME/projects/$PROJECT/pot}
    local module_name=""
    local project_package_name=$(get_project_package_name $PROJECT)
    
    case $component in
        "releasenotes")
            echo "$base_dir/releasenotes/source/locale/releasenotes.pot"
            ;;
        *-django)
            # openstack-auth-django -> openstack_auth/locale/django.pot
            module_name="${component%-django}"
            module_name="${module_name//-/_}"
            echo "$base_dir/$module_name/locale/django.pot"
            ;;
        *-djangojs)
            # openstack-auth-djangojs -> openstack_auth/locale/djangojs.pot
            module_name="${component%-djangojs}"
            module_name="${module_name//-/_}"
            echo "$base_dir/$module_name/locale/djangojs.pot"
            ;;
        "django")
            echo "$base_dir/$project_package_name/locale/django.pot"
            ;;
        "djangojs")
            echo "$base_dir/$project_package_name/locale/djangojs.pot"
            ;;
        "doc"|doc-*)
            echo "$base_dir/doc/source/locale/$component.pot"
            ;;
        *)
            echo "$base_dir/$project_package_name/locale/$component.pot"
            ;;
    esac
}

function get_po_path {
    local component=$1
    local locale=$2
    local base_dir=${3:-$HOME/workspace/projects/$PROJECT/translations}
    local is_weblate=${4:-false}

    # For Weblate, normalize locale code
    if [ "$is_weblate" == "true" ]; then
        locale=$(sanitize_locale "$locale")
    fi

    case $component in
        "releasenotes")
            echo "$base_dir/releasenotes/source/locale/$locale/LC_MESSAGES/releasenotes.po"
            ;;
        *-django)
            if [ "$is_weblate" == "true" ]; then
                echo "$base_dir/$component/locale/$locale/LC_MESSAGES/django.po"
            else
                # openstack-auth-django -> openstack_auth/locale/django.pot
                module_name="${component%-django}"
                module_name="${module_name//-/_}"
                echo "$base_dir/$module_name/locale/$locale/LC_MESSAGES/django.po"
            fi
            ;;
        *-djangojs)
            if [ "$is_weblate" == "true" ]; then
                echo "$base_dir/$component/locale/$locale/LC_MESSAGES/djangojs.po"
            else
                # openstack-auth-djangojs -> openstack_auth/locale/djangojs.pot
                module_name="${component%-djangojs}"
                module_name="${module_name//-/_}"
                echo "$base_dir/$module_name/locale/$locale/LC_MESSAGES/djangojs.po"
            fi
            ;;
        "django")
            if [ "$is_weblate" == "true" ]; then
                echo "$base_dir/django/locale/$locale/LC_MESSAGES/django.po"
            else
                echo "$base_dir/$project_package_name/locale/$locale/LC_MESSAGES/django.po"
            fi
            ;;
        "djangojs")
            if [ "$is_weblate" == "true" ]; then
                echo "$base_dir/djangojs/locale/$locale/LC_MESSAGES/djangojs.po"
            else
                echo "$base_dir/$project_package_name/locale/$locale/LC_MESSAGES/djangojs.po"
            fi
            ;;
        "doc"|doc-*)
            if [ "$is_weblate" == "true" ]; then
                echo "$base_dir/$component/source/locale/$locale/LC_MESSAGES/$component.po"
            else
                echo "$base_dir/doc/source/locale/$locale/LC_MESSAGES/$component.po"
            fi
            ;;
        *)
            echo "$base_dir/$project_package_name/locale/$locale/LC_MESSAGES/$component.po"
            ;;
    esac
}


function sanitize_django_component {
    local component=$1
    
    if [[ "$component" == *"-django" ]]; then
        echo "django"
    elif [[ "$component" == *"-djangojs" ]]; then
        echo "djangojs"
    else
        echo "$component"
    fi
}

function get_module_name_from_component {
    local component=$1
    
    if [[ "$component" == *"-django" || "$component" == *"-djangojs" ]]; then
        # Extract module name from component (e.g., "horizon-django" -> "horizon")
        echo "${component%-django*}" | sed 's/-/_/g'
    else
        echo "$component"
    fi
}

function extract_locale_from_path {
    local translation_path=$1
    
    echo "$translation_path" | sed 's|.*/locale/\([^/]*\)/LC_MESSAGES/.*|\1|'
}

function get_po_file_path() {
    local component=$1
    local locale_file=$2
    local django_module_name=$3
    
    # Extract locale name from the full path
    # For paths like /path/to/locale/de/LC_MESSAGES/file.po, extract "de"
    local locale_name=$(echo "$locale_file" | sed 's|.*/locale/\([^/]*\)/LC_MESSAGES/.*|\1|')

    case $component in
        doc*)
            path="${TARGET_PROJECT_DIR}/translations/doc/source/locale/${locale_name}/LC_MESSAGES/${component}.po"
            echo "Doc PO path: $path" >&2
            echo "$path"
            ;;
        "*django"|"*djangojs"|"django"|"djangojs")
            # Django projects: use actual module name
            sanitized_component=$(sanitize_django_component $component)
            if [ -n "$django_module_name" ]; then
                path="${TARGET_PROJECT_DIR}/translations/${django_module_name}/locale/${locale_name}/LC_MESSAGES/${sanitized_component}.po"
                echo "Django PO path with module name: $path" >&2
                echo "$path"
            else
                path="${TARGET_PROJECT_DIR}/translations/${project_package_name}/locale/${locale_name}/LC_MESSAGES/${sanitized_component}.po"
                echo "Django PO path with package name: $path" >&2
                echo "$path"
            fi
            ;;
        "${PROJECT}")
            echo "${TARGET_PROJECT_DIR}/translations/${project_package_name}/locale/${locale_name}/LC_MESSAGES/${project_package_name}.po"
            ;;
        "releasenotes")
            # For releasenotes, locale_file should be the full path
            echo "${TARGET_PROJECT_DIR}/translations/releasenotes/source/locale/${locale_name}/LC_MESSAGES/${component}.po"
            ;;
        *)
            echo "${TARGET_PROJECT_DIR}/translations/${project_package_name}/locale/${locale_name}/LC_MESSAGES/${project_package_name}.po"
            ;;
    esac
}

function get_translation_path_list() {
    local component=$1
    local target_project_dir="$HOME/workspace/projects/$PROJECT/translations"
    local project_package_name="${PROJECT//-/_}"
    
    if [[ "$component" == "releasenotes" ]]; then
        # Special handling for releasenotes
        locale_list=($(find ${target_project_dir}/releasenotes -name "*.po" -path "*/locale/*/LC_MESSAGES/*.po" 2>/dev/null || echo ""))
    
    elif [[ "$component" == "django" ]]; then
        locale_list=($(find ${target_project_dir}/${project_package_name} -name "*.po" -path "*/locale/*/LC_MESSAGES/django.po" 2>/dev/null || echo ""))
    elif [[ "$component" == "djangojs" ]]; then
        locale_list=($(find ${target_project_dir}/${project_package_name} -name "*.po" -path "*/locale/*/LC_MESSAGES/djangojs.po" 2>/dev/null || echo ""))
    elif [[ "$component" == *"-django" || "$component" == *"-djangojs" ]]; then
        # Django components are saved as django.pot, djangojs.pot
        sanitized_component=$(sanitize_django_component $component)
        # Get the correct module name for this component
        correct_module_name=$(get_module_name_from_component $component)
        locale_list=($(find ${target_project_dir}/${correct_module_name} -name "*.po" -path "*/locale/*/LC_MESSAGES/${sanitized_component}.po" 2>/dev/null || echo ""))
    else
        locale_list=($(find ${target_project_dir} -name "*.po" -path "*/locale/*/LC_MESSAGES/${component}.po" 2>/dev/null || echo ""))
    fi

    echo "${locale_list[@]}"
}