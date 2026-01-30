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
  String status = '데이터 로딩 중...'; // 초기 상태 메시지 변경

  // 조절 파라미터
  double intensityScale = 1.0; 
  double speedScale = 1.0; 
  int offsetMs = 0; 

  bool isPlaying = false;
  bool isDataLoaded = false; // 데이터 로드 완료 여부 플래그

  // ✅ 고정 입력(assets)
  static const String kWavAssetPath = 'assets/drums.wav';
  static const String kJsonAssetPath = 'assets/data.json';

  @override
  void initState() {
    super.initState();
    // [개선 1] 앱 시작 시 데이터 미리 로드
    _initializeData();
  }

  // 초기 데이터 로드 함수
  Future<void> _initializeData() async {
    try {
      // 1. JSON 로드
      final jsonText = await rootBundle.loadString(kJsonAssetPath);
      drum = DrumJson.fromJsonString(jsonText);
      
      // 2. 오디오 에셋 설정 (미리 로딩)
      await _player.setAsset(kWavAssetPath);
      
      setState(() {
        isDataLoaded = true;
        status = '준비 완료 (재생 버튼을 누르세요)';
      });
    } catch (e) {
      setState(() {
        status = '초기화 실패: $e\n(assets 폴더와 pubspec.yaml을 확인하세요)';
      });
    }
    
    // 종료 감지 리스너 등록
    _player.playerStateStream.listen((st) async {
      if (st.processingState == ProcessingState.completed) {
        await stop();
      }
    });
  }

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

  // 재생 시작 함수 (Start)
  Future<void> start() async {
    if (isPlaying) return;
    
    // [개선 2] 데이터가 없으면 다시 시도 (안전장치)
    if (drum == null) {
      setState(() => status = '데이터 재로딩 중...');
      await _initializeData();
      if (drum == null) return; // 그래도 없으면 중단
    }

    final d = drum!; // null 아님 보장됨

    // 1. 재생 속도 설정
    try {
      await _player.setSpeed(speedScale);
    } catch (e) {
      setState(() => status = '오디오 설정 실패: $e');
      return;
    }

    // 2. 진동 패턴 준비
    final dtMs = d.dtMs;
    final wf = HapticsEngine.buildWaveform(
      amps: d.amps,
      dtMs: dtMs,
      intensityScale: intensityScale,
    );

    // 3. 기존 재생 정리
    await HapticsEngine.stop();
    await _player.stop();

    // 4. "동시에" 시작 (싱크 조절 로직)
    // 오디오 위치를 0으로 초기화
    await _player.seek(Duration.zero);

    if (offsetMs >= 0) {
      // 오디오 먼저 시작
      await _player.play();
      if (offsetMs > 0) {
        await Future.delayed(Duration(milliseconds: offsetMs));
      }
      HapticsEngine.playWaveform(
        pattern: wf.pattern,
        intensities: wf.intensities,
      );
    } else {
      // 진동 먼저 시작
      HapticsEngine.playWaveform(
        pattern: wf.pattern,
        intensities: wf.intensities,
      );
      await Future.delayed(Duration(milliseconds: -offsetMs));
      await _player.play();
    }

    setState(() {
      isPlaying = true;
      status = '재생 중...';
    });
  }

  Future<void> stop() async {
    await HapticsEngine.stop();
    await _player.pause(); // stop 대신 pause 추천 (위치 유지)
    await _player.seek(Duration.zero); // 처음으로 되감기
    
    if (mounted) {
      setState(() {
        isPlaying = false;
        status = '정지됨';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = drum;
    final totalStr = (d == null) ? '--:--' : _formatMsToMinSec(d.totalMs);

    return Scaffold(
      appBar: AppBar(title: const Text('Drum Haptics Player')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView( // 화면 작을 때 스크롤 가능하게
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 상태 표시창
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  status,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 20),

              // 재생 컨트롤 버튼
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    // [개선 3] 데이터 로드 전에는 버튼 비활성화
                    onPressed: (isDataLoaded && !isPlaying) ? start : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('PLAY'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                      textStyle: const TextStyle(fontSize: 18),
                    ),
                  ),
                  const SizedBox(width: 20),
                  OutlinedButton.icon(
                    onPressed: isPlaying ? stop : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('STOP'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              
              // 정보 표시
              if (d != null)
                Text(
                  '파일 정보: dt=${d.dtMs}ms / 총 길이 $totalStr',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),

              const Divider(height: 40),

              // 설정 컨트롤러들
              const Text('설정 (Settings)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              
              // 1. 진폭 (Intensity)
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('진동 세기'),
                  Text('${intensityScale.toStringAsFixed(1)}x', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              Slider(
                value: intensityScale,
                min: 0.0,
                max: 2.0,
                divisions: 20,
                label: intensityScale.toStringAsFixed(1),
                onChanged: (v) => setState(() => intensityScale = v),
              ),

              // 2. 속도 (Speed)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('재생 속도'),
                  Text('${speedScale.toStringAsFixed(1)}x', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
              Slider(
                value: speedScale,
                min: 0.5,
                max: 1.5,
                divisions: 10,
                label: speedScale.toStringAsFixed(1),
                onChanged: (v) async {
                  setState(() => speedScale = v);
                  if (isPlaying) {
                    await _player.setSpeed(speedScale);
                  }
                },
              ),

              // 3. 싱크 (Offset)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('싱크 조절 (Offset)'),
                  Text('${offsetMs}ms', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                ],
              ),
              Slider(
                value: offsetMs.toDouble(),
                min: -300,
                max: 300,
                divisions: 60,
                label: '$offsetMs ms',
                onChanged: (v) => setState(() => offsetMs = v.round()),
              ),
              const Text(
                '• (+) 값: 진동이 늦게 나옴 (소리가 느릴 때)\n• (-) 값: 진동이 빨리 나옴 (진동이 느릴 때)',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}