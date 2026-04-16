# Source Semantic Staging Fix

Toplam assignment satiri: 57
- same_id split: 14
- different_id split: 43
- kullanilan placeholder id: 14

Region apply satiri: 114
Placeholder pixel repurpose satiri: 14
Definition duplicate RGB (0,0,0 disi): 0

Ciktilar:
- F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit\Works\analysis\generated\source_semantic_staging_fix\provinces_source_semantic_staging.png
- F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit\Works\analysis\generated\source_semantic_staging_fix\definition_source_semantic_staging.csv
- F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit\Works\analysis\generated\source_semantic_staging_fix\source_semantic_staging_image_apply_report.csv
- F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit\Works\analysis\generated\source_semantic_staging_fix\source_semantic_same_id_split_id_assignments.csv
- F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit\Works\analysis\generated\source_semantic_staging_fix\source_semantic_staging_definition_changes.csv

Notlar:
- Bu tur sadece staging uretir; canli map_data dosyalarina dokunmaz.
- same_id semantic splitlerde placeholder row ve onun gizli teknik pikseli repurpose edildi.
- keep-source mask pikselleri de hedef eski/shared RGBye zorlandi; bu, onceki heuristic recolorlarin tersine cevrilmesini saglar.
