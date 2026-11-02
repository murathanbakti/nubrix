# QA ve güvenlik raporu: özellik anahtarları, sekme düzeni, optimizasyon (2026-11-02)

Kapsam: v0.1.1 sonrası `nubrix` dalındaki yeni özellikler ve bu daldaki (`murathan.bakti/settings-tabs-scan-0aabcd`) değişiklikler.

Önceki yeni özellikler:
- Kaydırma düzeltmesi
- Claude oturumunu açma
- Bildirimlere hızlı cevap

Bu daldaki değişiklikler:
- Her izin gerektiren özelliğe bir Ayarlar anahtarı
- Notch sekmelerinin sırası ve görünürlüğü
- Boşta CPU ve yeniden çizim taraması
- Dışarıya dokunan kodun güvenlik taraması

Bulguların düzeltmeleri bu daldaki commit'lerde: `a0dc0a1`, `981e5c4`, `22f27d2`, `5ba197f`, `e4d289f` ve bu raporun commit'i.

Ortam: macOS 26 (Darwin 25.6.0), Xcode 26, Apple silicon.

## Karar

**Kullanıcı denemesinden sonra birleştirmeye engel yok.** Yüksek önemli bulgu çıkmadı.

- Kendi alanımdaki orta ve düşük önemli bulguların çoğu düzeltildi. Kalanlar "Ertelenen" altında.
- Hızlı cevabın güvenlik bulguları, o kodu yeniden yazan `nubrix-interactions` oturumuna devredildi. O oturum düzeltmeleri `370f45a`'da `nubrix`'e aldı ve bu dal o commit'le birleştirildi.
- Anahtarların çalışma anındaki davranışı yalnızca kodla doğrulandı. Uygulamanın açılması gereken kontroller kullanıcıya kaldı (K maddeleri).

## Çalıştırılan testler

| Test | Sonuç |
|---|---|
| Debug derlemesi (`CODE_SIGNING_ALLOWED=NO`), her adımdan sonra | geçti, hata yok; dokunulan dosyalarda yeni uyarı yok |
| `nubrix` dalının birleştirilmesi (`af51d7e`) | çakışmasız |
| Release derlemesi ve `scripts/verify-bundle.sh` | geçti (birleştirmeden sonra; tam beş Mach-O dosyası) |
| Hook betikleri: `bash -n`, `shellcheck -S warning` | geçti |
| Sahte HOME ve sahte dinleyiciyle hook'lar | geçti. Kaynak klasöründen `NUBRIX_DEV=1` sahte sunucuya ulaşıyor. Kurulu kopyalardan ve onlara giden sembolik bağdan istek gitmiyor; hepsi 0 ile ve boş stdout ile çıkıyor |
| Takılan bir `lsof` taklidiyle `nubrix-permission` | 1,03 sn'de vazgeçip 0 ile çıkıyor; geçici dosya ya da süreç kalmıyor |
| `csreq` ile yeni XPC istemci şartı | geçerli |
| Kurulu uygulamanın boştaki ölçümü, notch kapalı, 60 sn (`top -l 13 -s 5`) | Nubrix %0,1–0,7 CPU, 44 MB; NubrixHelper %0–0,2, 5 MB. Bu ölçüm değişikliklerden önceki sürüme ait, sonrası için K-11'e bak |

## Bulgular ve durum

### Özellik anahtarları

