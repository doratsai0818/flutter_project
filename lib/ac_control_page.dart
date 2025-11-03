// lib/ac_control_page.dart

import 'package:flutter/material.dart';
import 'dart:math';
import 'dart:convert';
import 'package:iot_project/energy_saving_settings_page.dart';
import 'dart:async';
import 'package:iot_project/main.dart'; // 導入 main.dart 以使用 ApiService

class ACControlPage extends StatefulWidget {
  const ACControlPage({super.key});

  @override
  State<ACControlPage> createState() => _ACControlPageState();
}

class _ACControlPageState extends State<ACControlPage> {
  // 冷氣狀態變數
  bool _isManualMode = false;
  int _currentRoomTemp = 0;
  double _currentHumidity = 0.0;
  int _pmvValue = 0;
  int _recommendedTemp = 0;
  int _currentSetTemp = 0;
  int _selectedACModeIndex = 0;
  bool _isACTimerOn = false;
  TimeOfDay? _selectedOnTime;
  TimeOfDay? _selectedOffTime;
  bool _isLoading = true;

  Timer? _timer;
  final List<String> _acModes = ['製冷', '製熱', '除濕', '送風'];

  @override
  void initState() {
    super.initState();
    _fetchACStatus();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // === API 互動方法 ===

  /// 從後端獲取當前冷氣狀態
  Future<void> _fetchACStatus() async {
    try {
      setState(() => _isLoading = true);
      
      final response = await ApiService.get('/ac/status');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _updateStateFromResponse(data);
      } else if (response.statusCode == 401) {
        _showErrorMessage('認證失效，請重新登入');
        // 可以在這裡觸發登出
      } else if (response.statusCode == 404) {
        _showErrorMessage('找不到冷氣設定資料');
      } else {
        _showErrorMessage('獲取冷氣狀態失敗');
      }
    } catch (e) {
      _showErrorMessage('網路連線錯誤：$e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // Fixed: Better type handling for API response data
  void _updateStateFromResponse(Map<String, dynamic> data) {
    setState(() {
      _isManualMode = data['is_manual_mode'] ?? false;
      
      // Safe conversion for temperature values
      _currentRoomTemp = _safeParseInt(data['current_room_temp']);
      _currentHumidity = _safeParseDouble(data['current_humidity']);
      _pmvValue = _safeParseInt(data['pmv_value']);
      _recommendedTemp = _safeParseInt(data['recommended_temp']);
      _currentSetTemp = _safeParseInt(data['current_set_temp']);
      
      _selectedACModeIndex = data['selected_ac_mode_index'] ?? 0;
      _isACTimerOn = data['is_ac_timer_on'] ?? false;

      _selectedOnTime = _parseTimeFromString(data['timer_on_time']);
      _selectedOffTime = _parseTimeFromString(data['timer_off_time']);
    });
  }

  // Helper method for safe integer parsing
  int _safeParseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) {
      try {
        return double.parse(value).round();
      } catch (e) {
        print('Error parsing int from string: $value - $e');
        return 0;
      }
    }
    return 0;
  }

  // Helper method for safe double parsing
  double _safeParseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      try {
        return double.parse(value);
      } catch (e) {
        print('Error parsing double from string: $value - $e');
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
      print('解析時間失敗: $timeString - $e');
    }
    return null;
  }

  /// 更新冷氣模式
  Future<void> _updateACMode(int index) async {
    if (!_isManualMode) {
      _showSnackBar('請先切換到手動模式');
      return;
    }

    try {
      final response = await ApiService.post('/ac/mode', {
        'selectedACModeIndex': index,
      });

      if (response.statusCode == 200) {
        setState(() => _selectedACModeIndex = index);
        _showSnackBar('冷氣模式已更新為：${_acModes[index]}');
      } else if (response.statusCode == 401) {
        _showErrorMessage('認證失效，請重新登入');
      } else {
        _showErrorMessage('更新冷氣模式失敗');
      }
    } catch (e) {
      _showErrorMessage('網路連線錯誤：$e');
    }
  }

