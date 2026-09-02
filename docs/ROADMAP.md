# Zenithium — Ürün Yol Haritası v3

## Neden v1'i attık

İlk yol haritası koşuculara yazılmıştı. Yanlıştı — çünkü Zenithium'un halihazırdaki üç ana
motoru (Recovery, Strain, Sleep) **zaten spordan bağımsız.** Zorlanma kalp atışından
hesaplanıyor; stresli bir toplantı da, sled push da, 10K da aynı ölçeğe düşüyor. Whoop'un
asıl zekâsı da tam olarak bu: hiç spor yapmayan biri için de anlamlı olması.

Yani doğru mimari **koşu uygulaması** değil, **evrensel çekirdek + spora özel mercekler.**

```
                    ┌─────────────────────────────────┐
                    │      EVRENSEL ÇEKİRDEK          │
                    │  Recovery · Strain · Sleep      │
                    │  Sirkadiyen · Sağlık temelleri  │
                    │  Günlük + korelasyon motoru     │
                    │  (herkes, her gün, istisnasız)  │
                    └───────────────┬─────────────────┘
                                    │
        ┌───────────────┬───────────┴───────┬──────────────────┐
        ▼               ▼                   ▼                  ▼
   ┌─────────┐   ┌─────────────┐    ┌─────────────┐   ┌──────────────┐
   │ Dayanık.│   │   Hibrit    │    │    Kuvvet   │   │   Sağlık     │
   │ merceği │   │  merceği    │    │   merceği   │   │  merceği     │
   │         │   │             │    │             │   │              │
   │ koşu    │   │ Hyrox       │    │ hipertrofi  │   │ hiç spor     │
   │ bisiklet│   │ CrossFit    │    │ powerlift.  │   │ yapmayan     │
   │ yüzme   │   │ fonksiyonel │    │             │   │              │
   └─────────┘   └─────────────┘    └─────────────┘   └──────────────┘
```

Kullanıcı bir mercek seçer, çekirdek herkeste aynı kalır. Mercek değiştirmek uygulamayı
yeniden kurmak değil, sadece hangi ekranların öne çıktığını değiştirmek demektir.

---

## Üç kullanıcı, üç farklı cümle

Aynı motor, farklı çıktı. Yol haritasının başarı ölçütü bu üç cümlenin de doğru kurulması:

**Koşucu, salı sabahı**
> Recovery 72. Bugün 55 dk kolay, 5:40–6:00/km. Bacaklar %71'de — pazartesi intervalinden.
> Bu 12.4 zorlanma yapar, tavanın 17.0.

**Hyrox sporcusu, perşembe**
> Recovery 58. Bugün istasyon değil, kompanse koşu günü. Sled sonrası koşu temponun
> tazeye göre %8 düşüyor — bu senin zayıf halkan. 4×800 m, aralarda 40 sn farmer's carry.

**Hiç spor yapmayan, pazar**
> Recovery 81 — üç haftanın en iyisi. Son 10 günde alkol kaydettiğin gecelerde HRV ortalama
> 9 ms düşük çıktı. Bu hafta 3 gün yürüyüş yaptın, geçen hafta 1'di.

---

## Değişmeyecek kurallar

Yeni özellikler bunları bozamaz. Tasarım tercihi, eksiklik değil:

1. **Tıbbi cihaz değil.** Kalp ritmi bildirimleri, apne göstergeleri, kan değerleri
   *gösterilir*, yorumlanmaz. "AFib yükün %2" denir; "kalbinde sorun var" denmez.
2. **Kalori ve kilo hedefi yok.** Hiçbir mercekte. Vücut ağırlığı yalnızca W/kg gibi
   hesaplarda okunur, hedef veya trend olarak gösterilmez.
3. **Ağ erişimi yok.** Bulut yok, hesap yok, Strava senkronu yok. Her hesap cihazda.
4. **Her sayı açıklanabilir.** Ekrandaki her metriğin nereden geldiği görünür olmalı.
5. **Korelasyon nedensellik değildir.** Günlük motoru "şunu yaptığın gecelerde HRV daha
   düşüktü" der; "alkol HRV'ni düşürüyor" demez.

---

# BÖLÜM 1 — EVRENSEL ÇEKİRDEK

Herkes için, mercek seçiminden bağımsız.

## Faz 10 — Günlük ve Korelasyon Motoru ⭐

**Neden ilk:** Whoop'un en yapışkan özelliği bu ve üç persona için de aynı derecede
değerli. Hiç spor yapmayan biri için uygulamanın *tek* sebebi bile olabilir. Tamamen
cihaz içi istatistik — ağ gerektirmiyor, mevcut mimariyle birebir uyumlu.

