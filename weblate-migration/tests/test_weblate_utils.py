# Copyright (c) 2026 OpenStack Korea User Group
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may
# not use this file except in compliance with the License. You may obtain
# a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0

import importlib.util
from pathlib import Path
from types import SimpleNamespace
import unittest
from unittest import mock


MODULE_PATH = (
    Path(__file__).resolve().parents[1] / 'common' / 'weblate_utils.py'
)
SPEC = importlib.util.spec_from_file_location('weblate_utils', MODULE_PATH)
weblate_utils = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(weblate_utils)


def make_response(status_code, data):
    response = mock.Mock()
    response.status_code = status_code
    response.json.return_value = data
    response.text = str(data)
    return response


class WeblateUtilsReadinessTest(unittest.TestCase):
    def setUp(self):
        config = SimpleNamespace(
            token='test-token',
            base_url='https://weblate.example/',
        )
        self.utils = weblate_utils.WeblateUtils(config)

    def _write_po(self, content):
        po_path = Path(
            f'{self.id().replace(".", "-")}-{id(content)}'
        ).with_suffix('.po')
        self.addCleanup(po_path.unlink, missing_ok=True)
        po_path.write_text(content, encoding='utf-8')
        return po_path

    def test_create_translation_returns_when_source_strings_are_ready(self):
        po_path = self._write_po(
            'msgid ""\nmsgstr ""\n'
            '"Plural-Forms: nplurals=2; plural=(n != 1);\\n"\n\n'
            'msgid "first"\nmsgstr ""\n'
        )
        state = {
            'created': False,
            'ready': False,
            'readiness_checks': 0,
        }

        def get_translation(url, headers=None, params=None):
            if not state['created']:
                return make_response(404, {'detail': 'Not found.'})

            state['readiness_checks'] += 1
            if state['readiness_checks'] == 1:
                return make_response(200, {'total': 0})

            state['ready'] = True
            return make_response(200, {'total': 1260})

        def create_translation(url, json=None, headers=None):
            state['created'] = True
            return make_response(201, {})

        with (
            mock.patch.object(
                weblate_utils.requests, 'get', side_effect=get_translation
            ),
            mock.patch.object(
                weblate_utils.requests, 'post', side_effect=create_translation
            ),
            mock.patch.object(weblate_utils.time, 'sleep'),
        ):
            self.utils.create_translation(
                'neutron', 'master', 'releasenotes', 'fr', str(po_path)
            )

        self.assertTrue(state['ready'])

    def test_create_translation_stops_on_non_retryable_error(self):
        po_path = self._write_po(
            'msgid ""\nmsgstr ""\n'
            '"Plural-Forms: nplurals=2; plural=(n != 1);\\n"\n\n'
            'msgid "first"\nmsgstr ""\n'
        )
        state = {
            'created': False,
            'readiness_checks': 0,
        }

        def get_translation(url, headers=None, params=None):
            if not state['created']:
                return make_response(404, {'detail': 'Not found.'})

            state['readiness_checks'] += 1
            return make_response(401, {'detail': 'Unauthorized.'})

        def create_translation(url, json=None, headers=None):
            state['created'] = True
            return make_response(201, {})

        with (
            mock.patch.object(
                weblate_utils.requests, 'get', side_effect=get_translation
            ),
            mock.patch.object(
                weblate_utils.requests, 'post', side_effect=create_translation
            ),
            mock.patch.object(weblate_utils.time, 'sleep'),
        ):
            with self.assertRaises(SystemExit):
                self.utils.create_translation(
                    'neutron', 'master', 'releasenotes', 'fr', str(po_path)
                )

        self.assertEqual(state['readiness_checks'], 1)

    def test_create_translation_waits_for_plural_slots_to_fill(self):
        po_path = self._write_po(
            'msgid ""\nmsgstr ""\n'
            '"Plural-Forms: nplurals=2; plural=(n != 1);\\n"\n\n'
            'msgid "Delete Volume"\nmsgid_plural "Delete Volumes"\n'
            'msgstr[0] ""\nmsgstr[1] ""\n'
        )
        state = {
            'created': False,
            'plural_checks': 0,
            'ready': False,
        }

        def get_translation(url, headers=None, params=None):
            if not state['created']:
                return make_response(404, {'detail': 'Not found.'})

            if url.endswith(
                    '/translations/neutron/master%252Freleasenotes/fr/'):
                return make_response(200, {
                    'total': 1,
                    'language': {'plural': {'number': 2}},
                })

            if '/units/' in url:
                state['plural_checks'] += 1
                if state['plural_checks'] == 1:
                    target = ['']
                else:
                    state['ready'] = True
                    target = ['', '']
                return make_response(200, {
                    'results': [{'target': target}],
                })

            self.fail(f'Unexpected GET: {url}')

        def create_translation(url, json=None, headers=None):
            state['created'] = True
            return make_response(201, {})

        with (
            mock.patch.object(
                weblate_utils.requests, 'get', side_effect=get_translation
            ),
            mock.patch.object(
                weblate_utils.requests, 'post', side_effect=create_translation
            ),
            mock.patch.object(weblate_utils.time, 'sleep'),
        ):
            self.utils.create_translation(
                'neutron', 'master', 'releasenotes', 'fr', str(po_path)
            )

        self.assertTrue(state['ready'])

    def test_create_translation_waits_for_all_plural_units_across_pages(
            self):
        po_path = self._write_po(
            'msgid ""\nmsgstr ""\n'
            '"Plural-Forms: nplurals=2; plural=(n != 1);\\n"\n\n'
            'msgid "Delete Volume"\nmsgid_plural "Delete Volumes"\n'
            'msgstr[0] ""\nmsgstr[1] ""\n'
            '\nmsgid "Delete Item"\nmsgid_plural "Delete Items"\n'
            'msgstr[0] ""\nmsgstr[1] ""\n'
        )
        page_two_url = (
            'https://weblate.example/translations/neutron/'
            'master%252Freleasenotes/fr/units/?q=has%3Aplural&page=2'
        )
        state = {
            'created': False,
            'page_two_checks': 0,
            'ready': False,
        }

        def get_translation(url, headers=None, params=None):
            if not state['created']:
                return make_response(404, {'detail': 'Not found.'})

            if url.endswith(
                    '/translations/neutron/master%252Freleasenotes/fr/'):
                return make_response(200, {
                    'total': 2,
                    'language': {'plural': {'number': 2}},
                })

            if url == page_two_url:
                state['page_two_checks'] += 1
                if state['page_two_checks'] == 1:
                    target = ['']
                else:
                    state['ready'] = True
                    target = ['', '']
                return make_response(200, {'results': [{'target': target}]})

            if '/units/' in url:
                # First page: its own unit is already full, but a
                # second page (not yet ready) still exists - a
                # correct implementation must not stop here.
                return make_response(200, {
                    'results': [{'target': ['', '']}],
                    'next': page_two_url,
                })

            self.fail(f'Unexpected GET: {url}')

        def create_translation(url, json=None, headers=None):
            state['created'] = True
            return make_response(201, {})

        with (
            mock.patch.object(
                weblate_utils.requests, 'get', side_effect=get_translation
            ),
            mock.patch.object(
                weblate_utils.requests, 'post', side_effect=create_translation
            ),
            mock.patch.object(weblate_utils.time, 'sleep'),
        ):
            self.utils.create_translation(
                'neutron', 'master', 'releasenotes', 'fr', str(po_path)
            )

        self.assertTrue(state['ready'])
        self.assertGreaterEqual(state['page_two_checks'], 2)

    def test_create_component_returns_when_whole_pot_is_imported(self):
        pot_path = Path(self.id().replace('.', '-')).with_suffix('.pot')
        self.addCleanup(pot_path.unlink, missing_ok=True)
        pot_path.write_text(
            'msgid "first"\nmsgstr ""\n\n'
            'msgid "second"\nmsgstr ""\n',
            encoding='utf-8',
        )

        state = {
            'created': False,
            'ready': False,
            'source_checks': 0,
        }

        def get_component(url, headers=None, params=None):
            if '/components/' in url:
                return make_response(404, {'detail': 'Not found.'})
            if url.endswith('/projects/neutron/categories/'):
                return make_response(
                    200,
                    {'results': [{'name': 'master', 'id': 17}]},
                )
            if url.endswith('/translations/neutron/'
                            'master%252Freleasenotes/en_US/'):
                state['source_checks'] += 1
                if state['source_checks'] == 1:
                    return make_response(200, {'total': 1})

                state['ready'] = True
                return make_response(200, {'total': 2})
            self.fail(f'Unexpected GET: {url}')

        def create_component(url, data=None, files=None, headers=None):
            state['created'] = True
            return make_response(201, {})

        with (
            mock.patch.object(
                weblate_utils.requests, 'get', side_effect=get_component
            ),
            mock.patch.object(
                weblate_utils.requests, 'post', side_effect=create_component
            ),
            mock.patch.object(weblate_utils.time, 'sleep'),
        ):
            self.utils.create_component(
                'neutron', 'master', 'releasenotes', str(pot_path)
            )

        self.assertTrue(state['created'])
        self.assertTrue(state['ready'])


if __name__ == '__main__':
    unittest.main()
