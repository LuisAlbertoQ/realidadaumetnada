import 'package:flutter/material.dart';

import '../../services/waste_catalog.dart';

/// Punto de color del contenedor (con borde cuando es blanco/amarillo).
class CategoryDot extends StatelessWidget {
  final WasteCategory category;
  final double size;

  const CategoryDot({super.key, required this.category, this.size = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: category.color,
        shape: BoxShape.circle,
        border: category.needsOutline
            ? Border.all(color: Colors.black45, width: 1)
            : null,
      ),
    );
  }
}

/// Píldora con el nombre de la categoría y su contenedor.
class CategoryBadge extends StatelessWidget {
  final WasteCategory category;
  final String? trailing;

  const CategoryBadge({super.key, required this.category, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: category.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: category.color.withValues(alpha: 0.70),
          width: 1.2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          CategoryDot(category: category),
          const SizedBox(width: 7),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              category.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: 6),
            Text(
              trailing!,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