  /// 更新設定溫度
  Future<void> _updateTemperature(int temp) async {
    if (!_isManualMode) {
      _showSnackBar('請先切換到手動模式');
      return;
    }

    if (temp < 16 || temp > 30) {
      _showSnackBar('溫度設定範圍為 16-30°C');
      return;
    }

    try {
      final response = await ApiService.post('/ac/temperature', {
        'currentSetTemp': temp,
      });

      if (response.statusCode == 200) {
        setState(() => _currentSetTemp = temp);
        _showSnackBar('溫度已設定為：$temp°C');
      } else if (response.statusCode == 401) {
        _showErrorMessage('認證失效，請重新登入');
      } else {
        _showErrorMessage('更新溫度失敗');
      }
    } catch (e) {
      _showErrorMessage('網路連線錯誤：$e');
    }
  }

  /// 更新手動/自動模式
  Future<void> _updateManualMode(bool value) async {
    try {
      final response = await ApiService.post('/ac/manual-mode', {
        'isManualMode': value,
      });

      if (response.statusCode == 200) {
        setState(() {
          _isManualMode = value;
          if (!value) {
            // 自動模式下使用建議溫度
            _currentSetTemp = _recommendedTemp;
          }
        });
        _showSnackBar(value ? '已切換到手動模式' : '已切換到自動模式');
      } else if (response.statusCode == 401) {
        _showErrorMessage('認證失效，請重新登入');
      } else {
        _showErrorMessage('更新模式失敗');
      }
    } catch (e) {
      _showErrorMessage('網路連線錯誤：$e');
    }
  }

  /// 確認定時設定並傳送至後端
  Future<void> _confirmTimerSettings() async {
    if (_selectedOnTime == null || _selectedOffTime == null) {
      _showSnackBar('請先設定完整的開機和關機時間');
      return;
    }

    try {
      final response = await ApiService.post('/ac/timer', {
        'isACTimerOn': true,
        'timerOnTime': _formatTimeOfDay(_selectedOnTime!),
        'timerOffTime': _formatTimeOfDay(_selectedOffTime!),
      });

      if (response.statusCode == 200) {
        setState(() => _isACTimerOn = true);
        _showSnackBar(
          '冷氣定時已設定：開機 ${_selectedOnTime!.format(context)}，關機 ${_selectedOffTime!.format(context)}',
        );
        _startTimerForAutoOff();
      } else if (response.statusCode == 401) {
        _showErrorMessage('認證失效，請重新登入');
      } else {
        _showErrorMessage('更新定時設定失敗');
      }
    } catch (e) {
      _showErrorMessage('網路連線錯誤：$e');
    }
  }

  /// 更新定時設定（主要用於關閉定時）
  Future<void> _updateTimer(bool isTimerOn) async {
    try {
      final response = await ApiService.post('/ac/timer', {
        'isACTimerOn': isTimerOn,
        'timerOnTime': isTimerOn && _selectedOnTime != null 
            ? _formatTimeOfDay(_selectedOnTime!) 
            : null,
        'timerOffTime': isTimerOn && _selectedOffTime != null 
            ? _formatTimeOfDay(_selectedOffTime!) 
            : null,
      });

      if (response.statusCode == 200) {
        setState(() {
          _isACTimerOn = isTimerOn;
          if (!isTimerOn) {
            _selectedOnTime = null;
            _selectedOffTime = null;
            _timer?.cancel();
          }
        });

        _showSnackBar(isTimerOn ? '冷氣定時功能已開啟' : '冷氣定時功能已關閉');
      } else if (response.statusCode == 401) {
        _showErrorMessage('認證失效，請重新登入');
      } else {
        _showErrorMessage('更新定時設定失敗');
      }
    } catch (e) {
      _showErrorMessage('網路連線錯誤：$e');
    }
  }

