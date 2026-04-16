# ID Policy Draft Summary

## Generated Files

- preserve assignments: `F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit\analysis\generated\id_policy_preserve_old_assignments.csv`
- preserve placeholders: `F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit\analysis\generated\id_policy_preserve_old_placeholders.csv`
- preserve mod map: `F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit\analysis\generated\id_map_modlu_preserve_old.csv`
- preserve orijinal map: `F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit\analysis\generated\id_map_orijinal_preserve_old.csv`
- full renumber assignments: `F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit\analysis\generated\id_policy_full_renumber_assignments.csv`
- full renumber mod map: `F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit\analysis\generated\id_map_modlu_full_renumber.csv`
- full renumber orijinal map: `F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit\analysis\generated\id_map_orijinal_full_renumber.csv`
- source burden csv: `F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit\analysis\generated\id_policy_source_burden.csv`

## Policy A: Preserve Old IDs (Draft)

- intent: keep as many existing IDs as possible
- tie-break for duplicate ID groups: prefer `modlu_kalan`, then deterministic lexical order
- candidate rows keeping current ID: `12627`
- candidate rows getting new ID: `634`
- displaced duplicate rows reassigned into existing gaps: `634`
- displaced duplicate rows appended after max old ID: `0`
- placeholder rows still required for contiguity: `1435`
- final max ID under policy A: `14696`
- changed modlu_kalan rows: `0`
- changed orijinal_dogu rows: `634`

## Policy B: Full Renumber (Draft)

- intent: assign dense contiguous IDs to real rows only
- ordering: current_id asc, then preferred source subset priority, then deterministic lexical order
- candidate rows keeping current ID by coincidence: `615`
- candidate rows changing ID: `12646`
- placeholder rows required: `0`
- final max ID under policy B: `13261`
- changed modlu_kalan rows: `9508`
- changed orijinal_dogu rows: `3138`

## Notes

- Neither draft writes into actual game definition files yet.
- Both drafts keep provenance fields through the source-specific ID maps.
- Policy A minimizes changed IDs but still leaves a substantial placeholder burden.
- Policy B maximizes renumbering but removes the placeholder burden completely.

## Sample Preserve-Policy Rows

- final `1` <= current `1` `VESTFIRDIR`
- final `2` <= current `2` `REYKJAVIK`
- final `3` <= current `3` `STOKKSEYRI`
- final `4` <= current `4` `REYDARFJALL`
- final `5` <= current `5` `HUSAVIK`
- final `6` <= current `6` `TORSHAVN`
- final `7` <= current `7` `SCALLOWAY`
- final `8` <= current `8` `KIRKWALL`
- final `9` <= current `9` `DONEGAL`
- final `10` <= current `10` `RAPHOE`
- final `11` <= current `11` `FAHAN`
- final `12` <= current `12` `DERRY`

## Sample Full-Renumber Rows

- final `1` <= current `1` `VESTFIRDIR`
- final `2` <= current `2` `REYKJAVIK`
- final `3` <= current `3` `STOKKSEYRI`
- final `4` <= current `4` `REYDARFJALL`
- final `5` <= current `5` `HUSAVIK`
- final `6` <= current `6` `TORSHAVN`
- final `7` <= current `7` `SCALLOWAY`
- final `8` <= current `8` `KIRKWALL`
- final `9` <= current `9` `DONEGAL`
- final `10` <= current `10` `RAPHOE`
- final `11` <= current `11` `FAHAN`
- final `12` <= current `12` `DERRY`
