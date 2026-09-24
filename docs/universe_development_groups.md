# Evren Geliştirme Grupları

## Grup 1 — Kimlik ve koordinat temeli

- [x] Galaksi, yıldız, gezegen ve uydu için kalıcı hiyerarşik kimlik
- [x] Nesnelerde `parent_id`, `galaxy_id` ve `system_id` bağları
- [x] Yıldız verisinde sektör + yerel metre tabanlı `GalacticPosition`
- [x] Aynı seed ile aynı kimlik ağacını doğrulayan regresyon testi
- [x] Oyuncu konumunu `main_galaxy` içinde sektör + yerel konuma geçirmek
- [x] Kayıt dosyasının keşfedilen nesneleri kalıcı kimlikleriyle saklaması

## Grup 2 — Galaksi akışı ve LOD

- [x] Galaksileri uzaklık ve ekran boyutuna göre nokta, görsel galaksi ve etkin yıldız kataloğu olarak üç kademede yayınlamak
- [x] Yalnız etkin galaksinin yıldız kataloğunu bellekte tutmak
- [x] Üretim/silme işlerini karelere bölerek ani FPS düşüşlerini önlemek

## Grup 3 — Yıldız sistemi, yörünge ve zaman

- [x] Yıldız sistemi sınırını yıldız kütlesi ve en dış yörüngeden türetmek
- [x] Kepler tabanlı yörünge periyotlarını ortak simülasyon saatine bağlamak
- [ ] Uzak sistemleri analitik konumla, yakın sistemi etkin düğümlerle güncellemek

## Grup 4 — Gezegen LOD ve kesintisiz yüzey

- [x] Küre görünümünden arazi chunk'larına ekran alanına göre kademeli geçiş
- [ ] Kamera bakış yönüne öncelik veren quadtree bütçesi
- [x] Görsel yüzey ve çarpışma yüksekliğini aynı örnekleyiciden üretmek

## Grup 5 — Teleskop, hedefleme ve kozmik harita

- [x] Hedef hassasiyetini açısal boyuta ve yakınlaştırmaya bağlamak
- [x] Galaksi, yıldız, gezegen ve uydu için tek hedefleme akışı
- [x] Keşfedilen nesneleri kalıcı katalog ve rota planlayıcıda göstermek

## Grup 6 — Astrofiziksel üretim kuralları

- [x] Yıldız metalikliği/yaşı ile gezegen dağılımını ilişkilendirmek
- [x] Yaşanabilir bölge, gelgit kilidi ve atmosfer olasılıklarını fiziksel veriden türetmek
- [x] Galaksi morfolojisinin yıldız popülasyonlarına etkisini üretime katmak
