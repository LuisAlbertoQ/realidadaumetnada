DETECTOR ACTIVO (pivote foto + boxes):
- detect.tflite (6.2 MB): SSD MobileNetV2 COCO cuantizado uint8 300x300 CON postproceso.
  Fuente verificada: https://raw.githubusercontent.com/google-coral/test_data/master/ssd_mobilenet_v2_coco_quant_postprocess.tflite
  (el bucket clasico de TensorFlow da 403; TF Hub exige cuenta Kaggle).
  Outputs: boxes[1,10,4] + classes[1,10] (0-89) + scores[1,10] + count[1].
  Descarga: python tools/download_detector.py (sin TensorFlow).
- coco_labels.txt (90 lineas COCO, 0-based): cup=46, book=83, laptop=72, keyboard=75.
  COCO NO trae corn ni pen -> se usan bottle/chair en el diccionario.
- Invocar con runForMultipleInputs([input], {0..3}); run() simple revienta en outputs[1]!.

LEGADO (no se usa, solo referencia):
- mobilenet_v2.tflite + labels.txt (clasificador ImageNet 1001) + tools/download_model.py.
