# Zenithium — Yol Haritası v4

**Kapsam:** performans optimizasyonu, tasarımın kusursuzlaştırılması, yeni özellikler.
**Temel:** 195 üretim dosyası, 25 motor, 308 test, 40.899 satır, 4 hedef.

Bu belge genel tavsiye listesi değil. Her madde bir dosyayı ve o dosyada
ölçülen ya da gözlenen somut bir durumu gösteriyor. Denetim `grep`/`wc` ile
yapıldı; sayılar sayımdır, tahmin değil.

**Değişmeyen kurallar** (v2 sözleşmesinden, hepsi yürürlükte): Swift 6 tam
eşzamanlılık; `ObservableObject`/Combine/`DispatchQueue`/`print()`/zorla
açma yok; sıfır sunucu, sıfır hesap, sıfır ağ çağrısı, sıfır üçüncü parti
paket. §12 — Zenithium tıbbi cihaz değildir, teşhis koymaz, belirtiyi
görmezden gelmeyi önermez. §1 — kalori hedefi, kilo hedefi, kısıtlama
uyarısı hiçbir yerde yok.

---

## A — Performans

Ortak ilke: **önce ölç, sonra düzelt.** A9 maddesi diğer sekizinin önüne
geçmeli; aksi hâlde iyileştirmelerin işe yarayıp yaramadığını bilemeyiz.

### A1 — Kas haritası her karede yeniden spline üretiyor ⭐⭐
`Zenithium/Views/Muscle/MuscleMapView.swift:266, 314, 316`

`region.path(in: rect)` üç ayrı çağrı yerinde çağrılıyor: Canvas çizimi,
üstteki dokunma katmanı ve `contentShape`. Her çağrı `BodyGeometry`
üzerinden 20 örnekli quadratic Bézier omurga örneklemesi + kapalı
Catmull-Rom spline'ı sıfırdan kuruyor. 14 bölge × 3 çağrı = düzen başına
42 spline inşası. Buna ek olarak satır 259–260'ta `BodyGeometry.silhouette`
dizisinin dış çizgileri her Canvas karesinde yeniden üretiliyor.

**Çözüm:** normalize edilmiş `[BodyPoint]` dış çizgilerini `BodyGeometry`
içinde `static let` olarak bir kez üret (rect'ten bağımsızlar, sadece
ölçeklenmeleri gerekiyor). `Path`'i `(bölge, rect.size)` anahtarlı küçük
bir önbellekte tut; Canvas zaten rect'i veriyor, boyut değişmedikçe yeniden
kurma. Dokunma katmanı ile çizim katmanı aynı önbelleği paylaşsın.

**Ölçüt:** düzen başına spline inşası 42 → 0 (boyut değişmediği sürece).

### A2 — Biyobelirteç eşleştirmesi satır başına ~200 gereksiz normalizasyon ⭐⭐
`Zenithium/Domain/Labs/Biomarker.swift:1090-1094`

```swift
for definition in all {
    for synonym in definition.synonyms + [definition.displayName] {
        let needle = normalize(synonym).split(separator: " ").map(String.init)
```

`normalize(synonym)` iç döngünün içinde. 50 tanım × ortalama ~4 eşanlamlı
≈ satır başına 200 normalizasyon + 200 `split` + 200 dizi ayırma. Tipik bir
tahlil raporu ~120 satır → tek içe aktarımda ~24.000 gereksiz string işlemi.
Ayrıca `definition.synonyms + [definition.displayName]` her turda yeni bir
dizi ayırıyor.

**Çözüm:** iğneleri katalogla birlikte bir kez üret — `all`'ın yanında
`static let needles: [(definition: BiomarkerDefinition, tokens: [String])]`.
Üstüne ilk-token indeksi ekle: `[String: [Int]]` sözlüğü ile satırın
tokenlarından hangi tanımların aday olduğunu O(1) bul, tarama O(tanım
sayısı)'ndan çıkar. Eşleştirme mantığı ve öncelik sırası aynı kalır — bu
saf bir yeniden düzenleme, davranış değişikliği değil; mevcut testler
korumadır.

