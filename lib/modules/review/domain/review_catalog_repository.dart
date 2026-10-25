class ReviewCatalogItem {
  const ReviewCatalogItem({
    required this.key,
    required this.version,
    required this.title,
    required this.laboratory,
    required this.status,
    required this.snapshot,
    this.ingredient,
    this.presentation,
    this.source,
    this.page,
  });

  final String key, version, title, laboratory, status;
  final String? ingredient, presentation, source;
  final int? page;
  final Map<String, dynamic> snapshot;

  factory ReviewCatalogItem.read(Map<String, dynamic> row) {
    final snapshot = Map<String, dynamic>.from(row['snapshot'] as Map);
    return ReviewCatalogItem(
      key: row['source_key'] as String,
      version: row['catalog_version'] as String,
      title: row['title'] as String,
      laboratory: row['laboratory'] as String? ?? '',
      status: row['review_status'] as String? ?? 'sin_verificar',
      ingredient: row['active_ingredients'] as String?,
      presentation: row['presentation'] as String?,
      source: row['source_document'] as String?,
      page: row['source_page'] as int?,
      snapshot: snapshot,
    );
  }
}

abstract interface class ReviewCatalogRepository {
  Future<List<ReviewCatalogItem>> list(String clinic, String search, int offset);
  Future<Map<String, dynamic>> progress(String clinic);
  Future<void> report({
    required String clinic,
    required String reviewer,
    required ReviewCatalogItem item,
    required String comment,
    String? expected,
    String? source,
  });
}
