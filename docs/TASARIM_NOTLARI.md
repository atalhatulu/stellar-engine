# Uzay, gemi ve akış iyileştirmeleri

19 Eylül 2026 — Godot 4.7.2, Forward+.

## Görünüm

Referanstaki koyu uzay, soğuk beyaz/mavi yıldızlar ve yumuşak haleler esas alındı. Galaksi bandı ve parıltı azaltıldı; yıldızların boyutu ekran pikseline göre hesaplanıyor. Gerçek sistem koordinatlarından bağımsız çizim mesafesi 20.000 metre içine alındı; yakın kokpit kamerasında oluşan GPU frustum hatası giderildi.

ASTER / 07 prosedürel keşif gemisi: açık koridor, panoramik kokpit, animasyonlu gösterge ekranları, yan motorlar, açılan arka rampa, toplanan iniş takımları. Seyahatte motor parıltısı, yumuşak kamera/FOV ve hız çizgileri var. Astronot, görünür jetpack ve hareketli uzuvlarla basit prosedürel bir modeldir. Kabin sınırları kinematik; dış gövde için fiziksel çarpışma çözümü henüz yok. Paneller görsel animasyondur, uçuş telemetrisi mevcut HUD'dadır.

## Kontroller

- F: gemide dış kamera → kokpit → serbest kamera. EVA sırasında birinci/üçüncü şahıs.
- Kokpitte E: koltuktan kalk/koltuğa yakından otur. Kalkınca seyahat durur.
- WASD: kabinde yürü. Arka kapıda E ile rampayı aç; tamamen açıldıktan sonra yürüyerek dışarı çık.
- EVA: WASD, Space/Ctrl yönlü itiş; Shift hızlandırma; X fren.
- Açık rampaya yaklaşınca E: gemiye dön, kapıyı kapat, yakıt/oksijeni yenile.
- L: kask feneri. R: yeni evren; EVA/iniş durumunu da sıfırlar.
- Mevcut hedef seçimi ve G otopilot kontrolleri korunur. İniş/kalkış için dış kamera modunda E kullanılır.

## Grid geçişleri

20.000 orta ve 50.000 uzak yıldız arka plan iş parçacığında hazırlanır. Ana iş parçacığında kare başına bir MultiMesh parçası yüklenir; önceki alan 0,65 saniyelik geçiş boyunca korunur. Eski işler iptal edilebilir; yıldız kimlikleri ve tohumlar deterministiktir.

Yakın sektörler öncelik kuyruğuyla, kare başına en fazla iki sektör ve yaklaşık 1 ms iş bütçesiyle yüklenir. Tek bir işin süresi bütçeyi aşabilir. Yakın yıldız havuzu güncellemeleri birleştirilir. Arazi üretimi de karelere bölünür; eski yüzey hazır yenisi gelene kadar tutulur.

Son headless regresyon örneğinde senkron sektör çağrısı en fazla 33,86 ms, kademeli çağrı 10,59 ms; yıldız alanı ana iş parçacığı güncellemesi 1,72 / 3,95 ms ölçüldü. Bunlar eşzamanlı test yükü altındaki CPU ölçümleridir, oyun FPS sonucu değildir. GPU görsel kontrolü RX 5500 XT ile yapıldı; sabit FPS garantisi verilmez.

## Doğrulama

Proje klasöründe:

```sh
godot --headless --path . --script res://tests/streaming_regression.gd
godot --headless --path . --script res://tests/eva_regression.gd
godot --headless --path . -- --diagnostics --quit-after-diagnostics
godot --path . --script res://tests/visual_smoke.gd
```

Streaming testi deterministik geri dönüş, iptal, sınırlı düğüm sayısı ve arazi sürekliliğini denetler. EVA testi gerçek oyuncu denetleyicisinden çıkış, kapı engeli, astronomik koordinatlarda santimetrelik hareket, fren, kamera değişimi, uzak mesafeden binme reddi, dönüş ve evren sıfırlamayı denetler. Görsel test `/tmp/star-system-*.png` görüntülerini üretir.

