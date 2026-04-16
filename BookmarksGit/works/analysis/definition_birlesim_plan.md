# Definition Birlesim Plani

## Durum

- Tarih: `2026-04-11`
- Bu not, mod ve vanilla haritalarini birlestirme projesinde `definition_birlesim.csv` uretim mantigini netlestirmek icin tutuluyor.
- Bu dosya uzun analiz, yorum ve karar notlari icin var.
- Ozet hafiza her zaman `hafiza.md` dosyasinda da tutulmali.

## Kullanici Is Akisi Tercihi

- Kullanici acikca "su an tartisiyoruz" dediginde otomatik uygulamaya gecilmemeli.
- Kullanici 2026-04-11 tarihinde mevcut planlama konusu icin tekrar yetki verdi.
- Kullanici `hafiza.md`nin sisman olmasindan cekinmiyor.
- Uzun analizler yalnizca gecici sohbet baglaminda birakilmamali.

## Girdiler

### Definition Kaynaklari

- `map_data/definition_modlu.csv`
- `map_data/definition_orijinal.csv`

### Tam Province Haritalari

- `map_data/provinces_modlu.png`
- `map_data/provinces_orijinal.png`

### Secim ve Kontrol Haritalari

- `map_data/provinces_modlu_dogu.png`
- `map_data/provinces_modlu_kalan.png`
- `map_data/provinces_orijinal_dogu.png`
- `map_data/provinces_orijinal_kalan.png`
- `map_data/provinces_birlesim.png`

## Guncel Girdi Hash Kaydi

- `provinces_modlu.png`
  - `05A03A6FB339CFA64E57974BCED142180D4CFA52730E64DB9B199F241B652438`
- `provinces_modlu_dogu.png`
  - `F3ABE180F5E10033A3D295998A0D1E0874CCE6B4BDBF2F3160AAE1B548A438DB`
- `provinces_modlu_kalan.png`
  - `1AB2562A9109388C734F0B2C199F6E9E6F3CF6CEFF1D4F41EBC96A70E48CD501`
- `provinces_orijinal.png`
  - `33A2B0D488DE5CB79488E5C8603788D52277DDAB93FB1F3B1FED0FCD75E82CD4`
- `provinces_orijinal_dogu.png`
  - `F354B7FBFD13B3854837FDB02A5B1958A960BA478D810AC56ED3463BBA166504`
- `provinces_orijinal_kalan.png`
  - `AC136EE9E2A6621CFB8D7AAEDA2DB5969B6442A7E382513486116EBCBF372714`
- `provinces_birlesim.png`
  - `514DCA0E95DAF9FA23304604708B90CBE50768C91D2FFADCFAAD2C13EB94102D`

## Ana Model

- `PNG` dosyalari hangi province geometrisinin finalde kaldigini gosterir.
- `definition_modlu.csv` ve `definition_orijinal.csv` dosyalari bu geometrilerin kimlik sozlugudur.
- Final hedef, PNG'den definition "yeniden okumak" degil; iki mevcut definition sozlugunu secim PNG'leri yardimiyla birlestirmektir.

## Kaynak Rolleri

- Mod tarafi ana kimlik kaynagi:
  - `definition_modlu.csv`
  - `provinces_modlu.png`

- Vanilla tarafi ana kimlik kaynagi:
  - `definition_orijinal.csv`
  - `provinces_orijinal.png`

- Final secim kaynagi:
  - `provinces_birlesim.png`

- Audit ve capraz kontrol:
  - `provinces_modlu_dogu.png`
  - `provinces_modlu_kalan.png`
  - `provinces_orijinal_dogu.png`
  - `provinces_orijinal_kalan.png`

## Boyut ve Definition Temeli

- Tam mod province haritasi: `9216x4608`
- Tam vanilla province haritasi: `9216x4608`
- `definition_modlu.csv` satir sayisi: `14697`
- `definition_orijinal.csv` satir sayisi: `13270`

## Tarihsel Not: Superseded Kirik Girdi

- Ilk verilen `provinces_orijinal_dogu.png` dosyasi onceki analizde ciddi renk bozulmasi gostermisti.
- O surumde non-black unique renk sayisi `61589` idi.
- Bu surum artik gecerli kabul edilmemeli.
- Guncel plan yalnizca duzeltilmis `provinces_orijinal_dogu.png` uzerinden yorumlanmali.

## Guncel PNG Ozetleri

### Tam Haritalar

- `provinces_modlu.png`
  - non-black unique renk: `14155`
  - black piksel: `0`

- `provinces_orijinal.png`
  - non-black unique renk: `12750`
  - black piksel: `0`

### Secim Haritalari

- `provinces_modlu_dogu.png`
  - non-black unique renk: `4282`
  - black piksel: `28010551`

- `provinces_modlu_kalan.png`
  - non-black unique renk: `9891`
  - black piksel: `14456836`

- `provinces_orijinal_dogu.png`
  - non-black unique renk: `3391`
  - black piksel: `28010490`

- `provinces_orijinal_kalan.png`
  - non-black unique renk: `9365`
  - black piksel: `14459659`

- `provinces_birlesim.png`
  - non-black unique renk: `13142`
  - black piksel: `0`

## 2026-04-11 Renk Butunlugu Dogrulamasi

- Kullanici mevcut `provinces*.png` dosyalarindaki renkleri duzelttigini ve anti-alias benzeri hatalar kalmamis olmasi gerektigini belirtti.
- Bunun uzerine exact RGB kaynagi kontrolu yapildi.

### Kontrol Sonucu

- `provinces_modlu_dogu.png`
  - non-black unique renk: `4282`
  - mod tam haritasinda bulunmayan renk: `0`

- `provinces_modlu_kalan.png`
  - non-black unique renk: `9891`
  - mod tam haritasinda bulunmayan renk: `0`

- `provinces_orijinal_dogu.png`
  - non-black unique renk: `3391`
  - vanilla tam haritasinda bulunmayan renk: `0`

- `provinces_orijinal_kalan.png`
  - non-black unique renk: `9365`
  - vanilla tam haritasinda bulunmayan renk: `0`

- `provinces_birlesim.png`
  - non-black unique renk: `13142`
  - mod veya vanilla tam haritalarinda bulunmayan renk: `0`

### Teknik Yorum

- Bu sonuc, mevcut secim PNG'lerinde anti-alias, resample veya yeni uydurulmus ara renk kalmadigini kuvvetle destekliyor.
- Yani secim PNG'leri artik exact province RGB setleriyle uyumlu gorunuyor.
- Bu, onceki kirik `provinces_orijinal_dogu.png` surumunden farkli olarak guncel setin guvenilir oldugunu gosteren guclu bir isaret.

### Sinir

- Bu kontrol yalnizca renk butunlugunu dogrular.
- Province secim mantigi, split province, eksik piksel, ya da dogu/kalan complement kusurlari gibi konular ayri kontrollerle degerlendirilmelidir.

