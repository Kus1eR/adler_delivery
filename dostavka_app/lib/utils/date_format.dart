String formatOrderDate(String isoDate) {
  final date = DateTime.parse(isoDate);
  const months = [
    'янв',
    'фев',
    'мар',
    'апр',
    'май',
    'июн',
    'июл',
    'авг',
    'сен',
    'окт',
    'ноя',
    'дек',
  ];
  return '${date.day} ${months[date.month - 1]}, '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String formatOrderDateOrOriginal(String isoDate) {
  try {
    return formatOrderDate(isoDate);
  } on FormatException {
    return isoDate;
  }
}
