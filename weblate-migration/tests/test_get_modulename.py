# Copyright (c) 2026 OpenStack Korea User Group
#
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

import importlib.util
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


MODULE_PATH = (
    Path(__file__).resolve().parents[1]
    / '03-prepare-component-name'
    / 'get_modulename.py'
)
SPEC = importlib.util.spec_from_file_location('get_modulename', MODULE_PATH)
get_modulename = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(get_modulename)


class GetModuleNameTest(unittest.TestCase):
    def test_cli_prefers_pulled_django_pot_over_translation_metadata(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_path = Path(temp_dir)
            config_path = temp_path / 'setup.cfg'
            config_path.write_text(
                '[openstack_translations]\n'
                'django_modules = stale_dashboard\n',
                encoding='utf-8',
            )
            pot_path = (
                temp_path / 'pot' / 'bgpvpn_dashboard' / 'locale'
                / 'django.pot'
            )
            pot_path.parent.mkdir(parents=True)
            pot_path.touch()

            result = subprocess.run(
                [
                    sys.executable,
                    str(MODULE_PATH),
                    '-p', 'networking-bgpvpn',
                    '-t', 'django',
                    '-f', str(config_path),
                    '--pot-dir', str(temp_path / 'pot'),
                ],
                check=False,
                capture_output=True,
                text=True,
            )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual('bgpvpn_dashboard', result.stdout.strip())

    def test_uses_setup_cfg_packages_without_pot_directory(self):
        config = {
            'files': {
                'packages': 'legacy_dashboard\nsecond_dashboard',
            },
        }

        modules = get_modulename.get_valid_modules(
            config, 'example-dashboard', 'django')

        self.assertEqual(
            ['legacy_dashboard', 'second_dashboard'], modules)

    def test_uses_pot_module_when_name_differs_from_project_slug(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            pot_path = (
                Path(temp_dir)
                / 'unrelated_package'
                / 'locale'
                / 'django.pot'
            )
            pot_path.parent.mkdir(parents=True)
            pot_path.touch()

            modules = get_modulename.get_valid_modules(
                {}, 'example-dashboard', 'django', temp_dir)

        self.assertEqual(['unrelated_package'], modules)

    def test_uses_django_pot_for_project_without_django_name_suffix(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            pot_path = Path(temp_dir) / 'web_console' / 'locale' / 'django.pot'
            pot_path.parent.mkdir(parents=True)
            pot_path.touch()

            modules = get_modulename.get_valid_modules(
                {}, 'unexpected-project-name', 'django', temp_dir)

        self.assertEqual(['web_console'], modules)

    def test_pot_modules_filter_stale_metadata_and_keep_multiple_modules(self):
        config = {
            'files': {
                'packages': 'stale_package\nfirst_dashboard',
            },
        }
        with tempfile.TemporaryDirectory() as temp_dir:
            pot_dir = Path(temp_dir)
            for module_name, pot_name in (
                    ('first_dashboard', 'django.pot'),
                    ('second_dashboard', 'djangojs.pot')):
                pot_path = pot_dir / module_name / 'locale' / pot_name
                pot_path.parent.mkdir(parents=True)
                pot_path.touch()

            modules = get_modulename.get_valid_modules(
                config, 'example-dashboard', 'django', temp_dir)

        self.assertEqual(
            ['first_dashboard', 'second_dashboard'], modules)

    def test_deduplicates_module_with_django_and_djangojs_pots(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            locale_dir = Path(temp_dir) / 'dashboard' / 'locale'
            locale_dir.mkdir(parents=True)
            (locale_dir / 'django.pot').touch()
            (locale_dir / 'djangojs.pot').touch()

            modules = get_modulename.get_django_pot_modules(temp_dir)

        self.assertEqual(['dashboard'], modules)

    def test_does_not_guess_django_module_when_pot_directory_is_empty(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            modules = get_modulename.get_valid_modules(
                {}, 'neutron-fwaas-dashboard', 'django', temp_dir)

        self.assertEqual([], modules)

    def test_non_django_target_is_ignored_for_dashboard_project(self):
        modules = get_modulename.get_valid_modules(
            {}, 'neutron-fwaas-dashboard', 'python')

        self.assertEqual([], modules)


if __name__ == '__main__':
    unittest.main()
