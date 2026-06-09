import 'dart:io';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FakeCallPrankApp());
}

class FakeCallPrankApp extends StatelessWidget {
  const FakeCallPrankApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prank Call Recorder',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF6D4AFF),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6F7FB),
      ),
      home: const RecorderHomePage(),
    );
  }
}

enum SpeakerType { personA, personB }

class AudioChunk {
  final SpeakerType speaker;
  final String path;
  final DateTime createdAt;

  const AudioChunk({
    required this.speaker,
    required this.path,
    required this.createdAt,
  });
}

class RecorderHomePage extends StatefulWidget {
  const RecorderHomePage({super.key});

  @override
  State<RecorderHomePage> createState() => _RecorderHomePageState();
}

class _RecorderHomePageState extends State<RecorderHomePage> {
  static const MethodChannel _mediaStoreChannel = MethodChannel(
    'fake_call_prank/media_store',
  );

  final AudioRecorder _recorder = AudioRecorder();
  final List<AudioChunk> _chunks = [];

  bool _isRecording = false;
  bool _isProcessing = false;
  SpeakerType? _activeSpeaker;

  double _personBPitch = 1.25;
  int _chunkCounter = 0;
  String? _lastSavedPath;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  String get _activeSpeakerName {
    if (_activeSpeaker == SpeakerType.personA) return 'Person A (ক)';
    if (_activeSpeaker == SpeakerType.personB) return 'Person B (খ)';
    return 'None';
  }

  Future<bool> _requestPermissions() async {
    final micStatus = await Permission.microphone.request();
    if (!micStatus.isGranted) {
      _showSnack('Microphone permission is required.');
      return false;
    }

    if (Platform.isAndroid) {
      // For Android 10+ MediaStore write does not need WRITE_EXTERNAL_STORAGE.
      // For old Android devices, this may help public Downloads export.
      await Permission.storage.request();
    }

    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      _showSnack('Recorder permission was not granted.');
      return false;
    }

