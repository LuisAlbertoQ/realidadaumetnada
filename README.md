# 📱 Cámara Parlante — Demo de Realidad Aumentada + Lengua Indígena

Demo móvil **100% offline (on-device)** que apunta la cámara a un objeto físico,
lo reconoce con visión computacional y **muestra su nombre en quechua en pantalla
mientras reproduce su pronunciación en audio**.

## 🎯 ¿De qué trata?

Una herramienta educativa para revalorizar lenguas originarias: el usuario apunta
la cámara (con una mirilla guía) y cuando el modelo reconoce un objeto del
diccionario con confianza ≥ 50 %, la app muestra una tarjeta flotante con la
palabra en quechua y reproduce el audio grabado. Incluye cooldown de 5 s para no
saturar el equipo (el stream va a ~30 fps).

**Objetos soportados (6):**

| Objeto (EN)         | Quechua          | Audio                          |
|---------------------|------------------|--------------------------------|
| cup                 | Puku             | `assets/audio/taza_quechua.m4a` |
| book jacket         | Liwru            | `assets/audio/libro_quechua.m4a`|
| corn                | Sara             | `assets/audio/maiz_quechua.m4a` |
| laptop              | Antañiqiq        | `assets/audio/antanikiq.mp3`    |
| computer keyboard   | Qillqana taqlla  | `assets/audio/qillqana_taqlla.mp3` |
| fountain pen        | Qillqana         | `assets/audio/qillqana.mp3`     |

> Las etiquetas en inglés son las clases exactas de ImageNet que emite el modelo
> (ej. `book jacket`, no `book`).

## 🛠️ Stack

| Capa        | Tecnología |
|-------------|------------|
| Frontend    | Flutter (Dart) |
| Cámara      | `camera` + `permission_handler` |
| ML on-device| MobileNetV2 `.tflite` + `tflite_flutter` + `image` (preproceso YUV→RGB 224×224) |
| Audio       | `audioplayers` (assets locales, `AssetSource`) |
| Datos       | `assets/data/vocabulario.json` (etiqueta EN → palabra quechua → audio) |
| AR visual   | Overlay Flutter sobre el preview (se descartó `arcore_flutter_plugin v0.1.0` por incompatibilidad con AGP 8 — sin `namespace`, rompe `assembleDebug`) |
| Exportación del modelo | Python + TensorFlow/Keras (`tools/download_model.py`, sin entrenamiento) |

## 🧩 Arquitectura

```
lib/
  main.dart                  → home: CameraScreen
  services/
    ml_service.dart          → carga .tflite + labels, predict(CameraImage)
    dictionary_service.dart  → carga vocabulario.json, lookup por label
    audio_service.dart       → reproduce AssetSource, corta anterior
  ui/
    camera_screen.dart       → StatefulWidget: stream + umbral 50% + cooldown 5 s
    widgets/
      detection_reticle.dart → mirilla central translúcida
      ar_label_card.dart     → tarjeta amarilla alto contraste (legible ~1 m)
      status_panel.dart      → "Buscando objetos..." / "¡Encontrado: X!"
assets/
  model/   → mobilenet_v2.tflite (3.8 MB cuantizado) + labels.txt (1001)
  data/    → vocabulario.json
  audio/   → .m4a/.mp3 grabados (mono 44.1 kHz)
tools/
  download_model.py → descarga MobileNetV2 (ImageNet) y lo convierte a .tflite
```

## 🚀 Cómo ejecutar

**1. Modelo (una vez, requiere Python con TensorFlow):**
```powershell
pip install tensorflow
python tools/download_model.py
Copy-Item tools/mobilenet_v2.tflite, tools/labels.txt assets/model/ -Force
```

**2. Audios:** coloca los 6 archivos con los nombres exactos de la tabla en `assets/audio/`.

**3. App:**
```powershell
flutter pub get
flutter run          # reinstalación limpia (los assets nuevos no entran con hot reload)
```

**Notas:**
- `flutter analyze` debe dar `No issues found!`.
- Si agregas audios o editas el JSON, reinstala el APK.
- Umbral de confianza: `CameraScreen._minConfidence` (actual: `0.50`).

## 👥 Integrantes

- **Luis Alberto Quila Lopes** — Tarea 3 / Grupo 3