**Ölçüt:** satır başına normalizasyon 200 → 0, aday tanım sayısı 50 → ~1–3.

### A3 — 18 vital ardışık okunuyor ⭐
`Zenithium/ViewModels/VitalsViewModel.swift:82-92`

Döngü 18 `HKStatisticsCollectionQuery`'yi sırayla bekliyor. Koddaki yorum
bunu hata yalıtımıyla savunuyor — bir işaretin patlaması ekranın kalanını
götürmesin diye. Gerekçe doğru ama çözüm gereğinden pahalı: aynı yalıtım
`withTaskGroup` içinde her çocuğun `Result` döndürmesiyle de sağlanır.

**Çözüm:** en fazla 4 eşzamanlı görev tutan sınırlı bir görev grubu; her
çocuk kendi hatasını yakalayıp `Result` olarak döndürsün, yetki hatası
ayrımı (`healthAuthorizationDenied` / `healthDataUnavailable`) toplama
aşamasında yapılsın. Kod yorumunu da güncelle — yanlış gerekçe bırakmayalım.

**Ölçüt:** ekran açılışında HealthKit gidiş-dönüşü 18 sıralı → ~5 dalga.

### A4 — Aynı gün kayıtları bir yenilemede dört kez okunuyor ⭐⭐
`Zenithium/ViewModels/TodayViewModel.swift:240, 320, 375, 402`

Tek bir `refresh()` geçişinde `records.dayRecords(...)` dört kez, üst üste
binen pencerelerle çağrılıyor. Toplamda projede 15 çağrı yeri var
(`grep -rn "dayRecords("`), en genişleri 120 günlük.

**Çözüm:** yenileme başına tek okuma. En geniş pencereyi bir kez oku,
sonucu geçiş boyunca taşınan bir bağlam değerinde paylaş; alt hesaplar
dilimlerini bu diziden alsın. Daha ileri adım: `DailyRecalculationCoordinator`
zaten bir yeniden hesaplama akışı yayınlıyor — gün kayıtları için o akışla
geçersizleştirilen, aktörde tutulan küçük bir önbellek.

### A5 — 120 günlük okuma iki ekranda ayrı ayrı yapılıyor ⭐
`Zenithium/ViewModels/StrengthViewModel.swift:72` ve
`Zenithium/ViewModels/TrainingLoadViewModel.swift:79`

Kuvvet ekranı yalnızca yük oranını öğrenmek için 120 günlük tam bir kayıt
okuması yapıyor; yük ekranı aynı okumayı kendi için tekrarlıyor.

**Çözüm:** `TrainingLoadOutput`'u koordinatörde hesaplanıp önbelleklenen
paylaşılan bir değere yükselt. Her iki ekran da hazır sonucu okusun.
`TrainingLoadEngine` saf kalır — değişen sadece kimin çağırdığı.

### A6 — SwiftData'da izdüşüm okuması hiç kullanılmıyor
`propertiesToFetch`: 0 çağrı yeri. `fetchLimit`: 23 (bu iyi.)

`HealthDocumentLog.extractedText` `.externalStorage` ile işaretli, doğru
karar; ama liste ekranları yine tam modeli gerçekliyor.

**Çözüm:** liste ekranlarına izdüşüm getirmeleri (`propertiesToFetch`) —
belge listesi başlık/tarih/tür ile çizilir, tam metin yalnızca arama ve
detayda okunur.

### A7 — HealthKit servisinde döngü içi bekleme
`Zenithium/Health/HealthKitService.swift:156, 399`

Günlük ortalama ve uyku yollarında `await` bir döngünün içinde. A3 ile aynı
düzeltme: sınırlı görev grubu.

### A8 — Geriye dönük doldurma gün gün, her gün kendi okumasıyla
`Zenithium/Orchestration/DailyRecalculationCoordinator.swift:97-99`

