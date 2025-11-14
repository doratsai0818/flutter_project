// lib/ac_control_page.dart
// 改進版：使用後端紅外線控制 + 即時溫溼度顯示

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ACControlPage extends StatefulWidget {
  final String jwtToken;
  const ACControlPage({super.key, required this.jwtToken});

  @override
  State<ACControlPage> createState() => _ACControlPageState();
}

class _ACControlPageState extends State<ACControlPage> {
  final String _baseUrl = 'http://localhost:3000/api';
  
  String get _jwtToken => widget.jwtToken;

  // 冷氣狀態變數
  bool _isACOn = false;
  bool _isManualMode = true; // 自動/手動模式
  int _currentSetTemp = 26; // 設定溫度 (16-30°C)
  int _selectedACModeIndex = 0; // 0:製冷, 1:除濕, 2:送風
  int _fanSpeed = 1; // 風速 (1-3)
  
  // 環境感測數據
  double _currentRoomTemp = 0.0;
  double _currentHumidity = 0.0;
  
  // 定時器
  bool _isACTimerOn = false;
  TimeOfDay? _selectedOnTime;
  TimeOfDay? _selectedOffTime;
  
  // UI 狀態
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';
  
  Timer? _statusTimer;
  Timer? _sensorTimer;

  final List<String> _acModes = ['製冷', '除濕', '送風'];
  final List<String> _acModeKeys = ['cool', 'dehumidify', 'fan'];

