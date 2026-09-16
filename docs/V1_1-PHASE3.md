# Zenithium 1.1 — Açıklanabilir kararlar ve yayın doğrulaması

Bu sürüm, bir önceki günle toparlanma farkını ölçüm katkılarına ayırır; aynı karar yolunu telefon, widget ve saate bağlar. Tahlil ve ayarlar fazlarının üzerine kuruludur. Sürüm `1.1`, derleme `10`, hesap sürümü `2`.

## Değişen davranış

- **Skor farkı:** Dünün ham ölçümleri bugünkü tabanla tekrar hesaplanır. Ağırlıklı z-skor değişimleri toplamın puan ölçeğine dönüşüm katsayısıyla ayrıştırılır; kalan fark taban/hesap değişimi olarak gösterilir. Katkıların toplamı kayıtlı puan farkına eşittir. Eksik sürücü ve ağırlık değişimi açıklanır. Matematiksel ayrıştırma nedensellik kanıtı değildir.
- **Gerçek zaman çizgisi:** Hipnogram özgün Sağlık evrelerini ve saatlerini gösterir. Ölçüm olmayan günler çizgiyle birleştirilmez veya sıfır yükle doldurulmaz. Yük hesabına günlük zorlanma puanı yerine kaydedilmiş TRIMP girer. Yük oranı için 28 ardışık kayıt günü ve en az 8 etkin gün gerekir.
- **Bağlam:** Hastalık, seyahat, rakım ve vardiya başlangıç/bitiş tarihleriyle kaydedilir. Hastalık yük artışını durdurur; diğer koşullar artış önerisini sınırlar. Ham ölçüm ve toparlanma puanı değiştirilmez. Reçete, ana ekran ve widget aynı kararı kullanır. Kalan bütçe doğrusal olmayan zorlanma ölçeğinde çıkarılmaz; TRIMP alanında hesaplanır.
- **Kuvvet:** Egzersiz başına gün tarihli hacim ve tahmini tek tekrar maksimumu. Eksik ağırlıkta hacim uydurulmaz; ilerleme grafiğinin maksimum tahmini 1–10 tekrarla sınırlıdır. Saatte çevrimdışı set kaydı ve çift dokunuş bulunur.
- **Hedef:** Yarış mesafesi/süresi, geri sayım ve kişisel geçmişten türetilen haftalık yük senaryosu. Kritik hız karşılaştırması yeterli efor ve sınırlı dışdeğerleme gerektirir. Ulaşılabilirlik olasılığı veya zorunlu/güvenli yük olduğu iddia edilmez. Etkin kişisel bağlamda haftalık artış senaryosu gösterilmez.
- **Saat:** App Group'un cihazlar arasında dosya paylaşmadığı dikkate alınarak WatchConnectivity aktarımı eklendi. Kayıt, telefon kalıcı depoya yazıp kimliği onaylayana kadar saatte tutulur. Yeniden gönderilen set çoğalmaz; eski günlük mesajı daha yeni tercihi geri alamaz. Silme sınırı çevrimdışı saate sonraki bağlantıda uygulanır. Yeni watchOS widget uzantısı komplikasyon ve Smart Stack görünümü sağlar. Önceki günün özeti yeni günün önerisi olarak sunulmaz.
- **Tasarım:** iOS 26'da profil kontrolünde sistem cam malzemesi, iOS 18'de malzeme geri dönüşü. Ana ekrana ek kart katmanı eklenmez; fark açıklaması ayrıntılardadır. Yeni ekranlar standart ve en büyük erişilebilir yazıyla render edilir. Hareket azaltma animasyonları durdurur.

## Bilimsel sınırlar

Uzun vadeli indeks, kayıt kapsamını ve bileşenlerini gösterir; biyolojik yaş veya yaşam süresi tahmini değildir. Doğrulanmış bir belirsizlik dağılımı olmadığından güven aralığı üretilmez. Ham ölçüm eğimi, indeksin aylık puan değişimi olarak etiketlenmez. Takvimden çıkarılan döngü fazıyla SDNN veya nabız düzeltmesi günlük karar yolunda kapalıdır.

Tahlil değerleri yalnızca raporun kendi referansları ve zaman bağlamıyla değerlendirilir; doğrulanmamış sayısal ceza yoktur. Yakın tarihli atriyal fibrilasyon kaydı için HRV yorumunun 24 saat askıya alınması ürünün ihtiyat kuralıdır; bilimsel olarak doğrulanmış iyileşme süresi değildir. Ölçüm kapsamı katsayısı tahminin doğru çıkma olasılığı veya klinik güven aralığı değildir.

Foundation Models yalnızca sayısız kısa başlığı yeniden ifade edebilir. Sayı, yazıyla miktar veya birim içeren çıktı reddedilir. Sayısal gövde, kaynaklar ve karar değişmeden hesap kodundan alınır. Uygun olmayan cihazlarda hazır metinler kullanılır.

### Kaynak doğrulama notları — 16 Eylül 2026