| # | Önem | Bulgu | Durum |
|---|---|---|---|
| S-1 | orta | Claude Code entegrasyonunun ana anahtarı yoktu. Loopback sunucusu, 60 sn'lik oturum süpürmesi ve plan kullanımı yoklaması her zaman çalışıyordu | düzeltildi: "Claude Code integration" (`claudeEnabled`). Sunucu yalnızca Claude ya da Dev açıkken çalışıyor. Kapalı bir özelliğin rotaları reddediliyor (Claude rotaları 404; notch onayları kapalıysa `/permission` 404, böylece hook hemen Claude'un kendi penceresine düşüyor). Oturumlar, banner'lar, okunmamışlar ve sekme temizleniyor |
| S-2 | orta | Claude oturumunu açmanın (Terminal ve iTerm için Automation, `claude://`) anahtarı yoktu | düzeltildi: "Open the session when you click it" (`claudeOpenSession`). Kapalıyken Apple Event ya da URL gönderilmiyor; banner Claude sekmesini açıyor |
| S-3 | orta | GitHub'ı token'ı silmeden kapatmanın yolu yoktu; her açılışta Keychain okunuyordu | düzeltildi: "GitHub integration" (`githubEnabled`). Kapalıyken Keychain okunmuyor, istek gitmiyor, gözlemciler kalkıyor, banner'lar ve Dev sekmesindeki GitHub bölümü kayboluyor. Token Keychain'de kalıyor |
| S-4 | orta | Medya denetimi kapatılamıyordu. Her açılışta perl ile kontrol yapılıyor ve denetleyici kuruluyordu. Apple Music ya da Spotify açıksa açılışta Automation istemi çıkabiliyordu. YouTube Music websocket'i ve zamanlayıcısı hiç durmuyordu | düzeltildi: "Media control" (`mediaControlEnabled`). Kapalıyken adaptör süreci yok, AppleScript yok, websocket ve zamanlayıcı yok. Oynatıcı, canlı etkinlik ve sneak peek gizleniyor. Bütün denetleyicilerde `stop()` var. NowPlaying kontrolünün sonucu macOS sürümü ve build'ine göre saklanıyor |
| S-5 | orta | Ayna anahtarı kapalıyken de ⌃⌥M kamerayı açıyor ve kamera iznini istiyordu | düzeltildi: kısayol ve `present` anahtara bakıyor; anahtar kapanınca açık ayna kapanıyor |
| S-6 | orta | Ayarlar → Takvim'i açmak bile takvim iznini istiyordu. "Calendar" anahtarı yalnızca tarih kapsülünü gizliyordu. Toplantı izleyicisi ve takvim yöneticisi her açılışta EventKit'e dokunuyordu | düzeltildi: Ayarlar sayfası yalnızca durumu okuyor, izin "Allow Calendar Access" düğmesiyle isteniyor. "Calendar" artık ana anahtar: takvim sayfası kısayolu, toplantı geri sayımı ve EventKit gözlemcileri ona bağlı |
| S-7 | düşük | HUD anahtarı açıkken Erişilebilirlik izni geri alınmışsa açılışta sistem istemi çıkıyordu | düzeltildi: istem yalnızca kullanıcı anahtarı açınca çıkıyor |
| S-8 | düşük | Vitrin kapalıyken de veritabanı açılıyor, ekran görüntüsü klasörünün erişimi tutuluyor ve saatlik zamanlayıcı çalışıyordu. Ayarlar kapalıyken de klasör seçici açılabiliyordu | düzeltildi: kapalıyken veritabanı kapanıyor, erişim bırakılıyor, banner kalkıyor; ayar bölümleri devre dışı |
| S-9 | düşük | Notch onayları kapatılınca kuyruktaki istekler kalıyordu. Plan kullanımı ve bildirim anahtarları yalnızca ilgili Ayarlar sayfası açıkken uygulanıyordu (`.onChange`) | düzeltildi: her store anahtarı kendisi dinliyor (`Defaults.publisher`); değişiklik her yerden anında uygulanıyor |
| S-10 | düşük | Dev kapalıyken `notchctl` 204 alıyor, bildirim sessizce düşüyordu | düzeltildi: sunucu 503 dönüyor, `notchctl` "the Dev tab is turned off" yazıp 1 ile çıkıyor |
| S-11 | düşük | Dev kapalıyken Dev ayarları açıksa port tarama döngüsü 15 sn'de bir boşuna uyanıyordu | düzeltildi |
| S-12 | düşük | Kapatılan bir kaynağın okunmamış kayıtları ve sekme noktaları kalıyordu | düzeltildi: kaynak kapanınca okundu sayılıyor |
| S-13 | düşük | Onboarding'in müzik adımı atlanamıyordu | düzeltildi: "Not Now" medya denetimini kapatıp devam ediyor. NowPlaying desteklenmiyorsa her açılışta müzik adımına dönme davranışı da artık bu anahtara bağlı |
| S-14 | bilgi | Kullanılmayan eski kamera kodu (`WebcamManager`, `WebcamView`) açılışta kamera aygıtlarını listeliyor ve bağlantı gözlemcisi kuruyordu | kaldırıldı |

