# CK3 Harita Birlesim Hafizasi

## Calisma Kurali

- Kullanici `su an tartisiyoruz`, `simdi yapma`, `eyleme gecme` gibi bir cerceve cizdiyse otomatik uygulamaya gecilmemeli.
- Bu durumda once sadece anlama teyidi, kural netlestirme ve planlama yapilmali.
- Kullanici 2026-04-11 tarihinde bu planlama konusu icin tekrar yetki verdi ve eylem asamasina gecmeme izin verdi.
- Kullanici `sadece soru` dediginde yalnizca cevap verilmeli, dosya degisikligi yapilmamali.
- `common/landed_titles/00_landed_titles.txt` degisirse ayni degisiklik `test_files/common/landed_titles/00_landed_titles.txt` icine de yansitilmali; kullanici test kopyasindan dosya temin ediyor.
- Kullanici `hafiza.md`nin sismesinden cekinmiyor. Hafiza ne kadar dolu ve bilgi tasiyorsa o kadar iyi.
- Uzun analizler yalnizca gecici baglamda kalmamali; `hafiza.md` disinda ayri analiz dosyalarina da kaydedilmeli.
- Kullanici ayrica her asamada yeni bilgilerin `hafiza.md`ye aktarilmasini istiyor.
- Kullanici bu konuda tekrar tekrar hatirlatmak istemiyor; bundan sonra yeni bir karar, ara sonuc veya netlesmis teknik kural olusunca `hafiza.md` ayrica hatirlatma beklenmeden guncellenmeli.
- Ama kullanici acikca tartisma modunda `simdi yapma` dediyse, `unutma`, `not et`, `hafizaya gecir` gibi ifadeler anlik dosya duzenleme emri degil, sonraki uygun guncellemede kayda gecirilmesi gereken hatirlatma olarak ele alinmali.
- Bir seyin hafizada yazili olup olmadigi soruldugunda yalnizca sohbetteki hatiraya guvenmek yerine dosyanin mevcut durumu kontrol edilerek cevap verilmeli.
- Kisa ve operasyonel hafiza `hafiza.md`de tutulmali.
- Daha uzun ve detayli analizler `analysis/` altinda ayrica saklanmali.

## 2026-04-15 Province ve Title Mapping Pipeline Durumu

- `works/tools/build_province_relation_master.py` eklendi.
- Bu script `Pillow` kullanarak:
  - `works/map_data_sources/provinces_modlu_dogu.png`
  - `map_data/provinces.png`
  uzerinden province bazli iliski cikartiyor.
- Uretilen ana dosya:
  - `works/map_data_sources/province_relation_master.csv`
- Uretilen raporlar:
  - `works/analysis/generated/province_relation_mapping/province_relation_manual_review.csv`
  - `works/analysis/generated/province_relation_mapping/province_relation_split_merge_preview.csv`
  - `works/analysis/generated/province_relation_mapping/province_relation_coverage.csv`
  - `works/analysis/generated/province_relation_mapping/province_relation_summary.md`
- Son province relation ozetleri:
  - `master rows: 4282`
  - `exact mapped rows: 100`
  - `split/merge agirlikli manual review var`
- `works/tools/apply_province_relation_history.ps1` eklendi.
- Bu script sadece `exact + mapped + apply_to_history = yes` province relation satirlarini kullanarak backup moddan province history bloklarini:
  - `history/provinces/00_MB_PROVINCES.txt`
  - `test_files/history/provinces/00_MB_PROVINCES.txt`
  icine tasiyor.
- Province history apply raporlari:
  - `works/analysis/generated/province_relation_mapping/province_relation_history_apply_report.csv`
  - `works/analysis/generated/province_relation_mapping/province_relation_history_apply_summary.md`

## 2026-04-15 e_srivijaya Province Pilot Turu

- `works/tools/build_province_cluster_review.py` eklendi.
- Bu arac:
  - `province_relation_master.csv` satirlarini cluster bazinda filtreliyor
  - current `common/landed_titles/00_landed_titles.txt` icinden hedef province title path bilgisini ekliyor
  - backup source history blogu var mi kontrol ediyor
  - live/test target history blogu var mi kontrol ediyor
  - `promotion_hint` uretip review csv/summary cikariyor
- Ilk pilot:
  - `python works/tools/build_province_cluster_review.py --source-root e_srivijaya --target-root e_srivijaya --cluster-name e_srivijaya_pilot`
- Uretilen ciktilar:
  - `works/analysis/generated/province_relation_mapping/cluster_reviews/e_srivijaya_pilot.csv`
  - `works/analysis/generated/province_relation_mapping/cluster_reviews/e_srivijaya_pilot_summary.md`
- Pilot ozeti:
  - `rows: 264`
  - `ready:exact: 2`
  - `review:target_fully_captured: 1`
  - `review:high_overlap: 18`
  - `blocked:no_target_title: 73`
  - `blocked:no_source_history: 26`
- Bu turda tek manuel province terfisi yapildi:
  - `source_province_id 10399 (North Andaman) -> target_province_id 12848 (Diglipur)`
  - eski durum: `classification = split`, `status = manual_review`, `apply_to_history = no`
  - yeni durum: `classification = exact`, `status = mapped`, `apply_to_history = yes`
  - not: `manual: target_fully_captured_and_unique_target`
- Gerekce:
  - `12848` icin tek kaynak aday `10399`
  - `target_coverage = 1.000000`
  - `source_history_exists = yes`
  - hedef province current `e_srivijaya > k_malayadvipa > d_handumans > c_andamans > b_diglipur`
- Sonraki apply sonrasi:
  - `province_relation_history_apply_summary.md`
    - `exact rows requested: 101`
    - `applied rows: 184`
    - `missing source blocks: 27`
  - `10399 -> 12848` hem live hem `test_files` province history dosyasina uygulandi
- Son validator:
  - `validation errors: 0`
  - `validation warnings: 0`
  - `missing playable province titles: 0`
  - `landed_titles live/test hash match: yes`

## 2026-04-16 e_andong Province Pilot Turu

- `works/tools/build_province_cluster_review.py` sikilastirildi.
- Yeni review metrikleri:
  - `target_source_count_all`
  - `target_best_source_id`
  - `target_best_overlap_score`
  - `target_second_best_overlap_score`
  - `target_overlap_gap`
  - `target_is_best_source`
- `promotion_hint` kurallari da guclendirildi:
  - paylasilan hedef ve dusuk `target_coverage` artik `blocked:shared_target_low_coverage`
  - bir hedef icin birincil kaynak olmayan satirlar artik `blocked:not_primary_target_source`
  - boylece yalnizca overlap yuksek diye yanlis pozitif promote adayi cikmiyor
- Pilot komutu:
  - `python works/tools/build_province_cluster_review.py --source-root e_andong --target-root e_andong --cluster-name e_andong_pilot`
- Ciktilar:
  - `works/analysis/generated/province_relation_mapping/cluster_reviews/e_andong_pilot.csv`
  - `works/analysis/generated/province_relation_mapping/cluster_reviews/e_andong_pilot_summary.md`
- Pilot ozeti:
  - `rows: 228`
  - `review:manual: 129`
  - `blocked:not_primary_target_source: 60`
  - `blocked:no_source_history: 35`
  - `blocked:shared_target_low_coverage: 4`
- Sonuc:
  - bu ilk `e_andong` turunda guvenli promote edilebilir satir cikmadi
  - yani `province_relation_master.csv` icinde bu turda yeni manuel exact terfi yapilmadi
- Blokaj tipleri:
  - bazi hedefler birden fazla source province tarafindan paylasiliyor ve `target_coverage` dusuk kaliyor
  - bazi satirlarda source history block backup setinde yok
  - bazi satirlar hedefin ikincil/ucuncul kaynagi oldugu icin promote edilemez
- Ornek bloklanan satirlar:
  - `12864 -> 11664` `blocked:shared_target_low_coverage`
  - `14384 -> 11683` `blocked:shared_target_low_coverage`
  - `12456 -> 11758` `blocked:shared_target_low_coverage`
  - `13704 -> 11911` `blocked:shared_target_low_coverage`
- Bu turda validator/apply dongusu yeniden calistirilmadi; cunku data dosyalarina degil yalnizca review aracina degisiklik yapildi ve province master icinde yeni mapping override'u yazilmadi.

## 2026-04-16 Nested Target Title Block Review

- `works/tools/build_province_cluster_review.py` icine `--target-title-block` argumani eklendi.
- Bu filtre current `common/landed_titles/00_landed_titles.txt` icindeki adli title block'u bulup o subtree altindaki tum province id'leri cikartiyor.
- Boylece `source_root`/`target_root` seviyesinin yetmedigi nested yapilar artik review edilebiliyor.
- Eklenen yardimci fonksiyonlar:
  - `extract_named_title_block`
  - `get_province_ids_from_title_block`
- Bu degisiklikten sonra `filter_reason` icine `target_title_block` da yaziliyor.
- Review csv kolonlari ve promotion mantigi korunuyor; ama artik root degil subtree bazli cluster analizi yapilabiliyor.

## 2026-04-16 e_yongliang Subtree Turu

- Ilk root bazli deneme bosta kaldi cunku `e_yongliang` province'leri `target_root = e_yongliang` degil, current landed_titles parser acisindan `h_china` altindaki nested subtree olarak gorunuyor.
- `--target-title-block e_yongliang` ile tekrar review alindi:
  - `works/analysis/generated/province_relation_mapping/cluster_reviews/e_yongliang_block_probe.csv`
  - `works/analysis/generated/province_relation_mapping/cluster_reviews/e_yongliang_block_probe_summary.md`
- Ozet:
  - `rows: 130`
  - `ready:exact: 6`
  - `blocked:not_primary_target_source: 44`
  - `blocked:no_source_history: 14`
  - `blocked:shared_target_low_coverage: 11`
- Sonuc:
  - Yeni manuel exact terfi yapilmadi.
  - `ready:exact` satirlar zaten mevcutta `exact/mapped`.
  - Geri kalan adaylar paylasilan hedef, ikincil kaynak veya history eksigi nedeniyle promote edilmedi.
- Ornek blokajlar:
  - `12916 -> 12366` `blocked:not_primary_target_source`
  - `12797 -> 12206` `blocked:shared_target_low_coverage`
  - `12856 -> 12203` `blocked:shared_target_low_coverage`

## 2026-04-16 e_xi_xia Subtree Turu

- Ayni nested filtre mantigi `--target-title-block e_xi_xia` ile uygulandi:
  - `works/analysis/generated/province_relation_mapping/cluster_reviews/e_xi_xia_block_probe.csv`
  - `works/analysis/generated/province_relation_mapping/cluster_reviews/e_xi_xia_block_probe_summary.md`
- Ozet:
  - `rows: 5`
  - `ready:exact: 2`
  - `blocked:not_primary_target_source: 2`
  - `blocked:shared_target_low_coverage: 1`
- Sonuc:
  - Yeni manuel exact terfi yapilmadi.
  - Iki `ready:exact` satir zaten mevcutta `exact/mapped`:
    - `9537 -> 9537` `Wuluhai`
    - `9539 -> 9539` `Dengkou`
  - Diğer uc satir guvenli promote eşiğini gecmedi.


## 2026-04-15 Title Relation Master V2

- `works/tools/build_title_relation_master.ps1` yeniden duzenlendi.
- Eski global `mod canonical` mantigi birakildi; yeni schema source/canonical ayrimini ve provenance cluster bilgisini tutuyor.
- Yeni `title_relation_master.csv` kolonlari en az su alanlari iceriyor:
  - `source_title_id`
  - `source_tier`
  - `canonical_title_id`
  - `canonical_tier`
  - `canonical_namespace`
  - `cluster_key`
  - `source_root_title`
  - `source_kingdom`
  - `source_duchy`
  - `source_county`
  - `relation_type`
  - `rewrite_allowed`
  - `status`
  - `notes`
- Candidate discovery sadece province overlap'e degil, name-family ve context ipuclarina da bakacak sekilde guclendirildi.
- `b_xiagui` icin bos kalan mapping problemi bu refactor sirasinda kapatildi:
  - `b_xiagui -> b_xiagui_china`
  - `relation_type = contextual`
  - `canonical_namespace = mod`
- Son title master seed ozeti:
  - `source titles inventoried: 3776`
  - `mapped rows: 3770`
  - `manual review rows: 6`
  - `exact rows: 2246`
  - `contextual rows: 1524`
  - `mod canonical rows: 1536`
  - `vanilla canonical rows: 2234`

## 2026-04-15 Apostrof Içeren Title ID Desteği

- `common/landed_titles/00_landed_titles.txt` icinde `b_ka'abir` gibi apostrof iceren title id'ler var.
- Ilk title parser/validator regex'leri bu title'lari kapsamiyordu.
- Bu nedenle apostrof desteklenmediğinde:
  - bazi title'lar relation inventory'ye girmeyebiliyor
  - statik province-title validator sahte eksik province uretebiliyor
- 2026-04-15 tarihinde su scriptlerde regex'ler apostrof destekleyecek sekilde guncellendi:
  - `works/tools/build_title_relation_master.ps1`
  - `works/tools/build_title_relation_outputs.ps1`
  - `works/tools/validate_east_mapping_pipeline.ps1`
- Ayrica title stem normalization icinde apostrof kaldiriliyor; bu name-family matching'i iyilestiriyor.

## 2026-04-15 Title Output ve Validator Durumu

- `works/tools/build_title_relation_outputs.ps1` yeni schema ile uyumlu hale getirildi.
- Uretilen raporlar:
  - `works/analysis/generated/title_relation_mapping/title_relation_outputs_summary.md`
  - `works/analysis/generated/title_relation_mapping/title_relation_manual_review.csv`
  - `works/analysis/generated/title_relation_mapping/title_relation_reference_hits.csv`
  - `works/analysis/generated/title_relation_mapping/title_relation_rewrite_candidates.csv`
  - `works/analysis/generated/title_relation_mapping/title_relation_coverage.csv`
- Son output ozeti:
  - `safe rewrite rows: 438`
  - `reference hits: 704`
  - `rewrite candidate hits: 2`
  - `apply mode: no`
- Otomatik rewrite bu turda uygulanmadi; sadece rapor uretildi.
- `works/tools/validate_east_mapping_pipeline.ps1` eklendi.
- Bu validator su seyleri statik olarak kontrol ediyor:
  - province relation safety gate
  - province history apply safety gate
  - title inventory/master coverage
  - rewrite candidate safety gate
  - landed_titles brace dengesi
  - `common` ve `test_files` landed_titles hash senkronu
  - duplicate province assignment
  - invalid capital
  - invalid de jure tier zinciri
  - non-land province assignment
  - `definition.csv` bazli missing playable province title
- Son validator ozeti:
  - `landed_titles live/test hash match: yes`
  - `missing playable province titles: 0`
  - `validation errors: 0`
  - `validation warnings: 0`

## 2026-04-15 Manual Review Kapatma Turu

- Title relation master icindeki kalan `6` manuel satir kapatildi.
- Elle verilen canonical kararlar:
  - `d_LIAO_linhuang -> d_xarmoron_china`
  - `d_LIAO_shangjing -> d_changchun_china`
  - `d_LIAO_zhongjing -> d_tohchen_china`
  - `d_yanyun_yuyi -> d_hiyaxu_china`
  - `b_siantan -> b_riau`
  - `b_muot -> b_nakkavaram`
- Bu kararlar `manual:` notuyla yazildi; boylece `build_title_relation_master.ps1` yeniden calistiginda korunuyorlar.
- Ayrica `history/titles/00_ASIA_CHINA.txt` icinde:
  - `set_capital_county = title:c_hangzhou`
  - `set_capital_county = title:c_hangzhou_china`
  olarak duzeltildi.
- `works/tools/build_title_relation_outputs.ps1` icinde quoted string tarama false positive'i azaltildi:
  - scan asamasinda quoted string segmentleri ayiklaniyor
  - bu sayede `name = "b_Wuling"` gibi localization/name stringleri rewrite hit sayilmiyor
- Son yeniden uretim sonrasi:
  - `manual review rows: 0`
  - `rewrite candidate hits: 0`
  - `rewrite candidate rows: 0`
  - validator yine `errors = 0`, `warnings = 0`

## 2026-04-15 Landed Titles Crash Notlari

- `ck3_20260415_005155` crash analizinde en guclu suphe, `Works/tools/restore_missing_landed_title_roots.ps1` icindeki `mapping yoksa barony sil` mantigiydi.
- Bu mantik sonrasi `Province with no county data` zinciri ozellikle `e_xi_xia`, `e_tibet`, `e_yongliang` ve `h_china` cevresinde goruldu.
- 2026-04-15 tarihinde `common/landed_titles/00_landed_titles.txt` ve `test_files/common/landed_titles/00_landed_titles.txt` icinden yuksek supheli top-level root'lar geri alindi:
  - `e_xi_xia`
  - `e_tibet`
  - `e_yongliang`
- Ayni tarihte `Works/tools/restore_missing_landed_title_roots.ps1` guncellendi:
  - artik `missing_mapping_barony_removed` yok
  - onun yerine `missing_mapping_barony_blocked` raporlaniyor
  - eksik province mapping varsa script root restore'u durdurup hata veriyor
- Dogrulama sonucu:
  - iki landed_titles kopyasi yine birebir ayni hash'e sahip
  - brace dengesi iki dosyada da `final_depth=0`
  - restore script calistirildiginda `e_xi_xia` icin `51` eksik mappingte fail ediyor; artik sessizce barony silmiyor

## 2026-04-15 Landed Titles Full Rebuild Karari

- `Works/tools/rebuild_managed_landed_titles_from_sources.ps1` bu turda daha guclu hale getirildi:
  - `SourceBlockName` destegi eklendi
  - `RemoveNestedNames` destegi eklendi
  - `Rename-BlockRootName` fonksiyonu eklendi
  - `manual_barony_override` destegi eklendi
- En kritik karar: `e_xi_xia` artik mod kaynagindan degil, vanilla `02_china.txt` icindeki `k_xia` blogundan uretilecek.
- Buna paralel olarak `h_china` rebuild sirasinda nested `k_xia` blogu cikariliyor; boylece Xi Xia iki kez tanimlanmiyor.
- Ayni turda su zorunlu temizlemeler yapildi:
  - `h_india` icinden `b_kaptai` cikarildi
  - `h_china` icinden `c_maozhou` ve `b_shanglin` cikarildi
  - `e_tibet` icinden `b_jagsam` cikarildi
- `e_tibet` icin kullanilan guvenli province override'lari:
  - `b_muli -> 11454`
  - `b_maowun -> 7115`
  - `b_sumshul -> 12535`
  - `b_wunchoin -> 10322`
- Rebuild 2026-04-15 tarihinde basariyla tamamlandi.
- Son rebuild dogrulamasi:
  - `managed roots rebuilt: 16`
  - `province rows rewritten/re-evaluated: 3716`
  - `duplicate province rows after rebuild: 0`
  - `common/landed_titles/00_landed_titles.txt` ile `test_files/common/landed_titles/00_landed_titles.txt` hash olarak birebir ayni
- Bu turdaki landed_titles duzeltmesi script uzerinden iki kopyaya da yazildi; ancak oyun ici yeni launch/crash testi bu kayittan sonra kullanici tarafinda yapilacak.

## Proje Amaci

- Hedef: mevcut total conversion modunun genel harita mantigini korumak, ama Dogu Asya tarafinda vanilla CK3 projeksiyonuna geri donmek.
- Birlesim mantigi: modun vanilla ile uyumsuz olan dogu kismi vanilla'dan alinacak, geri kalan kisim moddan kalacak.
- Mevcut odak: eldeki `definition_modlu.csv`, `definition_orijinal.csv` ve `provinces_*.png` secim dosyalarini kullanarak gelecekte uretilecek `definition_birlesim.csv` icin saglam bir veri modeli ve plan cikarmak.
- Bu asamada ana hedef dogrudan tum oyun dosyalarini donusturmek degil; once final `definition` tablosunu guvenli sekilde nasil cikaracagimizi netlestirmek.

## Kaynak Dizinler

- Mod klasoru: `F:\Storage\Codding\git\Crusader Kings III\Leviathonlx MoreBookmarks-Plus\BookmarksGit`
- Vanilla oyun klasoru: `C:\Program Files (x86)\Steam\steamapps\common\Crusader Kings III\game`

## Kaynak Rolleri

- Mod tarafi kimlik kaynagi: `map_data/definition_modlu.csv`
- Vanilla tarafi kimlik kaynagi: `map_data/definition_orijinal.csv`
- Mod tam province haritasi: `map_data/provinces_modlu.png`
- Vanilla tam province haritasi: `map_data/provinces_orijinal.png`
- Mod dogu secimi: `map_data/provinces_modlu_dogu.png`
- Mod kalan secimi: `map_data/provinces_modlu_kalan.png`
- Vanilla dogu secimi: `map_data/provinces_orijinal_dogu.png`
- Vanilla kalan secimi: `map_data/provinces_orijinal_kalan.png`
- Nihai secim goruntusu: `map_data/provinces_birlesim.png`

## Isimlendirme Notu

- Genel `provinces.png` ifadesi bu proje icin fazla belirsiz.
- Bundan sonra mumkun oldugunca dosya adlari acikca yazilmali:
  - `provinces_modlu.png`
  - `provinces_orijinal.png`
  - `provinces_modlu_dogu.png`
  - `provinces_modlu_kalan.png`
  - `provinces_orijinal_dogu.png`
  - `provinces_orijinal_kalan.png`
  - `provinces_birlesim.png`

## Temel Teknik Bilgiler

- Mod tam province haritasi boyutu: `9216x4608`
- Vanilla tam province haritasi boyutu: `9216x4608`
- Sonuc: teknik olarak iki harita ayni canvas uzerinde calisabiliyor.

- `definition_modlu.csv` aktif satir sayisi: `14697` (`id 0` dahil)
- `definition_orijinal.csv` aktif satir sayisi: `13270` (`id 0` dahil)

- Mod icinde province ID referanslarinin ana agirligi:
  - `map_data/default.map`
  - `common/landed_titles/00_landed_titles.txt`
  - `history/provinces/00_MB_PROVINCES.txt`
  - bazi `history/titles/*.txt`
  - bazi `map_data/geographical_regions/*.txt`

- `history/provinces` yapisi modda buyuk oranda su dosyada toplu duruyor:
  - `history/provinces/00_MB_PROVINCES.txt`

## Tam Harita Seviyesinde Mod ve Vanilla Cakisma Tabani

- Mod icinde duplicate RGB yok.
- Vanilla icinde duplicate RGB olarak gorunen anlamli tek durum `0,0,0` disi degil; aktif problem gibi ele alinmamali.
- Tam harita karsilastirmasinda mod ve vanilla arasinda:
  - ortak RGB sayisi: `9602`
  - ayni RGB ve ayni ID olanlar: `9473`
  - ayni RGB ama farkli ID olanlar: `129`
  - ortak ID sayisi: `13270`
  - ayni ID ama farkli RGB olanlar: `3797`

## Kullanici Tarafindan Netlestirilen Kural

- `provinces_modlu_kalan.png` ile `provinces_orijinal_dogu.png` arasinda ayni RGB varsa ve `definition_modlu.csv` ile `definition_orijinal.csv` icinde bu RGB ayni province ID'ye gidiyorsa bu hata degildir.
- Yani "ayni RGB" tek basina hata kriteri degil.
- Hata karari icin en azindan RGB ve ID birlikte degerlendirilmeli.

## Format Notu

- Province rengi dogrulugu icin ana oncelik lossless ve pixel-exact davranistir.
- JPG/JPEG kullanilmamali.
- Lossy WebP kullanilmamali.
- `PNG` su an en guvenli calisma formati.
- `DDS` teorik olarak kullanilabilir ama pratikte sikistirma, mipmap, format varyasyonu ve arac farklari nedeniyle analiz girdisi olarak daha riskli.
- Province secimi icin calisma formati olarak `PNG` tercih edilmeli.

## Tarihsel Not: Eski Kirik Girdi

- 2026-04-11 tarihinde ilk verilen `provinces_orijinal_dogu.png` dosyasinda agir renk bozulmasi goruldu.
- O surumde `provinces_orijinal_dogu.png` non-black unique renk sayisi `61589` idi.
- Bu, vanilla tam haritadaki `12750` renkten cok daha yuksekti ve exact province RGB korunumunun bozulduguna isaret ediyordu.
- Bu bulgu artik tarihsel not olarak saklanmali.
- Daha sonra kullanici `provinces_orijinal_dogu.png` dosyasini duzeltti; guncel plan ve analizler sadece duzeltilmis set uzerinden yorumlanmali.

## Guncel PNG Seti Icin Hash Kaydi

- `provinces_modlu.png`: `05A03A6FB339CFA64E57974BCED142180D4CFA52730E64DB9B199F241B652438`
- `provinces_modlu_dogu.png`: `F3ABE180F5E10033A3D295998A0D1E0874CCE6B4BDBF2F3160AAE1B548A438DB`
- `provinces_modlu_kalan.png`: `1AB2562A9109388C734F0B2C199F6E9E6F3CF6CEFF1D4F41EBC96A70E48CD501`
- `provinces_orijinal.png`: `33A2B0D488DE5CB79488E5C8603788D52277DDAB93FB1F3B1FED0FCD75E82CD4`
- `provinces_orijinal_dogu.png`: `F354B7FBFD13B3854837FDB02A5B1958A960BA478D810AC56ED3463BBA166504`
- `provinces_orijinal_kalan.png`: `AC136EE9E2A6621CFB8D7AAEDA2DB5969B6442A7E382513486116EBCBF372714`
- `provinces_birlesim.png`: `514DCA0E95DAF9FA23304604708B90CBE50768C91D2FFADCFAAD2C13EB94102D`

## Guncel PNG Dosya Ozetleri

- `provinces_modlu.png`
  - non-black unique renk: `14155`
  - black piksel: `0`

- `provinces_modlu_dogu.png`
  - non-black unique renk: `4282`
  - black piksel: `28010551`

- `provinces_modlu_kalan.png`
  - non-black unique renk: `9891`
  - black piksel: `14456836`

