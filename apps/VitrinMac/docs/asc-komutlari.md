# asc komutları: arayüz iş listesi

`asc` 5.17.1'in 1315 komutu, uygulamada durdukları sekmeye göre. Bir sekme işlenince komutu çalışıp çıktısı arayüzde okunur biçimde görünenler buradan silinir.

Her komut `VitrinMac/Resources/asc-commands.json` kataloğundan sekmesindeki "App Store Connect'te daha fazlası" kartlarına gelir: okuma komutları yerinde açılıp kendiliğinden çalışır, değişiklik yapanlar kısa formlu butondur. Katalog `scripts/asc-catalog.py` ile yenilenir.

Burada kalanlar iki gruptur:

- **Çalıştırılamadı:** okuma komutu, ama bu hesapta gereken veri yok veya izin gerekiyor. Arayüzde yeri var, çıktısı gerçek veriyle görülmedi.
- **Gerçek hesapta denenmedi:** App Store Connect'te bir şeyi değiştiren komutlar. Butonu ve formu var; yayındaki uygulamalara dokunmamak için hiçbiri çalıştırılmadı.

| Sekme | Komut | Kalan okuma | Çalıştırılamadı | Denenmedi |
|---|---|---:|---:|---:|
| Durum | 57 | 0 | 7 | 34 |
| Mağaza metni | 107 | 0 | 18 | 61 |
| Görseller | 122 | 0 | 29 | 81 |
| Derlemeler | 46 | 0 | 13 | 20 |
| TestFlight | 69 | 0 | 9 | 33 |
| Yorumlar | 9 | 0 | 2 | 6 |
| Satın almalar | 219 | 0 | 61 | 120 |
| Analitik | 19 | 0 | 7 | 9 |
| Diğer | 318 | 0 | 100 | 178 |
| Takım: Kullanıcılar | 17 | 0 | 5 | 6 |
| Takım: Cihazlar | 6 | 0 | 0 | 4 |
| Takım: Sertifikalar, profiller, bundle ID'ler | 70 | 0 | 10 | 46 |
| Takım: Raporlar ve finans | 6 | 0 | 1 | 5 |
| Takım: Otomasyon | 61 | 0 | 21 | 32 |
| Takım: Apple Ads | 186 | 0 | 90 | 94 |
| Takım: Hesap | 3 | 0 | 1 | 0 |

## Durum

### Çalıştırılamadı

- `review attachments-get`: Ek (`review attachments-get: failed to fetch: The specified resource`)
- `review attachments-list`: Ekler (`--review-detail is required`)
- `review details-get`: İnceleme ayrıntıları (`review details-get: failed to fetch: The specified resource doe`)
- `submit status`: Gönderim durumu (`--id or --version-id is required`)
- `versions links`: App Store sürümü bağlantıları (`--type is required; must be one of: ageRatingDeclaration, alter`)
- `versions rating-reset view`: Puan sıfırlama ayrıntıları (`Session expired.`)
- `versions view`: App Store sürümü ayrıntıları (`versions view: resolve version: app store version not found for`)

### Gerçek hesapta denenmedi

- `publish appstore`: App Store'da yayınla
- `publish testflight`: TestFlight'ta yayınla
- `release stage`: Yayını hazırla
- `release-notes generate`: Sürüm notları oluştur
- `review attachments-delete`: Eki sil
- `review attachments-upload`: Ek yükle
- `review details-create`: İnceleme ayrıntıları oluştur
- `review details-update`: İnceleme ayrıntılarını güncelle
- `review items add`: İnceleme öğesi ekle
- `review items remove`: İnceleme öğesini kaldır
- `review items update`: İnceleme öğesini güncelle
- `review items-add`: İnceleme öğesi ekle
- `review items-remove`: İnceleme öğesini kaldır
- `review items-update`: İnceleme öğesini güncelle
- `review submissions-cancel`: İnceleme gönderimini iptal et
- `review submissions-create`: İnceleme gönderimi oluştur
- `review submissions-submit`: İncelemeye gönder
- `review submissions-update`: İnceleme gönderimini güncelle
- `review submit`: Sürümü incelemeye gönder
- `submit cancel`: Gönderimi iptal et
- `validate iap`: Uygulama içi satın almaları denetle
- `validate subscriptions`: Abonelikleri denetle
- `validate testflight`: TestFlight derlemesini denetle
- `versions attach-build`: Derleme ekle
- `versions create`: App Store sürümü oluştur
- `versions delete`: App Store sürümü sil
- `versions phased-release create`: Aşamalı yayın oluştur
- `versions phased-release delete`: Aşamalı yayın sil
- `versions phased-release update`: Aşamalı yayın güncelle
- `versions promotions create`: Promosyon oluştur
- `versions rating-reset create`: Puan sıfırlama oluştur
- `versions rating-reset delete`: Puan sıfırlama sil
- `versions release`: Sürümü yayınla
- `versions update`: App Store sürümü güncelle

## Mağaza metni

### Çalıştırılamadı

- `accessibility view`: Erişilebilirlik beyanı ayrıntıları (`--id is required`)
- `app-tags territories`: Etiket bölgeleri (`--id is required`)
- `app-tags view`: Uygulama etiketi ayrıntıları (`--id is required`)
- `apps ci-product view`: Xcode Cloud ürünü (`apps ci-product view: failed to fetch: The specified resource d`)
- `apps public prices`: Herkese açık App Store fiyatı (`apps public prices: app not found: 6759182280`)
- `apps public rank`: Arama sıralaması (`--term is required`)
- `apps public search`: App Store'da ara (`--term is required`)
- `apps public view`: Herkese açık App Store sayfası (`apps public view: app not found: 6759182280`)
- `apps search-keywords list`: Arama anahtar kelimeleri (`apps search-keywords list: failed to fetch: A parameter has an `)
- `categories view`: Kategori ayrıntıları (`--category-id is required`)
- `encryption declarations app view`: Uygulama (`--id is required`)
- `encryption declarations app-encryption-declaration-document view`: Beyan belgesi (`--id is required`)
- `encryption declarations view`: Beyan ayrıntıları (`--id is required`)
- `encryption documents view`: Belge ayrıntıları (`--id is required`)
- `metadata keywords audit`: Anahtar kelime denetimi (`metadata keywords audit: app store version not found for versio`)
- `metadata keywords diff`: Anahtar kelime farkları (`--dir is required`)
- `metadata status`: Meta veri onay durumu (`metadata plan artifact not found at .asc/metadata/review/plan.j`)
- `metadata validate`: Meta veri doğrulaması (`--dir is required`)

### Gerçek hesapta denenmedi

- `accessibility create`: Erişilebilirlik beyanı oluştur
- `accessibility delete`: Erişilebilirlik beyanını sil
- `accessibility update`: Erişilebilirlik beyanını güncelle
- `age-rating edit`: Yaş derecelendirmesini güncelle
- `app-setup availability edit`: Kullanılabilirliği düzenle
- `app-setup categories set`: Kategorileri belirle
- `app-setup info set`: Uygulama bilgilerini güncelle
- `app-setup localizations upload`: Yerelleştirmeleri yükle
- `app-setup pricing set`: Fiyatlandırmayı belirle
- `app-tags territories-links`: Etiket bölge bağlantıları
- `app-tags update`: Uygulama etiketini güncelle
- `apps content-rights edit`: İçerik haklarını düzenle
- `apps info edit`: Sürüm üst verilerini güncelle
- `apps info relationships primary-category`: Birincil kategori
- `apps info relationships primary-subcategory-one`: Birincil alt kategori 1
- `apps info relationships primary-subcategory-two`: Birincil alt kategori 2
- `apps info relationships secondary-category`: İkincil kategori
- `apps info relationships secondary-subcategory-one`: İkincil alt kategori 1
- `apps info relationships secondary-subcategory-two`: İkincil alt kategori 2
- `apps public descriptions`: Herkese açık App Store açıklaması
- `apps published`: Yayınlanmış uygulamalar
- `apps registry pull`: Uygulama kaydını eşitle
- `apps remove-beta-testers`: Test kullanıcılarını kaldır
- `apps rename`: Uygulamayı yeniden adlandır
- `apps search-keywords set`: Anahtar kelimeleri ayarla
- `apps update`: Uygulamayı güncelle
- `apps wall submit`: Wall of Apps'e gönder
- `categories parent`: Üst kategori
- `categories set`: Uygulama kategorilerini ayarla
- `categories subcategories`: Alt kategoriler
- `encryption declarations assign-builds`: Derlemeleri ata
- `encryption declarations create`: Beyan oluştur
- `encryption declarations exempt-declare`: Muafiyet bildir
- `encryption documents upload`: Belge yükle
- `eula create`: Lisans sözleşmesi oluştur
- `eula delete`: Lisans sözleşmesini sil
- `eula update`: Lisans sözleşmesini güncelle
- `localizations create`: Dil ekle
- `localizations download`: Yerelleştirmeleri indir
- `localizations placements create`: Görsel yerleşimi ekle
- `localizations placements delete`: Görsel yerleşimini kaldır
- `localizations placements reorder`: Yerleşimleri yeniden sırala
- `localizations placements swap`: Yerleşimi değiştir
- `localizations screenshot-sets delete`: Ekran görüntüsü setini sil
- `localizations search-keywords add`: Arama anahtar kelimeleri ekle
- `localizations search-keywords delete`: Arama anahtar kelimelerini sil
- `localizations supported-locales`: Desteklenen dilleri göster
- `localizations update`: Yerelleştirmeyi güncelle
- `localizations upload`: Yerelleştirmeleri yükle
- `metadata apply`: Meta veri değişikliklerini uygula
- `metadata approve`: Meta veri planını onayla
- `metadata init`: Meta veri şablonları oluştur
- `metadata keywords apply`: Anahtar kelime değişikliklerini uygula
- `metadata keywords import`: Anahtar kelimeleri içe aktar
- `metadata keywords localize`: Anahtar kelimeleri dillere kopyala
- `metadata keywords plan`: Anahtar kelime değişikliklerini önizle
- `metadata keywords push`: Anahtar kelimeleri gönder
- `metadata keywords sync`: Anahtar kelimeleri eşitle
- `metadata plan`: Meta veri değişikliklerini planla
- `metadata pull`: Meta verileri çek
- `metadata push`: Meta verileri gönder

## Görseller

### Çalıştırılamadı

