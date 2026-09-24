# Stellar Engine

Stellar Engine, Godot 4 (3D) üzerinde geliştirilmiş; prosedürel yıldız sistemleri, çok katmanlı GPU tabanlı yıldız alanları (starfield), dinamik gezegen LOD (Level of Detail) yüzey arazi üretimi ve serbest uçuş kamerası içeren açık dünya uzay motoru ve keşif simülasyonudur.

---

## Öne Çıkan Özellikler

- **Prosedürel Yıldız ve Gezegen Üretimi**:
  - Spektral sınıflandırmaya uygun gerçekçi yıldız tipleri (Mavi Dev, Kırmızı Dev, Sarı Cüce, Beyaz Cüce vb.).
  - Yörünge mekaniği, gezegen ve uydu hiyerarşileri.
- **Çok Katmanlı GPU Yıldız Alanı**:
  - **Yakın Alan**: Fiziksel ölçekli, mesafeye ve parlaklığa göre kadir derecelendirmeli `StarVisualPool` MultiMesh sistemi.
  - **Orta Alan**: GPU tabanlı `mid_field_stars` shader katmanı.
  - **Derin Galaktik Fon**: İğne ucu mikro yıldız tozu `deep_field_stars` shader katmanı.
- **Dinamik Gezegen LOD & Yüzey Arazisi**:
  - Quad-tree tabanlı LOD (Level of Detail) parça yönetimi.
  - Yüzeye yaklaşırken kesintisiz iniş ve detay artışı.
  - Ekvator / ılıman enlem iniş kılavuzu.
  - Çarpışma ve zemin yüksekliği hesaplama optimizasyonu.
  - **LOD Telemetrisi (I)**: LOD 0–11 parça dağılımını ve aktif arazi durumunu gösterir. **V** parçaları seviyelerine göre renklendirir.
- **Gelişmiş HUD ve Telemetri**:
  - Cam efektli hedef kilitleme, analiz ve seyahat paneli.
  - Gerçek zamanlı LOD parça telemetri kartı (aktif parça sayısı, grid konumu, kuyruk ve üretim süreleri).
- **Serbest Kamera Keşfi**:
  - Uzayda ve gezegen yüzeyinde kesintisiz serbest kamera dolaşımı.
  - Yüzey feneri ve fiziksel zemin etkileşimi.

---

## Kontroller

| Tuş / Girdi | İşlev |
| :--- | :--- |
| **W, A, S, D** | Serbest kamera hareketi |
| **Mouse Sağ Tık + Sürükle** | Kamera serbest bakış açısı |
| **Mouse Sol Tık / C** | Hedef gökcismine odaklan / Analiz et / Seçimi temizle |
| **Shift + Sol Tık** | Seçili gökcismine otopilot ile seyahat |
| **L** | Gezegene iniş yap / yüzeyden kalk |
| **H** | Kask fenerini aç/kapat |
| **Space / Ctrl** | Dikey eksende yükselme / alçalma (Uzay uçuşu) |
| **Shift (Basılı)** | Hızlı itki / Koşma |
| **I** | Arazi LOD telemetri kartını aç/kapat |
| **V** | Arazi parçalarını LOD seviyesine göre renklendir |
| **M** | Yıldız haritası modunu aç / kapat |

---

## Kurulum ve Çalıştırma

1. Projeyi klonlayın:
   ```bash
   git clone https://github.com/atalhatulu/stellar-engine.git
   cd stellar-engine
   ```
2. Godot 4.2+ ile projeyi açın veya komut satırından çalıştırın:
   ```bash
   godot --path .
   ```

### Testleri Çalıştırma

Regresyon test setini çalıştırmak için:
```bash
godot --headless -s tests/camera_controls_regression.gd
godot --headless -s tests/travel_regression.gd
godot --headless -s tests/surface_terrain_regression.gd
godot --headless -s tests/starfield_map_regression.gd
godot --headless -s tests/planet_lod_collision_regression.gd
```

---

## Lisans

Bu proje MIT lisansı ile lisanslanmıştır.