- `provinces_orijinal.png`
  - non-black unique renk: `12750`
  - black piksel: `0`

- `provinces_orijinal_dogu.png`
  - non-black unique renk: `3391`
  - black piksel: `28010490`

- `provinces_orijinal_kalan.png`
  - non-black unique renk: `9365`
  - black piksel: `14459659`

- `provinces_birlesim.png`
  - non-black unique renk: `13142`
  - black piksel: `0`

## Guncel Renk Butunlugu Kontrolu

- 2026-04-11 tarihli kontrol sonucuna gore mevcut `provinces*.png` setinde anti-alias veya rastgele renk kaymasi bulgusu gorulmedi.
- Kontrol mantigi:
  - `provinces_modlu_dogu.png` icindeki tum non-black renkler `provinces_modlu.png` icinde bulundu
  - `provinces_modlu_kalan.png` icindeki tum non-black renkler `provinces_modlu.png` icinde bulundu
  - `provinces_orijinal_dogu.png` icindeki tum non-black renkler `provinces_orijinal.png` icinde bulundu
  - `provinces_orijinal_kalan.png` icindeki tum non-black renkler `provinces_orijinal.png` icinde bulundu
  - `provinces_birlesim.png` icindeki tum non-black renkler mod veya vanilla tam haritalardan en az birinde bulundu

- Sonuc sayilari:
  - `provinces_modlu_dogu.png`: bilinmeyen non-black renk `0`
  - `provinces_modlu_kalan.png`: bilinmeyen non-black renk `0`
  - `provinces_orijinal_dogu.png`: bilinmeyen non-black renk `0`
  - `provinces_orijinal_kalan.png`: bilinmeyen non-black renk `0`
  - `provinces_birlesim.png`: bilinmeyen non-black renk `0`

- Yorum:
  - Su anki PNG seti, en azindan exact RGB butunlugu acisindan temiz gorunuyor.
  - Bu kontrol renk bozulmasi olmadigini destekliyor.
  - Bu kontrol tek basina split province veya eksik piksel gibi secim mantigi sorunlarini bitirmez; sadece renklerin kaynak haritalardaki gerçek province renklerinden geldigini gosterir.

## Definition ve PNG Uyumlulugu

### Tam Mod Haritasi

- `provinces_modlu.png` icindeki tum non-black renkler `definition_modlu.csv` icinde tanimli.
- Sayilar:
  - PNG non-black unique renk: `14155`
  - definition non-black unique renk: `14696`
  - PNG'de olup definition'da olmayan renk: `0`
  - definition'da olup PNG'de kullanilmayan renk: `541`

- Yorum:
  - `definition_modlu.csv`, `provinces_modlu.png` icin kapsama acisindan uyumlu.
  - Ama definition tarafinda su an haritada kullanilmayan ek satirlar var.

### Tam Vanilla Haritasi

- `provinces_orijinal.png` icindeki tum non-black renkler `definition_orijinal.csv` icinde tanimli.
- Sayilar:
  - PNG non-black unique renk: `12750`
  - definition non-black unique renk: `13268`
  - PNG'de olup definition'da olmayan renk: `0`
  - definition'da olup PNG'de kullanilmayan renk: `518`

- Yorum:
  - `definition_orijinal.csv`, `provinces_orijinal.png` icin kapsama acisindan uyumlu.
  - Vanilla definition tarafinda da haritada kullanilmayan ek satirlar var.

### Secim PNG'leri ve Kendi Definition Kaynaklari

- `provinces_modlu_dogu.png`
  - PNG'de olup `definition_modlu.csv` icinde olmayan renk: `0`
  - `definition_modlu.csv` icinde olup bu secimde kullanilmayan renk: `10414`

- `provinces_modlu_kalan.png`
  - PNG'de olup `definition_modlu.csv` icinde olmayan renk: `0`
  - `definition_modlu.csv` icinde olup bu secimde kullanilmayan renk: `4805`

- `provinces_orijinal_dogu.png`
  - PNG'de olup `definition_orijinal.csv` icinde olmayan renk: `0`
  - `definition_orijinal.csv` icinde olup bu secimde kullanilmayan renk: `9877`

- `provinces_orijinal_kalan.png`
  - PNG'de olup `definition_orijinal.csv` icinde olmayan renk: `0`
  - `definition_orijinal.csv` icinde olup bu secimde kullanilmayan renk: `3903`

- Yorum:
  - Bu beklenen bir durum.
  - Secim PNG'leri definition'in sadece bir alt kumesini kullaniyor.

### Birlesim PNG ve Definition Birligi

- `provinces_birlesim.png` icindeki tum non-black renkler mod veya vanilla definition kaynaklarindan en az birinde tanimli.
- Sayilar:
  - `provinces_birlesim.png` non-black unique renk: `13142`
  - her iki definition'da da bulunmayan renk: `0`
  - sadece mod definition'da bulunan renk: `590`
  - sadece vanilla definition'da bulunan renk: `3094`
  - hem mod hem vanilla definition'da bulunup ayni ID'ye giden renk: `9333`
  - hem mod hem vanilla definition'da bulunup farkli ID'ye giden renk: `125`

- Yorum:
  - Final `provinces_birlesim.png` icin definition seviyesinde kapsama sorunu yok.
  - Esas sorun "eksik tanim" degil, "iki kaynakta farkli anlama gelen ortak renkler" yani collision yonetimi.

## Definition Uyumlulugu Icin Genel Sonuc

- Guncel `definition_modlu.csv` ile `provinces_modlu.png` uyumlu.
- Guncel `definition_orijinal.csv` ile `provinces_orijinal.png` uyumlu.
- Secim PNG'leri kendi kaynak definition'lariyla uyumlu.
- `provinces_birlesim.png` mod+vanilla definition birligiyle uyumlu.
- Bu da su an asagidaki seyi guclu sekilde destekliyor:
  - final `definition_birlesim.csv` uretimi teknik olarak tanim eksigi yuzunden degil
  - esas olarak collision ve ID/RGB politika kararlari yuzunden dikkat gerektiriyor

## Guncel Secim Ozetleri

- `provinces_modlu_dogu.png` secimi, `provinces_modlu.png` icindeki province renkleri acisindan:
  - tam tutulan province rengi: `4250`
  - hic alinmayan province rengi: `9873`
  - parcali kalan province rengi: `32`

- `provinces_modlu_kalan.png` secimi, `provinces_modlu.png` icindeki province renkleri acisindan:
  - tam tutulan province rengi: `9851`
  - hic alinmayan province rengi: `4264`
  - parcali kalan province rengi: `40`

- `provinces_orijinal_dogu.png` secimi, `provinces_orijinal.png` icindeki province renkleri acisindan:
  - tam tutulan province rengi: `3385`
  - hic alinmayan province rengi: `9359`
  - parcali kalan province rengi: `6`

- `provinces_orijinal_kalan.png` secimi, `provinces_orijinal.png` icindeki province renkleri acisindan:
  - tam tutulan province rengi: `9359`
  - hic alinmayan province rengi: `3385`
  - parcali kalan province rengi: `6`

## Dogu ve Kalan Arasindaki Ayni-RGB Sayilari

- Mod tarafinda `provinces_modlu_dogu.png` ile `provinces_modlu_kalan.png` arasinda ortak RGB sayisi: `18`
- Vanilla tarafinda `provinces_orijinal_dogu.png` ile `provinces_orijinal_kalan.png` arasinda ortak RGB sayisi: `6`

## Composite Kontroller

- `provinces_modlu_dogu.png + provinces_modlu_kalan.png -> provinces_modlu.png`
  - non-ambiguous mismatch piksel: `624`
  - overlap same-color piksel: `0`
  - overlap different-color piksel: `0`
  - yorum: modun dogu/kalan ayriminda kucuk miktarda eksik piksel veya bosluk birakilmis gorunuyor

- `provinces_orijinal_dogu.png + provinces_orijinal_kalan.png -> provinces_orijinal.png`
  - non-ambiguous mismatch piksel: `2821`
  - overlap same-color piksel: `0`
  - overlap different-color piksel: `0`
  - yorum: vanilla dogu/kalan ayrimi genel olarak temiz ama tam kusursuz degil; az miktarda bosluk veya eksik piksel var

- `provinces_modlu_kalan.png + provinces_orijinal_dogu.png -> provinces_birlesim.png`
  - non-ambiguous mismatch piksel: `0`
  - overlap same-color piksel: `2`
  - overlap different-color piksel: `0`
  - yorum: mevcut `provinces_birlesim.png`, `provinces_modlu_kalan.png` ile `provinces_orijinal_dogu.png` birlesiminin en guclu referansi gibi gorunuyor

## Guncel Secim Setleri Arasi Paylasilan RGB Ozetleri

- `provinces_modlu_kalan.png` vs `provinces_orijinal_dogu.png`
  - ortak RGB toplam: `140`
  - ayni RGB ve ayni ID: `21`
  - ayni RGB ama farkli ID veya eksik tanim: `119`

- `provinces_modlu_dogu.png` vs `provinces_orijinal_dogu.png`
  - ortak RGB toplam: `161`
  - ayni RGB ve ayni ID: `157`
  - ayni RGB ama farkli ID veya eksik tanim: `4`

- `provinces_modlu_kalan.png` vs `provinces_orijinal_kalan.png`
  - ortak RGB toplam: `9163`
  - ayni RGB ve ayni ID: `9163`
  - ayni RGB ama farkli ID veya eksik tanim: `0`

## Bu Ozetlerden Cikan Ana Yorum

- Mod ve vanilla kalan kisimlari buyuk oranda ortak province tabanini koruyor.
- Dogu tarafinda mod ve vanilla arasinda daha fazla yapisal ayrisma var.
- Final `definition_birlesim.csv` uretiminde esas belirleyici kaynak, tam secimlerin union mantigini gosteren `provinces_birlesim.png` olmali.
- `provinces_modlu_dogu.png` ve `provinces_orijinal_kalan.png` daha cok audit ve capraz kontrol girdisi gibi dusunulmeli.

## Yeni Definition Uretim Mantigi

- Amac `definition_modlu.csv` ve `definition_orijinal.csv` dosyalarini PNG'den sifirdan yeniden cizmek degil.
- Dogru model su:
  - `PNG` dosyalari hangi province'lerin finalde yasadigini ve hangi tarafa ait olduklarini gosterecek
  - `definition_modlu.csv` ve `definition_orijinal.csv` ise bu province'lerin `id/rgb/name` sozlugu olacak
  - bunlardan yeni bir `definition_birlesim.csv` uretilecek

- Kisa formul:
  - `PNG` = secim ve geometri
  - `definition_*.csv` = kimlik sozlugu
  - final hedef = `definition_birlesim.csv`

## Guncellenmis Ara Uretim Fikri

- Kullanici tarafindan kabul edilen yeni ara plan:
  1. `provinces_modlu_kalan.png` icindeki tum yasayan RGB'leri al
  2. bunlari `definition_modlu.csv` icinden ayikla
  3. `definition_modlu_kalan.csv` uret
  4. `provinces_orijinal_dogu.png` icindeki tum yasayan RGB'leri al
  5. bunlari `definition_orijinal.csv` icinden ayikla
  6. `definition_orijinal_dogu.csv` uret
  7. sonra bu iki ara definition dosyasini kuralli bicimde karsilastir
  8. en son `definition_birlesim.csv` uret

- Bu yaklasimda `provinces_birlesim.png`ye dogrudan dokunma veya recolor etme plani yok.
- Bu nedenle final asamada PNG degismeden cozulmesi gereken butun kimlik cakismalari raporlanmali.

## Cakisma Kurallari

- Ayni RGB + ayni ID:
  - benign overlap
  - hata degil

- Ayni RGB + farkli ID:
  - sert cakisma
  - kullaniciya bildirilmeli

- Farkli RGB + ayni ID:
  - ID cakismasi
  - kullaniciya bildirilmeli

- Kullanici notu:
  - bu durumlarin hic olmamasi umuluyor
  - ama olurlarsa mutlaka raporlanmali

## Alt-Kume Definition Dosyalariyla Kontrol Fikri

- Kullanici, `definition_(modlu/orijinal)*isim*.csv` benzeri ara CSV dosyalari olusturarak kontroller yapilmasini uygun goruyor.
- Bu ara dosyalar yalnizca uretim icin degil, audit icin de kullanilabilir.

- Olası audit basliklari:
  - PNG'de olup ilgili definition alt-kumesinde olmayan renkler
  - alt-kume definition icinde olup PNG'de bulunmayan renkler
  - ayni RGB + farkli ID durumlari
  - farkli RGB + ayni ID durumlari
  - ayni province'in iki kaynakta farkli name/comment tasimasi
  - secim sonucu olusan bosluk / split province / parcali secim bulgulari
  - birlesim sonunda yalniz bir tarafta kalan province kimlikleri
  - beklenmeyen placeholder / bos isim / x satirlari

- Kullanici `vb.` derken benzer diger mantikli denetimlerin de dahil edilmesini istiyor.

## Cakisma Siniflari

- Benign overlap:
  - ayni RGB
  - ayni ID
  - kullanici kuralina gore hata degil

- RGB collision:
  - ayni RGB
  - farkli ID
  - final tabloda ayni renk iki farkli province anlamina gelemeyecegi icin cozulmeli

- ID collision:
  - farkli RGB
  - ayni ID
  - final tabloda ayni ID iki farkli province anlamina geliyorsa cozulmeli

- Split province:
  - bir province rengi secim taraflarinda parcali kalmis
  - bu durumda province tek parcali final sahipligine nasil atanacagi netlestirilmeli

- Missing-pixel gap:
  - dogu+kalan ayriminda bazi pikseller hicbir tarafa gitmemis
  - composite mismatch bunun isaretlerinden biri

- Name/comment divergence:
  - ayni RGB ve ayni ID olsa bile `comment/name` alanlari farkli olabilir
  - bu tek basina hata sayilmiyor
  - ama final comment politikasinda karar gerektirebilir

## Gecici ID Politikasi Dusuncesi

- En guvenli ilk dusunce hala su:
  - modda kalan province'ler mod ID'lerini korusun
  - vanilla'dan ithal edilen dogu province'leri sadece guvenliyse mevcut ID'yi korusun
  - conflict varsa yeni ID bloguna tasinsin

- Bunun icin finalde ayri bir esleme tablosu lazim:
  - `old_id`
  - `new_id`
  - `source`

## Gecici RGB Politikasi Dusuncesi

- Cakismayan province mevcut RGB'sini koruyabilir.
- Ayni RGB farkli province anlami tasiyorsa finalde tekil RGB zorunlulugu nedeniyle bunlardan biri recolor edilmeli.
- Bunun icin ayri bir RGB esleme tablosu lazim:
  - `old_rgb`
  - `new_rgb`
  - `source`

## Planlanan Uretim Artefaktlari

- `definition_birlesim.csv`
- `id_mapping.csv`
- `rgb_mapping.csv`
- `conflict_report.csv`
- daha sonra gerekiyorsa:
  - `split_province_report.csv`
  - downstream province referans donusum tablolari

## Uretim Araci

- Tekrarlanabilir subset ve audit uretimi icin script eklendi:
  - `tools/build_definition_subset_audit.ps1`

- Bu script su ciktilari uretir:
  - `map_data/definition_modlu_dogu.csv`
  - `map_data/definition_modlu_kalan.csv`
  - `map_data/definition_orijinal_dogu.csv`
  - `map_data/definition_orijinal_kalan.csv`
  - `analysis/generated/definition_rgb_conflicts.csv`
  - `analysis/generated/definition_id_conflicts.csv`
  - `analysis/generated/definition_shared_same_id.csv`
  - `analysis/generated/definition_quality_flags.csv`
  - `analysis/generated/definition_merge_inventory.csv`
  - `analysis/generated/definition_id_tracking.csv`
  - `analysis/generated/definition_subset_audit.md`
  - `analysis/generated/definition_subset_validation.csv`
  - `analysis/generated/definition_modlu_dogu_rgb_inventory.csv`
  - `analysis/generated/definition_modlu_kalan_rgb_inventory.csv`
  - `analysis/generated/definition_orijinal_dogu_rgb_inventory.csv`
  - `analysis/generated/definition_orijinal_kalan_rgb_inventory.csv`

- Kullanici istegi uzerine yeni guvence:
  - subset olusturulurken PNG'den alinan tum RGB'ler ayri dosyalara tek tek yazilmali
  - boylece hangi renklerin gercekten secildigi sonradan da denetlenebilmeli

## Uretilen Alt-Kume Definition Dosyalari

- `definition_modlu_dogu.csv`
  - image renk sayisi: `4282`
  - cekilen satir sayisi: `4282`
  - definition eksigi: `0`

- `definition_modlu_kalan.csv`
  - image renk sayisi: `9891`
  - cekilen satir sayisi: `9891`
  - definition eksigi: `0`

- `definition_orijinal_dogu.csv`
  - image renk sayisi: `3391`
  - cekilen satir sayisi: `3391`
  - definition eksigi: `0`

- `definition_orijinal_kalan.csv`
  - image renk sayisi: `9365`
  - cekilen satir sayisi: `9365`
  - definition eksigi: `0`

## RGB Inventory Dosyalari

- `analysis/generated/definition_modlu_dogu_rgb_inventory.csv`
  - satir sayisi: `4282`
  - `provinces_modlu_dogu.png` icinden alinan tum non-black RGB'leri tek tek listeler

- `analysis/generated/definition_modlu_kalan_rgb_inventory.csv`
  - satir sayisi: `9891`
  - `provinces_modlu_kalan.png` icinden alinan tum non-black RGB'leri tek tek listeler

- `analysis/generated/definition_orijinal_dogu_rgb_inventory.csv`
  - satir sayisi: `3391`
  - `provinces_orijinal_dogu.png` icinden alinan tum non-black RGB'leri tek tek listeler

- `analysis/generated/definition_orijinal_kalan_rgb_inventory.csv`
  - satir sayisi: `9365`
  - `provinces_orijinal_kalan.png` icinden alinan tum non-black RGB'leri tek tek listeler

- Bu dosyalardaki her satirda en az su bilgiler tutuluyor:
  - subset_name
  - source_label
  - rgb
  - r/g/b
  - present_in_png
  - present_in_definition
  - source_id
  - source_name
  - definition_path
  - image_path

## Subset Validation Tekrari

- `analysis/generated/definition_subset_validation.csv` olusturuldu.
- Bu dosya her subset icin su kontrolu tekrar kaydediyor:
  - image non-black unique renk sayisi
  - cekilen definition satir sayisi
  - rgb inventory satir sayisi
  - missing_colors_in_definition
  - validation_pass

- Sonuc:
  - `modlu_dogu`: `validation_pass = True`
  - `modlu_kalan`: `validation_pass = True`
  - `orijinal_dogu`: `validation_pass = True`
  - `orijinal_kalan`: `validation_pass = True`

- Yorum:
  - tekrar kontrolde her subset icin:
    - PNG'deki secili non-black RGB sayisi
    - cekilen definition satir sayisi
    - yazilan RGB inventory satir sayisi
    birebir ayni cikti
  - ve tanimsiz renk bulunmadi

## Uretilen Audit Sonuclari

- `analysis/generated/definition_shared_same_id.csv`
  - satir sayisi: `21`
  - anlami: ayni RGB + ayni ID

- `analysis/generated/definition_rgb_conflicts.csv`
  - satir sayisi: `119`
  - anlami: ayni RGB + farkli ID
  - kullanici kuralina gore sert cakisma, raporlanmali

- `analysis/generated/definition_id_conflicts.csv`
  - satir sayisi: `634`
  - anlami: farkli RGB + ayni ID
  - kullanici kuralina gore ID cakismasi, raporlanmali

- `analysis/generated/definition_quality_flags.csv`
  - satir sayisi: `188`
  - anlami: bos isim, placeholder, veya name/comment divergence gibi ek kalite uyarilari

- `analysis/generated/definition_merge_inventory.csv`
  - satir sayisi: `13282`
  - kapsam: `9891` modlu_kalan + `3391` orijinal_dogu
  - her satir icin status, partner eslesmeleri ve notlar tutuluyor

- `analysis/generated/definition_id_tracking.csv`
  - satir sayisi: `13282`
  - rol: gelecekte verilecek yeni ID'lerin ana takip tablosu
  - `final_new_id` su an bilerek bos
  - conflict olmayan satirlarda bile ileride bu dosya uzerinden gitmek daha guvenli

## Yeni ID Takibi Icin Kural

- Kullaniciya gore ileride yeni ID atanan modlu ve orijinal province'ler not edilmeli.
- Bunun nedeni, daha sonra province ID iceren oyun dosyalarini duzenlerken hata yapmamak.
- Bu amacla:
  - `analysis/generated/definition_id_tracking.csv` birincil takip tablosu olacak
  - burada su alanlar tutuluyor:
    - kaynak alt-kume
    - kaynak definition
    - source_id
    - source_rgb
    - source_name
    - primary_status
    - final_new_id
    - final_id_status
    - partner conflict bilgileri
    - notlar

- Kural:
  - gelecekte bir province yeni ID alirsa bu once `definition_id_tracking.csv` icine yazilmali
  - daha sonra province referansli oyun dosyalarina gecilmeli

## Bu Asamada Cikan En Onemli Yeni Sonuc

- `definition_birlesim.csv` olusturmadan once mutlaka iki buyuk conflict sinifi ele alinmali:
  - `119` adet RGB conflict
  - `634` adet ID conflict

- Bu da su demek:
  - sorun tanim eksigi degil
  - sorun aktif kimlik cakismasi

## Placeholder Province Tartismasi

- Kullanici yeni bir oneride bulundu:
  - final `definition_birlesim.csv` icinde ID'ler ardışık olmak zorundaysa
  - arada bos kalan ID'ler `place_holder` satirlariyla doldurulabilir
  - ornek mantik:
    - `13999;123;53;87;place_holder;x`
  - daha sonra bu placeholder province'ler `provinces_birlesim.png` icinde haritanin en sag altinda gorunmeyecek teknik bir bolgeye tek tek kucuk pikseller olarak yerlestirilebilir
  - `default.map` icinde bunlar yorumla aciklanmis bir `impassable_mountains` bloguna eklenebilir

- Bu tartismada yeni netlesen nokta:
  - daha once "PNG'ye hic dokunmayalim" itirazi zayifladi
  - cunku kullaniciya gore zaten `provinces_birlesim.png` icinde ayni RGB ile cakisan province'ler yuzunden belirli duzeyde PNG duzenlemesi gerekebilir

- Kullanici itirazlari:
  - placeholder'lari sadece CSV'de tutup PNG'de hic boyamamak cokmeye neden olabilir
  - alt sagdaki teknik bolge oyunda gorunmeyecegi icin oradaki yapay province birikimi pratikte sorun olmayabilir
  - `default.map`e "gereksiz teknik province" sokmus olmayiz; bunun yerine yorumla aciklanan tek bir `impassable_mountains` blogu kullanabiliriz

- Bu tartismadan cikan guncel tutum:
  - placeholder'larin sadece CSV'de tutulmasi artik tek tercih olarak dusunulmemeli
  - placeholder'lari `provinces_birlesim.png` icinde gizli teknik bir bolgede boyama fikri ciddi ve gecerli bir secenek
  - bu teknik placeholder province'ler icin `default.map`te acik yorumlu ayri bir `impassable_mountains` blogu kullanmak makul goruluyor

- Hala acik teknik sorular:
  - CK3 placeholder province'lerin hic boyanmamasina gercekten toleransli mi
  - `1` piksel mi, yoksa biraz daha guvenli bir teknik boyut mu kullanilmali
  - placeholder bolgesinin tam koordinat ve geometri kurali ne olmali
  - bu teknik province'lerin adjacencies, rivers veya baska map sistemleriyle etkilesimi sifir kalir mi

- Ama genel yon su an icin kullanici tarafina dogru kaydi:
  - gerekirse PNG'ye teknik placeholder province'ler eklenebilir
  - bunlar gizli bir alanda tutulur
  - `default.map`te yorumla belgelenir

## Su Anki Cakisma Durumu

- Bu baslik, mevcut son generator calistirmasinin ozet durumudur.

- benign overlap:
  - `21`
  - anlami: ayni RGB + ayni ID
  - bunlar hata degil

- RGB conflict:
  - `119`
  - anlami: ayni RGB + farkli ID
  - bunlar sert cakisma olarak ele alinmali

- ID conflict:
  - `634`
  - anlami: farkli RGB + ayni ID
  - bunlar province referansli dosyalar acisindan ileride kritik risk tasiyor

- quality flags:
  - `188`
  - bos isim, placeholder, veya name/comment divergence gibi ek kalite uyarilari

- manual ID review gereken satir:
  - `1271`
  - kaynak: `definition_id_tracking.csv`
  - not: bu satir bazli sayidir; conflict ciftlerinin her iki tarafi da burada isaretlenebilir

- Validation durumu:
  - `modlu_dogu`: `True`
  - `modlu_kalan`: `True`
  - `orijinal_dogu`: `True`
  - `orijinal_kalan`: `True`

- En onemli yorum:
  - su anki ana problem tanim eksigi degil
  - aktif problem, subsetler arasi kimlik cakismalari

## Kullanici Notlari

- Kullanici `hafiza.md` icinde kendi yazdiklari ile benim ne anladigimin de tutulmasini istiyor.
- Kullanici hafizanin kisa olmasindansa dolu ve bilgili olmasini tercih ediyor.
- Kullanici once tartisma ve plan, sonra uygulama sekliyle ilerlemek istiyor.
- Kullanici, daha sonra verdigi yetkiyle mevcut konu icin eyleme gecilebilecegini acikca belirtti.

## Benim Anladigim

- Bundan sonra kararlar ve ara bulgular daha net sekilde `hafiza.md`ye yazilabilir.
- Uzun teknik analizler ayri dosyalara da yazilmali.
- `definition_birlesim.csv` olusturma sureci, `provinces_birlesim.png` ile iki `definition` sozlugunun kontrollu birlesiminden cikacak.
- Nihai oyun dosyalarina genis capli dokunmadan once `definition` seviyesindeki kimlik ve cakisma modeli netlestirilmeli.

## Son Tartisma Netlesmeleri

