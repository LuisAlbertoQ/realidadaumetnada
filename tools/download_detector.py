"""PIVOTE - Descarga SSD MobileNetV2 de DETECCION (cajas, no clasificacion).
No requiere TensorFlow ni entrenamiento: descarga directa del .tflite
pre-convertido + labels COCO desde GitHub (google-coral/test_data).
Salida: detect.tflite y coco_labels.txt en el directorio actual.

Modelo: ssd_mobilenet_v2_coco_quant_postprocess (uint8, 300x300, ~6.2 MB)
  Input : 1 tensor uint8 [1, 300, 300, 3], pixeles 0-255 SIN normalizar.
  Output: 4 tensores float32:
    [0] boxes   [1, 10, 4]  (ymin, xmin, ymax, xmax) normalizados 0-1
    [1] classes [1, 10]     indice 0-89 -> linea de coco_labels.txt
    [2] scores  [1, 10]     confianza 0-1
    [3] count   [1]         nro. de detecciones validas
Labels: 90 lineas COCO (cup=46, laptop=72, keyboard=75, book=83).
  OJO: NO contiene 'corn' ni 'pen' -> esas entradas del diccionario
  quedaran dormidas; usa cup/book/laptop/keyboard para la demo.
"""
import urllib.request

BASE = "https://raw.githubusercontent.com/google-coral/test_data/master"
FILES = {
    f"{BASE}/ssd_mobilenet_v2_coco_quant_postprocess.tflite": "detect.tflite",
    f"{BASE}/coco_labels.txt": "coco_labels.txt",
}

print("Descargando detector SSD MobileNetV2...")
for url, out in FILES.items():
    print(f"  [↓] {url}")
    urllib.request.urlretrieve(url, out)

    if out.endswith(".tflite"):
        with open(out, "rb") as f:
            head = f.read(16)
        assert b"TFL3" in head, f"{out} no parece un .tflite valido"
        print(f"  [✓] {out} OK (magic TFL3 presente)")
    else:
        print(f"  [✓] {out} OK (archivo de texto)")

print("Listo. Copia ambos a assets/model/ del proyecto Flutter.")
print("Demo sugerida: cup, book, laptop, keyboard (exactos en COCO).")