- `app-events links`: Etkinlik yerelleştirme bağlantıları (`--event-id is required`)
- `app-events localizations list`: Etkinlik yerelleştirmeleri (`--event-id is required`)
- `app-events localizations screenshots list`: Etkinlik ekran görüntüleri (`app-events localizations screenshots list: failed to fetch: The`)
- `app-events localizations video-clips list`: Etkinlik video klipleri (`app-events localizations video-clips list: failed to fetch: The`)
- `app-events localizations view`: Etkinlik yerelleştirmesi ayrıntıları (`app-events localizations view: failed to fetch: The specified r`)
- `app-events screenshots links`: Ekran görüntüsü bağlantıları (`--event-id or --localization-id is required`)
- `app-events screenshots list`: Etkinlik ekran görüntüleri (`--event-id or --localization-id is required`)
- `app-events screenshots view`: Etkinlik ekran görüntüsü ayrıntıları (`--screenshot-id is required`)
- `app-events video-clips links`: Video klip bağlantıları (`--event-id or --localization-id is required`)
- `app-events video-clips list`: Etkinlik video klipleri (`--event-id or --localization-id is required`)
- `app-events video-clips view`: Etkinlik video klibi ayrıntıları (`--clip-id is required`)
- `app-events view`: Uygulama içi etkinlik ayrıntıları (`--event-id is required`)
- `product-pages custom-pages localizations list`: Sayfa yerelleştirmeleri (`--custom-page-version-id is required`)
- `product-pages custom-pages localizations preview-sets list`: Önizleme setleri (`custom-pages localizations preview-sets list: failed to fetch: `)
- `product-pages custom-pages localizations screenshot-sets list`: Ekran görüntüsü setleri (`custom-pages localizations screenshot-sets list: failed to fetc`)
- `product-pages custom-pages localizations search-keywords list`: Arama anahtar kelimeleri (`custom-pages localizations search-keywords list: failed to fetc`)
- `product-pages custom-pages localizations view`: Sayfa yerelleştirme ayrıntıları (`custom-pages localizations view: failed to fetch: The specified`)
- `product-pages custom-pages versions list`: Sayfa sürümleri (`--custom-page-id is required`)
- `product-pages custom-pages versions view`: Sayfa sürümü ayrıntıları (`--custom-page-version-id is required`)
- `product-pages custom-pages view`: Özel ürün sayfası ayrıntıları (`--custom-page-id is required`)
- `product-pages experiments treatments list`: Varyantlar (`--experiment-id is required`)
- `product-pages experiments treatments localizations list`: Varyant yerelleştirmeleri (`--treatment-id is required`)
- `product-pages experiments treatments localizations preview-sets list`: Önizleme setleri (`experiments treatments localizations preview-sets list: failed `)
- `product-pages experiments treatments localizations screenshot-sets list`: Ekran görüntüsü setleri (`experiments treatments localizations screenshot-sets list: fail`)
- `product-pages experiments treatments localizations view`: Varyant yerelleştirme ayrıntıları (`experiments treatments localizations view: failed to fetch: The`)
- `product-pages experiments treatments view`: Varyant ayrıntıları (`--treatment-id is required`)
- `product-pages experiments view`: Deneme ayrıntıları (`--experiment-id is required`)
- `screenshots list`: Ekran görüntüleri (`screenshots list: --fields, --limit, and --paginate require --s`)
- `screenshots validate`: Ekran görüntüsü denetimi (`--path is required`)

### Gerçek hesapta denenmedi

- `app-events create`: Uygulama içi etkinlik oluştur
- `app-events delete`: Uygulama içi etkinliği sil
- `app-events localizations create`: Etkinlik yerelleştirmesi oluştur
- `app-events localizations delete`: Etkinlik yerelleştirmesini sil
- `app-events localizations placements create`: Kütüphane varlığı ata
- `app-events localizations placements delete`: Varlık yerleşimini kaldır
- `app-events localizations placements swap`: Varlık yerleşimini değiştir
- `app-events localizations screenshots-links`: Ekran görüntüsü bağlantıları
- `app-events localizations update`: Etkinlik yerelleştirmesini güncelle
- `app-events localizations video-clips-links`: Video klip bağlantıları
- `app-events screenshots create`: Etkinlik ekran görüntüsü yükle
- `app-events screenshots delete`: Etkinlik ekran görüntüsünü sil
- `app-events submit`: Etkinliği incelemeye gönder
- `app-events update`: Uygulama içi etkinliği güncelle
- `app-events video-clips create`: Etkinlik video klibi yükle
- `app-events video-clips delete`: Etkinlik video klibini sil
- `asset-library images archive`: Görseli arşivle
- `asset-library images delete`: Görseli sil
- `asset-library images placements`: Görsel yerleşimleri
- `asset-library images rename`: Görseli yeniden adlandır
- `asset-library images unarchive`: Görseli arşivden çıkar
- `asset-library images upload`: Görsel yükle
- `asset-library specs`: Varlık özellikleri
- `asset-library videos archive`: Videoyu arşivle
- `asset-library videos delete`: Videoyu sil
- `asset-library videos placements`: Video yerleşimleri
- `asset-library videos rename`: Videoyu yeniden adlandır
- `asset-library videos set-poster-frame`: Kapak karesini ayarla
- `asset-library videos unarchive`: Videoyu arşivden çıkar
- `asset-library videos upload`: Video yükle
- `product-pages custom-pages create`: Özel ürün sayfası oluştur
- `product-pages custom-pages delete`: Özel ürün sayfasını sil
- `product-pages custom-pages localizations create`: Sayfa yerelleştirmesi ekle
- `product-pages custom-pages localizations delete`: Sayfa yerelleştirmesini sil
- `product-pages custom-pages localizations placements create`: Görsel yerleşimi ekle
- `product-pages custom-pages localizations placements delete`: Görsel yerleşimini kaldır
- `product-pages custom-pages localizations placements reorder`: Yerleşimleri yeniden sırala
- `product-pages custom-pages localizations placements swap`: Yerleşimi değiştir
- `product-pages custom-pages localizations preview-sets sync`: Önizlemeleri eşitle
- `product-pages custom-pages localizations preview-sets upload`: Önizleme yükle
- `product-pages custom-pages localizations screenshot-sets sync`: Ekran görüntülerini eşitle
- `product-pages custom-pages localizations screenshot-sets upload`: Ekran görüntüleri yükle
- `product-pages custom-pages localizations search-keywords add`: Arama anahtar kelimeleri ekle
- `product-pages custom-pages localizations search-keywords delete`: Arama anahtar kelimelerini sil
- `product-pages custom-pages localizations update`: Sayfa yerelleştirmesini güncelle
- `product-pages custom-pages update`: Özel ürün sayfasını güncelle
- `product-pages custom-pages versions create`: Sayfa sürümü oluştur
- `product-pages custom-pages versions update`: Sayfa sürümünü güncelle
- `product-pages experiments create`: Deneme oluştur
- `product-pages experiments delete`: Denemeyi sil
- `product-pages experiments treatments create`: Varyant oluştur
- `product-pages experiments treatments delete`: Varyantı sil
- `product-pages experiments treatments localizations create`: Varyant yerelleştirmesi ekle
- `product-pages experiments treatments localizations delete`: Varyant yerelleştirmesini sil
- `product-pages experiments treatments localizations placements create`: Görsel yerleşimi ekle
- `product-pages experiments treatments localizations placements delete`: Görsel yerleşimini kaldır
- `product-pages experiments treatments localizations placements reorder`: Yerleşimleri yeniden sırala
- `product-pages experiments treatments localizations placements swap`: Yerleşimi değiştir
- `product-pages experiments treatments localizations screenshot-sets sync`: Ekran görüntülerini eşitle
- `product-pages experiments treatments localizations screenshot-sets upload`: Ekran görüntüleri yükle
- `product-pages experiments treatments update`: Varyantı güncelle
- `product-pages experiments update`: Denemeyi güncelle
- `screenshots apply`: Ekran görüntüsü yüklemelerini uygula
- `screenshots capture`: Ekran görüntüsü yakala
- `screenshots delete`: Ekran görüntüsünü sil
- `screenshots download`: Ekran görüntülerini indir
- `screenshots frame`: Ekran görüntüsünü çerçevele
- `screenshots list-frame-devices`: Çerçeve cihazlarını göster
- `screenshots matrix`: Ekran görüntüsü matrisi yakala
- `screenshots plan`: Ekran görüntüsü yüklemelerini planla
- `screenshots reorder`: Ekran görüntülerini yeniden sırala
- `screenshots review-approve`: Ekran görüntüsü incelemesini onayla
- `screenshots review-generate`: Ekran görüntüsü incelemesi oluştur
- `screenshots review-open`: Ekran görüntüsü incelemesini aç
- `screenshots run`: Ekran görüntüsü dizisini çalıştır
- `screenshots sizes`: Ekran görüntüsü boyutları
- `screenshots upload`: Ekran görüntülerini yükle
- `video-previews delete`: Önizleme videosu sil
- `video-previews download`: Önizleme videolarını indir
- `video-previews set-poster-frame`: Kapak karesini ayarla
- `video-previews upload`: Önizleme videosu yükle

## Derlemeler

### Çalıştırılamadı

- `builds app view`: Uygulama (`--build-id cannot be combined with --app, --latest, --build-num`)
- `builds app-encryption-declaration view`: Şifreleme beyanı (`--build-id cannot be combined with --app, --latest, --build-num`)
- `builds beta-app-review-submission view`: Beta inceleme gönderimi (`--build-id cannot be combined with --app, --latest, --build-num`)
- `builds build-beta-detail view`: Beta ayrıntıları (`--build-id cannot be combined with --app, --latest, --build-num`)
- `builds icons list`: Derleme simgeleri (`--build-id cannot be combined with --app, --latest, --build-num`)
- `builds individual-testers list`: Bireysel test kullanıcıları (`--build-id cannot be combined with --app, --latest, --build-num`)
- `builds info`: Derleme ayrıntıları (`--build-id cannot be combined with --app, --latest, --build-num`)
- `builds links view`: Derleme bağlantıları (`--type is required; must be one of: app, appStoreVersion, betaB`)
- `builds pre-release-version view`: Ön sürüm (`--build-id cannot be combined with --app, --latest, --build-num`)
- `builds test-notes list`: Test notları (`--build-id cannot be combined with --app, --latest, --build-num`)
- `builds test-notes view`: Test notu ayrıntıları (`--localization-id cannot be combined with build selectors or --`)
- `builds uploads files list`: Yüklenen dosyalar (`--upload is required`)
- `builds uploads files view`: Yüklenen dosya ayrıntıları (`builds uploads files view: failed to fetch: The specified resou`)

### Gerçek hesapta denenmedi

- `build-localizations create`: Sürüm notları oluştur
- `build-localizations delete`: Sürüm notlarını sil
- `build-localizations update`: Sürüm notlarını güncelle
- `builds add-groups`: Beta grupları ekle
- `builds compile`: Derlemeyi derle
- `builds dsyms`: Hata ayıklama sembollerini indir
- `builds expire`: Derlemeyi sonlandır
- `builds expire-all`: Eski derlemeleri sonlandır
- `builds individual-testers add`: Test kullanıcısı ekle
- `builds individual-testers remove`: Test kullanıcılarını kaldır
- `builds metrics beta-usages`: Beta kullanım metrikleri
- `builds package`: Derlemeyi paketle
- `builds remove-groups`: Beta gruplarını kaldır
- `builds test-notes create`: Test notu oluştur
- `builds test-notes delete`: Test notunu sil
- `builds test-notes update`: Test notunu güncelle
- `builds update`: Derlemeyi güncelle
- `builds upload`: Derleme yükle
- `builds uploads delete`: Derleme yüklemesini sil
- `builds wait`: İşlenmesini bekle

## TestFlight

### Çalıştırılamadı

- `testflight crashes log`: Çökme günlüğü (`exactly one of --submission-id or --crash-log-id is required`)
- `testflight crashes view`: Çökme raporu ayrıntıları (`--submission-id is required`)
- `testflight feedback view`: Geri bildirim ayrıntıları (`--submission-id is required`)
- `testflight groups compatibility view`: Katılım uyumluluğu (`testflight groups compatibility view: failed to fetch: The spec`)
- `testflight groups links view`: Grup bağlantıları (`--type is required; must be one of: betaTesters, builds`)
- `testflight groups recruitment view`: Katılım ölçütleri (`testflight groups recruitment view: failed to fetch: The provid`)
- `testflight pre-release links view`: Ön sürüm bağlantıları (`--type is required; must be one of: app, builds`)
- `testflight review submissions view`: İnceleme gönderimi ayrıntıları (`testflight review submissions view: failed to fetch: The specif`)
- `testflight testers links view`: Test kullanıcısı bağlantıları (`--type is required; must be one of: apps, betaGroups, builds`)

### Gerçek hesapta denenmedi

