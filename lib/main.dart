import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'src/drum_json.dart';
import 'src/haptics.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drum Haptics',
      theme: ThemeData(useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _player = AudioPlayer();

  DrumJson? drum;
  String status = '준비됨 (assets의 wav/json을 사용합니다)';

  // 조절 파라미터
  double intensityScale = 1.0; // 진폭 스케일
  double speedScale = 1.0; // 재생 속도(오디오 + 진동 같이 적용)
  int offsetMs = 0; // 싱크 미세 조정 (+면 진동을 늦춤, -면 진동을 빠르게)

  bool isPlaying = false;

  // ✅ 고정 입력(assets)
  // pubspec.yaml의 flutter/assets에 반드시 등록되어 있어야 함.
  static const String kWavAssetPath = 'assets/drums.wav';
  static const String kJsonAssetPath = 'assets/drum_10ms_1234.json';

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _formatMsToMinSec(int ms) {
    if (ms < 0) ms = 0;
    final totalSec = (ms / 1000).floor();
    final m = (totalSec ~/ 60).toString().padLeft(2, '0');
    final s = (totalSec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<DrumJson> _loadDrumJsonFromAssets() async {
    final jsonText = await rootBundle.loadString(kJsonAssetPath);
    return DrumJson.fromJsonString(jsonText);
  }

  Future<void> start() async {
    if (isPlaying) return;

    // 1) JSON asset 로드
    DrumJson parsed;
    try {
      parsed = await _loadDrumJsonFromAssets();
    } catch (e) {
      setState(() => status = 'JSON 로드/파싱 실패: $e');
      return;
    }
    drum = parsed;

    // 2) 오디오 asset 준비
    try {
      await _player.setAsset(kWavAssetPath);
      await _player.setSpeed(speedScale);
    } catch (e) {
      setState(() => status = '오디오 로드 실패: $e');
      return;
    }

    // 3) 진동 패턴 준비
    final d = parsed;
    final dtMs = d.dtMs;

    final wf = HapticsEngine.buildWaveform(
      amps: d.amps,
      dtMs: dtMs,
      intensityScale: intensityScale,
    );

    // 4) 기존 재생 중이면 정리
    await HapticsEngine.stop();
    await _player.stop();

    // 5) "동시에" 시작
    // 요구사항 2) 재생 버튼 누르면 노래와 진동이 함께 시작
    // - offsetMs가 0이면 거의 동시에 시작
    // - offsetMs로 사용자가 보정 가능
    if (offsetMs >= 0) {
      // 오디오 먼저 시작 후, offset만큼 늦게 진동 시작 (진동을 늦춤)
      await _player.play();
      if (offsetMs > 0) {
        await Future.delayed(Duration(milliseconds: offsetMs));
      }
      await HapticsEngine.playWaveform(
        pattern: wf.pattern,
        intensities: wf.intensities,
      );
    } else {
      // 진동 먼저 시작 후, offset만큼 늦게 오디오 시작 (진동을 빠르게)
      await HapticsEngine.playWaveform(
        pattern: wf.pattern,
        intensities: wf.intensities,
      );
      await Future.delayed(Duration(milliseconds: -offsetMs));
      await _player.play();
    }

    setState(() {
      isPlaying = true;
      status =
          '재생 시작 (dtMs=$dtMs, speed=${speedScale.toStringAsFixed(2)}, intensity=${intensityScale.toStringAsFixed(2)}, offset=$offsetMs ms)';
    });

    // 6) 종료 감지
    _player.playerStateStream.listen((st) async {
      if (st.processingState == ProcessingState.completed) {
        await stop();
      }
    });
  }

  Future<void> stop() async {
    await HapticsEngine.stop();
    await _player.stop();
    if (mounted) {
      setState(() {
        isPlaying = false;
        status = '정지';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = drum;

    final totalStr = (d == null)
        ? '--:--'
        : _formatMsToMinSec(d.totalMs);

    return Scaffold(
      appBar: AppBar(title: const Text('Drum JSON → Haptics (Android)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(status),
            const SizedBox(height: 12),

            // ✅ 요구사항 1) 사용자 파일 선택 UI 제거
            // ✅ 요구사항 2) 재생 버튼 누르면 함께 시작
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: isPlaying ? null : start,
                  child: const Text('▶ 재생'),
                ),
                OutlinedButton(
                  onPressed: isPlaying ? stop : null,
                  child: const Text('■ 정지'),
                ),
              ],
            ),

            const SizedBox(height: 16),
            if (d != null) ...[
              Text(
                'dtMs=${d.dtMs} / samples=${d.amps.length} / total=$totalStr',
              ),
              const SizedBox(height: 12),
            ] else ...[
              const Text('아직 JSON을 로드하지 않았습니다. (재생을 누르면 assets에서 자동 로드)'),
              const SizedBox(height: 12),
            ],

            // ✅ 요구사항 3) 사용자에게 설명 추가
            const Text(
              '설명',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              '• 진폭 스케일: 진동 세기를 전체적으로 키우거나 줄입니다.\n'
              '  (1.0이 기본, 0.5면 절반 느낌, 1.2면 조금 더 강하게)\n'
              '• 재생 속도: 노래 재생 속도를 바꾸며, 진동도 같이 빨라지거나 느려지게 의도했습니다.\n'
              '• 싱크 오프셋(ms): 노래와 진동 타이밍이 어긋날 때 맞추는 값입니다.\n'
              '  + 값: 진동을 늦춤 \n'
              '  - 값: 진동을 빠르게(오디오를 늦게 시작)',
            ),
            const SizedBox(height: 12),

            Text('진폭 스케일: ${intensityScale.toStringAsFixed(2)}'),
            Slider(
              value: intensityScale,
              min: 0.2,
              max: 1.2,
              onChanged: (v) => setState(() => intensityScale = v),
            ),

            Text('재생 속도: ${speedScale.toStringAsFixed(2)}'),
            Slider(
              value: speedScale,
              min: 0.5,
              max: 1.5,
              onChanged: (v) async {
                setState(() => speedScale = v);
                if (isPlaying) {
                  await _player.setSpeed(speedScale);
                }
              },
            ),

            Text('싱크 오프셋(ms): $offsetMs'),
            Slider(
              value: offsetMs.toDouble(),
              min: -200,
              max: 200,
              divisions: 40,
              onChanged: (v) => setState(() => offsetMs = v.round()),
            ),

            const SizedBox(height: 8),
            const Text(
              '참고: dtMs를 5ms로 촘촘하게 하면, 기기/OS에 따라 진동이 뭉개질 수 있어요.',
            ),
          ],
        ),
      ),
    );
  }
}