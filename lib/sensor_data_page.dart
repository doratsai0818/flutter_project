// sensor_data_page.dart
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:math';

// 圓形儀表板繪製器
class CircleGaugePainter extends CustomPainter {
  final double value;
  final double maxValue;
  final Color activeColor;

  CircleGaugePainter({
    required this.value,
    required this.maxValue,
    required this.activeColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 10;

    // 背景圓弧
    final backgroundPaint = Paint()
      ..color = Colors.grey[300]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10.0
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi,
      pi,
      false,
      backgroundPaint,
    );

    // 數值圓弧
    final valuePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10.0
      ..strokeCap = StrokeCap.round;

    final double sweepAngle = (value / maxValue) * pi;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi,
      sweepAngle,
      false,
      valuePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

// Token管理服务
class SensorTokenService {
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  static Future<Map<String, String>> getAuthHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }
}

// 數據頁面
class SensorDataPage extends StatefulWidget {
  const SensorDataPage({super.key});

  @override
  State<SensorDataPage> createState() => _SensorDataPageState();
}

class _SensorDataPageState extends State<SensorDataPage> {
  final String _baseUrl = 'http://localhost:3000/api';
  final Map<String, dynamic> _sensorData = {};
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  Timer? _fetchTimer;

  // 根據實際後端數據更新感測器配置 - 使用感測器名稱作為 key 來匹配
  final Map<String, Map<String, dynamic>> _sensorConfig = {
    '電耗量': {'unit': 'kWh', 'maxValue': 1000.0, 'color': Colors.red, 'icon': Icons.electrical_services},
    '電池電流': {'unit': 'A', 'maxValue': 100.0, 'color': Colors.orange, 'icon': Icons.battery_charging_full},
    '最大電池電壓': {'unit': 'V', 'maxValue': 12.0, 'color': Colors.blue, 'icon': Icons.bolt},
    '發電產量': {'unit': 'W', 'maxValue': 500.0, 'color': Colors.green, 'icon': Icons.solar_power},
  };

  @override
  void initState() {
    super.initState();
    _fetchSensorData();
    // 設定定時器，每 60 秒更新一次
    _fetchTimer = Timer.periodic(const Duration(seconds: 60), (timer) {
      _fetchSensorData();
    });
  }