- `testflight agreements edit`: TestFlight sözleşmesi düzenle
- `testflight app-localizations create`: TestFlight yerelleştirmesi oluştur
- `testflight app-localizations delete`: TestFlight yerelleştirmesi sil
- `testflight app-localizations update`: TestFlight yerelleştirmesi güncelle
- `testflight config export`: Yapılandırmayı dışa aktar
- `testflight crashes delete`: Çökme raporu sil
- `testflight distribution edit`: Dağıtım ayarlarını düzenle
- `testflight feedback delete`: Geri bildirim sil
- `testflight groups add-testers`: Gruba test kullanıcısı ekle
- `testflight groups create`: TestFlight grubu oluştur
- `testflight groups delete`: TestFlight grubu sil
- `testflight groups edit`: TestFlight grubu düzenle
- `testflight groups remove-testers`: Gruptan test kullanıcısı çıkar
- `testflight metrics app-testers`: Uygulama test kullanıcısı kullanımı
- `testflight metrics group-testers`: Grup test kullanıcısı kullanımı
- `testflight metrics public-link`: Herkese açık bağlantı kullanımı
- `testflight notifications send`: Derleme bildirimi gönder
- `testflight recruitment delete`: Katılım ölçütlerini sil
- `testflight recruitment options`: Katılım seçenekleri
- `testflight recruitment set`: Katılım ölçütlerini ayarla
- `testflight review edit`: İnceleme ayrıntılarını düzenle
- `testflight review submissions build`: İnceleme gönderimi derlemesi
- `testflight review submit`: Derlemeyi incelemeye gönder
- `testflight testers add`: Test kullanıcısı ekle
- `testflight testers add-builds`: Test kullanıcısına derleme ekle
- `testflight testers add-groups`: Test kullanıcısını gruplara ekle
- `testflight testers export`: Test kullanıcılarını dışa aktar
- `testflight testers import`: TestFlight test kullanıcıları içe aktar
- `testflight testers invite`: TestFlight test kullanıcısı davet et
- `testflight testers remove`: Test kullanıcısını kaldır
- `testflight testers remove-apps`: Test kullanıcısından uygulama kaldır
- `testflight testers remove-builds`: Test kullanıcısından derleme kaldır
- `testflight testers remove-groups`: Test kullanıcısını gruplardan çıkar

## Yorumlar

### Çalıştırılamadı

- `reviews response view`: Yanıt ayrıntıları (`--id is required`)
- `reviews view`: Yorum ayrıntıları (`--id is required`)

### Gerçek hesapta denenmedi

- `reviews ratings`: Puanları göster
- `reviews respond`: Yoruma yanıt ver
- `reviews respond-batch`: Birden çok yoruma yanıt ver
- `reviews response delete`: Yanıtı sil
- `reviews response for-review`: Yorum yanıtını göster
- `reviews summarizations`: Yorum özetlerini göster

## Satın almalar

### Çalıştırılamadı

- `iap offer-codes custom-codes list`: Özel kodlar (`--offer-code-id is required`)
- `iap offer-codes custom-codes view`: Özel kod ayrıntıları (`--custom-code-id is required`)
- `iap offer-codes one-time-codes list`: Tek kullanımlık kod grupları (`--offer-code-id is required`)
- `iap offer-codes one-time-codes values`: Tek kullanımlık kod değerleri (`--one-time-code-id is required`)
- `iap offer-codes one-time-codes view`: Tek kullanımlık kod grubu ayrıntıları (`--one-time-code-id is required`)
- `iap offer-codes prices`: Teklif kodu fiyatları (`--offer-code-id is required`)
- `iap offer-codes view`: Teklif kodu ayrıntıları (`--offer-code-id is required`)
- `iap promoted-purchases view`: Öne çıkarılan satın alma ayrıntıları (`--promoted-purchase-id or --iap-id is required`)
- `iap versions images list`: Satın alma sürümü görselleri (`iap versions images list: failed to fetch: The specified resour`)
- `iap versions images view`: Sürüm görseli (`--image-id is required`)
- `iap versions links localizations`: Yerelleştirme bağlantıları (`iap versions links localizations: failed to fetch: The specifie`)
- `iap versions localizations list`: Satın alma sürümü yerelleştirmeleri (`iap versions localizations list: failed to fetch: The specified`)
- `iap versions localizations view`: Sürüm yerelleştirmesi (`iap versions localizations view: failed to fetch: The specified`)
- `iap versions view`: Satın alma sürümü ayrıntıları (`iap versions view: failed to fetch: The specified resource does`)
- `pre-orders list`: Ön sipariş bölgeleri (`--availability is required`)
- `pricing price-points equalizations`: Eşitlenmiş fiyat noktaları (`--price-point is required`)
- `pricing price-points view`: Fiyat noktası ayrıntıları (`--price-point is required`)
- `storekit auth doctor`: StoreKit kimlik bilgileri denetimi (`unknown flag `--output` for `asc storekit auth doctor``)
- `storekit groups list`: Müşterinin grupları (`--transaction-id is required`)
- `storekit notifications history`: Bildirim geçmişi (`--start is required`)
- `storekit notifications test-status`: Test bildirimi durumu (`--token is required`)
- `storekit refunds history`: İade geçmişi (`--transaction-id is required`)
- `storekit retention-messaging defaults view`: Varsayılan mesaj (`--product-id is required`)
- `storekit retention-messaging endpoint view`: Mesaj uç noktası (`--environment is required (or set ASC_STOREKIT_ENVIRONMENT)`)
- `storekit retention-messaging images list`: Elde tutma görselleri (`--environment is required (or set ASC_STOREKIT_ENVIRONMENT)`)
- `storekit retention-messaging messages list`: Elde tutma mesajları (`--environment is required (or set ASC_STOREKIT_ENVIRONMENT)`)
- `storekit retention-messaging performance view`: Performans testi sonucu (`--request-id is required`)
- `storekit subscriptions status`: Abonelik durumları (`--transaction-id is required`)
- `storekit transactions history`: İşlem geçmişi (`--transaction-id is required`)
- `storekit transactions view`: İşlem ayrıntıları (`--transaction-id is required`)
- `subscriptions grace-periods view`: Abonelik ek süresi ayrıntıları (`subscriptions grace-periods view: failed to fetch: The specifie`)
- `subscriptions groups versions links localizations`: Yerelleştirme bağlantıları (`subscriptions groups versions links localizations: failed to fe`)
- `subscriptions groups versions links versions`: Sürüm bağlantıları (`subscriptions groups versions links versions: failed to fetch: `)
- `subscriptions groups versions list`: Grup sürümleri (`subscriptions groups versions list: failed to fetch: The specif`)
- `subscriptions groups versions localizations list`: Abonelik grubu yerelleştirmeleri (`subscriptions groups versions localizations list: failed to fet`)
- `subscriptions groups versions localizations view`: Abonelik grubu yerelleştirmesi ayrıntıları (`subscriptions groups versions localizations view: failed to fet`)
- `subscriptions groups versions view`: Grup sürümü ayrıntıları (`subscriptions groups versions view: failed to fetch: The specif`)
- `subscriptions offers introductory view`: Tanıtım teklifi ayrıntıları (`subscriptions offers introductory view: failed to fetch: introd`)
- `subscriptions offers offer-codes custom-codes list`: Özel teklif kodları (`--offer-code-id is required`)
- `subscriptions offers offer-codes custom-codes view`: Özel teklif kodu ayrıntıları (`--custom-code-id is required`)
- `subscriptions offers offer-codes one-time-codes list`: Tek kullanımlık kod grupları (`--offer-code-id is required`)
- `subscriptions offers offer-codes one-time-codes view`: Tek kullanımlık kod grubu ayrıntıları (`--batch-id is required`)
- `subscriptions offers offer-codes prices`: Teklif kodu fiyatları (`--offer-code-id is required`)
- `subscriptions offers offer-codes values`: Tek kullanımlık kod değerleri (`--batch-id is required`)
- `subscriptions offers offer-codes view`: Teklif kodu ayrıntıları (`--offer-code-id is required`)
- `subscriptions offers promotional prices`: Promosyon teklifi fiyatları (`subscriptions offers promotional prices: failed to fetch: The s`)
- `subscriptions offers promotional view`: Promosyon teklifi ayrıntıları (`subscriptions offers promotional view: failed to fetch: The spe`)
- `subscriptions offers win-back prices`: Geri kazanma teklifi fiyatları (`subscriptions offers win-back prices: failed to fetch: The spec`)
- `subscriptions offers win-back view`: Geri kazanma teklifi ayrıntıları (`subscriptions offers win-back view: The specified resource does`)
- `subscriptions pricing availability available-territories`: Kullanılabilir bölgeler (`--availability-id or --subscription-id is required`)
- `subscriptions pricing availability view`: Kullanılabilirlik ayrıntıları (`--availability-id or --subscription-id is required`)
- `subscriptions pricing price-points equalizations`: Eşitlenmiş fiyatlar (`--price-point-id is required`)
- `subscriptions pricing price-points view`: Fiyat noktası ayrıntıları (`--price-point-id is required`)
- `subscriptions promoted-purchases view`: Öne çıkan satın alma ayrıntıları (`--promoted-purchase-id or --subscription-id is required`)
- `subscriptions review screenshots view`: İnceleme ekran görüntüsü ayrıntıları (`--screenshot-id is required`)
- `subscriptions versions images links`: Görsel bağlantıları (`subscriptions versions images links: failed to fetch: The speci`)
- `subscriptions versions images list`: Abonelik görselleri (`subscriptions versions images list: failed to fetch: The specif`)
- `subscriptions versions images view`: Abonelik görseli ayrıntıları (`subscriptions versions images view: failed to fetch: The specif`)
- `subscriptions versions localizations links`: Yerelleştirme bağlantıları (`subscriptions versions localizations links: failed to fetch: Th`)
- `subscriptions versions localizations list`: Abonelik yerelleştirmeleri (`subscriptions versions localizations list: failed to fetch: The`)
- `subscriptions versions localizations view`: Abonelik yerelleştirmesi ayrıntıları (`subscriptions versions localizations view: failed to fetch: The`)

### Gerçek hesapta denenmedi