- `same RGB + different ID` durumu zaten aktif olarak tartisilan ana teknik problemdir; bu konuda `provinces_birlesim.png` uzerinde kontrollu recolor ihtiyaci olabilecegi kabul edildi.
- Placeholder province fikri su an ciddi ve mesru bir secenek olarak tartisiliyor, ancak bu hala kesin uygulanmis karar degil.
- Placeholder yaklasimi esas olarak `ID` ardissikligi sorununa aday bir cozumdur; `RGB` cakismalarini tek basina cozmez.
- Kullanici 2026-04-11 tarihinde acikca su duzeltmeyi yapti:
  - `634` adet `ID conflict` placeholder ile cozulecek bir konu degil
  - bu conflict'ler icin cozum, gerekli province'lere yeni `final_new_id` vermek ve eski `id/rgb/source` bilgisini tam takip etmektir
  - yani placeholder mantigi ile `ID conflict` cozumu ayni sey degildir
- Gizli teknik bolgede placeholder province boyama ve bunu `default.map` icinde yorumlu bir `impassable_mountains` bloguyla belgeleme fikri olumlu degerlendirildi, ama teknik ayrintilari hala acik.
- Kullanici ayrica sunu netlestirdi:
  - `119` adet `same RGB + different ID` vakasinda, modlu ya da orijinal taraftan hangisi secilecekse o karardan sonra diger tarafa yeni RGB verilecek
  - yani iki province de ayri yasayacaksa, paylasilan eski RGB yalnizca bir tarafta kalacak

## RGB Conflict Karar Asamasi

- Sıradaki fiili uygulama asamasi olarak `119` adet `same RGB + different ID` vakasi icin karar tablosu uretildi.
- Bu is icin script genisletildi:
  - `tools/build_definition_subset_audit.ps1`
- Yeni cikan ana dosya:
  - `analysis/generated/definition_rgb_conflict_decisions.csv`
- Yeni yardimci preview klasoru:
  - `analysis/generated/rgb_conflict_previews/`

- Bu yeni karar dosyasinin mantigi:
  - her satir bir RGB conflict vakasini temsil eder
  - modlu ve orijinal taraftaki eski `id`, `name` ve ilgili piksel kapsami birlikte yazilir
  - karar asamasinda su alanlar daha sonra doldurulabilir:
    - `keep_original_rgb_source`
    - `recolor_source`
    - `new_rgb`
    - `final_modlu_id`
    - `final_orijinal_id`
    - `decision_notes`

- Script bu dosya icin ayrica yardimci uzamsal bilgi de uretir:
  - `modlu_pixel_count`
  - `modlu_bbox`
  - `orijinal_pixel_count`
  - `orijinal_bbox`
  - `modlu_preview_path`
  - `orijinal_preview_path`
- Bu sayede, conflict karari verirken province'in secili alt-kumedeki kapladigi alan ve yaklasik konumu gorulebilir.

- Karar vermeyi hizlandirmak icin mekanik bir oneri katmani da eklendi:
  - `suggest_keep_original_rgb_source`
  - `suggest_recolor_source`
  - `suggestion_reason`
- Bu oneri katmani bir adim daha genisletildi:
  - `suggest_new_rgb`
  - `suggest_new_rgb_reason`
- Bu bir politika karari degil, yalnizca yardimci heuristiktir.
- Su anki heuristic mantigi:
  - daha az piksel kaplayan tarafi recolor etmek daha ucuz olabilir
  - bu yuzden daha kucuk `pixel_count` sahibi taraf `suggest_recolor_source` olarak isaretlenir
  - ayrica, modlu+orijinal definition renk uzayinda bos olan bir `suggest_new_rgb` otomatik onerilir

- Guncel sonuc:
  - `definition_rgb_conflict_decisions.csv` satir sayisi: `119`
  - bu, `definition_rgb_conflicts.csv` icindeki conflict sayisiyla birebir uyumlu
  - `rgb_conflict_previews/` icindeki preview dosya sayisi: `238`
  - heuristic dagilimi:
    - `suggest_recolor_source = modlu`: `105`
    - `suggest_recolor_source = orijinal`: `14`

- Bu onerilere dayanarak yeni bir taslak dosya da uretildi:
  - `analysis/generated/rgb_mapping_draft.csv`
- Bu dosya:
  - `119` satir icerir
  - her satirda hangi tarafin recolor edilmesinin onerildigi
  - etkilenen subset/id/name
  - ilgili preview yolu
  - onerilen yeni RGB
  - ve heuristic gerekcesi yazilir
- Onemli:
  - bu dosya final karar degildir
  - yalnizca review edilebilir taslak mapping katmanidir

## Olusturulan Dosyalar ve Amaclari

- `tools/build_definition_subset_audit.ps1`
  - amac: subset definition dosyalarini ve bunlara bagli audit/rapor dosyalarini tekrar uretmek
  - neden olusturuldu: `provinces_*.png` secimlerinden sistematik ve tekrar calistirilabilir sekilde `definition` alt-kumeleri, conflict raporlari ve takip tablolari cikarmak

- `map_data/definition_modlu_dogu.csv`
  - amac: `provinces_modlu_dogu.png` icindeki yasayan RGB'lerin `definition_modlu.csv` karsiliklarini tutmak
  - neden olusturuldu: mod tarafindaki dogu secimini ayri bir definition alt-kumesi olarak gorebilmek

- `map_data/definition_modlu_kalan.csv`
  - amac: `provinces_modlu_kalan.png` icindeki yasayan RGB'lerin `definition_modlu.csv` karsiliklarini tutmak
  - neden olusturuldu: final birlesimde moddan kalacak province'leri tanim seviyesinde ayiklamak

- `map_data/definition_orijinal_dogu.csv`
  - amac: `provinces_orijinal_dogu.png` icindeki yasayan RGB'lerin `definition_orijinal.csv` karsiliklarini tutmak
  - neden olusturuldu: final birlesimde vanilla/orijinal taraftan alinacak dogu province'lerini tanim seviyesinde ayiklamak

- `map_data/definition_orijinal_kalan.csv`
  - amac: `provinces_orijinal_kalan.png` icindeki yasayan RGB'lerin `definition_orijinal.csv` karsiliklarini tutmak
  - neden olusturuldu: vanilla tarafinin dogu disi referans alt-kumesini de kontrol edebilmek ve secimlerin ic tutarliligini dogrulamak

- `analysis/generated/definition_modlu_dogu_rgb_inventory.csv`
  - amac: `provinces_modlu_dogu.png` icinden secilen tum non-black RGB'leri tek tek kaydetmek
  - neden olusturuldu: PNG'den hangi renklerin gercekten alindigini kalici olarak belgelemek

- `analysis/generated/definition_modlu_kalan_rgb_inventory.csv`
  - amac: `provinces_modlu_kalan.png` icinden secilen tum non-black RGB'leri tek tek kaydetmek
  - neden olusturuldu: moddan kalan kisim icin renk envanterini kaybetmemek ve subset extraction'i tekrar kontrol edebilmek

- `analysis/generated/definition_orijinal_dogu_rgb_inventory.csv`
  - amac: `provinces_orijinal_dogu.png` icinden secilen tum non-black RGB'leri tek tek kaydetmek
  - neden olusturuldu: vanilla dogu seciminin exact RGB setini kalici kayit altina almak

- `analysis/generated/definition_orijinal_kalan_rgb_inventory.csv`
  - amac: `provinces_orijinal_kalan.png` icinden secilen tum non-black RGB'leri tek tek kaydetmek
  - neden olusturuldu: vanilla kalan seciminin exact RGB setini kaydetmek ve tutarlilik kontrolu yapmak

- `analysis/generated/definition_subset_validation.csv`
  - amac: her subset icin PNG renk sayisi, cekilen satir sayisi ve RGB inventory satir sayisini karsilastirmak
  - neden olusturuldu: subset extraction adiminin sayisal olarak tam tutup tutmadigini gostermek

- `analysis/generated/definition_rgb_conflicts.csv`
  - amac: `same RGB + different ID` conflict listesini sade formatta vermek
  - neden olusturuldu: ana RGB cakisma kumesini hizli okumak ve kontrol etmek

- `analysis/generated/definition_rgb_conflict_decisions.csv`
  - amac: `119` RGB conflict icin karar verme ve daha sonra recolor uygulama tablosu olmak
  - neden olusturuldu: hangi tarafin eski RGB'yi koruyacagi, hangi tarafin yeni RGB alacagi ve final ID'lerin nasil baglanacaginin tek dosyada islenebilmesi

- `analysis/generated/rgb_conflict_previews/`
  - amac: her RGB conflict icin modlu ve orijinal tarafin province sekil preview'lerini tutmak
  - neden olusturuldu: `definition_rgb_conflict_decisions.csv` icindeki karar asamasinda tek tek harita aramaya gerek kalmadan ilgili province sekillerini hizli inceleyebilmek

- `analysis/generated/rgb_mapping_draft.csv`
  - amac: heuristic tabanli ilk recolor mapping taslagini vermek
  - neden olusturuldu: `suggest_recolor_source` ve `suggest_new_rgb` bilgilerini uygulamaya yakin, review edilebilir bir csv katmanina donusturmek

## Selective RGB Apply Asamasi

- Draft RGB mapping'in gercekten uygulanabilir olup olmadigini test etmek icin yeni bir script uretildi:
  - `tools/apply_selective_rgb_mapping.ps1`

- Bu scriptin amaci:
  - `rgb_mapping_draft.csv` benzeri bir mapping tablosunu alip
  - `provinces_birlesim.png` uzerinde yalnizca secilen subset tarafini recolor etmek
  - orijinal dosyayi bozmadan once sonuc gorselini ve uygulama raporunu uretmek

- Bu scriptin neden olusturuldugu:
  - `same RGB + different ID` durumlarinin yalnizca CSV mantiginda degil, gercek piksel seviyesinde de cozulup cozulemedigini dogrulamak
  - recolor'un global degil, subset-mask bazli secici sekilde yapildigini kanitlamak

- Bu asamada uretilen ana dosyalar:
  - `analysis/generated/provinces_birlesim_rgb_draft.png`
  - `analysis/generated/rgb_mapping_apply_report.csv`
  - `analysis/generated/rgb_mapping_apply_summary.md`

- Bu dosyalarin rolleri:
  - `provinces_birlesim_rgb_draft.png`
    - amac: draft recolor uygulanmis test cikti haritasi
    - neden olusturuldu: orijinal `provinces_birlesim.png`ye dokunmadan teknik uygulanabilirligi gormek
  - `rgb_mapping_apply_report.csv`
    - amac: her mapping satiri icin kac pikselin hedeflendigi ve gercekten degistirildigini gostermek
    - neden olusturuldu: recolor'un subset bazli dogru uygulandigini satir satir dogrulamak
  - `rgb_mapping_apply_summary.md`
    - amac: selective recolor turunun okunabilir markdown ozeti olmak
    - neden olusturuldu: toplam degisen piksel, mismatch ve tam uygulama sayilarini hizli okumak

- Guncel sonuc:
  - toplam mapping satiri: `119`
  - fully applied satir: `119`
  - total changed pixels: `24443`
  - total base mismatch pixels: `0`

- Bu sonucun anlami:
  - heuristic draft mapping teknik olarak uygulanabildi
  - `provinces_birlesim.png` icinde secici recolor mantigi calisiyor
  - en azindan draft seviyesinde, secilen subset pikselleri hedeflenen yeni RGB'lere kaydirilabildi

## RGB Resolved Candidate Asamasi

- RGB duzeyindeki kararlarin `definition` envanterine de yansitilmasi icin yeni bir script uretildi:
  - `tools/build_rgb_resolved_candidates.ps1`

- Bu scriptin amaci:
  - `definition_merge_inventory.csv` uzerindeki satirlara `effective_rgb` mantigi islemek
  - recolor edilen province'leri ve eski RGB'yi koruyan taraflari tek bir ara tabloda gostermek
  - `benign_shared` ciftlerini final ID asamasindan once tek candidate satira indirmek

- Bu scriptin neden olusturuldugu:
  - RGB problemi cozuldukten sonra, siradaki buyuk asama olan ID atamasi icin `definition` tarafinda daha temiz ve yararli bir temel tabloya ihtiyac vardi

- Bu asamada uretilen dosyalar:
  - `analysis/generated/definition_rgb_resolved_inventory.csv`
  - `analysis/generated/definition_rgb_resolved_candidates_pre_id.csv`
  - `analysis/generated/definition_rgb_resolved_summary.md`

- Bu dosyalarin rolleri:
  - `definition_rgb_resolved_inventory.csv`
    - amac: tum merge satirlarini koruyup her satir icin `effective_rgb` degerini gostermek
    - neden olusturuldu: recolor edilen ve eski RGB'yi koruyan satirlari tek inventory katmaninda toplamak
  - `definition_rgb_resolved_candidates_pre_id.csv`
    - amac: `benign_shared` tekrarlarini merge edip final ID oncesi candidate satir listesi cikarmak
    - neden olusturuldu: ID atama asamasina daha yakin, daha temiz bir candidate tablosu elde etmek
  - `definition_rgb_resolved_summary.md`
    - amac: resolved inventory ve pre-ID candidate asamasinin ozetini vermek
    - neden olusturuldu: recolor sonrasi satir sayilarini ve merge etkisini hizli okumak

- Guncel sonuc:
  - resolved inventory row count: `13282`
  - pre-ID candidate row count: `13261`
  - recolored rows: `119`
  - keep-original-shared-rgb rows: `119`
  - benign-shared rows in inventory: `42`
  - benign-shared merged candidates: `21`

- Bu sonucun anlami:
  - RGB tarafindaki kararlar `definition` tarafina basariyla tasindi
  - `benign_shared` tekrarlar final ID asamasi icin tek candidate'a indirildi
  - bundan sonraki ana problem artik agirlikli olarak ID stratejisi

## Pre-ID Strategy Analizi

- RGB-resolved candidate seti icin mevcut ID manzarasini sayisallastirmak amaciyla yeni bir script uretildi:
  - `tools/analyze_pre_id_strategy.ps1`

- Bu scriptin amaci:
  - mevcut candidate satirlarin eski ID dagilimini cikarmak
  - duplicate ID gruplarini bulmak
  - bos ID araliklarini cikarip placeholder yukunu sayisallastirmak

- Bu scriptin neden olusturuldugu:
  - "eski ID'leri ne kadar koruyabiliriz" sorusunu sezgisel degil, sayisal veriyle tartisabilmek

- Bu asamada uretilen dosyalar:
  - `analysis/generated/current_id_candidate_inventory.csv`
  - `analysis/generated/id_duplicates_pre_id.csv`
  - `analysis/generated/id_gap_ranges_pre_id.csv`
  - `analysis/generated/id_strategy_pre_id_summary.md`

- Bu dosyalarin rolleri:
  - `current_id_candidate_inventory.csv`
    - amac: her pre-ID candidate satir icin mevcut/kanonik eski ID'yi gosterir envanter olmak
    - neden olusturuldu: duplicate ve gap analizinin ana girdisini kalici kaydetmek
  - `id_duplicates_pre_id.csv`
    - amac: ayni mevcut ID'yi paylasan candidate satirlari listelemek
    - neden olusturuldu: yeni `final_new_id` gerektiren duplicate kimlikleri topluca gormek
  - `id_gap_ranges_pre_id.csv`
    - amac: `1..max current ID` araligindaki bos ID araliklarini range bazli kaydetmek
    - neden olusturuldu: placeholder veya contiguous strateji maliyetini olcmek
  - `id_strategy_pre_id_summary.md`
    - amac: duplicate/gap analizinin markdown ozeti olmak
    - neden olusturuldu: hangi ID stratejisinin daha az maliyetli oldugunu hizli tartisabilmek

- Guncel sonuc:
  - candidate row count: `13261`
  - unique current ID count: `12627`
  - max current ID: `14696`
  - duplicate current ID groups: `634`
  - duplicate current ID rows: `1268`
  - one row per duplicate group eski ID'yi korursa yeni ID ihtiyaci: `634`
  - missing ID count from `1..14696`: `2069`
  - gap range count: `135`
  - eger tum unique eski ID'leri koruyup arayi contiguous yapmak istersek placeholder ihtiyaci: `2069`

- Bu sonucun anlami:
  - ID problemi artik sayisal olarak cok daha net
  - duplicate yuzunden en az `634` yeni ID gerekecek
  - eski unique ID'leri topluca koruma denemesi ise `2069` placeholder yukune yol acacak

## ID Policy Draft Asamasi

- ID tarafi icin iki somut draft politika uretildi:
  - `old-id-heavy / preserve_old_ids`
  - `full_renumber`

- Bu is icin yeni bir script uretildi:
  - `tools/build_id_policy_drafts.ps1`

- Bu scriptin amaci:
  - ayni pre-ID candidate setinden iki farkli final ID atama taslagi cikarmak
  - her politika icin source bazli `old_id -> final_new_id` map dosyalari uretmek
  - placeholder yukunu ve ID degisim yukunu sayisal olarak karsilastirmak

- Bu scriptin neden olusturuldugu:
  - "hangi ID stratejisi daha az aci verir" sorusunu sezgiyle degil, dogrudan draft ciktılarla tartisabilmek

- Bu asamada uretilen dosyalar:
  - `analysis/generated/id_policy_preserve_old_assignments.csv`
  - `analysis/generated/id_policy_preserve_old_placeholders.csv`
  - `analysis/generated/id_map_modlu_preserve_old.csv`
  - `analysis/generated/id_map_orijinal_preserve_old.csv`
  - `analysis/generated/id_policy_full_renumber_assignments.csv`
  - `analysis/generated/id_map_modlu_full_renumber.csv`
  - `analysis/generated/id_map_orijinal_full_renumber.csv`
  - `analysis/generated/id_policy_source_burden.csv`
  - `analysis/generated/id_policy_drafts_summary.md`

- Bu dosyalarin rolleri:
  - `id_policy_preserve_old_assignments.csv`
    - amac: old-id-heavy draft politikadaki gercek province satirlarinin final ID atamalarini vermek
    - neden olusturuldu: mumkun oldugunca eski ID koruyan draft'i somutlastirmak
  - `id_policy_preserve_old_placeholders.csv`
    - amac: old-id-heavy draft'te contiguous kalmak icin gereken placeholder satirlarini vermek
    - neden olusturuldu: placeholder yukunu soyut degil, satir seviyesinde gormek
  - `id_map_modlu_preserve_old.csv`
    - amac: modlu satirlar icin old-id-heavy draft `old_id -> final_new_id` map'i olmak
    - neden olusturuldu: daha sonra mod tarafindaki province referansli dosyalari guncellerken kullanmak
  - `id_map_orijinal_preserve_old.csv`
    - amac: orijinal satirlar icin old-id-heavy draft `old_id -> final_new_id` map'i olmak
    - neden olusturuldu: vanilla/orijinal import edilen province referanslarini daha sonra guncellerken kullanmak
  - `id_policy_full_renumber_assignments.csv`
    - amac: full renumber draft'inde tum gercek province satirlarin final ID atamalarini vermek
    - neden olusturuldu: placeholder'siz alternatif stratejiyi somutlastirmak
  - `id_map_modlu_full_renumber.csv`
    - amac: modlu satirlar icin full renumber draft `old_id -> final_new_id` map'i olmak
    - neden olusturuldu: modlu referanslari genis capli yeniden numaralandirmada takip etmek
  - `id_map_orijinal_full_renumber.csv`
    - amac: orijinal satirlar icin full renumber draft `old_id -> final_new_id` map'i olmak
    - neden olusturuldu: orijinal referanslari genis capli yeniden numaralandirmada takip etmek
  - `id_policy_source_burden.csv`
    - amac: her politika altinda source bazli ne kadar satirin eski ID'yi korudugunu veya degistirdigini gostermek
    - neden olusturuldu: degisim yukunun modlu mu, orijinal mi tarafina bindigini sayisal gormek
  - `id_policy_drafts_summary.md`
    - amac: iki draft politikanin ozet karsilastirmasini markdown olarak vermek
    - neden olusturuldu: draft sonuclarini hizli okumak ve tartismak

- Guncel sonuc:
  - `preserve_old_ids`
    - current ID'yi koruyan candidate satir: `12627`
    - yeni ID alan candidate satir: `634`
    - mevcut gap'lere yerlestirilen duplicate satir: `634`
    - max old ID ustune append ihtiyaci: `0`
    - placeholder ihtiyaci: `1435`
    - final max ID: `14696`
    - degisen `modlu_kalan` satir: `0`
    - degisen `orijinal_dogu` satir: `634`
  - `full_renumber`
    - current ID'yi tesadufen koruyan satir: `615`
    - ID'si degisen satir: `12646`
    - placeholder ihtiyaci: `0`
    - final max ID: `13261`
    - degisen `modlu_kalan` satir: `9508`
    - degisen `orijinal_dogu` satir: `3138`

- Bu sonucun anlami:
  - `preserve_old_ids` draft'i degisim yukunu neredeyse tamamen `orijinal_dogu` tarafina iter
  - `full_renumber` draft'i ise her iki tarafa da buyuk bir yeniden numaralandirma yukler
  - temel tradeoff artik cok net:
    - az ID degisikligi + cok placeholder
    - sifir placeholder + cok fazla ID degisikligi

## Definition Policy Draft Asamasi

- ID draft'lerinden gercek `definition.csv` taslaklari da uretildi.
- Bu is icin yeni bir script uretildi:
  - `tools/build_definition_csv_drafts.ps1`

- Bu scriptin amaci:
  - draft ID assignment ciktılarini CK3 `definition.csv` bicimine donusturmek
  - contiguity ve duplicate RGB gibi temel teknik kontrolleri otomatik yapmak

- Bu scriptin neden olusturuldugu:
  - tartisilan ID politikalarinin gercek `definition.csv` ciktilarina donustugunde teknik olarak gecerli olup olmadigini aninda gorebilmek

- Bu asamada uretilen dosyalar:
  - `analysis/generated/definition_policy_preserve_old_draft.csv`
  - `analysis/generated/definition_policy_full_renumber_draft.csv`
  - `analysis/generated/definition_policy_draft_validation.csv`
  - `analysis/generated/definition_policy_drafts_summary.md`

- Bu dosyalarin rolleri:
  - `definition_policy_preserve_old_draft.csv`
    - amac: old-id-heavy draft'ten uretilmis gercek `definition.csv` taslagi olmak
    - neden olusturuldu: placeholder'li stratejinin teknik gecerliligini gormek
  - `definition_policy_full_renumber_draft.csv`
    - amac: full renumber draft'ten uretilmis gercek `definition.csv` taslagi olmak
    - neden olusturuldu: placeholder'siz stratejinin teknik gecerliligini gormek
  - `definition_policy_draft_validation.csv`
    - amac: her iki draft'in row count, max id, placeholder count, duplicate RGB ve contiguous ID durumunu topluca gostermek
    - neden olusturuldu: hangi draft'in teknik olarak saglam oldugunu hizli kontrol etmek
  - `definition_policy_drafts_summary.md`
    - amac: definition draft sonuclarinin markdown ozeti olmak
    - neden olusturuldu: iki policy `definition` ciktilarini karsilastirmayi kolaylastirmak

- Guncel validation sonucu:
  - `preserve_old_ids` draft:
    - data rows: `14696`
    - placeholders: `1435`
    - duplicate RGB: `0`
    - missing IDs: `0`
    - contiguous: `True`
  - `full_renumber` draft:
    - data rows: `13261`
    - placeholders: `0`
    - duplicate RGB: `0`
    - missing IDs: `0`
    - contiguous: `True`

- Bu sonucun anlami:
  - her iki draft da teknik olarak gecerli `definition.csv` taslagi uretiyor
  - yani bu noktadan sonra tartisma "calisir mi" degil, daha cok "hangi bakim stratejisi daha az maliyetli" sorusuna donmus durumda

- `analysis/generated/definition_id_conflicts.csv`
  - amac: `different RGB + same ID` conflict listesini vermek
  - neden olusturuldu: yeni `final_new_id` gerektiren kimlik cakismalarini belirlemek

- `analysis/generated/definition_shared_same_id.csv`
  - amac: `same RGB + same ID` olan benign overlap vakalarini gostermek
  - neden olusturuldu: hata olmayan paylasimlari conflict'lerden ayirmak

- `analysis/generated/definition_quality_flags.csv`
  - amac: bos isim, placeholder benzeri isim ve name/comment divergence gibi kalite uyarilarini toplamak
  - neden olusturuldu: final merge oncesi veri temizligi gereken satirlari ayri gormek

- `analysis/generated/definition_merge_inventory.csv`
  - amac: modlu_kalan + orijinal_dogu icindeki tum satirlari ortak bir envanter tablosunda gostermek
  - neden olusturuldu: her satirin source, partner conflict durumu ve merge statulerini tek yerde toplamak

- `analysis/generated/definition_id_tracking.csv`
  - amac: gelecekte yeni final ID atanacak satirlarin birincil takip tablosu olmak
  - neden olusturuldu: eski `source_id`, `source_rgb`, `source_name`, `source_subset` ve gelecekteki `final_new_id` iliskisini kaybetmemek

- `analysis/generated/definition_subset_audit.md`
  - amac: tum subset extraction ve audit ciktisinin okunabilir markdown ozeti olmak
  - neden olusturuldu: sayisal sonuclari ve ana rapor dosyalarini tek yerde hizli okumak

## Ayri Analiz Dosyasi

- Daha uzun ve fazlandirilmis teknik notlar icin bak:
  - `analysis/definition_birlesim_plan.md`

## Repo Impact Asamasi

- Iki ID politikasinin mevcut mod reposu uzerinde ne kadar downstream dosya duzenleme yuku getirecegini sayisal gormek icin yeni bir script yazildi:
  - `tools/build_id_policy_repo_impact.ps1`

- Bu scriptin amaci:
  - mevcut repo icindeki aktif province ID referanslarini taramak
  - `preserve_old_ids` ve `full_renumber` altinda hangi referanslarin degisecegini saymak
  - karar verirken sadece `definition.csv` gecerliligine degil, gercek duzenleme maliyetine de bakmak

