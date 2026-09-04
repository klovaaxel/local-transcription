const _months = [
  'januari',
  'februari',
  'mars',
  'april',
  'maj',
  'juni',
  'juli',
  'augusti',
  'september',
  'oktober',
  'november',
  'december',
];

/// A lecture is identified by its date: "1 september 2026".
String lectureDateLine(DateTime date) {
  return '${date.day} ${_months[date.month - 1]} ${date.year}';
}

/// Time of day the lecture started: "10:05".
String lectureClock(DateTime date) {
  final hours = date.hour.toString().padLeft(2, '0');
  final minutes = date.minute.toString().padLeft(2, '0');
  return '$hours:$minutes';
}

/// Running length while recording: "00:12:04".
String elapsedLine(Duration elapsed) {
  final hours = elapsed.inHours.toString().padLeft(2, '0');
  final minutes = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}
