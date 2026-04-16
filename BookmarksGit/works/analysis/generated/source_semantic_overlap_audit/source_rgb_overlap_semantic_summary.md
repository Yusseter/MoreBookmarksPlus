# Source Semantic RGB Overlap Audit

Toplam ortak RGB satiri: 140
- same RGB + same ID: 21
- same RGB + different ID: 119
- same RGB + same ID + different name: 15

Semantic suggestion sayilari:
- Review: 77
- False: 57
- True: 6

Semantic classification sayilari:
- unclassified_review: 76
- barony_vs_nonbarony: 54
- same_id_same_name_nonbarony_nonland: 5
- different_barony: 2
- different_default_map_class: 1
- same_barony: 1
- same_noncounty_default_class_review: 1

Otomatik karar verilebilen satir: 63
Manual review kalan satir: 77

Notlar:
- Mod source semantic verisi 0backup klasorunden okundu.
- Orijinal source semantic verisi vanilla game default.map ve landed_titles uzerinden okundu.
- Bu tur sadece audit/karar destegi uretir; canli map_data veya landed_titles dosyalarina dokunmaz.
- semantic_same_province_suggest = True sadece ayni barony kaniti varsa verilir; diger pek cok durum bilincli olarak Review kalir.