`for dayStart in stale.suffix(limit)` her gün için tam bir
`recalculateDay` çalıştırıyor; her çağrı kendi mağaza okumasını yapıyor.
İlk kurulumda 60 günlük doldurma = 60 ayrı okuma dalgası.

**Çözüm:** pencereyi bir kez oku, günleri o bellek içi dizi üzerinde katla.

### A9 — Hiçbir yerde ölçüm yok ⭐⭐ (önce bu)
Projede tek bir `os_signpost` yok. "Yavaş" hissi ile ölçülmüş yavaşlık
arasındaki farkı kapatmadan A1–A8'in etkisini doğrulayamayız.

**Çözüm:** üç kritik yola imzalı aralık koy — günlük yeniden hesaplama,
tahlil ayrıştırma, kas haritası çizimi. Yanına `ZenithiumTests` içinde
deterministik bir başarım paketi: duvar saati yerine **iş sayısı** üzerinde
iddia (spline inşa sayısı, normalizasyon sayısı, mağaza okuma sayısı).
Duvar saati testi CI'da titrer; sayım testi titremez ve gerilemeyi aynı
kesinlikte yakalar.

---

## B — Tasarımı kusursuzlaştırma

Renk ve tipografi bir belirteç katmanında toplanmış (`ZenithiumColor`,
`ZenithiumFont`). Boşluk, hareket ve dokunsal geri bildirim toplanmamış.
Aradaki fark ekranda "elle yapılmış" olarak görünüyor.

### B1 — Boşluk belirteci yok; 15 farklı sabit dolaşıyor ⭐⭐
Görünüm katmanındaki `spacing:` sayımı:

| değer | kullanım | değer | kullanım |
|---|---|---|---|
| 8 | 36 | 2 | 16 |
| 12 | 35 | 14 | 16 |
| 16 | 32 | 3 | 12 |
| 10 | 26 | 1 | 9 |
| 0 | 20 | 4 | 6 |
| 6 | 16 | 5, 9, 18, 20 | 1–5 |

`ZenithiumColor` ve `ZenithiumFont` var; `ZenithiumSpacing` yok. 8/12/16
omurgası zaten kendiliğinden oluşmuş — asıl sorun 1, 3, 5, 9, 18, 20 gibi
tek seferlik değerler; ekranda hizasızlık olarak okunuyorlar.

**Çözüm:** 4pt tabanlı ölçek (`xxs 2, xs 4, s 8, m 12, l 16, xl 24, xxl 32`),
sonra göç. Göç sırasında tek seferlik değerler en yakın basamağa yuvarlanır;
yuvarlama bir düzeni bozuyorsa o düzen zaten yanlıştır.

### B2 — Grafik çerçevesi dört dosyada birebir kopyalanmış ⭐
`BloodMarkerDetailView.swift:66`, `EnduranceView.swift:195`,
`TrainingLoadView.swift:172`, `TrendChart.swift:80` — aynı
`AxisMarks(position: .leading)` + `AxisMarks(values: .automatic(desiredCount:))`
blokları.

**Çözüm:** tek bir `ZenithiumChartStyle` `ViewModifier` ve
`.zenithiumChartChrome(yCount:xCount:)`. Bir yerde değişen ızgara rengi her
grafikte değişsin. `HybridView`'un kendine özgü eksenleri (satır 259, 270,
317) istisna kalır — orada eksen verisi taşıyor.

### B3 — Hareket sistemi neredeyse yok ⭐
44 görünüm dosyasında 7 animasyon çağrısı, 2 geçiş, 2 dokunsal geri
bildirim. `accessibilityReduceMotion` 5 yerde onurlandırılıyor — altyapı
duruyor, kullanılmıyor.

**Çözüm — kasıtlı ve sınırlı bir hareket dili:**
- Skor yayları ilk görünüşte 0'dan değerine yazılsın (`ArcGauge`, `Animatable`
  zaten var).
- Değişen her sayıya `contentTransition(.numericText())` — 18 vital, yük
  oranı, skorlar.