**Yapılacaklar**
- **Davranış günlüğü:** alkol, kafein (ve saati), geç yemek, ekran, stres, hastalık,
  yolculuk, ilaç, sauna, soğuk duş, meditasyon — özelleştirilebilir liste
- **iOS 18 `stateOfMind` entegrasyonu:** Apple'ın yeni ruh hâli kaydını oku, kendi
  günlüğümüzle birleştir
- **Korelasyon motoru:** her davranış için, o davranışın kaydedildiği geceleri takip eden
  Recovery'yi kaydedilmediklerle karşılaştır. Etki büyüklüğü + güven göstergesi (kaç
  gözlem var). 5 gözlemin altında sonuç gösterilmez.
- **Haftalık içgörü kartı:** "Bu ay en güçlü üç ilişki"

**Dil kuralı:** "Alkol kaydettiğin 7 gecede Recovery ortalama 11 puan düşüktü (14 gözlem)."
Sebep-sonuç iddiası yok, gözlem var.

**Boyut:** Orta · **Risk:** Düşük

---

## Faz 11 — Sağlık İzleme Katmanı

**Amaç:** Apple Watch'ın ölçtüğü ama hiçbir uygulamanın toparlamadığı sinyalleri tek
ekranda toplamak. Özellikle "sağlık merceği" kullanıcısı için uygulamanın omurgası.

**Yapılacaklar — Apple Watch'ın sınırlarını zorlayan kısım**

| Veri | HealthKit | Neden değerli |
|---|---|---|
| Dinlenme nabzı trendi | `restingHeartRate` | Var ama trend olarak gösterilmiyor |
| Yürüyüş nabzı | `walkingHeartRateAverage` | Kondisyonun en sessiz göstergesi |
| Nabız toparlanması | `heartRateRecoveryOneMinute` | Aerobik kapasitenin en iyi tek göstergesi |
| VO2max | `vo2Max` | 90 günlük trend |
| AFib yükü | `atrialFibrillationBurden` | Yalnızca gösterim (§12) |
| Yüksek/düşük nabız olayları | kategori tipleri | Yalnızca gösterim |
| EKG | `HKElectrocardiogram` | Yalnızca gösterim, sayım ve tarih |
| Uykuda solunum bozulmaları | `appleSleepingBreathingDisturbances` (iOS 18) | Uyku kalitesi sinyali |
| Kandaki oksijen | `oxygenSaturation` | Var, trend eklenecek |
| Gün ışığı süresi | `timeInDaylight` (iOS 17) | **Sirkadiyen motorun eksik girdisi** |
| Ses maruziyeti | `environmentalAudioExposure` | Uzun vadeli işitme sağlığı |
| Yürüme hızı, asimetri, çift destek | mobilite dörtlüsü | Yaşlanma + yorgunluk göstergesi |
| Yürüme dengesi | `appleWalkingSteadiness` | Sağlık merceği için birinci sınıf |
| Merdiven hızı | `stairAscentSpeed` | Fonksiyonel kapasite |
| 6 dk yürüme mesafesi | `sixMinuteWalkTestDistance` | Klinik standart, Watch hesaplıyor |

- **Vitals ekranı:** hepsi tek yerde, her biri kendi baz çizgisine göre
- **Sapma tespiti:** mevcut EWMA motoru bu metriklere de uygulanır — yeni motor gerekmez
- **Gün ışığı → sirkadiyen:** ışık en güçlü zeitgeber'dır. `timeInDaylight` düşükse
  sirkadiyen eğrinin güvenilirliği düşer ve uygulama bunu söyler.

**Boyut:** Orta-büyük · **Risk:** Düşük — mevcut HealthKit ve baz çizgisi mimarisine ekleniyor

---

## Faz 12 — Regl Döngüsü Farkındalığı

**Amaç:** Kadın kullanıcıların yarısı için Recovery'nin doğruluğunu ciddi biçimde artırmak.
Bugün eksik olması bir boşluk değil, hata.

**Neden:** Luteal fazda dinlenme nabzı 3–5 bpm artar, HRV düşer, vücut ısısı ~0.3 °C yükselir.
Bunu bilmeyen bir Recovery motoru, tamamen normal bir fazı "kötü toparlanma" olarak okur.

**Yapılacaklar**
- `menstrualFlow`, `basalBodyTemperature`, `ovulationTestResult`, `progesteroneTestResult`
  okuma
- **Faz tahmini:** foliküler / ovulasyon / luteal / menstrüel
- **Faz-farkında baz çizgisi:** her metrik için faza göre ayrı baz — mevcut
  `BaselineEngine`'in metrik başına satırı, faz başına satıra genişletilir
- **Faz bağlamı:** "Recovery 61 — luteal fazdasın, bu faz için normalin 58"
- **Antrenman bağlamı:** faza göre kapasite beklentisi (dayatma değil, bilgi)

