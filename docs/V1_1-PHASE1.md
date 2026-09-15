# v1.1 — Tahlil ve gezinme onarımı

Tahlil, belge, günlük, ayarlar ve veri taşıma yolları bütün antrenman profillerinde Keşfet üzerinden erişilebilir. Ana gezinme beş sekmede kalır.

## Tahlil akışı

- Dosyalar'dan PDF/görüntü, Fotoğraflar'dan görüntü veya manuel giriş.
- Metin PDF'lerinde sözcüklerin sayfadaki konumu kullanılır; metinsiz sayfalarda cihaz içi Vision OCR çalışır. Dosya boyutu ve sayfa sayısı sınırlandırılır.
- Her satır başlangıçta onaysızdır. Değer, birim, belirteç, referans veya tarih değiştiğinde onay yenilenir. Kaynak satır ve okuma güveni görünür; eşik sonuçları kesin sayı olarak kaydedilmez.
- Birim dönüşümü sonuç ve referans sınırlarına birlikte uygulanır. Eksik referans katalogdan doldurulmaz. Kaydedilmeyen satırlar açıkça gösterilir; tekrar deneme kayıtları çoğaltmaz.
- Onaylanan kaydın aslı App Group içindeki belgelerde saklanır. Tam dosya koruması kullanılır, otomatik yedeğe dahil edilmez. Eski belge klasörü taşınır; silme ve kopyalama hataları görünür olur.
- Tahlil tarihinde HRV, önceki en çok 60 günlük kişisel taban ve önceki 28 günün antrenman yükü karşılaştırılabilir. HRV için en az 14 geçerli gece, yük oranı için 28 kayıtlı gün gerekir. Eksik gün dinlenme sayılmaz; gelecekteki kayıt kullanılmaz. Görünen ilişki eşzamanlılıktır, nedensellik değildir.

## Hesaplama sınırları

`LabInsightEngine` yalnızca kayıttaki aralıkları kullanır. Kullanıcının belirttiği kişisel hedef aralığına literatür doğrulaması atfedilmez. `ClinicalContextEngine` içinde tek bir tahlilden toparlanma güvenini %10–15 azaltan doğrulanmamış katsayılar kaldırılmıştır; referans dışı sonuçlar yalnızca bağlam ve hekime yönlendirme sağlar. Eksik referans, bilinmeyen birim veya gelecek tarihli kayıttan klinik düzeltme çıkmaz.

Okunamayan EKG, optik HRV ölçümüne ceza vermez. Son 24 saatte atriyal fibrilasyon sınıflandırması bulunan EKG için antrenman kararını askıya alma bir ürün önlemidir; doğrulanmış bir etki süresi veya tanı değildir. [Apple'ın EKG açıklaması](https://support.apple.com/en-euro/120278), EKG sınıflandırmasının ve okunamayan sonuçların sınırlarını açıklar.

## Doğrulama

15 Eylül 2026: preflight başarılı. Xcode simülatör testleri kayıt modu kapalıyken başarılı: Swift Testing 726 test / 81 grup; ayrıca 4 XCTest görsel üretim kontrolü; toplam 730 test. 21 görsel referans normal karşılaştırma modunda geçti. Görseller sabit örnek tarih ve tamamlanmış örnek geçmişle üretilir; kayıt modu yalnızca açık ortam değişkeniyle açılır.

Yeni kontroller: zorunlu satır onayı, kısmi kayıt sonrası güvenli tekrar, birim ve aralık dönüşümü, eksik referans, geçersiz giriş, üç gerçek Türkçe PDF düzeni, görüntü OCR yolu, klinik bağlamda geçersiz/gelecek tarihli kayıtlar ve her mercekte zorunlu gezinme yolları. [PDF kaynakları ve beklenen değerler](../ZenithiumTests/Fixtures/Laboratory/README.md).

Görseller: [Tahlil paneli](../ZenithiumTests/__Snapshots__/tahlil-dolu.png), [boş tahlil paneli](../ZenithiumTests/__Snapshots__/tahlil-veriyok.png), diğer durumlar `ZenithiumTests/__Snapshots__` altında. Büyük yazı ve küçük ekran çıktıları yerel `.build/renders` klasöründe üretilir.

Bu aşama nihai v1.1 yayını değildir. Ayarların genişletilmesi, günlük karar/uyku/yük ekranlarındaki kalan veri akışı sorunları, tanıtım sayfası ve son Release arşivi sonraki aşamalardadır. Bu aşamanın görsel referansları bütün eski hesapların bilimsel olarak doğrulandığı anlamına gelmez.
