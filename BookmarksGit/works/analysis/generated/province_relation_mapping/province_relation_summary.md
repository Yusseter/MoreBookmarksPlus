# Province Relation Summary

- master rows: `4282`
- exact mapped rows: `100`
- split/merge rows: `3744`
- manual review rows: `4182`

## Classification Counts

- `exact`: `100`
- `manual_review`: `438`
- `merge`: `3288`
- `split`: `456`

## Notes

- Source subset is `modlu_dogu`; target subset is current final provinces traced from `orijinal_dogu`.
- Matching is identity-warp for this run because source and target province atlases already share dimensions.
- Only `exact` rows are marked `apply_to_history = yes`.
