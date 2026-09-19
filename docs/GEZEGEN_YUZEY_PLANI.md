# Gezegen ve uydu yüzeyi: uygulama ve devam planı

Durum: Yalnızca planlandı. Bu aşamada oyun kodu değiştirilmedi.
Kullanıcı hedefi: Gemiyi gezegene/uyduya indir, kabinden rampayla çık, engebeli gerçek 3D zeminde karakterle dolaş, gemiye geri dön ve kalkış yap.
Korunacaklar: Mevcut uzay görünümü, hız tabanlı warp, kamera yumuşatma, merkez nişangâhı ve EVA/gemi kontrol ayrımı.

## İnceleme bulguları

- `scripts/rendering/planet_lod_manager.gd`: 2.000 m parçalar, 9×9 pencere, en yakın LOD'da 36 bölme. En iyi kenar örnekleme aralığı yaklaşık 55,6 m; yürünebilir ince arazi için yetersiz. Mesafe eşikleri 300/800/2.200/6.000 m, fakat LOD seçimi 2.000 m'lik parça aralıklarından yapıldığı için ara seviyeler de etkili kullanılmıyor.
- Aynı yönetici kare başına iki üretim ve yaklaşık 1,5 ms yumuşak bütçe kullanıyor. Bu yaklaşım korunabilir; artacak geometri için CPU üretimi iş parçacığına taşınmalı.
- `planet_chunk_sphere.gd` yaklaşma sırasında farklı bir küresel ağ ve `noise(dir.x * 5, dir.z * 5) * 0.005` kullanıyor. Yer yüzeyi ise yerel metre koordinatlarından 80 m genlikli başka örnekleme yapıyor. İki görünüm aynı dağları üretmiyor.
- `scripts/main.gd` inişi sabit bir yüzey yönüne yerleştiriyor. Kalkış doğrudan 2,5 gezegen yarıçapı mesafesine taşıyor.
- Yüzey yürüyüşü konum/yükseklik hesabıyla ilerliyor; fiziksel arazi çarpışması, yürünebilir eğim ve gemi ayaklarının zemine oturma çözümü yok. Yürüyüş mesafesi iki eksende yaklaşık ±11,5 km ile sınırlı.
- Gemi kabini, kapı/rampa animasyonu, EVA ve geri binme akışları mevcut. Bu akışlar yeni yüzey fiziğine bağlanmalı.
- Gaz devlerini katı yüzeyli gezegenlerden ayıran iniş kontrolü eklenmeli.

## Uygulama sırası

### 1. Tek kayalık uydu ve ortak yükseklik kaynağı

İlk teslim kapsamı: Sabit tohumlu, tekrar bulunabilen bir kayalık uydu ve yaklaşık 2 km çapında oynanabilir iniş çevresi. Yakındaki bir kayalık gezegen ikinci doğrulama sahnesi olacak.

- `scripts/terrain/planet_surface_profile.gd`: gök cismi tohumu, katı yüzey/iniş uygunluğu, yerçekimi oyun ayarı, yükseklik ölçekleri ve malzeme paleti.
- `scripts/terrain/planet_height_sampler.gd`: gezegene bağlı koordinattan deterministik yükseklik ve normal. Büyük dağlar, orta ölçekli sırt/kraterler, küçük yüzey engebeleri ayrı frekans katmanları olacak.
- Küresel görünüm, yakın arazi, iniş sorguları aynı kaynak veriyi kullanacak. Düşük LOD yalnızca küçük detayları azaltacak; dağların konumunu değiştirmeyecek.
- Küresel boylam/kutup dikişleri için 3D yön örneklemesi; yakın detay için parça kimliği + metre ölçeğinde yerel koordinatlar. Komşu parçalar aynı sınır örneklerini paylaşacak. Büyük tek bir Vector3 üzerinde santimetre hesabı yapılmayacak.
- Renk dokusunun gürültüsü arazi yüksekliğinin tek kaynağı olmaktan çıkarılacak.

Bitiş ölçütü: Aynı tohum/koordinat aynı yüksekliği verir; farklı parçalarda ortak kenarlar eşleşir; uzaktan görülen büyük krater/tepe yakında yer değiştirmez.

### 2. Yürünebilir 3D arazi ve LOD

İlk ayar adayları; ölçümden sonra değişebilir:

