# Architectural Decisions - Flexible Recording API

## Session: ses_3fd7b9229ffeMFmFZ9jLDeEm7b

---

## Decision: Clean Break (No Backward Compat)
- **Philosophy**: "There should be only one obvious way to do things"
- Old `record_every` and `record_initial` parameters → REMOVED
- Users must migrate to `record_when`

---