- Sayfa/sheet içeriğine tek bir yerleşik giriş geçişi.
- Hub gezinmesinde kart → ekran `matchedGeometryEffect`.

**Sınır:** ortam animasyonu, dekoratif parçacık, sürekli döngü yok. Sağlık
verisi okunan bir ekranda hareket dikkat çeker, sonra rahatsız eder.

### B4 — Dokunsal geri bildirim iki yerde
**Çözüm:** `sensoryFeedback` — toparlanma bandı değiştiğinde (`.impact`),
günlük kaydedildiğinde (`.success`), tahlil satırı onaylandığında
(`.selection`), reçete kabul edildiğinde (`.success`). Sadece durum
değiştiren eylemlerde; gezinmede değil.

### B5 — Yükleme durumu iskelet değil, dönen çark
`redacted` ve `ContentUnavailableView` kullanımı: 0.
`StateViews.swift` içinde `LoadingStateView` ve `NoDataView` var, işlerini
görüyorlar; ama yüklenme bitince düzen zıplıyor.

**Çözüm:** gerçek düzeni taklit eden `redacted(reason: .placeholder)`
iskeletleri. Boş durumlarda `ContentUnavailableView` — Apple'ın kalıbı,
bedava erişilebilirlik ve Dynamic Type davranışı getirir.

### B6 — Palet yalnızca koyu; bu bir karar mı, eksik mi?
`ZenithiumColor.background` sabit `0x07090E`. Aydınlık moddaki kullanıcı
koyu bir uygulama görüyor.

**Öneri:** koyuyu kimlik olarak koru — gece okunan bir sağlık uygulaması
için savunulabilir bir tercih — ama onu bir *tercih* hâline getir:
belirteçleri anlamsal bir katmanın (`surface`, `onSurface`, `hairline`)
arkasına al, `@Environment(\.colorScheme)` bağlanabilir olsun. Bugünkü
yapıda aydınlık tema eklemek 40+ dosyaya dokunmayı gerektirir; belirteç
katmanından sonra tek dosya olur.

### B7 — Dynamic Type'ta 14 satır kesiliyor
`lineLimit(1)`: 14 çağrı yeri. AX5 boyutunda bunlar kırpılır.

**Çözüm:** her birini tek tek gözden geçir. Sayısal değerlerde
`minimumScaleFactor(0.7)`; etiketlerde sarmaya izin ver. Ölçüt: en büyük
erişilebilirlik boyutunda hiçbir ekranda kesilen metin kalmaması.

### B8 — Erişilebilirlik 44 dosyanın 33'ünde
11 görünüm dosyasında `accessibilityLabel`/`accessibilityValue` yok.
Ayrıca grafikler ses grafiği tanımlayıcısı taşımıyor, kas haritası
bölge bölge gezilemiyor.

**Çözüm:** 11 dosyayı listele ve kapat; grafiklere
`accessibilityChartDescriptor`; kas haritasına bölge rotoru (`BodyRegion`
zaten `Identifiable`).

### B9 — Simge dili tamamen stok
Yalnızca SF Symbols. Dört mercek (koşu / hibrit / kuvvet / sağlık) için
küçük bir özel sembol seti, uygulamayı kendi kategorisindeki her şeyden
görsel olarak ayırır. Sembol formatında üretilirse Dynamic Type ve ağırlık
eşleşmesi bedava gelir.

### B10 — Saat ve widget'lar kendi boşluklarını kullanıyor
`WATCH_SHARED` paylaşımı zaten var; B1'in belirteç dosyası oraya da
girsin ki iki yüzey aynı ritimde olsun.

---

## C — Yeni özellikler

Sıralama ilkesi: **önce motorların zaten hesaplayıp arayüzün göstermediği
şeyler.** Bu maddeler en az yeni riskle en çok değer veriyor.