  @override
  void initState() {
    super.initState();
    _fetchACStatus();
    _fetchTempHumidity();
    
    // 每5秒更新冷氣狀態
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchACStatus();
    });
    
    // 每3秒更新溫溼度
    _sensorTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      _fetchTempHumidity();
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _sensorTimer?.cancel();
    super.dispose();
  }

  // ===== API 互動方法 =====

  /// 從後端獲取冷氣狀態
  Future<void> _fetchACStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/ac/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_jwtToken',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _isManualMode = data['is_manual_mode'] ?? true;
          _currentSetTemp = _safeParseInt(data['current_set_temp'], 26);
          _selectedACModeIndex = data['selected_ac_mode_index'] ?? 0;
          _isACTimerOn = data['is_ac_timer_on'] ?? false;
          _selectedOnTime = _parseTimeFromString(data['timer_on_time']);
          _selectedOffTime = _parseTimeFromString(data['timer_off_time']);
          _hasError = false;
        });
      } else if (response.statusCode == 401) {
        _showErrorState('認證失效，請重新登入');
      } else if (response.statusCode == 404) {
        _showErrorState('找不到冷氣設定資料');
      }
    } catch (e) {
      debugPrint('獲取冷氣狀態失敗: $e');
      _showErrorState('網路連線錯誤');
    }
  }

  /// 從後端獲取溫溼度數據
  Future<void> _fetchTempHumidity() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/temp-humidity/status'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_jwtToken',
        },
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] && responseData['data'] != null) {
          final data = responseData['data'];
          setState(() {
            _currentRoomTemp = _safeParseDouble(data['temperature_c']);
            _currentHumidity = _safeParseDouble(data['humidity_percent']);
          });
        }
      }
    } catch (e) {
      debugPrint('獲取溫溼度失敗: $e');
    }
  }

  /// 發送紅外線控制指令
  Future<void> _sendIRCommand(String action) async {
    if (!_isManualMode && (action == 'temp_up' || action == 'temp_down' || action == 'wind_speed' || action.startsWith('mode'))) {
      _showSnackBar('請先切換到手動模式', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/aircon'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_jwtToken',
        },
        body: jsonEncode({
          'device': 'aircon',
          'action': action,
        }),
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success']) {
          _showSnackBar('操作成功');
          await _fetchACStatus();
        } else {
          _showSnackBar(responseData['message'] ?? '控制失敗', isError: true);
        }
      } else if (response.statusCode == 401) {
        _showSnackBar('認證失效，請重新登入', isError: true);
      } else {
        final responseData = json.decode(response.body);
        _showSnackBar(responseData['message'] ?? '控制失敗', isError: true);
      }
    } catch (e) {
      debugPrint('發送紅外線指令失敗: $e');
      _showSnackBar('網路連線失敗', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 更新手動/自動模式
  Future<void> _updateManualMode(bool value) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/ac/manual-mode'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $_jwtToken',
        },
        body: jsonEncode({'isManualMode': value}),
      );

      if (response.statusCode == 200) {
        setState(() => _isManualMode = value);
        _showSnackBar(value ? '已切換到手動模式' : '已切換到自動模式');
        await _fetchACStatus();
      } else {
        _showSnackBar('更新模式失敗', isError: true);
      }
    } catch (e) {
      debugPrint('更新模式失敗: $e');
      _showSnackBar('網路連線錯誤', isError: true);
    }
  }

  // ===== 輔助方法 =====

  int _safeParseInt(dynamic value, [int defaultValue = 0]) {
    if (value == null) return defaultValue;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) {
      try {
        return double.parse(value).round();
      } catch (e) {
        return defaultValue;
      }
    }
    return defaultValue;
  }

  double _safeParseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      try {
        return double.parse(value);
      } catch (e) {
        return 0.0;
      }
    }
    return 0.0;
  }

  TimeOfDay? _parseTimeFromString(String? timeString) {
    if (timeString == null || timeString.isEmpty) return null;
    try {
      final parts = timeString.split(':');
      if (parts.length >= 2) {
        return TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      }
    } catch (e) {
      debugPrint('解析時間失敗: $timeString');
    }
    return null;
  }

  void _showErrorState(String message) {
    setState(() {
      _hasError = true;
      _errorMessage = message;
    });
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  // ===== UI 構建方法 =====

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _buildErrorView();
    }

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 環境資訊卡片
            _buildEnvironmentCard(),
            const SizedBox(height: 20),
            
            // 模式控制
            _buildModeControl(),
            const SizedBox(height: 20),
            
            // 主控制面板
            _buildMainControlPanel(),
            const SizedBox(height: 20),
            
            // 模式選擇
            _buildACModeSelector(),
            const SizedBox(height: 20),
            
            // 溫度控制
            _buildTemperatureControl(),
            const SizedBox(height: 20),
            
            // 風速控制
            _buildFanSpeedControl(),
            const SizedBox(height: 20),
            
            // 定時器 (可選)
            // _buildTimerSection(),
            
            // 載入指示器
            if (_isLoading) _buildLoadingIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text('連線失敗', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(_errorMessage, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                setState(() => _hasError = false);
                _fetchACStatus();
                _fetchTempHumidity();
              },
              child: const Text('重新連線'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEnvironmentCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _buildCardDecoration(),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '當前環境資訊',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildEnvironmentItem(
                Icons.device_thermostat,
                '溫度',
                '${_currentRoomTemp.toStringAsFixed(1)}°C',
                Colors.orange,
              ),
              _buildEnvironmentItem(
                Icons.water_drop,
                '濕度',
                '${_currentHumidity.toStringAsFixed(1)}%',
                Colors.blue,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEnvironmentItem(IconData icon, String label, String value, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 14, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildModeControl() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: _buildCardDecoration(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '模式控制',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Row(
            children: [
              const Text('自動', style: TextStyle(fontSize: 16)),
              Switch(
                value: _isManualMode,
                onChanged: _updateManualMode,
                activeColor: Colors.blue,
              ),
              const Text('手動', style: TextStyle(fontSize: 16)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainControlPanel() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _buildCardDecoration(),
      child: Column(
        children: [
          Text(
            _isACOn ? '冷氣狀態：開啟' : '冷氣狀態：關閉',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _isACOn ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () async {
              await _sendIRCommand('power');
              setState(() => _isACOn = !_isACOn);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: _isACOn ? Colors.red : Colors.green,
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(24),
            ),
            child: Icon(
              _isACOn ? Icons.power_settings_new : Icons.power_off,
              color: Colors.white,
              size: 48,
            ),
          ),
          const SizedBox(height: 10),
          Text(_isACOn ? '關閉' : '開啟', style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildACModeSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _buildCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '運轉模式',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: _acModes.asMap().entries.map((entry) {
              int idx = entry.key;
              String mode = entry.value;
              bool isSelected = _selectedACModeIndex == idx;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ElevatedButton(
                    onPressed: (_isManualMode && _isACOn)
                        ? () async {
                            await _sendIRCommand('mode');
                            setState(() => _selectedACModeIndex = idx);
                          }
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected && _isManualMode
                          ? Colors.blue
                          : Colors.grey.shade300,
                      foregroundColor: isSelected && _isManualMode
                          ? Colors.white
                          : Colors.black54,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      mode,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTemperatureControl() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _buildCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '溫度設定',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 48),
                onPressed: (_isManualMode && _isACOn && _currentSetTemp > 16)
                    ? () async {
                        await _sendIRCommand('temp_down');
                        setState(() => _currentSetTemp--);
                      }
                    : null,
                color: (_isManualMode && _currentSetTemp > 16)
                    ? Colors.blue
                    : Colors.grey,
              ),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.blue, width: 3),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$_currentSetTemp°C',
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: _isManualMode ? Colors.blue : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '16-30°C',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 48),
                onPressed: (_isManualMode && _isACOn && _currentSetTemp < 30)
                    ? () async {
                        await _sendIRCommand('temp_up');
                        setState(() => _currentSetTemp++);
                      }
                    : null,
                color: (_isManualMode && _currentSetTemp < 30)
                    ? Colors.blue
                    : Colors.grey,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFanSpeedControl() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _buildCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '風速設定',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildFanSpeedButton(1, '低速'),
              _buildFanSpeedButton(2, '中速'),
              _buildFanSpeedButton(3, '高速'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFanSpeedButton(int speed, String label) {
    bool isSelected = _fanSpeed == speed;
    return ElevatedButton(
      onPressed: (_isManualMode && _isACOn)
          ? () async {
              await _sendIRCommand('wind_speed');
              setState(() => _fanSpeed = speed);
            }
          : null,
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected && _isManualMode
            ? Colors.blue
            : Colors.grey.shade300,
        foregroundColor: isSelected && _isManualMode
            ? Colors.white
            : Colors.black54,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return const Card(
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
    );
  }

  BoxDecoration _buildCardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withOpacity(0.2),
          spreadRadius: 2,
          blurRadius: 8,
          offset: const Offset(0, 4),
        ),
      ],
    );
  }
}