Ana değişiklikler: `scripts/rendering/streamed_star_field.gd`, `star_field_job.gd`, `spacecraft_design.gd`, `astronaut_visual.gd`; `scripts/core/player.gd`, `spacecraft.gd`, `scripts/main.gd` ve ilgili shader'lar. Etkin oyuncu `player.gd`; eski `flycamera.gd` ana sahnede kullanılmıyor.

Düzenleme öncesi kopyalar: `/home/teha/Documents/codex-backups/` altında `star-system-20260919-115005` ve `star-system-design-20260919-120412`.

## Hıza bağlı seyahat efekti

Warp efekti artık `flight_speed_mps` ile gerçek harekete bağlıdır. Manuel uçuşta hız vektörünün büyüklüğü, yıldızlararası otopilotta hesaplanan warp hızı, sistem içi otopilotta smoothstep eğrisinin analitik türevi kullanılır. Büyük koordinatlardan iki konumu çıkarıp hız ölçülmez; seçili gaz kademesi hareket sanılmaz.

1 km/s altında iz yok; daha yüksek hızlarda logaritmik artan iki katmanlı izler, ışık hızının üzerinde ek uzunluk ve hafif çevre parıltısı var. Görüş açısı varsayılan ayarda en fazla 9 derece genişler. Efekt hızlanırken yaklaşık 0,36 saniyelik, yavaşlarken 0,20 saniyelik zaman sabitiyle geçiş yapar; animasyon fazı sürekli birikir. Kabin yürüyüşü, EVA, iniş ve haritada kapalıdır. `Spacecraft.travel_effect_strength` Inspector üzerinden 0–1,5 arasında ayarlanabilir (0: kapalı). Yeni parçacık veya yıldız düğümü eklenmez; aynı tek ekran efekti kullanılır.

`godot --headless --path . --script res://tests/travel_regression.gd` hız tepkisi, durma, mod geçişleri, 30/144 FPS tutarlılığı ve her iki otopilot hız kaynağını doğrular. Test ve RX 5500 XT üzerindeki GPU shader/görsel kontrolü geçti.

## Kamera ve kontrol düzeltmeleri

Kabin dönüşleri Euler açılarını doğrusal karıştırmak yerine dünya uzayındaki quaternion ile en kısa yönde yumuşatılıyor. Böylece ±180° sınırından geçerken ters tarafa dönme engelleniyor. Kamera durumu oyuncu düğümünden bağımsız tutulduğu için gemi/EVA dönüşlerini gecikmeli takip ediyor; kabin yürüyüşünde konum da yumuşatılıyor. `Player.camera_position_response` (10) ve `camera_rotation_response` (12) Inspector ayarlarıdır; küçük değer daha fazla gecikme verir. Binme/çıkma ve sıfırlamadaki açık kamera yerleştirmeleri anlıktır.

Gemi motorları kontrolü hem oyuncu tarafında hem Spacecraft içinde pilot sahipliğiyle sınırlandırıldı. EVA, kabin yürüyüşü, iniş ve haritada fare/WASD motorları yönlendiremez; park edilmiş motorların alev ve itici ışığı kapalıdır. HUD tek, koyu konturlu merkez nişangâhını çizer; hedef seçimi gecikmeli gerçek kamera doğrultusunu kullanır.

`godot --headless --path . --script res://tests/camera_controls_regression.gd`: 180° sınır geçişleri, gemi/EVA kamera gecikmesi, yürüyüş takibi, gerçek WASD+fare girdilerinin motorlardan ayrılması ve pilot kontrolüne dönüş doğrulanır. Kamera/kontrol, EVA ve seyahat regresyonları geçti; GPU görsel kontrolünde hata raporlanmadı.
