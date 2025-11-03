// lib/lighting_control_page.dart

import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:iot_project/main.dart'; // 引入 main.dart 以使用 ApiService

class LightingControlPage extends StatefulWidget {
  const LightingControlPage({super.key});

  @override
  State<LightingControlPage> createState() => _LightingControlPageState();
}

class _LightingControlPageState extends State<LightingControlPage> {
  // 燈光狀態變數
  bool _isManualMode = false; // false: 自動，true: 手動

  // 各區燈光亮度 (0-100) 和色溫 (K)
  double _brightnessA = 50.0;
  double _colorTempA = 4000.0; // 色溫範圍 2700K(暖)到6500K(冷)
  double _brightnessB = 70.0;
  double _colorTempB = 5000.0;
  double _brightnessC = 30.0;
  double _colorTempC = 3000.0;

  // 各區建議值 (自動模式，可以從智能算法獲取)
  double _suggestedBrightnessA = 60.0;
  double _suggestedColorTempA = 4500.0;
  double _suggestedBrightnessB = 80.0;
  double _suggestedColorTempB = 5500.0;
  double _suggestedBrightnessC = 40.0;
  double _suggestedColorTempC = 3500.0;

  // 燈光定時設定
  bool _isLightTimerOn = false;
  TimeOfDay? _selectedLightOnTime;
  TimeOfDay? _selectedLightOffTime;

  // 載入狀態
  bool _isLoading = true;

  // 計時器管理
  Timer? _timer;
  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    _fetchLightingStatus();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  // --- API 互動方法 ---

  /// 安全地將動態值轉換為 double
  double _parseToDouble(dynamic value, double defaultValue) {
    if (value == null) return defaultValue;
    
    if (value is num) {
      return value.toDouble();
    }
    
    if (value is String) {
      try {
        return double.parse(value);
      } catch (e) {
        print('Error parsing string to double: $value, error: $e');
        return defaultValue;
      }
    }
    
    print('Unexpected value type for numeric field: ${value.runtimeType}, value: $value');
    return defaultValue;
  }

  /// 從後端獲取當前燈光狀態
  Future<void> _fetchLightingStatus() async {
    setState(() {
      _isLoading = true;
    });
    
    try {
      final response = await ApiService.get('/lighting/status');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          // 根據資料庫欄位名稱映射，使用安全的解析方法
          _isManualMode = data['is_manual_mode'] ?? false;
          _brightnessA = _parseToDouble(data['brightness_a'], 50.0);
          _colorTempA = _parseToDouble(data['color_temp_a'], 4000.0);
          _brightnessB = _parseToDouble(data['brightness_b'], 70.0);
          _colorTempB = _parseToDouble(data['color_temp_b'], 5000.0);
          _brightnessC = _parseToDouble(data['brightness_c'], 30.0);
          _colorTempC = _parseToDouble(data['color_temp_c'], 3000.0);
          _isLightTimerOn = data['is_light_timer_on'] ?? false;

          // 更新定時設定
          _updateTimerFromData(data);
        });