**Boyut:** Büyük · **Risk:** Orta — bilimsel olarak dikkat gerektirir, §12 dili kritik

---

## Faz 13 — Stres ve Gün İçi Yük

**Amaç:** Zorlanmayı yalnızca antrenmandan değil, hayattan da okumak. Hiç spor yapmayan
kullanıcı için "Strain 8.2" ancak böyle anlam kazanır.

**Yapılacaklar**
- **Gün içi stres eğrisi:** dinlenme hâlindeki nabız yükselmeleri + HRV düşüşleri
- **Zorlanma kaynak ayrımı:** antrenman kaynaklı mı, gün kaynaklı mı
- **Toparlanma pencereleri:** günün sakinleşen anları
- **Nefes önerisi:** yüksek stres bloğu sonrası (`mindfulSession` ile kayıt)
- **Ayakta durma / hareket düzeni:** `appleStandTime`, `appleExerciseTime` — hedef değil,
  desen olarak

**Boyut:** Orta · **Risk:** Düşük

---

# BÖLÜM 2 — MERCEKLER

## Faz 14 — Antrenman Zekâsı (tüm mercekler için ortak)

**Amaç:** Merceklerin ortak matematiği. Her mercek bunu farklı gösterir ama motor tektir.

**Yapılacaklar**
- **Akut:Kronik yük oranı** — 7 gün / 28 gün. **`BaselineEngine`'in EWMA'sı buna birebir
  uygun:** literatürdeki en iyi ACWR varyantı (Williams 2017) EWMA tabanlı. Motor hazır.
- **Yükleme hızı, monotonluk, Foster zorlanması**
- **Antrenman detay ekranı:** `HKWorkoutActivity` (iOS 17) ile çok segmentli antrenmanlar,
  `HKWorkoutEvent` ile turlar, splitler, nabız/tempo eğrisi, rota, yükseklik
- **Ekipman takibi:** ayakkabı ve diğer ekipman kilometresi
- **Antrenman kalitesi:** aerobik ayrışma, verimlilik faktörü, nabız kayması

**Boyut:** Büyük · **Risk:** Düşük-orta

---

## Faz 15 — Dayanıklılık Merceği

**Kim için:** Koşucu, bisikletçi, yüzücü, triatletçi.

**Yapılacaklar**
- **Koşu:** `runningSpeed`, `runningPower`, `runningStrideLength`,
  `runningGroundContactTime`, `runningVerticalOscillation`; kadans = hız ÷ adım uzunluğu × 60
- **Bisiklet:** `cyclingPower`, `cyclingCadence`, `cyclingSpeed`,
  `cyclingFunctionalThresholdPower` (iOS 17)
- **Yüzme:** `swimmingStrokeCount`, `distanceSwimming`, `underwaterDepth`, SWOLF
- **Kritik Hız / Kritik Güç modeli:** `d = CS·t + D'`, geçmiş en iyi eforlardan
- **Tempo ve güç bölgeleri:** modelden türetilir, tahminden değil
- **Yarış tahmini:** 5K'dan maratona, kendi verinle kalibre
- **Eğim düzeltilmiş tempo:** rota yüksekliğinden
- **Isı düzeltmesi:** antrenman metadata'sındaki sıcaklık ve nemden

**Boyut:** Büyük · **Risk:** Orta

---

## Faz 16 — Hibrit Mercek (Hyrox / CrossFit) ⭐

**Kim için:** Hyrox, CrossFit, fonksiyonel fitness. Bu kitle hızla büyüyor ve **hiçbir
uygulama onlara doğru bakmıyor** — hepsi ya saf dayanıklılık ya saf kuvvet varsayıyor.

**Hyrox'un asıl problemi:** 8×1 km koşu, aralarında 8 istasyon. Zorluk koşuda da değil
istasyonda da değil — **yorgunken koşmakta.** Ölçülmesi gereken şey bu.

**Yapılacaklar**
- **Kompanse koşu skoru:** taze koşu temponun vs istasyon sonrası koşu temponun aynı
  nabızdaki farkı. Hyrox'ta yarışı kaybettiren tek sayı budur.
- **Roxzone takibi:** geçiş süreleri — elit ile amatörü ayıran en büyük kalem
- **İstasyon profili:** 8 istasyonun her biri için süre, nabız, toparlanma; zayıf halka tespiti
- **Yarış simülasyonu:** tam veya yarım simülasyon kaydı, geçmişle karşılaştırma
- **`HKWorkoutActivity` segmentasyonu (iOS 17):** her istasyon ayrı segment — Apple'ın
  çok segmentli antrenman API'si tam bunun için var