### C1 — Antrenman içi canlı ekran (saat) ⭐⭐
`StrainEngine` zorlanmayı olay sonrası hesaplıyor; `PrescriptionEngine`
günün yük tavanını (`loadCeiling(forInstantRatio:)`) zaten üretiyor.
Eksik olan tek şey ikisini seans sırasında birleştiren ekran: biriken
zorlanma, günün tavanına oranla ve tavana kalan süre.

Bu, mevcut matematiğin en büyük kullanılmayan kısmı. Whoop'un canlı
zorlanma ekranının karşılığı ve altındaki tüm hesap yazılı durumda.

### C2 — Yarış temposu planlayıcısı ⭐⭐
`EnduranceEngine` kritik hızı ve Minetti eğim maliyetini (`gradeAdjustedPace`)
hesaplıyor. Kullanıcının seçtiği bir GPX'ten parkur profilini oku →
kilometre başına hedef tempo üret. Ağ gerekmez, dosya seçici yeter.
Koşucu tarafı için en yüksek talep bu.

### C3 — Tahlil zaman çizelgesi ⭐
`BloodMarkerDetailView` tek belirteci çiziyor. Panel görünümü (lipid,
tiroit, demir…) + referans bandı gölgeli alan olarak + değişim hızı
(yılda birim). `LabInsightEngine` gözlemleri zaten üretiyor; eksik olan
zaman ekseni.

### C4 — Uyku borcu defteri ve sosyal jetlag
`EnvironmentEngine` sirkadiyen güvenilirliği hesaplıyor. Buradan yuvarlanan
uyku borcu ve hafta içi/sonu orta nokta kayması doğrudan çıkar.

### C5 — Takviye günlüğü × korelasyon ⭐
Korelasyon motoru günlük davranışları üzerinde çalışıyor ve güven aralığı
üretiyor. Takviyeleri birer davranış olarak eklemek, "kreatine başladığımda
HRV'me ne oldu" sorusunu mevcut istatistikle cevaplanabilir kılıyor.
**§12 sınırı:** motor ilişki bildirir, etki iddia etmez; dil filtresi
(`SafetyFilter`) bu ayrımı zaten koruyor.

### C6 — Faza duyarlı reçete
`CycleEngine` fazı kestiriyor ve `BriefingContext` bunu okuyor, ama
`PrescriptionEngine` okumuyor. Faz bilgisini reçeteye bağlamak, kadın
sporcu tarafındaki en belirgin boşluk.

