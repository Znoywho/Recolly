abstract final class TodayFormat {
  static String clock(DateTime time) =>
      '${_twoDigits(time.hour)}:${_twoDigits(time.minute)}';

  static String shortClock(DateTime time) =>
      '${time.hour}:${_twoDigits(time.minute)}';

  static String window(DateTime start, DateTime end) =>
      '${shortClock(start)}–${shortClock(end)}';

  static String sleepDebt(int minutes) {
    if (minutes <= 0) return 'Đủ giấc';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours == 0) return '-${rest}p';
    if (rest == 0) return '-${hours}h';
    return '-${hours}h ${_twoDigits(rest)}p';
  }

  static String duration(int minutes) {
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    if (hours == 0) return '${rest}p';
    if (rest == 0) return '${hours}h';
    return '${hours}h ${_twoDigits(rest)}p';
  }

  static String weekdayLabel(DateTime date) =>
      date.weekday == DateTime.sunday ? 'CN' : 'T${date.weekday + 1}';

  static String greeting(DateTime now) => switch (now.hour) {
    < 11 => 'Chào buổi sáng',
    < 14 => 'Chào buổi trưa',
    < 18 => 'Chào buổi chiều',
    _ => 'Chào buổi tối',
  };

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');
}