- **Kas dayanıklılığı vs kardiyovasküler denge:** mevcut 16 kas modeli + TRIMP birlikte;
  "aerobik tabanın yeterli ama posterior zincirin yetişemiyor"
- **Sled/carry yükü:** posterior zincir + kavrama yükü, mevcut kas motoruna özel satır
- **Hyrox'a özel hazırlık:** yarış tarihine göre istasyon/koşu dengesi

**Boyut:** Büyük · **Risk:** Orta · **Farklılaşma:** En yüksek — bu alanda ciddi rakip yok

---

## Faz 17 — Kuvvet Merceği

**Kim için:** Hipertrofi, powerlifting, genel kuvvet.

**Yapılacaklar**
- **Antrenman kaydedicinin genişletilmesi:** egzersiz kütüphanesi, ağırlık + tekrar + RPE
- **Hacim takibi:** kas grubu başına haftalık set sayısı (literatürdeki 10–20 set aralığı)
- **Tahmini 1RM:** Epley/Brzycki, zaman içinde trend
- **Progresif aşırı yük:** egzersiz bazında ilerleme tespiti
- **Kas grubu dengesi:** itme/çekme, ön/arka zincir oranları — mevcut 16 kas modeli hazır
- **Deload önerisi:** hacim + Recovery + kas yorgunluğu birlikte

**Boyut:** Orta-büyük · **Risk:** Düşük — mevcut kas motoru ve kaydedici temeli var

---

## Faz 18 — Sağlık Merceği

**Kim için:** Hiç antrenman yapmayan, sadece sağlığını takip eden kullanıcı.

**Amaç:** Uygulamanın dilini değiştirmek. "Bugün ne kadar zorlanmalısın" sorusu bu kişi
için anlamsız; "vücudun nasıl ve neyden etkileniyor" sorusu anlamlı.

**Yapılacaklar**
- **Basitleştirilmiş ana ekran:** Recovery + Uyku + Günlük içgörüsü; Strain tavanı gizli
- **Hareket tutarlılığı:** hedef değil, desen — "bu hafta 4 gün 20 dk üstü hareket"
- **Uzun vadeli sağlık trendleri:** VO2max, dinlenme nabzı, yürüme hızı, mobilite —
  yıl bazında
- **Kan değerleri entegrasyonu:** mevcut ekran + Recovery ile zaman hizalaması
- **Yaş karşılaştırması:** "VO2max'ın yaş grubunun üst %25'inde" (yalnızca gösterim, hedef değil)
- **Uyku koçluğu:** yatma saati tutarlılığı, sirkadiyen uyum

**Boyut:** Orta · **Risk:** Düşük

---

## Faz 19 — Reçete Motoru ⭐⭐

**Amaç:** Her şeyin buluştuğu yer. Recovery + tavan + mercek + yük + kas durumu →
**bugünün somut önerisi.**

**Yapılacaklar**
- **Mercek-farkında öneri:** aynı Recovery skoru koşucuya "55 dk kolay", Hyrox sporcusuna
  "kompanse koşu bloğu", kuvvetçiye "üst vücut, alt vücut dinlensin", sağlık kullanıcısına
  "40 dk tempolu yürüyüş" der
- **Zorlanma tahmini:** TRIMP motoru **tersten** çalıştırılır — "planladığın antrenman ≈ 12.4
  zorlanma". Motor zaten yazılı, sadece ters yönde kullanılacak.
- **Sirkadiyen saat önerisi:** mevcut eğriden
- **Alternatifler ve gerekçe:** her öneri neden o olduğunu söyler

**Boyut:** Büyük · **Risk:** Orta — mantık öznel, ayarlanabilir olmalı

---

## Faz 20 — Planlama ve Periyodizasyon

- Hedef etkinlik (yarış, Hyrox, güç testi) ve tarih
- Baz → yapı → keskinleşme → tapering
- Uyum takibi, hastalık/tatil sonrası yeniden planlama
- Etkinlik haftası: uyku borcu, sirkadiyen hazırlık, saat uyumu

**Boyut:** Büyük · **Risk:** Orta-yüksek

---

## Faz 21 — Apple Watch Uygulaması

- watchOS hedefi, bilekte reçete
- Canlı rehberlik: tempo/nabız bandı, interval sayacı
- Hyrox modu: istasyon geçişleri, roxzone kronometresi
- Kuvvet modu: set/tekrar sayacı

**Boyut:** Çok büyük · **Risk:** Yüksek

**Not:** En görünür özellik bu, ama **19'dan önce yapılmamalı.** Bilekte gösterilecek iyi
bir reçete olmadan güzel bir watch uygulaması, boş tabağı süslemektir.

---

## Faz 22 — Sistem Entegrasyonu

