import 'package:flutter_test/flutter_test.dart';
import 'package:dostavka_app/utils/pagination.dart';

void main() {
  test('fetchAllPages stops at total and preserves every item', () async {
    final requestedPages = <int>[];

    final items = await fetchAllPages<int>(
      fetchPage: (page) async {
        requestedPages.add(page);
        return PageResult<int>(
          items: page == 1 ? [1, 2] : [3],
          total: 3,
          page: page,
          pages: 2,
        );
      },
      maxPages: 10,
      maxItems: 100,
    );

    expect(items, [1, 2, 3]);
    expect(requestedPages, [1, 2]);
  });

  test('fetchAllPages enforces maxItems', () async {
    final items = await fetchAllPages<int>(
      fetchPage: (page) async => PageResult<int>(
        items: [page * 2 - 1, page * 2],
        total: 20,
        page: page,
        pages: 10,
      ),
      maxPages: 10,
      maxItems: 3,
    );

    expect(items, [1, 2, 3]);
  });
}