## 2026-04-11 Definition ve PNG Uyumluluk Kontrolu

Bu kontrol iki yone bakar:

1. PNG'de gorunen her non-black rengin ilgili definition dosyasinda bir satiri var mi?
2. Definition dosyasindaki her non-black renk ilgili PNG'de gercekten kullaniliyor mu?

### Mod Tam Haritasi

- `provinces_modlu.png`
  - PNG non-black unique renk: `14155`
  - `definition_modlu.csv` non-black unique renk: `14696`
  - PNG'de olup definition'da olmayan renk: `0`
  - definition'da olup PNG'de kullanilmayan renk: `541`

Yorum:

- Kapsama sorunu yok.
- Ama mod definition'inda haritada kullanilmayan ek satirlar bulunuyor.

### Vanilla Tam Haritasi

- `provinces_orijinal.png`
  - PNG non-black unique renk: `12750`
  - `definition_orijinal.csv` non-black unique renk: `13268`
  - PNG'de olup definition'da olmayan renk: `0`
  - definition'da olup PNG'de kullanilmayan renk: `518`

Yorum:

- Kapsama sorunu yok.
- Vanilla definition'inda da haritada kullanilmayan ek satirlar bulunuyor.

### Mod Secim PNG'leri

- `provinces_modlu_dogu.png`
  - PNG'de olup `definition_modlu.csv` icinde olmayan renk: `0`
  - definition'da olup bu secimde kullanilmayan renk: `10414`

- `provinces_modlu_kalan.png`
  - PNG'de olup `definition_modlu.csv` icinde olmayan renk: `0`
  - definition'da olup bu secimde kullanilmayan renk: `4805`

Yorum:

- Beklenen sonuc.
- Secim PNG'leri mod definition sozlugunun alt kumelerini kullaniyor.

### Vanilla Secim PNG'leri

- `provinces_orijinal_dogu.png`
  - PNG'de olup `definition_orijinal.csv` icinde olmayan renk: `0`
  - definition'da olup bu secimde kullanilmayan renk: `9877`

- `provinces_orijinal_kalan.png`
  - PNG'de olup `definition_orijinal.csv` icinde olmayan renk: `0`
  - definition'da olup bu secimde kullanilmayan renk: `3903`

Yorum:

- Beklenen sonuc.
- Secim PNG'leri vanilla definition sozlugunun alt kumelerini kullaniyor.

### Birlesim PNG ve Definition Birligi

- `provinces_birlesim.png`
  - non-black unique renk: `13142`
  - her iki definition'da da bulunmayan renk: `0`
  - sadece mod definition'da bulunan renk: `590`
  - sadece vanilla definition'da bulunan renk: `3094`
  - hem mod hem vanilla definition'da bulunup ayni ID olan renk: `9333`
  - hem mod hem vanilla definition'da bulunup farkli ID olan renk: `125`

Yorum:

- Final birlesim icin tanim kapsama eksigi yok.
- Ana sorun definition eksigi degil, collision siniflandirmasi ve politika secimi.

## Uyumluluk Sonucu

- `definition_modlu.csv` <-> `provinces_modlu.png`: uyumlu
- `definition_orijinal.csv` <-> `provinces_orijinal.png`: uyumlu
- Secim PNG'leri kendi kaynak definition dosyalariyla uyumlu
- `provinces_birlesim.png`, mod+vanilla definition birligiyle uyumlu

Pratik anlam:

- Final `definition_birlesim.csv` uretiminde "PNG'de gorunen ama definition'da olmayan renk" tipi bir blocker yok.
- Bir sonraki asama rahatlikla collision politikasina kayabilir.

## Secim Kalitesi

### Mod Tarafi

- `provinces_modlu_dogu.png`
  - tam tutulan province rengi: `4250`
  - hic alinmayan province rengi: `9873`
  - parcali kalan province rengi: `32`

- `provinces_modlu_kalan.png`
  - tam tutulan province rengi: `9851`
  - hic alinmayan province rengi: `4264`
  - parcali kalan province rengi: `40`

- `provinces_modlu_dogu.png` ile `provinces_modlu_kalan.png` arasinda ortak RGB sayisi: `18`
- Bu deger, mod tarafi dogu/kalan ayriminin tam complement olmadigini gosteriyor.
- `32` ve `40` parcali province sayilarinin farkli olmasi da bunu destekliyor.

### Vanilla Tarafi

- `provinces_orijinal_dogu.png`
  - tam tutulan province rengi: `3385`
  - hic alinmayan province rengi: `9359`
  - parcali kalan province rengi: `6`

- `provinces_orijinal_kalan.png`
  - tam tutulan province rengi: `9359`
  - hic alinmayan province rengi: `3385`
  - parcali kalan province rengi: `6`

- `provinces_orijinal_dogu.png` ile `provinces_orijinal_kalan.png` arasinda ortak RGB sayisi: `6`
- Vanilla ayrimi mod tarafina gore daha temiz gorunuyor.

## Composite Kontroller

### Modun Kendi Icinde

- `provinces_modlu_dogu.png + provinces_modlu_kalan.png -> provinces_modlu.png`
  - non-ambiguous mismatch piksel: `624`
  - overlap same-color piksel: `0`
  - overlap different-color piksel: `0`

Yorum:

- Mod tarafinda az miktarda piksel hicbir tarafa gitmemis olabilir.
- Buna ragmen secim mantigi genel sekilde okunabilir durumda.

### Vanillanin Kendi Icinde

- `provinces_orijinal_dogu.png + provinces_orijinal_kalan.png -> provinces_orijinal.png`
  - non-ambiguous mismatch piksel: `2821`
  - overlap same-color piksel: `0`
  - overlap different-color piksel: `0`

Yorum:

- Vanilla tarafi da kusursuz complement degil.
- Yine de genel secim yapisi okunabilir durumda.

### Final Birlesim Kontrolu

- `provinces_modlu_kalan.png + provinces_orijinal_dogu.png -> provinces_birlesim.png`
  - non-ambiguous mismatch piksel: `0`
  - overlap same-color piksel: `2`
  - overlap different-color piksel: `0`

Yorum:

- Bu bulgu cok onemli.
- `provinces_birlesim.png`, mevcut secimlerin final unionu icin su anda en guvenilir PNG referansi gibi gorunuyor.
- `2` adet same-color overlap piksel var ama farkli renkli cakisma yok.

## RGB Paylasim Ozetleri

### `provinces_modlu_kalan.png` vs `provinces_orijinal_dogu.png`

- ortak RGB toplam: `140`
- ayni RGB ve ayni ID: `21`
- ayni RGB ama farkli ID veya eksik tanim: `119`

Yorum:

- Kullanici kuralina gore `21` tanesi hata degil.
- Kalan `119` durum, final `definition_birlesim.csv` icin aktif kontrol listesi olmaya aday.