| Oyuncuya uzaklık | Geometri örnek aralığı | Çarpışma |
| --- | --- | --- |
| 0–128 m | 1–2 m | Oyuncu ve gemi çevresinde etkin |
| 128–512 m | 4–8 m | Gerekli hareket alanında |
| 512 m–2 km | 16–32 m | Normalde yok |
| 2 km sonrası | Mevcut küresel LOD | Yok |

- Yakında 64–128 m parçalar; uzak halkalarda daha geniş parçalar/azaltılmış çözünürlük. Dağılım ekran hatası ve irtifayla uyarlanacak, yalnızca parça indeksine bağlı olmayacak.
- Komşu LOD farkı sınırlandırılacak; kenar dikişi ve geçiş morflaması uygulanacak. Görsel etekler gerekirse yedek olacak; fiziksel delikleri gizlemek için kullanılmayacak.
- Yeni parça hazır olana kadar eski yüzey tutulacak. İniş bölgesi öncelikli yüklenecek; oyuncu hazır olmayan çarpışmaya bırakılmayacak.
- Arazi dizileri arka planda üretilecek; sahne/mesh/fizik kaynaklarının eklenmesi ana iş parçacığında bütçeli yapılacak. İptal ve sürüm numarasıyla eski gezegen sonuçları reddedilecek.
- Görünürlük LOD'u değişirken oyuncunun altındaki çarpışma kaldırılmayacak. Yakın fizik ağı sabit bir çözünürlükte tutulacak; yüzeyle aynı üçgenlerden üretilecek.

Bitiş ölçütü: Karakter boyunda tepeler gerçek geometri olarak görünür; parça geçişinde delik, zeminden düşme veya belirgin tepe sıçraması oluşmaz.

### 3. Yüzey karakteri ve yerel fizik alanı

- `scripts/terrain/surface_frame.gd`: gezegene/uyduya bağlı yerel koordinat çerçevesi. Yakın fizik metre ölçeğinde; uzak gök cisimleri mevcut görsel ölçek sisteminde kalır. İniş noktası gezegen dönerken onunla birlikte hareket eder.
- `scripts/core/surface_walker.gd`: kapsüllü CharacterBody3D, fizik adımında yürüyüş, zemin teması, zıplama, yerçekimi, eğim sınırı ve kontrollü jetpack.
- İlk test ayarları: 3–5 m/s yürüyüş ve yaklaşık 40° yürünebilir eğim; bunlar oynanış ayarlarıdır. Uydu yerçekimi daha düşük olacak.
- Gemi kabini sınırları ve rampa fizik çarpışmaları bu yerel alana bağlanacak. Kapalı kapıdan veya gemi gövdesinden geçilmeyecek.
- Önce yüzey yürüyüşü yeni denetleyiciye taşınacak; çalışan uzay EVA sistemi korunacak. Uzay/yüzey geçişinde konum, yön ve hız açıkça aktarılacak.
- Üçüncü şahıs kamera için zemin/duvar engeli kontrolü; mevcut quaternion takibi ve nişangâh korunacak.

Bitiş ölçütü: Zeminde durma, eğimde yürüme, zıplama, çukurdan çıkma ve rampa geçişi doğru çalışır; kamera veya karakter zemine girmez.

### 4. Gerçek iniş, gemiden çıkış ve dönüş

Durumlar: Uçuş → Yaklaşma → İniş alanı hazırlanıyor → Alçalma → Park → Kabin/yüzey yürüyüşü → Geri binme → Kalkış → Uçuş.

- Hedeflenen bölgenin etrafında uygun alan seç; gemi ayakları ve rampa çıkışında yükseklik/eğim/engel sorgula. İlk sürümde yardımcı otopilot inişi; tam manuel iniş fiziği sonraki aşama.
- Örnek güvenlik ayarı: Ayak alanında yaklaşık 12° altında eğim ve açık rampa çıkışı. Uygun alan bulunamazsa iniş gerçekleşmez, HUD nedeni gösterir.
- Yakın geometri ve çarpışma hazır olduğunda yumuşak alçalma başlar. Gemi ortalama yüzey normaline sınırlı eğimle oturur; ayaklar zemine gömülmez.
- Parkta motorlar kapalı. E ile koltuktan kalk, kapıya yürü, rampayı aç, fiziksel zemine bas. Gemi gezegenin yerel çerçevesinde sabit kalır.
- Yakından rampaya dön, kabine gir, pilot koltuğuna otur; kapı kapanmadan ve çıkış alanı uygun olmadan kalkış başlamaz.
- Kalkış aynı iniş yerinden yükselir; görünür şekilde yörüngeye ışınlanma kaldırılır.
- Gaz devi ve katı yüzeyi olmayan gök cisimleri için iniş kapalı. İlk teslimde okyanusa iniş yok; yalnızca doğrulanmış katı/kuru zemin.

