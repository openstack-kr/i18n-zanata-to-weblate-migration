---
name: Migration accuracy issue
about: The script succeeded, but the Zanata source and Weblate result differ (see docs/horizon-test.md for the report format)
title: "[Accuracy] "
labels: accuracy
assignees: ""
---

## Target

- project:
- version (branch):
- component:
- locale:

## Type of Issue

<!-- Check all that apply. -->

- [ ] Translations missing entirely or partially
- [ ] Fuzzy flag lost
- [ ] Plural structure lost
- [ ] Other (describe below)

## Zanata Source vs. Weblate Result

<!-- Follow the table format used in docs/horizon-test.md. -->

| Item | Zanata | Weblate |
|---|---|---|
| Total entries | | |
| Translated | | |
| Untranslated | | |
| Plural entries | | |

### Example msgid/msgstr Comparison

```po
msgid "..."

# Zanata source
msgstr "..."

# Weblate result
msgstr "..."
```

## Number of Affected Entries

<!-- How many entries were affected in this locale/component? -->

## Additional Context

<!-- Relevant logs, comparison with docs/horizon-test.md, related issues/PRs, etc. -->
