# 📱 Cámara Parlante — Foto + Detección de Objetos + Lengua Indígena

Demo móvil **100% offline (on-device)**: el usuario toma una **foto**, la app
detecta los objetos con un modelo SSD, dibuja **bounding boxes** tocables sobre
la imagen y al tocar una caja abre un **BottomSheet** con la palabra en quechua,
su audio y oraciones de ejemplo.

> **Pivote de arquitectura:** se abandonó el flujo AR en vivo (clasificación por
> stream + overlay). El flujo actual es foto estática → detección → boxes →
> BottomSheet. Los archivos del flujo anterior (`ml_service.dart`,
> `camera_screen.dart` y widgets de Fase 5) quedan en el repo como referencia
> pero ya no se usan (`main.dart` apunta a `PhotoScreen`).

## 🎯 Flujo de la app

1. Vista de cámara full-screen + botón flotante **Capturar**.
2. La foto se congela y pasa por `detect.tflite` (SSD MobileNetV2, 300×300).
3. La foto se muestra con rectángulos (`CustomPaint`): **amarillos** si la
   etiqueta está en el diccionario, blancos si no.
4. Tap en una caja → `showModalBottomSheet` con:
   - palabra en quechua + botón 🔊 de audio,
   - sección Diccionario/Contexto con oraciones de ejemplo (cada una con su play),
   - o "Sin traducción aún" si el objeto no está en el JSON.
5. Botón **Nueva foto** (recrea la cámara desde cero; `resumePreview` se congela
   en varios Xiaomi/CameraX).

El detector reporta **hasta 10 objetos** por foto (todo lo que ve el modelo,
sin pasar por el JSON); el JSON solo decide resaltado y contenido del sheet.
Umbral por defecto: score ≥ 50 % (`detect(file, minScore: 0.5)`).

## 🛠️ Stack

| Capa         | Tecnología |
|--------------|------------|
| Frontend     | Flutter (Dart) |
| Cámara       | `camera` + `permission_handler` (foto `takePicture`, sin stream) |
| ML on-device | SSD MobileNetV2 `.tflite` (uint8 300×300, postproceso con NMS incluido) + `tflite_flutter` + `image` |
| Audio        | `audioplayers` (assets locales, `AssetSource`) |
| Datos        | `assets/data/vocabulario.json` v2 (label EN → palabra + audio + ejemplos) |
| Dibujo       | `CustomPaint` + `showModalBottomSheet` (Flutter core, sin plugins AR) |
| Descarga del modelo | Python estándar, sin TensorFlow (`tools/download_detector.py`) |

**Salidas del modelo** (`detect.tflite`, 6.2 MB): `boxes[1,10,4]` (ymin,xmin,ymax,xmax
0-1) + `classes[1,10]` (índice 0-89 a `coco_labels.txt`) + `scores[1,10]` + `count[1]`.
⚠️ Multisalida: invocar con `runForMultipleInputs([input], {0..3})` — `run()`
simple envuelve el Map como salida única y revienta en `outputs[1]!`
(bug real encontrado y corregido en esta demo).

## 🧩 Arquitectura

```
lib/
  main.dart                  → home: PhotoScreen
  services/
    detector_service.dart    → SSD: preproceso JPEG→RGB300 + inferencia + filtro score
                             (+ self-test con ceros, lastBest/lastError/lastStack en pantalla)
    dictionary_service.dart  → vocabulario.json v2 + lookup (ejemplos opcionales)
    audio_service.dart       → AssetSource, corta el audio anterior
    ml_service.dart          → [LEGADO Fase 3] clasificador, no se usa
  ui/
    photo_screen.dart        → live / processing / result + tap→sheet + retake con re-init
    camera_screen.dart       → [LEGADO Fase 4/5] stream en vivo, no se usa
    widgets/
      boxes_painter.dart     → CustomPaint de rects + chips (mapeo contain compartido)
      word_sheet.dart        → BottomSheet: palabra, audio, ejemplos
      detection_reticle.dart, ar_label_card.dart, status_panel.dart → [LEGADO]
assets/
  model/   → detect.tflite + coco_labels.txt (90 clases COCO)
  data/    → vocabulario.json (v2)
  audio/   → .m4a/.mp3 grabados
tools/
  download_detector.py → descarga SSD + labels (urllib, verificado GitHub raw 200)
  download_model.py    → [LEGADO] clasificador MobileNetV2 (requería TensorFlow)
```

**Diccionario actual (6 entradas):** cup→Puku, book→Liwru, laptop→Antañiqiq,
keyboard→Qillqana taqlla, bottle→Puyñu (REVISAR), chair→Tiyana (REVISAR).
cup/book ya tienen 3 oraciones de ejemplo c/u; resto pendiente + audios de
laptop/keyboard/bottle/chair pendientes. Las etiquetas son las exactas de COCO
(`book` y `keyboard` directos; COCO **no** tiene `corn` ni `pen`, se
reemplazaron por `bottle`/`chair`).

## 🚀 Cómo ejecutar

**1. Modelo (una vez, sin dependencias):**
```powershell
python tools/download_detector.py
Copy-Item tools/detect.tflite, tools/coco_labels.txt assets/model/ -Force
```

**2. Audios:** graba los `.m4a/.mp3` con los nombres exactos del JSON en `assets/audio/`
y cablea las oraciones en el campo `ejemplos` (`texto_quechua`, `traduccion_es`, `audio`).

**3. App:**
```powershell
flutter pub get
flutter run          # reinstalación limpia (assets nuevos no entran con hot reload)
```

**Diagnóstico en pantalla (sin logcat):** en vivo se muestra la ficha del modelo
(`in=[1,300,300,3] uint8 | outs=...`) + `Self-test: OK/FALLO`; en resultado, la
barra muestra `mejor: <label> <%>` y caja roja con error + stack si algo falla.

**Notas:**
- `flutter analyze` debe dar `No issues found!`.
- Varias instancias del mismo objeto pueden fusionarse por el NMS interno o
  quedar bajo el umbral: probar con `minScore: 0.3` y buena luz si faltan cajas.

## 👥 Integrantes

- **Luis Alberto Quila Lopes** — Tarea 3 / Grupo 3
