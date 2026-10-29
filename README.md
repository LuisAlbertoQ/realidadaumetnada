# ♻️ Clasificador de Residuos — Cámara + Foto + Video

App Flutter **100 % offline** que clasifica residuos con un **modelo TFLite
entrenado por nosotros** y muestra a qué categoría de separación pertenece:
**clase + nombre + color del contenedor + confianza**.

Es el pivote de la demo anterior de "Cámara Parlante" (quechua): se eliminaron
el diccionario y los audios, y el foco pasó a la clasificación de residuos.

> **Modelo:** `assets/model/waste_classifier.tflite` (42.7 MB, float32,
> entrada `[1,224,224,3]`, salida `[1,7]` logits). Si el archivo no está, la
> app arranca en **modo demo** con clases simuladas y todas las pantallas
> siguen siendo navegables.

## 🎯 Qué hace

| Entrada | Flujo |
|---|---|
| **Cámara en vivo** | `startImageStream` → recorte central cuadrado (YUV420→RGB) → clasificación cada ~450 ms → etiqueta estabilizada con voto mayoritario (5 cuadros) |
| **Foto (cámara o galería)** | `image_picker` → **marco ajustable** (arrastrar para mover, pellizcar o deslizador para agrandar/achicar) → clasificación de la región elegida → clase, contenedor, confianza y top-3 |
| **Video de galería** | se extraen hasta 80 fotogramas → se clasifican → se reproduce el video con la clase de cada momento + línea de tiempo de colores → resumen por clase |

No hay audios, traducción ni bottom sheets: solo **clase + nombre + contenedor
+ confianza**. Como el modelo es un **clasificador de imagen completa** (no un
detector), la app no dibuja cajas: marca con un visor el cuadrado que se
analiza. En **foto** y en **cámara en vivo** ese visor es ajustable: se puede
mover, agrandar (hasta el 100 %) o achicar (hasta el 25 %) para dejar fuera
distracciones del fondo. En la foto, al soltar el marco se vuelve a clasificar
automáticamente.

La foto tomada con la app es **temporal**: se guarda en la caché de
`image_picker`, no en la galería del teléfono.

## 🗑️ Clases y colores (Colombia)

| Índice | Etiqueta (`labels.txt`) | Categoría | Contenedor | Color |
|---|---|---|---|---|
| 0 | `azul_papel_carton` | Papel y cartón | Azul | `#1565C0` |
| 1 | `amarillo_metales` | Metales | Amarillo | `#F9A825` |
| 2 | `blanco_plasticos` | Plásticos | Blanco | `#FFFFFF` |
| 3 | `gris_vidrio` | Vidrio | Gris | `#757575` |
| 4 | `marron_organicos` | Orgánicos | Marrón | `#6D4C41` |
| 5 | `rojo_peligrosos` | Peligrosos | Rojo | `#C62828` |
| 6 | `negro_generales` | Generales / No aprovechables | Negro | `#212121` |

`WasteCatalog` resuelve las etiquetas por `id` **o por alias** (`paper`,
`cardboard`, `plastic`, `glass`, `organic`, `hazardous`, `trash`…), así que
tolera variantes del nombre de clase del entrenamiento.

## 🛠️ Stack

| Capa | Tecnología |
|---|---|
| UI | Flutter Material 3, tema oscuro |
| Cámara | `camera` 0.11 (CameraX, `yuv420`, stream de imágenes) |
| Galería | `image_picker` (Android Photo Picker, sin permisos de almacenamiento) |
| Video | `video_player` + **canal nativo Kotlin** con `MediaMetadataRetriever` para extraer fotogramas |
| ML on-device | `tflite_flutter` + `image` (recorte y preproceso) |
| Modelo | Clasificador de 7 clases, `.tflite` float32 (o int8/uint8) |

## 🧩 Arquitectura

```
lib/
  main.dart                       → arranca la carga del modelo y HomeScreen
  models/
    classification.dart           → ClassScore, Classification, SmoothedLabel
  services/
    waste_catalog.dart            → 7 categorías, colores, alias y normalización
    classifier_math.dart          → recorte cuadrado ajustable, tensor ImageNet, softmax(T), voto mayoritario
    classifier_service.dart       → TFLite: carga, inferencia, self-test, demo
    video_frames.dart             → MethodChannel waste/video_frames
  ui/
    home_screen.dart              → 3 accesos + estado del modelo + leyenda
    live_camera_screen.dart       → clasificación continua + marco ajustable
    photo_screen.dart             → foto (cámara/galería) + marco ajustable + top-3
    video_screen.dart             → análisis + reproducción + resumen
    widgets/
      result_card.dart            → tarjeta de clase/color/confianza
      crop_selector.dart          → marco arrastrable y pellizcable + máscara
      classification_timeline.dart→ franja de clases del video (con seek)
      class_summary.dart          → distribución de clases en el video
      category_badge.dart         → puntos/píldoras de color
      category_legend.dart        → leyenda de las 7 clases
      demo_banner.dart            → aviso de modo demo
      model_status_card.dart      → shapes reales, self-test y errores
android/app/src/main/kotlin/.../
  MainActivity.kt                 → registra el canal
  VideoFramesChannel.kt           → open/frame/close con MediaMetadataRetriever
assets/model/
  labels.txt                      → 7 clases en el orden de salida
  waste_classifier.tflite         → modelo float32 (obligatorio para salir de demo)
  README.md                       → cómo exportar y validar el modelo
tools/
  verify_model.py                 → compara .tflite vs .onnx con una imagen sintética
test/
  classifier_math_test.dart       → preproceso, marco ajustable, softmax, etiquetas, voto mayoritario
  crop_selector_test.dart         → gestos del marco, límites, BoxFit.cover, pantallas
  home_screen_test.dart           → smoke test de la home
```

