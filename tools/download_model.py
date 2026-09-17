"""FASE 2 - Descarga MobileNetV2 pre-entrenado y exporta a .tflite (Edge ML).
No entrena. Solo descarga + convierte + descarga labels.
Salida: mobilenet_v2.tflite y labels.txt en el directorio actual.
"""
import urllib.request
import tensorflow as tf

MODEL_URL_LABELS = "https://storage.googleapis.com/download.tensorflow.org/data/ImageNetLabels.txt"
OUT_TFLITE = "mobilenet_v2.tflite"
OUT_LABELS = "labels.txt"

print("[1/3] Descargando MobileNetV2 (weights=imagenet)...")
model = tf.keras.applications.MobileNetV2(
    weights="imagenet",
    input_shape=(224, 224, 3),
)
print("Modelo OK:", model.name)

print("[2/3] Convirtiendo a TFLite (optimizacion DEFAULT para edge)...")
converter = tf.lite.TFLiteConverter.from_keras_model(model)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
tflite_bytes = converter.convert()
with open(OUT_TFLITE, "wb") as f:
    f.write(tflite_bytes)
print(f"Guardado: {OUT_TFLITE} ({len(tflite_bytes)/1e6:.2f} MB)")

print("[3/3] Descargando labels.txt...")
urllib.request.urlretrieve(MODEL_URL_LABELS, OUT_LABELS)
print(f"Guardado: {OUT_LABELS}")
print("Listo. Copia ambos a assets/model/ del proyecto Flutter.")