Diğer kontroller:
- Onboarding'deki bütün izin adımları ("Not Now") atlanabiliyor.
- Hiçbir `*Enabled` anahtarı kullanıcı tıklaması olmadan açılmıyor; tek yazan `FullDiskAccessGuide.begin()`, o da düğmelerden çağrılıyor.
- Pil ve raf sürükleme izinsiz ve olay tabanlı; değiştirilmedi.
- Hızlı cevabın anahtarı (`systemNotificationQuickReply`), birleştirilen kodda hem arayüzde hem store'da kontrol ediliyor.

### Sekme düzeni

Ayarlar'a "Tabs" sayfası eklendi. Kurallar:
- Sekmeler sürükle-bırak ile sıralanıyor ve her birinin bir "Show" anahtarı var.
- En az bir sekme görünür kalıyor: son görünür sekmenin anahtarı devre dışı, model de bunu ayrıca zorluyor.
- Kayıtlı sırada olmayan ve yeni sekmeler sona ekleniyor; "Restore Defaults" varsayılana dönüyor.
- `currentView` gizli ya da kapalı bir sekmeye ayarlanırsa (banner tıklaması dahil) ilk görünür sekmeye geçiyor.
- Özelliği kapalı sekme listede gri ve açıklamalı görünüyor.
- Gizlemek ile kapatmak arasındaki fark tek cümleyle yazılı.
- 6/8 pt sekme dolgusu kuralı korundu.
- Bulgu yok. Sürükle-bırakın gerçek pencerede denenmesi gerekiyor (K-3).

### Performans

| # | Önem | Bulgu | Durum |
|---|---|---|---|
| P-1 | orta | Plan kullanımı yoklaması hiç uykuya geçmiyordu. Claude hiç kullanılmasa da 30 dakikada bir `claude` CLI'ı başlatılıyordu (önceki denetimdeki "6 saatten sonra zamanlayıcı yok" iddiası doğru değildi) | düzeltildi: 6 saat etkinlik yoksa zamanlayıcı yok. Son etkinlik yeniden başlatmada da hatırlanıyor. Yeni oturum, istem, Stop ya da notch açılınca yeniden başlıyor |
| P-2 | orta | Kök görünüm bütün oturum store'unu izliyordu. Claude çalışırken notch kapalıyken bile saniyede bir yeniden çiziliyordu | düzeltildi: kök görünüm ve kapalı notch etkinliği yalnızca banner, dikkat ve çalışma bilgisini taşıyan küçük bir nesneyi izliyor; değer değişmedikçe yayın yok |
| P-3 | orta-düşük | Pano yoklaması (0,5 sn) boşta en sık uyanan işti | düzeltildi: 30 sn girdi yoksa 2 sn'ye iniyor, ilk girdide 0,5 sn'ye dönüyor |
| P-4 | düşük-orta | Ayarlar penceresi kapanınca HUD sayfasındaki 3 sn'lik XPC yoklaması ve Dev sayfasındaki port taraması sürebiliyordu | düzeltildi: pencere kapanınca duruyor, açılınca o sayfa yeniden başlatıyor |
| P-5 | düşük-orta | Bildirim yoklaması ekran uykusunda ve oturum pasifken durmuyordu; uygulama seçili değilken de yardımcıya soruyordu | düzeltildi: ek gözlemciler, tolerans eklendi; seçili uygulama yoksa yardımcıya sorulmuyor |
| P-6 | düşük | Kullanım özeti bir çizimde 3 kez, 20.000 kayda kadar taranarak hesaplanıyordu | düzeltildi: önbellekte |
| P-7 | düşük | 16 MB'a kadar olabilen kullanım defteri açılışta ana iş parçacığında okunuyordu | düzeltildi: arka planda okunuyor, kayıtlar birleştiriliyor; yükleme bitmeden yazma yapılmıyor |
| P-8 | düşük | Sneak peek her tuş olayında 4 kez yayın yapıyordu | düzeltildi: tek atama |
| P-9 | düşük | Saatsiz süpürme beklemesi, her güncellemede yeni tarih biçimlendirici, her şarkı sözü satırında yeni regex | düzeltildi |