- **Control Center widget'ı** (iOS 18 `ControlWidget`) — kilit ekranından tek dokunuş
- **Live Activity** — antrenman sırasında Dynamic Island
- **Interactive widget'lar** — widget'tan doğrudan günlük kaydı
- **App Intents / Siri** — "Bugün ne kadar toparlandım?"
- **Shortcuts** — otomasyon desteği

**Boyut:** Orta · **Risk:** Düşük

---

## İkinci dalga — v3'te eklenenler

v2 "hangi sporu yapıyorsun" sorusuna cevap veriyordu. v3 üç yeni ekseni ekliyor:

- **İçeri akan veri sadece saatten gelmesin.** Hastane tahlili, EKG raporu, doktor
  notu — hepsi cihazda okunup zaman çizelgesine oturmalı (Faz 23, 26).
- **Sayıyı gösterme, cümleyi kur.** Recovery 61 bir sayı. "Recovery 61, çünkü dün gece
  uykun 5s 40dk ve son üç gecenin en kötüsü" bir cevap (Faz 24).
- **Ekran, motorun kalitesini hak etsin.** Kutulardan yapılmış vücut haritası, arkadaki
  matematiği yalanlıyor (Faz 25).

---

## Faz 23 — Laboratuvar Zekâsı ⭐⭐

Hastaneden alınan PDF tahlil sonucunu uygulamaya atarsın, gerisi cihazda halledilir.

**Boru hattı**

```
PDF  ──►  metin katmanı var mı?  ──evet──►  metin
          │                                   │
          hayır                               ▼
          │                            satır ayrıştırıcı
          ▼                                   │
    sayfa → görüntü → Vision OCR ────────────►│
    (tr-TR + en-US, cihaz içi)                ▼
                                     eşleşen belirteç + değer + birim
                                              │
                                              ▼
                                   ⚠ ZORUNLU İNSAN ONAYI ekranı
                                              │
                                              ▼
                                          SwiftData
```

**Neden zorunlu onay ekranı:** OCR hata yapar. Tıbbi sayıda sessiz hata kabul edilemez.
Ayrıştırıcı hiçbir satırı kendi başına kaydetmez; her satır güven puanıyla birlikte
gösterilir, kullanıcı onaylar veya düzeltir.

**Kapsam**
- ~40 belirteçlik panel kataloğu: lipit, hematoloji, demir, tiroid, metabolik,
  karaciğer/böbrek, hormon, vitamin, iltihap.
- Her belirteç için Türkçe **ve** İngilizce laboratuvar isimleri (eşanlamlı sözlüğü) —
  "Hemoglobin", "HGB", "Hgb", "Hemoglobin (Hb)" hepsi aynı satıra düşer.
- Cinsiyete göre referans aralığı (hematokrit, ferritin, hemoglobin farklı).
- Birim dönüşümü: mg/dL ↔ mmol/L, ng/mL ↔ nmol/L, µg/L ↔ ng/mL.
- Ondalık virgül, `<0,3` gibi eşik değerler, `(30 - 400)` biçimli referans aralıkları.
- Panel bütünlüğü: "demir paneli için ferritin var, transferrin satürasyonu yok."
- Yeniden test takvimi: her belirtecin makul tekrar aralığı, son ölçümün yaşı.