- Bu scriptin neden olusturuldugu:
  - iki ID politikasinin teknik olarak calistigi zaten gorulmustu
  - ama asil stratejik soru, repo genelinde hangi politikanin daha az kirilim ve daha az toplu refactor gerektirdigiydi

- Script once iki kez hata verdi ve duzeltildi:
  - `Sort-Object` coklu property yazimi parser hatasi veriyordu; hashtable-property siralamaya cevrildi
  - tek satirli dosyalarda `Get-Content` string dondurdugu icin `.Count` hatasi aliyordu; tum line okumalar `@(...)` ile diziye zorlandi

- Bu asamada uretilen dosyalar:
  - `analysis/generated/id_policy_repo_impact_by_context.csv`
  - `analysis/generated/id_policy_repo_impact_by_file.csv`
  - `analysis/generated/id_policy_repo_impact_summary.md`

- Bu dosyalarin rolleri:
  - `id_policy_repo_impact_by_context.csv`
    - amac: referans tipine gore (landed_titles, history/provinces, adjacencies, default.map vb.) iki ID politikasinin kac satiri etkileyecegini gostermek
    - neden olusturuldu: degisim yukunun hangi sistemlerde yogunlastigini gormek
  - `id_policy_repo_impact_by_file.csv`
    - amac: dosya bazinda hangi dosyalarin ne kadar etkilenecegini gostermek
    - neden olusturuldu: daha sonra gercek edit asamasinda en pahali dosyalari onceden bilmek
  - `id_policy_repo_impact_summary.md`
    - amac: repo etki sonucunun hizli okunabilir markdown ozeti olmak
    - neden olusturuldu: politikalar arasi bakim maliyet farkini tek bakista gormek

- Bu scriptin taradigi aktif referans baglamlari:
  - `history/provinces` icindeki province block header ID'leri
  - `history/province_mapping` icindeki sol ve sag numeric mapping satirlari
  - `common/landed_titles` icindeki aktif `province = <id>` satirlari
  - `common/situation` icindeki aktif `capital_province = <id>` satirlari
  - `history/titles` icindeki aktif `capital = <id>` satirlari
  - `map_data/adjacencies.csv`
  - `map_data/default.map` icindeki aktif `LIST {}` ve `RANGE {}` province ID satirlari
  - `map_data/island_region.txt`, `map_data/geographical_regions/*.txt`, `common/connection_arrows/*.txt` icindeki aktif `provinces = {}` bloklari

- Cok onemli yorum:
  - bu repo impact taramasi mevcut mod reposundaki aktif province referanslari icin yapildi
  - yani esasen mod tarafinin bugunku ID uzayina dokunma maliyetini olcer
  - vanilla/orijinalden ithal edilecek dogu province'lerinin henuz repo icine tasinmamis gelecekteki referanslari bu raporda dogal olarak yoktur

- Guncel sonuc:
  - `preserve_old_ids`
    - changed references: `0`
    - touched lines: `0`
  - `full_renumber`
    - changed references: `19499`
    - touched lines: `18206`

- Bu sonucun anlami:
  - mevcut repo mod ID uzayini kullandigi icin `preserve_old_ids` secenegi bugunku dosyalarin neredeyse tamamini oldugu gibi birakiyor
  - `full_renumber` ise mevcut mod tarafinda cok buyuk bir toplu duzenleme dalgasi gerektiriyor
  - bu nedenle repo bakim maliyeti acisindan su anki en guclu aday politika `preserve_old_ids`

- Full renumber altinda en cok etkilenen context'ler:
  - `common_landed_titles_province`: `8327` touched line
  - `history_provinces_block_header`: `7897` touched line
  - `common_connection_arrows_provinces_block`: `486` touched line
  - `history_province_mapping_right`: `360` touched line
  - `history_province_mapping_left`: `360` touched line
  - `adjacencies_through`: `202` touched line
  - `adjacencies_to`: `180` touched line
  - `adjacencies_from`: `180` touched line

- Full renumber altinda en cok etkilenen dosyalar:
  - `common/landed_titles/00_landed_titles.txt`: `8327` touched line
  - `history/provinces/00_MB_PROVINCES.txt`: `7897` touched line
  - `history/province_mapping/00_guinea.txt`: `600` touched line
  - `map_data/adjacencies.csv`: `562` touched line
  - `common/connection_arrows/silk_road_arrows.txt`: `486` touched line
  - `map_data/default.map`: `170` touched line

- Bu asamadan cikan pratik sonuc:
  - teknik gecerlilik acisindan iki draft da olur
  - ama mevcut repo uzerinde uygulanabilirlik ve emek maliyeti acisindan `preserve_old_ids` cok daha avantajli gorunuyor
  - sonraki ana asama buyuk ihtimalle `preserve_old_ids` politikasini ana yol kabul edip final tracking/master tabloyu ona gore kurmak olmali

## Final Master Tracking Asamasi

- Repo impact sonucundan sonra `preserve_old_ids` pratik ana politika adayi olarak one ciktigi icin, bu politika etrafinda tek merkezli bir final tracking/master tablo katmani kuruldu.

- Bu is icin yeni bir script yazildi:
  - `tools/build_policy_master_tracking.ps1`

- Bu scriptin amaci:
  - secilen ID policy assignment ciktisini tek bir final master tabloya donusturmek
  - `modlu` ve `orijinal` kaynaklar icin ayri source-tracking csv'leri uretmek
  - eski `id/rgb/name/source` ile final `new_id/rgb/name` baglantisini kayipsiz tutmak
  - placeholder satirlarini da ayri bir inventory olarak cikarmak

- Bu scriptin neden olusturuldugu:
  - ileride province referansli oyun dosyalari duzenlenirken tek tek farkli ara csv'lere bakmak yerine, final gercegi tek bir master tablo ve source-map katmaninda toplamak gerekiyordu
  - kullanicinin ozellikle istedigi `old id`, `old rgb`, `source` bilgisini kalici ve sorgulanabilir tutmak gerekiyordu

- Bu script gelistirilirken bir kritik eksik yakalandi:
  - ilk surum sadece `id_policy_preserve_old_assignments.csv` girisini okuyordu
  - fakat `preserve_old_ids` politikasindaki placeholder satirlari ayri dosyada tutuluyordu: `id_policy_preserve_old_placeholders.csv`
  - bu nedenle ilk ozet yanlis olarak `13261` master row ve `0` placeholder gosterdi
  - script duzeltildi ve placeholder input'u da dahil edilerek tekrar calistirildi
  - dogru toplam artik:
    - master rows: `14696`
    - placeholder rows: `1435`

- Bu asamada uretilen dosyalar:
  - `analysis/generated/final_master_preserve_old_ids.csv`
  - `analysis/generated/final_modlu_tracking_preserve_old_ids.csv`
  - `analysis/generated/final_orijinal_tracking_preserve_old_ids.csv`
  - `analysis/generated/final_placeholder_inventory_preserve_old_ids.csv`
  - `analysis/generated/final_tracking_summary_preserve_old_ids.md`

- Bu dosyalarin rolleri:
  - `final_master_preserve_old_ids.csv`
    - amac: `preserve_old_ids` politikasindaki tum final satirlari tek tabloda toplamak
    - neden olusturuldu: final province gercegini `final_new_id` bazinda tek yerden izlemek
  - `final_modlu_tracking_preserve_old_ids.csv`
    - amac: modlu kaynakli province'ler icin `old_id -> final_new_id` ve `old_rgb -> final_rgb` takibini vermek
    - neden olusturuldu: mevcut mod referansli dosyalari guncellerken mod tarafinin kaydini kaybetmemek
  - `final_orijinal_tracking_preserve_old_ids.csv`
    - amac: orijinal/dogu kaynakli province'ler icin `old_id -> final_new_id` ve `old_rgb -> final_rgb` takibini vermek
    - neden olusturuldu: vanilla dogudan ithal edilen province'lerin yeni kimligini ve varsa recolor/renumber durumunu kalici kayit altina almak
  - `final_placeholder_inventory_preserve_old_ids.csv`
    - amac: `preserve_old_ids` altinda araya giren tum placeholder satirlarini listelemek
    - neden olusturuldu: ardissiklik icin olusan teknik satirlari ileride map/default.map tasarimiyla baglayabilmek
  - `final_tracking_summary_preserve_old_ids.md`
    - amac: final master tracking katmaninin okunabilir markdown ozeti olmak
    - neden olusturuldu: sayisal dagilimi ve degisim yukunu hizli okumak

- Guncel final tracking sonucu (`preserve_old_ids`):
  - master rows: `14696`
  - real candidate rows: `13261`
  - placeholder rows: `1435`
  - modlu tracking rows: `9891`
  - orijinal tracking rows: `3391`
  - modlu rows with changed final ID: `0`
  - orijinal rows with changed final ID: `634`
  - modlu rows with changed final RGB: `105`
  - orijinal rows with changed final RGB: `14`

- Real row source split:
  - `both`: `21`
  - `modlu`: `9870`
  - `orijinal`: `3370`

- Real row primary status split:
  - `benign_shared`: `21`
  - `id_conflict`: `1033`
  - `mod_only`: `9234`
  - `orijinal_only`: `2735`
  - `rgb_conflict`: `238`

- Bu sonucun anlami:
  - artik `preserve_old_ids` politikasinda hangi eski province'in finalde nereye gittigi tek merkezli olarak takip edilebiliyor
  - mod tarafinda ID degisikligi yok, yani mevcut mod dosyalari icin buyuk avantaj korunuyor
  - orijinal/dogu tarafinda `634` satir yeni final ID alacak
  - RGB recolor yukunun buyuk kismi mod tarafina (`105`) bindigi icin `provinces_birlesim.png` final uygulama asamasinda bu mapping'ler dikkatle kullanilmali

- Bu asamadan sonraki mantikli adim:
  - `preserve_old_ids` master tabloyu baz alip gercek uygulama sirasini tanimlamak
  - yani:
    - final `provinces_birlesim.png` RGB uygulamasi
    - final `definition_birlesim.csv`
    - sonra province referansli oyun dosyalari icin kontrollu update pipeline'i

## Final Preserve-Old Staging Asamasi

- Kullanici tarafindan kabul edilen plan gerceklestirildi:
  - `preserve_old_ids` ana politika olarak uygulandi
  - RGB tarafinda mevcut draft kararlar final staging temeli olarak kilitlendi
  - placeholder province'ler sag alt teknik bolgede, en sag alttan baslayan `1 pixel` duzenli grid olarak boyandi
  - bu boyama siyah alan zorunlulugu aramadan yapildi
  - kullanicinin duzeltmesine gore sag alt anchor alani `126,186,199` (`sea_indian_ocean`) ustune boyandi

- Bu is icin yeni bir script yazildi:
  - `tools/build_final_preserve_old_staging.ps1`

- Bu scriptin amaci:
  - final RGB mapping csv'sini draft mapping'den authoritative staging mapping'e cevirmek
  - `provinces_birlesim.png` uzerinde secici RGB recolor'u uygulamak
  - placeholder grid'i son final staging PNG uzerine boyamak
  - final `definition_birlesim` staging csv'sini uretmek
  - placeholder'lar icin `default.map` teknik blok taslagi uretmek
  - overpaint ve legacy-unused raporlarini cikarmak
  - final staging validation ozeti vermek

- Bu scriptin neden olusturuldugu:
  - daha once farkli script ve ara csv'lerle parcali kurulan pipeline'i tek seferde tekrar uretilebilir staging hattina cevirmek gerekiyordu
  - canli mod dosyalarina dokunmadan, kontrol edilebilir bir final taslak seti elde etmek gerekiyordu

- Script gelistirme notlari:
  - ilk parser hatasi `Sort-Object` coklu property yazimindan geldi; PowerShell uyumlu hashtable siralamaya cevrildi
  - `Add-Type` icindeki `nameof(...)` kullanimi ortam derleyicisi tarafindan desteklenmedi; klasik string argumana cevrildi
  - consecutive-run helper'in donus tipi PowerShell list/dizi uyumsuzlugu verdi; `ToArray()` ile sabitlendi
  - `default.map` staging blok satirlarinda format operatoru ile literal `{}` kullanimi hata veriyordu; brace escaping duzeltildi
  - son olarak validation markdown icindeki ufak format kusuru ve final RGB mapping notlarindaki eski `draft only` ifadesi temizlendi

- Bu asamada uretilen dosyalar:
  - `analysis/generated/rgb_mapping_final_preserve_old.csv`
  - `analysis/generated/provinces_birlesim_rgb_only_preserve_old.png`
  - `analysis/generated/rgb_mapping_final_apply_report_preserve_old.csv`
  - `analysis/generated/rgb_mapping_final_apply_summary_preserve_old.md`
  - `analysis/generated/provinces_birlesim_final_preserve_old.png`
  - `analysis/generated/placeholder_pixel_map_preserve_old.csv`
  - `analysis/generated/placeholder_overpaint_report_preserve_old.csv`
  - `analysis/generated/legacy_unused_after_placeholder_overpaint_preserve_old.csv`
  - `analysis/generated/definition_birlesim_final_preserve_old.csv`
  - `analysis/generated/default_map_placeholder_block_preserve_old.txt`
  - `analysis/generated/final_staging_validation_preserve_old.md`

- Bu dosyalarin rolleri:
  - `rgb_mapping_final_preserve_old.csv`
    - amac: draft RGB kararlarini authoritative final staging mapping'e cevirmek
    - neden olusturuldu: recolor isleminde artik hangi RGB'nin kesin secildigini sabitlemek
  - `provinces_birlesim_rgb_only_preserve_old.png`
    - amac: sadece RGB conflict recolor'u uygulanmis, placeholder henuz boyanmamis ara PNG olmak
    - neden olusturuldu: placeholder oncesi ve sonrasi asamalari ayirmak
  - `rgb_mapping_final_apply_report_preserve_old.csv`
    - amac: final RGB mapping satirlarinin piksel bazli ne kadar uygulandigini gostermek
    - neden olusturuldu: recolor uygulamasinin tam yapildigini dogrulamak
  - `rgb_mapping_final_apply_summary_preserve_old.md`
    - amac: recolor uygulama ozetini okunabilir markdown olarak vermek
    - neden olusturuldu: mapping tarafinin sonucunu hizli okumak
  - `provinces_birlesim_final_preserve_old.png`
    - amac: RGB recolor + placeholder grid boyamasi tamamlanmis final staging province haritasi olmak
    - neden olusturuldu: canli `provinces.png` oncesinde kontrol edilecek nihai taslak gorsel
  - `placeholder_pixel_map_preserve_old.csv`
    - amac: her placeholder final ID'sinin hangi piksele boyandigini kaydetmek
    - neden olusturuldu: teknik placeholder alanini koordinat bazinda izlemek
  - `placeholder_overpaint_report_preserve_old.csv`
    - amac: placeholder boyamasi sirasinda hangi mevcut province renginin ne kadar ustune yazildigini toplu gostermek
    - neden olusturuldu: placeholder teknik alaninin hangi province'i feda ettigini net kaydetmek
  - `legacy_unused_after_placeholder_overpaint_preserve_old.csv`
    - amac: final definition'da kalip final PNG'de artik hic pikseli olmayan satirlari listelemek
    - neden olusturuldu: placeholder overpaint sonrasi bos kalan eski province var mi diye kontrol etmek
  - `definition_birlesim_final_preserve_old.csv`
    - amac: `preserve_old_ids` politikasina gore uretilmis final staging `definition.csv` olmak
    - neden olusturuldu: canli `map_data/definition.csv` oncesi authoritative taslak tanimi saglamak
  - `default_map_placeholder_block_preserve_old.txt`
    - amac: placeholder province ID'lerini tek yorumlu teknik `impassable_mountains` blogu halinde vermek
    - neden olusturuldu: canli `default.map` degisikliginden once staging blok hazirlamak
  - `final_staging_validation_preserve_old.md`
    - amac: tum staging setinin dogrulama ve sayisal kontrol ozetini vermek
    - neden olusturuldu: final taslagin teknik olarak tutarli oldugunu tek yerde gostermek

- Guncel staging sonucu:
  - final image size: `9216x4608`
  - anchor base RGB before placeholder overlay: `126,186,199`
  - placeholder grid: `38` kolon x `38` satir
  - placeholder pixel count: `1435`
  - final non-black image color count: `14696`
  - final definition color count: `14696`
  - contiguous final definition IDs: `True`
  - duplicate RGB count in final definition: `0`
  - legacy unused definition rows after placeholder overpaint: `0`

- Placeholder overpaint sonucu:
  - placeholder boyamasi yalnizca `126,186,199` uzerine oturdu
  - bu renk `final_new_id = 12763`, isim `sea_indian_ocean`
  - overwritten pixel count: `1435`
  - baska hicbir province renginin ustune placeholder boyanmadi

- Bunun anlami:
  - kullanicinin istedigi teknik alan pratikte dogrudan `sea_indian_ocean` alani oldu
  - fakat bu boyama sonrasinda bile `legacy_unused` sayisi `0` cikti
  - yani `sea_indian_ocean` rengi haritada tamamen yok olmadi; alt sagdaki teknik alan disinda baska piksellerde de yasiyor

- Placeholder koordinat ornegi:
  - ilk placeholder `12773` su piksele boyandi: `9215,4607`
  - sonra sola dogru gidildi: `9214,4607`, `9213,4607` ...
  - satir dolunca bir ust satira gecildi

- `default.map` staging blok ozet sonucu:
  - blok yorumlu teknik placeholder bolumu olarak uretildi
  - hem `RANGE` hem `LIST` satirlari kullanildi
  - bloktaki ID kumesi placeholder inventory ile birebir ayni cikti

- RGB tarafi staging sonucu:
  - final RGB mapping authoritative dosyaya kilitlendi
  - mapping notlari artik yalnizca draft degil, final staging temeli oldugunu acikca belirtiyor
  - mevcut beklenen sayilar korundu:
    - modlu changed RGB: `105`
    - orijinal changed RGB: `14`

- ID / tracking tarafi staging boyunca korunan sayilar:
  - modlu changed ID: `0`
  - orijinal changed ID: `634`

- Bu asamanin pratik sonucu:
  - artik canli dosyalara terfi edilmeden once incelenebilecek tam bir final staging set var
  - province PNG, definition, placeholder koordinatlari, overpaint raporu ve `default.map` teknik blok taslagi birbirine bagli halde duruyor
  - bir sonraki mantikli asama, bu staging seti kullanarak gercek `map_data/provinces.png`, `map_data/definition.csv` ve `map_data/default.map` gecis planini uygulamak olacak

## Canli Map_Data Terfi Asamasi

- Staging setten canli `map_data` dosyalarina kontrollu terfi yapildi.

- Bu asamada yapilan canli degisiklikler:
  - `analysis/generated/provinces_birlesim_final_preserve_old.png` -> `map_data/provinces.png`
  - `analysis/generated/definition_birlesim_final_preserve_old.csv` -> `map_data/definition.csv`
  - `map_data/default.map` icine teknik placeholder blogu eklendi

- Bu asamanin amaci:
  - staging seti artik oyunun bekledigi gercek hedef dosya adlarina terfi ettirmek
  - `default.map` icindeki `definitions = "definition.csv"` ve `provinces = "provinces.png"` referanslarini fiilen karsilamak

- Bu asamada yapilan on kontrol:
  - `map_data/default.map` aktif olarak `definition.csv` ve `provinces.png` bekliyordu
  - fakat `map_data` klasorunde bu dosyalar yoktu
  - bu nedenle staging promotion yalnizca iyilestirme degil, ayni zamanda gerekli hedef dosyalari yerine koyma islevi gordu

- `default.map` placeholder blogu eklenirken yapilan ek akil yurutme:
  - placeholder inventory icindeki tum ID'ler kor olarak eklenmedi
  - once `default.map` icinde sayilar tarandi
  - `1435` placeholder ID'sinin `118` tanesinin zaten mevcut `impassable_mountains` satirlarinda bulundugu goruldu
  - bu nedenle canli `default.map`e yalnizca eksik `1317` ID eklendi
  - boylece gereksiz duplicate `impassable_mountains` kalabaligi olusturulmadi

- Bu asamada uretilen ek yardimci dosya:
  - `analysis/generated/default_map_placeholder_block_missing_only_preserve_old.txt`

- Bu dosyanin rolu:
  - amac: canli `default.map`e eklenecek filtrelenmis teknik placeholder blogunu saklamak
  - neden olusturuldu: staging bloktaki mevcut duplicate ID'leri ayiklayip yalnizca eksik placeholder ID'leri canli dosyaya temiz sekilde eklemek

- `default.map` icindeki canli ekleme:
  - blok, mevcut `impassable_mountains` bolumunun sonunda
  - `#Old Steppe. Re use these` satirlarindan sonra
  - yeni `sea_zones` satirlarina gecilmeden once yerlestirildi
  - blok bas/son yorumlari:
    - `# TECH PLACEHOLDER PROVINCES BEGIN`
    - `# TECH PLACEHOLDER PROVINCES END`

- Canli promotion sonrasi dogrulama:
  - `map_data/provinces.png` var: `True`
  - `map_data/definition.csv` var: `True`
  - `map_data/default.map` icinde teknik placeholder blogu bulundu: `True`
  - staging vs canli hash esitligi:
    - `provinces.png`: `True`
    - `definition.csv`: `True`

- Canli dosya boyutlari:
  - `map_data/provinces.png`: `3287215`
  - `map_data/definition.csv`: `441244`
  - `map_data/default.map`: `19802`

- Bu asamanin pratik sonucu:
  - mod artik province haritasi ve definition icin gercek hedef dosya adlarina sahip
  - `default.map` placeholder ID'leri de canli dosyada tanimli
  - staging set ile canli set arasinda province PNG ve definition tarafinda icerik farki yok

- Bu asamadan sonraki mantikli adim:
  - oyun/log seviyesinde smoke test
  - sonra province ID referansli diger canli dosyalari, tracking csv'lere bakarak gerekli yerlerde guncellemek

## Definition Name Encoding Notu

- Kullanici, `map_data/definition.csv` icinde bazi isimlerin bozuk gorundugunu bildirdi:
  - ornek: `Näsijärvi` yerine `NÃ¤sijÃ¤rvi`

- Yapilan tespit:
  - temiz kaynak dosyalar:
    - `map_data/definition_modlu.csv`
    - `map_data/definition_orijinal.csv`
    icinde isimler dogru UTF-8 olarak duruyor
  - bozulmus isimler esasen ara generated csv'lerdeki onceki encoding yanlis okumalarindan geliyor
  - ama canli `map_data/definition.csv` icin cok onemli bir nufans bulundu:
    - dosya UTF-8 olarak dogru icerige sahip
    - PowerShell `Get-Content` varsayilan encoding ile okununca isimler bozuk gorunuyor
    - ayni dosya `-Encoding utf8` ile okununca isimler dogru gorunuyor

- Bu nedenle sonuc:
  - canli `map_data/definition.csv` icindeki bayt duzeyi isimler zaten dogruydu
  - bozuk gorunumun bir kismi gosterim/okuma katmanindan kaynaklaniyordu

- Yine de isim onarimi icin yeni bir script yazildi:
  - `tools/repair_definition_names_from_sources.ps1`

- Bu scriptin amaci:
  - final master tracking tablosunu kullanip her final ID icin dogru source adini belirlemek
  - temiz UTF-8 kaynaklardan isimleri tekrar yuklemek
  - hedef definition dosyalarinda yalnizca isim sutununu duzeltmek

- Bu scriptin neden olusturuldugu:
  - isim katmanini gelecekte kontrollu sekilde yeniden kurabilmek
  - bozuk generated definition kopyalarini temiz kaynaklardan tekrar isimlendirmek

- Bu asamada uretilen dosyalar:
  - `analysis/generated/definition_name_repair_report.csv`
  - `analysis/generated/definition_name_repair_summary.md`

- Bu dosyalarin rolleri:
  - `definition_name_repair_report.csv`
    - amac: hangi final ID'de hangi eski ismin hangi yeni isme cevrildigini listelemek
    - neden olusturuldu: isim duzeltmesini denetlenebilir hale getirmek
  - `definition_name_repair_summary.md`
    - amac: hangi hedef dosyada kac isim duzeltmesi yapildigini ozetlemek
    - neden olusturuldu: onarimin sonucunu hizli okumak

- Scriptin hedefledigi dosyalar:
  - `map_data/definition.csv`
  - `analysis/generated/definition_birlesim_final_preserve_old.csv`

- Guncel sonuc:
  - `map_data/definition.csv` icin changed names: `0`
    - neden: dosya UTF-8 olarak zaten dogruydu; varsayilan yanlis okuma bozuk gorunum uretiyordu
  - `analysis/generated/definition_birlesim_final_preserve_old.csv` icin changed names: `98`
    - burada generated staging kopyasinda gercek mojibake isimler vardi ve onarildi

- Dogrulama:
  - `map_data/definition.csv` dosyasi UTF-8 ile okununca:
    - `Näsijärvi`
    - `Aral Teńizi`
    - `Kilikía`
    - `Aktí tis Taurikê`
    gibi isimler dogru gorunuyor
  - ayni dosya bozuk mojibake metni (`NÃ¤sijÃ¤rvi`) artik UTF-8 raw okumada icermiyor
## Works Klasoru Temizlik Asamasi

- Kullanici repo kokunde `Works` adinda ayri bir klasor acti.
- Bu asamanin ana amaci:
  - canli kullanilan son `map_data` dosyalarini yerinde birakmak
  - bizim uretdigimiz generated/developing dosyalari ayri klasorde toplamak
  - ortami temizleyip sonraki provinces downstream asamasina daha duzenli gecmek

- Kullanici tarafindan korunmasi istenen canli hedef dosyalar:
  - `map_data/provinces.png`
  - `map_data/default.map`
  - `map_data/definition.csv`

- Bu asamada gercekten yapilan tasimalar:
  - `analysis/generated/*` -> `Works/analysis/generated/`
  - `map_data` icindeki development source PNG/CSV dosyalari -> `Works/map_data_sources/`

- `Works/analysis/generated/` klasorunun rolu:
  - amac: bugune kadar uretilen tum audit, tracking, staging, preview ve final-draft dosyalarini tek yerde toplamak
  - neden olusturuldu: canli mod dosyalari ile analysis/generated kalabaligini ayirmak

