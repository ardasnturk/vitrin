# Vitrin for Mac: Ascelerate karşılaştırması ve yönetim paneli yol haritası

Tarih: 3 Kasım 2026. Kaynak: github.com/keremerkan/ascelerate (README ve kaynak dizini), Vitrin'in bugünkü kodu.

## Ascelerate ne yapıyor

Ascelerate iki parçadan oluşuyor. Depodaki kısım bir Swift komut satırı aracı: App Store Connect'in OpenAPI tanımından üretilmiş bir istemci (`ASCKit`) ve üstünde `apps`, `builds`, `testflight`, `iap`, `sub`, `reviews`, `product-pages`, `reports`, `ads`, `screenshot` komut grupları. Uygulama (ascelerate.app) bu istemcinin üzerine kurulu, ama kaynağı depoda yok; TestFlight beta'da.

Sizin işaret ettiğiniz özellikler:

- **Onboarding tek adım.** `ascelerate configure` Key ID, Issuer ID ve .p8 yolunu bir kez soruyor; .p8 `~/.ascelerate/` altına yalnızca sahibinin okuyabileceği izinlerle kopyalanıyor. Sonrasında `apps list` takımdaki tüm uygulamaları API'den listeliyor; proje klasörü gerekmiyor.
- **Tek anahtar, tüm uygulamalar.** Anahtar takıma ait; uygulama seçimi API'den gelen listeyle yapılıyor. Başka bir takım için ortam değişkenleri (`ASCELERATE_KEY_ID` vb.) kullanılıyor.
- **Kapsam ASC'nin tamamı.** Sürümler ve ürün sayfası metinleri, ekran görüntüleri ve önizlemeler, TestFlight, uygulama içi satın alma ve abonelikler, özel ürün sayfaları ve PPO testleri, yorumlar ve yanıtlar, sertifika/profil, satış ve analitik raporları, Apple Ads.
- **Yapay zeka araç içinde değil.** Claude Code ve benzerleri için bir "skill" dağıtıyor; `screenshot setup-prompt` bir ajana ekran görüntüsü düzeneği kurduran bir yönerge basıyor. Metin üretimi yok.

## Vitrin bugün nerede

Vitrin'in çekirdeği tersine kurulu: proje klasörü merkezde, ASC yalnızca yükleme hedefi. Güçlü yanı Ascelerate'de olmayan şey: kodu okuyup mağaza metnini, anahtar kelimeleri, ekran görüntülerini ve videoları Claude ile üretmek, doğrulamak ve onay kapısından geçirip yüklemek.

Bu turda kapanan boşluklar:

- Ayarlar → Hesap: Key ID, Issuer ID ve .p8 bir kez giriliyor; her projeye `.env` yazmak gerekmiyor. Kendi `.env`'inde anahtarı olan proje onu kullanmaya devam ediyor.
- Claude modeli seçilebiliyor (Ayarlar → Genel ya da Claude sütunu başlığı); her çalıştırma hangi modeli kullandığını gösteriyor.
- Brief penceresi gerçekten açılıyor ve kapanıyor; araç çubuğu sadeleşti; Claude sütunu sürüklenerek genişliyor.

Kalan fark: Vitrin hâlâ "proje ekle" ile başlıyor. Anahtar girildikten sonra takımın uygulamalarını listelemiyor; bir uygulamanın ASC'deki mevcut sürümünü, metnini, görsellerini, TestFlight ve yorumlarını göstermiyor.

## Hedef: tek uygulama, iki giriş kapısı

Önerilen model, Ascelerate'in "ASC'nin yerel arayüzü" fikrini Vitrin'in üretim hattına kapı yapmak:

1. **Hesap kurulumu** uygulamanın ilk ekranı olur (bugünkü Hesap sekmesi). Anahtar girilince `asc` CLI ya da doğrudan ASC API ile takımın uygulamaları listelenir.
2. **Kenar çubuğu uygulama listesi olur**, proje listesi değil. Her uygulamanın yanında ASC'deki durum (hazırlanıyor, incelemede, satışta) ve varsa eşleşen yerel proje klasörü.
3. **Bir uygulamanın sayfaları:** Genel bakış (sürüm, durum, derlemeler), Mağaza metni (ASC'deki canlı metin, yerel üretilmiş metinle yan yana ve fark), Görseller (ASC'deki setler ile yerel setler), TestFlight, Yorumlar, Ürün sayfaları. Yerel proje bağlı değilse sayfalar salt ASC verisini gösterir ve düzenler.
4. **"Claude ile üret" her sayfada bir eylem:** yerel proje bağlıysa bugünkü akış (analiz → araştırma → metin → görsel → inceleme → yükleme). Bağlı değilse "Projeyi bağla" tek tıkla `vitrin init` ve klasör seçimi.

## Yol haritası (öncelik sırasıyla)

### 1. Uygulama listesi ve ASC okuma katmanı (2–3 gün)
- CLI'ya `vitrin asc apps --json`, `vitrin asc app <bundleId> --json` (sürümler, yerelleştirmeler, ekran görüntüsü setleri, derlemeler). `packages/upload`'daki ASC istemcisi (`asc-client.ts`) zaten JWT ve sayfalama yapıyor; okuma uçları eklenir.
- Mac uygulamasında kenar çubuğu: "Uygulamalar" bölümü (API'den), "Projeler" bölümü (yerel). Bir proje `vitrin.config.yaml`'daki bundle id ile uygulamaya eşlenir.
- Sonuç: anahtar girildiği anda takımın uygulamaları görünür; Ascelerate'deki ilk izlenim yakalanır.

### 2. Canlı listeleme sayfası (2 gün)
- Bugünkü `live-listing.ts` ASC'deki metni okuyor; bunu Mağaza metni sayfasında "ASC'de olan / Vitrin'in ürettiği" olarak iki sütun ve fark görünümü yapılır. Değişiklikleri doğrudan ASC'ye yazma (Vitrin'in onay kapısından geçerek) eklenir.
- Görseller sayfasında ASC'deki setlerin küçük resimleri; yerel setle karşılaştırma.

### 3. TestFlight, derlemeler ve yorumlar (3 gün)
- Salt okunur başlangıç: derleme listesi, işleme durumu, "What to Test", test grupları; müşteri yorumları ve yanıt yazma (Claude taslak önerir, siz gönderirsiniz).
- Sürümü incelemeye gönderme zaten `vitrin submit`'te; uygulamadan sürüm oluşturma ve derleme seçme eklenir.

### 4. Hesap ve güvenlik (1 gün)
- Birden çok takım anahtarı (anahtar listesi, proje başına seçim).
- Anahtarı Keychain'de tutma seçeneği; şu an dosya izinleriyle (Ascelerate ile aynı yaklaşım).
- İmzalama ve notarization; Sparkle ile güncelleme.

### 5. Sonraki adımlar
- Uygulama içi satın alma ve abonelik fiyatları, özel ürün sayfaları, PPO testleri (Vitrin'in CPP üretimi var; ASC tarafındaki yönetim eklenir).
- Satış ve analitik raporları.

## Önerilen başlangıç

1. adım tek başına en çok şeyi değiştiriyor: uygulama bir "proje aracı" olmaktan çıkıp "takımın ASC paneli" olur, Vitrin'in üretim hattı da her uygulamanın altında bir eylem olarak kalır. CLI'daki ASC istemcisi hazır olduğu için maliyeti düşük.