### `provinces_modlu_dogu.png` vs `provinces_orijinal_dogu.png`

- ortak RGB toplam: `161`
- ayni RGB ve ayni ID: `157`
- ayni RGB ama farkli ID veya eksik tanim: `4`

Yorum:

- Dogu secimleri birbirine geometri olarak beklenenden daha yakin olabilir.
- Ama proje hedefi vanilla doguyu almak oldugu icin bu audit bulgusu daha cok referans niteliginde.

### `provinces_modlu_kalan.png` vs `provinces_orijinal_kalan.png`

- ortak RGB toplam: `9163`
- ayni RGB ve ayni ID: `9163`
- ayni RGB ama farkli ID veya eksik tanim: `0`

Yorum:

- Kalan kisimlar buyuk oranda ortak temel province tabanini koruyor.
- Bu, batida mod ve vanilla arasinda daha buyuk uyum oldugunu gosteriyor.

## Ornek Benign Eslesmeler

- Ayni RGB ve ayni ID bulundugu halde isim/comment alani birebir ayni olmak zorunda degil.
- Bu tur durumlar kullanici kuralina gore hata degil.
- Ornekler:
  - `51,30,33` -> ID `9666`
  - `135,36,34` -> ID `9668`
  - `177,24,32` -> ID `9664`
  - `51,51,43` -> ID `9886`

Not:

- Bazi comment alanlari farkli yazilmis olabilir.
- Su an hata sinifi icin esas kriter isim degil, province kimligi.

## Ornek RGB Collision Adaylari

- `51,69,138`
  - mod ID: `9821` (`Moluag`)
  - vanilla ID: `9843` (`Lingnan_Siming_Siming`)

- `93,57,136`
  - mod ID: `9817` (`Colonsay`)
  - vanilla ID: `9838` (`Lingnan_Guishunzhou_Napo`)

- `9,30,75`
  - mod ID: `9950` (`Uvs Nuur`)
  - vanilla ID: `9936` (`Goryeo_Yanggwan_Cheongju`)

- `177,27,202`
  - mod ID: `9949` (`Khyargas Nuur`)
  - vanilla ID: `9935` (`Goryeo_Yanggwan_Jangyeon`)

- `93,36,76`
  - mod ID: `9952` (`Achit Nuur`)
  - vanilla ID: `9937` (`Goryeo_Yanggwan_Gongju`)

- `9,0,70`
  - mod ID: `9940` (`Khar-Us Nuur`)
  - vanilla ID: `9931` (`Goryeo_Yanggwan_Yeongwol`)

## Cakisma Siniflari

### Benign Overlap

- ayni RGB
- ayni ID
- hata degil

### Gercek RGB Collision

- ayni RGB
- farkli ID
- final tabloda kesin cozulmeli

### Gercek ID Collision

- farkli RGB
- ayni ID
- eger iki farkli province finalde ayni ID ile yasiyorsa cozulmeli

### Split Province

- bir province secim PNG'lerinde parcali kalmis
- final sahiplik karari gerektirir

### Missing-Pixel Gap

- dogu ve kalan ayriminda bazi pikseller her iki secimde de siyah kalmis
- composite mismatch bunun pratik gostergesi

### Name Divergence

- ayni province kimligi icin farkli comment/name metni olabilir
- dusuk oncelikli ama belgelemek faydali

## Uretim Mantigi

### Asama 1

- `provinces_modlu_kalan.png` icindeki yasayan RGB'leri al.
- Bunlari `definition_modlu.csv` icinden ayikla.
- `definition_modlu_kalan.csv` uret.

### Asama 2

- `provinces_orijinal_dogu.png` icindeki yasayan RGB'leri al.
- Bunlari `definition_orijinal.csv` icinden ayikla.
- `definition_orijinal_dogu.csv` uret.

### Asama 3

- Bu iki ara definition dosyasini karsilastir.
- Her province'i su siniflardan birine koy:
  - mod only
  - vanilla only
  - benign shared
  - rgb collision
  - id collision
  - unresolved

### Asama 4

- `definition_conflict_report.csv` benzeri bir audit cikisi uret.
- Kullanici beklentisine gore:
  - ayni RGB + farkli ID durumlari bildirilmeli
  - farkli RGB + ayni ID durumlari bildirilmeli

### Asama 5

- Kurallar yeterince netse `definition_birlesim.csv` uret.

Onemli not:

- Bu yeni yaklasimda `provinces_birlesim.png`ye dogrudan dokunma veya recolor etme karari yok.
- Bu nedenle PNG degismeden cozulmesi gereken kimlik cakismalari ayrica audit edilmelidir.

## Neden Direkt PNG'den Definition Yeniden Cikarmiyoruz

- Province geometrisi PNG'de var ama kimlik semantics'i PNG'de yok.
- Province adlari, comment alanlari ve hangi RGB'nin hangi province ID'ye ait oldugu `definition_*.csv` dosyalarinda var.
- Bu nedenle PNG tek basina yeterli degil.

## Kullanici Tarafindan Onaylanan Denetim Fikri

- `definition_(modlu/orijinal)*isim*.csv` gibi ara CSV dosyalari olusturulabilir.
- Bu dosyalar hem uretim hem de audit amacli kullanilabilir.

Olası kontrol basliklari:

- PNG'de olup ilgili alt-kume definition'da olmayan renkler
- alt-kume definition'da olup PNG'de kullanilmayan renkler
- ayni RGB + farkli ID durumlari
- farkli RGB + ayni ID durumlari
- ayni province kimligi icin farkli comment/name farklari
- split province veya parcali secim bulgulari
- beklenmeyen placeholder / bos isim / teknik satirlar

## Bu Asamada Hala Acik Kalan Kararlar

- Final ID politikasinda ne kadar "mod once" gidilecek?
- Benign shared durumda comment/name hangi kaynaktan alinacak?
- RGB collision'da recolor tarafi her zaman vanilla ithali mi olacak, yoksa duruma gore mi secilecek?
- Split province'lerde tek tarafli sahiplik mi, yoksa manuel duzeltme listesi mi olusturulacak?

## Pratik Sonuc

- Bu noktada en guclu veri modeli su:
  - final province yasam listesi icin `provinces_birlesim.png`
  - province kimlikleri icin `definition_modlu.csv` ve `definition_orijinal.csv`
  - conflict cozumleri icin ara mapping dosyalari

- Yani amac:
  - PNG'den `definition` yeniden uretmek degil
  - iki mevcut `definition` sozlugunu final secim PNG'si yardimiyla kontrollu sekilde birlestirmek

## 2026-04-11 Uygulanan Ara Uretim

Tekrarlanabilir arac:

- `tools/build_definition_subset_audit.ps1`

Bu script ile uretilen alt-kume definition dosyalari:

