# Migration Tools from Zanata to Weblate

This folder provides tools to migrate translation projects from Zanata
to Weblate.

> **Note:** The tool currently works with horizon and plugin projects.

## Background

OpenStack I18n team has been using
[Zanata](https://github.com/zanata/zanata-platform)
as translation platform, which development and release is discountinued
from August 2018.
To ensure continued translation management and improve OpenStack
internationalization workflow, OpenStack I18n SIG is migrating
Zanata projects to Weblate.

## Objectives

* Preserve existing translation structure and format as much as possible

## Migration Workflow

1. Set up the workspace.
2. Generate POT files from cloned project repositories.
3. Create `zanata.xml` and export translations (PO files) from Zanata.
4. Create a Weblate project, category, and component.
5. Create translations and upload a translation file for each locale.

## How to use

1. Clone the repository
2. Run the migration script:

* single project migration:

```bash
./migration_resources.sh <project_name> <version> <workspace_name>
```

Arguments:

* project_name: The name of the OpenStack project to migrate.
* version: The version of the project. The default is "master".
  e.g. stable-2025.1
* workspace_name: The folder name for the migration workspace.
  It will be installed in the home directory. The default is "workspace".

* project group migration:

```bash
./migration_projects.sh <project_list.txt> <version_list.txt>
```

Arguments:

* project_list.txt: The text file containing the list of projects to migrate.
  Each line is a project name.

  example:

  ```text
  designate-dashboard
  freezer-web-ui
  ```

* version_list.txt: The text file containing the list of versions to migrate.
  Each line is a version name.
  The version name should be the same as the branch name in the project repository.

  example:

  ```text
  master
  stable/2025.2
  ```

## Logs

The log folder(/log) is created in the current repository directory.

* project.{timestamp}.log: The log file for the project migration.
* error.{timestamp}.log: The error log file for the project migration.

The timestamp is the current time of migration start. The format is HHMMSS.

```text
├── log/
│   └── <project_name>/
│       └── project.{timestamp}.log
│       └── error.{timestamp}.log
```

## Folder and File Structure

```text
├── common/
├── 01-setup-env/
├── 02-prepare-translations/
├── 03-prepare-component-name/
├── 04-prepare-weblate-components/
├── 05-test-accuracy/
├── migration_resources.sh
└── migration_projects.sh
```

* common/: Shared utilities used across multiple migration stages
  (Weblate API calls, PO/POT path resolution, colorized stage output).
* 01-setup-env/: Creates a virtual environment, installs dependencies,
  and sets up a workspace folder for migration tasks.
* 02-prepare-translations/: Clones the project, generates POT files, and
  exports translations (PO files) from Zanata.
* 03-prepare-component-name/: Detects the Weblate component name for
  each translated module.
* 04-prepare-weblate-components/: Creates the Weblate project, category,
  and component, and uploads translations.
* 05-test-accuracy/: Verifies migrated translations against the source.
* migration_resources.sh / migration_projects.sh: Entry points that run
  the stages above in order, for a single project or a project group.

Log format is:

```text
// project | category | component | locale | message
horizon | stable/2025.2 | openstack-dashboard-django | mai | [INFO] Testing locale: mai
horizon | stable/2025.2 | openstack-dashboard-django | mai | [INFO] Step 1/2: Check the sentence count...
horizon | stable/2025.2 | openstack-dashboard-django | mai | [INFO] ✓ Count matched(translated/total): 73/177
horizon | stable/2025.2 | openstack-dashboard-django | mai | [INFO] Step 2/2: Check the sentence detail...
horizon | stable/2025.2 | openstack-dashboard-django | mai | [INFO] ✓ Sentence detail matched: 177 entries
```

`component`/`locale` are `-` for lines from stages before a
component/locale is determined (e.g. clone, POT generation).

> **Note:** The current tool mainly focuses on translation resource
> migration, and actual resource migration process currently requires
> careful supervision to make sure that each migration step is performed
> well or not.

## Workspace Structure

By default, the migration workspace is installed to your home directory
with the following folder structure:

> **Note:** You can change the base directory by manually setting
> WORK_DIR on 01-setup-env/setup.sh.

* .venv/: Python virtual environment containing migration dependencies
* projects/: Migration workspace
  * \<project_name>/: Project-specific workspace
    * \<cloned_project_name>/: Cloned project repository
    * pot/: POT files for each component
    * translations/: Exported translations from Zanata

Directory Layout:

```text
<workspace_name>/
├── .venv/
└── projects/
    └── <project_name>/
        ├── <cloned_project_name>/
        ├── pot/
        └── translations/
```
