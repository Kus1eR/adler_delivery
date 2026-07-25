class PageResult<T> {
  const PageResult({
    required this.items,
    required this.total,
    required this.page,
    required this.pages,
  });

  final List<T> items;
  final int total;
  final int page;
  final int pages;
}

Future<List<T>> fetchAllPages<T>({
  required Future<PageResult<T>> Function(int page) fetchPage,
  int maxPages = 10,
  int maxItems = 1000,
}) async {
  final result = <T>[];
  for (var page = 1; page <= maxPages && result.length < maxItems; page++) {
    final response = await fetchPage(page);
    result.addAll(response.items.take(maxItems - result.length));
    if (page >= response.pages || result.length >= response.total) break;
  }
  return result;
}