- `Works/map_data_sources/` klasorunun rolu:
  - amac: merge sirasinda kullandigimiz kaynak `definition_*.csv` ve `provinces_*.png` dosyalarini saklamak
  - neden olusturuldu: `map_data` klasorunde sadece final canli province setini birakmak

- `Works/map_data_sources/` altina tasinan dosyalar:
  - `definition_modlu.csv`
  - `definition_modlu_kalan.csv`
  - `definition_orijinal.csv`
  - `definition_orijinal_dogu.csv`
  - `definition_orijinal_kalan.csv`
  - `provinces_birlesim.png`
  - `provinces_modlu.png`
  - `provinces_modlu_dogu.png`
  - `provinces_modlu_kalan.png`
  - `provinces_orijinal.png`
  - `provinces_orijinal_dogu.png`
  - `provinces_orijinal_kalan.png`

- Temizlik sonrasi yorum kuralı:
  - onceki notlarda gecen `analysis/generated/...` yollarinin buyuk cogu artik fiziksel olarak `Works/analysis/generated/...` altinda bulunuyor
  - onceki notlarda gecen `map_data/definition_modlu*.csv`, `map_data/definition_orijinal*.csv` ve `map_data/provinces_*` source dosyalari artik `Works/map_data_sources/...` altinda bulunuyor
  - canli authoritative province seti ise halen su uc dosya:
    - `map_data/provinces.png`
    - `map_data/definition.csv`
    - `map_data/default.map`

- Temizlik sonrasi `map_data` klasorunde kalan ana dosya yapisi:
  - `provinces.png`
  - `definition.csv`
  - `default.map`
  - ve normal CK3 map altyapi dosyalari:
    - `adjacencies.csv`
    - `geographical_regions/`
    - `gude-2026-03-26.log`
    - `heightmap.heightmap`
    - `heightmap.png`
    - `indirection_heightmap.png`
    - `island_region.txt`
    - `nodes.dat`
    - `packed_heightmap.png`
    - `rivers.png`

- Bu asamanin pratik sonucu:
  - repo kokundeki generated kalabalik `Works` altina toplandi
  - `map_data` artik final canli map_data setini daha net temsil ediyor
  - bundan sonraki provinces downstream calismalarinda yanlislikla eski source/preview dosyalarini hedef alma riski azaldi
## Works Altina Tools Ve Analysis Tasinmasi

- Kullanici, kokte hala duran `tools` ve `analysis` klasorlerinin de `Works` altina alinmasini acikca istedi.

- Bu asamada yapilan tasima:
  - `analysis/definition_birlesim_plan.md` -> `Works/analysis/definition_birlesim_plan.md`
  - `tools/*.ps1` -> `Works/tools/`

- `Works/tools/` klasorunun rolu:
  - amac: merge, audit, tracking, staging, name-repair ve policy uretim scriptlerini tek yerde toplamak
  - neden olusturuldu: kokte teknik script kalabaligini azaltmak ve calisma dosyalarini `Works` altinda toplamak

- `Works/tools/` altina tasinan scriptler:
  - `analyze_pre_id_strategy.ps1`
  - `apply_selective_rgb_mapping.ps1`
  - `build_definition_csv_drafts.ps1`
  - `build_definition_subset_audit.ps1`
  - `build_final_preserve_old_staging.ps1`
  - `build_id_policy_drafts.ps1`
  - `build_id_policy_repo_impact.ps1`
  - `build_policy_master_tracking.ps1`
  - `build_rgb_resolved_candidates.ps1`
  - `repair_definition_names_from_sources.ps1`

- `Works/analysis/definition_birlesim_plan.md` dosyasinin rolu:
  - amac: birlesim mantiginin uzun teknik planini, asamalari ve karar notlarini saklamak
  - neden oraya tasindi: `analysis/generated` zaten `Works/analysis/generated` altina alinmisti; plan dosyasinin da ayni ana klasorde durmasi daha tutarli oldu

- Tasima sonrasi kok durumu:
  - eski `analysis` klasoru bosaldigi icin kaldirildi
  - eski `tools` klasoru bosaldigi icin kaldirildi
  - kokte canli mod dosyalari ve genel mod klasorleri kaldi

- Bu asamanin pratik sonucu:
  - artik tum development/analysis/script varliklari `Works` altinda toplandi
  - kokteki ana odak canli mod yapisi ve `map_data` oldu
  - bundan sonraki downstream province entegrasyon asamalarinda aranacak yardimci dosyalar:
    - `Works/tools/...`
    - `Works/analysis/...`
    - `Works/map_data_sources/...`
## Province Touchpoints Envanteri

- Kullanici yeni asamada mod icinde province ile ilgili butun dosya ve kisimlari bulmamizi istedi.
- Bu asamanin hedefi:
  - province merge sonrasi hangi dosya ailelerine dokunmamiz gerekecegini tek yerde gormek
  - canli `map_data` degisince etkilenebilecek downstream dosyalari envanterlemek

- Bu is icin yeni script olusturuldu:
  - `Works/tools/build_province_touchpoints_inventory.ps1`

- Bu scriptin rolu:
  - amac: mod icinde province ile dogrudan veya dolayli ilgili dosyalari kategorilere ayirip listelemek
  - neden olusturuldu: sonraki downstream entegrasyon asamalarinda hangi dosya ailelerinin taranacagini ve oncelik sirasini netlestirmek

- Bu scriptin uretdigi dosyalar:
  - `Works/analysis/generated/province_touchpoints_inventory.csv`
  - `Works/analysis/generated/province_touchpoints_inventory.md`
  - `Works/analysis/generated/province_touchpoints_category_counts.csv`

- Bu dosyalarin rolleri:
  - `province_touchpoints_inventory.csv`
    - amac: her file path icin kategori, oncelik, neden ve varsa ilk evidence satirini tutmak
    - neden olusturuldu: province ile ilgili tum dosya temas noktalarini makine-okunur tam liste olarak saklamak
  - `province_touchpoints_inventory.md`
    - amac: ayni envanterin insan-okunur ozetini vermek
    - neden olusturuldu: hizli kategori bazli tarama yapabilmek
  - `province_touchpoints_category_counts.csv`
    - amac: kategori bazinda kac dosya oldugunu gostermek
    - neden olusturuldu: is yukunu ve oncelikli aileleri hizli degerlendirmek

- Guncel sayilar:
  - `history_provinces`: `186`
  - `history_titles`: `257`
  - `landed_titles`: `12`
  - `map_data_core`: `5`
  - `map_data_regions`: `11`
  - `map_object_data`: `21`
  - `map_object_generated`: `18`
  - `secondary_province_touchpoint`: `77`

- Bu sayilarin anlami:
  - `history_provinces`, `landed_titles`, `history_titles`, `map_data_core`, `map_object_data` ana downstream province aileleri
  - `secondary_province_touchpoint` ise core ailelerin disinda acik province/province-scope/location/building referansi iceren event/decision/script/history dosyalarini gosteriyor

- Bu asamanin pratik sonucu:
  - artik province merge sonrasi bakilacak dosya aileleri sadece sezgisel degil, somut envanter halinde mevcut
  - sonraki asamada bu listeye bakarak once `gfx/map/map_object_data`, sonra province ID veya province-title baglantisini etkileyen ailelere sirali gidebiliriz

- Sonraki rafine etme notu:
  - ilk inventory surumunde localization concept-link false positive'leri vardi
  - ornek: `localization/replace/english/z_MB_decisions_l_english.yml` dosyasi yalnizca `[special_building|E]` gibi localization kavram linkleri yuzunden secondary kategoriye girmisti
  - script daha sonra daraltildi:
    - localization koku secondary taramadan cikarildi
    - yalnizca daha yapisal patternler birakildi:
      - `province:`
      - `province =`
      - `province_id`
      - `capital_province`
      - `title_province`
      - `any_county_province`
      - `every_county_province`
      - `outbreak_province`
      - `location = title:b_/c_`
      - `capital = b_/c_`
      - `special_building_slot =`
      - `special_building =`
      - `duchy_capital_building =`
  - bu rafine etmeden sonra localization false positive'leri inventory'den cikarildi
  - `secondary_province_touchpoint` sayisi `84`ten `77`ye dustu

- Daha sonra ikinci bir gap-check yapildi:
  - amac: sabit county/barony title atayan ama ilk daraltmada kacmis dosyalari bulmak
  - bu gap-check sonunda script bir kez daha genisletildi:
    - `title = c_*`
    - `county = c_*`
    - `barony = b_*`
    - `has_title = c_*` veya `has_title = title:c_*`
    - `x = c_*` tipi sabit title mapping satirlari da dahil edildi

- Bu ikinci turda envantere sonradan eklenen onemli gercek dosyalar:
  - `common/bookmarks/bookmarks/00_bookmarks.txt`
  - `common/religion/holy_site_types/00_holy_site_types.txt`
  - `common/religion/holy_site_types/RICE_holy_sites.txt`
  - `common/coat_of_arms/coat_of_arms/91_NB_landed_titles.txt`
  - `common/coat_of_arms/coat_of_arms/92_NB_dynasties.txt`
  - `common/coat_of_arms/dynamic_definitions/00_MB_dynamic_coas.txt`

- Ikinci tur sonrasi `secondary_province_touchpoint` guncel sayisi:
  - `68`

- Ikinci tur gap-check sonucu bilincli olarak disarida birakilan false positive dosyalar:
  - `common/coat_of_arms/coat_of_arms/93_NB_random_templates.txt`
    - `c_` ile baslayan sablon anahtarlari title degil, COA template adi
  - `common/dynasties/00_dynasties.txt`
    - `c_` ile baslayan bazi anahtarlar county title degil, dynasty key

- Bu gap-check sonucunu belgelemek icin yeni dosya olusturuldu:
  - `Works/analysis/generated/province_touchpoints_gap_check.md`

- Bu dosyanin rolu:
  - amac: inventory'nin son daraltma/genisletme sonrasi neden bu sekilde kabul edildigini belgelemek
  - neden olusturuldu: hangi dosyalar sonradan eklendi, hangileri bilincli olarak disarida birakildi net kalsin

## 2026-04-12 Core Province Entegrasyon Turu Uygulandi

Bu turda daha once planlanan `core only` downstream entegrasyon gercekten uygulandi.

Canli olarak guncellenen dosyalar:

- `history/provinces/00_MB_PROVINCES.txt`
- `common/landed_titles/00_landed_titles.txt`
- `history/titles/00_ASIA_CHINA.txt`
- `history/titles/00_ASIA_JAPAN.txt`
- `history/titles/00_ASIA_NORTH.txt`
- `history/titles/00_ASIA_SOUTH.txt`
- `history/titles/00_OTHER.txt`
- `map_data/adjacencies.csv`
- `map_data/island_region.txt`
- `gfx/map/map_object_data/building_locators.txt`
- `gfx/map/map_object_data/special_building_locators.txt`
- `gfx/map/map_object_data/player_stack_locators.txt`
- `gfx/map/map_object_data/combat_locators.txt`
- `gfx/map/map_object_data/siege_locators.txt`
- `gfx/map/map_object_data/activities.txt`

Bu turda bilerek dokunulmayan aileler:

- `map_data/geographical_regions/*.txt`
- `secondary_province_touchpoint`
- 6 crash locator disindaki `map_object_data`

### Uygulama Kurali

- `modlu_kalan` icerik mod kaynagindan tasindi
- `orijinal_dogu` icerik vanilla kaynagindan tasindi
- imported vanilla east tarafinda `old_vanilla_id -> final_new_id` rewrite uygulandi
- ana ID politikasi degismedi: `preserve_old_ids`

### Uretilen Ana Arac

- `Works/tools/implement_core_province_integration.ps1`
  - amac: core downstream province entegrasyonunu tek script ile tekrar uretilebilir hale getirmek
  - neden olusturuldu: `history/provinces`, `landed_titles`, `history/titles`, `adjacencies` ve 6 locator dosyasini ayni authoritative tracking tablolarindan tekrar kurabilmek

### Bu Turda Uretilen Yeni Raporlar

- `Works/analysis/generated/core_province_integration/core_province_integration_summary.md`
  - amac: bu turun toplu sonuc sayilarini kisa ozet halinde saklamak
  - neden olusturuldu: tek bakista coverage/missing/diff durumunu gormek

- `Works/analysis/generated/core_province_integration/history_provinces_merge_report.csv`
  - amac: her final province icin history blok kaynagi bulundu mu bulunmadi mi gostermek
  - neden olusturuldu: imported east ve kept west history coverage'ini satir bazinda denetlemek

- `Works/analysis/generated/core_province_integration/history_provinces_mod_duplicates.csv`
  - amac: mod history/provinces tarafinda ayni province id birden fazla dosyada var mi gostermek
  - neden olusturuldu: source dictionary cikarirken duplicate riskini belgelemek

- `Works/analysis/generated/core_province_integration/history_provinces_vanilla_duplicates.csv`
  - amac: vanilla history/provinces tarafinda ayni province id birden fazla dosyada var mi gostermek
  - neden olusturuldu: vanilla source coverage/duplicate durumunu kayda gecirmek

- `Works/analysis/generated/core_province_integration/landed_titles_vanilla_province_rewrite_report.csv`
  - amac: imported vanilla landed title root'larindaki `province = id` satirlarinin nasil cozuldugunu gostermek
  - neden olusturuldu: dogrudan rewrite, mod-barony fallback ve tamamen kaldirilan unmapped barony durumlarini belgelemek

- `Works/analysis/generated/core_province_integration/history_titles_merge_report.csv`
  - amac: hangi east title history root'larinin hangi mod dosyasina import edildigini gostermek
  - neden olusturuldu: macro root bazli merge'in izlenebilir olmasi

- `Works/analysis/generated/core_province_integration/stale_old_vanilla_id_report.csv`
  - amac: adjacencies merge sirasinda maplenemeyen vanilla/mod source satirlarini gostermek
  - neden olusturuldu: seam veya source coverage sorunlarini sonradan manuel incelemek

- `Works/analysis/generated/core_province_integration/invalid_final_id_report.csv`
  - amac: final definition disi province id kalip kalmadigini raporlamak
  - neden olusturuldu: rewritten `adjacencies.csv` icinde gecersiz id kalmamasini denetlemek

- `Works/analysis/generated/core_province_integration/island_region_pass_report.csv`
  - amac: `map_data/island_region.txt` icin bu turda ne yapildigini kayda gecirmek
  - neden olusturuldu: bu dosyada numeric province rewrite gerekmedigi ve mevcut mod bazinin korundugu net kalsin

- `Works/analysis/generated/core_province_integration/locator_missing_report.csv`
  - amac: 6 locator dosyasinda mod/vanilla source veya generated fallback tarafinda eksik kalan province id'leri gostermek
  - neden olusturuldu: incomplete locator riskinin hangi subsette toplandigini belgelemek

- `Works/analysis/generated/core_province_integration/locator_validation_report.csv`
  - amac: final locator dosyalarinda invalid final id veya duplicate positive id var mi gostermek
  - neden olusturuldu: statik locator saglik kontrolu yapmak

- `Works/analysis/generated/core_province_integration/locator_oracle_diff_report.csv`
  - amac: merged locator sonucu ile crash-sonrasi generated oracle arasindaki farklari dosya/id bazinda gostermek
  - neden olusturuldu: source-merge sonucu ile oyunun uretecegi locator seti arasindaki aciyi olcmek

### Core Tur Sonuc Sayilari

- `history/provinces` merged candidates: `11063`
- `history/provinces` missing history block: `2198`
  - yorum: bu eksiklerin tamami fatal kabul edilmemeli; deniz/wasteland/boş history beklenen alanlar olabilir

- `common/landed_titles` imported root sayisi: `10`
- `history/titles` imported root sayisi: `7`

- `map_data/adjacencies.csv` merged row sayisi: `375`
- `map_data/adjacencies.csv` dropped stale row sayisi: `279`

- `landed_titles` province rewrite sonucu:
  - `rewritten`: `1853`
  - `fallback_mod_barony`: `345`
  - `missing_mapping_barony_removed`: `90`
  - yorum: `h_china` ve `e_tibet` root'larinda final ID karsiligi bulunmayan bazi vanilla barony'ler tamamen kaldirildi; boylece stale yanlis province id tasinmadi

- locator sonucu:
  - `locator missing rows`: `8466`
  - `locator validation flags`: `0`
  - `locator oracle diffs`: `12841`
  - status dagilimi:
    - `missing_mod_locator`: `5748`
    - `missing_vanilla_locator`: `496`
    - `fallback_generated_for_missing_vanilla`: `2222`

### Bu Turda Alinan Ek Teknik Kararlar

- `common/landed_titles` importunda vanilla province id finale maplenemiyorsa once ayni `b_*` title icin moddaki province id fallback'i denendi
- bu da yoksa ilgili vanilla `b_*` barony block'u tamamen kaldirildi
- amac yanlis province id ile oyuna hatali title baglantisi sokmamak

- mod source dosyalarini tekrar tekrar ustune merge ederken drift olmamasi icin bazi kaynaklar script icinde `git HEAD` iceriginden okunacak sekilde tasarlandi
- bu sayede ikinci/ucuncu kosularda mevcut working copy merge sonucu tekrar kaynak sanilmayacak

- `git show` stdout encoding'i unicode mojibake uretebildigi icin HEAD okuma katmani byte-seviyesinde okunacak sekilde duzeltildi
- bu duzeltme sonrasi imported title history bloklarinda `Shōtoku` gibi isimlerdeki bozulma temizlendi

### Bu Turun Pratik Sonucu

- artik `map_data` merge'inin downstream ilk cekirdek ailesi gercekten uygulanmis durumda
- bundan sonraki crash/uyumsuzluk arastirmasi icin ana focus:
  - locator completeness
  - `geographical_regions`
  - sonra `secondary_province_touchpoint`

## 2026-04-12 Core Entegrasyon Sonrasi Dogrulama Bulgulari

Core entegrasyon turundan sonra degisen dosyalar tek tek kontrol edildi.

### Kesin Hata

- 6 locator dosyasinda script kaynakli `id` bozulmasi bulundu:
  - `gfx/map/map_object_data/building_locators.txt`
  - `gfx/map/map_object_data/special_building_locators.txt`
  - `gfx/map/map_object_data/player_stack_locators.txt`
  - `gfx/map/map_object_data/combat_locators.txt`
  - `gfx/map/map_object_data/siege_locators.txt`
  - `gfx/map/map_object_data/activities.txt`

- Ornek:
  - `gfx/map/map_object_data/activities.txt` satir civari `2289`
  - beklenen: `id=383`
  - mevcut bozuk sonuc: `$1383`

- Kok neden:
  - `Works/tools/implement_core_province_integration.ps1` icindeki `Rewrite-LocatorBlockId`
  - regex replacement `('$1' + $NewId)` kullandigi icin `id=` prefixini korumak yerine `$1NNN` turu bozuk satirlar uretti

- Bozuk satir sayilari:
  - `building_locators.txt`: `2826`
  - `special_building_locators.txt`: `2826`
  - `player_stack_locators.txt`: `3099`
  - `combat_locators.txt`: `3099`
  - `siege_locators.txt`: `2826`
  - `activities.txt`: `2826`

- Sonuc:
  - locator dosyalari su haliyle guvenilir kabul edilmemeli
  - bir sonraki uygulama adiminda once locator rewrite bug'i duzeltilmeli

### Yapisal Olarak Temiz Gorunenler

- `common/landed_titles/00_landed_titles.txt`
  - imported east root'lar tek kopya:
    - `e_viet`
    - `e_tibet`
    - `h_china`
    - `e_suvarnabhumi`
    - `e_brunei`
    - `e_kambuja`
    - `e_japan`
    - `k_chrysanthemum_throne`
    - `e_goryeo`
    - `k_yongson_throne`
  - `province = ...` satirlarinda final set disi ID bulunmadi
  - ama fidelity acisindan:
    - `1853` satir direkt rewrite
    - `345` satir mod-barony fallback
    - `90` vanilla barony tamamen kaldirildi
  - yorum:
    - invalid province id birakmadi
    - ama imported east birebir vanilla kalmadi; bazi barony baglari fallback veya drop ile cozuldu

- `history/titles`
  - imported east root'lar hedef dosyalarda tek kopya bulundu
  - duplicate east root bug'i gorulmedi
  - imported block'larda bazi mojibake comment/name kalintilari var ama bunlar buyuk olcude vanilla/source iceriginden geliyor; merge'in yarattigi yeni syntax hatasi olarak degerlendirilmedi

- `map_data/adjacencies.csv`
  - final definition disi province id bulunmadi
  - ama `279` stale/source satiri drop edildigi icin baglanti kapsaminda eksik kalmis olabilecek seam satirlari sonra gozden gecirilmeli

- `map_data/island_region.txt`
  - bu turda fiilen mantiksal degisiklik yapilmadi
  - eldeki fark esasen line ending seviyesinde

### Izlenmesi Gereken Riskler

- `history/provinces/00_MB_PROVINCES.txt`
  - merge raporuna gore `11063` candidate icin block bulundu
  - `2198` candidate icin source history block bulunmadi
  - bu durum tek basina fatal degil; bir kismi deniz/wasteland/default olabilir
  - ama imported east history coverage'in eksiksiz oldugu soylenemez

- `locator_oracle_diff_report.csv`
- locator tarafinda oracle'a gore fark halen cok yuksek (`12841`)
- bu da locator merge'in sadece syntax bug'i degil, coverage/fidelity acisindan da tekrar ele alinmasi gerektigini gosteriyor

## 2026-04-12 Locator Rewrite Bug Duzeltildi

Core entegrasyon sonrasi bulunan `$1383` tipi locator `id` bozulmasi duzeltildi.

### Kok Neden

- `Works/tools/implement_core_province_integration.ps1`
  - `Rewrite-LocatorBlockId`
  - `Rewrite-ProvinceHistoryBlockId`

- Bu helper'larda regex replacement string olarak `('$1' + $NewId)` benzeri ifade kullaniliyordu.
- `id=383` gibi bir satir bu nedenle `id=383` yerine `$1383` tipine bozulabiliyordu.

### Duzeltme

- Her iki helper da string replacement yerine explicit line rewrite mantigina cekildi
- yani prefix ve suffix regex match ile ayrilip yeni id dogrudan tekrar birlestirildi

### Duzeltme Sonrasi Sonuc

- 6 locator dosyasindaki `$NNN` bozuk satir sayisi artik `0`
  - `building_locators.txt`: `0`
  - `special_building_locators.txt`: `0`
  - `player_stack_locators.txt`: `0`
  - `combat_locators.txt`: `0`
  - `siege_locators.txt`: `0`
  - `activities.txt`: `0`

- `gfx/map/map_object_data/activities.txt` icindeki onceki ornek:
  - eski bozuk: `$1383`
  - yeni dogru: `id=383`

- `locator_validation_report.csv`
  - invalid final ID: `0`
  - duplicate positive ID: `0`

### Duzeltme Sonrasi Hala Acik Kalan Locator Riski

- syntax bug kapandi
- ama coverage/fidelity sorunu kapanmadi
- guncel sayilar:
  - `locator missing rows`: `8466`
  - `locator oracle diffs`: `17582`

- `locator_missing_report.csv` dagilimi:
  - `missing_mod_locator`: `5748`
  - `missing_vanilla_locator`: `496`
  - `fallback_generated_for_missing_vanilla`: `2222`

Yorum:

- Artık locator dosyalari parse edilebilir gorunuyor
- Ama source-merge coverage hala zayif; bu crash/log davranisini tekrar test etmek gerekiyor

## 2026-04-12 History Provinces Gap Siniflandirma

`history/provinces/00_MB_PROVINCES.txt` coverage acigi daha iyi anlasilsin diye ayri siniflandirma yapildi.

Yeni arac:

- `Works/tools/classify_history_province_gaps.ps1`
  - amac: `missing_history_block` satirlarini isim ve subset bazinda siniflandirmak
  - neden olusturuldu: `2198` eksigin ne kadarinin normal sayilabilecek deniz/wasteland/default alanlar oldugunu ayirmak

Yeni raporlar:

- `Works/analysis/generated/core_province_integration/history_provinces_missing_classification.csv`
  - amac: her eksik satir icin category ve review class yazmak
  - neden olusturuldu: manuel bakilacak province'leri daraltmak

- `Works/analysis/generated/core_province_integration/history_provinces_missing_classification.md`
  - amac: toplu siniflandirma sayilarini kisa ozetlemek
  - neden olusturuldu: tek bakista risk seviyesini gormek

### Siniflandirma Sonucu

- toplam `missing_history_block`: `2198`

- review class:
  - `likely_benign_or_low_priority`: `1200`
  - `needs_manual_review`: `998`

- category:
  - `named_land_or_special`: `998`
  - `maritime_or_water`: `746`
  - `terrain_or_impassable`: `299`
  - `blank_name`: `155`

- source subset:
  - `modlu_kalan`: `1636`
  - `orijinal_dogu`: `562`

### Bu Sonucun Yorumlanmasi

- `2198` sayisinin tamami artik ayni agirlikta gorulmemeli
- bunlarin `1200` tanesi su anlik daha dusuk oncelikli gorunuyor
  - deniz
  - river
  - lake
  - terrain/wasteland benzeri isimler
  - bos isimli satirlar

- asil aktif inceleme havuzu su anda `998` satir
  - yani adli, ozel, kara province veya normal county/barony gibi duran eksik history bloklari

### Sonraki Mantikli Teknik Oncelik

- locator coverage ve smoke test
- ardindan `history_provinces_missing_classification.csv` icindeki `998` manual-review satirini kaynak bazli temizlemek

## Test Files Paketi

- kullanicinin istegiyle `test_files/` klasoru olusturulan test paketi hedefi olarak kullaniliyor
- amac: oyunda/ayri ortamda denenecek, az once yeniden yazdigimiz veya duzenledigimiz canli dosyalari tek yerde toplamak
- kural: sadece testte kullanilacak canli veri dosyalari kopyalandi; `Works/` altindaki analiz raporlari bu paketin icine alinmadi

### Kopyalanan Dosyalar