Değişmeyenler:
- Kapalı notch'ta animasyon ya da `TimelineView` yok.
- GitHub ve toplantı zamanlayıcıları zaten toleranslı ve duraklayabiliyor.
- Önbellek ve listelerin hepsi sınırlı.

### Güvenlik

Hızlı cevap (`NubrixHelper/NotificationReplier.swift` ve ilgili uygulama kodu, a7b7820 ve bd01f24 üzerinde incelendi):

| # | Önem | Bulgu | Durum |
|---|---|---|---|
| Q-1 | orta | Gevşek eşleşme (alt dize ve token eşleşmesi, yumuşak uygulama kontrolü), cevabı yanlış sohbete ya da uygulamaya gönderebiliyordu | `nubrix-interactions` oturumuna devredildi; `0d0e8d6` ve `370f45a` |
| Q-2 | orta | Metin, Bildirim Merkezi'nde odakta olan başka bir cevap alanına gidebiliyordu; Gönder düğmesi `hasPrefix` ile aranıyordu | devredildi; `370f45a` |
| Q-3 | orta | Banner kaybolunca `.invalidUIElement` "gönderildi" sayılıyordu | devredildi; `370f45a` |
| Q-4 | orta | Zaman aşımı ile gönderim arasında yarış vardı; XPC hatası çift gönderime yol açabiliyordu | devredildi; `370f45a` (`beginSubmit`) |
| Q-5 | düşük | Loglarda uygulamaların verdiği AX kimlikleri ve eylem adları `.public` idi | devredildi; `370f45a`'da `.private` |
| Q-6 | düşük | Yardımcı süreç ve store, özellik anahtarlarını kontrol etmiyordu | devredildi; birleştirilen kodda kontrol var |
| Q-7 | düşük | Bildirim Merkezi'ni açarken saat menüsü yedeği başka bir menü öğesine basabiliyordu | devredildi |
| Q-8 | düşük | Pano yedeği Universal Clipboard ile senkronlanabiliyordu; replier bağlantı başına oluşturuluyordu | devredildi |

Q bulgularının düzeltmeleri bu raporda yeniden doğrulanmadı; ayrıntı o oturumun commit'lerinde. Doğrulanan sağlam taraflar:
- Metin CGEvent ile değil, AXValue ile yazılıp geri okunuyor.
- SQL parametreli ve veritabanı salt okunur açılıyor.
- NSKeyedUnarchiver kullanılmıyor.
- Cevap metni loglanmıyor.
- Pano yedeği Concealed/Transient işaretli; Vitrin onu kaydetmiyor.

Claude oturumunu açma, hook'lar, loopback sunucu ve yardımcı süreç:

| # | Önem | Bulgu | Durum |
|---|---|---|---|
| G-1 | düşük | Yardımcı sürecin XPC istemci şartı yalnızca kimlik içeriyordu (`identifier "dev.nubrix.app"`) | düzeltildi: yardımcı kendi takım kimliğini okuyor; varsa `anchor apple generic` ve aynı takım şartını koyuyor. Ad-hoc derlemelerde eski şart kalıyor |
| G-2 | düşük | `nubrix-permission` içindeki `lsof`'un zaman sınırı yoktu | düzeltildi: 1 sn bekçi; zaman aşımında karar verilmiyor ve 0 ile çıkılıyor |
| G-3 | düşük | Kurulu hook kopyaları `NUBRIX_DEV`, `NUBRIX_ENDPOINT_FILE` ve `NUBRIX_PERMISSION_WAIT`'e uyuyordu. Bir projenin `.claude/settings.json` `env` bloğu hook'ları sahte bir dinleyiciye yönlendirip onay uydurabilirdi | düzeltildi: bu değişkenler `~/.config/nubrix/bin` dışından çalışan kopyalarda geçerli. Hook'lar ve `notchctl` için geçerli. Kullanıcının `install-hooks.sh`'i yeniden çalıştırması gerekiyor (K-2) |
| G-4 | düşük | `fetchSystemNotifications` uygulama kimliklerinin uzunluğunu ve imleci denetlemiyordu | düzeltildi: kimlik başına 255 bayt; negatif imleç -1 |
| G-5 | düşük | `claude://` URL'sine giren oturum kimliği girişte iki kez doğrulanıyor ama kullanıldığı yerde doğrulanmıyordu | düzeltildi: URL kurulmadan önce `^local_[A-Za-z0-9-]{1,64}$` |
| G-6 | düşük | Token'sız yerel bir süreç 12 bekleyen başlık ya da 16 bağlantı yuvasını doldurup hook kanalını tıkayabilir. Hook'lar açık kalarak (fail-open) çıkıyor | ertelendi |
| G-7 | bilgi | Bearer token ile HMAC anahtarı aynı 32 bayt | ertelendi: sunucu ve betiğin birlikte değişmesi gerekiyor |
| G-8 | bilgi | Token gizliliği dışında tekrar oynatma koruması yok | bilgi: token her açılışta yenileniyor |
| G-9 | bilgi | Release entitlements'ta `disable-library-validation` var | önceden belgeli (perl ile MediaRemote adaptörü) |

Doğrulanan, sorun olmayan noktalar:
- **`claude://` URL'si:** `URLComponents` ve `URLQueryItem` ile kuruluyor, kimlik sıkı regex ile doğrulanıyor.
- **AppleScript:** betik gövdesi sabit; tek değişken tty ve iki kez `^ttys[0-9]{1,4}$` ile doğrulanıyor. `do script` yok ve yalnızca kullanıcı tıklamasıyla çalışıyor.
- **Hook'lar:** `set -e` yok, hepsi 0 ile çıkıyor. Başlık değerlerinde CR/LF temizleniyor. Zaman sınırları: hook 1 sn, `async` 5 sn, permission 12/110 sn.
- **Sunucu:**
  - Yalnızca 127.0.0.1'e bağlanıyor.
  - Her rotada bearer token şart; karşılaştırma sabit zamanlı.
  - Origin ve Host denetleniyor.
  - Boyut, zaman ve bağlantı sınırları var.
  - Uç nokta dosyası 0600, 0700 bir dizinde.
- **Entitlements:** Apple Events istisnası yalnızca Spotify, Music, Terminal ve iTerm için; daha dar bir seçenek yok.
- **Usage description metinleri** doğru ve gerekli.
- **Gizli bilgiler:** GitHub token'ı ve HMAC anahtarı loglanmıyor.

## Ertelenen

