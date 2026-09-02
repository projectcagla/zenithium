# Bilimsel kaynaklar

Bu dosya elle yazılmaz — `Scripts/check-citations.py` tarafından
`Zenithium/Domain/Intelligence/EvidenceLibrary.swift` içinden üretilir. Elle
düzenlenirse bir sonraki preflight çalıştırmasında geri alınır; değişiklik
kaynağın kendisinde yapılmalıdır.

Her kaydın **ne göstermediği** satırı zorunludur. Bir çalışmanın neyi
kanıtlamadığını yazmak, neyi kanıtladığını yazmaktan daha çok düşünmeyi
gerektirir ve aşırı iddiayı kaynağında keser.

Toplam 16 kaynak: 12 doğrulanmış, 4 doğrulama bekliyor.

## Doğrulanmış kaynaklar

Kanıt tasarımına göre gruplanmış, güçlüden zayıfa.

### Derleme / konsensüs

#### BUCHHEIT-2014

Buchheit M (2014). *Monitoring training status with HR measures: do all roads lead to Rome?*. Frontiers in Physiology.

- **Tanımlayıcı:** doi:10.3389/fphys.2014.00073
- **Kanıt derecesi:** Derleme / konsensüs
- **Ne göstermiyor:** Nabız türevli hiçbir ölçütün tek başına yeterli olduğunu göstermez; tersine, her birinin farklı bir şeyi ölçtüğünü ve bağlam olmadan yorumlanamayacağını savunur.
- **Kullanan:** Zenithium/Domain/Intelligence/ScientificBoundaryRegistry.swift, Zenithium/Engines/RecommendationEngine.swift

#### GABBETT-2016

Gabbett TJ (2016). *The training-injury prevention paradox: should athletes be training smarter and harder?*. British Journal of Sports Medicine.

- **Tanımlayıcı:** doi:10.1136/bjsports-2015-095788
- **Kanıt derecesi:** Derleme / konsensüs
- **Ne göstermiyor:** Belirli bir akut:kronik oranının güvenli olduğunu göstermez ve rekreasyonel sporcularda doğrulanmamıştır. Bulguların çoğu takım sporu profesyonellerinden gelir.
- **Çelişki:** LOLLI-2019
- **Kullanan:** Zenithium/Domain/Intelligence/ScientificBoundaryRegistry.swift, Zenithium/Engines/RecommendationEngine.swift

#### HIRSHKOWITZ-2015

Hirshkowitz M, Whiton K, Albert SM, et al. (2015). *National Sleep Foundation's sleep time duration recommendations: methodology and results summary*. Sleep Health.

- **Tanımlayıcı:** doi:10.1016/j.sleh.2014.12.010
- **Kanıt derecesi:** Derleme / konsensüs
- **Ne göstermiyor:** Uyku süresi dışında hiçbir şey hakkında konuşmaz — uyku kalitesi, evre dağılımı veya zamanlaması bu bildirinin kapsamında değildir.
- **Kullanan:** Zenithium/Domain/Intelligence/ScientificBoundaryRegistry.swift, Zenithium/Engines/RecommendationEngine.swift

#### IMPELLIZZERI-2019

Impellizzeri FM, Marcora SM, Coutts AJ (2019). *Internal and external training load: 15 years on*. International Journal of Sports Physiology and Performance.

- **Tanımlayıcı:** doi:10.1123/ijspp.2018-0935
- **Kanıt derecesi:** Derleme / konsensüs
- **Ne göstermiyor:** İç yükün dış yükten üstün olduğunu söylemez; ikisinin farklı sorulara cevap verdiğini ve karıştırıldıklarında her ikisinin de anlamsızlaştığını savunur.
- **Kullanan:** Zenithium/Domain/Intelligence/ScientificBoundaryRegistry.swift

#### PLEWS-2013

Plews DJ, Laursen PB, Stanley J, Kilding AE, Buchheit M (2013). *Training adaptation and heart rate variability in elite endurance athletes: opening the door to effective monitoring*. Sports Medicine.

- **Tanımlayıcı:** doi:10.1007/s40279-013-0071-8
- **Kanıt derecesi:** Derleme / konsensüs
- **Ne göstermiyor:** Tek bir günün HRV değerinden o günün antrenman kapasitesini çıkarmayı desteklemez; savunduğu şey haftalık ortalamaların takibidir. Bir gecelik düşüşün nedenini de söylemez.
- **Kullanan:** Zenithium/Domain/Intelligence/ScientificBoundaryRegistry.swift, Zenithium/Engines/RecommendationEngine.swift

