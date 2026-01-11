import 'dart:async';
import 'dart:io';
import 'package:vosk_flutter/vosk_flutter.dart';
import 'package:permission_handler/permission_handler.dart';

/// Service for French speech recognition using Vosk
class SpeechRecognitionService {
  final _vosk = VoskFlutterPlugin.instance();
  final _modelLoader = ModelLoader();
  
  Model? _model;
  Recognizer? _recognizer;
  SpeechService? _speechService;
  
  bool _isInitialized = false;
  bool _isListening = false;
  
  StreamSubscription<String>? _partialSubscription;
  StreamSubscription<String>? _resultSubscription;
  
  // Callback for recognized text
  Function(String)? onResult;
  Function(String)? onPartialResult;
  Function()? onError;

  /// Initialize the Vosk model from assets
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // Check microphone permission
      final permissionStatus = await Permission.microphone.request();
      if (!permissionStatus.isGranted) {
        throw Exception('Microphone permission not granted');
      }

      // Load model from zip file using ModelLoader
      print('📦 Loading Vosk French model from zip file...');
      final modelPath = await _modelLoader.loadFromAssets('assets/vosk-model-small-fr-0.22.zip');
      print('✅ Model loaded from zip: $modelPath');
      
      // Create model object from extracted directory path
      print('🔧 Creating model from: $modelPath');
      _model = await _vosk.createModel(modelPath);
      
      // Create recognizer
      _recognizer = await _vosk.createRecognizer(
        model: _model!,
        sampleRate: 16000,
      );
      
      // For Android, initialize speech service
      if (Platform.isAndroid) {
        _speechService = await _vosk.initSpeechService(_recognizer!);
      }
      
      _isInitialized = true;
      print('✅ Vosk speech recognition initialized');
    } catch (e) {
      print('❌ Error initializing Vosk: $e');
      onError?.call();
      rethrow;
    }
  }


  /// Start listening for speech
  Future<void> startListening() async {
    if (!_isInitialized) {
      await initialize();
    }

    if (_isListening) {
      return;
    }

    try {
      if (Platform.isAndroid && _speechService != null) {
        // Android: Use SpeechService
        await _speechService!.start();
        
        // Listen to partial results
        _partialSubscription = _speechService!.onPartial().listen(
          (partialText) {
            final text = _extractTextFromJson(partialText);
            if (text.isNotEmpty) {
              onPartialResult?.call(text);
            }
          },
          onError: (error) {
            print('Partial result stream error: $error');
            onError?.call();
          },
        );
        
        // Listen to final results
        _resultSubscription = _speechService!.onResult().listen(
          (resultText) {
            final text = _extractTextFromJson(resultText);
            if (text.isNotEmpty) {
              onResult?.call(text);
            }
          },
          onError: (error) {
            print('Result stream error: $error');
            onError?.call();
          },
        );
      } else {
        // Non-Android platforms would need record package
        // For now, throw an error
        throw Exception('Speech recognition is only supported on Android. For other platforms, use the record package.');
      }
      
      _isListening = true;
    } catch (e) {
      print('Error starting speech recognition: $e');
      _isListening = false;
      onError?.call();
      rethrow;
    }
  }

  /// Stop listening for speech
  Future<void> stopListening() async {
    if (!_isListening) return;

    _isListening = false;
    
    // Cancel stream subscriptions
    await _partialSubscription?.cancel();
    _partialSubscription = null;
    await _resultSubscription?.cancel();
    _resultSubscription = null;
    
    // Stop speech service (Android)
    if (Platform.isAndroid && _speechService != null) {
      try {
        await _speechService!.stop();
      } catch (e) {
        print('Error stopping speech service: $e');
      }
    }
  }

  /// Extract text from Vosk JSON result
  String _extractTextFromJson(String jsonResult) {
    try {
      // Vosk returns JSON like: {"text": "recognized text"}
      // Simple extraction without full JSON parsing
      final textMatch = RegExp(r'"text"\s*:\s*"([^"]*)"').firstMatch(jsonResult);
      if (textMatch != null) {
        return textMatch.group(1) ?? '';
      }
      return '';
    } catch (e) {
      print('Error parsing Vosk result: $e');
      return '';
    }
  }

  /// Check if currently listening
  bool get isListening => _isListening;

  /// Dispose resources
  void dispose() {
    stopListening();
    _speechService = null;
    _recognizer = null;
    _model = null;
    _isInitialized = false;
  }
}
