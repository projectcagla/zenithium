# v1.1 — Ayarlar ve kişisel veri yönetimi

Ayarlar; kullanılan profil alanlarını, kişisel tabanı, karar yaklaşımını, uyku saatini, bildirimleri ve veri yönetimini tek yerde toplar. Kullanılmayan boy/kilo alanı istenmez. Bu sürümün dili Türkçedir; işlevsiz bir dil anahtarı sunulmaz.

## Davranış

- Yaş, biyolojik cinsiyet ve isteğe bağlı maksimum nabız mevcut hesaplara bağlanır. Boş doğum tarihi varsayılan bir yaş olarak kaydedilmez.
- Sağlık erişimi Apple'ın izin ekranının durumunu gösterir. Okuma izni ayrıntılarının uygulamaya açıklanmadığı belirtilir; eksik veriden izin verildiği sonucu çıkarılmaz.
- Geçerli HRV gecesi ve 14 gecelik başlangıç ilerlemesi görünür. Tabanı yeniden başlatmak eski gün kayıtlarını silmez; yeni taban seçilen günden itibaren birikir.
- İhtiyatlı yaklaşım yüksek yük önerisi için 80, gelişim odaklı yaklaşım 67 toparlanma puanı bekler. Bunlar ürünün planlama tercihleridir; fizyolojik ölçüm veya sakatlık riski sınırı değildir. Hedef profil önerilen etkinlikleri değiştirir.
- Uyku saati tercihi ve hedef süre, yatış/kalkış planında kullanılır. Bu, kullanıcının seçtiği zamanlamadır; ölçülmüş kronotip olduğu iddia edilmez.
- Sabah hatırlatması, eksik gece kaydı ve haftalık hatırlatma ayrı anahtarlardır. Bildirimler cihazda zamanlanır. Eksik gece bildirimi ancak o günkü okuma eksikse hazırlanır; rutin hatırlatma yeni bir sağlık sonucu hazırmış gibi konuşmaz.
- Widget, Live Activity ve Watch bilgileri sistemden okunur. Saatin ulaşılabilir olması Sağlık aktarımının tamamlandığı anlamına gelmez.
- Birim tercihi sıcaklık farkını, koşu mesafesini ve tempoyu değiştirir. Hesaplar özgün birimleriyle çalışır; yarışın kilometrelik bölümleri kendi kilometre etiketlerini korur.
- Motor sabitlerinin koddan üretilen dökümü, kaynakların kanıt dereceleri ve göstermedikleri uygulamada çevrimdışı okunabilir.

## Aktarım ve silme

Tercihler ayrı, korumalı bir App Group dosyasında tutulur ve `.zenithium` arşivine eklenir. Eski arşivler bu alan olmadan da okunur. Arşivde tüm kayıt türleri ve belgelerin asılları bulunur; boyut sınırı aşılırsa eksik arşiv üretmek yerine işlem açıklamayla durur. Geçersiz sayılar, dosya yolları, eksik dosyalar ve mevcut belgeyle çelişen içerikler yazma öncesinde reddedilir. Depolama hatasında kısmi aktarım olabileceği açıklanır; aynı arşivi tekrar aktarmak kayıtları çoğaltmaz.

Geri yükleme sırasında hesaplama yazmaları durdurulur ve ardından okuma önbelleği temizlenir. Aktarım ekranından ayrılınca ekranlar yeniden kurulur. Tam silme, yerel kayıtları, tercihleri, belgeleri, uygulamanın geçici arşivlerini, bildirimleri ve paylaşılan özeti temizler. Apple Sağlık kaynakları ve kullanıcının dışarı kaydettiği kopyalar silinmez; yeniden kurulumda Sağlık verileri tekrar okunabilir.

## Doğrulama

15 Eylül 2026: preflight temiz. Son Xcode derlemesi ve bütün test paketi başarılı: 733 Swift Testing testi / 82 grup ve 5 XCTest ekran üretim kontrolü, toplam 738 test. 21 görsel karşılaştırma kayıt modu kapalıyken geçti. Sonuç paketi: `zenithium-v11-phase2-full-04.xcresult`.

Yeni testler: tercihlerin yeni depo örneğinde okunması ve sıfırlanması, geçersiz tercihin eski kaydı değiştirmemesi, ayrı bildirim planları, gece yarısını geçen uyku planı, taban sıfırlamasının eski geçmişi dışlaması, hesap sonrası önbellek yenilemesi, gerçek disk deposunun yeniden açılması ve silinmesi, arşiv/tercih aktarımının yinelenebilirliği, geçersiz dosya yolu ve karar tercihinin gerçekten eylemi değiştirmesi.

Ekran incelemesi: [ayarlar](qa/phase2/ayarlar-default.png), [en büyük erişilebilir yazı boyutu](qa/phase2/ayarlar-ax5.png). Nabız girişi dikey yerleşime alınmıştır. Bugün ekranındaki yeni karar metni ve antrenman bağlantısı incelenmiş; yalnızca ilgili görsel referans yenilenmiştir.

Değişen hesap motorları: `DecisionEngine`, `PrescriptionEngine`. Toparlanma formülüne yeni fizyolojik katsayı eklenmez. Ayar davranışları deterministiktir.

Bu aşama nihai yayın değildir. Skor ayrıştırması, eksik veri/grafik doğruluğu, kişisel bağlam, tanıtım metinleri ve son Release arşivi üçüncü aşamada tamamlanır.
