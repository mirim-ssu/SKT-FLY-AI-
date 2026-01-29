import 'dart:math';
import 'package:vibration/vibration.dart';

class HapticsEngine {
  /// 1~4 -> amplitude(0~255) 매핑
  /// 1은 무진동(0)
  /// 강/중/약 느낌을 "진폭"으로 주는 1차 시도.
  /// 값은 기기마다 체감이 달라서 slider로 스케일링 가능하게 함.
  static int ampToAmplitude(int drumAmp, double intensityScale) {
    // 기본 매핑: 2/3/4만 울림
    // (너가 원한) 4=킥(가장 강)
    final base = switch (drumAmp) {
      1 => 0,
      2 => 90,
      3 => 170,
      4 => 255,
      _ => 0,
    };

    final scaled = (base * intensityScale).round();
    return max(0, min(255, scaled));
  }

  /// 진폭 제어가 안 되면 duration 기반으로 폴백할 때 사용
  static int ampToDurationMs(int drumAmp, double durationScale) {
    final base = switch (drumAmp) {
      1 => 0,
      2 => 10,
      3 => 18,
      4 => 28,
      _ => 0,
    };
    return max(0, (base * durationScale).round());
  }

  /// (핵심) amps를 run-length encoding해서 pattern/intensities로 변환
  /// - dtMs가 5ms면 요소가 엄청 많으니까, 연속 구간을 합쳐서 길이를 줄임
  /// - 1(무진동)도 timing엔 포함시키되 intensity=0으로 처리하면
  ///   전체 타임라인이 유지됨(오디오와 싱크 맞추기 쉬움)
  static ({List<int> pattern, List<int> intensities}) buildWaveform({
    required List<int> amps,
    required int dtMs,
    required double intensityScale,
  }) {
    if (amps.isEmpty) return (pattern: <int>[], intensities: <int>[]);

    final pattern = <int>[];
    final intensities = <int>[];

    int current = amps[0];
    int run = 1;

    void flush(int value, int count) {
      final duration = count * dtMs;
      // vibration 패키지는 int ms 단위
      pattern.add(duration);
      intensities.add(ampToAmplitude(value, intensityScale));
    }

    for (int i = 1; i < amps.length; i++) {
      final a = amps[i];
      if (a == current) {
        run++;
      } else {
        flush(current, run);
        current = a;
        run = 1;
      }
    }
    flush(current, run);

    // vibration plugin은 pattern[0]을 "대기"로 해석하는 경우가 많아서
    // 시작을 즉시 울리려면 0ms 대기를 앞에 넣는 게 안전함.
    if (pattern.isNotEmpty && pattern.first != 0) {
      pattern.insert(0, 0);
      intensities.insert(0, 0);
    }

    return (pattern: pattern, intensities: intensities);
  }

  static Future<void> stop() async {
    await Vibration.cancel();
  }

  static Future<void> playWaveform({
    required List<int> pattern,
    required List<int> intensities,
  }) async {
    if (pattern.isEmpty) return;

    final hasVibrator = await Vibration.hasVibrator() ?? false;
    if (!hasVibrator) return;

    final hasCustom = await Vibration.hasCustomVibrationsSupport() ?? false; // pattern/intensity 가능 여부 :contentReference[oaicite:3]{index=3}
    if (!hasCustom) {
      // 최소 폴백: pattern만이라도
      await Vibration.vibrate(pattern: pattern);
      return;
    }

    // 진폭 제어 가능하면 intensities 사용
    final hasAmpCtrl = await Vibration.hasAmplitudeControl() ?? false;
    if (hasAmpCtrl) {
      await Vibration.vibrate(pattern: pattern, intensities: intensities);
    } else {
      // 진폭 제어가 안 되면 intensities는 무시되고 시간 패턴만 적용될 수 있음.
      // 여기선 차라리 강약을 duration으로 재구성하는 방식도 가능하지만,
      // 우선 pattern만이라도 재생.
      await Vibration.vibrate(pattern: pattern);
    }
  }
}