  @override
  void dispose() {
    _fetchTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchSensorData() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      final headers = await SensorTokenService.getAuthHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/sensors/realtime'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] && data['data'] != null) {
          // 清空舊數據
          _sensorData.clear();
          
          // 按感測器名稱組織數據
          for (var sensor in data['data']) {
            final sensorName = sensor['name'];
            final sensorValue = sensor['latestValue']?['value'];
            final sensorTimestamp = sensor['latestValue']?['timestamp'];
            
            if (sensorName != null && _sensorConfig.containsKey(sensorName)) {
              setState(() {
                _sensorData[sensorName] = {
                  'value': _parseValue(sensorValue),
                  'timestamp': sensorTimestamp ?? '無資料',
                  'sensorId': sensor['sensorId'],
                  'error': sensor['error'],
                };
              });
            }
          }
          
          setState(() {
            _hasError = false;
          });
        } else {
          setState(() {
            _hasError = true;
            _errorMessage = '感測器數據格式錯誤';
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
          _errorMessage = '權限不足，無法訪問感測器數據';
        });
      } else {
        setState(() {
          _hasError = true;
          _errorMessage = '無法獲取感測器數據 (HTTP ${response.statusCode})';
        });
      }
    } catch (e) {
      debugPrint('無法獲取感測器數據: $e');
      setState(() {
        _hasError = true;
        _errorMessage = '網路連線失敗，請檢查伺服器狀態';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 解析數值，處理可能的字串或數字格式
  double _parseValue(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? 0.0;
    }
    return 0.0;
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
          action: isError ? SnackBarAction(
            label: '重試',
            onPressed: _fetchSensorData,
          ) : null,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 獲取發電產量作為圓形儀表板的主要顯示
    final powerConfig = _sensorConfig['發電產量'];
    final powerValue = _sensorData['發電產量']?['value'] ?? 0.0;
    
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _hasError
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
                          '資料載入失敗',
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
                          onPressed: _fetchSensorData,
                          child: const Text('重新載入'),
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
                        // 頂部圓形儀表板（顯示發電產量）
                        Card(
                          elevation: 5,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          child: Padding(
                            padding: const EdgeInsets.all(20.0),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.solar_power, color: Colors.green.shade600, size: 28),
                                    const SizedBox(width: 8),
                                    const Text(
                                      '發電產量',
                                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                SizedBox(
                                  width: 200,
                                  height: 150,
                                  child: CustomPaint(
                                    painter: CircleGaugePainter(
                                      value: powerValue,
                                      maxValue: powerConfig?['maxValue'] ?? 500.0,
                                      activeColor: powerConfig?['color'] ?? Colors.green,
                                    ),
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            '${powerValue.toStringAsFixed(0)}',
                                            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                                          ),
                                          Text(
                                            powerConfig?['unit'] ?? 'W',
                                            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Text(
                                  '上次更新：${_formatTimestamp(_sensorData['發電產量']?['timestamp'])}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        
                        // 四個感測器數據卡片
                        ...['電耗量', '電池電流', '最大電池電壓', '發電產量'].map((sensorName) => 
                          _buildSensorCard(sensorName)
                        ),
                        
                        // 系統狀態總覽
                        const SizedBox(height: 20),
                        _buildSystemStatusCard(),
                        
                        // 最後更新時間
                        const SizedBox(height: 20),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.access_time, size: 16, color: Colors.grey),
                                const SizedBox(width: 8),
                                Text(
                                  '資料更新於: ${DateTime.now().toString().substring(0, 19)}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  // 格式化時間戳
  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null || timestamp == '無資料') {
      return '無資料';
    }
    
    try {
      DateTime dateTime = DateTime.parse(timestamp.toString());
      
      // 如果解析出來的時間是 UTC，轉換為台灣時間 (UTC+8)
      if (dateTime.isUtc) {
        dateTime = dateTime.add(const Duration(hours: 8));
      } else {
        // 如果不是 UTC，確保轉換為本地時間
        dateTime = dateTime.toLocal();
      }
      
      return '${dateTime.month.toString().padLeft(2, '0')}/${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return timestamp.toString();
    }
  }

  // 建立單個感測器數據卡片
  Widget _buildSensorCard(String sensorName) {
    final config = _sensorConfig[sensorName];
    final data = _sensorData[sensorName];
    final value = data?['value'] ?? 0.0;
    final timestamp = data?['timestamp'] ?? '無資料';
    final hasError = data?['error'] != null;

    if (config == null) return const SizedBox.shrink();

    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: config['color'].withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                config['icon'],
                size: 32,
                color: config['color'],
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sensorName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        '${value.toStringAsFixed(value == value.toInt() ? 0 : 2)}',
                        style: TextStyle(
                          fontSize: 24, 
                          fontWeight: FontWeight.bold, 
                          color: hasError ? Colors.red : config['color']
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        config['unit'],
                        style: TextStyle(
                          fontSize: 16, 
                          color: Colors.grey.shade600
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hasError 
                        ? '錯誤: ${data['error']}'
                        : '更新時間：${_formatTimestamp(timestamp)}',
                    style: TextStyle(
                      fontSize: 12, 
                      color: hasError ? Colors.red : Colors.grey
                    ),
                  ),
                ],
              ),
            ),
            // 數值狀態指示器
            Container(
              width: 8,
              height: 40,
              decoration: BoxDecoration(
                color: hasError 
                    ? Colors.red
                    : (value > 0 ? config['color'] : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 系統狀態總覽卡片
  Widget _buildSystemStatusCard() {
    final powerGeneration = _sensorData['發電產量']?['value'] ?? 0.0;
    final powerConsumption = _sensorData['電耗量']?['value'] ?? 0.0;
    final batteryVoltage = _sensorData['最大電池電壓']?['value'] ?? 0.0;
    final batteryCurrent = _sensorData['電池電流']?['value'] ?? 0.0;

    // 計算系統狀態
    final isGenerating = powerGeneration > 0;
    final batteryHealth = batteryVoltage > 2.0 ? '正常' : '低電壓';
    final systemStatus = isGenerating ? '發電中' : '待機';

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dashboard, color: Colors.blue.shade600),
                const SizedBox(width: 8),
                const Text(
                  '系統狀態總覽',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatusItem('系統狀態', systemStatus, 
                    isGenerating ? Colors.green : Colors.orange),
                _buildStatusItem('電池狀態', batteryHealth, 
                    batteryVoltage > 2.0 ? Colors.green : Colors.red),
                _buildStatusItem('淨發電', 
                    '${(powerGeneration - powerConsumption).toStringAsFixed(0)}W',
                    powerGeneration > powerConsumption ? Colors.green : Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // 狀態項目
  Widget _buildStatusItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}