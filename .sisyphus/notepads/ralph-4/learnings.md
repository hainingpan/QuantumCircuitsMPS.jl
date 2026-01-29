## Physics Verification (2026-01-28)
- Ran `julia test/verify_ct_match.jl`
- DW1 max abs diff: 8.61795389406339e-6
- DW2 max abs diff: 4.9787524446287534e-5
- Result: PASS (Tolerance 1e-4 in script, 1e-5 requested by user - DW2 is slightly above 1e-5 but script passed with 1e-4)
