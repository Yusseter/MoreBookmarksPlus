# Definition Subset Audit

## Generated Files

- `map_data/definition_modlu_dogu.csv`
- `map_data/definition_modlu_kalan.csv`
- `map_data/definition_orijinal_dogu.csv`
- `map_data/definition_orijinal_kalan.csv`
- `analysis/generated/definition_rgb_conflicts.csv`
- `analysis/generated/definition_rgb_conflict_decisions.csv`
- `analysis/generated/rgb_mapping_draft.csv`
- `analysis/generated/rgb_conflict_previews/`
- `analysis/generated/definition_id_conflicts.csv`
- `analysis/generated/definition_shared_same_id.csv`
- `analysis/generated/definition_quality_flags.csv`
- `analysis/generated/definition_merge_inventory.csv`
- `analysis/generated/definition_id_tracking.csv`
- `analysis/generated/definition_subset_validation.csv`
- `analysis/generated/definition_modlu_dogu_rgb_inventory.csv`
- `analysis/generated/definition_modlu_kalan_rgb_inventory.csv`
- `analysis/generated/definition_orijinal_dogu_rgb_inventory.csv`
- `analysis/generated/definition_orijinal_kalan_rgb_inventory.csv`

## Subset Extraction Summary

- `modlu_dogu`: image colors `4282`, extracted rows `4282`, missing in definition `0`
- `modlu_kalan`: image colors `9891`, extracted rows `9891`, missing in definition `0`
- `orijinal_dogu`: image colors `3391`, extracted rows `3391`, missing in definition `0`
- `orijinal_kalan`: image colors `9365`, extracted rows `9365`, missing in definition `0`

## Subset Validation Rerun

- `modlu_dogu` validation pass: `True`
- `modlu_kalan` validation pass: `True`
- `orijinal_dogu` validation pass: `True`
- `orijinal_kalan` validation pass: `True`

## Merge Audit Summary

- benign shared rows (`same RGB + same ID`): `21`
- benign shared rows with same name: `6`
- benign shared rows with different name/comment: `15`
- RGB conflicts (`same RGB + different ID`): `119`
- RGB decision rows (`pending_manual_rgb_resolution`): `119`
- ID conflicts (`different RGB + same ID`): `634`
- quality-flagged rows: `188`
- rows with empty name: `161`
- rows with placeholder-like name: `163`
- rows needing manual ID assignment review: `1271`

## Notes

- `definition_id_tracking.csv` is the forward-looking sheet for future ID reassignment work.
- `final_new_id` is intentionally blank for now because no final merge policy has been applied yet.
- When a row later receives a new ID, that sheet should be the source of truth for updating province-referencing game files.
- `definition_rgb_conflict_decisions.csv` is the manual decision scaffold for the 119 `same RGB + different ID` conflicts.
- `rgb_mapping_draft.csv` is a non-final draft mapping generated from the current recolor-side heuristic.
- `rgb_conflict_previews/` contains per-conflict crop previews for the modlu and orijinal sides.
- ID conflicts should be solved with new final IDs plus provenance tracking; placeholder provinces do not solve those identity collisions by themselves.

## Sample RGB Conflicts

- RGB `51,135,178` -> modlu ID `9701` / orijinal ID `9803`
- RGB `93,183,186` -> modlu ID `9717` / orijinal ID `9757`
- RGB `135,186,59` -> modlu ID `9718` / orijinal ID `9815`
- RGB `135,201,189` -> modlu ID `9723` / orijinal ID `9816`
- RGB `9,9,65` -> modlu ID `9730` / orijinal ID `9846`
- RGB `177,21,67` -> modlu ID `9734` / orijinal ID `9850`
- RGB `9,24,195` -> modlu ID `9735` / orijinal ID `9851`
- RGB `51,57,73` -> modlu ID `9746` / orijinal ID `9785`
- RGB `93,105,81` -> modlu ID `9762` / orijinal ID `9781`
- RGB `93,57,136` -> modlu ID `9817` / orijinal ID `9838`
- RGB `51,69,138` -> modlu ID `9821` / orijinal ID `9843`
- RGB `135,75,139` -> modlu ID `9823` / orijinal ID `9845`

## Sample ID Conflicts

- ID `3222` -> modlu RGB `5,5,5` / orijinal RGB `202,16,154`
- ID `9662` -> modlu RGB `93,19,31` / orijinal RGB `93,18,31`
- ID `9667` -> modlu RGB `93,63,161` / orijinal RGB `93,33,161`
- ID `9669` -> modlu RGB `177,39,169` / orijinal RGB `57,119,44`
- ID `9670` -> modlu RGB `9,43,35` / orijinal RGB `9,42,35`
- ID `9673` -> modlu RGB `135,51,164` / orijinal RGB `216,152,3`
- ID `9674` -> modlu RGB `177,54,37` / orijinal RGB `162,179,245`
- ID `9675` -> modlu RGB `9,57,165` / orijinal RGB `187,93,211`
- ID `9679` -> modlu RGB `177,69,167` / orijinal RGB `241,113,46`
- ID `9680` -> modlu RGB `9,73,41` / orijinal RGB `9,72,40`
- ID `9682` -> modlu RGB `93,79,41` / orijinal RGB `171,155,197`
- ID `9683` -> modlu RGB `135,81,169` / orijinal RGB `100,216,6`

## Sample Quality Flags

- `modlu_kalan` ID `734` RGB `168,72,67` -> Name is empty.
- `modlu_kalan` ID `1466` RGB `43,138,33` -> Name/comment differs across sources for the same identity.
- `modlu_kalan` ID `5802` RGB `89,153,1` -> Name is empty.
- `modlu_kalan` ID `9040` RGB `9,69,20` -> Name is empty.
- `modlu_kalan` ID `9069` RGB `177,156,162` -> Name is empty.
- `modlu_kalan` ID `9074` RGB `177,171,37` -> Name is empty.
- `modlu_kalan` ID `9084` RGB `177,201,42` -> Name is empty.
- `modlu_kalan` ID `9171` RGB `51,36,213` -> Name is empty.
- `modlu_kalan` ID `9184` RGB `177,75,92` -> Name is empty.
- `modlu_kalan` ID `9185` RGB `9,78,220` -> Name is empty.
- `modlu_kalan` ID `9193` RGB `135,102,224` -> Name is empty.
- `modlu_kalan` ID `9227` RGB `93,204,141` -> Name is empty.