- `map_data/definition_modlu_dogu.csv`
- `map_data/definition_modlu_kalan.csv`
- `map_data/definition_orijinal_dogu.csv`
- `map_data/definition_orijinal_kalan.csv`

Bu script ile uretilen audit dosyalari:

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

## Alt-Kume Uretim Sonuclari

- `definition_modlu_dogu.csv`
  - image renk sayisi: `4282`
  - cekilen satir sayisi: `4282`
  - eksik definition rengi: `0`

- `definition_modlu_kalan.csv`
  - image renk sayisi: `9891`
  - cekilen satir sayisi: `9891`
  - eksik definition rengi: `0`

- `definition_orijinal_dogu.csv`
  - image renk sayisi: `3391`
  - cekilen satir sayisi: `3391`
  - eksik definition rengi: `0`

- `definition_orijinal_kalan.csv`
  - image renk sayisi: `9365`
  - cekilen satir sayisi: `9365`
  - eksik definition rengi: `0`

Yorum:

- Ara definition uretimi kapsama acisindan temiz cikti.
- Yani secim PNG'lerinde gorunen province renklerinin tumu ilgili definition sozluklerinden cekilebildi.

## RGB Inventory Guvencesi

Kullanici istegi uzerine, "alinan tum RGB'ler" artik ayri dosyalara tek tek yaziliyor.

Dosyalar:

- `definition_modlu_dogu_rgb_inventory.csv`
- `definition_modlu_kalan_rgb_inventory.csv`
- `definition_orijinal_dogu_rgb_inventory.csv`
- `definition_orijinal_kalan_rgb_inventory.csv`

Bu dosyalarin amaci:

- subset olusturulurken hangi RGB'lerin gercekten secildigini kalici kayit altina almak
- "PNG'de olan ama subset definition'a girmeyen renk var mi?" sorusunu sonradan tekrar kontrol edebilmek
- ileride merge veya ID atama asamalarinda kaynak renk listesini kaybetmemek

Her satirda en az su alanlar var:

- `subset_name`
- `source_label`
- `rgb`
- `r`
- `g`
- `b`
- `present_in_png`
- `present_in_definition`
- `source_id`
- `source_name`
- `definition_path`
- `image_path`

## Validation Rerun

Script ikinci bir guvence olarak `definition_subset_validation.csv` de uretir.

Bu dosyada her subset icin su eslesmeler tekrar kontrol edilir:

- PNG non-black unique renk sayisi
- cekilen definition satir sayisi
- yazilan RGB inventory satir sayisi
- missing colors in definition
- validation pass sonucu

Guncel sonuc:

- `modlu_dogu` -> `True`
- `modlu_kalan` -> `True`
- `orijinal_dogu` -> `True`
- `orijinal_kalan` -> `True`

Yorum:

- Bu tekrar kontrol, subset cikarma adiminin ic tutarliligini kuvvetle destekliyor.
- Yani secim PNG'sinden alinan renkler, yazilan RGB inventory ve cekilen definition satirlari sayisal olarak birebir tutuyor.

## Uretilen Audit Sonuclari

- benign shared (`same RGB + same ID`): `21`
- same RGB + same ID ama name/comment farkli: `15`
- RGB conflict (`same RGB + different ID`): `119`
- ID conflict (`different RGB + same ID`): `634`
- quality flags: `188`
- merge inventory satir sayisi: `13282`
- id tracking satir sayisi: `13282`

Yorum:

- Beklenenden daha onemli sorun su an ID conflict hacmi gibi gorunuyor.
- `119` RGB conflict kritik ama `634` ID conflict daha buyuk bir asama aciyor.
- Bu nedenle final `definition_birlesim.csv`ye gecmeden once conflict cozum politikasi yazili hale gelmeli.

## ID Tracking Dosyasinin Rolu

- `analysis/generated/definition_id_tracking.csv`
  - gelecekte atanacak yeni ID'lerin ana takip tablosu
  - `final_new_id` alani su an bilerek bos
  - final merge politikasi sonrasi doldurulacak

Pratik kural:

- yeni ID atamasi once bu dosyaya yazilmali
- daha sonra province ID referansi iceren oyun dosyalari guncellenmeli
- boylece downstream duzenlemelerde source_id -> final_new_id eslemesi kaybolmaz

## RGB Conflict Decision Scaffold

2026-04-11 itibariyla `119` adet `same RGB + different ID` vakasi icin karar asamasini destekleyen yeni bir dosya uretilmistir:

- `analysis/generated/definition_rgb_conflict_decisions.csv`

Bu dosyanin amaci:

- her RGB conflict icin modlu/orijinal taraf bilgilerini tek satirda toplamak
- daha sonra hangi tarafin mevcut RGB'yi koruyacagini ve hangi tarafin yeni RGB alacagini isleyebilmek
- final `provinces_birlesim.png` recolor asamasi ile `definition_birlesim.csv` olusumunu ayni karar tablosuna baglamak

Bu dosyada bulunan yardimci alanlar:

- `modlu_pixel_count`
- `modlu_bbox`
- `modlu_preview_path`
- `orijinal_pixel_count`
- `orijinal_bbox`
- `orijinal_preview_path`
- `suggest_keep_original_rgb_source`
- `suggest_recolor_source`
- `suggestion_reason`
- `suggest_new_rgb`
- `suggest_new_rgb_reason`
- `keep_original_rgb_source`
- `recolor_source`
- `new_rgb`
- `final_modlu_id`
- `final_orijinal_id`
- `decision_notes`

Bu yeni asamada netlesen kural:

- `119` RGB conflict icin, iki province de ayri yasayacaksa mevcut RGB yalnizca bir tarafta kalacak
- diger tarafa yeni RGB atanacak
- bu karar yalnizca `definition` seviyesinde birakilmayacak; daha sonra `provinces_birlesim.png` recolor asamasina da tasinacak

Ek yardimci ciktı:

- `analysis/generated/rgb_conflict_previews/`
  - her conflict icin iki preview dosyasi uretir:
    - modlu preview
    - orijinal preview
  - toplam preview sayisi: `238`

Heuristic yardim:

- `suggest_recolor_source` ve `suggest_keep_original_rgb_source` alanlari otomatik doldurulur
- bu alanlar politik karar degil, yalnizca yardimci oneridir
- mevcut heuristic:
  - daha az piksel kaplayan tarafi recolor etmek genelde daha ucuz olabilir
- ayni zamanda her satir icin:
  - modlu+orijinal definition renk uzayinda bos olan bir `suggest_new_rgb` da onerilir
- guncel dagilim:
  - `suggest_recolor_source = modlu`: `105`
  - `suggest_recolor_source = orijinal`: `14`

## Draft RGB Mapping

Heuristic sonucunu uygulamaya yakin bir taslak olarak gostermek icin su dosya da uretilmistir:

- `analysis/generated/rgb_mapping_draft.csv`

