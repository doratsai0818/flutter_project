//fan_control_page.dart

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

// 風扇控制頁面
class FanControlPage extends StatefulWidget {
  final String jwtToken;
  const FanControlPage({super.key, required this.jwtToken});

  @override
  State<FanControlPage> createState() => _FanControlPageState();
}

class _FanControlPageState extends State<FanControlPage> {
  final String _baseUrl = 'http://localhost:3000/api';

  // 風扇狀態變數
  bool _isFanOn = false;
  int _fanSpeed = 0; // 0: 關閉, 1-4: 轉速
  bool _isOscillationOn = false;
  String _currentMode = 'normal';
  int _timerMinutes = 0;
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';

  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _fetchFanStatus();
    // 設定定時器，每隔5秒更新狀態
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchFanStatus();
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  // 獲取風扇狀態
  Future<void> _fetchFanStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/fan/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.jwtToken}',
        },
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] && responseData['data'] != null) {
          final data = responseData['data'];
          setState(() {
            _isFanOn = data['isOn'] ?? false;
            _fanSpeed = data['speed'] ?? 0;
            _isOscillationOn = data['oscillation'] ?? false;
            _currentMode = data['mode'] ?? 'normal';
            _timerMinutes = data['timerMinutes'] ?? 0;
            _hasError = false;
            _errorMessage = '';
          });
        }
      } else if (response.statusCode == 401) {
        setState(() {
          _hasError = true;
          _errorMessage = '認證失效，請重新登入';
        });
      } else if (response.statusCode == 403) {
        setState(() {
          _hasError = true;
          _errorMessage = '權限不足，無法控制風扇';
        });
      } else {
        debugPrint('獲取風扇狀態失敗: ${response.statusCode} ${response.body}');
        setState(() {
          _hasError = true;
          _errorMessage = '無法獲取風扇狀態 (HTTP ${response.statusCode})';
        });
      }
    } catch (e) {
      debugPrint('無法獲取風扇狀態: $e');
      setState(() {
        _hasError = true;
        _errorMessage = '網路連線失敗，請檢查伺服器狀態';
      });
    }
  }

  // 發送控制指令
  Future<void> _sendControlCommand(String endpoint, Map<String, dynamic> body) async {
    setState(() => _isLoading = true);
    
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/fan/$endpoint'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.jwtToken}',
        },
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        await _fetchFanStatus(); // 指令成功後重新獲取狀態
        _showSnackBar('操作成功');
      } else if (response.statusCode == 401) {
        _showSnackBar('認證失效，請重新登入', isError: true);
      } else if (response.statusCode == 403) {
        _showSnackBar('權限不足，無法控制風扇', isError: true);
      } else {
        final responseData = jsonDecode(response.body);
        _showSnackBar(responseData['message'] ?? '控制失敗', isError: true);
      }
    } catch (e) {
      debugPrint('發送控制指令失敗: $e');
      _showSnackBar('網路連線失敗，請檢查伺服器狀態', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
          duration: Duration(seconds: isError ? 4 : 2),
        ),
      );
    }
  }

  // 風速按鈕的 UI
  Widget _buildSpeedButton(int speed) {
    bool isSelected = _isFanOn && _fanSpeed == speed;
    return ElevatedButton(
      onPressed: _isLoading ? null : () => _sendControlCommand('speed', {'speed': speed}),
      style: ElevatedButton.styleFrom(
        foregroundColor: isSelected ? Colors.white : Colors.black,
        backgroundColor: isSelected ? Colors.blue : Colors.grey[200],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      ),
      child: Text('$speed'),
    );
  }

  // 模式按鈕的 UI
  Widget _buildModeButton(String mode, String label) {
    bool isSelected = _isFanOn && _currentMode == mode;
    return ElevatedButton(
      onPressed: _isLoading ? null : () => _sendControlCommand('mode', {'mode': mode}),
      style: ElevatedButton.styleFrom(
        foregroundColor: isSelected ? Colors.white : Colors.black,
        backgroundColor: isSelected ? Colors.blue : Colors.grey[200],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      child: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _hasError
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '連線失敗',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _fetchFanStatus,
                      child: const Text('重新連線'),
                    ),
                  ],
                ),
              ),
            )
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 狀態顯示區塊
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.2),
                            spreadRadius: 2,
                            blurRadius: 5,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            _isFanOn ? '風扇狀態：開啟' : '風扇狀態：關閉',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _isFanOn ? Colors.blue : Colors.red),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '當前風速：${_isFanOn ? _fanSpeed : 0} 級',
                            style: const TextStyle(fontSize: 18),
                          ),
                          if (_timerMinutes > 0) ...[
                            const SizedBox(height: 5),
                            Text(
                              '定時關機：${_timerMinutes} 分鐘',
                              style: const TextStyle(fontSize: 14, color: Colors.orange),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // 控制按鈕區塊
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.2),
                            spreadRadius: 2,
                            blurRadius: 5,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          // 電源按鈕
                          ElevatedButton(
                            onPressed: _isLoading ? null : () => _sendControlCommand('power', {'isOn': !_isFanOn}),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isFanOn ? Colors.red : Colors.green,
                              shape: const CircleBorder(),
                              padding: const EdgeInsets.all(20),
                            ),
                            child: Icon(
                              _isFanOn ? Icons.power_settings_new : Icons.power_off,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                          Text(_isFanOn ? '關閉' : '開啟'),
                          const SizedBox(height: 20),

                          // 風速控制
                          const Text('風速控制', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildSpeedButton(1),
                              _buildSpeedButton(2),
                              _buildSpeedButton(3),
                              _buildSpeedButton(4),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // 功能按鈕
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              // 擺頭按鈕
                              Column(
                                children: [
                                  IconButton(
                                    onPressed: _isLoading ? null : () => _sendControlCommand('oscillation', {'oscillation': !_isOscillationOn}),
                                    icon: Icon(
                                      Icons.rotate_right,
                                      size: 40,
                                      color: _isOscillationOn ? Colors.blue : Colors.black,
                                    ),
                                  ),
                                  Text(_isOscillationOn ? '擺頭中' : '擺頭'),
                                ],
                              ),
                              // 定時按鈕
                              Column(
                                children: [
                                  IconButton(
                                    onPressed: _isLoading ? null : () {
                                      showModalBottomSheet(
                                        context: context,
                                        builder: (context) => _buildTimerBottomSheet(),
                                      );
                                    },
                                    icon: Icon(
                                      Icons.timer,
                                      size: 40,
                                      color: _timerMinutes > 0 ? Colors.blue : Colors.black,
                                    ),
                                  ),
                                  Text(_timerMinutes > 0 ? '定時 (${_timerMinutes}分)' : '定時'),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // 模式控制
                          const Text('模式控制', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildModeButton('normal', '一般風'),
                              _buildModeButton('natural', '自然風'),
                              _buildModeButton('sleep', '舒眠風'),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // 載入指示器
                    if (_isLoading) ...[
                      const SizedBox(height: 20),
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 12),
                              Text('處理中...'),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  // 定時器底部彈窗
  Widget _buildTimerBottomSheet() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('設定定時器', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildTimerButton(60, '1 小時'),
              _buildTimerButton(120, '2 小時'),
              _buildTimerButton(180, '3 小時'),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              _sendControlCommand('timer', {'minutes': 0});
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('取消定時'),
          ),
        ],
      ),
    );
  }

  Widget _buildTimerButton(int minutes, String label) {
    return ElevatedButton(
      onPressed: () {
        _sendControlCommand('timer', {'minutes': minutes});
        Navigator.pop(context);
      },
      style: ElevatedButton.styleFrom(
        foregroundColor: _timerMinutes == minutes ? Colors.white : Colors.black,
        backgroundColor: _timerMinutes == minutes ? Colors.blue : Colors.grey[200],
      ),
      child: Text(label),
    );
  }
}