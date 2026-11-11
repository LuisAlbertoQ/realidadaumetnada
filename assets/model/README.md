# Modelo clasificador de residuos

La app espera aquí dos archivos:

| Archivo | Obligatorio | Descripción |
|---|---|---|
| `labels.txt` | Sí | Una etiqueta por línea, en el **mismo orden** que la capa de salida del modelo. |
| `waste_classifier.tflite` | No | Clasificador de 7 clases. Si falta, la app arranca en **modo demo** con clases simuladas. |

## Características que debe cumplir el `.tflite`

| Dato | Valor |
|---|---|
| Entrada | `[1, 224, 224, 3]` **NHWC**, float32 (o int8/uint8 cuantizado) |
| Salida | `[1, 7]` **logits** (sin softmax) |
| Normalización | ImageNet: `mean=[0.485,0.456,0.406]`, `std=[0.229,0.224,0.225]` |
| Temperatura | `T = 3.1314` → `softmax(logits / T)` |
| Tamaño | 42.9 MB en float32 (ONNX 42.9 MB) |

Modelo actual: `best_model_optuna.pt` (exportado el 2026-11-08). Backbone
ResNet18 + cabeza `Linear → BatchNorm → ReLU → Dropout → Linear`, elegido por
búsqueda de hiperparámetros Optuna. La matriz de confusión de `processed/` es
del modelo anterior (2026-10-28), no de este export.

## Rendimiento (test, 4260 imágenes)

| Modelo | Preprocesamiento | Accuracy | F1 macro |
|---|---|---|---|
| optuna (actual) | resize 224×224 (el del entrenamiento) | 0.9768 | 0.9727 |
| optuna (actual) | recorte cuadrado + resize (lo que hace la app) | 0.9714 | 0.9666 |
| anterior | resize 224×224 | 0.9702 | 0.9639 |

Medido con `onnxruntime` sobre `data/splits/test.csv`; el primer valor coincide
con `docs/MODEL_CARD.md`. El recorte cuadrado de la app cuesta ~0.5 puntos
frente al resize completo, pero el modelo actual sigue por encima del anterior.

La app recorta el **cuadrado central** de la imagen y lo redimensiona a
224×224 antes de normalizar.

## Exportar desde PyTorch (ONNX → TFLite)

El modelo del repo ya está convertido. Para reexportar:

```python
import tensorflow as tf

converter = tf.lite.TFLiteConverter.from_saved_model('saved_model')
converter.optimizations = []          # float32, sin cuantizar
tflite_model = converter.convert()
open('waste_classifier.tflite', 'wb').write(tflite_model)
```

Copia el resultado como `assets/model/waste_classifier.tflite`.

> **No uses float16 en todo el grafo.** El export `..._float16.tflite` de
> `processed/` deja entrada, capas y salida en `FLOAT16`, y los kernels CPU de
> TFLite fallan con `Type FLOAT16 not currently supported` en `MAX_POOL_2D`.
> Si necesitas el modelo más pequeño, usa int8 con dataset de calibración
> (`converter.optimizations = [tf.lite.Optimize.DEFAULT]` +
> `representative_dataset`); la app ya soporta entradas int8/uint8.

## Orden de clases esperado

```
0 azul_papel_carton   -> Azul     (Papel y cartón)
1 amarillo_metales    -> Amarillo (Metales)
2 blanco_plasticos    -> Blanco   (Plásticos)
3 gris_vidrio         -> Gris     (Vidrio)
4 marron_organicos    -> Marrón   (Orgánicos)
5 rojo_peligrosos     -> Rojo     (Peligrosos)
6 negro_generales     -> Negro    (Generales / No aprovechables)
```

Si tu entrenamiento usa otros nombres, la app igual intenta resolverlos por
alias (`paper`, `cardboard`, `plastic`, `glass`, `organic`, `hazardous`,
`trash`…). Para nombres completamente distintos, agrega el alias en
`lib/services/waste_catalog.dart`.

## Validar el archivo antes de integrarlo

```powershell
python tools/verify_model.py
```

El script:

1. Genera una imagen sintética determinista.
2. La preprocesa igual que la app (recorte + resize + mean/std + NHWC).
3. Corre el `.tflite` y el `.onnx`.
4. Compara logits y muestra el `argmax` con `softmax(logits / T)`.

Salida esperada con los archivos actuales:

```
input input [1 224 224 3] float32
output logits [1 7] float32
tflite argmax = 2  p = 0.5070
onnx   argmax = 2  p = 0.5070
max abs diff = 1.3e-06
```

## Diagnóstico en la app

La ficha superior de la home muestra la entrada y salida reales del modelo
cargado, además del resultado del self-test (inferencia con una imagen gris):

```
waste_classifier.tflite · in [1, 224, 224, 3] float32 · out [1, 7] · T=3.13
Self-test: OK
```

Si la entrada o la salida no coinciden, `classifier_service.dart` muestra el
error en la misma ficha en lugar de fallar en silencio.
