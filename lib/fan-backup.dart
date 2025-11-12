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
  // 【新增】自動/手動模式，預設為手動
  bool _isManualMode = true; 
  // 風速現在代表 1-8 級，0 代表關閉
  int _fanSpeed = 0; 
  // 左右擺頭
  bool _isOscillationOn = false; 
  // 【新增】上下擺頭
  bool _isVerticalSwingOn = false; 
  // 【新增】液晶顯示
  bool _isDisplayOn = true; 
  // 【新增】靜音
  bool _isMuteOn = false; 
  // 【修改】模式新增 'eco'
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
            // 【新增】讀取模式狀態
            _isManualMode = data['isManualMode'] ?? true;
            
            // 確保風速在 0-8 範圍內
            _fanSpeed = data['speed'] ?? 0;
            if (_fanSpeed < 0 || _fanSpeed > 8) _fanSpeed = 0;
            
            _isOscillationOn = data['oscillation'] ?? false; 
            _isVerticalSwingOn = data['verticalSwing'] ?? false; 
            _isDisplayOn = data['isDisplayOn'] ?? true; 
            _isMuteOn = data['isMuteOn'] ?? false; 
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

  // 發送控制指令 (核心方法)
  Future<void> _sendControlCommand(String endpoint, Map<String, dynamic> body) async {
    // 檢查是否為模式或風速控制，且不在手動模式
    if (endpoint == 'speed' || endpoint == 'mode') {
      if (!_isManualMode) {
        _showSnackBar('請先切換到手動模式才能調整風速或模式', isError: true);
        return;
      }
    }

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
        await _fetchFanStatus();
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
  
  // 【新增】更新手動/自動模式
  Future<void> _updateManualMode(bool value) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/fan/manual-mode'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.jwtToken}',
        },
        body: jsonEncode({'isManualMode': value}),
      );
      
      if (response.statusCode == 200) {
        // 切換成功後，強制獲取最新狀態，讓後端設定的自動模式生效
        await _fetchFanStatus(); 
        _showSnackBar(value ? '已切換到手動模式' : '已切換到自動模式');
      } else {
        final responseData = jsonDecode(response.body);
        _showSnackBar(responseData['message'] ?? '更新模式失敗', isError: true);
      }
    } catch (e) {
      debugPrint('更新模式失敗: $e');
      _showSnackBar('網路連線錯誤', isError: true);
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

  // 模式按鈕的 UI (新增 ECO)
  Widget _buildModeButton(String mode, String label) {
    bool isSelected = _isFanOn && _currentMode == mode;
    bool isDisabled = !_isManualMode;
    return ElevatedButton(
      onPressed: isDisabled || _isLoading ? null : () => _sendControlCommand('mode', {'mode': mode}),
      style: ElevatedButton.styleFrom(
        foregroundColor: isSelected ? Colors.white : (isDisabled ? Colors.grey : Colors.black),
        backgroundColor: isSelected ? Colors.blue : Colors.blueGrey, 
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      ),
      child: Text(label),
    );
  }
  
  // 建構功能按鈕的 Helper Widget
  Widget _buildFeatureButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onPressed,
    bool isTimer = false,
  }) {
    return Column(
      children: [
        IconButton(
          onPressed: _isLoading ? null : onPressed,
          icon: Icon(
            icon,
            size: 40,
            color: isActive ? Colors.blue : Colors.black,
          ),
        ),
        Text(isTimer
             ? (_timerMinutes > 0 ? '定時 (${_timerMinutes}分)' : label)
             : label
        ),
      ],
    );
  }
  
  // 風速增減控制邏輯
  void _changeSpeed(bool isIncrement) {
    if (!_isManualMode) {
      _showSnackBar('請先切換到手動模式才能調整風速', isError: true);
      return;
    }
    
    // 如果風扇關閉，切換風速應先開啟並設定為 1 級
    if (!_isFanOn) {
      _sendControlCommand('power', {'isOn': true});
      _sendControlCommand('speed', {'speed': 1});
      return;
    }

    int newSpeed = _fanSpeed;
    if (isIncrement) {
      newSpeed = (_fanSpeed < 8) ? _fanSpeed + 1 : 8; // 最大 8 級
    } else {
      newSpeed = (_fanSpeed > 1) ? _fanSpeed - 1 : 1; // 最小 1 級
    }

    // 只有在風速發生變化時才發送指令
    if (newSpeed != _fanSpeed) {
      _sendControlCommand('speed', {'speed': newSpeed});
    }
  }
  
  // 【新增】自動/手動模式控制區塊
  Widget _buildFanModeControl() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          '模式控制',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Row(
          children: [
            const Text(
              '自動',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Switch(
              value: _isManualMode,
              onChanged: _isLoading ? null : _updateManualMode,
              activeColor: Theme.of(context).primaryColor,
            ),
            const Text(
              '手動',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    // 【修改】將 Theme.of(context).primaryColor 改為使用 Colors.blue，因為這個檔案沒有 Theme 資訊
    final primaryColor = Colors.blue; 

    return Scaffold(
      body: _hasError
          ? Center(
              // 錯誤訊息顯示區塊
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
                            _isFanOn ?
                            '風扇狀態：開啟' : '風扇狀態：關閉',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _isFanOn ? primaryColor : Colors.red),
                          ),
                          const SizedBox(height: 10),
                          // 【新增】模式狀態提示
                          Text(
                            _isManualMode ? '當前模式：手動' : '當前模式：自動 (一般風)',
                            style: TextStyle(fontSize: 16, color: _isManualMode ? Colors.black87 : Colors.orange),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '當前風速：${_isFanOn ? _fanSpeed : 0} 級 (Max 8)',
                            style: const TextStyle(fontSize: 18),
                          ),
                          if (_timerMinutes > 0) ...[
                            const SizedBox(height: 5),
                            Text(
                              '定時關機：${_timerMinutes} 分鐘',
                              style: const TextStyle(fontSize: 14, color: Colors.orange),
                            ),
                          ],
                          if (_isMuteOn) ...[
                            const SizedBox(height: 5),
                            const Text(
                              '提示音已關閉 (靜音)',
                              style: TextStyle(fontSize: 14, color: Colors.teal),
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
                          // 【新增】自動/手動模式控制
                          _buildFanModeControl(),
                          const SizedBox(height: 20),

                          // 電源按鈕
                          ElevatedButton(
                            onPressed: _isLoading ?
                            null : () => _sendControlCommand('power', {'isOn': !_isFanOn}),
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

                          // 風速控制 - 左右箭頭切換 1-8 級
                          const Text('風速控制 (1-8 級)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // 減風速按鈕
                              IconButton(
                                icon: const Icon(Icons.arrow_left, size: 48),
                                onPressed: (_isLoading || !_isManualMode || _fanSpeed <= 1) ? null : () => _changeSpeed(false),
                                color: (_isManualMode && _fanSpeed > 1) ? primaryColor : Colors.grey,
                              ),
                              
                              // 當前風速顯示
                              Container(
                                width: 80,
                                height: 80,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: primaryColor, width: 2),
                                ),
                                child: Text(
                                  '${_isFanOn ? _fanSpeed : 0}',
                                  style: TextStyle(
                                    fontSize: 36, 
                                    fontWeight: FontWeight.bold, 
                                    color: _isManualMode ? primaryColor : Colors.grey
                                  ),
                                ),
                              ),

                              // 加風速按鈕
                              IconButton(
                                icon: const Icon(Icons.arrow_right, size: 48),
                                onPressed: (_isLoading || !_isManualMode || _fanSpeed >= 8) ? null : () => _changeSpeed(true),
                                color: (_isManualMode && _fanSpeed < 8) ? primaryColor : Colors.grey,
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          
                          // 擺頭、定時與靜音控制
                          const Text('擺頭、定時與顯示', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),

                          // 功能按鈕：左右擺頭、上下擺頭、靜音、顯示、定時
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                // 左右擺頭按鈕
                                _buildFeatureButton(
                                  icon: Icons.swap_horiz, 
                                  label: '左右擺頭',
                                  isActive: _isOscillationOn,
                                  onPressed: () => _sendControlCommand('oscillation', {'oscillation': !_isOscillationOn}),
                                ),

                                // ➡️ 新增間隔
                                const SizedBox(width: 16), // 增加 16 像素的間隔

                                // 上下擺頭按鈕
                                _buildFeatureButton(
                                  icon: Icons.swap_vert, 
                                  label: '上下擺頭',
                                  isActive: _isVerticalSwingOn,
                                  onPressed: () => _sendControlCommand('verticalSwing', {'verticalSwing': !_isVerticalSwingOn}), 
                                ),

                                // ➡️ 新增間隔
                                const SizedBox(width: 16), // 增加 16 像素的間隔

                                // 液晶顯示按鈕
                                _buildFeatureButton(
                                  icon: _isDisplayOn ? Icons.remove_red_eye : Icons.visibility_off,
                                  label: '液晶顯示',
                                  isActive: _isDisplayOn,
                                  onPressed: () => _sendControlCommand('display', {'isDisplayOn': !_isDisplayOn}), 
                                ),

                                // ➡️ 新增間隔
                                const SizedBox(width: 16), // 增加 16 像素的間隔

                                // 靜音按鈕
                                _buildFeatureButton(
                                  icon: _isMuteOn ? Icons.volume_off : Icons.volume_up,
                                  label: '靜音',
                                  isActive: _isMuteOn,
                                  onPressed: () => _sendControlCommand('mute', {'isMuteOn': !_isMuteOn}), 
                                ),

                                // ➡️ 新增間隔
                                const SizedBox(width: 16), // 增加 16 像素的間隔
                                
                                // 定時按鈕
                                _buildFeatureButton(
                                  icon: Icons.timer,
                                  label: '定時', 
                                  isActive: _timerMinutes > 0,
                                  onPressed: () {
                                    showModalBottomSheet(
                                      context: context,
                                      builder: (context) => _buildTimerBottomSheet(),
                                    );
                                  },
                                  isTimer: true, 
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 20),

                          // 模式控制 (風類)
                          const Text('風類切換', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildModeButton('normal', '一般風'),
                              _buildModeButton('natural', '自然風'),
                              _buildModeButton('sleep', '舒眠風'),
                              // 新增 ECO 模式
                              _buildModeButton('eco', 'ECO 溫控'), 
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
  
  // 定時器底部彈窗 (與上次程式碼相同)
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