Bitiş ölçütü: Tek bir uyduda uçuş → iniş → çıkış → en az 500 m keşif → dönüş → kalkış zinciri, R ile kurtarma gerektirmeden tamamlanır.

### 5. Yakın yüzey görünümü ve gezegen çeşitliliği

- Eğim/yükseklik tabanlı kaya, toz, kum ve buz karışımı; yakında tekrarları azaltan triplanar malzeme ve ince normal detayları.
- Kayalık uyduda kraterler ve taşlık alan; kayalık gezegende sırtlar, tepeler, vadiler ve düz iniş cepleri.
- Yakın taşlar deterministik MultiMesh dağılımıyla eklenir; yalnızca oyuncunun çevresindeki büyük taşlar çarpışma alır. İniş alanını sonradan kapatacak taş üretilmez.
- Ölçek hissi için gölgeler, ufuk ve türe uygun atmosfer. Görüntü ayarları mevcut uzay görünümünü değiştirmez.

Bitiş ölçütü: Uydu ve gezegenin yüzeyi farklı okunur; yakındaki engebeler ışık/gölge üretir; dekor ve iniş sistemi çelişmez.

### 6. Geçişler ve performans doğrulaması

- Yörünge → alçak uçuş → yüzey → kalkış geçişinde aynı arazi özellikleri korunur. Yeni yerel yüzey hazır olmadan gezegen görünümü kapatılmaz.
- CPU üretim, mesh yükleme, fizik oluşturma, GPU kare süresi ayrı ölçülür. Hedef: tipik karede arazi güncellemelerine yaklaşık 2 ms ana iş parçacığı bütçesi; bu ölçülecek bir hedeftir, FPS garantisi değildir.
- Görünür geometri, yakın çarpışma ve önbellek için ayrı sınırlar. İniş alanı ve park edilen gemi gerektiği sürece korunur.
- İlk sürümde sınırlı keşif çevresi açıkça korunur. Gezegenin etrafında kesintisiz yürüme/yerel çerçeveyi taşıma daha sonra genişletilir; sınırsız hassasiyet varsayılmaz.

## Test ve kabul listesi

- Sabit tohum ve konumda yükseklik tekrarı; komşu parça/LOD kenarları ve negatif koordinatlar.
- Görsel ağ ile fizik zemininin aynı yüzeyi temsil etmesi; boşluk üstünde inişin bekletilmesi.
- Arazi üretimi sürerken hedef değişimi, kalkış, hızlı seyahat veya R: eski işler yanlış gezegene eklenmez.
- Farklı eğimler, krater kenarı, uydu yerçekimi, zıplama ve rampa üzerinden geri binme.
- Gemi ayakları ve çıkış alanı; gaz devine inişin reddi; kapanmamış kapıyla kalkışın engellenmesi.
- Hem kayalık gezegen hem uydu üzerinde tam döngü; gezegen dönerken park konumunun korunması.
- Kamera/EVA/warp mevcut regresyonları tekrar geçer. Gerçek GPU ile hızlı yaklaşma, iniş ve 10 dakikalık keşifte kare süreleri/bellek ölçülür.

## İlk uygulama oturumunda yapılacaklar

1. Çalışan sürümü yedekle; mevcut camera_controls, eva, travel ve streaming regresyonlarını başlangıç kontrolü olarak çalıştır.
2. Sabit tohumlu bir uydu yüzeyi test sahnesi oluştur; ortak profil/yükseklik örnekleyicisini ekle (Aşama 1).
3. Yakın arazi ve çarpışmanın küçük bir bölgesini ayağa kaldır; karakterin gerçekten bastığı zemini doğrula (Aşama 2–3 temel parçası).
4. Bu temel doğrulanmadan ana oyunun iniş akışını tümden değiştirme. Sonraki teslimde mevcut rampa/EVA döngüsüne bağla.

Devam talimatı: Bu dosyayı ve `docs/TASARIM_NOTLARI.md` belgesini oku. Önce Aşama 1 ve küçük yüzey test sahnesiyle başla. Mevcut iyi çalışan uzay, kamera ve gemi kontrollerini koru. Bu plan bir uygulama onayı yerine geçmez; kullanıcı şu anda önce planlama istedi.