#### ROSS-2016

Ross R, Blair SN, Arena R, et al. (2016). *Importance of assessing cardiorespiratory fitness in clinical practice: a case for fitness as a clinical vital sign*. Circulation (American Heart Association scientific statement).

- **Tanımlayıcı:** doi:10.1161/CIR.0000000000000461
- **Kanıt derecesi:** Derleme / konsensüs
- **Ne göstermiyor:** Bilekten tahmin edilen VO₂max değerinin laboratuvar ölçümünün yerine geçtiğini göstermez; kanıtın tamamı doğrudan ölçüme dayanır.
- **Kullanan:** Zenithium/Engines/RecommendationEngine.swift

#### WATSON-2015

Watson NF, Badr MS, Belenky G, et al. (2015). *Recommended amount of sleep for a healthy adult: a joint consensus statement of the American Academy of Sleep Medicine and Sleep Research Society*. Sleep.

- **Tanımlayıcı:** doi:10.5665/sleep.4716
- **Kanıt derecesi:** Derleme / konsensüs
- **Ne göstermiyor:** Bir bireyin ihtiyacını vermez. Yetişkin nüfus için bir aralık bildirir; aralığın dışında uyuyan herkesin yetersiz uyuduğu anlamına gelmez.
- **Kullanan:** Zenithium/Domain/Intelligence/ScientificBoundaryRegistry.swift, Zenithium/Engines/RecommendationEngine.swift

### Randomize kontrollü

#### MINETTI-2002

Minetti AE, Moia C, Roi GS, Susta D, Ferretti G (2002). *Energy cost of walking and running at extreme uphill and downhill slopes*. Journal of Applied Physiology.

- **Tanımlayıcı:** doi:10.1152/japplphysiol.01177.2001
- **Kanıt derecesi:** Randomize kontrollü
- **Ne göstermiyor:** On antrenmanlı erkekte, koşu bandında ve ±%45 eğim aralığında ölçülmüştür. Arazide, farklı zeminlerde veya bu aralığın dışında doğrulanmamıştır.
- **Kullanan:** Zenithium/Domain/Intelligence/ScientificBoundaryRegistry.swift

### Kohort

#### FOSTER-1998

Foster C (1998). *Monitoring training in athletes with reference to overtraining syndrome*. Medicine & Science in Sports & Exercise.

- **Tanımlayıcı:** doi:10.1097/00005768-199807000-00023
- **Kanıt derecesi:** Kohort
- **Ne göstermiyor:** Yük artışının hastalık veya sakatlığa yol açtığını kanıtlamaz; yüksek yük ve ani artışların bunlarla birlikte görüldüğünü bildirir.
- **Kullanan:** Zenithium/Domain/Intelligence/ScientificBoundaryRegistry.swift

#### HULIN-2016

Hulin BT, Gabbett TJ, Lawson DW, Caputi P, Sampson JA (2016). *The acute:chronic workload ratio predicts injury: high chronic workload may decrease injury risk in elite rugby league players*. British Journal of Sports Medicine.

- **Tanımlayıcı:** doi:10.1136/bjsports-2015-094817
- **Kanıt derecesi:** Kohort
- **Ne göstermiyor:** Elit erkek rugby oyuncularında gözlenen bir ilişkidir; başka sporlara, kadınlara veya rekreasyonel sporculara aktarılabilirliği gösterilmemiştir.
- **Çelişki:** LOLLI-2019
- **Kullanan:** Zenithium/Domain/Intelligence/ScientificBoundaryRegistry.swift, Zenithium/Engines/RecommendationEngine.swift

### Gözlemsel

#### KAMINSKY-2015

Kaminsky LA, Arena R, Myers J (2015). *Reference standards for cardiorespiratory fitness measured with cardiopulmonary exercise testing: data from the Fitness Registry and the Importance of Exercise National Database*. Mayo Clinic Proceedings.