## 🚀 Cómo ejecutar

```powershell
flutter pub get
flutter run
```

Sin `waste_classifier.tflite` la app funciona en **modo demo** (banner amarillo
y resultados simulados). Para usar el modelo real:

1. Entrena el clasificador de las 7 clases (entrada 224×224, normalización
   ImageNet, 7 logits de salida).
2. Exporta a TFLite **float32** (no conviertas todo el grafo a float16: los
   kernels CPU de TFLite no soportan `FLOAT16` en `MAX_POOL_2D`, verificado
   con `ai-edge-litert`).
3. Copia el archivo como `assets/model/waste_classifier.tflite`.
4. Verifica `assets/model/labels.txt` (mismo orden que la capa de salida).
5. Ajusta `kTemperature` en `lib/services/classifier_math.dart` si reentrenaste
   (valor actual: 3.0924).
6. Reconstruye: `flutter clean && flutter pub get && flutter run`.

La ficha de la home muestra la entrada/salida reales:

```
waste_classifier.tflite · in [1, 224, 224, 3] float32 · out [1, 7] · T=3.09
```

y el resultado del self-test (una inferencia con imagen gris al arrancar).

### Preprocesamiento exacto

```
1. Recorte cuadrado de la región elegida (por defecto el cuadrado central;
   en foto y cámara en vivo el usuario puede moverlo y redimensionarlo).
2. Resize a 224×224 (RGB).
3. (p / 255 - mean) / std   con mean=[0.485,0.456,0.406], std=[0.229,0.224,0.225]
4. Tensor NHWC [1,224,224,3] float32.
5. probs = softmax(logits / 3.0924)   →  argmax = clase
```

El marco se expresa en coordenadas normalizadas (`SquareCrop`: `size`,
`centerX`, `centerY`). `size` es la fracción del **lado menor** de la imagen
(0.25–1.0) y `clamp(aspect)` garantiza que el cuadrado nunca se salga de la
foto, también cuando la imagen es muy ancha o muy alta.

El `.tflite` ya está en **NHWC** (el ONNX de origen era NCHW); el conversor
hizo la transposición. Alimentarlo sin normalizar cambia la predicción, así que
`buildInputTensor` aplica `mean/std` siempre.

## 🎬 Análisis de video (detalle)

`VideoFramesChannel.kt` expone tres métodos por `MethodChannel`:

| Método | Devuelve |
|---|---|
| `open {path}` | `durationMs`, `width`, `height`, `rotation` |
| `frame {timeMs, maxWidth}` | JPEG (`Uint8List`) ya rotado y escalado, o `null` |
| `close` | libera el `MediaMetadataRetriever` |

El muestreo es adaptativo: `max(400 ms, duración / 80)` y como máximo 80
fotogramas. Durante la reproducción se muestra la clase del fotograma
analizado más cercano a la posición actual, la franja de colores permite
saltar a cualquier momento, y el resumen cuenta en cuántos fotogramas ganó
cada clase.

> El canal nativo está implementado **solo para Android**. En iOS el video se
> reproduce, pero el análisis muestra un aviso de no soportado. La cámara y
> las fotos sí funcionan en ambas plataformas.

## ✅ Verificación

```powershell
flutter analyze   # No issues found!
flutter test      # 24 tests: preproceso, marco ajustable, softmax(T), etiquetas, voto, gestos
flutter build apk --debug
```

Validación numérica del modelo (requiere Python con `onnxruntime` y
`ai-edge-litert`):

```powershell
python tools/verify_model.py
```

Genera una imagen sintética, la preprocesa igual que la app y compara los
logits de `.tflite` contra `.onnx`. Resultado esperado con la imagen sintética:
`argmax = 2 (blanco_plasticos)`, `p ≈ 0.7069`, diferencia máxima `≈ 2e-6`.

## ⚠️ Notas

- Umbral de confianza: **35 %** (`ClassifierService.minScore`); por debajo la
  tarjeta avisa "baja confianza" pero sigue mostrando la clase más probable.
- La cámara en vivo usa `ResolutionPreset.low` (480p) y convierte **solo el
  cuadrado central**, no el fotograma completo, para no congelar el teléfono.
  El deslizador sobre el resultado cambia el tamaño de ese recorte (25–100 %)
  y reinicia la ventana de votos para que la etiqueta no arrastre el encuadre
  anterior.
- En foto, el marco se mueve arrastrando y se redimensiona pellizcando o con
  el deslizador; al soltar se vuelve a clasificar solo la región elegida.
- La foto tomada con la app es temporal (caché de `image_picker`): no se
  escribe en la galería.
- La pantalla de cámara está bloqueada en vertical para que el recorte sea
  estable; si en tu equipo las etiquetas no coinciden con lo que ves, ajusta
  `sensorOrientation` en `live_camera_screen.dart`.
- El modelo float16 de 21 MB que venía en `processed/` **no funciona en CPU**
  (todo el grafo en FLOAT16). Para reducir tamaño hay que reexportar con
  float16 solo en pesos (I/O float32) o cuantizar a int8 con calibración; el
  servicio ya soporta entradas int8/uint8.
- `assets/model/processed/` (checkpoints, ONNX, duplicados) está ignorado por
  git: no entra al APK ni al repo.
- El flujo anterior (quechua/audio/SSD COCO) quedó respaldado en la rama
  `backup-pre-basura`.

## 👥 Integrantes

- **Luis Alberto Quila Lopes** — Tarea 3 / Grupo 3