- `iap create`: Uygulama içi satın alma oluştur
- `iap delete`: Uygulama içi satın almayı sil
- `iap import`: Uygulama içi satın almaları içe aktar
- `iap offer-codes create`: Teklif kodu oluştur
- `iap offer-codes custom-codes create`: Özel kodlar oluştur
- `iap offer-codes one-time-codes create`: Tek kullanımlık kodlar üret
- `iap offer-codes update`: Teklif kodunu güncelle
- `iap pricing availability set`: Kullanılabilirliği ayarla
- `iap pricing schedules automatic-prices`: Otomatik fiyatları göster
- `iap pricing schedules base-territory`: Ana bölgeyi göster
- `iap pricing schedules create`: Fiyat takvimi oluştur
- `iap pricing schedules manual-prices`: Manuel fiyatları göster
- `iap promoted-purchases create`: Öne çıkarılan satın alma oluştur
- `iap promoted-purchases delete`: Öne çıkarılan satın almayı sil
- `iap promoted-purchases link`: Öne çıkarılan satın almaları bağla
- `iap promoted-purchases update`: Öne çıkarılan satın almayı güncelle
- `iap review-screenshots create`: İnceleme ekran görüntüsü yükle
- `iap review-screenshots delete`: İnceleme ekran görüntüsünü sil
- `iap review-screenshots update`: İnceleme ekran görüntüsünü güncelle
- `iap setup`: Uygulama içi satın alma kur
- `iap update`: Uygulama içi satın almayı güncelle
- `iap versions create`: Satın alma sürümü oluştur
- `iap versions image`: Ana görseli göster
- `iap versions images create`: Sürüm görseli yükle
- `iap versions images delete`: Sürüm görselini sil
- `iap versions images update`: Sürüm görselini güncelle
- `iap versions links image`: Ana görsel bağlantısını göster
- `iap versions links images`: Görsel bağlantılarını göster
- `iap versions localizations create`: Sürüm yerelleştirmesi ekle
- `iap versions localizations delete`: Sürüm yerelleştirmesini sil
- `iap versions localizations import`: Yerelleştirmeleri içe aktar
- `iap versions localizations update`: Sürüm yerelleştirmesini güncelle
- `iap versions submit`: Sürümü incelemeye gönder
- `pre-orders disable`: Ön siparişleri kapat
- `pre-orders enable`: Ön siparişleri aç
- `pre-orders end`: Ön siparişleri bitir
- `pre-orders update`: Ön sipariş ayarlarını güncelle
- `pricing availability create`: Kullanılabilirliği kur
- `pricing availability edit`: Kullanılabilirliği düzenle
- `pricing availability platforms`: Platform listelerini göster
- `pricing availability remove-from-sale`: Satıştan kaldır
- `pricing availability territory-availabilities`: Bölge kullanılabilirliğini göster
- `pricing current`: Güncel fiyatı göster
- `pricing schedule automatic-prices`: Otomatik fiyatları göster
- `pricing schedule create`: Fiyat takvimi oluştur
- `pricing schedule manual-prices`: Manuel fiyatları göster
- `pricing tiers`: Fiyat kademelerini göster
- `storekit auth login`: StoreKit anahtarı ekle
- `storekit auth logout`: StoreKit kimlik bilgilerini kaldır
- `storekit auth switch`: Varsayılan StoreKit anahtarını ayarla
- `storekit groups members`: Grup üyeleri
- `storekit notifications test`: Test bildirimi gönder
- `storekit orders lookup`: Siparişi sorgula
- `storekit retention-messaging defaults delete`: Varsayılan mesajı sil
- `storekit retention-messaging defaults set`: Varsayılan mesajı ayarla
- `storekit retention-messaging endpoint delete`: Mesaj uç noktasını sil
- `storekit retention-messaging endpoint set`: Mesaj uç noktasını ayarla
- `storekit retention-messaging images delete`: Görseli sil
- `storekit retention-messaging images upload`: Görsel yükle
- `storekit retention-messaging messages delete`: Mesajı sil
- `storekit retention-messaging messages upload`: Mesaj yükle
- `storekit retention-messaging performance start`: Performans testini başlat
- `storekit retention-messaging performance wait`: Performans testini bekle
- `subscriptions create`: Abonelik oluştur
- `subscriptions delete`: Abonelik sil
- `subscriptions grace-periods update`: Abonelik ek süresi güncelle
- `subscriptions groups create`: Abonelik grubu oluştur
- `subscriptions groups delete`: Abonelik grubu sil
- `subscriptions groups update`: Abonelik grubu güncelle
- `subscriptions groups versions create`: Grup sürümü oluştur
- `subscriptions groups versions localizations create`: Grup yerelleştirmesi oluştur
- `subscriptions groups versions localizations delete`: Abonelik grubu yerelleştirmesi sil
- `subscriptions groups versions localizations import`: Abonelik grubu yerelleştirmeleri içe aktar
- `subscriptions groups versions localizations update`: Abonelik grubu yerelleştirmesi güncelle
- `subscriptions offers introductory create`: Tanıtım teklifi oluştur
- `subscriptions offers introductory delete`: Tanıtım teklifi sil
- `subscriptions offers introductory import`: Tanıtım teklifleri içe aktar
- `subscriptions offers introductory update`: Tanıtım teklifi güncelle
- `subscriptions offers offer-codes create`: Teklif kodu oluştur
- `subscriptions offers offer-codes custom-codes create`: Özel teklif kodu oluştur
- `subscriptions offers offer-codes custom-codes update`: Özel teklif kodu güncelle
- `subscriptions offers offer-codes generate`: Tek kullanımlık kodlar oluştur
- `subscriptions offers offer-codes update`: Teklif kodu güncelle
- `subscriptions offers promotional create`: Promosyon teklifi oluştur
- `subscriptions offers promotional delete`: Promosyon teklifi sil
- `subscriptions offers promotional update`: Promosyon teklifi fiyatlarını güncelle
- `subscriptions offers win-back create`: Geri kazanma teklifi oluştur
- `subscriptions offers win-back delete`: Geri kazanma teklifi sil
- `subscriptions offers win-back prices-links`: Geri kazanma fiyat bağlantıları
- `subscriptions offers win-back update`: Geri kazanma teklifi güncelle
- `subscriptions pricing availability edit`: Kullanılabilirliği düzenle
- `subscriptions pricing derive`: Fiyatları başka aboneliğden kopyala
- `subscriptions pricing equalize`: Fiyatları eşitle
- `subscriptions pricing monthly-commitment disable`: 12 aylık taahhüdü kapat
- `subscriptions pricing monthly-commitment enable`: 12 aylık taahhüdü aç
- `subscriptions pricing plan-availability set`: Plan kullanılabilirliğini ayarla
- `subscriptions pricing plan-availability show`: Plan kullanılabilirliği
- `subscriptions pricing price-points adjusted-equalizations`: Ayarlanmış eşitlenmiş fiyatlar
- `subscriptions pricing prices delete`: Abonelik fiyatı sil
- `subscriptions pricing prices import`: Abonelik fiyatları içe aktar
- `subscriptions pricing prices set`: Abonelik fiyatı ayarla
- `subscriptions promoted-purchases create`: Öne çıkan satın alma oluştur
- `subscriptions promoted-purchases delete`: Öne çıkan satın alma sil
- `subscriptions promoted-purchases link`: Öne çıkan satın almaları bağla
- `subscriptions promoted-purchases update`: Öne çıkan satın alma güncelle
- `subscriptions review screenshots create`: İnceleme ekran görüntüsü yükle
- `subscriptions review screenshots delete`: İnceleme ekran görüntüsü sil
- `subscriptions review screenshots update`: İnceleme ekran görüntüsü güncelle
- `subscriptions setup`: Abonelik kur
- `subscriptions update`: Abonelik güncelle
- `subscriptions versions create`: Abonelik sürümü oluştur
- `subscriptions versions images delete`: Abonelik görseli sil
- `subscriptions versions images primary`: Birincil görsel
- `subscriptions versions images primary-link`: Birincil görsel bağlantısı
- `subscriptions versions images update`: Abonelik görseli güncelle
- `subscriptions versions images upload`: Abonelik görseli yükle
- `subscriptions versions localizations create`: Abonelik yerelleştirmesi oluştur
- `subscriptions versions localizations delete`: Abonelik yerelleştirmesi sil
- `subscriptions versions localizations import`: Abonelik yerelleştirmeleri içe aktar
- `subscriptions versions localizations update`: Abonelik yerelleştirmesi güncelle

## Analitik

### Çalıştırılamadı

- `analytics instances links`: Rapor segmenti bağlantıları (`--instance-id is required`)
- `analytics instances view`: Rapor örneği ayrıntıları (`--instance-id is required`)
- `analytics reports links`: Rapor örneği bağlantıları (`--report-id is required`)
- `analytics reports view`: Analiz raporu ayrıntıları (`--report-id is required`)
- `analytics segments view`: Rapor segmenti ayrıntıları (`--segment-id is required`)
- `analytics view`: İstek raporları (`--request-id is required`)
- `performance diagnostics view`: Tanılama günlükleri (`--id is required`)

### Gerçek hesapta denenmedi

- `analytics compare`: Satış metriklerini karşılaştır
- `analytics download`: Analiz verilerini indir
- `analytics request`: Analiz raporu iste
- `analytics requests delete`: Rapor isteğini sil
- `analytics sales`: Satış raporlarını indir
- `insights daily`: Günlük analizleri göster
- `insights weekly`: Haftalık analizleri göster
- `performance download`: Performans verilerini indir
- `performance overview`: Performans özetini göster

## Diğer

### Çalıştırılamadı