- `test_files/common/landed_titles/00_landed_titles.txt`
- `test_files/gfx/map/map_object_data/activities.txt`
- `test_files/gfx/map/map_object_data/building_locators.txt`
- `test_files/gfx/map/map_object_data/combat_locators.txt`
- `test_files/gfx/map/map_object_data/player_stack_locators.txt`
- `test_files/gfx/map/map_object_data/siege_locators.txt`
- `test_files/gfx/map/map_object_data/special_building_locators.txt`
- `test_files/history/provinces/00_MB_PROVINCES.txt`
- `test_files/history/titles/00_ASIA_CHINA.txt`
- `test_files/history/titles/00_ASIA_JAPAN.txt`
- `test_files/history/titles/00_ASIA_NORTH.txt`
- `test_files/history/titles/00_ASIA_SOUTH.txt`
- `test_files/history/titles/00_OTHER.txt`
- `test_files/map_data/adjacencies.csv`
- `test_files/map_data/default.map`
- `test_files/map_data/definition.csv`
- `test_files/map_data/island_region.txt`
- `test_files/map_data/provinces.png`

### Manifest

- `test_files/copied_files_manifest.txt`
  - amac: test paketine hangi dosyalarin konuldugunu tek listede tutmak
  - neden olusturuldu: klasor icindeki kopyalarin kapsamını hizli dogrulamak

## default.map Vanilla East Merge

- yeni crash analizi sonrasi `default.map`in dogu tarafi icin vanilla siniflandirmalarin hic merge edilmedigi netlesti
- bu nedenle yeni script yazildi:
  - `Works/tools/merge_default_map_vanilla_east.ps1`
  - amac: vanilla `default.map` icindeki imported east province'lerin `sea_zones`, `river_provinces`, `lakes`, `impassable_mountains`, `impassable_seas` uyeliklerini final `old_vanilla_id -> final_new_id` mapping ile canli `map_data/default.map`e tasimak
  - neden olusturuldu: `Province with no county data` loglarini azaltmak ve dogu su/mountain/special province siniflarini vanilla ile uyumlu hale getirmek

### default.map Merge Kurali

- baz dosya mevcut mod `map_data/default.map`
- imported east province seti:
  - `Works/analysis/generated/final_orijinal_tracking_preserve_old_ids.csv`
- kaynak kategori dogrusu:
  - vanilla `game/map_data/default.map`
- uygulama mantigi:
  - imported east final ID'lerini mevcut mod `default.map` icindeki hedef kategorilerden temizle
  - vanilla'daki karsilik old ID uyeliklerini final yeni ID'ye cevir
  - sonucu `# VANILLA EAST DEFAULT MAP BEGIN/END` blok olarak canli `default.map`e ekle
- test paketi senkronu:
  - `test_files/map_data/default.map` guncellendi

### Uretilen Dosyalar

- `Works/analysis/generated/default_map_vanilla_east/default_map_vanilla_east_merge_summary.md`
  - amac: merge ozeti ve ornek province kontrolleri
  - neden olusturuldu: hangi kategoride kac imported east ID oldugunu ve kritik isimlerin post-merge durumunu tek dosyada gormek

- `Works/analysis/generated/default_map_vanilla_east/default_map_vanilla_east_merge_category_report.csv`
  - amac: kategori bazli eklenen/temizlenen ID sayilari
  - neden olusturuldu: merge etkisini sayisal olarak dogrulamak

- `Works/analysis/generated/default_map_vanilla_east/default_map_vanilla_east_name_sample_report.csv`
  - amac: crash logdaki ornek province isimlerinin merge sonrasi hangi kategorilere dustugunu gostermek
  - neden olusturuldu: `no county data` loglarina en hizli geri beslemeyi saglamak

### Sayisal Sonuc

- imported east tracked row: `3391`
- hedef kategoriler:
  - `sea_zones`
  - `river_provinces`
  - `lakes`
  - `impassable_mountains`
  - `impassable_seas`

- merge edilen imported east final ID sayilari:
  - `sea_zones`: `207`
  - `river_provinces`: `54`
  - `lakes`: `15`
  - `impassable_mountains`: `273`
  - `impassable_seas`: `7`

### Ornek Sonuc

- artik su province'ler `impassable_mountains` icinde:
  - `east_hokkaido_mountains`
  - `shinano_mountains` varyantlari
  - `korea_mountains` varyantlari
  - `Viet_Mountains_6`
  - `Viet_Mountains_7`
  - `Viet_Mountains_8`

- su province'ler sample kontrolde hala kategori almamis gorundu:
  - `Binglingsi`
  - `Hezhou`
  - `XYZ` varyantlarindan biri
- yorum:
  - bunlar `default.map` yerine daha cok `landed_titles/county` veya ozel province mantigi problemi olabilir

### Canli Dosya Durumu

- `map_data/default.map` simdi:
  - placeholder teknik blogunu
  - ve ayrica `# VANILLA EAST DEFAULT MAP BEGIN/END` managed blokunu
  - birlikte iceriyor

## Crash: 2026-04-12 20:02:35

- crash klasoru:
  - `C:\Users\bsgho\Documents\Paradox Interactive\Crusader Kings III\crashes\ck3_20260412_200235`
- exception ayni tipte kaldi:
  - `EXCEPTION_ACCESS_VIOLATION`
- ama pre-crash log artik onceki teste gore daha dar bir probleme isaret ediyor

### Yeni Log Yorumu

- `Province with no county data` sayisi:
  - onceki crash: `715`
  - yeni crash: `643`
- yorum:
  - `default.map` dogu merge'u bazi su/mountain/impassable vakalarini azaltmis gorunuyor
  - ama ana blocker artik daha net sekilde `landed_titles` icindeki county/barony province baglari

### Ana Bulgular

- kalan `no county data` vakalari agirlikla gercek kara province'leri:
  - East Manchuria / Balhae / Liao / Amur
  - Gobi
  - Sakhalin
  - Endonezya/Papua/Andaman benzeri imported east bolgeleri
  - `Hezhou`
  - `Binglingsi`

- kritik teknik bulgu:
  - `common/landed_titles/00_landed_titles.txt` icinde bazi imported east barony'ler gercek final province yerine placeholder veya stale province ID'ye bagli

### Kanit Ornekleri

- `b_EMan_Ningzhou`
  - landed_titles province: `11855`
  - dogru final province:
    - `definition.csv`de `EMan_Ningzhou = 11899`

- `b_FIC_EMan_Zhonganyuan`
  - landed_titles province: `14394`
  - `14394` artik placeholder araliginda
  - dogru final province:
    - `definition.csv`de `FIC_EMan_Zhonganyuan = 11897`

- `b_FIC_EMan_Qingshancun`
  - landed_titles province: `14395`
  - dogru final province:
    - `definition.csv`de `FIC_EMan_Qingshancun = 11900`

- `b_FIC_EMan_Huangyuan`
  - landed_titles province: `14396`
  - dogru final province:
    - `definition.csv`de `FIC_EMan_Huangyuan = 11901`

- `b_FIC_EMan_Sanhean`
  - landed_titles province: `14402`
  - `14402` placeholder
  - dogru final province:
    - `definition.csv`de `FIC_EMan_Sanhean = 11908`

### Sonuc

- su anki ana crash adayi `default.map` degil
- asıl sorun imported east `landed_titles` province rewritelarinin bazi bloklarda placeholder/stale ID ile kalmis olmasi
- sonraki mantikli teknik hedef:
  - `common/landed_titles/00_landed_titles.txt` icindeki imported east rootlerde tum `province = ...` satirlarini gercek final province ID'lere yeniden dogrulamak ve placeholder baglarini temizlemek

## landed_titles Province Link Repair

- yeni script:
  - `Works/tools/repair_landed_titles_province_links.ps1`
  - amac: `common/landed_titles/00_landed_titles.txt` icindeki barony `province = ...` baglarini final `definition.csv` ile yeniden dogrulamak
  - neden olusturuldu: `no county data` crash logunda gorulen stale/placeholder province baglarini temizlemek

### Repair Mantigi

- her `b_*` barony blogu icin barony anahtari `b_` olmadan alinir
- bu isim normalize edilip `map_data/definition.csv` icindeki province isimleriyle eslestirilir
- sadece su durumlarda rewrite yapilir:
  - mevcut province placeholder ise
  - veya imported east final ID kapsamina giren, acik isim uyusmazligi varsa
- unrelated bati duzeltmeleri kalici olmamasi icin kapsam daraltildi

### Teknik Not

- ilk repair calismasi placeholder/stale baglariyla birlikte bazi east-disi normalized mismatch satirlarini da duzeltti
- bunlardan imported east disindaki `4` satir geri alindi
- script daha sonra imported east + placeholder odakli hale getirildi

### Somut Duzenlenen Ornekler

- `b_EMan_Ningzhou`
  - eski: `11855`
  - yeni: `11899`

- `b_FIC_EMan_Qingshancun`
  - eski: `14395` placeholder
  - yeni: `11900`

- `b_FIC_EMan_Huangyuan`
  - eski: `14396` placeholder
  - yeni: `11901`

- `b_FIC_EMan_Sanhean`
  - eski: `14402` placeholder
  - yeni: `11908`

- `b_FIC_EMan_Zhonganyuan`
  - eski: `14394` placeholder
  - yeni: `11897`

- `b_gobi_ikh_nart`
  - eski: `14539` placeholder
  - yeni: `12552`

### Uretilen Dosyalar

- `Works/analysis/generated/landed_titles_link_repair/landed_titles_province_link_repair_report.csv`
  - amac: taranan her province assignment icin rewrite/keep/unresolved durumu
  - neden olusturuldu: hangi baronylerin duzeltildigini ve hangilerinin hala unresolved kaldigini belgelemek

- `Works/analysis/generated/landed_titles_link_repair/landed_titles_province_link_repair_summary.md`
  - amac: repair ozet sayilari
  - neden olusturuldu: tek bakista kalan unresolved havuzunu gormek

### Mevcut Durum

- repair sonrasi kritik ornekler canli dosyada duzeldi:
  - `province = 11899`
  - `province = 11900`
  - `province = 11901`
  - `province = 11908`
  - `province = 11897`
  - `province = 12552`

- hala unresolved ornekler var:
  - `b_tym_sakhalin = province 13913` placeholder
  - `b_hezhou_hailong_china = province 12454` ve isim eslesmesi otomatik cikmiyor
- yorum:
  - bu kalanlar otomatik exact/normalized isim eslesmesiyle cozulmeyen, daha manuel veya root-bazli ikinci tur adaylar

### Yeni Bug Bulgusu

- `common/landed_titles/00_landed_titles.txt` icinde yeni bir regex-replacement bozulmasi bulundu
- ornek:
  - `b_primda` altinda `province = 4144` yerine sadece `$14144` yaziyor
- bulunan satirlar:
  - `$11609`
  - `$14144`
  - `$11902`
  - `$11890`
- yorum:
  - bu kasitli degil
  - onceki geri-alma adiminda replacement string icinde `$1 + sayi` formu kullanilmasindan kaynakli ayni tur bir PowerShell regex bug'i
  - locator bug'indaki `$1383` problemine benzer bir sinif

### Bug Fix

- bozuk `4` satir dogrudan duzeltildi
  - `$11609` -> `province = 1609`
  - `$14144` -> `province = 4144`
  - `$11902` -> `province = 1902`
  - `$11890` -> `province = 1890`
- canli dosya ve `test_files/common/landed_titles/00_landed_titles.txt` senkronlandi
- yeniden taramada `^\$[0-9]+` patterni iki dosyada da `0` sonuc verdi

### Yeni Esleme Kurali

- kullanici yeni landed_titles/province link onarimlarinda yalnizca isim benzerligine guvenilmemesini istedi
- bundan sonraki dogru province bulma mantigi icin ana zincir su olacak:
  - `old source province id`
  - `old source province rgb`
  - `source` (`modlu` / `orijinal`)
  - bu bilgilerden `final_new_id`
- yorum:
  - isim/normalized isim eslesmesi yalnizca yardimci sinyal olacak
  - placeholder ya da sea province'e yanlis baglanan baronylerde once provenance zinciri kontrol edilecek
  - ozellikle imported east barony repair turlarinda `final_orijinal_tracking_preserve_old_ids.csv`, `final_modlu_tracking_preserve_old_ids.csv` ve gerekiyorsa eski `definition_*.csv` kaynaklari temel alinacak

### Landed Titles Root Sebebi

- `Barony ... has no province defined` havuzunun onemli bir bolumunde sorun tek tek barony satiri degil, `common/landed_titles/00_landed_titles.txt` icinde eski mod dogu top-level root'larinin dosyada kalmis olmasi
- vanilla east root'lari eklenmis olsa da asagidaki mod dogu root'lari ayri bloklar olarak halen duruyordu:
  - `e_qixi`
  - `e_tunguse`
  - `e_jurchen_china`
  - `e_java`
  - `e_malayadvipa`
  - `e_srivijaya`
  - `e_kalimantan`
  - `e_angkor`
  - `e_ramanya`
  - `e_panyupayana`
  - `e_maluku`
- yorum:
  - bu root'lar placeholder/sea/stale province id'lerine bagli mod dogu baronylerini tasiyordu
  - `b_fic_eman_*`, `b_tym_sakhalin`, `b_johor`, `b_laputta`, `b_wakema`, `b_pyapon`, `b_maynila` gibi crash ornekleri bunlardan cikti

### E Nusantara Bulgusu

- ilk `implement_core_province_integration.ps1` landed_titles merge turunda `e_nusantara` hic import edilmemisti
- yorum:
  - bu eksik kapsam Filipinler / Nusantara tarafindaki `has no province defined` havuzunu buyuttu

### Yeni Refresh Turu

- yeni script eklendi:
  - `Works/tools/refresh_landed_titles_imported_east_from_vanilla.ps1`
  - amac: imported vanilla east root'larini tekrar kurmak, `e_nusantara`yi eklemek ve eski mod dogu root'larini dosyadan temizlemek
  - neden olusturuldu: current landed_titles icinde vanilla east ve mod east'in birlikte kalmasindan dogan stale province linklerini toplu temizlemek

- script iki kez gelistirilerek kosuldu:
  - ilk kosuda vanilla east root refresh yapildi ama eski mod dogu root'lar kaldi
  - ikinci kosuda legacy mod east root remove list'i eklenerek gercek temizleme tamamlandi

### Landed Titles Vanilla Refresh Sonucu

- rapor klasoru:
  - `Works/analysis/generated/landed_titles_vanilla_refresh/`
- ana dosyalar:
  - `landed_titles_vanilla_refresh_report.csv`
    - amac: vanilla source old province id -> final new id rewrite satirlarini belgelemek
    - neden olusturuldu: hangi imported east barony province satirlarinin rewrite/keep/remove oldugunu gormek
  - `landed_titles_vanilla_refresh_validation.csv`
    - amac: refresh sonrasi imported east root'lardaki barony province linklerinin `land / water / placeholder / missing_definition` sinifini cikarmak
    - neden olusturuldu: placeholder ya da sea province'e kalan barony baglari var mi kesin kontrol etmek
  - `landed_titles_vanilla_refresh_summary.md`
    - amac: tek bakista sayisal ozet
    - neden olusturuldu: refresh kalitesini hizli okumak

- ikinci refresh sonrasi ozet:
  - refreshed roots: `22`
  - rewritten province rows: `625`
  - kept same-id rows: `1495`
  - removed unmapped baronies: `435`
  - validation `land`: `2120`
  - validation `water`: `0`
  - validation `placeholder`: `0`
  - validation `missing_definition`: `0`

- pratik sonuc:
  - onceki ornek bozuk baronyler (`b_fic_eman_*`, `b_tym_sakhalin`, `b_idoi`, `b_tarayka`, `b_eusutur`, `b_ketuni`, `b_johor`, `b_laputta`, `b_wakema`, `b_pyapon`, `b_maynila` vb.) canli `00_landed_titles.txt` icinden kayboldu
  - bu satirlar ya dogru vanilla east blocklariyla degisti ya da stale mod east root temizligiyle dosyadan kalkti

### Tooling Duzeltmesi

- `Works/tools/implement_core_province_integration.ps1` landed_titles root kapsami da guncellendi
- yeni eklenen / duzeltilenler:
  - `e_nusantara` landed replacement spec'e eklendi
  - remove list'e yukaridaki legacy mod east root'lari eklendi
- yorum:
  - boylece script ileride tekrar kosulursa ayni root omission / stale east root problemi daha az olasi

## 2026-04-12 21:43 crash objective log reading
- Crash folder: C:\Users\bsgho\Documents\Paradox Interactive\Crusader Kings III\crashes\ck3_20260412_214320
- More objective reading after user correction:
  - Province with no county data: 987 total, 983 unique
  - Barony ... has no province defined: 160 total, 27 unique
  - Land associated barony/county ... null holder: 1
  - Assertion failed: 1
  - geographical_region: 3520
- Comparison with previous crash ck3_20260412_211533:
  - Province with no county data: 380 -> 987
  - Barony ... has no province defined: 1026 -> 160
- Interpretation:
  - recent fixes reduced has no province defined heavily
  - but county coverage problems became the dominant log class
  - _yerevan is still the final fatal assert line, but should be treated as a downstream/final blocker candidate, not automatically as the primary root cause
- Some has no province defined examples (_crivitz, _kyburg, _eutin, _wismar, etc.) already have visible province = ... rows in common/landed_titles/00_landed_titles.txt, so at least part of that class may indicate deeper landed_titles parse/structure/consistency issues rather than simple missing province assignments
## 2026-04-12 - provinces.png / definition.csv dual-source duplicate RGB onarimi

- Kullanici `map_data/provinces.png` icinde `135,36,34` RGB'sinin duplicate oldugunu fark etti; bu satir final `definition.csv`de `9668;135;36;34;Crivitz;x;` olarak duruyordu ama ayni RGB daha once `orijinal_dogu` tarafinda `IMPASSABLE CENTRAL GOBI 3` olarak da secilmisti.
- Bu uyaridan sonra `source_origin=both` olan tum final RGB satirlari icin fiziksel piksel denetimi yapildi.
- Yeni audit araci:
  - `Works/tools/audit_dual_source_rgb_in_final_map.ps1`
- Audit raporlari:
  - `Works/analysis/generated/provinces_duplicate_rgb_audit/dual_source_rgb_presence.csv`
  - `Works/analysis/generated/provinces_duplicate_rgb_audit/dual_source_rgb_presence.md`
- Audit sonucu:
  - `21` adet `source_origin=both` satiri denetlendi.
  - Canli `provinces.png` icinde `18` RGB gercekten hem `provinces_modlu_kalan.png` hem `provinces_orijinal_dogu.png` kaynakli piksel tasiyordu.
  - Bunlarin `13` tanesi farkli province adi/kimligi tasiyordu. Bu grup gercek hata kabul edildi.
- Problemli final RGB'ler `preferred_source_subset=modlu_kalan` olmasina ragmen orijinal dogudan gelen pikselleri de yasatiyordu. Bu, tek bir final RGB altinda iki ayri province kimligini birlestiriyordu.
- Onarim yaklasimi:
  - `modlu_kalan` tarafi mevcut final ID/RGB ile korundu.
  - `orijinal_dogu` tarafindaki ayri province parcasi icin mevcut placeholder ID/RGB'lerden `13` tanesi repurpose edildi.
  - Canli `provinces.png` icinde sadece `orijinal_dogu` kaynagindan gelen ilgili pikseller yeni RGB'lere tasindi.
  - Ayni placeholder satirlari `definition.csv` icinde gercek province satirlarina cevrildi.
  - Placeholder teknik pikselleri siyaha cekildi.
- Onarim scripti:
  - `Works/tools/repair_dual_source_duplicate_provinces.ps1`
- Onarim raporlari:
  - `Works/analysis/generated/provinces_duplicate_rgb_repair/dual_source_duplicate_repair_assignments.csv`
  - `Works/analysis/generated/provinces_duplicate_rgb_repair/dual_source_duplicate_repair_summary.md`
  - yedekler:
    - `Works/analysis/generated/provinces_duplicate_rgb_repair/provinces_before_dual_source_split.png`
    - `Works/analysis/generated/provinces_duplicate_rgb_repair/definition_before_dual_source_split.csv`
- Bu assignment CSV'si kullanici tarafindan ozellikle istenen `degisen rgb/id kaydi`nin authoritative kaydidir. Icindeki alanlar:
  - `kept_final_id`
  - `kept_rgb`
  - `modlu_old_id / modlu_old_rgb / modlu_old_name`
  - `orijinal_old_id / orijinal_old_rgb / orijinal_old_name`
  - `new_final_id`
  - `new_rgb`
  - `new_name`
  - `changed_pixels`
- Repurpose edilen yeni final ID'ler:
  - `12773` `Karub`
  - `12774` `PLACEHOLDER_REGION_KOREA`
  - `12775` `IMPASSABLE CENTRAL GOBI 1`
  - `12776` `IMPASSABLE CENTRAL GOBI 3`
  - `12777` `split_orijinal_9671`
  - `12778` `PLACEHOLDER_REGION_SOUTHEAST_COAST`
  - `12779` `Marakele`
  - `12780` `Siantan Island`
  - `12781` `Goryeo_Donggye_Myeongju`
  - `12782` `Goryeo_Donggye_Deungju`
  - `12783` `Goryeo_Donggye_Uiju`
  - `12784` `Goryeo_Donggye_Hwaju`
  - `12785` `Goryeo_Bukgye_Maengju`
- En buyuk piksel tasimalari:
  - `9665 -> 12775` `IMPASSABLE CENTRAL GOBI 1`: `75122` piksel
  - `9668 -> 12776` `IMPASSABLE CENTRAL GOBI 3`: `34909` piksel
- Onarim sonrasi audit sonucu:
  - canli `provinces.png` icinde iki kaynaktan birden yasayan RGB sayisi `5`e indi
  - farkli isimli `both-source` RGB sayisi `0` oldu
  - geriye kalan `5` RGB her iki kaynakta da ayni isim/kimlik tasiyan benign satirlardir:
    - `Candranatha`
    - `EAST INDIAN OCEAN TI`
    - `sea_bay_of_bengal` (2 satir)
    - `Naga Hills`
- `definition.csv` duplicate RGB kontrolu:
  - `0`
- Bu turda canli ve test kopyalari birlikte guncellendi:
  - `map_data/provinces.png`
  - `map_data/definition.csv`
  - `test_files/map_data/provinces.png`
  - `test_files/map_data/definition.csv`
- Onemli sonraki not:
  - Bu yeni repurpose edilen `13` final ID ileride `default.map`, `landed_titles` ve gerekirse `history/provinces`/diger province-reference dosyalarina da propagate edilmelidir.
  - Ozellikle Goryeo ve Gobi tarafindaki yeni province kimlikleri artik placeholder degil, gercek province olarak yasiyor.

## 2026-04-12 - dual-source split denemesi geri alindi

- Kullanici, bu `13`'lu split onarimindan sonra canli `map_data/provinces.png` icinde province renklerinin dogru konuma gelmedigini ve gorunurde kayma/yanlis yerlesim oldugunu bildirdi.
- Bu geri bildirim kabul edildi; gorsel hata kesin kullanici raporu olarak ele alindi ve split onarimi canli setten geri alindi.
- Geri alma islemi:
  - `map_data/provinces.png` -> `Works/analysis/generated/provinces_duplicate_rgb_repair/provinces_before_dual_source_split.png` yedegine donuldu
  - `map_data/definition.csv` -> `Works/analysis/generated/provinces_duplicate_rgb_repair/definition_before_dual_source_split.csv` yedegine donuldu
  - `test_files/map_data/provinces.png` ve `test_files/map_data/definition.csv` de ayni surume senkronlandi
- Hatali ara surumler silinmedi; inceleme icin saklandi:
  - `Works/analysis/generated/provinces_duplicate_rgb_repair/provinces_bad_after_split.png`
  - `Works/analysis/generated/provinces_duplicate_rgb_repair/definition_bad_after_split.csv`
- Hash dogrulamasi yapildi:
  - canli `map_data/provinces.png` hash'i `provinces_before_dual_source_split.png` ile birebir ayni
  - canli `map_data/definition.csv` hash'i `definition_before_dual_source_split.csv` ile birebir ayni
- Bu nedenle su anki canli durumda `13`'lu split uygulanmis DEGILDIR.
- Yani su an:
  - dual-source benign/shared fiziksel problem raporu hala gecerlidir
  - fakat onu cozmek icin kullanilan son otomatik split/recolor yaklasimi kabul edilmemis ve geri alinmistir
- Daha guvenli bir sonraki yol:
  - problemi rapor seviyesinde koru
  - otomatik toplu split yerine daha kontrollu / province-bazli / kullanici-onayli uygulama dusun

## 2026-04-12 - rollback sonrasi provinces.png teshi s turu

- Rollback sonrasi kullanicinin yonlendirmesiyle `provinces.png` ustunde yeniden sadece teshis yapildi; canli `map_data` dosyalarina bu turda degisiklik uygulanmadi.
- Kullanilan yeni araclar:
  - `Works/tools/compare_live_provinces_to_source_split.ps1`
  - `Works/tools/analyze_rgb_components_in_provinces.ps1`
  - `Works/tools/build_dual_source_conflict_diagnostics.ps1`
- Once `map_data/provinces.png` canli dosyasi ile ham secim kaynagi `Works/map_data_sources/provinces_birlesim.png` karsilastirildi.
- Sonuc:
  - canli `provinces.png`, ham `provinces_birlesim.png` ile ayni degil
  - degisen piksel sayisi: `3,536,008`
  - degisim bbox'i: tum haritayi kapsiyor (`0,0 -> 9215,4607`)
- Bu ilk bakista buyuk gozukse de sonraki kontrol daha anlamli oldu:
  - canli `map_data/provinces.png` hash'i
  - `Works/analysis/generated/provinces_birlesim_final_preserve_old.png`
  ile birebir ayni cikti.
