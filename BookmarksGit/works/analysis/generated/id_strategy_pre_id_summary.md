# Pre-ID Strategy Summary

- candidates csv: `F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit\analysis\generated\definition_rgb_resolved_candidates_pre_id.csv`
- candidate inventory csv: `F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit\analysis\generated\current_id_candidate_inventory.csv`
- duplicate ids csv: `F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit\analysis\generated\id_duplicates_pre_id.csv`
- gap ranges csv: `F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit\analysis\generated\id_gap_ranges_pre_id.csv`
- candidate row count: `13261`
- unique current ID count: `12627`
- max current ID: `14696`
- duplicate current ID groups: `634`
- duplicate current ID rows: `1268`
- new IDs needed if one row per duplicate group keeps its old ID: `634`
- missing ID count from 1..max current ID: `2069`
- gap range count: `135`
- placeholder count needed to keep all unique old IDs contiguous up to max: `2069`

## Notes

- This summary describes the candidate set after RGB resolution but before final ID assignment.
- Duplicate IDs show how many rows cannot keep the same current ID simultaneously.
- Missing IDs show the placeholder burden if continuity is enforced while preserving unique existing IDs.

## Sample Duplicate ID Groups

- current ID `3222` appears `2` times
- current ID `9662` appears `2` times
- current ID `9667` appears `2` times
- current ID `9669` appears `2` times
- current ID `9670` appears `2` times
- current ID `9673` appears `2` times
- current ID `9674` appears `2` times
- current ID `9675` appears `2` times
- current ID `9679` appears `2` times
- current ID `9680` appears `2` times
- current ID `9682` appears `2` times
- current ID `9683` appears `2` times

## Sample Gap Ranges

- gap `383` -> `383` length `1`
- gap `397` -> `397` length `1`
- gap `402` -> `403` length `2`
- gap `408` -> `408` length `1`
- gap `413` -> `413` length `1`
- gap `418` -> `418` length `1`
- gap `455` -> `455` length `1`
- gap `622` -> `622` length `1`
- gap `631` -> `631` length `1`
- gap `952` -> `952` length `1`
- gap `955` -> `955` length `1`
- gap `1068` -> `1068` length `1`