- `alternative-distribution domains view`: Dağıtım alan adı ayrıntıları (`--domain-id is required`)
- `alternative-distribution keys view`: Dağıtım anahtarı ayrıntıları (`--key-id is required`)
- `alternative-distribution packages versions list`: Paket sürümleri (`--package-id is required`)
- `alternative-distribution packages versions view`: Paket sürümü ayrıntıları (`alternative-distribution packages versions view: failed to fetc`)
- `alternative-distribution packages view`: Dağıtım paketi ayrıntıları (`--package-id is required`)
- `android-ios-mapping view`: Android-iOS eşlemesi ayrıntıları (`--mapping-id is required`)
- `app-clips advanced-experiences images view`: Deneyim görseli ayrıntıları (`--id is required`)
- `app-clips advanced-experiences list`: Gelişmiş deneyimler (`--app-clip-id is required`)
- `app-clips advanced-experiences view`: Gelişmiş deneyim ayrıntıları (`--experience-id is required`)
- `app-clips default-experiences header-image view`: Yerelleştirme başlık görseli (`app-clips default-experiences header-image view: failed to fetc`)
- `app-clips default-experiences list`: Varsayılan deneyimler (`--app-clip-id is required`)
- `app-clips default-experiences localizations list`: Deneyim yerelleştirmeleri (`--experience-id is required`)
- `app-clips default-experiences localizations view`: Yerelleştirme ayrıntıları (`app-clips default-experiences localizations view: failed to fet`)
- `app-clips default-experiences view`: Varsayılan deneyim ayrıntıları (`--experience-id is required`)
- `app-clips header-images view`: Başlık görseli ayrıntıları (`--id is required`)
- `app-clips invocations list`: Beta çağrıları (`--build-bundle-id is required`)
- `app-clips invocations localizations list`: Çağrı yerelleştirmeleri (`--invocation-id is required`)
- `app-clips invocations view`: Beta çağrısı ayrıntıları (`--invocation-id is required`)
- `app-clips review-details view`: İnceleme ayrıntıları (`--id is required`)
- `app-clips view`: App Clip ayrıntıları (`--id is required`)
- `background-assets app-store-releases view`: App Store yayın ayrıntıları (`--id is required`)
- `background-assets external-beta-releases view`: Harici beta yayın ayrıntıları (`--id is required`)
- `background-assets internal-beta-releases view`: Dahili beta yayın ayrıntıları (`--id is required`)
- `background-assets upload-files list`: Yüklenen dosyalar (`background-assets upload-files list: failed to fetch: The speci`)
- `background-assets upload-files view`: Yüklenen dosya ayrıntıları (`--upload-file-id is required`)
- `background-assets versions list`: Varlık sürümleri (`--background-asset-id is required`)
- `background-assets versions view`: Varlık sürümü ayrıntıları (`background-assets versions view: failed to fetch: The specified`)
- `background-assets view`: Arka plan varlığı ayrıntıları (`--id is required`)
- `game-center achievements images view`: Başarım görseli ayrıntıları (`game-center achievements images view: The specified resource do`)
- `game-center achievements localizations achievement view`: Başarım (`game-center achievements localizations achievement view: failed`)
- `game-center achievements localizations image view`: Yerelleştirme görseli (`game-center achievements localizations image view: failed to fe`)
- `game-center achievements localizations list`: Başarım yerelleştirmeleri (`--achievement-id is required`)
- `game-center achievements localizations view`: Başarım yerelleştirmesi ayrıntıları (`game-center achievements localizations view: failed to fetch: T`)
- `game-center achievements releases list`: Başarım yayınları (`--achievement-id is required`)
- `game-center achievements v2 images view`: Başarım görseli ayrıntıları (v2) (`game-center achievements v2 images view: The specified resource`)
- `game-center achievements v2 localizations list`: Başarım yerelleştirmeleri (v2) (`game-center achievements v2 localizations list: failed to fetch`)
- `game-center achievements v2 localizations view`: Başarım yerelleştirmesi ayrıntıları (v2) (`game-center achievements v2 localizations view: failed to fetch`)
- `game-center achievements v2 versions list`: Başarım sürümleri (v2) (`--achievement-id is required`)
- `game-center achievements v2 versions view`: Başarım sürümü ayrıntıları (v2) (`game-center achievements v2 versions view: failed to fetch: The`)
- `game-center activities images view`: Etkinlik görseli ayrıntıları (`game-center activities images view: failed to fetch: The specif`)
- `game-center activities localizations image view`: Yerelleştirme görseli (`game-center activities localizations image view: failed to fetc`)
- `game-center activities localizations list`: Etkinlik yerelleştirmeleri (`game-center activities localizations list: failed to fetch: The`)
- `game-center activities localizations view`: Etkinlik yerelleştirmesi ayrıntıları (`game-center activities localizations view: failed to fetch: The`)
- `game-center activities versions default-image view`: Varsayılan görsel (`game-center activities versions default-image view: failed to f`)
- `game-center activities versions list`: Etkinlik sürümleri (`--activity-id is required`)
- `game-center activities versions view`: Etkinlik sürümü ayrıntıları (`game-center activities versions view: failed to fetch: The spec`)
- `game-center challenges images view`: Meydan okuma görseli ayrıntıları (`game-center challenges images view: failed to fetch: The specif`)
- `game-center challenges localizations image view`: Yerelleştirme görseli (`game-center challenges localizations image view: failed to fetc`)
- `game-center challenges localizations list`: Meydan okuma yerelleştirmeleri (`game-center challenges localizations list: failed to fetch: The`)
- `game-center challenges localizations view`: Meydan okuma yerelleştirmesi ayrıntıları (`game-center challenges localizations view: failed to fetch: The`)
- `game-center challenges versions default-image view`: Varsayılan görsel (`game-center challenges versions default-image view: failed to f`)
- `game-center challenges versions list`: Meydan okuma sürümleri (`--challenge-id is required`)
- `game-center challenges versions view`: Meydan okuma sürümü ayrıntıları (`game-center challenges versions view: failed to fetch: The spec`)
- `game-center details blocked-players list`: Engellenen oyuncular (`game-center details blocked-players list: --detail-id is requir`)
- `game-center groups achievements list`: Başarımlar (`game-center groups achievements list: failed to fetch: The spec`)
- `game-center groups activities list`: Etkinlikler (`game-center groups activities list: failed to fetch: The specif`)
- `game-center groups challenges list`: Meydan okumalar (`game-center groups challenges list: failed to fetch: The specif`)
- `game-center groups leaderboard-sets list`: Lider tablosu setleri (`game-center groups leaderboard-sets list: failed to fetch: The `)
- `game-center groups leaderboards list`: Lider tabloları (`game-center groups leaderboards list: failed to fetch: The spec`)
- `game-center groups list`: Gruplar (`game-center groups list: failed to fetch: The specified resourc`)
- `game-center groups view`: Grup ayrıntıları (`--id is required`)
- `game-center leaderboard-sets group-leaderboard-set view`: Grup lider tablosu seti (`--id is required`)
- `game-center leaderboard-sets localizations image view`: Yerelleştirme görseli (`--id is required`)
- `game-center leaderboard-sets localizations list`: Lider tablosu seti yerelleştirmeleri (`--set-id is required`)
- `game-center leaderboard-sets localizations view`: Lider tablosu seti yerelleştirmesi ayrıntıları (`--id is required`)
- `game-center leaderboard-sets member-localizations leaderboard view`: Lider tablosu (`--id is required`)
- `game-center leaderboard-sets member-localizations leaderboard-set view`: Lider tablosu seti (`--id is required`)
- `game-center leaderboard-sets member-localizations list`: Lider tablosu seti üye yerelleştirmeleri (`--set-id is required`)
- `game-center leaderboard-sets member-localizations view`: Lider tablosu seti üye yerelleştirmesi ayrıntıları (`--id is required`)
- `game-center leaderboard-sets members list`: Lider tablosu seti üyeleri (`--set-id is required`)
- `game-center leaderboard-sets releases list`: Lider tablosu seti yayınları (`--set-id is required`)
- `game-center leaderboard-sets v2 images view`: Lider tablosu seti görseli ayrıntıları (v2) (`--id or --localization-id is required`)
- `game-center leaderboard-sets v2 localizations list`: Lider tablosu seti yerelleştirmeleri (v2) (`game-center leaderboard-sets v2 localizations list: failed to f`)
- `game-center leaderboard-sets v2 localizations view`: Lider tablosu seti yerelleştirmesi ayrıntıları (v2) (`--id is required`)
- `game-center leaderboard-sets v2 members list`: Lider tablosu seti üyeleri (v2) (`--set-id is required`)
- `game-center leaderboard-sets v2 versions list`: Lider tablosu seti sürümleri (v2) (`--set-id is required`)
- `game-center leaderboard-sets v2 versions view`: Lider tablosu seti sürümü ayrıntıları (v2) (`--id is required`)
- `game-center leaderboard-sets v2 view`: Lider tablosu seti ayrıntıları (v2) (`--id is required`)
- `game-center leaderboard-sets view`: Lider tablosu seti ayrıntıları (`--id is required`)
- `game-center leaderboards localizations image view`: Yerelleştirme görseli (`game-center leaderboards localizations image view: failed to fe`)
- `game-center leaderboards localizations list`: Lider tablosu yerelleştirmeleri (`--leaderboard-id is required`)
- `game-center leaderboards localizations view`: Lider tablosu yerelleştirme ayrıntıları (`game-center leaderboards localizations view: failed to fetch: T`)
- `game-center leaderboards releases list`: Lider tablosu yayınları (`--leaderboard-id is required`)
- `game-center leaderboards v2 images view`: Lider tablosu görseli (`game-center leaderboards v2 images view: The specified resource`)
- `game-center leaderboards v2 localizations list`: Lider tablosu yerelleştirmeleri (v2) (`game-center leaderboards v2 localizations list: failed to fetch`)
- `game-center leaderboards v2 localizations view`: Lider tablosu yerelleştirme ayrıntıları (`game-center leaderboards v2 localizations view: failed to fetch`)
- `game-center leaderboards v2 score-moderations list`: Gönderilen skorlar (`game-center leaderboards v2 score-moderations list: --leaderboa`)
- `game-center leaderboards v2 versions list`: Lider tablosu sürümleri (`--leaderboard-id is required`)
- `game-center leaderboards v2 versions view`: Lider tablosu sürüm ayrıntıları (`game-center leaderboards v2 versions view: failed to fetch: The`)
- `game-center matchmaking queues view`: Eşleştirme kuyruğu ayrıntıları (`--id is required`)
- `game-center matchmaking rule-sets queues list`: Kural seti kuyrukları (`--rule-set-id is required`)
- `game-center matchmaking rule-sets view`: Kural seti ayrıntıları (`--id is required`)
- `game-center matchmaking rules list`: Eşleştirme kuralları (`--rule-set-id is required`)
- `game-center matchmaking teams list`: Eşleştirme takımları (`--rule-set-id is required`)
- `marketplace search-details view`: Arama ayrıntıları (`marketplace search-details view: failed to fetch: retry limit e`)
- `marketplace webhooks list`: Pazar yeri webhook'ları (`Warning: marketplace webhooks endpoints are deprecated in App Store Co`)
- `marketplace webhooks view`: Webhook ayrıntıları (`Warning: marketplace webhooks endpoints are deprecated in App Store Co`)
- `nominations list`: Öne çıkarma adaylıkları (`--status is required`)
- `nominations view`: Adaylık ayrıntıları (`--id is required`)
- `routing-coverage info`: Yönlendirme kapsamı ayrıntıları (`--id is required`)

### Gerçek hesapta denenmedi

