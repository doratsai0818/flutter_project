import 'package:flutter/material.dart';
import 'dart:convert';

import 'package:iot_project/notification_history_page.dart';
import 'package:iot_project/main.dart';

// 移除 NotificationPreference enum 和 extension

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  // 各類通知的開關狀態 (移除 Preference)
  bool _powerAnomalyOn = true;
  bool _tempLightReminderOn = true;
  bool _sensorAnomalyOn = true;

  bool _isLoading = false;
  bool _isInitialized = false;

  // 閾值設定
  double _humidityHighThreshold = 28.0; 
  double _tempHighThreshold = 32.0;
  double _powerSpikeThreshold = 2000;
  int _offlineTimeoutSec = 300;

  @override
  void initState() {
    super.initState();
    _fetchNotificationSettings();
    _fetchAlertThresholds();
  }

  /// 從後端獲取通知設定
  Future<void> _fetchNotificationSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiService.get('/notification/settings');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (mounted) {
          setState(() {
            _powerAnomalyOn = data['power_anomaly_on'] ?? true;
            // 移除 _powerAnomalyPreference 的設定

            _tempLightReminderOn = data['temp_light_reminder_on'] ?? true;
            // 移除 _tempLightReminderPreference 的設定

            _sensorAnomalyOn = data['sensor_anomaly_on'] ?? true;
            // 移除 _sensorAnomalyPreference 的設定

            _isInitialized = true;
          });
        }
        print('成功獲取通知設定: $data');
        
      } else if (response.statusCode == 401) {
        _showSnackBar('登入已過期,請重新登入', isError: true);
        await _handleTokenExpired();
        
      } else if (response.statusCode == 404) {
        _showSnackBar('找不到通知設定,使用預設值', isError: false);
        setState(() {
          _isInitialized = true;
        });
        
      } else {
        final errorData = json.decode(response.body);
        print('獲取通知設定失敗: ${response.statusCode}');
        _showSnackBar(errorData['message'] ?? '獲取通知設定失敗', isError: true);
        setState(() {
          _isInitialized = true;
        });
      }
      
    } catch (e) {
      print('獲取通知設定時發生錯誤: $e');
      if (mounted) {
        _showSnackBar('網路連線錯誤,請檢查伺服器狀態', isError: true);
        setState(() {
          _isInitialized = true;
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // 獲取閾值設定
Future<void> _fetchAlertThresholds() async {
    try {
      final response = await ApiService.get('/alert/thresholds');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (mounted) {
          setState(() {
            _humidityHighThreshold = _toDouble(data['humidity_high_threshold']) ?? 70.0; 
            _tempHighThreshold = _toDouble(data['temp_critical_threshold']) ?? 32.0;
            _powerSpikeThreshold = _toDouble(data['power_spike_threshold']) ?? 2000.0;
            _offlineTimeoutSec = _toInt(data['offline_timeout_sec']) ?? 300;
          });
        }
      }
    } catch (e) {
      print('獲取閾值設定失敗: $e');
    }
}

  /// 安全地轉換為 double
  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// 安全地轉換為 int
  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// 處理 Token 過期
  Future<void> _handleTokenExpired() async {
    // 假設 TokenService.clearAuthData() 存在於 main.dart 或其他地方
    // await TokenService.clearAuthData(); 
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  Future<void> _sendTestNotification() async {
    try {
      final response = await ApiService.post('/test/notification', {
        'message': '這是來自 App 的測試通知 📱'
      });
      
      if (response.statusCode == 200) {
        _showSnackBar('測試通知已發送,請檢查手機通知', isError: false);
      } else {
        final data = json.decode(response.body);
        _showSnackBar('發送失敗: ${data['message']}', isError: true);
      }
    } catch (e) {
      _showSnackBar('發送測試通知失敗: $e', isError: true);
    }
  }

  /// 向後端發送更新通知設定的請求
  Future<void> _updateNotificationSetting(
    String type, {
    required bool isOn, // 只保留 isOn
  }) async {
    if (!_isInitialized) return;

    try {
      final Map<String, dynamic> body = {
        'type': type,
        'isOn': isOn,
        // 移除 preference 參數，但因為後端 API 需要 preference 欄位，所以統一傳送 'vibrationAndSound'
        'preference': 'vibrationAndSound' 
      };
      
      print('發送通知設定更新請求: $body');

      final response = await ApiService.post('/notification/settings', body);

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('成功更新通知設定: $type - ${responseData['message']}');
        
        if (mounted) {
          _showSnackBar('${_getNotificationTypeName(type)} 設定已保存!', isError: false);
        }
        
      } else if (response.statusCode == 401) {
        print('Token 失效,需要重新登入');
        _showSnackBar('登入已過期,請重新登入', isError: true);
        await _handleTokenExpired();
        
      } else {
        final errorData = json.decode(response.body);
        print('更新通知設定失敗: ${response.statusCode} - ${response.body}');
        _showSnackBar(errorData['message'] ?? '保存失敗,請重試', isError: true);
        
        await _fetchNotificationSettings();
      }
      
    } catch (e) {
      print('更新通知設定時發生錯誤: $e');
      if (mounted) {
        _showSnackBar('網路連線錯誤,請檢查伺服器狀態', isError: true);
        await _fetchNotificationSettings();
      }
    }
  }

  /// 更新開關狀態的便利方法
  Future<void> _updateNotificationSwitch(String type, bool isOn) async {
    await _updateNotificationSetting(type, isOn: isOn);
  }

  // 移除 _updateNotificationPreference

  /// 顯示訊息
  void _showSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// 根據類型字串獲取通知名稱
  String _getNotificationTypeName(String type) {
    switch (type) {
      case 'powerAnomaly':
        return '用電異常通知';
      case 'tempLightReminder':
        return '環境警告提醒';
      case 'sensorAnomaly':
        return '設備狀態警告';
      default:
        return '通知';
    }
  }

  /// 重新載入設定
  Future<void> _refreshSettings() async {
    await _fetchNotificationSettings();
    await _fetchAlertThresholds();
  }

  /// ✅ 顯示可編輯的閾值設定對話框
  void _showEditableThresholdDialog() {
    // 建立暫存控制器
    final humidityController = TextEditingController(
      text: _humidityHighThreshold.toStringAsFixed(1)
    );
    final tempController = TextEditingController(
      text: _tempHighThreshold.toStringAsFixed(1)
    );
    final powerController = TextEditingController(
      text: _powerSpikeThreshold.toStringAsFixed(0)
    );
    final offlineController = TextEditingController(
      text: (_offlineTimeoutSec ~/ 60).toString()
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('異常偵測閾值設定'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 濕度過高警告
              TextField(
                controller: humidityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '濕度過高警告',
                  suffixText: '%',
                  helperText: '建議範圍: 60-80%',
                ),
              ),
              const SizedBox(height: 16),
              
              // 溫度過高警告
              TextField(
                controller: tempController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '溫度過高警告',
                  suffixText: '°C',
                  helperText: '建議範圍: 28-35°C',
                ),
              ),
              const SizedBox(height: 16),
              
              // 功率異常警告
              TextField(
                controller: powerController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '功率異常警告',
                  suffixText: 'W',
                  helperText: '建議範圍: 1500-3000W',
                ),
              ),
              const SizedBox(height: 16),
              
              // 離線判定時間
              TextField(
                controller: offlineController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '離線判定時間',
                  suffixText: '分鐘',
                  helperText: '建議範圍: 3-10 分鐘',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                // 解析輸入值
                final humidity = double.tryParse(humidityController.text);
                final temp = double.tryParse(tempController.text);
                final power = double.tryParse(powerController.text);
                final offlineMin = int.tryParse(offlineController.text);

                // 驗證輸入
                if (humidity == null || temp == null || power == null || offlineMin == null) {
                  _showSnackBar('請輸入有效的數值', isError: true);
                  return;
                }

                // ✅ 濕度範圍驗證 (50-90%)
                if (humidity < 50 || humidity > 90) {
                  _showSnackBar('濕度必須在 50-90% 之間', isError: true);
                  return;
                }

                // ✅ 溫度範圍驗證 (28-40°C)
                if (temp < 28 || temp > 40) {
                  _showSnackBar('溫度必須在 28-40°C 之間', isError: true);
                  return;
                }

                if (power < 0 || power > 5000) {
                  _showSnackBar('功率必須在 0-5000W 之間', isError: true);
                  return;
                }

                if (offlineMin < 1 || offlineMin > 60) {
                  _showSnackBar('離線時間必須在 1-60 分鐘之間', isError: true);
                  return;
                }

                // 儲存閾值
                final response = await ApiService.post('/alert/thresholds', {
                  'humidityHighThreshold': humidity,
                  'tempCriticalThreshold': temp,
                  'powerSpikeThreshold': power,
                  'offlineTimeoutSec': offlineMin * 60,
                });

                if (response.statusCode == 200) {
                  setState(() {
                    _humidityHighThreshold = humidity;
                    _tempHighThreshold = temp;
                    _powerSpikeThreshold = power;
                    _offlineTimeoutSec = offlineMin * 60;
                  });
                  
                  Navigator.pop(context);
                  _showSnackBar('閾值設定已更新!', isError: false);
                } else {
                  final data = json.decode(response.body);
                  _showSnackBar('更新失敗: ${data['message']}', isError: true);
                }
              } catch (e) {
                _showSnackBar('更新閾值失敗: $e', isError: true);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ).then((_) {
      // 釋放控制器
      humidityController.dispose();
      tempController.dispose();
      powerController.dispose();
      offlineController.dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('通知設定'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // ✅ 測試按鈕
          IconButton(
            icon: const Icon(Icons.notifications_active),
            onPressed: _sendTestNotification,
            tooltip: '發送測試通知',
          ),
          // ✅ 閾值設定按鈕(改為可編輯)
          IconButton(
            icon: const Icon(Icons.tune),
            onPressed: _showEditableThresholdDialog,
            tooltip: '編輯閾值設定',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refreshSettings,
            tooltip: '重新載入',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshSettings,
        child: Stack(
          children: [
            SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.notifications_active, size: 28),
                      const SizedBox(width: 12),
                      const Text(
                        '通知類型設定',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.only(left: 12),
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '設定各類通知的開關和提醒方式',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // 用電異常通知
                  _buildNotificationTypeCard(
                    context,
                    index: 1,
                    title: '用電異常通知',
                    subtitle: '功率異常、電流過載、設備故障等警告',
                    icon: Icons.power_off,
                    isOn: _powerAnomalyOn,
                    onChanged: _isInitialized ? (value) {
                      setState(() => _powerAnomalyOn = value);
                      _updateNotificationSwitch('powerAnomaly', value);
                    } : null,
                    // 移除 preference 參數
                  ),

                  // 環境警告提醒
                  _buildNotificationTypeCard(
                    context,
                    index: 2,
                    title: '環境警告提醒',
                    subtitle: '溫度/濕度過高時提醒',
                    icon: Icons.thermostat,
                    isOn: _tempLightReminderOn,
                    onChanged: _isInitialized ? (value) {
                      setState(() => _tempLightReminderOn = value);
                      _updateNotificationSwitch('tempLightReminder', value);
                    } : null,
                    // 移除 preference 參數
                  ),

                  // 設備狀態警告
                  _buildNotificationTypeCard(
                    context,
                    index: 3,
                    title: '設備狀態警告',
                    subtitle: '感測器異常或離線時警告',
                    icon: Icons.sensors_off,
                    isOn: _sensorAnomalyOn,
                    onChanged: _isInitialized ? (value) {
                      setState(() => _sensorAnomalyOn = value);
                      _updateNotificationSwitch('sensorAnomaly', value);
                    } : null,
                    // 移除 preference 參數
                  ),

                  const SizedBox(height: 32),

                  // 通知歷史記錄按鈕
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const NotificationHistoryPage(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.history),
                      label: const Text('通知歷史記錄', style: TextStyle(fontSize: 18)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
            
            // 載入遮罩
            if (_isLoading && !_isInitialized)
              Container(
                color: Colors.white70,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(
                        '載入通知設定中...',
                        style: TextStyle(fontSize: 16),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 通知類型設定卡片 (移除 Preference 相關參數和 UI)
  Widget _buildNotificationTypeCard(
    BuildContext context, {
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isOn,
    required ValueChanged<bool>? onChanged,
    // 移除 preference 參數
    // 移除 onPreferenceChanged 參數
  }) {
    final isEnabled = onChanged != null; // 簡化啟用檢查

    return Card(
      margin: const EdgeInsets.only(bottom: 16.0),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Row(
              children: [
                // 圖示
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: isOn 
                        ? Theme.of(context).primaryColor.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: isOn 
                        ? Theme.of(context).primaryColor
                        : Colors.grey,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),

                // 標題和描述
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isEnabled ? null : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: isEnabled ? Colors.grey[600] : Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                ),

                // 開關
                Switch(
                  value: isOn,
                  onChanged: isEnabled ? onChanged : null,
                  activeColor: Theme.of(context).primaryColor,
                ),
              ],
            ),

            // 移除偏好設定區塊
            // if (isOn) ...[
            //   const SizedBox(height: 12),
            //   const Divider(),
            //   ...
            // ],
          ],
        ),
      ),
    );
  }

  // 移除 _getPreferenceIcon (不再需要)
}