        if (_isLightTimerOn && _selectedLightOffTime != null) {
          _startTimerForAutoOff();
        }
      } else if (response.statusCode == 404) {
        _showErrorSnackBar('找不到燈光設定，請檢查帳戶設定');
      } else {
        _showErrorSnackBar('載入燈光設定失敗');
      }
    } catch (e) {
      print('Error fetching lighting status: $e');
      _showErrorSnackBar('網路連線錯誤，請檢查連線狀態');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 從數據更新定時器設定
  void _updateTimerFromData(Map<String, dynamic> data) {
    if (data['timer_on_time'] != null) {
      try {
        final onTimeParts = data['timer_on_time'].toString().split(':');
        if (onTimeParts.length >= 2) {
          _selectedLightOnTime = TimeOfDay(
            hour: int.parse(onTimeParts[0]),
            minute: int.parse(onTimeParts[1]),
          );
        }
      } catch (e) {
        print('Error parsing timer_on_time: ${data['timer_on_time']}, error: $e');
        _selectedLightOnTime = null;
      }
    } else {
      _selectedLightOnTime = null;
    }

    if (data['timer_off_time'] != null) {
      try {
        final offTimeParts = data['timer_off_time'].toString().split(':');
        if (offTimeParts.length >= 2) {
          _selectedLightOffTime = TimeOfDay(
            hour: int.parse(offTimeParts[0]),
            minute: int.parse(offTimeParts[1]),
          );
        }
      } catch (e) {
        print('Error parsing timer_off_time: ${data['timer_off_time']}, error: $e');
        _selectedLightOffTime = null;
      }
    } else {
      _selectedLightOffTime = null;
    }
  }

  /// 更新手動/自動模式
  Future<void> _updateManualMode(bool value) async {
    try {
      final response = await ApiService.post('/lighting/manual-mode', {
        'isManualMode': value,
      });

      if (response.statusCode == 200) {
        setState(() {
          _isManualMode = value;
        });
        _showSuccessSnackBar(value ? '已切換為手動模式' : '已切換為自動模式');
        // 重新獲取最新狀態
        await _fetchLightingStatus();
      } else {
        _showErrorSnackBar('模式切換失敗');
      }
    } catch (e) {
      print('Error updating lighting manual mode: $e');
      _showErrorSnackBar('網路連線錯誤，請稍後再試');
    }
  }

  /// 更新燈光亮度
  Future<void> _sendBrightnessUpdate(String area, double value) async {
    try {
      final response = await ApiService.post('/lighting/brightness', {
        'area': area,
        'brightness': value,
      });

      if (response.statusCode == 200) {
        print('Sent ${area} brightness update to backend: $value');
      } else {
        _showErrorSnackBar('${area}區亮度更新失敗');
      }
    } catch (e) {
      print('Error sending ${area} brightness update: $e');
      _showErrorSnackBar('網路連線錯誤，請稍後再試');
    }
  }

  /// 更新燈光色溫
  Future<void> _sendColorTempUpdate(String area, double value) async {
    try {
      final response = await ApiService.post('/lighting/color-temp', {
        'area': area,
        'colorTemp': value,
      });

      if (response.statusCode == 200) {
        print('Sent ${area} color temperature update to backend: $value');
      } else {
        _showErrorSnackBar('${area}區色溫更新失敗');
      }
    } catch (e) {
      print('Error sending ${area} color temperature update: $e');
      _showErrorSnackBar('網路連線錯誤，請稍後再試');
    }
  }

  /// 處理定時設定確認
  Future<void> _confirmLightTimerSettings() async {
    if (_selectedLightOnTime == null || _selectedLightOffTime == null) {
      _showErrorSnackBar('請先設定完整的開燈和關燈時間');
      return;
    }

    try {
      final response = await ApiService.post('/lighting/timer', {
        'isLightTimerOn': true,
        'timerOnTime': '${_selectedLightOnTime!.hour.toString().padLeft(2, '0')}:${_selectedLightOnTime!.minute.toString().padLeft(2, '0')}',
        'timerOffTime': '${_selectedLightOffTime!.hour.toString().padLeft(2, '0')}:${_selectedLightOffTime!.minute.toString().padLeft(2, '0')}',
      });

      if (response.statusCode == 200) {
        setState(() {
          _isLightTimerOn = true;
        });

        _showSuccessSnackBar(
          '燈光定時已設定：開燈 ${_selectedLightOnTime!.format(context)}，'
          '關燈 ${_selectedLightOffTime!.format(context)}',
        );
        _startTimerForAutoOff();
      } else {
        _showErrorSnackBar('定時設定失敗');
      }
    } catch (e) {
      print('Error updating light timer settings: $e');
      _showErrorSnackBar('網路連線錯誤，請稍後再試');
    }
  }

  /// 更新定時設定 (主要用於關閉定時)
  Future<void> _updateLightTimer(bool isTimerOn) async {
    try {
      final response = await ApiService.post('/lighting/timer', {
        'isLightTimerOn': isTimerOn,
        'timerOnTime': isTimerOn && _selectedLightOnTime != null 
          ? '${_selectedLightOnTime!.hour.toString().padLeft(2, '0')}:${_selectedLightOnTime!.minute.toString().padLeft(2, '0')}' 
          : null,
        'timerOffTime': isTimerOn && _selectedLightOffTime != null 
          ? '${_selectedLightOffTime!.hour.toString().padLeft(2, '0')}:${_selectedLightOffTime!.minute.toString().padLeft(2, '0')}' 
          : null,
      });

      if (response.statusCode == 200) {
        setState(() {
          _isLightTimerOn = isTimerOn;
          if (!isTimerOn) {
            _selectedLightOnTime = null;
            _selectedLightOffTime = null;
          }
        });
        
        _showSuccessSnackBar(
          isTimerOn ? '燈光定時功能已開啟' : '燈光定時功能已關閉'
        );
        
        if (!isTimerOn) {
          _timer?.cancel();
        }
      } else {
        _showErrorSnackBar('定時設定更新失敗');
      }
    } catch (e) {
      print('Error updating light timer settings: $e');
      _showErrorSnackBar('網路連線錯誤，請稍後再試');
    }
  }

  /// 啟動自動關閉定時器
  void _startTimerForAutoOff() {
    _timer?.cancel();

    if (_selectedLightOffTime == null) return;

    final now = DateTime.now();
    final offTime = DateTime(
      now.year,
      now.month,
      now.day,
      _selectedLightOffTime!.hour,
      _selectedLightOffTime!.minute,
    );

    final durationUntilOff = offTime.isAfter(now)
        ? offTime.difference(now)
        : offTime.add(const Duration(days: 1)).difference(now);

    _timer = Timer(durationUntilOff, () {
      _updateLightTimer(false);
    });
  }

  /// 時間選擇器
  Future<void> _selectTime(
    BuildContext context, {
    required ValueChanged<TimeOfDay?> onTimeSelected,
    TimeOfDay? initialTime,
  }) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime ?? TimeOfDay.now(),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      onTimeSelected(picked);
    }
  }

  /// 創建防抖控制處理器
  void Function(double) _createDebouncedHandler(
    String area,
    String type,
    void Function(double) updateState,
    Future<void> Function(String, double) sendUpdate,
  ) {
    return (value) {
      updateState(value);
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        sendUpdate(area, value);
      });
    };
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _refreshData() async {
    await _fetchLightingStatus();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              '載入燈光設定中...',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 頂部圖標
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 150,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),

            // 模式控制
            _buildModeControl(),
            const SizedBox(height: 32),

            // 各區燈光顯示
            const Text(
              '各區燈光顯示',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // A區
            _buildLightControlCard(
              context,
              area: 'A',
              brightness: _brightnessA,
              colorTemp: _colorTempA,
              onBrightnessChanged: _isManualMode
                  ? _createDebouncedHandler(
                      'A',
                      'brightness',
                      (value) => setState(() => _brightnessA = value),
                      _sendBrightnessUpdate,
                    )
                  : null,
              onColorTempChanged: _isManualMode
                  ? _createDebouncedHandler(
                      'A',
                      'colorTemp',
                      (value) => setState(() => _colorTempA = value),
                      _sendColorTempUpdate,
                    )
                  : null,
              isManualMode: _isManualMode,
              suggestedBrightness: _suggestedBrightnessA,
              suggestedColorTemp: _suggestedColorTempA,
            ),
            const SizedBox(height: 16),

            // B區
            _buildLightControlCard(
              context,
              area: 'B',
              brightness: _brightnessB,
              colorTemp: _colorTempB,
              onBrightnessChanged: _isManualMode
                  ? _createDebouncedHandler(
                      'B',
                      'brightness',
                      (value) => setState(() => _brightnessB = value),
                      _sendBrightnessUpdate,
                    )
                  : null,
              onColorTempChanged: _isManualMode
                  ? _createDebouncedHandler(
                      'B',
                      'colorTemp',
                      (value) => setState(() => _colorTempB = value),
                      _sendColorTempUpdate,
                    )
                  : null,
              isManualMode: _isManualMode,
              suggestedBrightness: _suggestedBrightnessB,
              suggestedColorTemp: _suggestedColorTempB,
            ),
            const SizedBox(height: 16),

            // C區
            _buildLightControlCard(
              context,
              area: 'C',
              brightness: _brightnessC,
              colorTemp: _colorTempC,
              onBrightnessChanged: _isManualMode
                  ? _createDebouncedHandler(
                      'C',
                      'brightness',
                      (value) => setState(() => _brightnessC = value),
                      _sendBrightnessUpdate,
                    )
                  : null,
              onColorTempChanged: _isManualMode
                  ? _createDebouncedHandler(
                      'C',
                      'colorTemp',
                      (value) => setState(() => _colorTempC = value),
                      _sendColorTempUpdate,
                    )
                  : null,
              isManualMode: _isManualMode,
              suggestedBrightness: _suggestedBrightnessC,
              suggestedColorTemp: _suggestedColorTempC,
            ),
            const SizedBox(height: 32),

            // 燈光定時
            _buildTimerSection(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  /// 建構模式控制區域
  Widget _buildModeControl() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 2,
            blurRadius: 5,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '模式控制',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Row(
            children: [
              Text(
                '自動',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: !_isManualMode ? Theme.of(context).primaryColor : Colors.grey,
                ),
              ),
              Switch(
                value: _isManualMode,
                onChanged: _updateManualMode,
                activeColor: Theme.of(context).primaryColor,
              ),
              Text(
                '手動',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: _isManualMode ? Theme.of(context).primaryColor : Colors.grey,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 建構定時器控制區域
  Widget _buildTimerSection() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '燈光定時',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              Switch(
                value: _isLightTimerOn,
                onChanged: (value) {
                  if (value) {
                    setState(() => _isLightTimerOn = true);
                  } else {
                    _updateLightTimer(false);
                  }
                },
                activeColor: Theme.of(context).primaryColor,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _isLightTimerOn ? _buildTimerSettings() : _buildTimerDisabled(),
        ],
      ),
    );
  }

  /// 建構定時器設定界面
  Widget _buildTimerSettings() {
    return Column(
      children: [
        _buildTimeSelector(
          label: '開燈時間:',
          time: _selectedLightOnTime,
          onTimeSelected: (picked) {
            setState(() => _selectedLightOnTime = picked);
          },
        ),
        const SizedBox(height: 12),
        _buildTimeSelector(
          label: '關燈時間:',
          time: _selectedLightOffTime,
          onTimeSelected: (picked) {
            setState(() => _selectedLightOffTime = picked);
          },
        ),
        const SizedBox(height: 20),
        Center(
          child: ElevatedButton(
            onPressed: _confirmLightTimerSettings,
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('確定', style: TextStyle(fontSize: 18)),
          ),
        ),
      ],
    );
  }

  /// 建構定時器禁用狀態
  Widget _buildTimerDisabled() {
    return const Center(
      child: Text(
        '燈光定時功能已關閉',
        style: TextStyle(fontSize: 16, color: Colors.grey),
      ),
    );
  }

  /// 建構時間選擇器
  Widget _buildTimeSelector({
    required String label,
    required TimeOfDay? time,
    required ValueChanged<TimeOfDay?> onTimeSelected,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 16)),
        GestureDetector(
          onTap: () async {
            await _selectTime(
              context,
              initialTime: time,
              onTimeSelected: onTimeSelected,
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.access_time, size: 16),
                const SizedBox(width: 8),
                Text(
                  time?.format(context) ?? '未設定',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 建構燈光控制卡片
  Widget _buildLightControlCard(
    BuildContext context, {
    required String area,
    required double brightness,
    required double colorTemp,
    required ValueChanged<double>? onBrightnessChanged,
    required ValueChanged<double>? onColorTempChanged,
    required bool isManualMode,
    required double suggestedBrightness,
    required double suggestedColorTemp,
  }) {
    final Color sliderActiveColor = isManualMode 
        ? Theme.of(context).primaryColor 
        : Colors.grey;
    final Color sliderInactiveColor = isManualMode 
        ? Colors.grey[300]! 
        : Colors.grey[200]!;
    final Color textColor = isManualMode ? Colors.black87 : Colors.grey;

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 區域標識
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  area,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).primaryColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              
              // 控制滑塊
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '實時亮度', 
                          style: TextStyle(fontSize: 16, color: textColor),
                        ),
                        Text(
                          '${brightness.round()}%',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    _buildSlider(
                      value: brightness,
                      min: 0,
                      max: 100,
                      divisions: 100,
                      onChanged: onBrightnessChanged,
                      activeColor: sliderActiveColor,
                      inactiveColor: sliderInactiveColor,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '色溫', 
                          style: TextStyle(fontSize: 16, color: textColor),
                        ),
                        Text(
                          '${colorTemp.round()}K',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    _buildSlider(
                      value: colorTemp,
                      min: 2700,
                      max: 6500,
                      divisions: (6500 - 2700).toInt(),
                      onChanged: onColorTempChanged,
                      activeColor: sliderActiveColor,
                      inactiveColor: sliderInactiveColor,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!isManualMode) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Text(
                    '自動模式 - 系統智慧調節中',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 建構統一樣式的滑塊
  Widget _buildSlider({
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double>? onChanged,
    required Color activeColor,
    required Color inactiveColor,
  }) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
        activeTrackColor: activeColor,
        inactiveTrackColor: inactiveColor,
        thumbColor: activeColor,
        overlayColor: activeColor.withOpacity(0.2),
      ),
      child: Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
      ),
    );
  }
}