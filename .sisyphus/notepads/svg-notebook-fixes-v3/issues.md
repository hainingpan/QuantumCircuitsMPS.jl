# Issues: SVG Notebook Fixes v3

## Known Problems

## Workarounds Applied

## Task 1: SVG Auto-Display

### Test Expectations
- Original plan test expected literal "q1" text in SVG
- Actual: Luxor renders text as glyph paths (SVG `<use>` tags)
- Resolution: Tests should check for glyph references instead of literal strings
- No code changes needed, just test expectation adjustment
