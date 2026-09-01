# NORM-1 — VO₂max referans tablosunu takma

Bu dosya tek bir iş için var: `ReferenceNorms` tablosunu yayımlanmış bir kaynaktan
doldurup özelliği açmak. Tahminen on beş dakika, ve tamamı tek bir dosyada.

## Neden boş

Tablo v0.1'de kaldırıldı. Önceki içeriği "yaygın olarak tablolandığı hâliyle" aktarılmış ve
doğrulanmamış olarak işaretlenmişti; kontrol edildiğinde işaret haklı çıktı:

| hücre | tabloda yazan | yayımlanan (Kaminsky 2015) |
|---|---|---|
| erkek 20–29, 50. persentil | 48,0 | 48,0 ✓ |
| kadın 20–29, 50. persentil | 37,6 | 37,6 ✓ |
| erkek 70–79, 50. persentil | 28,1 | **24,4** ✗ |
| kadın 70–79, 50. persentil | 21,5 | **18,3** ✗ |

Kontrol edilebilen dört hücrenin ikisi yanlıştı ve yuvarlama farkı değildi. Kalan otuz iki
hücre hiç kontrol edilemedi — yayıncının tabloları bu makinenin ağ politikasından
erişilemiyor. App Store'a giden bir sağlık uygulamasında bu durumdaki sayıları yayımlamak,
NORM-1'in var olma sebebiydi. Sayılar tahmin edilmek yerine silindi.

## Hangi yayın

**"FRIEND sayıları" tek bir şey değil.** Dolaşımda birbiriyle çelişen üç yayın var:

| yayın | kapsam | test sayısı | erkek 20–29 50. | erkek 70–79 50. |
|---|---|---|---|---|
| Kaminsky ve ark. **2015**, *Mayo Clin Proc* 90(11):1515–1523 | 20–79 yaş | 7.783 koşu bandı | 48,0 | 24,4 |
| FRIEND-I küresel rapor (2014–2019) | — | 11.678 koşu bandı | 49,5 | — |
| Kaminsky ve ark. **2022**, *Mayo Clin Proc* 97(2):285–293 | 20–89 yaş | 16.278 koşu bandı | — | 30,8 |

Birini seç ve tabloyu **yalnızca ondan** doldur. İkisini karıştırmak, hiçbirini
kullanmamaktan kötüdür.

İki not:

- **80+ yaş bandı istiyorsan 2022'yi seçmen gerekiyor.** 2015 koşu bandı çalışması 20–79 ile
  bitiyor; ona 80+ satırı eklemek, kaynağın söylemediği bir şeyi söylemek olur.
- Koşu bandı (treadmill) ile bisiklet ergometresi tabloları **farklı**. Zenithium HealthKit'in
  VO₂max'ını okuyor; o da koşu/yürüyüş tabanlı, dolayısıyla koşu bandı tablosu doğru olan.

## Adımlar

### 1. Tabloyu doldur

`Zenithium/Domain/Norms/ReferenceNorms.swift` içinde iki sözlük var. Yaş bandının alt sınırı
anahtar, satır değer:

```swift
static let maleTreadmill: [Int: VO2MaxPercentiles] = [
    20: VO2MaxPercentiles(p10: 00.0, p25: 00.0, p50: 48.0, p75: 00.0, p90: 00.0),
    30: VO2MaxPercentiles(p10: 00.0, p25: 00.0, p50: 00.0, p75: 00.0, p90: 00.0),
    40: VO2MaxPercentiles(p10: 00.0, p25: 00.0, p50: 00.0, p75: 00.0, p90: 00.0),
    50: VO2MaxPercentiles(p10: 00.0, p25: 00.0, p50: 00.0, p75: 00.0, p90: 00.0),
    60: VO2MaxPercentiles(p10: 00.0, p25: 00.0, p50: 00.0, p75: 00.0, p90: 00.0),
    70: VO2MaxPercentiles(p10: 00.0, p25: 00.0, p50: 24.4, p75: 00.0, p90: 00.0)
]
```

`femaleTreadmill` aynı bantları taşımak zorunda — test bunu kontrol ediyor.

Birim **mL·kg⁻¹·min⁻¹**. Yayın virgüllü yazıyorsa Swift'te nokta kullan (`48.0`).

### 2. Kaynağı söyle

```swift
static let source: String? = "Kaminsky 2015"    // ya da "Kaminsky 2022"
```

Bu dize `publishedMedians` sözlüğünün anahtarıyla **birebir** aynı olmalı; test çıpaları
oradan buluyor.

2022'yi seçtiysen `publishedMedians["Kaminsky 2022"]` şu an yalnızca 70 bandını taşıyor.
Özette geçen başka 50. persentil varsa oraya ekle — çıpa ne kadar çoksa transkripsiyon o
kadar denetlenmiş olur.

### 3. Bayrağı çevir

```swift
static let isPublicationVerified = true
```

### 4. 80+ bandı eklediysen

`band(for:)` kapsanan bantları tablodan türetiyor, yani `80: ...` satırını eklemek yeterli.
Başka hiçbir sabiti değiştirmen gerekmiyor.

### 5. Koştur

```sh
./Scripts/preflight.sh
xcodebuild test -project Zenithium.xcodeproj -scheme Zenithium \
          -destination "platform=iOS Simulator,name=iPhone 16 Pro"
```

## Test seni neye karşı koruyor

`ReferenceNormsTests` ve `ScientificBoundaryTests` şunları otomatik bakıyor:

| kontrol | yakaladığı |
|---|---|
| bayrak ↔ tablo | Bayrağı çevirip tabloyu doldurmayı unutmak, ya da tersi |
| kaynak ↔ bayrak | Doğrulanmış bir tablonun kaynağını söylememesi |
| iki cinsiyet aynı bantlar | Bir cinsiyette olan bandın öbüründe olmaması |
| satır monotonluğu | İki persentil sütununun yer değiştirmesi |
| ortancalar yaşla azalıyor | Bir satırın yanlış banda yazılması |
| yayımlanmış çıpalar | `source`'un işaret ettiği yayının özetinde geçen 50. persentillerle uyuşmama |
| kapsam dışı yaşlar | 18 altı ve tablonun üstündeki yaşlara bant uydurulması |

Yani yanlış aktarılmış bir tablo testte düşer, cihazda değil.

## Açık kalırsa ne olur

Hiçbir şey bozulmaz. `isPublicationVerified` false kaldığı sürece hayati işaretler ekranı
VO₂max karşılaştırması göstermiyor; uygulamanın geri kalanı bundan etkilenmiyor. Özelliği
0.2'ye bırakmak tamamen geçerli bir karar.
