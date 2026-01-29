import 'dart:convert';

class DrumJson {
  final int version;
  final int dtMs;
  final List<int> amps; // 1~4

  const DrumJson({
    required this.version,
    required this.dtMs,
    required this.amps,
  });

  factory DrumJson.fromJsonString(String jsonStr) {
    final Map<String, dynamic> m = json.decode(jsonStr) as Map<String, dynamic>;

    final version = (m['version'] as num).toInt();
    final dtMs = (m['dtMs'] as num).toInt();

    // JSON 키 이름은 네 그림에서 "amp_ver"처럼 보였는데,
    // 실제 파일에서 무엇인지 확정이 필요할 수 있어.
    // 여기서는 amp_ver -> amps -> amp 중 하나를 허용.
    final dynamic raw = m['amp_ver'] ?? m['amps'] ?? m['amp'];
    if (raw is! List) {
      throw FormatException('amps array not found. expected key: amp_ver / amps / amp');
    }

    final amps = raw.map((e) => (e as num).toInt()).toList();

    // 검증 (1~4 고정)
    for (final a in amps) {
      if (a < 1 || a > 4) {
        throw FormatException('amp out of range (1~4): $a');
      }
    }

    return DrumJson(version: version, dtMs: dtMs, amps: amps);
  }

  int get totalMs => amps.length * dtMs;
}