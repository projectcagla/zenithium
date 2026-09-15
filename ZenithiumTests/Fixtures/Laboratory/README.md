# Laboratuvar PDF test kaynakları

Üç PDF düzeni iki kurumun kamuya açık, kimlik alanları boş veya örnek bilgilerle doldurulmuş tanıtım belgelerinden alınmıştır. Gerçek kullanıcı verisi kullanılmaz. Yalnızca gerekli sayfa korunur; uygulama paketine eklenmez. Bunlar okuma testleridir; raporların klinik açıklamaları veya referansları ürün tavsiyesi olarak benimsenmez.

## duzen-annotated

- Kaynak: [duzen-annotated](https://www.duzen.com.tr/artFiles/EK%201.%20Rapor%20Format%C4%B1n%C4%B1n%20Temel%20Biles%CC%A7enleri.pdf), sayfa 1.
- Düzen: Açıklamalı görsel rapor; sonuç, SI birimi, referans ve önceki sonuç sütunları.
- SHA-256: `c93f79ef9f9bca288f9698e32035fb904a6adbeddb85ea99e4b9c84190d503b8`.

## biruni-text-columns

- Kaynak: [biruni-text-columns](https://biruni.com.tr/wp-content/uploads/2025/02/hucresel-check-up-paneli-rapor.pdf), sayfa 1.
- Düzen: Metin PDF; görsel sütun sırası PDF nesne sırasından farklı.
- SHA-256: `0b8befa880873723726e94632ac857d85e86fa1be77b68c89ffca5bda52846c6`.

## biruni-encoded-font

- Kaynak: [biruni-encoded-font](https://biruni.com.tr/wp-content/uploads/2024/06/bagisiklik-paneli.pdf), sayfa 2.
- Düzen: Önceki sonuç sütunlu rapor; bazı alanlarında bozuk karakter eşlemesi var. Okunabilen metin korunur, okunamayan sayfada OCR kullanılır.
- SHA-256: `24625cf56f79edff056f4bd619b1dcdc5c183428c30fa8b97ecc956087e482f4`.

Beklenen sonuçlar kaynak sayfalar görsel olarak incelenerek yazılmıştır; test başarısız olduğunda otomatik güncellenmez. OCR hatası bir ölçümün doğruluğunu garanti etmez; uygulamada her satır ayrıca onaylanır.