  /// 格式化 TimeOfDay 為 HH:mm 字串
  String _formatTimeOfDay(TimeOfDay time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  /// 啟動自動關閉定時器
  void _startTimerForAutoOff() {
    _timer?.cancel();
    if (_selectedOffTime == null) return;

    final now = DateTime.now();
    final offTime = DateTime(
      now.year,
      now.month,
      now.day,
      _selectedOffTime!.hour,
      _selectedOffTime!.minute,
    );

    final durationUntilOff = offTime.isAfter(now)
        ? offTime.difference(now)
        : offTime.add(const Duration(days: 1)).difference(now);

    _timer = Timer(durationUntilOff, () => _updateTimer(false));
  }

  // === 輔助方法 ===

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

  void _showErrorMessage(String error) {
    print('Error: $error');
    _showSnackBar(error, isError: true);
  }

  Future<TimeOfDay?> _selectTime(TimeOfDay? initialTime) async {
    return await showTimePicker(
      context: context,
      initialTime: initialTime ?? TimeOfDay.now(),
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        );
      },
    );
  }

  Future<void> _refreshData() async {
    await _fetchACStatus();
  }

  // === UI 構建方法 ===

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
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
            _buildACImage(),
            const SizedBox(height: 20),
            _buildEnvironmentInfo(),
            const SizedBox(height: 32),
            _buildModeControl(),
            const SizedBox(height: 32),
            _buildACModeSelector(),
            const SizedBox(height: 32),
            _buildTemperatureControlSection(),
            const SizedBox(height: 32),
            _buildTimerSection(),
            const SizedBox(height: 32),
            _buildPMVGauge(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildACImage() {
    return Center(
      child: Image.asset(
        'assets/ac.png', // Fixed: Removed duplicate 'assets/'
        height: 180,
        errorBuilder: (context, error, stackTrace) {
          return Icon(
            Icons.ac_unit,
            size: 180,
            color: Theme.of(context).primaryColor,
          );
        },
      ),
    );
  }

  Widget _buildEnvironmentInfo() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: _buildCardDecoration(),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Theme.of(context).primaryColor),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '當前環境資訊',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                '溫度 : $_currentRoomTemp°C',
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
              Text(
                '濕度 : ${_currentHumidity.toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 14, color: Colors.black87),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildModeControl() {
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
              onChanged: _updateManualMode,
              activeColor: Theme.of(context).primaryColor,
            ),
            const Text(
              '手動',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            _buildEnergySavingButton(),
          ],
        ),
      ],
    );
  }

  Widget _buildEnergySavingButton() {
    return ElevatedButton.icon(
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const EnergySavingSettingsPage(),
          ),
        );
      },
      icon: const Icon(Icons.settings, size: 20),
      label: const Text('節能設定', style: TextStyle(fontSize: 16)),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey.shade200,
        foregroundColor: Colors.black87,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  Widget _buildACModeSelector() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: _acModes.asMap().entries.map((entry) {
          int idx = entry.key;
          String mode = entry.value;
          bool isSelected = _selectedACModeIndex == idx;

          return Expanded(
            child: GestureDetector(
              onTap: _isManualMode ? () => _updateACMode(idx) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected && _isManualMode
                      ? Theme.of(context).primaryColor
                      : Colors.transparent,
                  border: idx > 0
                      ? Border(
                          left: BorderSide(
                            color: Colors.grey.shade300,
                            width: 1,
                          ),
                        )
                      : null,
                ),
                child: Center(
                  child: Text(
                    mode,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isSelected && _isManualMode
                          ? Colors.white
                          : (_isManualMode ? Colors.black87 : Colors.grey),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTemperatureControlSection() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _buildRecommendedTempCard(),
        const SizedBox(width: 16),
        _buildTemperatureControl(),
      ],
    );
  }

  Widget _buildRecommendedTempCard() {
    return Container(
      width: MediaQuery.of(context).size.width * 0.45,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
      decoration: _buildCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.thermostat, color: Theme.of(context).primaryColor),
              const SizedBox(width: 8),
              const Text(
                '目前建議設置溫度',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '$_recommendedTemp°C',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemperatureControl() {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '溫度設定',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_left, size: 40),
                onPressed: _isManualMode && _currentSetTemp > 16
                    ? () => _updateTemperature(_currentSetTemp - 1)
                    : null,
                color: _isManualMode ? null : Colors.grey,
              ),
              Container(
                width: 100,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$_currentSetTemp°C',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: _isManualMode ? Colors.black : Colors.grey,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_right, size: 40),
                onPressed: _isManualMode && _currentSetTemp < 30
                    ? () => _updateTemperature(_currentSetTemp + 1)
                    : null,
                color: _isManualMode ? null : Colors.grey,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimerSection() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: _buildCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTimerHeader(),
          const SizedBox(height: 16),
          _isACTimerOn ? _buildTimerSettings() : _buildTimerDisabled(),
        ],
      ),
    );
  }

  Widget _buildTimerHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          '冷氣定時',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Switch(
          value: _isACTimerOn,
          onChanged: (value) {
            if (value) {
              setState(() => _isACTimerOn = true);
            } else {
              _updateTimer(false);
            }
          },
          activeColor: Theme.of(context).primaryColor,
        ),
      ],
    );
  }

  Widget _buildTimerSettings() {
    return Column(
      children: [
        _buildTimeSelector('開機時間:', _selectedOnTime, (time) {
          setState(() => _selectedOnTime = time);
        }),
        const SizedBox(height: 12),
        _buildTimeSelector('關機時間:', _selectedOffTime, (time) {
          setState(() => _selectedOffTime = time);
        }),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _confirmTimerSettings,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 12),
          ),
          child: const Text('確定', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  Widget _buildTimeSelector(
    String label,
    TimeOfDay? time,
    Function(TimeOfDay?) onTimeSelected,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 16)),
        GestureDetector(
          onTap: () async {
            final picked = await _selectTime(time);
            if (picked != null) {
              onTimeSelected(picked);
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              time?.format(context) ?? '未設定',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTimerDisabled() {
    return const Center(
      child: Text(
        '定時功能未開啟',
        style: TextStyle(fontSize: 16, color: Colors.grey),
      ),
    );
  }

  Widget _buildPMVGauge() {
    return Center(
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 40.0, bottom: 8.0),
              child: Text(
                'PMV 數值顯示',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          CustomPaint(
            size: const Size(200, 100),
            painter: HalfCircleGaugePainter(pmvValue: _pmvValue),
            child: Container(
              width: 200,
              height: 100,
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'PMV',
                    style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
                  ),
                  Text(
                    '$_pmvValue',
                    style: TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _getPMVComfortLevel(_pmvValue),
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  String _getPMVComfortLevel(int pmv) {
    if (pmv >= -1 && pmv <= 1) {
      return '舒適';
    } else if (pmv >= -2 && pmv <= 2) {
      return pmv < 0 ? '稍冷' : '稍熱';
    } else if (pmv >= -3 && pmv <= 3) {
      return pmv < 0 ? '冷' : '熱';
    } else {
      return pmv < -3 ? '很冷' : '很熱';
    }
  }

  BoxDecoration _buildCardDecoration() {
    return BoxDecoration(
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
    );
  }
}

// PMV 儀表板繪製器
class HalfCircleGaugePainter extends CustomPainter {
  final int pmvValue;

  HalfCircleGaugePainter({required this.pmvValue});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2;

    _drawArc(canvas, center, radius);
    _drawTicks(canvas, center, radius);
    _drawPointer(canvas, center, radius);
  }

  void _drawArc(Canvas canvas, Offset center, double radius) {
    final Paint arcPaint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi,
      pi,
      false,
      arcPaint,
    );
  }

  void _drawTicks(Canvas canvas, Offset center, double radius) {
    const double tickLength = 10;
    final Paint tickPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2;

    // 繪製刻度線和標籤
    _drawTickWithLabel(canvas, center, radius, tickLength, tickPaint,
        Offset(center.dx - radius, center.dy), '-3', -15, 0);

    _drawTickWithLabel(canvas, center, radius, tickLength, tickPaint,
        Offset(center.dx, center.dy - radius), '0', -5, -tickLength - 5);

    _drawTickWithLabel(canvas, center, radius, tickLength, tickPaint,
        Offset(center.dx + radius, center.dy), '3', 5, 0);
  }

  void _drawTickWithLabel(
    Canvas canvas,
    Offset center,
    double radius,
    double tickLength,
    Paint tickPaint,
    Offset tickStart,
    String label,
    double labelOffsetX,
    double labelOffsetY,
  ) {
    canvas.drawLine(
      tickStart,
      Offset(tickStart.dx, tickStart.dy - tickLength),
      tickPaint,
    );

    TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: Colors.black, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )
      ..layout()
      ..paint(
        canvas,
        Offset(
          tickStart.dx + labelOffsetX,
          tickStart.dy - tickLength + labelOffsetY - 5,
        ),
      );
  }

  void _drawPointer(Canvas canvas, Offset center, double radius) {
    final double pointerLength = radius - 15;
    // 將 PMV 值從 -3 到 +3 映射到 0 到 1
    final double normalizedValue = (pmvValue.clamp(-3, 3) + 3) / 6;
    // 將標準化值映射到半圓弧（從左到右，即從 π 到 0）
    final double pointerAngle = pi * (1 - normalizedValue);

    final Paint pointerPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      center,
      Offset(
        center.dx + pointerLength * cos(pointerAngle),
        center.dy - pointerLength * sin(pointerAngle),
      ),
      pointerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant HalfCircleGaugePainter oldDelegate) {
    return oldDelegate.pmvValue != pmvValue;
  }
}