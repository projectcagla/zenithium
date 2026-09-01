# Teknik döküman üreteci

`docs/Zenithium-Teknik-Dokuman.pdf` bu klasörden üretilir.

## Parçalar

| Dosya | İçerik |
|---|---|
| `css.html` | Sayfa düzeni, tipografi ölçeği, palet. Gömülü fontlar `/*__FONTS__*/` yer tutucusuna enjekte edilir. |
| `cover.body.html` | Kapak sayfası |
| `b1.html` … `b11.html` | Gövde bölümleri, sırayla |
| `render.py` | Birleştirme, iki geçişli sayfa numarası çözümü, PDF çıktısı |

## Üretme

```sh
pip install playwright pypdf
python3 render.py ../Zenithium-Teknik-Dokuman.pdf
```

`render.py` önce `doc.html` ve `cover.html`'i yukarıdaki parçalardan
**birleştirir** (`assemble()`), sonra iki geçiş yapar: ilk geçişte gövdeyi
basar ve her bölüm başlığının hangi sayfaya düştüğünü çıkarılan metinden
bulur, ikinci geçişte o sayfa numaralarını içindekiler tablosuna yazar.
Ardından kapağı gövdeye ekler ve PDF yer imlerini oluşturur.

Birleştirme adımı sürüm 0.1'de eklendi. Öncesinde `doc.html` ve `cover.html`
git tarafından yok sayılıyordu ama hiçbir şey onları üretmiyordu — yani temiz
bir klonda belgenin bütün parçaları vardı ve basılmasının hiçbir yolu yoktu.

Başlık eşleşmesi iki şeye duyarlıdır:

- **Büyük/küçük harf.** Gövde başlıkları CSS ile büyük harfe çevrilirken
  içindekiler tablosu karışık harf düzeninde kalır, bu yüzden arama
  yanlışlıkla içindekiler sayfasını bulamaz.
- **Türkçe büyük harf.** Belge `lang="tr"` olduğu için Chromium `i` harfini
  `İ`'ye çevirir; Python'un `str.upper()`'ı `I`'ya çevirir. `tr_upper()` bu
  farkı kapatır. Kapatılmadığında içinde `i` geçen her başlık kendi basılmış
  hâliyle eşleşmez ve içindekiler tablosunda sayfa numarası yerine tire kalır.

Marka ve kod adları (`Zenithium`, `WatchConnectivity`, `wc`, `grep`, `git`)
`lang="en"` ile işaretlenir — Türkçe büyük harf kuralı yanlarındaki Türkçe
kelimeler için doğrudur, adın kendisi için değil.

## Sayılar nereden geliyor

Belgedeki her ölçüm depoda çalıştırılan bir komutun çıktısıdır (`wc -l`,
`grep -c`, `git log`). Bir sayı değiştiğinde ilgili bölüm dosyası elle
güncellenmelidir — otomatik bağlantı yok.
