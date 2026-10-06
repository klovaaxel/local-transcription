/// What the record screen says under the meter. Live text, cloud (nothing
/// until the file is uploaded), or local with live text turned off (the
/// recording is still transcribed after stop).
String recordCaptionBody({
  required bool live,
  required bool cloud,
  required String captions,
}) {
  if (live) {
    if (captions.isEmpty) {
      return 'Texten dyker upp när något sagts. Staplarna ovan rör sig när '
          'mikrofonen hör dig.';
    }
    return captions;
  }
  if (cloud) {
    return 'Molnet transkriberar efter lektionen. Staplarna ovan rör sig '
        'när mikrofonen hör dig.';
  }
  return 'Texten kommer när inspelningen är transkriberad. Staplarna ovan '
      'rör sig när mikrofonen hör dig.';
}