- Yani mevcut canli `provinces.png`, ham `provinces_birlesim.png` degil; eski final staging ciktiyla ayni.
- Bu nedenle ham secim PNG ile buyuk fark tek basina yeni bir hata kaniti degil; mevcut canli dosya zaten final-preserve-old uretilmis staging setle ayni.
- Rollback sonrasi `dual_source_rgb_presence` audit tekrar calistirildiginda:
  - `source_origin=both` satirlarindan canli haritada iki kaynaktan piksel tasiyan RGB sayisi `5`
  - farkli isimli canli both-source RGB sayisi `0`
- Bu da su anki canli dosyada eski `13` vakalik automated split onarimindan sonra gorulen tipte bir "both-source different-name" durumunun artik ayni sekilde yeniden uretilemedigini gosterdi.
- Bunun uzerine kullanicinin ozellikle isaret ettigi RGB'ler icin komponent analizi yapildi:
  - rapor klasoru: `Works/analysis/generated/provinces_rgb_components`
  - `135,36,34` raporu: `rgb_135_36_34_components.md/csv`
  - `9,27,160` raporu: `rgb_9_27_160_components.md/csv`
  - `177,24,32` raporu: `rgb_177_24_32_components.md/csv`
  - `93,48,36` raporu: `rgb_93_48_36_components.md/csv`
- Cok onemli bulgu:
  - `135,36,34` canli haritada `2` ayri komponentte gorunuyor:
    - buyuk komponent bbox: `6177,1325 -> 6486,1558`, `37391` piksel
    - kucuk komponent bbox: `1584,1171 -> 1616,1201`, `631` piksel
  - `9,27,160` da `2` komponent:
    - buyuk: `5976,1388 -> 6425,1723`, `78171` piksel
    - kucuk: `1348,1256 -> 1371,1277`, `357` piksel
  - `177,24,32` da `2` komponent:
    - buyuk: `7467,1461 -> 7511,1491`, `887` piksel
    - kucuk: `1259,1405 -> 1276,1418`, `185` piksel
  - `93,48,36` da `2` komponent:
    - buyuk: `7423,2424 -> 7462,2530`, `1757` piksel
    - kucuk: `1473,1546 -> 1497,1570`, `397` piksel
- Bu, kullanicinin "ayni RGB canli haritada duplicate/dagilmis durumda" suphelerini destekleyen objective kanittir.
- Ancak su noktada hala dikkat edilmesi gereken sey:
  - bu komponent bulgusu, hangi komponentin hangi province kimligine ait oldugunu tek basina ispatlamaz
  - fakat ayni RGB'nin haritada iki cok uzak bolgede yasadigini gosterdigi icin province-level kontrollu split/recolor ihtiyacini guclu sekilde destekler
- Bu nedenle artik toplu otomatik split yerine daha guvenli sonraki yol:
  - tek RGB
  - tek karar
  - koordinat/bbox kontrollu
  - her adimdan sonra görsel dogrulama

## 2026-04-13 - source PNG + subset definition tabanli overlap/conflict audit

- Kullanici yeni karar yontemini netlestirdi:
  - `provinces_modlu_kalan.png` icindeki yasayan RGB'ler alinacak
  - `provinces_orijinal_dogu.png` icindeki yasayan RGB'ler alinacak
  - ortak RGB'ler bulunacak
  - her ortak RGB icin ilgili subset definition dosyasindan province `id`si cekilecek
  - `same RGB + same ID = sorun yok`
  - `same RGB + different ID = gercek conflict`
- Bu kural artik authoritative conflict tespit yontemi olarak kabul edildi.
- Bu turda canli `map_data` dosyalarina dokunulmadi; sadece audit ve karar-sablonu uretildi.
- Yeni script:
  - `Works/tools/build_source_rgb_overlap_audit.ps1`
- Script once source PNG'leri tarayip her RGB icin:
  - `pixel_count`
  - `bbox`
  - ilgili subset definition'daki `source_id`
  - `source_name`
  topladi.
- Sonra su dosyalari urett i:
  - `Works/analysis/generated/source_rgb_overlap_audit/modlu_kalan_rgb_inventory_from_png.csv`
  - `Works/analysis/generated/source_rgb_overlap_audit/orijinal_dogu_rgb_inventory_from_png.csv`
  - `Works/analysis/generated/source_rgb_overlap_audit/source_rgb_overlap_same_id.csv`
  - `Works/analysis/generated/source_rgb_overlap_audit/source_rgb_overlap_conflicts.csv`
  - `Works/analysis/generated/source_rgb_overlap_audit/source_rgb_overlap_conflict_decisions.csv`
  - `Works/analysis/generated/source_rgb_overlap_audit/source_rgb_overlap_summary.md`
- Ilk calistirmada absurt unique RGB sayilari cikti. Bunun sebebi yeni image-analysis araclarinda `Graphics.DrawImageUnscaled` ile clone yapilmasi olabilir diye tespit edildi.
- Bu yuzden su araclarda piksel yolu guvenli `original.Clone(..., Format32bppArgb)` seklinde duzeltildi:
  - `Works/tools/build_source_rgb_overlap_audit.ps1`
  - `Works/tools/audit_dual_source_rgb_in_final_map.ps1`
  - `Works/tools/build_dual_source_conflict_diagnostics.ps1`
  - `Works/tools/compare_live_provinces_to_source_split.ps1`
  - `Works/tools/analyze_rgb_components_in_provinces.ps1`
- Duzenleme sonrasi source-overlap audit sonucu:
  - `modlu_kalan` unique non-black RGB: `9891`
  - `orijinal_dogu` unique non-black RGB: `3391`
  - ortak RGB: `140`
  - `same RGB + same ID`: `21`
  - `same RGB + different ID`: `119`
  - definition'da bulunamayan source PNG RGB: `0`
- Yani onceki `119` conflict sayisi, kullanicinin istedigi yontemle tekrar dogrulandi.
- Benign grup:
  - `21` satir `same RGB + same ID`
  - bunlarin `15` tanesinde isim farkli ama ID ayni
  - kullanicinin koydugu kurala gore bunlar conflict DEGIL
  - ornek: `135,36,34`
    - modlu: `9668 Crivitz`
    - orijinal: `9668 IMPASSABLE CENTRAL GOBI 3`
    - source PNG + source definition yontemine gore `same ID`, dolayisiyla benign kabul edilir
- Bu benign ama isim-farkli grup metadata acisindan ilginc olabilir, ancak conflict karari degistirmez.
- Gercek conflict grubu authoritative dosya:
  - `Works/analysis/generated/source_rgb_overlap_audit/source_rgb_overlap_conflicts.csv`
- Bir sonraki karar/uygulama icin kullanilacak sablon:
  - `Works/analysis/generated/source_rgb_overlap_audit/source_rgb_overlap_conflict_decisions.csv`
  - kolonlar:
    - `rgb`
    - `modlu_id`
    - `modlu_name`
    - `modlu_pixel_count`
    - `modlu_bbox`
    - `orijinal_id`
    - `orijinal_name`
    - `orijinal_pixel_count`
    - `orijinal_bbox`
    - `keep_rgb_source`
    - `recolor_source`
    - `new_rgb`
    - `decision_notes`
- Bu noktadan sonra conflict cozumunde bbox/pixel_count bilgisi sadece karar yardimcisi olacak; conflict'in varligi veya yoklugu artik source PNG + source definition ID karsilastirmasindan belirlenecek.

## 2026-04-13 - source default.map + source landed_titles semantic audit

- Kullanici `same_name` bilgisinin tek basina yetersiz oldugunu netlestirdi.
- Bundan sonra overlap/conflict semantigi icin yalnizca isim degil, su source kanitlari da kullanilacak:
  - source `default.map` sinifi
    - `sea_zones`
    - `river_provinces`
    - `lakes`
    - `impassable_mountains`
    - `impassable_seas`
    - veya `none`
  - source `common/landed_titles` tanimi
    - tanimli mi
    - tanimliysa hangi `b_*`
    - hangi `c_*`
    - gerekiyorsa ust zincir (`d_*`, `k_*`, `e_*`)
- Kullanici ayrica modun canli dosyalari degistirildigi icin mod source okunurken artik su klasor authoritative kabul edilecek bilgisini verdi:
  - `C:\Program Files (x86)\Steam\steamapps\workshop\content\1158310\2216670956\0backup`
- Buna gore semantic audit'te:
  - mod source = `0backup`
  - orijinal source = vanilla oyun dosyalari
- Yeni script:
  - `Works/tools/build_source_semantic_overlap_audit.ps1`
- Yeni cikt i dosyalari:
  - `Works/analysis/generated/source_semantic_overlap_audit/source_rgb_overlap_semantic_audit.csv`
  - `Works/analysis/generated/source_semantic_overlap_audit/source_rgb_overlap_semantic_decisions.csv`
  - `Works/analysis/generated/source_semantic_overlap_audit/source_rgb_overlap_semantic_summary.md`
  - `Works/analysis/generated/source_semantic_overlap_audit/source_rgb_overlap_semantic_class_counts.csv`
- Bu turda canli `map_data`, `default.map` veya `landed_titles` dosyalarina dokunulmadi.
- Semantic audit toplam ortak RGB seti uzerinde calisti:
  - toplam ortak RGB satiri: `140`
  - `same RGB + same ID`: `21`
  - `same RGB + different ID`: `119`
  - `same RGB + same ID + different name`: `15`
- Semantic suggestion dagilimi:
  - `Review`: `81`
  - `False`: `58`
  - `True`: `1`
- Semantic classification dagilimi:
  - `unclassified_review`: `76`
  - `barony_vs_nonbarony`: `54`
  - `same_noncounty_default_class_review`: `5`
  - `different_barony`: `2`
  - `different_default_map_class`: `2`
  - `same_barony`: `1`
- Yeni semantic kural:
  - source PNG + subset definition audit'i halen temel yapisal overlap tespitidir
  - ama artik `same RGB + same ID` satirlari otomatik olarak "guvenli/benign" sayilmayacak
  - once source `default.map` ve source `landed_titles` semantigiyle ikinci bir kontrol daha yapilacak
- Ozellikle su vakalar semantik olarak art ik problemli goruluyor:
  - `135,36,34`
    - mod source: `9668 Crivitz`
    - mod source landed title: `b_wismar`, `c_schwerin`
    - orijinal source: `9668 IMPASSABLE CENTRAL GOBI 3`
    - orijinal source default.map sinifi: `impassable_mountains`
    - semantic sonuc: `barony_vs_nonbarony`
    - onerilen eylem: `new_rgb_needed`
  - `177,24,32`
    - mod source: `9664 Stablo`
    - mod source landed title: `b_stablo`, `c_liege`
    - orijinal source: `9664 PLACEHOLDER_REGION_KOREA`
    - orijinal source default.map sinifi: `impassable_mountains`
    - semantic sonuc: `barony_vs_nonbarony`
    - onerilen eylem: `new_rgb_needed`
  - `9,27,160`
    - mod source: `9665 Laar`
    - mod source landed title: `b_laar`, `c_bentheim`
    - orijinal source: `9665 IMPASSABLE CENTRAL GOBI 1`
    - orijinal source default.map sinifi: `impassable_mountains`
    - semantic sonuc: `barony_vs_nonbarony`
    - onerilen eylem: `new_rgb_needed`
- Bu nedenle bundan sonraki karar modeli su olacak:
  - 1. source PNG + subset definition ile overlap/id yapisi bulunur
  - 2. source `default.map` + source `landed_titles` ile semantic anlam kontrol edilir
  - 3. ancak ondan sonra `keep_single_identity` mi yoksa `new_rgb_needed` mi karar verilir
- Semantic karar dosyasi bir tur daha ileri goturuldu:
  - `Works/analysis/generated/source_semantic_overlap_audit/source_rgb_overlap_semantic_decisions.csv`
  - artik `auto_keep_rgb_source`, `auto_recolor_source`, `auto_requires_new_rgb`, `auto_final_action`, `auto_decision_confidence`, `auto_decision_notes` kolonlarini da tasiyor
- Bu turda otomatik karar verilebilen satir sayisi:
  - `59`
  - manual review kalan satir:
  - `81`
- Otomatik karar kurallari:
  - `same_barony`:
    - `keep_single_identity`
    - recolor yok
  - `barony_vs_nonbarony`:
    - barony olan tarafin RGB'si korunur
    - nonbarony taraf recolor olur
  - `different_default_map_class`:
    - `navigable_water` tarafi korunur
    - `impassable` taraf recolor olur
  - `different_barony`:
    - iki taraf da barony ise buyuk piksel alani korunur
    - diger taraf recolor olur
- Otomatik karar dagilimi:
  - `56` satir:
    - `keep modlu`
    - `recolor orijinal`
  - `2` satir:
    - `keep orijinal`
    - `recolor modlu`
  - `1` satir:
    - `keep_single_identity`
- Kritik orneklerde otomatik karar:
  - `135,36,34`
    - `keep modlu`
    - `recolor orijinal`
  - `177,24,32`
    - `keep modlu`
    - `recolor orijinal`
  - `9,27,160`
    - `keep modlu`
    - `recolor orijinal`
  - `134,78,44`
    - `keep orijinal`
    - `recolor modlu`
    - neden: `sea_zones` tarafi, `impassable_seas` tarafina gore korunuyor
  - `178,192,2`
    - `keep modlu`
    - `recolor orijinal`
    - neden: `river_provinces` tarafi, `impassable_mountains` tarafina gore korunuyor
- Otomatik semantic kararlar icin yeni RGB atama dosyasi uretildi:
  - `Works/tools/build_source_semantic_rgb_assignments.ps1`
  - `Works/analysis/generated/source_semantic_overlap_audit/source_rgb_overlap_auto_rgb_assignments.csv`
  - `Works/analysis/generated/source_semantic_overlap_audit/source_rgb_overlap_auto_rgb_assignments_summary.md`
- Bu dosya:
  - sadece `auto_final_action = new_rgb_needed` olan `58` satiri kapsar
  - `keep_rgb_source`
  - `recolor_source`
  - `recolor_source_id`
  - `recolor_source_name`
  - `new_rgb`
  kolonlarini authoritative sekilde tasir
- Yeni RGB havuzu secilirken kullanilan occupied color uzayi:
  - canli `map_data/definition.csv`
  - `Works/map_data_sources/definition_modlu.csv`
  - `Works/map_data_sources/definition_orijinal.csv`
  - mevcut overlap satirlarinin kendi shared old RGB'leri
- Uretilen assignment sonucu:
  - toplam new RGB atanmis satir: `58`
  - `recolor modlu`: `2`
  - `recolor orijinal`: `56`
  - yeni RGB duplicate: `0`
  - mevcut color uzayiyla collision: `0`
- Kritik atama ornekleri:
  - `135,36,34`
    - `keep modlu`
    - `recolor orijinal`
    - `new_rgb = 1,5,32`
  - `177,24,32`
    - `keep modlu`
    - `recolor orijinal`
    - `new_rgb = 1,5,29`
  - `9,27,160`
    - `keep modlu`
    - `recolor orijinal`
    - `new_rgb = 1,5,30`
  - `134,78,44`
    - `keep orijinal`
    - `recolor modlu`
    - `new_rgb = 1,5,27`
- Bu otomatik semantic RGB atama katmaninin ustune staging uygulama turevi kuruldu:
  - `Works/tools/build_source_semantic_staging_fix.ps1`
  - amaci:
    - canli `map_data` dosyalarina dokunmadan
    - semantic overlap icin staging `provinces.png + definition.csv` uretmek
    - keep-source tarafini old/shared RGB'ye geri zorlamak
    - recolor-source tarafini `new_rgb` ile boyamak
    - `same_id` semantic conflictlerde placeholder ID ve placeholder piksel repurpose ederek yeni final kimlik yaratmak
- Bu scriptin girdileri:
  - `map_data/provinces.png`
  - `map_data/definition.csv`
  - `Works/map_data_sources/provinces_modlu_kalan.png`
  - `Works/map_data_sources/provinces_orijinal_dogu.png`
  - `Works/analysis/generated/source_semantic_overlap_audit/source_rgb_overlap_auto_rgb_assignments.csv`
  - `Works/analysis/generated/final_modlu_tracking_preserve_old_ids.csv`
  - `Works/analysis/generated/final_orijinal_tracking_preserve_old_ids.csv`
  - `Works/analysis/generated/final_placeholder_inventory_preserve_old_ids.csv`
  - `Works/analysis/generated/placeholder_pixel_map_preserve_old.csv`
- Bu scriptin urettigi staging ciktilar:
  - `Works/analysis/generated/source_semantic_staging_fix/provinces_source_semantic_staging.png`
  - `Works/analysis/generated/source_semantic_staging_fix/definition_source_semantic_staging.csv`
  - `Works/analysis/generated/source_semantic_staging_fix/source_semantic_staging_image_apply_report.csv`
  - `Works/analysis/generated/source_semantic_staging_fix/source_semantic_same_id_split_id_assignments.csv`
  - `Works/analysis/generated/source_semantic_staging_fix/source_semantic_staging_definition_changes.csv`
  - `Works/analysis/generated/source_semantic_staging_fix/source_semantic_staging_fix_summary.md`
- Staging uygulama sonucu:
  - toplam semantic assignment: `58`
  - `same_id` split: `15`
  - `different_id` recolor: `43`
  - kullanilan placeholder ID sayisi: `15`
  - kullanilan placeholder ID araligi: `12773..12787`
  - region apply rapor satiri: `116`
  - placeholder pixel repurpose satiri: `15`
  - staging definition duplicate RGB sayisi (`0,0,0` disi): `0`
  - recolor satirlarinda gercekten piksel degisen assignment: `58/58`
  - toplam recolor edilen piksel: `180178`
- `same_id` semantic split mantigi:
  - keep-source taraf mevcut merged final ID'de kalir
  - recolor-source taraf placeholder final ID'ye tasinir
  - ilgili gizli teknik placeholder pikseli de ayni `new_rgb` ile boyanir
  - boylece yeni split province hem gercek bolgesini hem de teknik kimlik pikselini kazanir
- Bu tur sadece staging uretir; canli `map_data/provinces.png` ve `map_data/definition.csv` henuz bu semantic split ile degistirilmedi
- `134,78,44 / 8688 / sea_bay_of_bengal` vakasi uzerinden yeni bir false-positive sinifi tespit edildi:
  - mod kaynaginda:
    - `8688;134;78;44;sea_bay_of_bengal`
    - `default.map` sinifi: `impassable_seas`
  - orijinal kaynaginda:
    - `8688;134;78;44;sea_bay_of_bengal`
    - `default.map` sinifi: `sea_zones`
  - ilk semantic kural bunu sadece `different_default_map_class` gorup yanlis sekilde `new_rgb_needed` demisti
  - kullanici itiraziyla bu kural daraltildi
- Yeni semantic kural:
  - `same_id + same_name + nonbarony + structured nonland/water default.map class`
  - tek basina split sebebi degildir
  - bu durum:
    - `semantic_same_province_suggest = True`
    - `semantic_classification = same_id_same_name_nonbarony_nonland`
    - `final_action = keep_single_identity`
  olarak ele alinacak
- Bu kural `Works/tools/build_source_semantic_overlap_audit.ps1` icine gomuldu; amac sadece `8688`i elle kapatmak degil, benzer water/nonland false-positive vakalarin tekrar etmesini onlemek
- Bu kuraldan sonra semantic karar zinciri yeniden uretildi:
  - `Works/tools/build_source_semantic_overlap_audit.ps1`
  - `Works/tools/build_source_semantic_rgb_assignments.ps1`
  - `Works/tools/build_source_semantic_staging_fix.ps1`
- Guncel authoritative sayilar:
  - otomatik `new_rgb` assignment: `57`
  - `recolor modlu`: `1`
  - `recolor orijinal`: `56`
  - staging assignment satiri: `57`
  - `same_id` split: `14`
  - `different_id` recolor: `43`
  - kullanilan placeholder id: `14`
  - staging definition duplicate RGB (`0,0,0` disi): `0`
- Bu yeniden uretimle:
  - `134,78,44` artik `source_rgb_overlap_auto_rgb_assignments.csv` icinde yer almiyor
  - `provinces_source_semantic_staging.png` icinde bu vaka icin ekstra `new_rgb` atanmiyor
  - staging split placeholder tuketimi `15 -> 14` dustu
- Semantic staging zincirinden sonra test paketi icin uygulama katmani kuruldu:
  - `Works/tools/apply_source_semantic_staging_to_test_files.ps1`
- Bu script:
  - staging `provinces_source_semantic_staging.png` dosyasini `test_files/map_data/provinces.png` olarak kopyalar
  - staging `definition_source_semantic_staging.csv` dosyasini `test_files/map_data/definition.csv` olarak kopyalar
  - same_id split assignment'lardan gelen nonland/default.map ihtiyaclarini `test_files/map_data/default.map` icine yorumlu blok olarak ekler
  - gerekiyorsa `test_files/common/landed_titles/00_landed_titles.txt` icinde barony `province = ...` baglarini yeni split ID'lere rewrite eder
- Bu turdaki test paketi sonucu:
  - guncellenen test dosyalari:
    - `test_files/map_data/provinces.png`
    - `test_files/map_data/definition.csv`
    - `test_files/map_data/default.map`
    - `test_files/common/landed_titles/00_landed_titles.txt`
  - same_id split `default.map` ekleme satiri: `7`
  - same_id split `landed_titles` relink satiri: `0`
  - test `default.map` icine su blok eklendi:
    - `# SOURCE SEMANTIC SAME-ID SPLITS BEGIN`
    - `impassable_mountains = LIST { 12774 12775 12776 12778 12779 12784 12786 }`
    - `# SOURCE SEMANTIC SAME-ID SPLITS END`
- Bu uygulamanin raporlari:
  - `Works/analysis/generated/source_semantic_test_package/source_semantic_test_package_summary.md`
  - `Works/analysis/generated/source_semantic_test_package/source_semantic_test_default_map_additions.csv`
  - `Works/analysis/generated/source_semantic_test_package/source_semantic_test_landed_title_relinks.csv`
- Yorum:
  - bu same_id split grubunda landed_titles tarafina yeni province ID rewrite gerektiren bir recolor-source barony bulunmadi; bu yuzden relink sayisi `0`
  - test paketi artik semantic staging map ve definition ile senkron durumdadir; sonraki dogal adim yeni test crash/log almaktir
- Sonraki crash ile birlikte somut blocker olarak su netlesti:
  - same_id semantic splitlerden gelen `impassable_mountains` yeni ID'leri test `default.map`e eklenmisti
  - ama eski split oncesi ID'ler vanilla-east impassable blokta kaldigi icin ayni `17` barony hala impassable province'e bagli gorunuyordu
  - bu yuzden `default.map` test uygulama scripti tekrar duzeltildi
- `Works/tools/apply_source_semantic_staging_to_test_files.ps1` guncellendi:
  - artik `default.map`e ayri ek blok yazmiyor
  - bunun yerine `# VANILLA EAST DEFAULT MAP BEGIN/END` blogunu parse edip yeniden yaziyor
  - same_id splitlerde:
    - eski `old_id` ilgili default.map sinifindan siliniyor
    - yeni `final_new_id` ayni sinifa ekleniyor
- Bu duzeltmeden sonra test `default.map` durumu:
  - `9664, 9665, 9666, 9668, 9671, 9672` eski impassable ID'leri bloktan temizlendi
  - yeni split ID'ler vanilla-east impassable blok icinde yasiyor:
    - `12774`
    - `12775`
    - `12776`
    - `12778`
    - `12779`
    - `12784`
    - `12786`
  - eski `# SOURCE SEMANTIC SAME-ID SPLITS` ek blogu kaldirildi; authoritative yer artik vanilla-east blok rewrite'i
- Bu adimin ozel raporu:
  - `Works/analysis/generated/source_semantic_test_package/source_semantic_test_default_map_additions.csv`
  - burada `old_id -> final_new_id` default.map rewrite satirlari authoritative olarak tutuluyor
- Bu adimdan sonra `test_files` paketindeki bir sonraki dogru adim:
  - yeniden oyun testi alip ayni `17 impassable barony` hatasinin dusup dusmedigine bakmak
- Sonraki testte oyun crash vermeden acildi; bu calisan durum referans kabul edildi
- Crash'i cozen pratik fark, `test_files/common/landed_titles/00_landed_titles.txt` icindeki legacy `_china` bloklarinin temizlenmesiyle birlikte `test_files` paketinin butun olarak stabil hale gelmesiydi
- Bunun ardindan calisan `test_files` seti canli dosyalara terfi edildi:
  - `test_files/common/landed_titles/00_landed_titles.txt` -> `common/landed_titles/00_landed_titles.txt`
  - `test_files/map_data/default.map` -> `map_data/default.map`
  - `test_files/map_data/definition.csv` -> `map_data/definition.csv`
  - `test_files/map_data/provinces.png` -> `map_data/provinces.png`
- Terfi sonrasi dogrulama:
  - `common/landed_titles/00_landed_titles.txt`, `map_data/default.map`, `map_data/definition.csv` ile `test_files` kopyalari birebir senkron
  - `map_data/provinces.png` hash'i ile `test_files/map_data/provinces.png` hash'i birebir ayni
- Bundan sonraki dogru asama:
  - crashsiz acilisin guncel `error.log`unu ayirip sadece kalan gercek hata/temizlik maddelerine odaklanmak
- Bu crashsiz acilisin sonraki ana log ailesi incelendi:
  - `C:\Users\bsgho\Documents\Paradox Interactive\Crusader Kings III\logs\error.log`
  - satir araligi `339249-340242`
  - hata ailesi: `Province '<id>' has no associated title in common/landed_titles`
- Bu aile icin kaynak-provenance raporu uretildi:
  - script: `Works/tools/build_missing_landed_title_source_cluster_report.ps1`
  - ciktilar:
    - `Works/analysis/generated/missing_landed_title_source_cluster/missing_landed_titles_source_detail.csv`
    - `Works/analysis/generated/missing_landed_title_source_cluster/missing_landed_titles_source_by_root.csv`
    - `Works/analysis/generated/missing_landed_title_source_cluster/missing_landed_titles_source_by_subtree.csv`
    - `Works/analysis/generated/missing_landed_title_source_cluster/missing_landed_titles_source_summary.md`