- G-6, G-7 ve G-8 (yukarıda).
- Simge durumuna küçültülmüş Ayarlar penceresinde HUD ve Dev sayfası yoklamaları sürüyor; yalnızca kapatma durduruyor.
- Bildirimlerde ilk uygulama işaretlendikten sonra yaklaşık 7 sn'ye kadar gecikme olabiliyor. Hiçbir uygulama seçili değilken Tam Disk Erişimi'nin geri alınması, bir uygulama seçilene kadar fark edilmiyor.
- Kullanım defteri arka planda okunurken uygulama ilk saniyelerde kapanırsa o arada kaydedilen bir tur kaybolabilir (düşük olasılık).
- `NowPlayingController.stop()` perl sürecini kapatırken ana iş parçacığını 0,5 sn'ye kadar bekletebilir; önceden de böyleydi.
- Medya denetimi açıkken "Full screen behavior" seçicisi açık kalıyor, çünkü müzik dışı uygulamaları da etkiliyor.

## Kullanıcı adımları

Bunlar uygulamanın açılmasını gerektiriyor. Bu oturum uygulamayı açamıyor.

- **K-1:** Worktree'den kur: `scripts/install-local.sh --open`. Açılınca XPC'nin çalıştığını kontrol et: HUD ve bildirim gibi yardımcıya bağlı özellikler hata vermemeli. Yeni takım şartı (G-1) burada sınanıyor.
- **K-2:** `scripts/install-hooks.sh`'i yeniden çalıştır (G-3). Yeni bir Claude oturumu notch'ta görünmeli.
- **K-3:** Ayarlar → Tabs:
  - Bir sekmeyi sürükleyip sırasını değiştir; notch aynı sırayı göstermeli.
  - Shelf'i gizle.
  - Açık olduğun sekmeyi gizle; notch ilk görünür sekmeye geçmeli.
  - Son görünür sekmenin anahtarı devre dışı olmalı.
  - "Restore Defaults" düğmesini dene.
- **K-4:** Ayarlar → Notifications → "Claude Code integration" kapat:
  - Claude sekmesi ve banner'lar kaybolmalı.
  - Yeni bir izin isteği Claude'un kendi penceresinde hemen çıkmalı.
  - Dev açıkken `notchctl notify test` yine çalışmalı.
  - Anahtarı geri açınca yeni oturum görünmeli.
- **K-5:** "Open the session when you click it" kapat. Kapalı notch'taki Claude banner'ına tıklayınca Terminal öne gelmemeli, Claude sekmesi açılmalı.
- **K-6:** Ayarlar → Dev → "Enable Dev tab" kapat. `notchctl notify test` "the Dev tab is turned off" demeli.
- **K-7:** Ayarlar → Media → "Media control" kapat:
  - `pgrep -f mediaremote-adapter.pl` boş dönmeli.
  - Notch'ta oynatıcı olmamalı.
  - Geri açınca müzik görünmeli.
- **K-8:** Ayarlar → Appearance → "Enable mirror" kapat. ⌃⌥M bir şey yapmamalı.
- **K-9:** Ayarlar → Calendar:
  - Sayfayı açmak izin istememeli.
  - "Calendar"ı kapatınca tarih kapsülü ve toplantı geri sayımı kaybolmalı; ⌃⌥K bir şey yapmamalı.
- **K-10:** Ayarlar → GitHub → "GitHub integration" kapat. Dev sekmesindeki GitHub bölümü kaybolmalı; geri açınca token yeniden sorulmamalı.
- **K-11:** Boştaki CPU'yu ölç. Notch kapalı, Claude çalışmıyorken 60 sn bekle:
  ```bash
  top -l 13 -s 5 -stats pid,cpu,mem,command -pid "$(pgrep -x Nubrix)" | grep Nubrix | tail -12
  ```
  Değişikliklerden önce %0,1–0,7 ve 44 MB idi; bunu aşmamalı.
- **K-12:** Claude çalışırken notch kapalıyken etkinlik simgesi ve banner'lar eskisi gibi animasyonlu görünmeli (P-2).