Ozellikleri:

- satir sayisi: `119`
- her satir bir RGB conflict vakasinin draft recolor eslemesini verir
- alanlar:
  - `shared_old_rgb`
  - `keep_original_rgb_source`
  - `recolor_source`
  - `affected_subset`
  - `affected_source_id`
  - `affected_source_name`
  - `affected_preview_path`
  - `suggested_new_rgb`
  - `basis`
  - `basis_reason`

Onemli not:

- bu dosya final karar degildir
- yalnizca review edilebilir heuristic draft mapping katmanidir

## Selective RGB Apply Verification

Draft recolor mapping'in gercekten piksel seviyesinde uygulanabildigini gostermek icin su script ve ciktılar uretilmistir:

- `tools/apply_selective_rgb_mapping.ps1`
- `analysis/generated/provinces_birlesim_rgb_draft.png`
- `analysis/generated/rgb_mapping_apply_report.csv`
- `analysis/generated/rgb_mapping_apply_summary.md`

Bu asamanin teknik onemi:

- recolor global degil, subset-mask bazli secici uygulanir
- `modlu_kalan` veya `orijinal_dogu` tarafindan hangisi recolor edilmisse yalnizca o taraf etkilenir
- orijinal `provinces_birlesim.png` degismeden test cikti alinir

Guncel dogrulama:

- mapping row count: `119`
- fully applied rows: `119`
- total changed pixels: `24443`
- total base mismatch pixels: `0`

Yorum:

- heuristic draft mapping teknik olarak uygulanabilir durumda
- RGB collision cozumunu gercek piksel verisi uzerinde yurutecek pipeline artik var

## RGB Resolved Definition Layer

RGB kararlarini `definition` tarafina yansitmak icin su script ve ciktılar uretilmistir:

- `tools/build_rgb_resolved_candidates.ps1`
- `analysis/generated/definition_rgb_resolved_inventory.csv`
- `analysis/generated/definition_rgb_resolved_candidates_pre_id.csv`
- `analysis/generated/definition_rgb_resolved_summary.md`

Bu asamanin amaci:

- merge inventory uzerindeki her satira `effective_rgb` islemek
- `recolor_to_new_rgb` ve `keep_original_shared_rgb` durumlarini ayri gostermek
- `benign_shared` satirlari final ID oncesi tek candidate satira dusurmek

Guncel sayilar:

- resolved inventory rows: `13282`
- candidate rows pre-ID: `13261`
- recolored rows: `119`
- keep-original-shared-rgb rows: `119`
- benign-shared rows in inventory: `42`
- benign-shared merged candidates: `21`

## Pre-ID Strategy Quantification

ID politikasina gecmeden once mevcut aday setin ID manzarasini olcmek icin su script ve ciktılar uretilmistir:

- `tools/analyze_pre_id_strategy.ps1`
- `analysis/generated/current_id_candidate_inventory.csv`
- `analysis/generated/id_duplicates_pre_id.csv`
- `analysis/generated/id_gap_ranges_pre_id.csv`
- `analysis/generated/id_strategy_pre_id_summary.md`

Bu asamanin amaci:

- duplicate ID gruplarini olcmek
- bos ID araliklarini range bazli cikarmak
- placeholder vs yeniden numaralandirma tartismasini sayisal veriye oturtmak

Guncel sayilar:

- candidate row count: `13261`
- unique current ID count: `12627`
- max current ID: `14696`
- duplicate current ID groups: `634`
- duplicate current ID rows: `1268`
- new IDs needed if one row per duplicate group keeps its old ID: `634`
- missing ID count in `1..14696`: `2069`
- gap range count: `135`
- placeholder load if unique IDs are preserved and continuity is forced: `2069`

Yorum:

- RGB tarafi artik kontrollu bir pipeline'a baglandi
- bundan sonraki ana stratejik karar, `ID` tarafinda
  - fazla placeholder yukunu kabul edip eski unique ID'leri daha cok korumak mi
  - yoksa daha genis yeniden numaralandirmaya gitmek mi

## Two Draft ID Policies

Bu stratejik karari somutlastirmak icin su script ve ciktılar uretilmistir:

- `tools/build_id_policy_drafts.ps1`
- `analysis/generated/id_policy_preserve_old_assignments.csv`
- `analysis/generated/id_policy_preserve_old_placeholders.csv`
- `analysis/generated/id_map_modlu_preserve_old.csv`
- `analysis/generated/id_map_orijinal_preserve_old.csv`
- `analysis/generated/id_policy_full_renumber_assignments.csv`
- `analysis/generated/id_map_modlu_full_renumber.csv`
- `analysis/generated/id_map_orijinal_full_renumber.csv`
- `analysis/generated/id_policy_source_burden.csv`
- `analysis/generated/id_policy_drafts_summary.md`

Policy A: `preserve_old_ids`

- hedef: mevcut ID'leri olabildigince korumak
- duplicate ID gruplarinda draft tie-break:
  - `modlu_kalan` once
  - sonra deterministik lexical siralama
- guncel sonuc:
  - keep current ID: `12627`
  - new ID: `634`
  - duplicate rows moved into existing gaps: `634`
  - append after max old ID: `0`
  - placeholder rows still needed: `1435`
  - final max ID: `14696`
  - changed `modlu_kalan` rows: `0`
  - changed `orijinal_dogu` rows: `634`

Policy B: `full_renumber`

- hedef: gercek province satirlari icin yogun ve placeholder'siz contiguous final ID uzayi
- ordering:
  - `current_id` ascending
  - sonra preferred source subset priority
  - sonra deterministik lexical siralama
- guncel sonuc:
  - keep current ID by coincidence: `615`
  - changed ID: `12646`
  - placeholder rows: `0`
  - final max ID: `13261`
  - changed `modlu_kalan` rows: `9508`
  - changed `orijinal_dogu` rows: `3138`

Yorum:

- `preserve_old_ids` draft pratikte degisim yukunu orijinal/east tarafina iter
- `full_renumber` draft placeholder sorununu bitirir ama iki kaynagi da agir yeniden numaralandirir

## Draft Definition CSV Outputs

ID draft'lerinin gercek `definition.csv` taslagina donebildigini gostermek icin su script ve ciktılar uretilmistir:

- `tools/build_definition_csv_drafts.ps1`
- `analysis/generated/definition_policy_preserve_old_draft.csv`
- `analysis/generated/definition_policy_full_renumber_draft.csv`
- `analysis/generated/definition_policy_draft_validation.csv`
- `analysis/generated/definition_policy_drafts_summary.md`

Validation:

- `preserve_old_ids`
  - data rows: `14696`
  - placeholders: `1435`
  - duplicate RGB: `0`
  - missing IDs: `0`
  - contiguous: `True`