- Bu raporun net sonucu:
  - `994` eksik live province tamamen source old_id ve landed_titles hiyerarsisine baglandi
  - `missing_source_binding = 0`
  - `missing_final_master/source_old_id = 0`
  - yani bu ailede bilinmeyen veya eslesmeyen province kalmadi
- En buyuk root kumeleri:
  - `modlu_kalan / e_tibet` -> `285`
  - `orijinal_dogu / e_andong` -> `249`
  - `orijinal_dogu / e_srivijaya` -> `159`
  - `orijinal_dogu / e_amur` -> `129`
  - `modlu_kalan / e_qixi` -> `101`
  - `modlu_kalan / e_xi_xia` -> `61`
- Operasyonel yorum:
  - sorun artik tekil province degil; eksik `landed_titles` subtree/root coverage problemi
  - `e_andong`, `e_srivijaya`, `e_amur`, `e_qixi`, `e_xi_xia` gibi koklerin veya alt-duchy bloklarinin canli `common/landed_titles/00_landed_titles.txt` icinde eksik oldugu sayisal olarak kanitlandi
  - `e_tibet` icinde ise root mevcut olsa da bazi alt-subtree/county/barony coverage'i eksik
- Sonraki dogru adim:
  - bu rapordaki `by_subtree` kumelerine gore eksik landed_titles subtree'lerini source dosyalardan geri almak
  - oncelik sirasi: `e_tibet`, `e_andong`, `e_srivijaya`, `e_amur`, `e_qixi`, `e_xi_xia`
- Canli `common/landed_titles/00_landed_titles.txt` icine ilk buyuk coverage geri yuklemesi uygulandi:
  - script: `Works/tools/restore_missing_landed_title_roots.ps1`
  - bu turda sadece tam eksik `5` root geri alindi:
    - `e_andong`
    - `e_srivijaya`
    - `e_amur`
    - `e_qixi`
    - `e_xi_xia`
  - source provenance:
    - `e_andong`, `e_srivijaya`, `e_amur` -> vanilla `00_landed_titles.txt`
    - `e_qixi`, `e_xi_xia` -> mod `0backup\common\landed_titles\00_landed_titles.txt`
  - province ID'ler source old_id -> final_new_id olarak rewrite edildi
- Bu uygulamanin raporlari:
  - `Works/analysis/generated/missing_landed_title_restore_roots/restored_missing_landed_title_roots_rewrite_report.csv`
  - `Works/analysis/generated/missing_landed_title_restore_roots/restored_missing_landed_title_roots_summary.csv`
  - `Works/analysis/generated/missing_landed_title_restore_roots/restored_missing_landed_title_roots_summary.md`
- Root bazli rewrite sonucu:
  - `e_andong` -> rewritten `321`
  - `e_srivijaya` -> rewritten `162`
  - `e_amur` -> rewritten `130`
  - `e_qixi` -> rewritten `99`
  - `e_xi_xia` -> rewritten `61`, fallback `16`, removed `36`
- Ardindan `Works/tools/build_missing_landed_title_source_cluster_report.ps1` yeniden calistirildi ve eski `994` province listesinin canli landed_titles kapsami tekrar olculdu
- Guncel canli coverage sonucu:
  - toplam eski eksik liste: `994`
  - simdi canlida tanimli olanlar: `699`
  - hala tanimsiz kalanlar: `295`
- Kalan tanimsizlarin dagilimi:
  - `e_tibet` -> `285`
  - `e_yongliang` -> `8`
  - `e_bengal` -> `1`
  - `e_wendish_empire` -> `1`
- Bu, ilk buyuk root geri yuklemesinin dogrudan `699` province coverage kazandirdigini kanitladi
- Sonraki en dogru adim:
  - `e_tibet` icindeki eksik subtree/county/barony coverage'ini tamamlamak
  - ilk oncelikli alt kumeler:
    - `d_lhasa` `16`
    - `d_nagormo` `15`
    - `d_ngari` `14`
    - `d_qamdo` `14`
    - `d_tuyuhun` `14`
- Kullanici yeni bir is akisi tercihi verdi:
  - `landed_titles` gibi degisiklikler yapildiginda `test_files` kopyasi da ayni turda guncel tutulmali
  - sebep: kullanici dosyalari cogu zaman `test_files` icinden temin ediyor
- `Works/tools/restore_missing_landed_title_roots.ps1` buna gore genislestirildi:
  - artik ciktiyi hem
    - `common/landed_titles/00_landed_titles.txt`
    - `test_files/common/landed_titles/00_landed_titles.txt`
    dosyalarina yazar
  - restore kapsami da su rootleri icerecek sekilde buyutuldu:
    - `e_bengal`
    - `e_tibet`
    - `e_yongliang`
    - `e_wendish_empire`
- `2026-04-15` crash klasoru `C:\Users\bsgho\Documents\Paradox Interactive\Crusader Kings III\crashes\ck3_20260415_002257` icin yeni landed_titles incelemesi yapildi
- Crash deseni:
  - `logs/error.log` sonundaki baskin hata ailesi `Province with no county data`
  - kumelenen rootler:
    - `e_tibet` -> `282`
    - `e_yongliang` -> `8`
    - `e_bengal` -> `1`
    - `e_wendish_empire` -> `1`
    - `e_xi_xia` -> `1`
- Yeni net bulgu:
  - asıl sorun sadece eksik root coverage degil, onceki `landed_titles` degisikliklerinde iki buyuk yapisal brace kaymasi da varmis
  - `e_bengal` rootu `h_india` icine yanlislikla gomulmus durumdaydi
  - eski `e_yongliang` rootu da `h_china` icine yanlislikla gomulmus durumdaydi
  - bu yuzden bu rootler gercek top-level blok olarak davranmiyordu
- Yapilan duzeltmeler:
  - `common/landed_titles/00_landed_titles.txt`
  - `test_files/common/landed_titles/00_landed_titles.txt`
  icinde:
    - `h_india -> e_bengal` sinirinda eksik kapanis dogru yere tasindi
    - `h_china -> e_yongliang` sinirinda eksik kapanis dogru yere tasindi
  - ardindan `restore_missing_landed_title_roots.ps1` tekrar calistirildi ve restore edilen rootler temiz top-level olarak yeniden basildi
- Son dogrulama:
  - hedef rootlerin hepsi `depth_before=0` olacak sekilde top-level hale geldi
  - dosya genel brace dengesi `final_depth=0`
  - crash logdaki `Province with no county data` listesinden taninabilen `295` province adinin `294`u artik landed_titles icinde bagli
  - kalan tek artik isim:
    - `CirQF_Langxinguan` (`final id 12356`)
  - bu artik `h_china` tarafindan geliyor; ana Tibet/Yongliang kaynakli crash zinciri ise landed_titles yapisal olarak kapatildi
- `2026-04-15` mevcut `logs/error.log` icinde crash olmadan kalan `Province 'X' has no associated title in common/landed_titles` blogu icin yeni landed_titles onarimi yapildi
- Bu turda duzeltilen exact eksikler:
  - `e_tibet`
    - `b_karub` -> `9301`
    - `c_deqen` icindeki `b_deqen` -> `9316`
    - `c_deqen` icindeki `b_balung` -> `9317`
  - `e_bengal`
    - `c_charaideo` icine `b_patkai` -> `10488`
  - `e_yongliang`
    - minimal `k_longxi_china -> d_shanzhou -> c_hezhou_china`
    - `b_hezhou_longyou_china` -> `12916`
    - `b_binglingsi_china` -> `12965`
  - `e_xi_xia`
    - minimal `d_guiyi -> c_subei -> b_ngor` -> `9408`
    - minimal `d_aksay -> c_aksay/c_haltang`
    - `9470/9471/9472/9469` baglari geri geldi
  - `e_andong`
    - vanilla `e_andong` blogundan sadece o anki error.log'da eksik kalan subtree'ler parcali olarak geri getirildi
    - province rewrite barony bazinda `missing_landed_titles_source_detail.csv` icindeki `final_new_id` degerlerine gore yapildi
    - boylece `k_balhae`, `k_luzhen`, `k_raole`, `k_shiwei` ve onlara bagli eksik county/barony zinciri geri geldi
- Bu tur sonunda yerel landed_titles dogrulamasi:
  - error.log'daki ayni setten okunan `260` missing province id'nin `260/260`i artik landed_titles icinde bagli
  - duplicate province assignment `0`
  - dosya brace dengesi `final_depth=0`
  - `common/landed_titles/00_landed_titles.txt` ile `test_files/common/landed_titles/00_landed_titles.txt` birebir ayni tutuldu
- `2026-04-15` canonical title mapping sistemi eklendi
- Yeni source-of-truth:
  - `Works/map_data_sources/title_relation_master.csv`
- Yeni tool'lar:
  - `Works/tools/build_title_relation_master.ps1`
  - `Works/tools/build_title_relation_outputs.ps1`
- Alinan karar:
  - canonical namespace `mod title id`
  - mapping sadece `vanilla -> mod`
  - `exact/contextual` olmayanlar otomatik rewrite edilmez
  - savunulabilir karsiligi olmayanlar `manual_review` olarak kalir
- Seed sonucu:
  - source inventory `3776`
  - mapped `3764`
  - manual review `12`
  - contextual auto-map `0`
  - safe rewrite row `0`
  - scan edilen hedef dosyalarda rewrite candidate hit `0`
- Bu su anlama geliyor:
  - repo taranan alanlarda zaten agirlikli olarak canonical mod title id'lerini kullaniyor
  - mapping sistemi su an daha cok coverage/validation/manual review katmani olarak devrede
- Mevcut `manual_review` listesi:
  - `e_andong`: `k_khitan`, `d_LIAO_linhuang`, `d_LIAO_shangjing`, `d_LIAO_zhongjing`, `d_yanyun_yuyi`
  - `e_goryeo`: `b_Goryeo_Bukgye_Maengju`, `b_Goryeo_Donggye_Deungju`, `b_Goryeo_Donggye_Hwaju`, `b_Goryeo_Donggye_Uiju`, `b_Goryeo_Donggye_Myeongju`
  - `e_srivijaya`: `b_siantan`, `b_muot`
- Generated raporlar:
  - `Works/analysis/generated/title_relation_mapping/title_relation_source_inventory.csv`
  - `Works/analysis/generated/title_relation_mapping/title_relation_coverage.csv`
  - `Works/analysis/generated/title_relation_mapping/title_relation_manual_review.csv`
  - `Works/analysis/generated/title_relation_mapping/title_relation_reference_hits.csv`
  - `Works/analysis/generated/title_relation_mapping/title_relation_rewrite_candidates.csv`
  - `Works/analysis/generated/title_relation_mapping/title_relation_outputs_summary.md`
- Sonradan canonical mapping seed'inde yapisal bug bulundu ve duzeltildi
- Bug:
  - `build_title_relation_master.ps1` canonical `mod_title_id` havuzunu yanlislikla `common/landed_titles/00_landed_titles.txt` icindeki live hibrit dosyadan kuruyordu
  - bu da `c_zezhou -> c_zezhou` gibi, orijinal modda bulunmayan ama live dosyada bulunan yanlis `exact` eslesmeler uretiyordu
- Duzeltme:
  - canonical aday havuzu artik sadece orijinal mod kaynagindan geliyor:
    - `C:\Program Files (x86)\Steam\steamapps\workshop\content\1158310\2216670956\0backup\common\landed_titles\00_landed_titles.txt`
  - province set karsilastirmasi hem vanilla hem mod tarafinda `final_new_id` uzayina normalize edildi:
    - `final_orijinal_tracking_preserve_old_ids.csv`
    - `final_modlu_tracking_preserve_old_ids.csv`
- Sonuc:
  - hatali `same_title_id` false-positive'leri temizlendi
  - `c_zezhou` artik `c_zezhou` olarak maplenmiyor; `manual_review`
  - yeni seed sayilari:
    - source inventory `3776`
    - mapped `1118`
    - manual review `2658`
    - safe rewrite row `0`
- Yorum:
  - bu sayilar daha dusuk ama semantik olarak daha dogru
  - bundan sonraki ilerleme manual review veya daha akilli contextual heuristic ile olacak
- `2026-04-16` province-first review turu devam etti
- `e_goryeo` subtree probe:
  - `works/analysis/generated/province_relation_mapping/cluster_reviews/e_goryeo_block_probe.csv`
  - `works/analysis/generated/province_relation_mapping/cluster_reviews/e_goryeo_block_probe_summary.md`
  - sonuc:
    - `rows = 21`
    - `review:manual = 16`
    - `blocked:not_primary_target_source = 3`
    - `blocked:no_source_history = 2`
  - tum playable adaylar ya `e_japan` kokenliydi ya da guvenli source history tasimiyordu
  - bu turda `e_goryeo` icin savunulabilir manual promote yapilmadi
- Review araci komsu cluster secimi icin kullanildi:
  - `e_tibet`, `e_amur`, `e_bengal` block probe raporlari uretildi
  - en yuksek getirili cluster `e_tibet` gorundu
- `e_tibet` icinde bir manuel exact terfi yapildi:
  - `9283 Kagong -> 9283 Kagong`
  - gerekce:
    - source ve target ayni `id`
    - source ve target ayni ad
    - `target_source_count_all = 1`
    - `overlap_score = 1.0`
    - source history mevcut
  - `works/map_data_sources/province_relation_master.csv` satiri:
    - `classification = exact`
    - `status = mapped`
    - `apply_to_history = yes`
    - note: `manual: same_id_name_unique_target_overlap_1_0`
  - not:
    - mevcut live/test province history bloklari zaten orijinal mod source ile ayniydi
    - yani bu terfi semantik esitligi master tabloda resmilestirdi; history iceriginde fiili fark olusturmasi beklenmiyor
- `e_bengal` subtree probe acildi:
  - `works/analysis/generated/province_relation_mapping/cluster_reviews/e_bengal_block_probe.csv`
  - `works/analysis/generated/province_relation_mapping/cluster_reviews/e_bengal_block_probe_summary.md`
  - sonuc:
    - `rows = 151`
    - `ready:exact = 22`
    - `review:high_overlap = 3`
    - `review:manual = 33`
    - geri kalan buyuk kisim `blocked:not_primary_target_source` ve `blocked:shared_target_low_coverage`
- `e_bengal` icinde iki manuel exact terfi yapildi:
  - `9556 Ava -> 9556 Ava`
  - `9562 Minbu -> 9562 Minbu`
  - gerekce:
    - source ve target ayni `id`
    - source ve target ayni ad
    - `target_source_count_all = 1`
    - ikinci aday overlap'i marjinal kaldi
    - `overlap_score` sirasiyla `0.996656` ve `0.961702`
    - source history mevcut
  - `works/map_data_sources/province_relation_master.csv` satirlari:
    - `classification = exact`
    - `status = mapped`
    - `apply_to_history = yes`
    - note: `manual: same_id_name_unique_target_high_overlap`
- `11585 Khabaungkyo -> 9595 Swa` promote edilmedi
  - ayni guven seviyesinde degil; ad/id degisimi var ve semantik sapma riski daha yuksek
- `11585 Khabaungkyo -> 9595 Swa` icin sonraki inceleme sonucu:
  - backup `c_toungoo` icinde hem `b_khabaungkyo = 11585` hem `b_swa = 9595` var
  - current landed_titles `c_toungoo` ise sadece `9593/9594/9595` tasiyor ve `11585` artik doguda degil
  - province relation verisi gosteriyor ki:
    - source `11585 b_khabaungkyo` en guclu olarak current `9595`e oturuyor
    - source `9595 b_swa` ise current `9593`e oturuyor
  - yani burada basit rename degil, `c_toungoo` icinde barony slot yeniden dagitimi var
  - bu nedenle `11585 -> 9595` province-only exact promote edilmedi
  - not:
    - bu tip satirlar title/subtree migration asamasinda birlikte ele alinmali
- `c_toungoo` subtree probe uretildi:
  - `works/analysis/generated/province_relation_mapping/cluster_reviews/c_toungoo_block_probe.csv`
  - `works/analysis/generated/province_relation_mapping/cluster_reviews/c_toungoo_block_probe_summary.md`
  - sonuc:
    - `rows = 9`
    - `review:high_overlap = 1`
    - `blocked:shared_target_low_coverage = 2`
    - `blocked:not_primary_target_source = 4`
    - `blocked:no_source_history = 2`
- `c_toungoo` icindeki barony shuffle yapisi:
  - source `11585 b_khabaungkyo` -> current `9595 b_swa` en guclu aday
  - source `9595 b_swa` -> current `9593 b_toungoo`
  - source `9593 b_toungoo` de current `9593 b_toungoo` uzerine yukleniyor
  - yani burada ayni county icinde province geometrisi ile aktif title slotlari birebir hizali degil
- karar:
  - `c_toungoo` icinde province-only promote yapilmadi
  - bu blok `title + province` birlikte ele alinacak subtree migration adayi olarak park edildi
- `2026-04-16` province manual review inventory araci eklendi:
  - `works/tools/build_province_manual_review_inventory.py`
- Uretilen raporlar:
  - `works/analysis/generated/province_relation_mapping/manual_review_inventory/province_manual_review_worklist.csv`
  - `works/analysis/generated/province_relation_mapping/manual_review_inventory/province_manual_review_root_summary.csv`
  - `works/analysis/generated/province_relation_mapping/manual_review_inventory/province_manual_review_summary.md`
  - `works/analysis/generated/province_relation_mapping/manual_review_inventory/province_probe_review_worklist.csv`
  - `works/analysis/generated/province_relation_mapping/manual_review_inventory/province_probe_summary.csv`
  - `works/analysis/generated/province_relation_mapping/manual_review_inventory/province_probe_summary.md`
- Bulgular:
  - master seviyesinde `manual_review` satirlarinin buyuk cogu hala `blocked:no_target_title`, yani dogrudan uygulanabilir backlog icin probe seviyesine bakmak daha dogru
  - probe bazli inventory sonucu:
    - `probe files = 11`
    - `unresolved probe rows = 1100`
    - `continue_exact_probe = 4`
    - `park = 7`
  - en verimli probe su an:
    - `e_srivijaya_pilot`
    - `rows = 264`
    - `high_overlap = 18`
    - `manual = 145`
  - sonra:
    - `e_bengal_block_probe`
    - `e_tibet_block_probe`
    - `c_toungoo_block_probe`
- Yorum:
  - bundan sonra province-only exact toplama icin en iyi hedef `e_srivijaya_pilot`
  - `c_toungoo_block_probe` ise exact backlogtan cok `subtree/title+province migration` backlogu olarak degerlendirilmeli
- Ek domain bilgisi:
  - `e_tibet` buyuk olcude moddan geliyor; sadece kucuk bir dogu parcasi vanilla ile yenilenmis
  - `e_bengal` de ayni sekilde buyuk olcude moddan geliyor; vanilla etkisi lokal
- Sonuc:
  - `e_tibet` ve `e_bengal` artik genel migration backlog'u gibi degil, `mod-canonical + kucuk vanilla cleanup` bloklari olarak ele alinacak
  - bu iki root icin full probe kovalamak yerine yalnizca vanilla kalan alt parcaya odaklanilacak
- `e_srivijaya_pilot` icin yeni manuel shortlist uretildi:
  - `works/analysis/generated/province_relation_mapping/manual_review_inventory/e_srivijaya_high_overlap_manual.csv`
  - `works/analysis/generated/province_relation_mapping/manual_review_inventory/e_srivijaya_high_overlap_manual.md`
- `e_srivijaya` sonucu:
  - `18` adet `review:high_overlap` satir var
  - bunlarin hicbiri province-only `exact` promote icin yeterince temiz degil
  - ortak ozellik:
    - neredeyse hepsi `merge`
    - overlap cok yuksek olsa da `target_coverage` dusuk
    - yani target province, source province'in basit birebir karsiligi degil; daha buyuk veya yeniden paketlenmis bir slot
- Kural:
  - `e_srivijaya` high-overlap satirlari bundan sonra `manual/contextual` backlog olarak tutulacak
  - otomatik `exact` promote ancak ayni `id/ad` veya daha sert kanit gelirse yapilacak
- `e_srivijaya` icinde yeni bir sert kanitli satir bulundu ve promote edildi:
  - `10401 Nicobar Islands -> 12849 Muot/Nancowry`
  - gerekce:
    - backup landed_titles icinde `b_nakkavaram = province 10401`
    - current landed_titles icinde ayni `b_nakkavaram = province 12849`
    - yani bu satir geometri dusuk gorunse de ayni barony yolunun yeni province id'ye tasinmis hali
    - current live history `12849` backup mod source ile farkliydi; bu nedenle promote fiili history duzeltmesi de sagliyor
  - `works/map_data_sources/province_relation_master.csv` satiri:
    - `classification = exact`
    - `status = mapped`
    - `apply_to_history = yes`
    - note: `manual: same_barony_path_id_reuse_to_current_target`
- `10401 -> 12849` uygulama sonucu:
  - `works/tools/apply_province_relation_history.ps1` calistirildi
  - live/test `history/provinces/00_MB_PROVINCES.txt` tekrar senkron kaldi
  - current `12849` history blogu artik backup mod source ile uyumlu:
    - `culture = aslian`
    - `religion = kadai`
    - `holding = tribal_holding`
  - validator temiz:
    - `validation errors = 0`
    - `validation warnings = 0`
    - `missing playable province titles = 0`
- `e_srivijaya_pilot` guncel durum:
  - `ready:exact = 3`
  - `review:manual = 54`
  - `blocked:not_primary_target_source = 88`
  - `blocked:shared_target_low_coverage = 20`
- `2026-04-16` strict `same_county_barony` exact harvest turu yapildi:
  - yeni promote edilen satirlar:
    - `8722 Karnaphuli -> 8722 Karnaphuli`
    - `9641 Singu -> 9641 Singu`
    - `9643 Takon -> 9643 Takon`
    - `9571 Yamethin -> 9571 Yamethin`
    - `828 Chatigama -> 828 Chatigama`
    - `9624 Kale -> 9624 Kale`
    - `11535 Taikkala -> 9630 Taikkala`
    - `9324 Lenggu -> 9324 Lenggu`
    - `9443 Jone -> 9443 Jone`
    - `9457 Choqu -> 9457 Choqu`
  - ortak promote gerekceleri:
    - ayni county/barony yolu veya ayni barony yolunun yeni province id'ye tasinmis olmasi
    - current target tarafinda dominant source olmalari
    - source history blogunun mevcut olmasi
  - `works/tools/apply_province_relation_history.ps1` her batch sonrasi tekrar calistirildi
  - `works/tools/validate_east_mapping_pipeline.ps1` her batch sonrasi temiz dondu
  - guncel apply sonucu:
    - `exact rows requested = 123`
    - `applied rows = 228`
    - `missing source blocks = 27`
  - guncel validator sonucu:
    - `validation errors = 0`
    - `validation warnings = 0`
    - `missing playable province titles = 0`
    - `landed_titles live/test hash match = yes`
  - live/test `history/provinces/00_MB_PROVINCES.txt` SHA256:
    - `A9AB084714B0340ED098FC3C3836955D9F79BE6B1C9AEF6BA890EBFD4B26356E`
  - probe durumlari:
    - `e_bengal_block_probe`: `ready:exact = 32`, `review:manual = 28`, `blocked:not_primary_target_source = 52`, `blocked:shared_target_low_coverage = 31`
    - `e_tibet_block_probe`: `ready:exact = 31`, `review:manual = 5`, `blocked:no_source_history = 4`
  - yorum:
    - `e_tibet` ve `e_bengal` icinde genel migration yerine `strict exact` hasadi verimli olmaya devam ediyor
    - `c_toungoo` benzeri shuffle/subtree vakalari ise hala province-only promote icin uygun degil
- Ayni tur icinde daha gevsek ama hala savunulabilir `province history` promote esikleri de uygulandi:
  - `same_county_barony_unique_target`:
    - `9317 Balung -> 9317 Balung`
    - `9328 Gyezil -> 9328 Gyezil`
    - `9445 Zhugqu -> 9445 Zhugqu`
    - `9551 Popa -> 9551 Popa`
  - `same_county_name_unique_target`:
    - `9561 Mekkhaya -> 9561 Mekkhaya`
    - `9625 Chin -> 9625 Chin`
  - `same_barony_name_unique_target`:
    - `9564 Ngape -> 9564 Ngape`
  - `same_id_name_dominant_self_target`:
    - `9557 Pinya -> 9557 Pinya`
    - `9568 Sagaing -> 9568 Sagaing`
    - `9590 Thayetmyo -> 9590 Thayetmyo`
    - `9599 Krapan -> 9599 Krapan`
    - `9622 Maukkadaw -> 9622 Maukkadaw`
    - `9628 Muttina -> 9628 Muttina`
    - `9638 Shwegyin -> 9638 Shwegyin`
    - `9639 Myinmu -> 9639 Myinmu`
  - `same_id_name_unique_target_high_coverage`:
    - `9658 Thaungdut -> 9658 Thaungdut`
  - `same_barony_path_id_reuse_to_current_target`:
    - `11061 Dagon -> 9598 Dagon`
  - guncel apply sonucu:
    - `exact rows requested = 140`
    - `applied rows = 262`
    - `missing source blocks = 27`
  - guncel validator sonucu degismedi:
    - `validation errors = 0`
    - `validation warnings = 0`
    - `missing playable province titles = 0`
    - `landed_titles live/test hash match = yes`
  - live/test `history/provinces/00_MB_PROVINCES.txt` SHA256:
    - `0FC7A544E5409B1548FE2A8885D7A3C93619D7C42F7047EB104B2747E942060B`
  - probe guncellemeleri:
    - `e_bengal_block_probe`: `ready:exact = 46`, `review:manual = 17`, `blocked:shared_target_low_coverage = 28`, `blocked:not_primary_target_source = 52`
    - `e_tibet_block_probe`: `ready:exact = 34`, `review:manual = 2`, `blocked:no_source_history = 4`
  - kalan agir zorluklar:
    - `11585 Khabaungkyo -> 9595 Swa` hala `review:high_overlap`; bu `c_toungoo` subtree shuffle vakasi olarak ayrik tutuluyor
    - kalan `e_bengal` satirlarinin buyuk cogu artik gercek `merge/shared_target` veya `not_primary_target_source` sinifinda
