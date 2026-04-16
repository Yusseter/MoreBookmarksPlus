# Province Touchpoints Gap Check

Bu not, `province_touchpoints_inventory.csv` listesinin ek bir gap-check taramasindan sonra hangi durumda oldugunu kaydeder.

## Sonuc

Inventory su an pratik olarak hedefledigimiz listeye yaklasmis durumda.

Gap-check sirasinda envantere sonradan dahil edilmis gercek dosya aileleri:

- `common/bookmarks/bookmarks/00_bookmarks.txt`
- `common/religion/holy_site_types/00_holy_site_types.txt`
- `common/religion/holy_site_types/RICE_holy_sites.txt`
- `common/coat_of_arms/coat_of_arms/91_NB_landed_titles.txt`
- `common/coat_of_arms/coat_of_arms/92_NB_dynasties.txt`
- `common/coat_of_arms/dynamic_definitions/00_MB_dynamic_coas.txt`

Bu dosyalar dahil edildi cunku sabit county/barony title referansi veya title mapping iceriyorlar.

## Bilincli Olarak Disarida Birakilanlar

Gap-check taramasinda envanter disinda kalan iki dosya bulundu:

- `common/coat_of_arms/coat_of_arms/93_NB_random_templates.txt`
- `common/dynasties/00_dynasties.txt`

Bunlar su an bilincli olarak disarida:

- `93_NB_random_templates.txt`
  - `c_diamond_combo_1 = { ... }` gibi `c_` ile baslayan template anahtarlari var
  - bunlar landed title referansi degil, COA template adi

- `00_dynasties.txt`
  - `c_kasar_chikidyn001 = { ... }` gibi `c_` ile baslayan dynasty anahtarlari var
  - bunlar county title degil, dynasty key

Yani bu iki dosya broad regex ile yakalanabiliyor ama bizim province/title baglaminda actionable degil.

## Guncel Yorum

- Core aileler:
  - `map_data_core`
  - `map_data_regions`
  - `history_provinces`
  - `landed_titles`
  - `history_titles`
  - `map_object_data`

- `secondary_province_touchpoint`
  - artik yalnizca sabit province ID, sabit county/barony title referansi veya sabit title mappingi iceren ek dosyalari hedefler

- Bu nedenle liste artik ilk surume gore daha dar ve kullanisli:
  - localization false positive'leri cikarildi
  - sadece dinamik `capital_province/title_province` kullanan, ama sabit province/title icermeyen dosyalar buyuk olcude elendi
