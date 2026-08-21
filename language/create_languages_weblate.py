#!/usr/bin/env python3
# -*- coding: utf-8 -*-
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
"""
Weblate batch language create/update script
- Input1: code -> plural-forms map (JSON)
- Input2: Zanata locales JSON (array)

Behavior:
  * If a language does not exist → create (code/name/plural formula)
  * If a language exists → apply diff only for name/plural via PATCH
Priority:
  * plural: input1 (user json) > Zanata pluralForms > skip if none
  * name: Zanata displayName > nativeName > fallback to code

Other:
  * Code normalization: force '-' → '_' (e.g., tr-TR → tr_TR)
  * RTL candidate languages get direction=rtl when created
  * Default is dry-run, use --apply for real changes
"""

import argparse
import json
import re
from typing import Any
from typing import Dict
from typing import Optional
from typing import Tuple

from weblate.weblate_utils import IniConfig
from weblate.weblate_utils import WeblateRestService


def normalize_code(code: str) -> str:
    if not code:
        return ""
    normalized = code.strip().replace("-", "_")
    return normalized[0].lower() + normalized[1:] if normalized else normalized


def parse_plural_forms(pf: str) -> Optional[Tuple[int, str]]:
    if not pf:
        return None
    s = pf.strip().rstrip(";")
    m_num = re.search(r"nplurals\s*=\s*(\d+)", s, re.IGNORECASE)
    m_for = re.search(r"plural\s*=\s*([^;]+)", s, re.IGNORECASE)
    if not (m_num and m_for):
        return None
    number = int(m_num.group(1))
    formula = m_for.group(1).strip()
    if formula.startswith("(") and formula.endswith(")"):
        formula = formula[1:-1].strip()
    formula = formula.rstrip(";").strip()
    if not formula or formula.count("(") != formula.count(")"):
        return None
    return number, formula


def load_plural_map(path: str) -> Dict[str, str]:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    out: Dict[str, str] = {}
    if isinstance(data, dict):
        for k, v in data.items():
            if isinstance(v, str):
                out[normalize_code(k)] = v.strip()
    elif isinstance(data, list):
        for item in data:
            if isinstance(item, dict):
                if "code" in item and ("plural" in item or
                                       "plural_equation" in item):
                    pf = item.get("plural") or item.get("plural_equation")
                    if isinstance(pf, str):
                        out[normalize_code(item["code"])] = pf.strip()
                else:
                    for k, v in item.items():
                        if isinstance(v, str):
                            out[normalize_code(k)] = v.strip()
    else:
        raise ValueError("Unsupported JSON format (Plural Map)")
    return out


def load_zanata_locales(path: str) -> Dict[str, Dict[str, Any]]:
    with open(path, "r", encoding="utf-8") as f:
        arr = json.load(f)
    if not isinstance(arr, list):
        raise ValueError("Zanata JSON must be an array.")
    out: Dict[str, Dict[str, Any]] = {}
    rtl_langs = {"ar", "fa", "he", "ur", "ug", "dv", "ps", "ku_Arab"}
    for it in arr:
        if not isinstance(it, dict):
            continue

        raw = it.get("localeId") or it.get("id") or ""
        code = normalize_code(raw)

        if not code:
            continue

        disp = (it.get("displayName") or "").strip()
        native = (it.get("nativeName") or "").strip()
        name = disp or native or code
        pf = (it.get("pluralForms") or "").strip()
        base = code.split("_", 1)[0]
        rtl = base in rtl_langs
        out[code] = {"name": name, "rtl": rtl, "pluralForms": pf}
    return out


def main():
    p = argparse.ArgumentParser(
        description="Weblate language create/update via weblate_utils"
    )
    p.add_argument("-i", "--input", required=True, help="Plural-Form map JSON")
    p.add_argument("-z", "--zanata", required=True, help="Zanata locales JSON")
    p.add_argument(
        "--ini",
        default="weblate.ini",
        help="Path to weblate.ini (default: weblate.ini)"
    )
    p.add_argument(
        "--apply",
        action="store_true",
        help="Apply real changes to Weblate"
    )
    args = p.parse_args()

    config = IniConfig(args.ini)
    svc = WeblateRestService(config)

    plural_map = load_plural_map(args.input)
    zanata_map = load_zanata_locales(args.zanata)
    print(f"=Plan=\n- plural: {len(plural_map)}\n- zanata : {len(zanata_map)}")
    print(f"- Mode: {'Apply changes' if args.apply else 'Dry-run'}\n")

    created = updated = skipped = failed = 0
    failures = []

    for code, zinfo in zanata_map.items():
        name = (zinfo.get("name") or code).strip()
        direction = "rtl" if zinfo.get("rtl") else None
        pf_str = plural_map.get(code)
        if not pf_str:
            base = code.split("_", 1)[0]
            pf_str = plural_map.get(base, "")
            if pf_str:
                print(f"  · {code}: inherit plural from base language {base}")

        parsed = parse_plural_forms(pf_str or "")
        if not parsed:
            skipped += 1
            continue
        num, formula = parsed

        fragment = f"/api/languages/{code}/"
        resp = svc.query(fragment, raise_errors=False)

        if resp.status_code == 200:
            data = resp.json()
            cur = data.get("plural") or {}
            cur_num = cur.get("number")
            cur_for = (cur.get("formula") or "").strip()
            cur_name = (data.get("name") or "").strip()
            need_name = (name and name != cur_name)
            need_plural = not (cur_num == num and cur_for == formula)

            print(f"- {code}: update name={cur_name!r}->{name!r}")
            print(f"  plural={cur_num}/{cur_for} -> {num}/{formula}")
            if args.apply and (need_name or need_plural):
                payload: Dict[str, Any] = {}
                if need_name:
                    payload["name"] = name
                if need_plural:
                    payload["plural"] = {"number": num, "formula": formula}
                r2 = svc.push(fragment, payload)
                if r2.status_code in (200, 202):
                    updated += 1
                else:
                    failed += 1
                    failures.append((code, r2.status_code, r2.text[:300]))
            else:
                updated += 1

        elif resp.status_code == 404:
            if args.apply:
                payload = {
                    "code": code,
                    "name": name,
                    "plural": {"number": num, "formula": formula},
                }
                if direction:
                    payload["direction"] = direction
                r3 = svc.post("/api/languages/", payload)
                if r3.status_code in (200, 201):
                    created += 1
                else:
                    failed += 1
                    failures.append((code, r3.status_code, r3.text[:300]))
            else:
                created += 1
        else:
            print(f"- {code}: lookup failed HTTP {resp.status_code}")
            failed += 1
            failures.append((code, resp.status_code, "lookup_failed"))

    if failures:
        print("\nFailures detail:")
        for code, s, body in failures[:30]:
            print(f"  - {code}: HTTP {s} body={body}")


if __name__ == "__main__":
    main()
