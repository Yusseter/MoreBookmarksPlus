# Dual-Source RGB Presence Audit

- Target set: `source_origin=both` rows from `final_master_preserve_old_ids.csv`
- final image: `map_data/provinces.png`
- west source: `Works/map_data_sources/provinces_modlu_kalan.png`
- east source: `Works/map_data_sources/provinces_orijinal_dogu.png`

- total audited RGB rows: `21`
- live RGBs with pixels coming from both sources: `18`
- live RGBs with both-source pixels and different source names: `13`

Rows with both-source live pixels and different source names:
- `9665` `9,27,160` -> mod `Laar` / orijinal `IMPASSABLE CENTRAL GOBI 1` (mod pixels `280`, orijinal pixels `75122`)
- `9865` `9,201,160` -> mod `Caymont` / orijinal `Goryeo_Donggye_Deungju` (mod pixels `157`, orijinal pixels `435`)
- `9301` `51,0,178` -> mod `Mountains` / orijinal `Karub` (mod pixels `188`, orijinal pixels `502`)
- `9671` `51,45,163` -> mod `Kyburg` / orijinal `` (mod pixels `687`, orijinal pixels `54`)
- `9886` `51,51,43` -> mod `Artvini` / orijinal `Goryeo_Bukgye_Maengju` (mod pixels `487`, orijinal pixels `516`)
- `9676` `51,60,38` -> mod `Eberstein` / orijinal `Marakele` (mod pixels `168`, orijinal pixels `3`)
- `9681` `51,75,168` -> mod `Blamont` / orijinal `Siantan Island` (mod pixels `274`, orijinal pixels `32`)
- `9866` `51,204,33` -> mod `Bethsan` / orijinal `Goryeo_Donggye_Uiju` (mod pixels `200`, orijinal pixels `626`)
- `9672` `93,48,36` -> mod `Stauffen` / orijinal `PLACEHOLDER_REGION_SOUTHEAST_COAST` (mod pixels `316`, orijinal pixels `632`)
- `9867` `93,207,161` -> mod `Jericho` / orijinal `Goryeo_Donggye_Hwaju` (mod pixels `151`, orijinal pixels `417`)
- `9668` `135,36,34` -> mod `Crivitz` / orijinal `IMPASSABLE CENTRAL GOBI 3` (mod pixels `529`, orijinal pixels `34909`)
- `9858` `135,180,29` -> mod `Babruysk` / orijinal `Goryeo_Donggye_Myeongju` (mod pixels `353`, orijinal pixels `220`)
- `9664` `177,24,32` -> mod `Stablo` / orijinal `PLACEHOLDER_REGION_KOREA` (mod pixels `134`, orijinal pixels `573`)
