import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';
import 'package:malinali/theme/malinali_chrome.dart';
import 'package:malinali/widgets/flow_shader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// WhatsApp-style hold-to-record control.
///
/// Hold to record, slide left to cancel, slide up to lock, release to finish.
/// Caps at [maxDuration]; then stops and calls [onRecordingComplete].
class VoiceRecordButton extends StatefulWidget {
  const VoiceRecordButton({
    super.key,
    required this.enabled,
    required this.onRecordingComplete,
    this.maxDuration = const Duration(seconds: 30),
    this.audioRecorder,
  });

  final bool enabled;
  final FutureOr<void> Function(String wavPath) onRecordingComplete;
  final Duration maxDuration;
  final AudioRecorder? audioRecorder;

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton>
    with SingleTickerProviderStateMixin {
  static const double _size = 56;

  late final AnimationController _controller;
  late final Animation<double> _buttonScale;
  late Animation<double> _timerSlide;
  late Animation<double> _lockerSlide;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<RecordState>? _recordSub;
  Timer? _timer;
  Timer? _maxTimer;

  int _recordDuration = 0;
  bool _isLocked = false;
  bool _isInitializing = false;
  bool _showLottie = false;
  bool _suppressBars = false;
  bool _ownsRecorder = true;
  RecordState _recordState = RecordState.stop;
  String? _activePath;
  String? _recordingBaseDir;

  double _cancelWidth = 0;
  final double _lockerHeight = 200;

  double _dragDy = 0;
  double _dragDx = 0;

  AudioRecorder get _audioRecorder => widget.audioRecorder ?? _recorder;

  @override
  void initState() {
    super.initState();
    _ownsRecorder = widget.audioRecorder == null;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _buttonScale = Tween<double>(begin: 1, end: 2).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticInOut),
      ),
    );
    _controller.addListener(() => setState(() {}));
    _recordSub = _audioRecorder.onStateChanged().listen((state) {
      if (mounted) setState(() => _recordState = state);
      if (state == RecordState.stop) {
        _timer?.cancel();
        _recordDuration = 0;
      } else if (state == RecordState.record) {
        _startTimer();
      } else if (state == RecordState.pause) {
        _timer?.cancel();
      }
    });
    _preWarm();
  }

  Future<void> _preWarm() async {
    try {
      // Pre-fetch and pre-create directory to save time during actual record start
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'voice_recordings'));
      if (!dir.existsSync()) await dir.create(recursive: true);
      _recordingBaseDir = dir.path;

      // Also pre-check permission (don't request, just check if already granted)
      // On some platforms, this might speed up the subsequent call.
      await _audioRecorder.hasPermission();
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _cancelWidth = MediaQuery.of(context).size.width - 48;
    // Animate from left to right (ending at right: 0)
    _timerSlide = Tween<double>(begin: _cancelWidth, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 1, curve: Curves.easeIn),
      ),
    );
    // Animate from bottom to top (ending at bottom: _size + 8)
    _lockerSlide = Tween<double>(begin: 0, end: _lockerHeight).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 1, curve: Curves.easeIn),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    _maxTimer?.cancel();
    _recordSub?.cancel();
    _controller.dispose();
    if (_ownsRecorder) {
      _recorder.dispose();
    }
    super.dispose();
  }

  Future<void> _start() async {
    if (!widget.enabled || _recordState != RecordState.stop || _isInitializing) return;
    setState(() => _isInitializing = true);
    try {
      if (!await _audioRecorder.hasPermission()) {
        if (mounted) setState(() => _isInitializing = false);
        return;
      }
      
      final String dirPath = _recordingBaseDir ?? (await getApplicationDocumentsDirectory()).path;
      final path = p.join(
        dirPath,
        'audio_${DateTime.now().millisecondsSinceEpoch}.wav',
      );
      
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          numChannels: 1,
          sampleRate: 16000,
        ),
        path: path,
      );
      _activePath = path;
      _recordDuration = 0;
      _startTimer();
      _maxTimer?.cancel();
      _maxTimer = Timer(widget.maxDuration, () async {
        if (!mounted || _recordState == RecordState.stop) return;
        await _finishRecording();
      });
    } catch (e) {
      if (kDebugMode) debugPrint('VoiceRecordButton start: $e');
    } finally {
      if (mounted) setState(() => _isInitializing = false);
    }
  }

  Future<String?> _stop() async {
    _maxTimer?.cancel();
    if (_recordState == RecordState.stop) {
      return _activePath;
    }
    try {
      final path = await _audioRecorder.stop();
      return path ?? _activePath;
    } catch (e) {
      if (kDebugMode) debugPrint('VoiceRecordButton stop error: $e');
      return _activePath;
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _recordDuration += 1);
    });
  }

  bool _isCancelled(Offset local, BuildContext context) {
    return local.dx < -(MediaQuery.of(context).size.width * 0.2);
  }

  bool _isLockedGesture(Offset local) => local.dy < -35;

  Future<void> _cancelRecording() async {
    if (_recordState == RecordState.stop && _activePath == null && !_isInitializing) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _showLottie = true;
      if (_isLocked) _suppressBars = true;
    });
    await _stop();
    final path = _activePath;
    if (path != null) {
      try {
        final f = File(path);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
    }
    _activePath = null;
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;
    setState(() {
      _showLottie = false;
      _isLocked = false;
    });
    await _controller.reverse();
    _suppressBars = false;
  }

  Future<void> _finishRecording() async {
    if (_recordState == RecordState.stop && _activePath == null && !_isInitializing) return;
    HapticFeedback.lightImpact();
    final path = await _stop();

    final bool wasLocked = _isLocked;
    if (wasLocked) {
      setState(() {
        _suppressBars = true;
        _isLocked = false;
      });
    }

    await _controller.reverse();
    if (wasLocked) _suppressBars = false;

    if (!wasLocked) {
      setState(() => _isLocked = false);
    }

    if (path == null || path.isEmpty) {
      _activePath = null;
      return;
    }
    _activePath = null;
    await widget.onRecordingComplete(path);
  }

  String _formatNumber(int n) => n < 10 ? '0$n' : '$n';

  @override
  Widget build(BuildContext context) {
    final double width = _cancelWidth > 0 ? _cancelWidth : MediaQuery.of(context).size.width - 48;
    return SizedBox(
      width: width,
      height: _isLocked ? _size + 8 : _size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.bottomRight,
        children: [
          if (!_isLocked && !_suppressBars && _controller.value > 0) ...[
            // Locker slides UP from behind the button
            Positioned(
              bottom: _size + 8 + (_lockerSlide.value - _lockerHeight),
              right: 0,
              child: Opacity(
                opacity: _controller.value.clamp(0.0, 1.0),
                child: Container(
                  height: _lockerHeight,
                  width: _size,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_size),
                    color: MalinaliChrome.success.withValues(alpha: 0.85),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      FlowShader(
                        direction: Axis.vertical,
                        child: const Icon(Icons.keyboard_arrow_up, color: Colors.black),
                      ),
                      const SizedBox(height: 8),
                      Transform.translate(
                        offset: Offset(0, (_dragDy * 0.1).clamp(-15.0, 0.0)),
                        child: Icon(
                          _dragDy < -35 ? Icons.lock_open : Icons.lock,
                          size: 20,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Timer bar slides LEFT from behind the button
            Positioned(
              right: _timerSlide.value,
              bottom: 0,
              child: Opacity(
                opacity: _controller.value.clamp(0.0, 1.0),
                child: Container(
                  height: _size,
                  width: _cancelWidth,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_size),
                    color: MalinaliChrome.redAccent,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${_formatNumber(_recordDuration ~/ 60)}:${_formatNumber(_recordDuration % 60)}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        FlowShader(
                          child: Transform.translate(
                            offset: Offset((_dragDx * 0.1).clamp(-30.0, 0.0), 0),
                            child: const Row(
                              children: [
                                Icon(Icons.keyboard_arrow_left, color: Colors.black),
                                Text(
                                  'Glisser pour annuler',
                                  style: TextStyle(color: Colors.black87),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (_isLocked)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                height: _size + 8,
                width: _cancelWidth,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: MalinaliChrome.bluePanel,
                  border: Border.all(
                    color: MalinaliChrome.yellowBorder.withValues(alpha: 0.4),
                  ),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: MalinaliChrome.redAccent),
                      onPressed: _cancelRecording,
                    ),
                    Expanded(
                      child: Text(
                        '${_formatNumber(_recordDuration ~/ 60)}:${_formatNumber(_recordDuration % 60)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: MalinaliChrome.onBlue,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.send, color: MalinaliChrome.yellowBorder),
                      onPressed: _finishRecording,
                    ),
                  ],
                ),
              ),
            ),
          if (!_isLocked)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onLongPressDown: widget.enabled
                  ? (_) {
                      _controller.forward();
                      _start();
                    }
                  : null,
              onLongPress: widget.enabled
                  ? () {
                      HapticFeedback.mediumImpact();
                      // We don't call _start() here anymore because it's started in onLongPressDown
                    }
                  : null,
              onLongPressMoveUpdate: (details) {
                setState(() {
                  _dragDy = details.localPosition.dy;
                  _dragDx = details.localPosition.dx;
                });
              },
              onLongPressEnd: widget.enabled
                  ? (details) async {
                      setState(() {
                        _dragDy = 0;
                        _dragDx = 0;
                      });
                      if (_isCancelled(details.localPosition, context)) {
                        await _cancelRecording();
                      } else if (_isLockedGesture(details.localPosition)) {
                        HapticFeedback.selectionClick();
                        setState(() => _isLocked = true);
                      } else {
                        await _finishRecording();
                      }
                    }
                  : null,
              onLongPressCancel: () async {
                setState(() {
                  _dragDy = 0;
                  _dragDx = 0;
                });
                _controller.reverse();
                // If it was just a tap, we started recording in onLongPressDown.
                // We should stop and delete it silently.
                await _stop();
                final path = _activePath;
                if (path != null) {
                  try {
                    final f = File(path);
                    if (f.existsSync()) f.deleteSync();
                  } catch (_) {}
                }
                _activePath = null;
              },
              child: Transform.translate(
                offset: Offset(
                  _dragDx.clamp(-_cancelWidth * 0.4, 0.0),
                  _dragDy.clamp(-40.0, 0.0),
                ),
                child: Transform.scale(
                  scale: _buttonScale.value,
                  alignment: Alignment.bottomRight,
                  child: Container(
                    height: _size,
                    width: _size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.enabled
                          ? MalinaliChrome.blueAction
                          : MalinaliChrome.mutedOnBlue,
                      border: Border.all(
                        color: MalinaliChrome.yellowBorder,
                        width: 2,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Icon(
                          Icons.mic,
                          color: widget.enabled
                              ? Colors.white
                              : MalinaliChrome.onBlue.withValues(alpha: 0.5),
                        ),
                        if (_isInitializing)
                          const SizedBox(
                            width: 32,
                            height: 32,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_showLottie)
            Positioned(
              bottom: 0,
              right: 0,
              child: IgnorePointer(
                child: SizedBox(
                  height: _size * 2,
                  width: _size * 2,
                  child: Lottie.asset('assets/dustbin_grey.json', repeat: false),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
