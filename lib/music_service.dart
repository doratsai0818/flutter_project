// lib/services/music_service.dart

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

class MusicService extends ChangeNotifier {
  static final MusicService _instance = MusicService._internal();
  factory MusicService() => _instance;
  MusicService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentPlayingScene;
  double _volume = 0.5;

  String? get currentPlayingScene => _currentPlayingScene;
  double get volume => _volume;
  AudioPlayer get audioPlayer => _audioPlayer;

  // 💡 關鍵修改 1: 定義基礎 URL，並確保它指向你 GitHub Pages 上的 music 資料夾
  // 請替換成你實際的網址！
  static const String _BASE_MUSIC_URL = 'https://doratsai0818.github.io/flutter_project/assets/music/'; 

  // 場景音樂路徑對應
  final Map<String, String> _sceneMusicPaths = {
    // 💡 關鍵修改 2: 使用完整的串流 URL
    'daily': '${_BASE_MUSIC_URL}morning.mp3',
    'christmas': '${_BASE_MUSIC_URL}christmas.mp3',
    'party': '${_BASE_MUSIC_URL}party.mp3',
    'halloween': '${_BASE_MUSIC_URL}halloween.mp3',
  };

  // 播放場景音樂
  Future<void> playSceneMusic(String sceneId) async {
    try {
      final musicPath = _sceneMusicPaths[sceneId];
      if (musicPath == null) {
        print('⚠️ 場景 $sceneId 沒有對應的音樂');
        return;
      }

      // 如果是同一個場景且正在暫停,則繼續播放
      if (_currentPlayingScene == sceneId && _audioPlayer.state == PlayerState.paused) {
        await _audioPlayer.resume();
        notifyListeners();
        print('🎵 繼續播放: $musicPath');
        return;
      }

      // 停止當前播放的音樂
      await _audioPlayer.stop();

      // ✅ 關鍵修改 3: 使用 UrlSource 載入遠端 URL
      try {
        await _audioPlayer.setSource(UrlSource(musicPath));
      } catch (e) {
        print('❌ 無法載入音樂文件 (UrlSource 錯誤): $musicPath');
        print('    錯誤: $e');
        return;
      }

      // 設定循環播放
      await _audioPlayer.setReleaseMode(ReleaseMode.loop);

      // 設定音量
      await _audioPlayer.setVolume(_volume);

      // 播放新音樂
      await _audioPlayer.resume();

      _currentPlayingScene = sceneId;
      notifyListeners();
      
      print('🎵 開始串流播放: $musicPath');
    } catch (e) {
      print('播放音樂失敗: $e');
    }
  }

  // 停止播放音樂
  Future<void> stopMusic() async {
    try {
      await _audioPlayer.stop();
      _currentPlayingScene = null;
      notifyListeners();
    } catch (e) {
      print('停止音樂失敗: $e');
    }
  }

  // 暫停播放
  Future<void> pauseMusic() async {
    try {
      await _audioPlayer.pause();
      notifyListeners();
    } catch (e) {
      print('暫停音樂失敗: $e');
    }
  }

  // 繼續播放
  Future<void> resumeMusic() async {
    try {
      if (_currentPlayingScene != null) {
        final state = _audioPlayer.state;
        print('🎵 當前狀態: $state');
        
        if (state == PlayerState.paused) {
          await _audioPlayer.resume();
          print('🎵 從暫停位置繼續播放');
        } else if (state == PlayerState.stopped || state == PlayerState.completed) {
          final musicPath = _sceneMusicPaths[_currentPlayingScene!];
          if (musicPath != null) {
            // ✅ 關鍵修改 4: 使用 UrlSource 重新開始播放
            await _audioPlayer.play(UrlSource(musicPath)); 
            await _audioPlayer.setReleaseMode(ReleaseMode.loop);
            await _audioPlayer.setVolume(_volume);
            print('🎵 重新開始串流播放');
          }
        }
      }
      notifyListeners();
    } catch (e) {
      print('繼續播放失敗: $e');
    }
  }

  // 設定音量
  Future<void> setVolume(double volume) async {
    try {
      _volume = volume.clamp(0.0, 1.0);
      await _audioPlayer.setVolume(_volume);
      notifyListeners();
    } catch (e) {
      print('設定音量失敗: $e');
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}