- [Morton 1997](https://pubmed.ncbi.nlm.nih.gov/9232559/): PMID ve başlık düzeltildi. Eğitim/performans modeli toparlanma skorunun veya aşırı antrenman tanısının doğrulanması değildir.
- [Lolli ve arkadaşları](https://pubmed.ncbi.nlm.nih.gov/29101104/): PMID düzeltildi; 2017 çevrimiçi, 2019 basılı yayın. Matematiksel bağlaşımı tartışan yazı sistematik derleme olarak sınıflandırılmaz; ACWR'den sakatlık olasılığı çıkarılmaz.
- [Smarr ve arkadaşları 2020](https://www.nature.com/articles/s41598-020-78355-6): 50 kişilik, Oura parmak sıcaklığıyla yapılmış gözlemsel çalışma. Apple Watch bilek sıcaklığı için enfeksiyon eşiği veya tanı doğrulamaz. [2022 düzeltmesi](https://www.nature.com/articles/s41598-022-08621-2) kaynakta dikkate alındı.
- [Banister bölüm künyesi](https://humankinetics.com/AcuCustom/Sitename/DAM/124/Complete_References.pdf): *Physiological Testing of the High-Performance Athlete*, 403–424, ISBN 9780873223003. Yayıncı kaynakçası künye kontrolüdür; bölüm tam metni incelenmiş olarak işaretlenmez.
- [Döngü araştırması](https://pubmed.ncbi.nlm.nih.gov/39108015/) ve [farklı HRV sonuçları](https://pubmed.ncbi.nlm.nih.gov/30998226/), kanama takviminden sabit bireysel SDNN düzeltmesini desteklemez. Bu nedenle düzeltme etkinleştirilmez.
- [Apple ECG açıklaması](https://support.apple.com/en-euro/120278): Kaydın sınıflandırılması ve sınırlamaları ayrı tutulur. Düşük kaliteli tek EKG kaydı tüm gece HRV'nin geçersiz olduğunu kanıtlamaz.

Künyeler ve uygulama içindeki kanıt kartları aynı [kaynak kütüphanesinden](../Zenithium/Domain/Intelligence/EvidenceLibrary.swift) üretilir. [EVIDENCE.md](EVIDENCE.md) hesap katsayılarının dayanaklarını ve sınırlarını listeler.

## Doğrulama

16 Eylül 2026: `preflight-13` temiz. Son tam Xcode test çalıştırması (`zenithium-v11-phase3-full-06.xcresult`) başarılı: 743 Swift Testing testi / 84 grup ve 6 XCTest kontrolü, toplam **749 test**. Kayıt modu kapalıyken 21 görsel karşılaştırmanın tamamı geçti. Release arşivi başarıyla oluşturuldu (`Zenithium-v1.1-build10.xcarchive`); derleyici uyarısı veya hatası yok. Dört paketin sürümü 1.1 (10), gizlilik bildirimi ve cihaz ailesi doğrulandı: iPhone/Widget arm64, Watch/Watch Widget arm64 ve arm64_32. Foundation Models `LC_LOAD_WEAK_DYLIB` olarak bağlı; iOS 18 için zorunlu yükleme bağımlılığı değil.

TestFlight dağıtımı, GitHub'a yüklenmesi veya yerel imzasız arşivin tamamlanmasıyla doğrulanmış sayılmaz; Xcode Cloud sonucu ayrıca izlenir.

Eklenen davranış testleri: tam puan farkı muhasebesi, karşıt sürücüler, taban değişimi, eksik ölçüm kapsamı, günlük TRIMP bütçesi, bağlam başlangıç/bitişi, anlatıdaki sayısal ifadelerin reddi, yinelenen saat kaydı, sıra dışı günlük teslimi, eksik ağırlıklı egzersiz hacmi ve hedef tercihlerinin kalıcı aktarımı.

Değişen hesap modülleri: `RecoveryChangeEngine` (yeni), `TrainingLoadEngine`, `PrescriptionEngine`, `DecisionEngine`, `DataQualityEngine`, `StrengthEngine`, `LongevityEngine`; `ClinicalContextEngine` içinde gelecekteki EKG kaydının dışlanması. Kaynak tabloları koddan üretilir ve preflight ile eşitlenir.

### Ekran incelemesi

[Bugün](qa/phase3/bugun-dolu.png), [uyku](qa/phase3/uyku-dolu.png), [yük](qa/phase3/yuk-dolu.png), [puan farkı](qa/phase3/skor-farki-default.png), [bağlam](qa/phase3/baglam-default.png), [yarış hedefi](qa/phase3/yaris-hedefi-default.png), [kuvvet](qa/phase3/kuvvet-gecmisi-default.png). Yeni ayrıntı ekranlarının `ax5` eşleri aynı klasördedir. Ekranlar yalnızca sabit test verisidir; kişisel sağlık kaydı içermez.

Görsel farklar tek tek incelendi: gerçek hipnogram, eksik günlerin korunması, yük biriminin TRIMP olması, boş kas geçmişinin hazır puanı göstermemesi ve ana ekran metinleri. Yalnızca değişen 10 referans, her çalıştırmada tek test seçilerek yenilendi. Tolerans değiştirilmedi. Tanıtım sayfası masaüstü ve 390 piksel telefon genişliğinde incelendi; mobil kenar boşlukları düzeltildi.

Fiziksel iPhone–Watch eşleştirme, çevrimdışı teslim, çift dokunuş ve gerçek HealthKit izinleri bu bilgisayardaki simülatör testleriyle bütünüyle doğrulanamaz; cihaz kontrolü sınırı korunur. Yerel arşiv imzasızdır; dağıtım imzası Xcode Cloud tarafından hazırlanır.
