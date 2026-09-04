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

from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT_PATH = (
    Path(__file__).resolve().parents[1]
    / 'common'
    / 'get_translation_path.sh'
)


class DjangoTranslationPathTest(unittest.TestCase):
    def run_function(self, home_dir, function_call):
        return subprocess.run(
            [
                'bash', '-c',
                'HOME="$2"; WORKSPACE_NAME=workspace; '
                'PROJECT=networking-bgpvpn; source "$1"; eval "$3"',
                '_', str(SCRIPT_PATH), str(home_dir), function_call,
            ],
            check=False,
            capture_output=True,
            text=True,
        )

    def create_pulled_catalog(self, home_dir, module_name, catalog_name):
        pot_path = (
            Path(home_dir) / 'workspace' / 'projects' / 'networking-bgpvpn'
            / 'pot' / module_name / 'locale' / f'{catalog_name}.pot'
        )
        pot_path.parent.mkdir(parents=True, exist_ok=True)
        pot_path.touch()
        return pot_path

    def test_generic_django_component_uses_unique_pulled_module(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            expected = self.create_pulled_catalog(
                temp_dir, 'bgpvpn_dashboard', 'django')

            result = self.run_function(temp_dir, 'get_pot_path django')

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(str(expected), result.stdout.strip())

    def test_generic_django_component_finds_module_translations(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            self.create_pulled_catalog(
                temp_dir, 'bgpvpn_dashboard', 'django')
            expected = (
                Path(temp_dir) / 'workspace' / 'projects'
                / 'networking-bgpvpn' / 'translations'
                / 'bgpvpn_dashboard' / 'locale' / 'fr' / 'LC_MESSAGES'
                / 'django.po'
            )
            expected.parent.mkdir(parents=True)
            expected.touch()

            result = self.run_function(
                temp_dir, 'get_translation_path_list django')

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(str(expected), result.stdout.strip())

    def test_project_package_path_remains_preferred_when_present(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            expected = self.create_pulled_catalog(
                temp_dir, 'networking_bgpvpn', 'django')
            self.create_pulled_catalog(
                temp_dir, 'bgpvpn_dashboard', 'django')

            result = self.run_function(temp_dir, 'get_pot_path django')

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(str(expected), result.stdout.strip())

    def test_ambiguous_fallback_keeps_existing_missing_path_behavior(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            self.create_pulled_catalog(temp_dir, 'first_dashboard', 'django')
            self.create_pulled_catalog(temp_dir, 'second_dashboard', 'django')
            expected = (
                Path(temp_dir) / 'workspace' / 'projects'
                / 'networking-bgpvpn' / 'pot' / 'networking_bgpvpn'
                / 'locale' / 'django.pot'
            )

            result = self.run_function(temp_dir, 'get_pot_path django')

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertEqual(str(expected), result.stdout.strip())


if __name__ == '__main__':
    unittest.main()