- `full_renumber`
  - data rows: `13261`
  - placeholders: `0`
  - duplicate RGB: `0`
  - missing IDs: `0`
  - contiguous: `True`

Ana sonuc:

- her iki draft da teknik olarak gecerli `definition.csv` taslagi uretiyor
- yani bu noktadan sonra karar engine-gecerliliginden cok, bakim ve downstream refactor maliyetine bagli

## ID Conflict Duzeltme Notu

2026-04-11 tarihinde kullanici su duzeltmeyi netlestirdi:

- `634` adet `different RGB + same ID` conflict placeholder ile cozulmez
- bu conflict'ler icin cozum, ilgili province'lere yeni `final_new_id` vermek ve eski `id/rgb/source` bilgisini tam kayit altina almaktir
- placeholder province fikri, varsa ancak ayri bir ardissiklik veya teknik map duzeni konusu olarak dusunulmelidir; `ID conflict` cozumunun kendisi degildir

## Repo Impact Karsilastirmasi

ID politikalari teknik olarak gecerli olduktan sonra, hangi politikanin mevcut mod reposunda daha az downstream edit gerektirdigini olcmek icin ek bir analiz asamasi kuruldu.

Bu is icin olusturulan script:

- `tools/build_id_policy_repo_impact.ps1`

Scriptin amaci:

- mevcut mod reposundaki aktif province ID referanslarini taramak
- `preserve_old_ids` ile `full_renumber` politikalari altinda hangi referanslarin degisecegini saymak
- karar verirken yalnizca `definition.csv` gecerliligine degil, fiili refactor maliyetine de bakmak

Scriptin olusturulma nedeni:

- onceki asamada her iki draft'in da teknik olarak gecerli `definition.csv` uretebildigi kanitlandi
- bundan sonra asil stratejik soru, bu iki draft'ten hangisinin repo genelinde daha az duzenleme gerektirecegiydi

Script gelistirme notu:

- ilk parser hatasi `Sort-Object` coklu property yazimindan geldi; PowerShell uyumlu hashtable-property siralamaya cevrildi
- ikinci hata tek satirli dosyalarda `Get-Content`'in string donmesi nedeniyle `.Count` kullanimi patlamasi idi; line okumalar `@(...)` ile normalize edildi

Uretilen dosyalar:

- `analysis/generated/id_policy_repo_impact_by_context.csv`
- `analysis/generated/id_policy_repo_impact_by_file.csv`
- `analysis/generated/id_policy_repo_impact_summary.md`

Bu dosyalarin rolleri:

- `id_policy_repo_impact_by_context.csv`
  - baglam bazli etkiyi verir
  - ornek baglamlar: `common_landed_titles_province`, `history_provinces_block_header`, `adjacencies_from/to/through`, `default_map_*`, `map_data_geographical_regions_provinces_block`
- `id_policy_repo_impact_by_file.csv`
  - dosya bazli etkiyi verir
  - en pahali dosyalarin onceden gorulmesini saglar
- `id_policy_repo_impact_summary.md`
  - sonucu hizli okuma ve tartisma ozeti olarak uretildi

Tarama kapsami:

- `history/provinces` province block header ID'leri
- `history/province_mapping` sol ve sag numeric mapping satirlari
- `common/landed_titles` aktif `province = <id>` satirlari
- `common/situation` aktif `capital_province = <id>` satirlari
- `history/titles` aktif `capital = <id>` satirlari
- `map_data/adjacencies.csv`
- `map_data/default.map` icindeki aktif `LIST {}` ve `RANGE {}` satirlari
- `map_data/island_region.txt`, `map_data/geographical_regions/*.txt`, `common/connection_arrows/*.txt` icindeki aktif `provinces = {}` bloklari

Yorum siniri:

- bu repo impact analizi mevcut mod reposundaki bugunku aktif referanslari tarar
- dolayisiyla mod tarafinin mevcut ID uzayina dokunma maliyetini olcer
- orijinal/vanilla dogudan gelecekte tasinacak yeni referanslar bu raporda dogal olarak yer almaz

Sonuc:

- `preserve_old_ids`
  - changed references: `0`
  - touched lines: `0`
- `full_renumber`
  - changed references: `19499`
  - touched lines: `18206`

En pahali context'ler (`full_renumber` altinda):

- `common_landed_titles_province`: `8327` touched line
- `history_provinces_block_header`: `7897` touched line
- `common_connection_arrows_provinces_block`: `486` touched line
- `history_province_mapping_right`: `360` touched line
- `history_province_mapping_left`: `360` touched line
- `adjacencies_through`: `202` touched line
- `adjacencies_to`: `180` touched line
- `adjacencies_from`: `180` touched line

En pahali dosyalar (`full_renumber` altinda):

- `common/landed_titles/00_landed_titles.txt`: `8327` touched line
- `history/provinces/00_MB_PROVINCES.txt`: `7897` touched line
- `history/province_mapping/00_guinea.txt`: `600` touched line
- `map_data/adjacencies.csv`: `562` touched line
- `common/connection_arrows/silk_road_arrows.txt`: `486` touched line
- `map_data/default.map`: `170` touched line

Plan uzerindeki etkisi:

- mevcut mod reposu icin bakim maliyeti acisindan `preserve_old_ids` cok guclu sekilde one cikti
- bu politika, mod tarafindaki mevcut province referansli dosyalari korur; degisim yuku agirlikla ithal edilen `orijinal_dogu` tarafina ve tracking tablolarina kayar
- bu nedenle bir sonraki mantikli uygulama asamasi, `preserve_old_ids` politikasini ana yol kabul edip final master/tracking tablolarini bu politika etrafinda kurmaktir

## Preserve-Old Final Tracking Katmani

Repo impact sonucu `preserve_old_ids`'i pratik ana yol olarak one cikarinca, assignment csv'lerinden tek merkezli bir final tracking/master katmani uretildi.

Bu is icin yazilan script:

- `tools/build_policy_master_tracking.ps1`

Scriptin amaci:

- secilen ID policy assignment ciktisini final master tabloya cevirmek
- modlu ve orijinal kaynaklar icin ayri tracking csv'leri olusturmak
- eski `id/rgb/name/source` bilgisini final `new_id/rgb/name` ile kayipsiz baglamak
- placeholder satirlarini ayri inventory olarak saklamak

Scriptin olusturulma nedeni:

- sonraki asamalarda province referansli oyun dosyalarini guncellerken tek tek ara raporlar yerine tek bir authoritative tracking katmani kullanmak
- kullanicinin ozellikle istedigi eski `id`, eski `rgb`, hangi kaynaktan geldigi bilgisini kalici hale getirmek

Gelistirme notu:

- ilk surum yalnizca `id_policy_preserve_old_assignments.csv` dosyasini okudugu icin placeholder satirlarini atliyordu
- `preserve_old_ids` politikasinda placeholder satirlari ayri dosyadaydi: `id_policy_preserve_old_placeholders.csv`
- bu hata fark edilip script guncellendi; placeholder input'u da eklenerek tracking ciktisi tekrar uretildi
- dogru final toplam:
  - master rows: `14696`
  - placeholder rows: `1435`

