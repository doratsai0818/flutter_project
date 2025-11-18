// lib/ac_control_page.dart
// 改進版:根據實際冷氣遙控器邏輯修正

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:iot_project/config.dart';

class ACControlPage extends StatefulWidget {
  final String jwtToken;
  const ACControlPage({super.key, required this.jwtToken});

  @override
  State<ACControlPage> createState() => _ACControlPageState();
}

class _ACControlPageState extends State<ACControlPage> {
  final String _baseUrl = Config.apiUrl;
  
  String get _jwtToken => widget.jwtToken;

  // 冷氣狀態變數
  bool _isACOn = false;
  bool _isManualMode = true;
  int _currentSetTemp = 26; // 15-31°C
  int _selectedACModeIndex = 2; // 0:送風, 1:自動, 2:冷氣, 3:除濕
  bool _isFanSpeedLow = true; // true=低速, false=高速
  bool _isSleepMode = false; // 睡眠模式
  
  // 環境感測數據
  double _currentRoomTemp = 0.0;
  double _currentHumidity = 0.0;
  
  // UI 狀態
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';
  
  Timer? _statusTimer;
  Timer? _sensorTimer;

  // 模式名稱對應
  final List<String> _acModes = ['送風', '自動', '冷氣', '除濕'];
  final List<IconData> _acModeIcons = [
    Icons.air,           // 送風
    Icons.autorenew,     // 自動
    Icons.ac_unit,       // 冷氣
    Icons.water_drop,    // 除濕
  ];