- `alternative-distribution domains create`: Dağıtım alan adı oluştur
- `alternative-distribution domains delete`: Dağıtım alan adını sil
- `alternative-distribution keys app`: Uygulama dağıtım anahtarı
- `alternative-distribution keys create`: Dağıtım anahtarı oluştur
- `alternative-distribution keys delete`: Dağıtım anahtarını sil
- `alternative-distribution packages app-store-version`: Sürüm paketi
- `alternative-distribution packages create`: Dağıtım paketi oluştur
- `alternative-distribution packages deltas`: Paket farkı
- `alternative-distribution packages variants`: Paket varyantı
- `alternative-distribution packages versions deltas`: Paket sürümü farkları
- `alternative-distribution packages versions variants`: Paket sürümü varyantları
- `android-ios-mapping create`: Android-iOS eşlemesi oluştur
- `android-ios-mapping delete`: Android-iOS eşlemesini sil
- `android-ios-mapping update`: Android-iOS eşlemesini güncelle
- `app-clips advanced-experiences create`: Gelişmiş deneyim oluştur
- `app-clips advanced-experiences delete`: Gelişmiş deneyimi kaldır
- `app-clips advanced-experiences images create`: Deneyim görseli yükle
- `app-clips advanced-experiences update`: Gelişmiş deneyimi güncelle
- `app-clips advanced-experiences-links`: Gelişmiş deneyim bağlantıları
- `app-clips default-experiences create`: Varsayılan deneyim oluştur
- `app-clips default-experiences delete`: Varsayılan deneyimi sil
- `app-clips default-experiences links app-store-review-detail`: İnceleme ayrıntısı bağlantısı
- `app-clips default-experiences links release-with-app-store-version`: Yayın sürümü bağlantısı
- `app-clips default-experiences localizations create`: Deneyim yerelleştirmesi oluştur
- `app-clips default-experiences localizations delete`: Yerelleştirmeyi sil
- `app-clips default-experiences localizations header-image-relationship`: Başlık görseli bağlantısı
- `app-clips default-experiences localizations update`: Yerelleştirmeyi güncelle
- `app-clips default-experiences release-with-app-store-version`: Yayın sürümü
- `app-clips default-experiences review-detail`: İnceleme ayrıntıları
- `app-clips default-experiences update`: Varsayılan deneyimi güncelle
- `app-clips default-experiences-links`: Varsayılan deneyim bağlantıları
- `app-clips domain-status cache`: Alan adı önbellek durumu
- `app-clips domain-status debug`: Alan adı hata ayıklama durumu
- `app-clips header-images create`: Başlık görseli yükle
- `app-clips header-images delete`: Başlık görselini sil
- `app-clips invocations create`: Beta çağrısı oluştur
- `app-clips invocations delete`: Beta çağrısını sil
- `app-clips invocations localizations create`: Çağrı yerelleştirmesi oluştur
- `app-clips invocations localizations delete`: Çağrı yerelleştirmesini sil
- `app-clips invocations localizations update`: Çağrı yerelleştirmesini güncelle
- `app-clips invocations update`: Beta çağrısını güncelle
- `app-clips review-details create`: İnceleme ayrıntıları oluştur
- `app-clips review-details update`: İnceleme ayrıntılarını güncelle
- `background-assets create`: Arka plan varlığı oluştur
- `background-assets submit`: İncelemeye gönder
- `background-assets update`: Arka plan varlığını güncelle
- `background-assets upload-files create`: Dosya yükle
- `background-assets upload-files update`: Yüklenen dosyayı güncelle
- `background-assets versions create`: Varlık sürümü oluştur
- `game-center achievements create`: Başarım oluştur
- `game-center achievements delete`: Başarımı sil
- `game-center achievements images delete`: Başarım görselini sil
- `game-center achievements images upload`: Başarım görseli yükle
- `game-center achievements localizations create`: Başarım yerelleştirmesi oluştur
- `game-center achievements localizations delete`: Başarım yerelleştirmesini sil
- `game-center achievements localizations update`: Başarım yerelleştirmesini güncelle
- `game-center achievements releases create`: Başarım yayını oluştur
- `game-center achievements releases delete`: Başarım yayınını sil
- `game-center achievements submit`: Başarımı gönder
- `game-center achievements update`: Başarımı güncelle
- `game-center achievements v2 images delete`: Başarım görselini sil (v2)
- `game-center achievements v2 images upload`: Başarım görseli yükle (v2)
- `game-center achievements v2 localizations create`: Başarım yerelleştirmesi oluştur (v2)
- `game-center achievements v2 localizations delete`: Başarım yerelleştirmesini sil (v2)
- `game-center achievements v2 localizations update`: Başarım yerelleştirmesini güncelle (v2)
- `game-center achievements v2 versions create`: Başarım sürümü oluştur (v2)
- `game-center activities achievements set`: Başarımları ayarla
- `game-center activities create`: Etkinlik oluştur
- `game-center activities delete`: Etkinliği sil
- `game-center activities images delete`: Etkinlik görselini sil
- `game-center activities images upload`: Etkinlik görseli yükle
- `game-center activities leaderboards set`: Lider tabloları ayarla
- `game-center activities localizations create`: Etkinlik yerelleştirmesi oluştur
- `game-center activities localizations delete`: Etkinlik yerelleştirmesini sil
- `game-center activities localizations update`: Etkinlik yerelleştirmesini güncelle
- `game-center activities releases create`: Etkinlik yayını oluştur
- `game-center activities releases delete`: Etkinlik yayınını sil
- `game-center activities update`: Etkinliği güncelle
- `game-center activities versions create`: Etkinlik sürümü oluştur
- `game-center activities versions update`: Etkinlik sürümünü güncelle
- `game-center app-versions create`: Uygulama sürümü oluştur
- `game-center app-versions update`: Uygulama sürümünü güncelle
- `game-center challenges create`: Meydan okuma oluştur
- `game-center challenges delete`: Meydan okumayı sil
- `game-center challenges images delete`: Meydan okuma görselini sil
- `game-center challenges images upload`: Meydan okuma görseli yükle
- `game-center challenges localizations create`: Meydan okuma yerelleştirmesi oluştur
- `game-center challenges localizations delete`: Meydan okuma yerelleştirmesini sil
- `game-center challenges localizations update`: Meydan okuma yerelleştirmesini güncelle
- `game-center challenges releases create`: Meydan okuma yayını oluştur
- `game-center challenges releases delete`: Meydan okuma yayınını sil
- `game-center challenges update`: Meydan okumayı güncelle
- `game-center challenges versions create`: Meydan okuma sürümü oluştur
- `game-center details blocked-players update`: Oyuncuyu engelle veya engeli kaldır
- `game-center details create`: Game Center ayrıntıları oluştur
- `game-center details metrics classic-matchmaking`: Klasik eşleştirme metrikleri
- `game-center details metrics rule-based-matchmaking`: Kural tabanlı eşleştirme metrikleri
- `game-center details update`: Game Center ayrıntılarını güncelle
- `game-center enabled-versions compatible-versions`: Uyumlu sürümler
- `game-center groups achievements set`: Başarımları ayarla
- `game-center groups create`: Grup oluştur
- `game-center groups delete`: Grubu sil
- `game-center groups leaderboards set`: Lider tabloları ayarla
- `game-center groups update`: Grubu güncelle
- `game-center leaderboard-sets create`: Lider tablosu seti oluştur
- `game-center leaderboard-sets delete`: Lider tablosu setini sil
- `game-center leaderboard-sets images delete`: Lider tablosu seti görselini sil
- `game-center leaderboard-sets images upload`: Lider tablosu seti görseli yükle
- `game-center leaderboard-sets localizations create`: Lider tablosu seti yerelleştirmesi oluştur
- `game-center leaderboard-sets localizations delete`: Lider tablosu seti yerelleştirmesini sil
- `game-center leaderboard-sets localizations update`: Lider tablosu seti yerelleştirmesini güncelle
- `game-center leaderboard-sets member-localizations create`: Lider tablosu seti üye yerelleştirmesi oluştur
- `game-center leaderboard-sets member-localizations delete`: Lider tablosu seti üye yerelleştirmesini sil
- `game-center leaderboard-sets member-localizations update`: Lider tablosu seti üye yerelleştirmesini güncelle
- `game-center leaderboard-sets members set`: Lider tablosu seti üyeleri ayarla
- `game-center leaderboard-sets releases create`: Lider tablosu seti yayını oluştur
- `game-center leaderboard-sets releases delete`: Lider tablosu seti yayınını sil
- `game-center leaderboard-sets update`: Lider tablosu setini güncelle
- `game-center leaderboard-sets v2 create`: Lider tablosu seti oluştur (v2)
- `game-center leaderboard-sets v2 delete`: Lider tablosu setini sil (v2)
- `game-center leaderboard-sets v2 images delete`: Lider tablosu seti görselini sil (v2)
- `game-center leaderboard-sets v2 images upload`: Lider tablosu seti görseli yükle (v2)
- `game-center leaderboard-sets v2 localizations create`: Lider tablosu seti yerelleştirmesi oluştur (v2)
- `game-center leaderboard-sets v2 localizations delete`: Lider tablosu seti yerelleştirmesini sil (v2)
- `game-center leaderboard-sets v2 localizations update`: Lider tablosu seti yerelleştirmesini güncelle (v2)
- `game-center leaderboard-sets v2 members set`: Lider tablosu seti üyeleri ayarla (v2)
- `game-center leaderboard-sets v2 update`: Lider tablosu setini güncelle (v2)
- `game-center leaderboard-sets v2 versions create`: Lider tablosu seti sürümü oluştur (v2)
- `game-center leaderboards create`: Lider tablosu oluştur
- `game-center leaderboards delete`: Lider tablosunu sil
- `game-center leaderboards images delete`: Lider tablosu görselini sil
- `game-center leaderboards images upload`: Lider tablosu görseli yükle
- `game-center leaderboards localizations create`: Lider tablosu yerelleştirmesi ekle
- `game-center leaderboards localizations delete`: Lider tablosu yerelleştirmesini sil
- `game-center leaderboards localizations update`: Lider tablosu yerelleştirmesini güncelle
- `game-center leaderboards releases create`: Lider tablosu yayını oluştur
- `game-center leaderboards releases delete`: Lider tablosu yayınını sil
- `game-center leaderboards submit`: Lider tablosuna skor gönder
- `game-center leaderboards update`: Lider tablosunu güncelle
- `game-center leaderboards v2 images delete`: Lider tablosu görselini sil
- `game-center leaderboards v2 images upload`: Lider tablosu görseli yükle
- `game-center leaderboards v2 localizations create`: Lider tablosu yerelleştirmesi ekle
- `game-center leaderboards v2 localizations delete`: Lider tablosu yerelleştirmesini sil
- `game-center leaderboards v2 localizations update`: Lider tablosu yerelleştirmesini güncelle
- `game-center leaderboards v2 score-moderations update`: Skoru engelle veya engeli kaldır
- `game-center leaderboards v2 versions create`: Lider tablosu sürümü oluştur
- `game-center matchmaking metrics experiment-queue-requests`: Deneme kuyruğu istekleri
- `game-center matchmaking metrics experiment-queue-sizes`: Deneme kuyruğu boyutları
- `game-center matchmaking metrics queue-requests`: Kuyruk istekleri
- `game-center matchmaking metrics queue-sessions`: Kuyruk oturumları
- `game-center matchmaking metrics queue-sizes`: Kuyruk boyutları
- `game-center matchmaking metrics rule-boolean-results`: Kural doğru/yanlış sonuçları
- `game-center matchmaking metrics rule-errors`: Kural hataları
- `game-center matchmaking metrics rule-number-results`: Kural sayısal sonuçları
- `game-center matchmaking queues create`: Eşleştirme kuyruğu oluştur
- `game-center matchmaking queues delete`: Eşleştirme kuyruğunu sil
- `game-center matchmaking queues update`: Eşleştirme kuyruğunu güncelle
- `game-center matchmaking rule-set-tests create`: Kural seti testi oluştur
- `game-center matchmaking rule-sets create`: Kural seti oluştur
- `game-center matchmaking rule-sets delete`: Kural setini sil
- `game-center matchmaking rule-sets update`: Kural setini güncelle
- `game-center matchmaking rules create`: Eşleştirme kuralı oluştur
- `game-center matchmaking rules delete`: Eşleştirme kuralını sil
- `game-center matchmaking rules update`: Eşleştirme kuralını güncelle
- `game-center matchmaking teams create`: Eşleştirme takımı oluştur
- `game-center matchmaking teams delete`: Eşleştirme takımını sil
- `game-center matchmaking teams update`: Eşleştirme takımını güncelle
- `marketplace search-details create`: Arama ayrıntıları oluştur
- `marketplace search-details delete`: Arama ayrıntılarını sil
- `marketplace search-details update`: Arama ayrıntılarını güncelle
- `marketplace webhooks create`: Webhook oluştur
- `marketplace webhooks delete`: Webhook'u sil
- `marketplace webhooks update`: Webhook'u güncelle
- `nominations create`: Adaylık oluştur
- `nominations delete`: Adaylığı sil
- `nominations update`: Adaylığı güncelle
- `routing-coverage create`: Yönlendirme kapsamı yükle
- `routing-coverage delete`: Yönlendirme kapsamını sil

## Takım: Kullanıcılar

### Çalıştırılamadı

- `actors list`: Aktörler (`--id is required`)
- `actors view`: Aktör ayrıntıları (`--id is required`)
- `users invites view`: Kullanıcı daveti ayrıntıları (`users invites view: failed to fetch: The specified resource doe`)
- `users invites visible-apps list`: Davetin görünür uygulamaları (`users invites visible-apps list: failed to fetch: The specified`)
- `users visible-apps view`: Görünür uygulama bağlantıları (`users visible-apps view: failed to fetch: retry limit exceeded `)

### Gerçek hesapta denenmedi

- `sandbox clear-history`: Satın alma geçmişini temizle
- `sandbox update`: Sandbox test kullanıcısını güncelle
- `users delete`: Kullanıcı sil
- `users invite`: Kullanıcı davet et
- `users invites revoke`: Daveti geri al
- `users update`: Kullanıcı güncelle

## Takım: Cihazlar

### Gerçek hesapta denenmedi

- `devices local-udid`: Bu Mac'in cihaz kimliği
- `devices register`: Cihaz kaydet
- `devices register-batch`: Birden çok cihaz kaydet
- `devices update`: Cihazı güncelle

## Takım: Sertifikalar, profiller, bundle ID'ler

### Çalıştırılamadı

- `bundle-ids app view`: Bağlı uygulama (`bundle-ids app view: failed to fetch: The URL path is not valid`)
- `bundle-ids capabilities list`: Yetenekler (`--bundle is required`)
- `merchant-ids certificates list`: Sertifikalar (`--merchant-id is required`)
- `merchant-ids certificates view`: Sertifika bağlantıları (`--merchant-id is required`)
- `merchant-ids view`: Satıcı kimliği ayrıntıları (`--merchant-id is required`)
- `notarization validate`: Noter onayı biletini doğrula (`notarization validate: --file is required`)
- `pass-type-ids certificates list`: Sertifikalar (`--pass-type-id is required unless --next is provided`)
- `pass-type-ids certificates view`: Sertifika bağlantıları (`--pass-type-id is required unless --next is provided`)
- `pass-type-ids view`: Pass türü kimliği ayrıntıları (`--pass-type-id is required`)
- `signing keychain set-partition-list`: Anahtarlık erişim denetimi (`signing keychain: --keychain is required`)

### Gerçek hesapta denenmedi