### C7 — Isı ve nem adaptasyonu
`EnvironmentEngine`'in gün ışığı ve saat dilimi eksenlerinin doğal
devamı: HealthKit antrenman ortam sıcaklığından ısı alışması.
(İrtifa bilerek dışarıda kalıyor — `CMAltimeter` yalnızca canlı veri
veriyor, ROADMAP v3'teki istisna geçerli.)

### C8 — Oturum tanıma ve şablonlar
HealthKit antrenmanlarını `HybridView`'da zaten modellenen istasyonlara
sınıflandır; tekrar eden seansları şablona dönüştür.

### C9 — Tam veri dışa/içe aktarımı ⭐
Belge kasası ve hekim raporu var; ama tüm veritabanını yeni bir telefona
taşımanın yolu yok. Sunucusuz bir uygulamada bu bir boşluk değil, bir
risk. Sürümlenmiş JSON dışa aktarım + içe aktarım, `VersionedSchema`
altyapısıyla uyumlu.

### C10 — Widget ailesini genişlet
Kilit ekranı dairesel aksesuarı (toparlanma) ve etkin seans için Live
Activity. `WidgetSnapshot` formatı (`currentFormatVersion = 2`) hazır.

### C11 — Karşılaştırmalı referans bantları
`LongevityEngine` yüzdelikleri yalnızca kullanıcının kendi geçmişine karşı
hesaplıyor. VO₂maks ve dinlenme nabzı için yayınlanmış yaş/cinsiyet
normları isteğe bağlı bir katman olarak eklenebilir — **referans olarak
etiketli, teşhis olarak değil** (§12).

---

## Sıralama

**Dalga 1 — ölç ve temelleri at.**
A9 (ölçüm), A1 (kas haritası), A2 (biyobelirteç), B1 (boşluk belirteci),
B2 (grafik çerçevesi). Hepsi davranış değiştirmeyen, testlerle korunan
işler; ilk ikisi en büyük iki kazanç.

**Dalga 2 — hissedilen kalite.**
A3–A5 (okuma birleştirme), B3–B5 (hareket, dokunsal, iskelet),
B7–B8 (Dynamic Type, erişilebilirlik). Bu dalgadan sonra uygulama
"profesyonel" hissini ölçülebilir biçimde kazanır.

**Dalga 3 — yeni yüzey.**
C1 (canlı seans), C2 (yarış temposu), C3 (tahlil zaman çizelgesi),
C9 (veri taşıma). Dördü de mevcut motorların üstüne biniyor.

**Dalga 4 — derinleştirme.**
C4–C8, C10, C11, A6–A8, B6, B9, B10.

## Bitti sayma ölçütleri

- Kas haritası: boyut sabitken kare başına spline inşası **0**.
- Tahlil içe aktarma: satır başına normalizasyon **0** (önceden ~200).
- Bugün ekranı: yenileme başına `dayRecords` okuması **1** (önceden 4).
- Görünüm katmanında ölçek dışı `spacing:` sabiti **0**.
- En büyük erişilebilirlik boyutunda kesilen metin **0**.
- `accessibilityLabel` taşımayan görünüm dosyası **0** (bugün 11).
- Başarım paketi iş sayısı üzerinden iddia ediyor, duvar saati üzerinden değil.

---

# Uygulama durumu

**Dört dalganın dördü de tamamlandı.** Aşağıda ne yapıldığı ve **denetimin
yanıldığı yerler** var — yol haritası koda bakarak yazılmıştı ama birkaç
maddede yanlış şeye bakmış. Uygulama sırasında çıktılar; hepsi yazılı.

## Tamamlananlar

| # | Madde | Sonuç |
|---|---|---|
| A9 | Ölçüm | `ZenithiumSignpost` üç yolda; `PerformanceRegressionTests` iş sayısı üzerinden |
| A1 | Kas haritası | Boyut sabitken kare başına spline **0** (önce düzen başına 42) |
| A2 | Biyobelirteç | Satır başına normalizasyon **0** (önce 252); aday tarama 252 → **2–9** |
| A3 | Vitals | 18 ardışık okuma → 4 eşzamanlı görevli sınırlı grup |
| A4 | Gün kayıtları | `DayRecordCache`; Bugün yenilemesi 4 okuma → **1** |
| A5 | Paylaşılan pencere | Kuvvet ve yük ekranları aynı 120 günlük okumayı paylaşıyor |
| A6 | Belge araması | Tuş başına 2 MB katlama → yükleme başına bir kez |
| A7 | HealthKit | İki döngü içi bekleme → görev grubu |
| A8 | Temel çizgiler | Doldurma geçişinde 8 özdeş 60 günlük okuma → **1** |
| B1 | Boşluk ölçeği | `ZenithiumMetrics`; 392 çağrı yeri belirtece taşındı |
| B2 | Grafik çerçevesi | `.zenithiumChartChrome()`; dört kopya → bir tanım |
| B3 | Hareket | Yay girişte 0'dan yazılıyor; değişen her sayı `numericText` |
| B4 | Dokunsal | 2 → 6 yer, yalnızca durum değiştiren eylemlerde |
| B5 | Yükleme | Dönen çark → ekranın iskeleti (`scored` / `cards` / `chart`) |
| B7 | Dynamic Type | Korumasız üç etiket düzeltildi |
| B8 | Erişilebilirlik | Dört zaman serisi grafiğinin dördü de artık çalınabilir |
| C1 | Canlı seans | Saatte, `LiveSessionEngine` üzerinden |
| C2 | Yarış temposu | GPX → kilometre hedefleri, Minetti eğrisi tersine |
| C3 | Tahlil zaman çizelgesi | Panel gruplaması + yıllık değişim hızı |
| C9 | Veri taşıma | Sürümlenmiş `.zenithium` arşivi, dışa + içe |

## Denetimin yanıldığı üç yer

Yol haritası kod taramasına dayanıyordu ama üç maddede yanlış şeyi ölçmüş.
Uygulamada ortaya çıktı; düzeltmesi burada.

**B8 — "11 dosyada erişilebilirlik etiketi yok."** Yanlış. O sayı yalnızca
`accessibilityLabel|accessibilityValue` araması yapıldığı için çıkmıştı; daha
geniş arama gerçek ekranların hepsinin kapsandığını gösterdi. Etiketsiz altı
dosya var, hepsi görünüm değil (geometri, belirteçler, grafik değiştiricisi).
Kas haritası rotoru da zaten vardı — her bölge kendi odaklanabilir öğesi.
**Gerçekten eksik olan**, dört zaman serisi grafiğinin üçünde ses grafiği
tanımlayıcısı olmamasıydı; `SeriesChartDescriptor` onu kapattı.

**A8 — "60 günlük doldurma 60 ayrı okuma dalgası."** Yanlış. Doldurma zaten
geçiş başına 7 günle sınırlı, üstelik nedenini açıklayan bir yorumla. **Gerçek
israf** şuydu: bir geçişteki her gün `refreshBaselines`'ı aynı `now` ile
çağırıyor, ve temel çizgiler yalnızca o ana bağlı — yani 8 özdeş 60 günlük
HealthKit okuması ve 8 özdeş yazma, hem de zaten en yavaş olan açılışta.

**A6 — "SwiftData izdüşüm okuması yok."** Doğru ama önemsiz. **Gerçek maliyet**
`matches(query:)`'ydi: belge başına, tuş başına, başlık + not + çıkarılan metni
katlıyordu. 50 KB'lık 40 belge = her karakterde 2 MB katlama, hem de tuşlar
arasında hiç değişmeyen bir sonuç için.

Üçü de aynı dersi veriyor: **bir grep sayısı bir ölçüm değildir.** A9'un
imzalı aralıkları ve sayım testleri tam bunun için var.

## Dalga 4 — tamamlandı

| # | Madde | Sonuç |
|---|---|---|
| C4 | Uyku defteri | 14 günlük yuvarlanan borç + sosyal jetlag; fazla uyku yarım geri ödüyor |
| C5 | Takviye korelasyonu | Kür = pencere; `CorrelationSubject` ile aynı istatistiğe giriyor |
| C6 | Faza duyarlı reçete | Faz **seansı değiştirmiyor**, okumayı açıklıyor — testle sabitlendi |
| C7 | Isı adaptasyonu | Seans hava verisinden; 7 gün %76, 14 gün %94, 3 hafta ara %13 |
| C8 | Oturum tanıma | Tekrar eden seans şekilleri; istasyon tahmini **bilerek yapılmadı** |
| C10 | Widget ailesi | Kilit ekranı üç aile; ayrıca kayıtsız iki widget bulundu |
| C11 | Referans bantları | VO₂max, FRIEND kayıtları; yaş/cinsiyet yoksa karşılaştırma yok |
| B6 | Palet katmanı | Aydınlık palet yazıldı; renk sabiti artık tek dosyada |

## Dalga 4'te bulunan üç şey daha

**İki widget cihazda hiç görünmüyordu.** `JournalWidget` ve
`RecoveryControlWidget` Faz 22'de yazılmış ama `WidgetBundle`'a hiç
eklenmemiş. Demette olmayan bir widget, kodu ne kadar doğru olursa olsun,
yoktur. İkisi de artık kayıtlı.

**C10'un yarısı zaten yapılmıştı.** Kilit ekranı dairesel aksesuarı §10'dan
beri duruyordu; eksik olan diğer iki aileydi.

**Arşiv formatı bir tuzak taşıyordu.** Yeni bir alana varsayılan değer
vermek yetmiyor — Swift'in sentezlenmiş çözücüsü anahtar yoksa varsayılana
düşmüyor, hata veriyor. Elle yazılmış fixture testi tam bunu yakaladı.

## Son üç iş — hepsi kapandı

Önceki turda açık bırakılan üç maddenin üçü de tamamlandı.

**B9 — özel simgeler.** SF Symbol dosyası üretmek yerine `Shape` geometrisi:
`BodyGeometry`'nin zaten kullandığı yol. Derleyici denetliyor, her yüzeyde
aynı ölçekleniyor, ve **test edilebiliyor** — dört işaretin kutusunda kaldığı,
kutuyu anlamlı doldurduğu, ölçeklendiği ve birbirinden farklı olduğu
doğrulanıyor. Bir SF Symbol'ün rehberleri yanlışsa hizasız çizer, sesli
hata vermez; burada o risk yok.

**B6 — palet geçişi.** Ölçüm kararı verdi: 712 çağrı yeri, altısı ortamı
okuyamayan statik bağlamda. Asset catalog çizim anında çözüyor, yani **hiçbir
çağrı yeri değişmedi**. `Scripts/generate-colors.py` hem `.colorset` JSON'unu
hem `ZenithiumColorAsset` enum'unu tek tablodan üretiyor — bir Swift adı
olmayan bir renk setine işaret edemiyor, ve testler iki yönde de doğruluyor.
Varsayılan koyu kaldı; `Ayarlar → Görünüm` üç seçenek sunuyor.

**C10 — Live Activity.** Köprü kuruldu: saat `updateApplicationContext` ile
üç saniyede bir durum yolluyor, telefon Live Activity'yi ondan sürüyor.
Telefon **yeniden hesaplamıyor** — Dynamic Island'daki sayı saatin
hesapladığı sayı. Birleştirilmiş teslimat sırayı bozabildiği için her yük
`generatedAt` taşıyor ve eskisi düşürülüyor.

## B6 ve C10'un getirdiği üç düzeltme

**`UserProfileSnapshot` aynı tuzağa düşüyordu.** Yeni bir zorunlu alan,
sentezlenmiş çözücüde eksik anahtarla hata veriyor — bu kez çekirdek bir
tipte. Profilin tel biçimi artık elle yazılı; sonradan eklenen alanlar
`decodeIfPresent` ile okunuyor.

**`project.yml`'de saat hedefi yoktu.** ASSUMPTION BUILD-1 o dosyanın otorite
olduğunu söylüyor; Faz 21'den beri yalnızca üretici betiğinde duran bir hedef
bunu yanlış kılıyordu. Eklendi.

**Şema zinciri üçe çıktı.** V2 takviye kürlerini, V3 görünüm tercihini
ekliyor; ikisi de hafif geçiş.

## Doğrulama notu

Bu konteynerde Swift araç zinciri yok; **hiçbir şey derlenmedi.** Her değişiklikten
sonra yapılanlar:

- süslü parantez dengesi ve §2.4 yasaklı yapı taraması;
- saat **ve** widget hedeflerinin kaynak kümelerinin kapalılığı (statik bağımlılık
  taraması) — `Domain`'e konan her yeni tip bu iki hedefte de derlenmek zorunda,
  ve bu tarama iki kez gerçek bir sızıntı yakaladı;
- her yeni motorun matematiğinin Python'da bağımsız doğrulanması — yük eğrisi,
  yarış temposu, ısı adaptasyonu zaman seyri, uyku defteri, Welch aralıkları.

Derleme macOS'ta.

## Son durum

239 üretim dosyası · 39 test dosyası · **474 test** · 51.609 satır · 4 hedef.

Yol haritasında açık madde kalmadı. Görünüm katmanında ölçek dışı boşluk
sabiti yok; renk sabitleri tek üretilmiş tabloda; yasaklı yapı yok; saat ve
widget hedeflerinin kaynak kümeleri kapalı.
