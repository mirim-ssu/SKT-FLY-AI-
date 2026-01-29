import 'dart:io';
import 'package:file_picker/file_picker.dart';
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

  String? wavPath;
  String? jsonPath;

  DrumJson? drum;
  String status = '파일을 선택하세요. (wav + json)';

  // 조절 파라미터
  double intensityScale = 1.0; // 진폭 스케일
  double speedScale = 1.0; // 재생 속도(오디오 + 진동 같이 적용)
  int offsetMs = 0; // 싱크 미세 조정 (+면 진동을 늦춤, -면 빠름)

  bool isPlaying = false;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> pickWav() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['wav'],
    );
    if (res?.files.single.path == null) return;

    setState(() {
      wavPath = res!.files.single.path!;
      status = 'WAV 선택됨: ${File(wavPath!).uri.pathSegments.last}';
    });
  }

  Future<void> pickJson() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
    );
    if (res?.files.single.path == null) return;

    final path = res!.files.single.path!;
    final text = await File(path).readAsString();

    DrumJson parsed;
    try {
      parsed = DrumJson.fromJsonString(text);
    } catch (e) {
      setState(() => status = 'JSON 파싱 실패: $e');
      return;
    }

    setState(() {
      jsonPath = path;
      drum = parsed;
      status = 'JSON 선택됨: dtMs=${parsed.dtMs}, len=${parsed.amps.length}, total=${(parsed.totalMs / 1000).toStringAsFixed(1)}s';
    });
  }

  Future<void> start() async {
    // ===== JSON asset 로드 =====
    try {
      final jsonText = await rootBundle.loadString('assets/converted_amps_1234.json'); //json파일
      drum = DrumJson.fromJsonString(jsonText);
    } catch (e) {
      setState(() => status = 'JSON 로드 실패: $e');
      return;
    }

    // ===== 오디오 asset 로드 =====
    try {
      await _player.setAsset('assets/drums.wav'); //wav파일
    } catch (e) {
      setState(() => status = '오디오 로드 실패: $e');
      return;
    }

    await _player.setSpeed(speedScale);

    // 진동 패턴 준비 (RLE 압축)
    final d = drum!;
    // dtMs=5를 목표로 했지만, 실제 JSON의 dtMs를 우선 존중.
    // (JSON 생성 단계에서 5ms로 만들어주면 그대로 동작)
    final dtMs = d.dtMs;

    final wf = HapticsEngine.buildWaveform(
      amps: d.amps,
      dtMs: dtMs,
      intensityScale: intensityScale,
    );

    // 기존 재생 중이면 정리
    await HapticsEngine.stop();
    await _player.stop();

    // 싱크 시작: "동시에" 시작을 최대한 맞추되,
    // offsetMs로 미세조정 가능하게 함.
    // offsetMs > 0 : 진동 늦춤
    // offsetMs < 0 : 진동 먼저(오디오를 늦출 수는 없어서, 이 경우엔 진동 패턴 앞에 무진동 구간을 줄여야 함)
    if (offsetMs >= 0) {
      await _player.play();
      if (offsetMs > 0) {
        await Future.delayed(Duration(milliseconds: offsetMs));
      }
      await HapticsEngine.playWaveform(pattern: wf.pattern, intensities: wf.intensities);
    } else {
      // 음수면: 진동을 앞당기는 대신, 오디오를 offset만큼 늦게 시작
      // (가장 간단/안전한 방식)
      await HapticsEngine.playWaveform(pattern: wf.pattern, intensities: wf.intensities);
      await Future.delayed(Duration(milliseconds: -offsetMs));
      await _player.play();
    }

    setState(() {
      isPlaying = true;
      status = '재생 시작 (dtMs=$dtMs, speed=$speedScale, intensity=$intensityScale, offset=$offsetMs ms)';
    });

    // 종료 감지
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
    return Scaffold(
      appBar: AppBar(title: const Text('Drum JSON → Haptics (Android)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(status),
            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(onPressed: pickWav, child: const Text('WAV 선택')),
                ElevatedButton(onPressed: pickJson, child: const Text('JSON 선택')),
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
              Text('dtMs=${d.dtMs} / samples=${d.amps.length} / total=${(d.totalMs / 1000).toStringAsFixed(1)}s'),
              const SizedBox(height: 12),
            ],

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
              '참고: dtMs를 5ms로 촘촘하게 하면, 기기/OS에 따라 진동이 뭉개질 수 있어요(확실하지 않음). 그래도 waveform 방식이 가장 안정적입니다.',
            ),
          ],
        ),
      ),
    );
  }
}