- `bundle-ids capabilities add`: Yetenek ekle
- `bundle-ids capabilities reconcile apply`: Yetenekleri uygula
- `bundle-ids capabilities reconcile plan`: Yetenek değişikliklerini önizle
- `bundle-ids capabilities remove`: Yeteneği kaldır
- `bundle-ids capabilities update`: Yeteneği güncelle
- `bundle-ids create`: Paket kimliği oluştur
- `bundle-ids delete`: Paket kimliğini sil
- `bundle-ids update`: Paket kimliğini güncelle
- `certificates create`: Sertifika oluştur
- `certificates csr generate`: Sertifika isteği oluştur
- `certificates export`: Sertifikayı dışa aktar
- `certificates links pass-type-id`: Pass türü kimliği
- `certificates revoke`: Sertifikayı iptal et
- `certificates update`: Sertifikayı güncelle
- `merchant-ids certificates create`: Sertifika oluştur
- `merchant-ids create`: Satıcı kimliği oluştur
- `merchant-ids delete`: Satıcı kimliğini sil
- `merchant-ids update`: Satıcı kimliğini güncelle
- `notarization staple`: Noter onayı biletini iliştir
- `notarization submit`: Noter onayına gönder
- `pass-type-ids create`: Pass türü kimliği oluştur
- `pass-type-ids delete`: Pass türü kimliğini sil
- `pass-type-ids update`: Pass türü kimliğini güncelle
- `profiles create`: Profil oluştur
- `profiles delete`: Profili sil
- `profiles download`: Profili indir
- `profiles inspect`: Yerel profili incele
- `profiles links bundle-id`: Paket kimliği bağlantısını göster
- `profiles links certificates`: Sertifika bağlantılarını göster
- `profiles links devices`: Cihaz bağlantılarını göster
- `profiles local clean`: Yerel profilleri temizle
- `profiles local install`: Profili yerel olarak yükle
- `signing fetch`: İmzalama dosyalarını getir
- `signing keychain delete`: Anahtarlığı sil
- `signing keychain install`: Anahtarlık kur
- `signing keychain lock`: Anahtarlığı kilitle
- `signing keychain set-timeout`: Anahtarlık zaman aşımını ayarla
- `signing keychain unlock`: Anahtarlığın kilidini aç
- `signing reconcile apply`: İmzalama planını uygula
- `signing reconcile plan`: İmzalama değişikliklerini planla
- `signing resign`: Uygulamayı yeniden imzala
- `signing run`: İmzalama kimliğiyle çalıştır
- `signing sync nuke`: İmzalama varlıklarını sıfırla
- `signing sync pull`: İmzalama varlıklarını çek
- `signing sync push`: İmzalama varlıklarını gönder
- `signing sync rotate-password`: Eşitleme parolasını değiştir

## Takım: Raporlar ve finans

### Çalıştırılamadı

- `optimize keywords rank`: Anahtar kelime sıralaması (`--keywords is required`)

### Gerçek hesapta denenmedi

- `finance regions`: Rapor bölgeleri
- `finance reports`: Finans raporlarını indir
- `optimize keywords discover`: Anahtar kelimeleri keşfet
- `optimize keywords score`: Anahtar kelimeleri puanla
- `optimize search plan`: Arama planı oluştur

## Takım: Otomasyon

### Çalıştırılamadı

- `webhooks deliveries links`: Teslimat bağlantıları (`--webhook-id is required`)
- `webhooks view`: Webhook ayrıntıları (`--webhook-id is required`)
- `xcode-cloud actions list`: Derleme eylemleri (`--run-id is required`)
- `xcode-cloud actions view`: Derleme eylemi ayrıntıları (`--id is required`)
- `xcode-cloud artifacts list`: Derleme çıktıları (`--action-id or --run-id is required`)
- `xcode-cloud artifacts view`: Derleme çıktısı ayrıntıları (`--id is required`)
- `xcode-cloud build-runs list`: Derleme çalıştırmaları (`--workflow-id is required. Find workflow IDs with: asc xcode-cl`)
- `xcode-cloud build-runs view`: Derleme çalıştırması ayrıntıları (`--id is required`)
- `xcode-cloud doctor`: Derleme çalıştırması tanılaması (`--run-id is required`)
- `xcode-cloud issues list`: Derleme sorunları (`--action-id or --run-id is required`)
- `xcode-cloud issues view`: Derleme sorunu ayrıntıları (`--id is required`)
- `xcode-cloud products view`: Xcode Cloud ürünü ayrıntıları (`--id is required`)
- `xcode-cloud scm git-references view`: Git referansı ayrıntıları (`--id is required`)
- `xcode-cloud scm providers view`: Kaynak sağlayıcı ayrıntıları (`--provider-id is required`)
- `xcode-cloud scm pull-requests view`: Çekme isteği ayrıntıları (`--id is required`)
- `xcode-cloud scm repositories view`: Depo ayrıntıları (`--id is required`)
- `xcode-cloud status`: Derleme çalıştırması durumu (`--run-id is required`)
- `xcode-cloud test-results list`: Test sonuçları (`--action-id or --run-id is required`)
- `xcode-cloud test-results view`: Test sonucu ayrıntıları (`--id is required`)
- `xcode-cloud workflows list`: Xcode Cloud iş akışları (`xcode-cloud workflows: no Xcode Cloud product found for app "67`)
- `xcode-cloud workflows view`: Xcode Cloud iş akışı ayrıntıları (`--id is required`)

### Gerçek hesapta denenmedi

- `notify slack`: Slack mesajı gönder
- `webhooks create`: Webhook oluştur
- `webhooks delete`: Webhook sil
- `webhooks deliveries redeliver`: Webhook'u yeniden gönder
- `webhooks ping`: Test ping gönder
- `webhooks serve`: Yerel webhook alıcısını başlat
- `webhooks update`: Webhook güncelle
- `workflow list`: İş akışları
- `workflow run`: İş akışını çalıştır
- `workflow validate`: İş akışı denetimi
- `xcode-cloud actions build-run`: Eylem derleme çalıştırması
- `xcode-cloud artifacts download`: Çıktıyı indir
- `xcode-cloud build-runs builds`: Derleme çalıştırmasının derlemeleri
- `xcode-cloud macos-versions xcode-versions`: macOS için Xcode sürümleri
- `xcode-cloud products additional-repositories`: Ek depolar
- `xcode-cloud products app`: Ürün uygulaması
- `xcode-cloud products build-runs`: Ürün derleme çalıştırmaları
- `xcode-cloud products delete`: Xcode Cloud ürünü sil
- `xcode-cloud products primary-repositories`: Birincil depolar
- `xcode-cloud products workflows`: Ürün iş akışları
- `xcode-cloud run`: Derleme başlat
- `xcode-cloud scm providers repositories`: Sağlayıcı depoları
- `xcode-cloud scm repositories git-references`: Depo git referansları
- `xcode-cloud scm repositories links git-references`: Git referansı bağlantıları
- `xcode-cloud scm repositories links pull-requests`: Çekme isteği bağlantıları
- `xcode-cloud scm repositories pull-requests`: Depo çekme istekleri
- `xcode-cloud workflows create`: Xcode Cloud iş akışı oluştur
- `xcode-cloud workflows delete`: Xcode Cloud iş akışı sil
- `xcode-cloud workflows duplicate`: İş akışını çoğalt
- `xcode-cloud workflows repository`: İş akışı deposu
- `xcode-cloud workflows update`: Xcode Cloud iş akışı güncelle
- `xcode-cloud xcode-versions macos-versions`: Xcode için macOS sürümleri

## Takım: Apple Ads

### Çalıştırılamadı

- `ads acls list`: Hesap erişimleri (`ads: default credentials not found; run 'asc ads auth login' to`)
- `ads ad-accounts view`: Reklam hesabı ayrıntıları (`ads: default credentials not found; run 'asc ads auth login' to`)
- `ads ad-groups find`: Reklam grupları (`ads: default credentials not found; run 'asc ads auth login' to`)
- `ads ad-groups view`: Reklam grubu ayrıntıları (`--ad-group is required`)
- `ads ads find`: Reklamlar (`ads: default credentials not found; run 'asc ads auth login' to`)
- `ads ads view`: Reklam ayrıntıları (`--ad is required`)
- `ads advertiser-resources list`: Reklamveren kaynakları (`--resource-type is required`)
- `ads apps eligibility find`: Uygulama uygunluğu (`ads: default credentials not found; run 'asc ads auth login' to`)
- `ads apps locales find`: Uygulama yerel ayarları (`--adam-id is required`)
- `ads apps search`: Uygulama ara (`at least one of --query, --cpids, or --return-owned-apps is req`)
- `ads apps supported-languages find`: Desteklenen uygulama dilleri (`ads: default credentials not found; run 'asc ads auth login' to`)
- `ads apps view`: Uygulama ayrıntıları (`--adam-id is required`)
- `ads assets find`: Varlıklar (`ads: default credentials not found; run 'asc ads auth login' to`)
- `ads assets view`: Varlık ayrıntıları (`--asset is required`)
- `ads brands find`: Markalar (`--file is required`)
- `ads brands view`: Marka ayrıntıları (`--brand is required`)
- `ads budget-orders find`: Ortak bütçeler (`ads: default credentials not found; run 'asc ads auth login' to`)
- `ads budget-orders view`: Ortak bütçe ayrıntıları (`--budget-order is required`)
- `ads business-categories find`: İş kategorileri (`--file is required`)
- `ads business-categories view`: İş kategorisi ayrıntıları (`--category is required`)
- `ads campaigns find`: Kampanyalar (`ads: default credentials not found; run 'asc ads auth login' to`)
- `ads campaigns view`: Kampanya ayrıntıları (`--campaign is required`)
- `ads change-history find`: Değişiklik geçmişi (`--file is required`)
- `ads change-history view`: Değişiklik geçmişi ayrıntıları (`--detail-id is required`)
- `ads creatives find`: Kreatifler (`ads: default credentials not found; run 'asc ads auth login' to`)
- `ads creatives view`: Kreatif ayrıntıları (`--creative is required`)
- `ads geo search`: Konum ara (`--supply-source is required`)
- `ads insights impression-share find`: Gösterim payı verileri (`--file is required`)
- `ads insights search-term-popularity find`: Arama terimi popülerlik verileri (`--file is required`)
- `ads location-groups find`: Konum grupları (`--file is required`)
- `ads location-groups view`: Konum grubu ayrıntıları (`--location-group is required`)
- `ads locations find`: Konumlar (`--file is required`)
- `ads locations view`: Konum ayrıntıları (`--location is required`)
- `ads me view`: Geçerli kullanıcı (`ads: default credentials not found; run 'asc ads auth login' to`)
- `ads negative-keywords find`: Negatif anahtar kelimeler (`--file is required`)
- `ads negative-keywords view`: Negatif anahtar kelime ayrıntıları (`--negative-keyword is required`)
- `ads orgs view`: Kuruluş ayrıntıları (`--org-id is required`)
- `ads product-pages find`: Ürün sayfaları (`ads: default credentials not found; run 'asc ads auth login' to`)
- `ads product-pages locales find`: Ürün sayfası yerel ayarları (`ads: default credentials not found; run 'asc ads auth login' to`)
- `ads product-pages view`: Ürün sayfası ayrıntıları (`--product-page is required`)
- `ads recommendations daily-budgets find`: Günlük bütçe önerileri (`--file is required`)
- `ads recommendations target-cpas find`: Hedef CPA önerileri (`--file is required`)
- `ads rejection-reasons apps find`: Uygulama ret nedenleri (`ads: default credentials not found; run 'asc ads auth login' to`)
- `ads rejection-reasons apps view`: Uygulama ret nedeni ayrıntıları (`--reason is required`)
- `ads rejection-reasons brands find`: Marka ret nedenleri (`ads: default credentials not found; run 'asc ads auth login' to`)
- `ads suggestions categories find`: Kategori önerileri (`--file is required`)
- `ads suggestions keywords find`: Anahtar kelime önerileri (`--file is required`)
- `ads suggestions phrases find`: İfade önerileri (`--file is required`)
- `ads suggestions target-cpas find`: Hedef CPA önerileri (`--file is required`)
- `ads targeting-keywords find`: Hedefleme anahtar kelimeleri (`--file is required`)
- `ads targeting-keywords view`: Anahtar kelime ayrıntıları (`--keyword is required`)
- `ads v5 acls list`: Eski hesap erişimleri (`Warning: `asc ads v5 acls list` is deprecated and retires on January 2`)
- `ads v5 ad-group-negative-keywords find`: Reklam grubu negatif anahtar kelimeleri (`Warning: `asc ads v5 ad-group-negative-keywords find` is deprecated an`)
- `ads v5 ad-group-negative-keywords list`: Reklam grubu negatif anahtar kelimeleri (`Warning: `asc ads v5 ad-group-negative-keywords list` is deprecated an`)
- `ads v5 ad-group-negative-keywords view`: Negatif anahtar kelime ayrıntıları (`Warning: `asc ads v5 ad-group-negative-keywords view` is deprecated an`)
- `ads v5 ad-groups find`: Reklam grupları (`Warning: `asc ads v5 ad-groups find` is deprecated and retires on Janu`)
- `ads v5 ad-groups list`: Reklam grupları (`Warning: `asc ads v5 ad-groups list` is deprecated and retires on Janu`)
- `ads v5 ad-groups view`: Reklam grubu ayrıntıları (`Warning: `asc ads v5 ad-groups view` is deprecated and retires on Janu`)
- `ads v5 ads find`: Reklamlar (`Warning: `asc ads v5 ads find` is deprecated and retires on January 26`)
- `ads v5 ads list`: Reklamlar (`Warning: `asc ads v5 ads list` is deprecated and retires on January 26`)
- `ads v5 ads view`: Reklam ayrıntıları (`Warning: `asc ads v5 ads view` is deprecated and retires on January 26`)
- `ads v5 apps assets find`: Varlıklar (`Warning: `asc ads v5 apps assets find` is deprecated and retires on Ja`)
- `ads v5 apps eligibility find`: Uygulama uygunluğu (`Warning: `asc ads v5 apps eligibility find` is deprecated and retires `)
- `ads v5 apps search`: Uygulama ara (`Warning: `asc ads v5 apps search` is deprecated and retires on January`)
- `ads v5 apps view`: Uygulama ayrıntıları (`Warning: `asc ads v5 apps view` is deprecated and retires on January 2`)
- `ads v5 budget-orders list`: Ortak bütçeler (`Warning: `asc ads v5 budget-orders list` is deprecated and retires on `)
- `ads v5 budget-orders view`: Ortak bütçe ayrıntıları (`Warning: `asc ads v5 budget-orders view` is deprecated and retires on `)
- `ads v5 campaign-negative-keywords find`: Kampanya negatif anahtar kelimeleri (`Warning: `asc ads v5 campaign-negative-keywords find` is deprecated an`)
- `ads v5 campaign-negative-keywords list`: Kampanya negatif anahtar kelimeleri (`Warning: `asc ads v5 campaign-negative-keywords list` is deprecated an`)
- `ads v5 campaign-negative-keywords view`: Negatif anahtar kelime ayrıntıları (`Warning: `asc ads v5 campaign-negative-keywords view` is deprecated an`)
- `ads v5 campaigns find`: Kampanyalar (`Warning: `asc ads v5 campaigns find` is deprecated and retires on Janu`)
- `ads v5 campaigns list`: Kampanyalar (`Warning: `asc ads v5 campaigns list` is deprecated and retires on Janu`)
- `ads v5 campaigns view`: Kampanya ayrıntıları (`Warning: `asc ads v5 campaigns view` is deprecated and retires on Janu`)
- `ads v5 creatives find`: Kreatifler (`Warning: `asc ads v5 creatives find` is deprecated and retires on Janu`)
- `ads v5 creatives list`: Kreatifler (`Warning: `asc ads v5 creatives list` is deprecated and retires on Janu`)
- `ads v5 creatives view`: Kreatif ayrıntıları (`Warning: `asc ads v5 creatives view` is deprecated and retires on Janu`)
- `ads v5 geo search`: Konum ara (`Warning: `asc ads v5 geo search` is deprecated and retires on January `)
- `ads v5 impression-share-reports list`: Gösterim payı raporları (`Warning: `asc ads v5 impression-share-reports list` is deprecated and `)
- `ads v5 impression-share-reports view`: Gösterim payı raporu ayrıntıları (`Warning: `asc ads v5 impression-share-reports view` is deprecated and `)
- `ads v5 me view`: Geçerli kullanıcı (`Warning: `asc ads v5 me view` is deprecated and retires on January 26,`)
- `ads v5 product-pages countries list`: Ürün sayfası ülkeleri (`Warning: `asc ads v5 product-pages countries list` is deprecated and r`)
- `ads v5 product-pages devices list`: Ürün sayfası cihazları (`Warning: `asc ads v5 product-pages devices list` is deprecated and ret`)
- `ads v5 product-pages list`: Ürün sayfaları (`Warning: `asc ads v5 product-pages list` is deprecated and retires on `)
- `ads v5 product-pages locales list`: Ürün sayfası yerel ayarları (`Warning: `asc ads v5 product-pages locales list` is deprecated and ret`)
- `ads v5 product-pages view`: Ürün sayfası ayrıntıları (`Warning: `asc ads v5 product-pages view` is deprecated and retires on `)
- `ads v5 rejection-reasons find`: Ret nedenleri (`Warning: `asc ads v5 rejection-reasons find` is deprecated and retires`)
- `ads v5 rejection-reasons view`: Ret nedeni ayrıntıları (`Warning: `asc ads v5 rejection-reasons view` is deprecated and retires`)
- `ads v5 targeting-keywords find`: Hedefleme anahtar kelimeleri (`Warning: `asc ads v5 targeting-keywords find` is deprecated and retire`)
- `ads v5 targeting-keywords list`: Hedefleme anahtar kelimeleri (`Warning: `asc ads v5 targeting-keywords list` is deprecated and retire`)
- `ads v5 targeting-keywords view`: Anahtar kelime ayrıntıları (`Warning: `asc ads v5 targeting-keywords view` is deprecated and retire`)

