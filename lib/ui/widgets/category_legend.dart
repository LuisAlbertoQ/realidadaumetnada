import 'package:flutter/material.dart';

import '../../services/waste_catalog.dart';
import 'category_badge.dart';

/// Leyenda de las 7 categorías con su color de contenedor.
class CategoryLegend extends StatelessWidget {
  final List<WasteCategory> categories;

  const CategoryLegend({super.key, this.categories = WasteCatalog.categories});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        for (final category in categories) CategoryBadge(category: category),
      ],
    );
  }
}