- **Tanımlayıcı:** doi:10.1016/j.mayocp.2015.07.026
- **Kanıt derecesi:** Gözlemsel
- **Ne göstermiyor:** Kayıt defteri ağırlıklı olarak ABD'li katılımcılardan oluşur; yüzdelik konumun başka nüfuslarda aynı anlamı taşıdığı gösterilmemiştir.
- **Kullanan:** Zenithium/Domain/Intelligence/ScientificBoundaryRegistry.swift, Zenithium/Engines/RecommendationEngine.swift

#### ROENNEBERG-2003

Roenneberg T, Wirz-Justice A, Merrow M (2003). *Life between clocks: daily temporal patterns of human chronotypes*. Journal of Biological Rhythms.

- **Tanımlayıcı:** doi:10.1177/0748730402239679
- **Kanıt derecesi:** Gözlemsel
- **Ne göstermiyor:** Kronotipe göre uyku saatini kaydırmanın bir fayda ürettiğini göstermez; kronotipin nüfusta nasıl dağıldığını betimler.
- **Kullanan:** Zenithium/Domain/Intelligence/ScientificBoundaryRegistry.swift, Zenithium/Engines/RecommendationEngine.swift

## Doğrulama bekleyen kaynaklar

Aşağıdaki kayıtların bulguları yerleşiktir; doğrulanamayan şey künyenin kendisidir
— basılı yılın çevrimiçi yıldan farklı olması, bir kitap bölümünün baskısı, ya da
başlığın tam olarak hatırlanamaması gibi. Bu kayıtlar uygulamada kullanılmaya
devam eder ama **hiçbiri bir tavsiyeyi destekleyemez**: dayandıkları kart en fazla
öneri seviyesinde kalır. Künyesi elle doğrulanan bir kaydın
`needsVerification` alanı `false` yapılmalıdır.

#### BANISTER-1991

Banister EW (1991). *Modeling elite athletic performance*. Physiological Testing of Elite Athletes (Human Kinetics).

- **Tanımlayıcı:** tanımlayıcı yok
- **Kanıt derecesi:** Mekanizma
- **Ne göstermiyor:** Model, bir sporcunun performansını ileriye dönük tahmin etmek için doğrulanmış değildir; antrenman yükünü tek bir sayıya indirgeyen bir muhasebe aracıdır.
- **Kullanan:** Zenithium/Domain/Intelligence/ScientificBoundaryRegistry.swift

#### LOLLI-2019

Lolli L, Batterham AM, Hawkins R, Kelly DM, Strudwick AJ, Thorpe RT, Gregson W, Atkinson G (2019). *Mathematical coupling causes spurious correlation within the conventional acute-to-chronic workload ratio calculations*. British Journal of Sports Medicine.

- **Tanımlayıcı:** doi:10.1136/bjsports-2017-098110
- **Kanıt derecesi:** Derleme / konsensüs
- **Ne göstermiyor:** Yük takibinin işe yaramadığını söylemez; akut değerin kronik değerin içinde yer almasının, gerçek bir ilişki olmasa bile korelasyon üreteceğini gösterir.
- **Çelişki:** GABBETT-2016, HULIN-2016
- **Kullanan:** Zenithium/Domain/Intelligence/ScientificBoundaryRegistry.swift, Zenithium/Engines/RecommendationEngine.swift

#### MORTON-1997

Morton RH (1997). *Modelling training and overtraining*. Journal of Sports Sciences.

- **Tanımlayıcı:** doi:10.1080/026404197367344
- **Kanıt derecesi:** Mekanizma
- **Ne göstermiyor:** Aşırı antrenmanı teşhis etmez ve bir eşik vermez; yorgunluk ile uyumun farklı hızlarda söndüğü bir matematiksel çerçeve sunar.
- **Kullanan:** Zenithium/Domain/Intelligence/ScientificBoundaryRegistry.swift

#### SMARR-2020

Smarr BL, Aschbacher K, Fisher SM, et al. (2020). *Feasibility of continuous fever monitoring using wearable devices*. Scientific Reports.

- **Tanımlayıcı:** doi:10.1038/s41598-020-78355-6
- **Kanıt derecesi:** Gözlemsel
- **Ne göstermiyor:** Bilek sıcaklığındaki bir sapmanın nedenini söylemez ve hastalık tespiti için doğrulanmış bir eşik vermez.
- **Kullanan:** Zenithium/Domain/Intelligence/ScientificBoundaryRegistry.swift