### Gerçek hesapta denenmedi

- `ads ad-accounts create`: Reklam hesabı oluştur
- `ads ad-accounts update`: Reklam hesabını güncelle
- `ads ad-groups create`: Reklam grubu oluştur
- `ads ad-groups delete`: Reklam grubunu sil
- `ads ad-groups update`: Reklam grubunu güncelle
- `ads ads create`: Reklam oluştur
- `ads ads delete`: Reklamı sil
- `ads ads update`: Reklamı güncelle
- `ads api request`: Gelişmiş istek gönder
- `ads assets delete`: Varlığı sil
- `ads assets upload`: Marka görseli yükle
- `ads auth discover`: Hesap erişimini keşfet
- `ads auth login`: Kimlik bilgilerini kaydet
- `ads auth logout`: Kimlik bilgilerini kaldır
- `ads auth switch`: Varsayılan profili değiştir
- `ads auth token`: Erişim jetonu al
- `ads budget-orders create`: Ortak bütçe oluştur
- `ads budget-orders delete`: Ortak bütçeyi sil
- `ads budget-orders update`: Ortak bütçeyi güncelle
- `ads campaigns create`: Kampanya oluştur
- `ads campaigns delete`: Kampanyayı sil
- `ads campaigns legacy-status-reasons`: Kampanya durum nedenleri
- `ads campaigns pause`: Kampanyayı duraklat
- `ads campaigns resume`: Kampanyayı sürdür
- `ads campaigns update`: Kampanyayı güncelle
- `ads creatives create`: Kreatif oluştur
- `ads creatives delete`: Kreatifi sil
- `ads creatives update`: Kreatifi güncelle
- `ads geo resolve`: Konumları çözümle
- `ads location-groups create`: Konum grubu oluştur
- `ads location-groups delete`: Konum grubunu sil
- `ads location-groups update`: Konum grubunu güncelle
- `ads negative-keywords create`: Negatif anahtar kelime oluştur
- `ads negative-keywords create-bulk`: Negatif anahtar kelimeleri toplu oluştur
- `ads negative-keywords delete`: Negatif anahtar kelimeyi sil
- `ads negative-keywords update`: Negatif anahtar kelimeyi güncelle
- `ads negative-keywords update-bulk`: Negatif anahtar kelimeleri toplu güncelle
- `ads recommendations daily-budgets apply`: Günlük bütçe önerilerini uygula
- `ads recommendations daily-budgets dismiss`: Günlük bütçe önerilerini yoksay
- `ads recommendations target-cpas apply`: Hedef CPA önerilerini uygula
- `ads recommendations target-cpas dismiss`: Hedef CPA önerilerini yoksay
- `ads reports apps ad-groups`: Uygulama reklam grubu raporları
- `ads reports apps ads`: Uygulama reklam raporları
- `ads reports apps campaigns`: Uygulama kampanya raporları
- `ads reports apps keywords`: Uygulama anahtar kelime raporları
- `ads reports apps search-terms`: Uygulama arama terimi raporları
- `ads reports brands ad-groups`: Marka reklam grubu raporları
- `ads reports brands ads`: Marka reklam raporları
- `ads reports brands campaigns`: Marka kampanya raporları
- `ads reports brands keywords`: Marka anahtar kelime raporları
- `ads reports brands search-terms`: Marka arama terimi raporları
- `ads targeting-keywords create`: Anahtar kelime oluştur
- `ads targeting-keywords create-bulk`: Anahtar kelimeleri toplu oluştur
- `ads targeting-keywords delete`: Anahtar kelimeyi sil
- `ads targeting-keywords update`: Anahtar kelimeyi güncelle
- `ads targeting-keywords update-bulk`: Anahtar kelimeleri toplu güncelle
- `ads v5 ad-group-negative-keywords create-bulk`: Negatif anahtar kelimeleri toplu oluştur
- `ads v5 ad-group-negative-keywords delete-bulk`: Negatif anahtar kelimeleri toplu sil
- `ads v5 ad-group-negative-keywords update-bulk`: Negatif anahtar kelimeleri toplu güncelle
- `ads v5 ad-groups create`: Reklam grubu oluştur
- `ads v5 ad-groups delete`: Reklam grubunu sil
- `ads v5 ad-groups find-org`: Kuruluş reklam grupları
- `ads v5 ad-groups update`: Reklam grubunu güncelle
- `ads v5 ads create`: Reklam oluştur
- `ads v5 ads delete`: Reklamı sil
- `ads v5 ads find-org`: Kuruluş reklamları
- `ads v5 ads update`: Reklamı güncelle
- `ads v5 api request`: Gelişmiş istek gönder
- `ads v5 apps localized-details`: Yerelleştirilmiş ayrıntılar
- `ads v5 budget-orders create`: Ortak bütçe oluştur
- `ads v5 budget-orders update`: Ortak bütçeyi güncelle
- `ads v5 campaign-negative-keywords create-bulk`: Negatif anahtar kelimeleri toplu oluştur
- `ads v5 campaign-negative-keywords delete-bulk`: Negatif anahtar kelimeleri toplu sil
- `ads v5 campaign-negative-keywords update-bulk`: Negatif anahtar kelimeleri toplu güncelle
- `ads v5 campaigns create`: Kampanya oluştur
- `ads v5 campaigns delete`: Kampanyayı sil
- `ads v5 campaigns pause`: Kampanyayı duraklat
- `ads v5 campaigns resume`: Kampanyayı sürdür
- `ads v5 campaigns update`: Kampanyayı güncelle
- `ads v5 creatives create`: Kreatif oluştur
- `ads v5 geo resolve`: Konumları çözümle
- `ads v5 impression-share-reports create`: Gösterim payı raporu oluştur
- `ads v5 reports ad-group-keywords`: Reklam grubu anahtar kelime raporları
- `ads v5 reports ad-group-search-terms`: Reklam grubu arama terimi raporları
- `ads v5 reports ad-groups`: Reklam grubu raporları
- `ads v5 reports ads`: Reklam raporları
- `ads v5 reports campaigns`: Kampanya raporları
- `ads v5 reports keywords`: Anahtar kelime raporları
- `ads v5 reports preset`: Hazır raporlar
- `ads v5 reports search-terms`: Arama terimi raporları
- `ads v5 targeting-keywords create-bulk`: Anahtar kelimeleri toplu oluştur
- `ads v5 targeting-keywords delete`: Anahtar kelimeyi sil
- `ads v5 targeting-keywords delete-bulk`: Anahtar kelimeleri toplu sil
- `ads v5 targeting-keywords update-bulk`: Anahtar kelimeleri toplu güncelle

## Takım: Hesap

### Çalıştırılamadı

- `agreements territories list`: Sözleşme bölgeleri (`--id is required`)
