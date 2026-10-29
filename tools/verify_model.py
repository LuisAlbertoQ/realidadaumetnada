"""Compara el .tflite con el .onnx usando una imagen sintética determinista.

Uso:
    python tools/verify_model.py
    python tools/verify_model.py --tflite assets/model/waste_classifier.tflite

Requiere numpy y ai-edge-litert (u onnxruntime para la comparación).
Es la contraparte en Python de las constantes de `test/classifier_math_test.dart`.
"""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_TFLITE = ROOT / "assets/model/waste_classifier.tflite"
DEFAULT_ONNX = ROOT / "assets/model/processed/waste_classifier.onnx"

SIZE = 224
MEAN = np.array([0.485, 0.456, 0.406], np.float32)
STD = np.array([0.229, 0.224, 0.225], np.float32)
TEMPERATURE = 3.092362530435132

LABELS = [
    "azul_papel_carton",
    "amarillo_metales",
    "blanco_plasticos",
    "gris_vidrio",
    "marron_organicos",
    "rojo_peligrosos",
    "negro_generales",
]


def synthetic_image() -> np.ndarray:
    """Mismo generador que el test de Dart (224x224 RGB 0-255)."""
    ys, xs = np.mgrid[0:SIZE, 0:SIZE]
    return np.stack(
        [
            xs * 255 // (SIZE - 1),
            ys * 255 // (SIZE - 1),
            (xs + ys) * 255 // (SIZE + SIZE - 2),
        ],
        axis=-1,
    ).astype(np.float32)


def preprocess(image: np.ndarray) -> np.ndarray:
    """NHWC normalizado, como `buildInputTensor` en Dart."""
    return ((image / 255.0 - MEAN) / STD)[None].astype(np.float32)


def softmax(logits: np.ndarray, temperature: float = TEMPERATURE) -> np.ndarray:
    scaled = logits.astype(np.float64) / temperature
    exp = np.exp(scaled - scaled.max())
    return exp / exp.sum()


def run_tflite(path: Path, tensor: np.ndarray) -> np.ndarray:
    from ai_edge_litert.interpreter import Interpreter

    interpreter = Interpreter(model_path=str(path), num_threads=4)
    interpreter.allocate_tensors()
    inp = interpreter.get_input_details()[0]
    out = interpreter.get_output_details()[0]

    if inp["dtype"] == np.float16:
        raise SystemExit(
            "El modelo tiene entrada float16: los kernels CPU de TFLite no lo "
            "soportan. Reexporta en float32 o int8."
        )

    data = tensor
    if inp["dtype"] in (np.int8, np.uint8):
        scale, zero = inp["quantization"]
        info = np.iinfo(inp["dtype"])
        data = np.clip(np.round(tensor / scale + zero), info.min, info.max).astype(
            inp["dtype"]
        )

    print(f"input  {inp['name']} {inp['shape']} {inp['dtype'].__name__}")
    print(f"output {out['name']} {out['shape']} {out['dtype'].__name__}")

    interpreter.set_tensor(inp["index"], data)
    interpreter.invoke()
    return interpreter.get_tensor(out["index"])[0]


def run_onnx(path: Path, tensor: np.ndarray) -> np.ndarray:
    import onnxruntime as ort

    options = ort.SessionOptions()
    options.log_severity_level = 3
    session = ort.InferenceSession(
        str(path), options, providers=["CPUExecutionProvider"]
    )
    # El ONNX de origen está en NCHW.
    return session.run(None, {"input": tensor.transpose(0, 3, 1, 2)})[0][0]


def report(name: str, logits: np.ndarray) -> int:
    probabilities = softmax(logits)
    index = int(probabilities.argmax())
    print(
        f"{name:6s} argmax = {index} ({LABELS[index]})  "
        f"p = {probabilities[index]:.4f}"
    )
    return index


def main() -> None:
    global TEMPERATURE

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tflite", type=Path, default=DEFAULT_TFLITE)
    parser.add_argument("--onnx", type=Path, default=DEFAULT_ONNX)
    parser.add_argument("--temperature", type=float, default=TEMPERATURE)
    args = parser.parse_args()

    TEMPERATURE = args.temperature

    if not args.tflite.exists():
        raise SystemExit(f"No existe {args.tflite}")

    tensor = preprocess(synthetic_image())
    tflite_logits = run_tflite(args.tflite, tensor)
    tflite_index = report("tflite", tflite_logits)

    if args.onnx.exists():
        onnx_logits = run_onnx(args.onnx, tensor)
        onnx_index = report("onnx", onnx_logits)
        diff = float(np.abs(tflite_logits - onnx_logits).max())
        print(f"max abs diff = {diff:.2e}")
        if tflite_index != onnx_index or diff > 1e-3:
            raise SystemExit("Los modelos NO coinciden.")
        print("OK: .tflite y .onnx coinciden.")
    else:
        print(f"(sin ONNX en {args.onnx}: solo se reporta el .tflite)")


if __name__ == "__main__":
    main()