Uretilen dosyalar:

- `analysis/generated/final_master_preserve_old_ids.csv`
- `analysis/generated/final_modlu_tracking_preserve_old_ids.csv`
- `analysis/generated/final_orijinal_tracking_preserve_old_ids.csv`
- `analysis/generated/final_placeholder_inventory_preserve_old_ids.csv`
- `analysis/generated/final_tracking_summary_preserve_old_ids.md`

Bu dosyalarin rolleri:

- `final_master_preserve_old_ids.csv`
  - `final_new_id` bazli ana tablo
  - her final satir icin eski modlu/orijinal kimlik ve effective RGB/isim bilgisini birlikte tutar
- `final_modlu_tracking_preserve_old_ids.csv`
  - modlu kaynagi icin authoritative `old_id -> final_new_id` ve `old_rgb -> final_rgb` haritasi
- `final_orijinal_tracking_preserve_old_ids.csv`
  - orijinal/dogu kaynagi icin authoritative `old_id -> final_new_id` ve `old_rgb -> final_rgb` haritasi
- `final_placeholder_inventory_preserve_old_ids.csv`
  - ardissiklik icin gereken placeholder satirlarini ayri verir
- `final_tracking_summary_preserve_old_ids.md`
  - sayisal ozeti okunabilir markdown formatinda verir

Guncel sonuc (`preserve_old_ids`):

- master rows: `14696`
- real candidate rows: `13261`
- placeholder rows: `1435`
- modlu tracking rows: `9891`
- orijinal tracking rows: `3391`
- modlu rows with changed final ID: `0`
- orijinal rows with changed final ID: `634`
- modlu rows with changed final RGB: `105`
- orijinal rows with changed final RGB: `14`

Real row source split:

- `both`: `21`
- `modlu`: `9870`
- `orijinal`: `3370`

Real row primary status split:

- `benign_shared`: `21`
- `id_conflict`: `1033`
- `mod_only`: `9234`
- `orijinal_only`: `2735`
- `rgb_conflict`: `238`

Plan uzerindeki etkisi:

- `preserve_old_ids` artik yalnizca bir draft fikir degil; provenance'i tam izlenen uygulanabilir ana yol haline geldi
- mod tarafinda ID degisikligi `0` oldugu icin mevcut mod repo referanslari korunuyor
- orijinal/dogu tarafindaki `634` yeni final ID tracking tablosu icinde artik net kayitli
- bir sonraki mantikli uygulama asamasi, bu master tabloyu baz alip final `provinces_birlesim.png` ve `definition_birlesim.csv` ciftini authoritative hale getirmektir

## Final Preserve-Old Staging Uygulamasi

Kullanici tarafindan kabul edilen plan, staging seviyesinde fiilen uygulandi. Ama bu uygulama canli mod dosyalarina yazilmadi; tum ciktilar `analysis/generated/` altinda tutuldu.

Bu is icin yazilan script:

- `tools/build_final_preserve_old_staging.ps1`

Scriptin amaci:

- mevcut RGB draft kararlarini authoritative final staging mapping'e cevirmek
- `provinces_birlesim.png` uzerinde selective RGB recolor'u uygulamak
- placeholder province'leri sag alt teknik bolgede `1 pixel` grid olarak boyamak
- final staging `definition.csv` uretmek
- placeholder ID'leri icin `default.map` teknik blok taslagi olusturmak
- overpaint ve legacy-unused raporlarini cikarmak
- tum staging seti icin validation markdown ozeti vermek

Scriptin olusturulma nedeni:

- daha once ayri scriptler ve ara csv'ler ile parcali ilerleyen pipeline'i tek seferde tekrar uretilebilir staging hatti yapmak
- canli `map_data` dosyalarina gecmeden once tam bir final taslak set elde etmek

Gelistirme notlari:

- `Sort-Object` coklu-property yazimi parser hatasi verdi; hashtable tabanli siralamaya cevrildi
- `Add-Type` icinde `nameof` kullanimi ortam derleyicisi tarafindan desteklenmedi; klasik string arguman ile degistirildi
- consecutive-run helper PowerShell tip uyumsuzlugu verdi; `ToArray()` ile duzeltildi
- `default.map` staging blok format string'lerinde literal `{}` escape hatasi vardi; brace escaping yapildi
- validation markdown icindeki kucuk bicim kusuru ve final RGB mapping notlarindaki eski `draft only` izi sonradan temizlendi

Uretilen dosyalar:

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

Bu dosyalarin rolleri:

- `rgb_mapping_final_preserve_old.csv`
  - authoritative final staging RGB mapping
- `provinces_birlesim_rgb_only_preserve_old.png`
  - placeholder oncesi, sadece RGB conflict'leri cozulmus ara PNG
- `rgb_mapping_final_apply_report_preserve_old.csv`
  - recolor uygulamasinin satir bazli piksel raporu
- `rgb_mapping_final_apply_summary_preserve_old.md`
  - recolor uygulama ozeti
- `provinces_birlesim_final_preserve_old.png`
  - RGB recolor + placeholder grid tamamlanmis final staging PNG
- `placeholder_pixel_map_preserve_old.csv`
  - her placeholder final ID'sinin koordinat kaydi
- `placeholder_overpaint_report_preserve_old.csv`
  - placeholder'larin hangi mevcut province renginin ustune yazdigini gosteren rapor
- `legacy_unused_after_placeholder_overpaint_preserve_old.csv`
  - final definition'da kalip PNG'de hic pikseli olmayan satirlarin raporu
- `definition_birlesim_final_preserve_old.csv`
  - final staging definition
- `default_map_placeholder_block_preserve_old.txt`
  - placeholder ID'leri icin yorumlu teknik `impassable_mountains` blok taslagi
- `final_staging_validation_preserve_old.md`
  - tum staging setinin teknik dogrulama ozeti

Uygulanan placeholder kuralinin somut sonucu:

- anchor base RGB before placeholder overlay: `126,186,199`
- bu renk `sea_indian_ocean` satirina (`final_new_id = 12763`) ait
- placeholder boyamasi tam kullanicinin tarif ettigi gibi en sag alttan baslayarak sola dogru ve satir bitince yukariya cikacak sekilde yapildi
- grid olcusu: `38 x 38`
- toplam placeholder pikseli: `1435`

Overpaint sonucu:

- butun placeholder boyamasi yalnizca `126,186,199` ustune geldi
- overwritten pixel count: `1435`
- baska hicbir province rengi teknik alan tarafindan ezilmedi

Onemli sonuc:

