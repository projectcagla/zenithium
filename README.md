# Zenithium

**Günün ritmini anla. Kararının nedenini gör.**

Zenithium, Apple Watch ve Apple Sağlık kayıtlarını toparlanma, uyku ve antrenman yükü için anlaşılır bir günlük özete dönüştürür. Her skorun ölçümleri, hesabı ve sınırları görülebilir. Hesap açılmaz; abonelik, reklam, analiz SDK’sı veya uygulamaya ait sunucu yoktur.

[Tanıtım](https://projectcagla.github.io/zenithium/) · [Gizlilik](https://projectcagla.github.io/zenithium/privacy.html) · [Destek](https://projectcagla.github.io/zenithium/support.html) · [Bilimsel kaynaklar](docs/EVIDENCE.md)

## 1.1’de neler var?

- **Dünden bugüne:** Toparlanma farkının ölçüm başına katkısı ve taban/hesap değişimi ayrı gösterilir. Bu ayrıştırma matematiksel açıklamadır; neden-sonuç kanıtı değildir.
- **Tahliller:** PDF, fotoğraf veya manuel giriş; cihaz içi metin tanıma; kayıt öncesi her satır için onay; belge silme, geçmiş ve antrenmanla eşzamanlılık görünümü. Raporda referans yoksa uygulama aralık uydurmaz.
- **Sana göre ayarlar:** Uyku saatleri, birimler, görünüm, karar tercihi, bildirimler, kişisel taban ve bağlantı durumu. Hastalık, seyahat, rakım veya vardiya bağlamı tarih aralığıyla günlük planı sınırlar.
- **Kuvvet ve günlük:** 16 kas grubunda kayıt temelli yorgunluk modeli; egzersiz başına hacim ve tahmini 1TM geçmişi; davranış örüntülerinde örneklem sayısı ve etki büyüklüğü.
- **Yarış hazırlığı:** Tarih, mesafe ve süre hedefi; kritik hız modeliyle sınırlı karşılaştırma; açıkça etiketlenmiş haftalık yük senaryosu. Bir yarış sonucunun garantisi verilmez.
- **Apple Watch:** Telefonla gerçek eşitleme, çevrimdışı set ve günlük kaydı, toparlanma/karar komplikasyonu ve Smart Stack. Telefonda kaydedildiği onaylanmadan saat kayıtları kuyruktan silinmez.
- **Veri kontrolü:** `.zenithium` arşivinde ölçümler, günlük, hedefler, tercihler ve belge asılları. Yerel verileri silme akışı eşlenmiş saate de silme sınırı gönderir; çevrimdışı saat bunu bağlantı yeniden kurulduğunda uygular. Apple Sağlık’taki asıl kayıtlar kullanıcıya aittir.

## Ölçümün sınırları

Toparlanma puanı klinik olarak doğrulanmış bir sağlık testi değildir. HRV burada Apple Sağlık’ın **SDNN** ölçümüdür. Araştırmaların tamamı aynı sensörü, örneklemi veya HRV yöntemini kullanmaz. Kaynak künyesinin doğrulanması uygulama algoritmasının doğrulandığı anlamına gelmez.

Kişisel taban 14 geçerli gece örneğiyle olgunlaşır. İlk 5 örnekten önce skor gösterilmez; 5–13 örnekte ürünün başlangıç değerleriyle harmanlanan bir ön değerlendirme vardır. Gösterilen kapsam katsayısı, bir tahminin doğru çıkma olasılığı değildir. Eksik günler sıfır yük veya normal ölçüm olarak doldurulmaz.

Uzun vadeli indeks bileşenlerini açar; **biyolojik yaş, yaşam süresi veya hastalık riski hesaplamaz**. Kanıtlanmış bir güven aralığı olmadığı için böyle bir aralık üretilmez. Kanama takviminden kişiye özgü hormon fazı veya HRV düzeltmesi çıkarılmaz. Tıbbi endişeler için bir sağlık uzmanına başvurun.

## Cihazlar ve gizlilik

- iPhone: **iOS 18 ve üzeri**. Bu sürümün cihaz ailesi iPhone’dur; ayrı bir iPad arayüzü desteklenmez.
- Apple Watch: **watchOS 11 ve üzeri**. Günlük karar telefonda hesaplanır; saat kaydedilmiş son özetin tarihini korur.
- Arayüz Türkçedir. Sayılar ve birimler bölgesel tercihlere göre gösterilir.
- Apple Foundation Models uygun iOS 26 cihazlarında isteğe bağlı anlatım katmanıdır. Çerçeve koşullu ve zayıf bağlanır. Model yalnızca sayısız bir başlığı yeniden ifade edebilir; sayısal gövde, kanıtlar, skor ve karar hesap kodundan gelir. Desteklenmeyen cihazlarda aynı hesaplar hazır metinlerle çalışır.
- Uygulama kodunda ağ isteği veya üçüncü parti paket yoktur. Apple Sağlık eşitlemesi, WatchConnectivity ve kullanıcının seçtiği dosya paylaşımı Apple’ın sistem hizmetleridir. Bunlar için “cihazdan hiçbir veri çıkamaz” iddiasında bulunulmaz.

## Geliştirme ve doğrulama

Yetkili proje tanımı **[project.yml](project.yml)** dosyasıdır. Depodaki Xcode projesi deterministik üreticiyle eşitlenir. Swift 6 ve tam eşzamanlılık denetimi kullanılır; Release derlemesinde Swift uyarıları hatadır.

```sh
./Scripts/preflight.sh
xcodebuild test -project Zenithium.xcodeproj -scheme Zenithium \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
xcodebuild archive -project Zenithium.xcodeproj -scheme Zenithium \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath /tmp/Zenithium.xcarchive
```

Apple Watch, HealthKit ve ortak uygulama alanı için geliştirici hesabında ilgili yetkiler gerekir. Üretici sürüm ve derleme numarasını `project.yml` üzerinden alır. Test sonuçları ve sürüm sınırları [faz raporlarında](docs/V1_1-PHASE3.md) tutulur; dokümantasyonda sabit bir test sayısı vaat edilmez.

## Hesap modülleri

Aşağıdaki tablo `Scripts/generate-engine-catalog.py` tarafından kaynak dosyalarından üretilir. Liste, dosyanın varlığını ve giriş noktalarını gösterir; tek başına bilimsel doğrulama veya bütün giriş noktalarının ürün içinde etkin olduğu iddiası değildir. `CycleEngine` faz düzeltmesi bu sürümün günlük karar yolunda kapalıdır.

<!-- ENGINE-CATALOG:START -->
Kodda **30 hesap modülü** var.

| Modül | Kaynaktaki giriş noktaları |
|---|---|
| [BaselineEngine](Zenithium/Engines/BaselineEngine.swift) | `update`, `rebuild`, `scoringBaseline`, `calibrationProgress` |
| [CircadianEngine](Zenithium/Engines/CircadianEngine.swift) | `arc`, `amplitudeScale` |
| [ClinicalContextEngine](Zenithium/Engines/ClinicalContextEngine.swift) | `assess` |
| [CorrelationEngine](Zenithium/Engines/CorrelationEngine.swift) | `analyse`, `rank`, `strongestOutcome`, `summary` |
| [CycleEngine](Zenithium/Engines/CycleEngine.swift) | `cycleStarts`, `measuredCycleLength`, `phase`, `confidence`, `partition`, `phaseBaseline`, `phaseShift`, `context` |
| [DataQualityEngine](Zenithium/Engines/DataQualityEngine.swift) | `assess` |
| [DecisionEngine](Zenithium/Engines/DecisionEngine.swift) | `decide` |
| [EnduranceEngine](Zenithium/Engines/EnduranceEngine.swift) | `fit`, `predictions`, `paceZones`, `zone`, `decoupling`, `gradeAdjustedPace`, `pace`, `gradeCostRatio`, `summary` |
| [EnvironmentEngine](Zenithium/Engines/EnvironmentEngine.swift) | `daylightContext`, `recentTimeZoneShift`, `isAdapting` |
| [FatigueEngine](Zenithium/Engines/FatigueEngine.swift) | `project`, `sleepModifier`, `halfLifeHours`, `decayConstant`, `impact`, `projectedReadiness` |
| [HeatAcclimationEngine](Zenithium/Engines/HeatAcclimationEngine.swift) | `state`, `increment`, `effectiveTemperature`, `exposures`, `summary` |
| [HybridEngine](Zenithium/Engines/HybridEngine.swift) | `analyse`, `compromisedRunning`, `degradationSlope`, `weakestStation`, `systemRatio`, `muscleImpacts`, `guidance` |
| [LabInsightEngine](Zenithium/Engines/LabInsightEngine.swift) | `observations` |
| [LongevityEngine](Zenithium/Engines/LongevityEngine.swift) | `score`, `percentileScore` |
| [NarrativeEngine](Zenithium/Engines/NarrativeEngine.swift) | `briefing`, `headline`, `body`, `supportingPoints`, `dominantDriver`, `phrase`, `recentMean` |
| [PainEngine](Zenithium/Engines/PainEngine.swift) | `insights`, `precedingLoad`, `lateralityImbalance` |
| [PlanEngine](Zenithium/Engines/PlanEngine.swift) | `position`, `phase`, `projectedForm`, `taperProjection`, `summary`, `taperSummary` |
| [PrescriptionEngine](Zenithium/Engines/PrescriptionEngine.swift) | `prescribe`, `cycleContextLine`, `sessionKinds`, `session`, `defaultMinutes`, `paceBand`, `trainingWindow` |
| [RacePlanEngine](Zenithium/Engines/RacePlanEngine.swift) | `plan`, `suggestedFinish`, `splitBounds` |
| [RecommendationEngine](Zenithium/Engines/RecommendationEngine.swift) | `recommendations`, `baseConfidence`, `dataQualityCard`, `sleepDebtCard`, `autonomicCard`, `loadRatioCard`, `cardiorespiratoryCard`, `circadianCard` |
| [RecoveryChangeEngine](Zenithium/Engines/RecoveryChangeEngine.swift) | `compare` |
| [RecoveryEngine](Zenithium/Engines/RecoveryEngine.swift) | `compute`, `targetCeiling`, `unavailable`, `calibrating` |
| [SessionShapeEngine](Zenithium/Engines/SessionShapeEngine.swift) | `shapes`, `summary` |
| [SleepDebtEngine](Zenithium/Engines/SleepDebtEngine.swift) | `ledger`, `socialJetlag`, `isFreeDay`, `summary` |
| [SleepScoreEngine](Zenithium/Engines/SleepScoreEngine.swift) | `compute`, `need`, `validity`, `sleepDebt`, `napCredit`, `resolveNaps`, `totalNapSeconds`, `longestAsleepBlock`, `midpoint`, `minutesFromLocalMidnight`, `midpointBaseline`, `stageSeconds` |
| [StrainEngine](Zenithium/Engines/StrainEngine.swift) | `compute`, `strain`, `trimp`, `minutes`, `sessionLoad`, `resolveMaxHeartRate` |
| [StrengthEngine](Zenithium/Engines/StrengthEngine.swift) | `estimateOneRepMax`, `oneRepMaxes`, `normalizedName`, `weeklyVolume`, `balance`, `deloadSignal`, `progressionSummary`, `exerciseProgress` |
| [StressEngine](Zenithium/Engines/StressEngine.swift) | `analyse`, `buckets`, `recoveryWindows`, `recoverySummary` |
| [TrainingLoadEngine](Zenithium/Engines/TrainingLoadEngine.swift) | `analyse`, `densifiedSeries`, `contiguousSeries`, `exponentialTrack`, `monotony`, `fitnessFatigue`, `projectedRatio`, `projectedInstantRatio`, `loadCeiling`, `summary`, `monotonySummary` |
| [VitalsEngine](Zenithium/Engines/VitalsEngine.swift) | `reading`, `readings`, `deviationScore`, `deviationSummary`, `slopePerDay` |
<!-- ENGINE-CATALOG:END -->

`LabReportParser` ve `BiomarkerCatalog` ayrıca tahlil okuma ve ad eşleştirmesini sağlar; motor sayısına eklenmez. Görüşler ekrana ait durumları, orkestrasyon veri akışını, saklama katmanı kayıtları, hesap modülleri ise sayısal işlemleri yönetir.

## Değişiklik kayıtları

[Regresyon envanteri](docs/REGRESYON.md) · [Tahlil modülü](docs/V1_1-PHASE1.md) · [Ayarlar ve veri taşınabilirliği](docs/V1_1-PHASE2.md) · [1.1 doğrulama raporu](docs/V1_1-PHASE3.md)
