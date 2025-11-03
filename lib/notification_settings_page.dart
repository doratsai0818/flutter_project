import 'package:flutter/material.dart';
import 'dart:convert';

import 'package:iot_project/notification_history_page.dart';
// 匯入 main.dart 中的服務類別
import 'package:iot_project/main.dart';

/// 定義通知偏好設定
enum NotificationPreference {
  vibrationAndSound,
  vibrationOnly,
  soundOnly,
}

extension NotificationPreferenceExtension on NotificationPreference {
  String get displayName {
    switch (this) {
      case NotificationPreference.vibrationAndSound:
        return '震動 + 鈴聲';
      case NotificationPreference.vibrationOnly:
        return '震動';
      case NotificationPreference.soundOnly:
        return '鈴聲';
    }
  }

  /// Helper to convert string from backend to enum
  static NotificationPreference fromString(String? value) {
    if (value == null) return NotificationPreference.vibrationAndSound;
    
    switch (value) {
      case 'vibrationOnly':
        return NotificationPreference.vibrationOnly;
      case 'soundOnly':
        return NotificationPreference.soundOnly;
      case 'vibrationAndSound':
      default:
        return NotificationPreference.vibrationAndSound;
    }
  }

  /// Helper to convert enum to string for backend
  String toBackendString() {
    switch (this) {
      case NotificationPreference.vibrationAndSound:
        return 'vibrationAndSound';
      case NotificationPreference.vibrationOnly:
        return 'vibrationOnly';
      case NotificationPreference.soundOnly:
        return 'soundOnly';
    }
  }
}

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  // 各類通知的開關狀態和偏好，從後端獲取
  bool _powerAnomalyOn = true;
  NotificationPreference _powerAnomalyPreference = NotificationPreference.vibrationAndSound;

  bool _tempLightReminderOn = true;
  NotificationPreference _tempLightReminderPreference = NotificationPreference.vibrationAndSound;

  bool _sensorAnomalyOn = true;
  NotificationPreference _sensorAnomalyPreference = NotificationPreference.vibrationAndSound;

  bool _systemModeSwitchOn = true;
  NotificationPreference _systemModeSwitchPreference = NotificationPreference.vibrationOnly;

  bool _isLoading = false;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _fetchNotificationSettings();
  }

  /// 從後端獲取通知設定（使用 JWT token）
  Future<void> _fetchNotificationSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 使用 ApiService 發送帶有 JWT token 的請求
      final response = await ApiService.get('/notification/settings');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (mounted) {
          setState(() {
            // 根據後端資料庫結構解析數據
            _powerAnomalyOn = data['power_anomaly_on'] ?? true;
            _powerAnomalyPreference = NotificationPreferenceExtension.fromString(
              data['power_anomaly_preference']
            );

            _tempLightReminderOn = data['temp_light_reminder_on'] ?? true;
            _tempLightReminderPreference = NotificationPreferenceExtension.fromString(
              data['temp_light_reminder_preference']
            );

            _sensorAnomalyOn = data['sensor_anomaly_on'] ?? true;
            _sensorAnomalyPreference = NotificationPreferenceExtension.fromString(
              data['sensor_anomaly_preference']
            );

            _systemModeSwitchOn = data['system_mode_switch_on'] ?? true;
            _systemModeSwitchPreference = NotificationPreferenceExtension.fromString(
              data['system_mode_switch_preference']
            );

            _isInitialized = true;
          });
        }
        print('成功獲取通知設定: $data');
        
      } else if (response.statusCode == 401) {
        // Token 失效
        _showSnackBar('登入已過期，請重新登入', isError: true);
        await _handleTokenExpired();
        
      } else if (response.statusCode == 404) {
        _showSnackBar('找不到通知設定，使用預設值', isError: false);
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
        _showSnackBar('網路連線錯誤，請檢查伺服器狀態', isError: true);
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

  /// 處理 Token 過期
  Future<void> _handleTokenExpired() async {
    await TokenService.clearAuthData();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  /// 向後端發送更新通知設定的請求（使用 JWT token）
  Future<void> _updateNotificationSetting(
    String type, {
    bool? isOn,
    NotificationPreference? preference,
  }) async {
    if (!_isInitialized) return;

    try {
      // 構建請求體，符合後端 API 期望的格式
      final Map<String, dynamic> body = {
        'type': type,
      };
      
      // 根據提供的參數決定發送的內容
      if (isOn != null) {
        body['isOn'] = isOn;
      }
      if (preference != null) {
        body['preference'] = preference.toBackendString();
      }

      // 確保至少有一個參數被提供
      if (isOn == null && preference == null) {
        print('警告: 更新通知設定時沒有提供任何參數');
        return;
      }

      print('發送通知設定更新請求: $body');

      // 使用 ApiService 發送帶有 JWT token 的請求
      final response = await ApiService.post('/notification/settings', body);

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('成功更新通知設定: $type - ${responseData['message']}');
        
        if (mounted) {
          _showSnackBar('${_getNotificationTypeName(type)} 設定已保存！', isError: false);
        }
        
      } else if (response.statusCode == 401) {
        // Token 失效
        print('Token 失效，需要重新登入');
        _showSnackBar('登入已過期，請重新登入', isError: true);
        await _handleTokenExpired();
        
      } else if (response.statusCode == 400) {
        final errorData = json.decode(response.body);
        print('請求參數錯誤: ${errorData['message']}');
        _showSnackBar(errorData['message'] ?? '參數錯誤', isError: true);
        
        // 重新載入設定以恢復正確狀態
        await _fetchNotificationSettings();
        
      } else if (response.statusCode == 404) {
        print('找不到用戶通知設定');
        _showSnackBar('找不到您的通知設定，請聯繫客服', isError: true);
        
      } else {
        final errorData = json.decode(response.body);
        print('更新通知設定失敗: ${response.statusCode} - ${response.body}');
        _showSnackBar(errorData['message'] ?? '保存失敗，請重試', isError: true);
        
        // 重新載入設定以恢復正確狀態
        await _fetchNotificationSettings();
      }
      
    } catch (e) {
      print('更新通知設定時發生錯誤: $e');
      if (mounted) {
        _showSnackBar('網路連線錯誤，請檢查伺服器狀態', isError: true);
        
        // 重新載入設定以恢復正確狀態
        await _fetchNotificationSettings();
      }
    }
  }

  /// 更新開關狀態的便利方法
  Future<void> _updateNotificationSwitch(String type, bool isOn) async {
    await _updateNotificationSetting(type, isOn: isOn);
  }

  /// 更新偏好設定的便利方法  
  Future<void> _updateNotificationPreference(String type, NotificationPreference preference) async {
    await _updateNotificationSetting(type, preference: preference);
  }

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

  /// 根據類型字串獲取通知名稱 (用於 SnackBar 提示)
  String _getNotificationTypeName(String type) {
    switch (type) {
      case 'powerAnomaly':
        return '用電異常通知';
      case 'tempLightReminder':
        return '溫度過高 / 照度不足提醒';
      case 'sensorAnomaly':
        return '感測器異常 / 離線警告';
      case 'systemModeSwitch':
        return '系統切換模式提示';
      default:
        return '通知';
    }
  }

  /// 重新載入設定
  Future<void> _refreshSettings() async {
    await _fetchNotificationSettings();
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
                    subtitle: '當偵測到異常用電時通知您',
                    icon: Icons.power_off,
                    isOn: _powerAnomalyOn,
                    onChanged: _isInitialized ? (value) {
                      setState(() => _powerAnomalyOn = value);
                      _updateNotificationSwitch('powerAnomaly', value);
                    } : null,
                    preference: _powerAnomalyPreference,
                    onPreferenceChanged: _isInitialized ? (newPreference) {
                      setState(() => _powerAnomalyPreference = newPreference);
                      _updateNotificationPreference('powerAnomaly', newPreference);
                    } : null,
                  ),

                  // 溫度過高 / 照度不足提醒
                  _buildNotificationTypeCard(
                    context,
                    index: 2,
                    title: '環境警告提醒',
                    subtitle: '溫度過高或照度不足時提醒',
                    icon: Icons.thermostat,
                    isOn: _tempLightReminderOn,
                    onChanged: _isInitialized ? (value) {
                      setState(() => _tempLightReminderOn = value);
                      _updateNotificationSwitch('tempLightReminder', value);
                    } : null,
                    preference: _tempLightReminderPreference,
                    onPreferenceChanged: _isInitialized ? (newPreference) {
                      setState(() => _tempLightReminderPreference = newPreference);
                      _updateNotificationPreference('tempLightReminder', newPreference);
                    } : null,
                  ),

                  // 感測器異常 / 離線警告
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
                    preference: _sensorAnomalyPreference,
                    onPreferenceChanged: _isInitialized ? (newPreference) {
                      setState(() => _sensorAnomalyPreference = newPreference);
                      _updateNotificationPreference('sensorAnomaly', newPreference);
                    } : null,
                  ),

                  // 系統切換模式提示
                  _buildNotificationTypeCard(
                    context,
                    index: 4,
                    title: '系統模式切換',
                    subtitle: '系統切換運作模式時提示',
                    icon: Icons.swap_horiz,
                    isOn: _systemModeSwitchOn,
                    onChanged: _isInitialized ? (value) {
                      setState(() => _systemModeSwitchOn = value);
                      _updateNotificationSwitch('systemModeSwitch', value);
                    } : null,
                    preference: _systemModeSwitchPreference,
                    onPreferenceChanged: _isInitialized ? (newPreference) {
                      setState(() => _systemModeSwitchPreference = newPreference);
                      _updateNotificationPreference('systemModeSwitch', newPreference);
                    } : null,
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

  /// 通知類型設定卡片
  Widget _buildNotificationTypeCard(
    BuildContext context, {
    required int index,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isOn,
    required ValueChanged<bool>? onChanged,
    required NotificationPreference preference,
    required ValueChanged<NotificationPreference>? onPreferenceChanged,
  }) {
    final isEnabled = onChanged != null && onPreferenceChanged != null;

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

            // 偏好設定 (只在開關開啟時顯示)
            if (isOn) ...[
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.volume_up, size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  const Text(
                    '通知方式：',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: PopupMenuButton<NotificationPreference>(
                      initialValue: preference,
                      onSelected: isEnabled ? onPreferenceChanged : null,
                      itemBuilder: (BuildContext context) => 
                          NotificationPreference.values
                              .map((p) => PopupMenuItem<NotificationPreference>(
                                      value: p,
                                      child: Row(
                                        children: [
                                          Icon(
                                            _getPreferenceIcon(p),
                                            size: 18,
                                            color: Theme.of(context).primaryColor,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(p.displayName),
                                        ],
                                      ),
                                    ))
                              .toList(),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            preference.displayName,
                            style: TextStyle(
                              color: Theme.of(context).primaryColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Icon(
                            Icons.arrow_drop_down,
                            color: Theme.of(context).primaryColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 根據偏好設定獲取對應圖示
  IconData _getPreferenceIcon(NotificationPreference preference) {
    switch (preference) {
      case NotificationPreference.vibrationAndSound:
        return Icons.vibration;
      case NotificationPreference.vibrationOnly:
        return Icons.vibration;
      case NotificationPreference.soundOnly:
        return Icons.volume_up;
    }
  }
}