    return true;
  }

  Future<void> _startOrStopRecording(SpeakerType speaker) async {
    if (_isProcessing) return;

    if (_isRecording) {
      if (_activeSpeaker == speaker) {
        await _stopRecording();
      } else {
        _showSnack('Stop the current speaker first.');
      }
      return;
    }

    final allowed = await _requestPermissions();
    if (!allowed) return;

    final tempDir = await getTemporaryDirectory();
    final speakerSlug = speaker == SpeakerType.personA ? 'person_a' : 'person_b';
    final filePath = p.join(
      tempDir.path,
      'chunk_${_chunkCounter++}_${speakerSlug}_${DateTime.now().millisecondsSinceEpoch}.m4a',
    );

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 128000,
        numChannels: 1,
      ),
      path: filePath,
    );

    setState(() {
      _isRecording = true;
      _activeSpeaker = speaker;
    });
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    final speaker = _activeSpeaker;

    setState(() {
      _isRecording = false;
      _activeSpeaker = null;
    });

    if (path == null || speaker == null) {
      _showSnack('No audio file was saved.');
      return;
    }

    setState(() {
      _chunks.add(
        AudioChunk(
          speaker: speaker,
          path: path,
          createdAt: DateTime.now(),
        ),
      );
    });

    _showSnack('Chunk saved in sequence.');
  }

  Future<void> _finishAndSave() async {
    if (_isRecording) {
      _showSnack('Please stop recording first.');
      return;
    }

    if (_chunks.isEmpty) {
      _showSnack('Record at least one chunk first.');
      return;
    }

    setState(() => _isProcessing = true);

    try {
      final tempDir = await getTemporaryDirectory();
      final workingDir = Directory(
        p.join(tempDir.path, 'prank_call_${DateTime.now().millisecondsSinceEpoch}'),
      );
      if (!workingDir.existsSync()) workingDir.createSync(recursive: true);

      final processedPaths = <String>[];

      // 1) Normalize Person A chunks and pitch-shift Person B chunks.
      // The list order is not changed, so the exact conversation sequence is preserved.
      for (int i = 0; i < _chunks.length; i++) {
        final chunk = _chunks[i];
        final outputPath = p.join(workingDir.path, 'processed_$i.wav');

        if (chunk.speaker == SpeakerType.personB) {
          await _processPersonBChunk(
            inputPath: chunk.path,
            outputPath: outputPath,
            pitchFactor: _personBPitch,
          );
        } else {
          await _normalizeChunk(
            inputPath: chunk.path,
            outputPath: outputPath,
          );
        }

        processedPaths.add(outputPath);
      }

      // 2) Create concat list and merge chunks sequentially.
      final concatListPath = p.join(workingDir.path, 'concat_list.txt');
      await _writeConcatList(concatListPath, processedPaths);

      final mergedWavPath = p.join(workingDir.path, 'merged_call.wav');
      await _mergeChunks(
        concatListPath: concatListPath,
        outputPath: mergedWavPath,
      );

      // 3) Apply telephone/radio effect and create the final MP3 in temp.
      final fileName = _makeOutputFileName();
      final tempFinalMp3Path = p.join(workingDir.path, fileName);
      await _applyTelephoneEffectAndExportMp3(
        inputPath: mergedWavPath,
        outputPath: tempFinalMp3Path,
      );

      // 4) Export to Android Downloads/PrankCallRecorder using MediaStore.
      // On other platforms, save to the app documents folder.
      final exportedPath = await _exportFinalFile(
        sourcePath: tempFinalMp3Path,
        fileName: fileName,
      );

      setState(() {
        _lastSavedPath = exportedPath;
      });

      _showSnack('Saved successfully.');
    } catch (e) {
      _showSnack('Processing failed: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _normalizeChunk({
    required String inputPath,
    required String outputPath,
  }) async {
    final command = [
      '-y',
      '-i',
      _q(inputPath),
      '-ar',
      '44100',
      '-ac',
      '1',
      '-c:a',
      'pcm_s16le',
      _q(outputPath),
    ].join(' ');

    await _runFFmpeg(command, 'Normalize audio chunk');
  }

  Future<void> _processPersonBChunk({
    required String inputPath,
    required String outputPath,
    required double pitchFactor,
  }) async {
    // Pitch range is limited to keep audio understandable.
    final safePitch = pitchFactor.clamp(0.70, 1.60);

    // asetrate changes pitch and duration, so atempo reverses the duration change.
    final tempoCorrection = 1 / safePitch;
    final filter = 'asetrate=44100*$safePitch,atempo=$tempoCorrection,aresample=44100';

    final command = [
      '-y',
      '-i',
      _q(inputPath),
      '-af',
      _q(filter),
      '-ar',
      '44100',
      '-ac',
      '1',
      '-c:a',
      'pcm_s16le',
      _q(outputPath),
    ].join(' ');

    await _runFFmpeg(command, 'Pitch shift Person B chunk');
  }

  Future<void> _writeConcatList(String listPath, List<String> filePaths) async {
    final buffer = StringBuffer();
    for (final filePath in filePaths) {
      buffer.writeln("file '${_escapeConcatPath(filePath)}'");
    }
    await File(listPath).writeAsString(buffer.toString());
  }

  Future<void> _mergeChunks({
    required String concatListPath,
    required String outputPath,
  }) async {
    final command = [
      '-y',
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      _q(concatListPath),
      '-c',
      'copy',
      _q(outputPath),
    ].join(' ');

    await _runFFmpeg(command, 'Merge chunks');
  }

  Future<void> _applyTelephoneEffectAndExportMp3({
    required String inputPath,
    required String outputPath,
  }) async {
    // Classic phone-band audio is roughly 300Hz to 3400Hz.
    // Compressor + volume makes the result closer to a call recording style.
    const telephoneFilter = 'highpass=f=300,'
        'lowpass=f=3400,'
        'acompressor=threshold=-18dB:ratio=3:attack=10:release=100,'
        'volume=1.6';

    final command = [
      '-y',
      '-i',
      _q(inputPath),
      '-af',
      _q(telephoneFilter),
      '-codec:a',
      'libmp3lame',
      '-b:a',
      '128k',
      _q(outputPath),
    ].join(' ');

    await _runFFmpeg(command, 'Apply telephone effect');
  }

  Future<String> _exportFinalFile({
    required String sourcePath,
    required String fileName,
  }) async {
    if (Platform.isAndroid) {
      final result = await _mediaStoreChannel.invokeMethod<String>(
        'saveAudioToDownloads',
        {
          'sourcePath': sourcePath,
          'fileName': fileName,
        },
      );
      return result ?? sourcePath;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(docsDir.path, 'PrankCallRecorder'));
    if (!exportDir.existsSync()) exportDir.createSync(recursive: true);
    final destPath = p.join(exportDir.path, fileName);
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  Future<void> _runFFmpeg(String command, String stepName) async {
    final session = await FFmpegKit.execute(command);
    final returnCode = await session.getReturnCode();

    if (ReturnCode.isSuccess(returnCode)) return;

    final logs = await session.getAllLogsAsString();
    throw Exception('$stepName failed. Return code: $returnCode\n$logs');
  }

  String _makeOutputFileName() {
    final date = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    return 'prank_call_recording_$date.mp3';
  }

  String _q(String value) => '"${value.replaceAll('"', r'\"')}"';

  String _escapeConcatPath(String value) => value.replaceAll("'", r"'\''");

  void _deleteLastChunk() {
    if (_chunks.isEmpty || _isRecording || _isProcessing) return;
    final removed = _chunks.removeLast();
    try {
      final file = File(removed.path);
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
    setState(() {});
    _showSnack('Last chunk removed.');
  }

  void _clearAllChunks() {
    if (_isRecording || _isProcessing) return;
    for (final chunk in _chunks) {
      try {
        final file = File(chunk.path);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
    setState(() {
      _chunks.clear();
      _lastSavedPath = null;
    });
    _showSnack('All chunks cleared.');
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canFinish = _chunks.isNotEmpty && !_isRecording && !_isProcessing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prank Call Recorder'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            _noticeCard(),
            const SizedBox(height: 16),
            _statusCard(),
            const SizedBox(height: 22),
            Row(
              children: [
                _recordButton(
                  speaker: SpeakerType.personA,
                  title: 'Person A (ক)',
                  icon: Icons.person,
                  color: const Color(0xFF2563EB),
                ),
                const SizedBox(width: 12),
                _recordButton(
                  speaker: SpeakerType.personB,
                  title: 'Person B (খ)',
                  icon: Icons.record_voice_over,
                  color: const Color(0xFF7C3AED),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _pitchSlider(),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _chunks.isNotEmpty && !_isRecording && !_isProcessing
                        ? _deleteLastChunk
                        : null,
                    icon: const Icon(Icons.undo),
                    label: const Text('Remove Last'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _chunks.isNotEmpty && !_isRecording && !_isProcessing
                        ? _clearAllChunks
                        : null,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Clear All'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            const Text(
              'Recording Sequence',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _sequenceList(),
            const SizedBox(height: 26),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: canFinish ? _finishAndSave : null,
              icon: _isProcessing
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_alt),
              label: Text(
                _isProcessing ? 'Processing...' : 'Finish & Save',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
            ),
            if (_lastSavedPath != null) ...[
              const SizedBox(height: 18),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: SelectableText(
                    'Saved file:\n$_lastSavedPath',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _noticeCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFFDBA74)),
      ),
      child: const Text(
        'Use only for consent-based prank, acting, demo, or skit audio. '
        'This app records microphone audio only; it does not record real phone calls.',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _statusCard() {
    final activeColor = _isRecording ? Colors.red : Colors.green;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: activeColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: activeColor.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(_isRecording ? Icons.mic : Icons.mic_none, color: activeColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isRecording
                  ? 'Recording: $_activeSpeakerName'
                  : 'Ready. Chunks recorded: ${_chunks.length}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordButton({
    required SpeakerType speaker,
    required String title,
    required IconData icon,
    required Color color,
  }) {
    final isActive = _isRecording && _activeSpeaker == speaker;

    return Expanded(
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor: isActive ? Colors.red : color,
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ),
        onPressed: _isProcessing ? null : () => _startOrStopRecording(speaker),
        icon: Icon(isActive ? Icons.stop_circle : icon),
        label: Text(
          isActive ? 'Stop $title' : title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _pitchSlider() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Person B Voice Pitch: ${_personBPitch.toStringAsFixed(2)}x',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            Slider(
              min: 0.70,
              max: 1.60,
              divisions: 18,
              label: '${_personBPitch.toStringAsFixed(2)}x',
              value: _personBPitch,
              onChanged: _isRecording || _isProcessing
                  ? null
                  : (value) => setState(() => _personBPitch = value),
            ),
            const Text(
              'Lower = deeper. Higher = sharper. This affects only Person B chunks.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _sequenceList() {
    if (_chunks.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.black12),
        ),
        child: const Text(
          'No chunks yet. Example sequence: Person A → Person B → Person A → Person B.',
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      children: List.generate(_chunks.length, (index) {
        final chunk = _chunks[index];
        final isA = chunk.speaker == SpeakerType.personA;
        final color = isA ? const Color(0xFF2563EB) : const Color(0xFF7C3AED);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(0.25)),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: color,
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isA ? 'Person A (ক) chunk' : 'Person B (খ) chunk',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Icon(isA ? Icons.person : Icons.record_voice_over, color: color),
            ],
          ),
        );
      }),
    );
  }
}