**Sınır (§12, tartışmaya kapalı):** Aralık dışı bir değer görüldüğünde uygulamanın
söyleyeceği tek şey hekime yönlendirmedir. Teşhis yok, takviye önerisi yok, doz yok.
Antrenman tarafında bağlam kurar ("ferritin düşük seyrettiği dönemde HRV ortalaman
şuydu"), tedavi tarafında susar.

**Boyut:** Büyük · **Risk:** Orta (OCR doğruluğu) · **Durum:** bu turda yapıldı

---

## Faz 24 — Cihaz İçi Yapay Zekâ ⭐⭐

İki katman, biri her cihazda çalışır, diğeri varsa devreye girer.

**Katman 1 — Belirlenimci anlatıcı (her zaman açık)**
Şablon değil, karar ağacı: hangi sinyal bugünün *sebebi*, onu bulur ve cümleyi onun
üstüne kurar. Recovery 61 ise "neden 61" sorusunun cevabı HRV mi, RHR mi, uyku borcu mu,
kas yorgunluğu mu — katkı payları zaten motorda var, anlatıcı en büyük payı seçer.
İnternet yok, model dosyası yok, her iPhone'da aynı çalışır.

**Katman 2 — Apple Foundation Models (varsa)**
iOS 26 + Apple Intelligence açık cihazlarda `LanguageModelSession` ile aynı yapılandırılmış
girdiyi daha doğal bir dile çevirir. Yoksa katman 1 zaten cevabı vermiştir — kullanıcı
eksik bir şey görmez. **Veri cihazdan çıkmaz** (sunucuya giden bir istek yok).

**Güvenlik süzgeci:** Üretilen her cümle yayımlanmadan önce yasaklı kalıplardan geçirilir —
teşhis dili, ilaç/doz, kalori/kilo hedefi, "belirtini yok say" türü ifadeler. Süzgeç
tetiklenirse belirlenimci metne düşülür. Model ne söylerse söylesin, ekrana çıkan metin
bu süzgeçten geçmiş olandır.

**Yüzeyler**
- Günlük brifing (sabah, tek paragraf + üç madde)
- "Neden?" — her sayının yanında, katkı dökümüne inen açıklama
- Haftalık özet (pazar akşamı)
- Soru-cevap: sabit soru seti değil, kendi verisi üzerinden cevaplanan sorular

**Boyut:** Büyük · **Risk:** Orta · **Durum:** bu turda yapıldı

---

## Faz 25 — Görsel Sistem Profesyonelleşmesi ⭐

**Vücut haritası yeniden çizildi.** Eski hâli kutu ve elipslerden ibaretti. Yenisi her kas
grubu için elle yazılmış kübik bezier konturlar kullanıyor: omuz deltoidi yuvarlanıyor,
kuadriseps aşağı doğru inceliyor, latlar V oluşturuyor. Isı dolgusu düz renk değil,
kasın kendi eksenini takip eden gradyan; üstünde ince bir kontur ve kenar ışığı var.

**Grafik seti** (`ChartKit`)
- Referans bantlı belirteç grafiği (referans + optimal bant, ölçüm noktaları, trend oku)
- Radar / altıgen: sistem dengesi (kardiyo · kassal · dayanıklılık · esneklik · uyku)
- Yük grafiği: akut/kronik oran, "tatlı nokta" bandı, aşırı yük bölgesi
- Hipnogram: gerçek evre blokları, uyanma noktaları, evre geçiş yoğunluğu
- Sparkline: her kartın köşesinde 14 günlük mini seri

**Kural:** Her grafik hem açık hem koyu temada okunur, hem de VoiceOver ile
`accessibilityChartDescriptor` üzerinden dinlenebilir.

**Boyut:** Büyük · **Risk:** Düşük · **Durum:** bu turda yapıldı

---

## Faz 26 — Sağlık Belge Kasası

Faz 23'ün genellemesi: sadece tahlil değil, her sağlık belgesi.

- EKG raporu, görüntüleme raporu, ameliyat notu, aşı kartı, reçete
- OCR ile metin çıkarılır, tarih ve kurum bulunur, zaman çizelgesine oturur
- Belgeler cihazda `.complete` dosya koruması ile şifreli durur
- Arama: "2024 kan tahlilleri", "diz MR"
- Doktora giderken: seçili belgeler + son 90 günün özeti tek PDF

**Sınır:** Uygulama belgeyi *okur ve saklar*, yorumlamaz.

**Boyut:** Orta · **Risk:** Düşük

---

## Faz 27 — Hekime Rapor (dışa aktarım)

Faz 23'ün ters yönü ve bence en çok değer üreten özelliklerden biri. Doktora giderken
"nabzım bazen yükseliyor" demek yerine 12 haftalık veriyi tek sayfada uzatmak.

- İstirahat nabzı, HRV, uyku süresi/verimliliği, VO₂max, SpO₂, solunum hızı trendleri
- İşaretlenmiş anomaliler (ani RHR sıçraması, uzun uyku bozulması)
- Kan değerleri tablosu + zaman içindeki değişim
- İlaç ve semptom günlüğü
- Tek dokunuşla PDF; hiçbir yere yüklenmez, paylaşım kullanıcının elinde

**Boyut:** Orta · **Risk:** Düşük

---

## Faz 28 — Erken Uyarı ve Anomali Tespiti

Whoop'un en sevilen özelliği bu ve tamamen istatistik: kişisel taban çizgisinden anlamlı
sapma.

- Çok değişkenli sapma puanı: RHR ↑ + HRV ↓ + solunum hızı ↑ + uyku bozulması aynı gece
- "Vücudunda alışılmadık bir şey var" — teşhis değil, gözlem
- Aşırı antrenman erken uyarısı: 10 günlük HRV eğimi + ACWR + uyku borcu
- Toparlanma yörüngesi: sapmadan sonra kaç günde taban çizgisine dönüldü

**Sınır:** Hastalık adı geçmez. "Grip olmuşsun" demez, "bu sabahki değerlerin son 60
günün dışında" der ve semptom varsa hekime yönlendirir.

**Boyut:** Orta · **Risk:** Orta (yanlış pozitif maliyeti yüksek)

---

## Faz 29 — Hareket Kalitesi ve Uzun Ömür

"Hiç spor yapmayan" personası için asıl değer burada, ve Apple Watch'ın en az kullanılan
verileri burada.

- Yürüyüş kararlılığı, çift destek süresi, adım uzunluğu, yürüyüş asimetrisi
- Merdiven inme/çıkma hızı — fonksiyonel kapasitenin en erken göstergelerinden
- VO₂max yörüngesi ve "kondisyon yaşı"
- İşitme: ortam ve kulaklık ses maruziyeti
- Ayakta kalma, hareket dakikaları, günlük ışık maruziyeti
- Bileşik **Zenithium Skoru**: tek uzun vadeli sağlık göstergesi (bileşenleri her zaman
  açılabilir — kapalı kutu skor yok)

**Boyut:** Büyük · **Risk:** Düşük

---

## Faz 30 — Çevresel Bağlam (cihaz içi)

Ağ yok kuralını bozmadan çevre bilgisi:

- Barometrik yükseklik (`CMAltimeter`) → irtifa adaptasyonu takibi
- HealthKit ortam sıcaklığı/nem verisi olan antrenmanlarda sıcak adaptasyonu
- Gün ışığında geçen süre → sirkadiyen motora girdi
- Zaman dilimi değişimi → jet lag planlayıcısı (uçuştan önce kayma programı)

**Boyut:** Orta · **Risk:** Düşük

---

## Faz 31 — Sistem Derinliği

- App Intents + Siri: "Zenithium bugünkü toparlanmam ne?"
- Etkileşimli widget'lar, kilit ekranı, StandBy
- Antrenman sırasında Live Activity
- Focus filtresi: uyku moduna girince gece raporu
- Watch uygulaması: bilekte toparlanma, gün içi zorlanma, hızlı günlük girişi
- Control Center kontrolü (iOS 18)

**Boyut:** Büyük · **Risk:** Orta

---

## Faz 32 — Sakatlık ve Ağrı Haritası

- Vücut haritasına dokunup ağrı kaydı (0–10, tip, tarih)
- Ağrı ↔ yük korelasyonu: "sağ aşil ağrısı kaydettiğin 6 günün 5'i, önceki 48 saatte
  tempo koşusu olan günlerdi"
- Dönüş protokolü: sakatlık sonrası kademeli yük artışı takibi
- Asimetri: tek taraflı kayıtlar sol/sağ dengesizliğine bağlanır

**Boyut:** Orta · **Risk:** Düşük

---

## Durum — hepsi yapıldı

```
ÇEKİRDEK
  0–9   Recovery · Strain · Sleep · Kas · Sirkadiyen · Kan · Widget      ✓
  10    Günlük + korelasyon motoru                                        ✓
  11    Sağlık izleme (18 vital sinyal)                                   ✓
  12    Regl döngüsü farkındalığı                                         ✓
  13    Stres ve gün içi yük ayrımı                                       ✓
  14    Antrenman zekâsı (ACWR, monotonluk, form)                         ✓

MERCEKLER
  15    Dayanıklılık (kritik hız, tempo bölgeleri, yarış tahmini)         ✓
  16    Hibrit (Hyrox istasyonları, kompanse koşu)                        ✓
  17    Kuvvet (hacim, denge, 1TM, deload)                                ✓
  18    Sağlık merceği (basitleştirilmiş yüzeyler + Zenithium skoru)      ✓

BULUŞMA
  19    Reçete motoru (ters TRIMP, mercek-farkında)                       ✓
  20    Planlama ve periyodizasyon (hedef, faz, tapering)                 ✓

İKİNCİ DALGA
  21    Apple Watch uygulaması                                            ✓
  22    Sistem entegrasyonu (App Intents, Control Center, widget)         ✓
  23    Laboratuvar zekâsı (PDF içe aktarım, 50 belirteç)                 ✓
  24    Cihaz içi yapay zekâ (anlatıcı + güvenlik süzgeci)                ✓
  25    Görsel sistem (anatomik vücut haritası, grafik seti)              ✓
  26    Sağlık belge kasası                                               ✓
  27    Hekim raporu (PDF dışa aktarım)                                   ✓
  28    Erken uyarı (çok değişkenli sapma)                                ✓
  29    Hareket kalitesi ve Zenithium skoru                               ✓
  30    Çevresel bağlam (gün ışığı, saat dilimi)                          ✓
  32    Sakatlık ve ağrı haritası                                         ✓
```

**Bilerek yapılmayan tek şey — Faz 30'un irtifa kısmı.** `CMAltimeter` yalnızca canlı
göreli yükseklik verir, HealthKit yükseklik geçmişi tutmaz. İrtifa adaptasyonu takibi
arka planda örnekleme yolu, yeni bir seri ve onu ayakta tutan bir mekanizma demek —
küçük bir kullanıcı kesimi için yılda birkaç hafta işe yarayacak bir sinyal karşılığında
ciddi bir makine. Kendi fazını hak ediyor, bu fazın yan ürünü olarak sızdırılmayı değil.
Gerekçe `EnvironmentEngine`'in başında da yazılı.

---

## Bundan sonrası

Yeni faz değil, olgunlaştırma:

1. **Cihazda derleme ve gerçek veriyle doğrulama.** Bu turda yazılan hiçbir satır Xcode'dan
   geçmedi (konteynerde Swift yok). Motorların matematiği bağımsız doğrulandı, vücut
   haritası çizilip bakıldı, 180+ test yazıldı — ama derleyici görmedi.
2. **Kalibrasyon.** Reçete motorunun süre tabloları ve mercek eşleştirmeleri gerçek
   kullanımla ayarlanmalı; hepsi tek dosyada sabit olarak duruyor, tam da bunun için.
3. **App Store hazırlığı.** Developer Program, gizlilik beyanı, App Store metinleri.

## v2 mercek sırası (referans)

```
ÇEKİRDEK (herkes)                    MERCEKLER                  BULUŞMA
──────────────────                   ─────────                  ───────
10 Günlük+korelasyon ⭐  ──┐
11 Sağlık izleme        ──┤
12 Regl döngüsü         ──┼──►  14 Antrenman zekâsı  ──┐
13 Stres/gün içi yük    ──┘         │                  │
                                    ├── 15 Dayanıklılık│
                                    ├── 16 Hibrit ⭐   ├──►  19 Reçete ⭐⭐
                                    ├── 17 Kuvvet      │        │
                                    └── 18 Sağlık      ┘        ▼
                                                            20 Planlama
                                                                ▼
                                                       21 Watch · 22 Sistem
```

**İlk üç adım için önerim: 10 → 11 → 14.**

Sebebi: 10 her personaya aynı gün değer katar ve tamamen cihaz içi istatistiktir (risk
düşük, etki yüksek). 11 Apple Watch'ın sınırlarını zorlama sözünü somutlaştırır. 14 tüm
merceklerin ortak matematiğidir, hangi merceği önce yapacağımızdan bağımsız olarak gerekir.

Mercekler arasında **16 (Hibrit)** en yüksek farklılaşmayı sunuyor — Hyrox kitlesine doğru
bakan bir uygulama yok. Ama kendi kullanımın koşuysa 15 önce gelmeli.

---

## "Whoop rakibi oldu" ölçütü

Özellik sayısı değil, dört testin geçilmesi:

1. **İlk gün testi:** Hiç antrenman yapmayan biri ilk gün açtığında anlamlı bir şey görüyor mu?
2. **Otuzuncu gün testi:** Kullanıcı kendisi hakkında bilmediği bir şey öğrendi mi?
   (Günlük korelasyon motorunun işi bu.)
3. **Spor testi:** Hyrox sporcusu, koşucu ve powerlifter aynı uygulamadan farklı ama
   eşit derecede doğru cevaplar alıyor mu?
4. **Güven testi:** Uygulama bir sayı gösterdiğinde, kullanıcı nereden geldiğini
   görebiliyor mu?

---

## v4 — sonraki dalga

Performans, tasarım cilası ve yeni özellikler için ayrı bir belge var:
[`docs/ROADMAP-V4.md`](ROADMAP-V4.md). Kod taramasına dayanıyor; her madde
bir dosyayı ve o dosyadaki somut durumu gösteriyor.

---

## Faz 33 — Klinik Bağlam Katmanı (Clinical Context Layer)

Klinik veriler (laboratuvar tahlilleri ve Apple Watch EKG kayıtları) doğrudan karar mekanizmasının güvenilirlik katmanına bağlanmıştır.
* **Yönetici İlke**: Klinik veri skoru değiştirmez, skorun güvenilirliğini (epistemic confidence) ayarlar ve sistematik hata payını belirtir.
* **ClinicalContext**: `confidenceMultiplier` (taban: 0.70), `penaltyReasons`, `limitations`, `evidence`, `suppressesHRVRecovery`.
* **ClinicalModifierRegistry**: Hemoglobin, Ferritin, TSH, hsCRP, CK (>5x), EKG AFib, EKG Zayıf Okuma düzenleyicileri ve geçerlilik ufukları (staleness).
* **EKG Ölçümleri Paneli**: Hastane EKG PDF'leri için PR aralığı, QRS süresi, QT, QTc, QRS aksı biyobelirteç tanımları.
* **Şeffaflık & Rıza**: Tahlil detayında "Bu değer uygulamayı nasıl etkiliyor?" kartı, Ayarlar'da her düzenleyiciyi tek tek kapatabilme imkânı, HRV/RHR trendlerinde tarafsız tahlil tarih işaretleri.
