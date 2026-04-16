# Definition Policy Draft Summary

- preserve draft: `F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit\analysis\generated\definition_policy_preserve_old_draft.csv`
- full renumber draft: `F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit\analysis\generated\definition_policy_full_renumber_draft.csv`
- validation csv: `F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit\analysis\generated\definition_policy_draft_validation.csv`

## Validation

- preserve_old_ids -> data rows `14696`, max id `14696`, placeholders `1435`, duplicate RGB `0`, missing IDs `0`, contiguous `True`
- full_renumber -> data rows `13261`, max id `13261`, placeholders `0`, duplicate RGB `0`, missing IDs `0`, contiguous `True`

## Notes

- Both drafts emit `0;0;0;0;x;x` as the reserved first line.
- Drafts are generated under `analysis/generated/` only and do not overwrite live map_data definitions.
- RGB uniqueness here is checked against the draft rows themselves after the earlier RGB-resolution stage.
