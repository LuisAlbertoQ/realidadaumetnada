import 'package:flutter/material.dart';

/// FASE 5.1: Mirilla central translúcida — indica dónde apuntar.
/// Recuadro 230x230 + esquinas reforzadas + cruz + punto. Pasivo.
class DetectionReticle extends StatelessWidget {
  const DetectionReticle({super.key});

  static const _edge = BorderSide(color: Colors.greenAccent, width: 4);

  Widget _corner({bool l = false, bool r = false, bool t = false, bool b = false}) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        border: Border(
          left: l ? _edge : BorderSide.none,
          right: r ? _edge : BorderSide.none,
          top: t ? _edge : BorderSide.none,
          bottom: b ? _edge : BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: SizedBox(
          width: 230,
          height: 230,
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.greenAccent.withValues(alpha: 0.55),
                    width: 2,
                  ),
                ),
              ),
              Positioned(left: 0, top: 0, child: _corner(l: true, t: true)),
              Positioned(right: 0, top: 0, child: _corner(r: true, t: true)),
              Positioned(left: 0, bottom: 0, child: _corner(l: true, b: true)),
              Positioned(right: 0, bottom: 0, child: _corner(r: true, b: true)),
              const Center(child: Icon(Icons.add, color: Colors.greenAccent, size: 40)),
              Center(
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Colors.greenAccent,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