- `legacy_unused_after_placeholder_overpaint` satir sayisi `0`
- yani `sea_indian_ocean` alani teknik placeholder zemini olarak kullanilsa da, bu renk haritada tamamen yok olmadi; baska piksellerde varligini surduruyor

Validation sonucu:

- contiguous final definition IDs: `True`
- duplicate RGB count in final definition: `0`
- placeholder pixel count matches inventory: `True`
- placeholder coordinates unique: `True`
- placeholder ID set matches inventory: `True`
- `default.map` placeholder block ID set matches inventory: `True`
- modlu changed ID count: `0`
- orijinal changed ID count: `634`
- modlu changed RGB count: `105`
- orijinal changed RGB count: `14`
- final non-black image color count: `14696`
- final definition color count: `14696`

Plan uzerindeki etkisi:

- `preserve_old_ids` artik yalnizca teorik degil; tum staging ciktilari uretilmis uygulanmis yol haline geldi
- province PNG, definition, placeholder koordinatlari ve `default.map` teknik blok taslagi birbirine bagli halde hazir
- sonraki mantikli uygulama asamasi, bu staging setini gercek `map_data/provinces.png`, `map_data/definition.csv` ve `map_data/default.map` dosyalarina kontrollu bicimde terfi ettirmektir

## Canli Map_Data Promotion Sonucu

Staging set daha sonra canli `map_data` hedef dosyalarina terfi edildi.

Canli yapilan degisiklikler:

- `analysis/generated/provinces_birlesim_final_preserve_old.png` -> `map_data/provinces.png`
- `analysis/generated/definition_birlesim_final_preserve_old.csv` -> `map_data/definition.csv`
- `map_data/default.map` icine teknik placeholder blogu eklendi

Bu promotion'in nedeni:

- `default.map` aktif olarak `definitions = "definition.csv"` ve `provinces = "provinces.png"` bekliyordu
- ama promotion oncesi `map_data` klasorunde bu iki dosya yoktu
- dolayisiyla staging ciktilarinin canli hedef adlara alinmasi gerekiyordu

Canli `default.map` promotion mantigi:

- staging placeholder blogu oldugu gibi eklenmedi
- once placeholder inventory ile mevcut `default.map` numeric icerigi karsilastirildi
- `1435` placeholder ID'sinin `118` tanesinin zaten mevcut `impassable_mountains` bolumlerinde bulundugu goruldu
- bu nedenle canli `default.map` icine sadece eksik `1317` ID eklendi
- bu amacla ek yardimci dosya olusturuldu:
  - `analysis/generated/default_map_placeholder_block_missing_only_preserve_old.txt`

Bu yardimci dosyanin rolu:

- canli `default.map`e girecek filtrelenmis teknik placeholder blogunu saklamak
- mevcut duplicate impassable ID'leri tekrar eklememek

Canli `default.map`te blok yeri:

- mevcut `impassable_mountains` bolumunun sonunda
- `#Old Steppe. Re use these` satirlarindan sonra
- `sea_zones` satirlarina gecilmeden hemen once

Canli promotion dogrulamasi:

- `map_data/provinces.png` mevcut: `True`
- `map_data/definition.csv` mevcut: `True`
- `map_data/default.map` icinde `TECH PLACEHOLDER PROVINCES` blogu bulundu: `True`
- staging/canli hash eslesmesi:
  - `provinces.png`: `True`
  - `definition.csv`: `True`

Plan uzerindeki etkisi:

- province haritasi ve definition tarafi artik staging degil, canli hedef dosyalara yerlesti
- placeholder ID'leri de canli `default.map` tarafinda temsil ediliyor
- bundan sonraki mantikli asama, oyun/log seviyesinde smoke test ve sonra province ID referansli diger dosyalari tracking csv'lere gore guncellemek

## Definition Name Encoding Duzeltmesi

Canli `map_data/definition.csv` icinde kullanici tarafindan bildirilen bozuk gorunen isimler icin ayri bir encoding analizi yapildi.

Bulgu:

- temiz kaynak dosyalar olan `definition_modlu.csv` ve `definition_orijinal.csv` isimleri dogru UTF-8 tutuyor
- canli `map_data/definition.csv` dosyasi da bayt duzeyinde dogru UTF-8 icerige sahip
- ancak PowerShell varsayilan okuma davranisi ayni dosyayi bazen mojibake olarak gosterebiliyor
- ayni satirlar `-Encoding utf8` ile okununca dogru gorunuyor

Bu nedenle:

- canli `definition.csv` icin gercek isim bozulmasindan cok, okuma/gosterim encoding farki soz konusuydu
- fakat generated staging definition kopyasinda gercekten mojibake kalan isimler vardi

Bu is icin yazilan script:

- `tools/repair_definition_names_from_sources.ps1`

Scriptin amaci:

- final master tracking tablosunu kullanarak her final ID icin dogru kaynak ismi bulmak
- temiz UTF-8 source definition dosyalarindan isimleri yeniden almak
- hedef definition dosyalarinda yalnizca isim sutununu duzeltmek

Uretilen dosyalar:

- `analysis/generated/definition_name_repair_report.csv`
- `analysis/generated/definition_name_repair_summary.md`

Guncel sonuc:

- `map_data/definition.csv` changed names: `0`
  - aciklama: dosya zaten dogru UTF-8 idi; bozuk gorunum varsayilan yanlis okumadan kaynaklaniyordu
- `analysis/generated/definition_birlesim_final_preserve_old.csv` changed names: `98`
  - generated staging copy icindeki mojibake isimler onarildi

Onemli yorum:

- ileride `definition.csv` kontrol edilirken UTF-8 okuyucu ile bakilmasi gerekir
- aksi halde isimler dosyada dogru olsa bile terminal araci tarafinda bozukmus gibi gorunebilir
## Works Temizlik Sonrasi Konum Notu

Canli promotion ve isim/encoding duzeltmelerinden sonra repo temizligi yapildi.

Bu temizlikte:

- `analysis/generated/*` ciktilari `Works/analysis/generated/` altina tasindi
- development source `definition_*.csv` ve `provinces_*.png` dosyalari `Works/map_data_sources/` altina tasindi

Bu nedenle bu plan dosyasinda daha once gecen eski yollar su sekilde yorumlanmali:

- `analysis/generated/...` -> guncel fiziksel konum cogunlukla `Works/analysis/generated/...`
- `map_data/definition_modlu*.csv`, `map_data/definition_orijinal*.csv`, `map_data/provinces_*` -> guncel fiziksel konum `Works/map_data_sources/...`

Temizlikten sonra canli authoritative province merge seti:

- `map_data/provinces.png`
- `map_data/definition.csv`
- `map_data/default.map`

Temizlik asamasinin amaci:

- canli CK3 map_data hedeflerini ara audit/staging dosyalarindan ayirmak
- bundan sonraki downstream province referans guncellemelerinde yalnizca canli seti hedeflemeyi kolaylastirmak