  @override
  void initState() {
    super.initState();
    _fetchACStatus();
    _fetchTempHumidity();
    
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      _fetchACStatus();
    });
    
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

  Future<void> _fetchACStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/ac/status'),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
          'Authorization': 'Bearer $_jwtToken',
        },
      );

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        
        if (responseData['success'] == true && responseData['data'] != null) {
          final data = responseData['data'];
          
          setState(() {
            _isACOn = data['is_on'] ?? false;
            _isManualMode = data['is_manual_mode'] ?? true;
            _currentSetTemp = _safeParseInt(data['current_set_temp'], 26);
            _selectedACModeIndex = data['selected_ac_mode_index'] ?? 2;
            _isFanSpeedLow = (data['fan_speed'] ?? 1) == 1; // 1=低速, 2=高速
            _isSleepMode = data['is_sleep_mode'] ?? false;
            _hasError = false;
          });
        } else {
          _showErrorState('資料格式錯誤');
        }
      } else if (response.statusCode == 401) {
        _showErrorState('認證失效,請重新登入');
      } else {
        _showErrorState('取得冷氣狀態失敗');
      }
    } catch (e) {
      debugPrint('取得冷氣狀態失敗: $e');
      _showErrorState('網路連線錯誤');
    }
  }

  Future<void> _fetchTempHumidity() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/temp-humidity/status'),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
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
      debugPrint('獲取溫濕度失敗: $e');
    }
  }

  Future<void> _sendIRCommand(String action) async {
    // 自動模式下禁止手動操作(除了開關和模式切換)
    if (!_isManualMode && 
        action != 'power' && 
        action != 'mode' &&
        action != 'sleep') {
      _showSnackBar('請先切換到手動模式', isError: true);
      return;
    }

    setState(() => _isLoading = true);
    
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/aircon'),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
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
          
          // 樂觀更新本地狀態
          setState(() {
            switch (action) {
              case 'power':
                _isACOn = !_isACOn;
                break;
              case 'temp_up':
                if (_currentSetTemp < 31) _currentSetTemp++;
                break;
              case 'temp_down':
                if (_currentSetTemp > 15) _currentSetTemp--;
                break;
              case 'mode':
                _selectedACModeIndex = (_selectedACModeIndex + 1) % 4;
                break;
              case 'wind_speed':
                _isFanSpeedLow = !_isFanSpeedLow;
                break;
              case 'sleep':
                _isSleepMode = !_isSleepMode;
                break;
            }
          });
          
          await _fetchACStatus();
        } else {
          _showSnackBar(responseData['message'] ?? '控制失敗', isError: true);
        }
      } else {
        _showSnackBar('控制失敗', isError: true);
      }
    } catch (e) {
      debugPrint('發送紅外線指令失敗: $e');
      _showSnackBar('網路連線失敗', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateManualMode(bool value) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/ac/manual-mode'),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
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

  // 檢查當前模式是否可調整溫度
  bool get _canAdjustTemperature {
    return _isACOn && _isManualMode && _selectedACModeIndex == 2; // 只有冷氣模式
  }

  // 檢查當前模式是否可調整風速
  bool get _canAdjustFanSpeed {
    return _isACOn && _isManualMode && _selectedACModeIndex != 3; // 除濕模式鎖定低速
  }

  // 檢查是否可開啟睡眠模式
  bool get _canUseSleepMode {
    return _isACOn && _selectedACModeIndex == 2; // 只有冷氣模式
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
            _buildEnvironmentCard(),
            const SizedBox(height: 20),
            _buildModeControl(),
            const SizedBox(height: 20),
            _buildMainControlPanel(),
            const SizedBox(height: 20),
            _buildACModeSelector(),
            const SizedBox(height: 20),
            _buildTemperatureControl(),
            const SizedBox(height: 20),
            _buildFanSpeedControl(),
            const SizedBox(height: 20),
            _buildSleepModeControl(),
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
          const Text(
            '當前環境資訊',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
            _isACOn ? '冷氣狀態:開啟' : '冷氣狀態:關閉',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: _isACOn ? Colors.green : Colors.red,
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => _sendIRCommand('power'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isACOn ? Colors.red : Colors.green,
              shape: const CircleBorder(),
              padding: const EdgeInsets.all(24),
            ),
            child: Icon(
              Icons.power_settings_new,
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
                        ? () => _sendIRCommand('mode')
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected && _isManualMode
                          ? Colors.blue
                          : Colors.grey.shade300,
                      foregroundColor: isSelected && _isManualMode
                          ? Colors.white
                          : Colors.black54,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(_acModeIcons[idx], size: 20),
                        const SizedBox(height: 4),
                        Text(
                          mode,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Text(
            '提示: 循環順序為 ${_acModes.join(' → ')}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '溫度設定',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (!_canAdjustTemperature)
                Text(
                  '(僅限冷氣模式)',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline, size: 48),
                onPressed: (_canAdjustTemperature && _currentSetTemp > 15)
                    ? () => _sendIRCommand('temp_down')
                    : null,
                color: _canAdjustTemperature ? Colors.blue : Colors.grey,
              ),
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: _canAdjustTemperature 
                      ? Colors.blue.shade50 
                      : Colors.grey.shade200,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _canAdjustTemperature ? Colors.blue : Colors.grey,
                    width: 3,
                  ),
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
                          color: _canAdjustTemperature ? Colors.blue : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '15-31°C',
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
                onPressed: (_canAdjustTemperature && _currentSetTemp < 31)
                    ? () => _sendIRCommand('temp_up')
                    : null,
                color: _canAdjustTemperature ? Colors.blue : Colors.grey,
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '風速設定',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (_selectedACModeIndex == 3)
                Text(
                  '(除濕模式鎖定低速)',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _canAdjustFanSpeed
                      ? () => _sendIRCommand('wind_speed')
                      : null,
                  icon: Icon(_isFanSpeedLow ? Icons.air : Icons.tornado),
                  label: Text(
                    _isFanSpeedLow ? '低速' : '高速',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _canAdjustFanSpeed
                        ? Colors.blue
                        : Colors.grey.shade300,
                    foregroundColor: _canAdjustFanSpeed
                        ? Colors.white
                        : Colors.black54,
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '點擊切換 低速 ↔ 高速',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSleepModeControl() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _buildCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '睡眠模式',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (!_canUseSleepMode)
                Text(
                  '(僅限冷氣模式)',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _canUseSleepMode
                      ? () => _sendIRCommand('sleep')
                      : null,
                  icon: Icon(_isSleepMode ? Icons.bedtime : Icons.bedtime_outlined),
                  label: Text(
                    _isSleepMode ? '睡眠模式:開啟' : '睡眠模式:關閉',
                    style: const TextStyle(fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isSleepMode && _canUseSleepMode
                        ? Colors.indigo
                        : Colors.grey.shade300,
                    foregroundColor: _isSleepMode && _canUseSleepMode
                        ? Colors.white
                        : Colors.black54,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_isSleepMode && _canUseSleepMode)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.indigo.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 16, color: Colors.indigo.shade700),
                        const SizedBox(width: 8),
                        Text(
                          '睡眠模式說明',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• 風速鎖定低速並減少噪音\n'
                      '• 每隔一段時間提升設定溫度\n'
                      '• 避免因溫度過低導致不適\n'
                      '• 6小時後自動停止運轉',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            ),
        ],
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