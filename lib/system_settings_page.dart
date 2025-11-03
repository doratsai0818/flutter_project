import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class SystemSettingsPage extends StatefulWidget {
  const SystemSettingsPage({super.key});

  @override
  State<SystemSettingsPage> createState() => _SystemSettingsPageState();
}

class _SystemSettingsPageState extends State<SystemSettingsPage> {
  final String _baseUrl = 'http://localhost:3000/api';

  // 系統設定狀態
  bool _isDarkMode = false;
  String _selectedLanguage = '載入中...';
  double _preferredTemperature = 26.0;
  double _preferredBrightness = 50.0;
  String _preferredColorTemp = '載入中...';

  // UI 狀態
  bool _isPreferenceExpanded = false;
  bool _isLoading = true;
  String _errorMessage = '';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _fetchSystemSettings();
  }

  /// 安全地轉換數值為 double
  double _safeToDouble(dynamic value, double defaultValue) {
    if (value == null) return defaultValue;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      return double.tryParse(value) ?? defaultValue;
    }
    return defaultValue;
  }

  /// 獲取認證標頭
  Future<Map<String, String>> _getAuthHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// 從後端獲取系統設定
  Future<void> _fetchSystemSettings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/system/settings'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        setState(() {
          _isDarkMode = data['is_dark_mode'] ?? false;
          _selectedLanguage = data['selected_language'] ?? '繁體中文';
          // 使用安全轉換函數處理可能是字串的數值
          _preferredTemperature = _safeToDouble(data['preferred_temperature'], 26.0);
          _preferredBrightness = _safeToDouble(data['preferred_brightness'], 50.0);
          _preferredColorTemp = data['preferred_color_temp'] ?? '暖色';
          _isLoading = false;
        });
        print('成功獲取系統設定: $data');
        print('溫度類型: ${data['preferred_temperature'].runtimeType}');
        print('亮度類型: ${data['preferred_brightness'].runtimeType}');
      } else if (response.statusCode == 401) {
        setState(() {
          _errorMessage = '認證失敗，請重新登入';
          _isLoading = false;
        });
        _handleAuthError();
      } else if (response.statusCode == 404) {
        setState(() {
          _errorMessage = '找不到系統設定，將使用預設值';
          _isLoading = false;
        });
        _setDefaultValues();
      } else {
        final errorBody = json.decode(response.body);
        setState(() {
          _errorMessage = errorBody['message'] ?? '載入系統設定失敗: ${response.statusCode}';
          _isLoading = false;
        });
        print('獲取系統設定失敗: ${response.statusCode}, ${response.body}');
      }
    } on SocketException {
      setState(() {
        _errorMessage = '無法連接到伺服器，請檢查網路連線';
        _isLoading = false;
      });
      print('網路連線錯誤');
    } catch (e) {
      setState(() {
        _errorMessage = '發生未知錯誤: $e';
        _isLoading = false;
      });
      print('獲取系統設定時發生錯誤: $e');
    }
  }

  /// 設定預設值
  void _setDefaultValues() {
    setState(() {
      _isDarkMode = false;
      _selectedLanguage = '繁體中文';
      _preferredTemperature = 26.0;
      _preferredBrightness = 50.0;
      _preferredColorTemp = '暖色';
    });
  }

  /// 處理認證錯誤
  void _handleAuthError() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('認證錯誤'),
          content: const Text('您的登入狀態已過期，請重新登入。'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
              },
              child: const Text('確定'),
            ),
          ],
        );
      },
    );
  }

  /// 將系統設定更新發送到後端
  Future<void> _updateSystemSettings() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
    });

    try {
      final headers = await _getAuthHeaders();
      final Map<String, dynamic> updateData = {
        'isDarkMode': _isDarkMode,
        'selectedLanguage': _selectedLanguage,
        'preferredTemperature': _preferredTemperature,
        'preferredBrightness': _preferredBrightness,
        'preferredColorTemp': _preferredColorTemp,
      };

      final response = await http.post(
        Uri.parse('$_baseUrl/system/settings'),
        headers: headers,
        body: json.encode(updateData),
      );

      if (response.statusCode == 200) {
        print('成功更新系統設定');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('系統設定已保存！'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (response.statusCode == 401) {
        _handleAuthError();
      } else {
        final errorBody = json.decode(response.body);
        print('更新系統設定失敗: ${response.statusCode} - ${response.body}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorBody['message'] ?? '保存失敗，請重試！'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } on SocketException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('保存失敗，請檢查網路連接！'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      print('更新系統設定時發生錯誤: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('保存失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  /// 顯示保存確認對話框
  void _showSaveDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('保存設定'),
          content: const Text('確定要保存這些設定變更嗎？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _updateSystemSettings();
              },
              child: _isSaving 
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('保存'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('系統設定'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!_isLoading && _errorMessage.isEmpty)
            TextButton.icon(
              onPressed: _isSaving ? null : _showSaveDialog,
              icon: _isSaving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
              label: Text(_isSaving ? '保存中...' : '保存'),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              '載入系統設定...',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchSystemSettings,
              child: const Text('重試'),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 主題設定
          _buildSettingCard(
            title: '外觀設定',
            icon: Icons.palette,
            child: Column(
              children: [
                _buildSwitchTile(
                  title: '深色模式',
                  subtitle: _isDarkMode ? '已啟用深色主題' : '已啟用淺色主題',
                  value: _isDarkMode,
                  onChanged: (value) {
                    setState(() {
                      _isDarkMode = value;
                    });
                  },
                ),
                const Divider(height: 1),
                _buildSelectableTile(
                  title: '語言',
                  subtitle: _selectedLanguage,
                  onTap: () => _showLanguagePicker(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 偏好設定
          _buildSettingCard(
            title: '偏好設定',
            icon: Icons.tune,
            child: Column(
              children: [
                _buildSelectableTile(
                  title: '偏好溫度',
                  subtitle: '${_preferredTemperature.toInt()}°C',
                  onTap: () => _showTemperaturePicker(context),
                ),
                const Divider(height: 1),
                _buildSelectableTile(
                  title: '偏好亮度',
                  subtitle: '${_preferredBrightness.toInt()}%',
                  onTap: () => _showBrightnessPicker(context),
                ),
                const Divider(height: 1),
                _buildSelectableTile(
                  title: '偏好色溫',
                  subtitle: _preferredColorTemp,
                  onTap: () => _showColorTempPicker(context),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSettingCard({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: Colors.blue.shade600, size: 24),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600])),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: Colors.blue.shade600,
      ),
    );
  }

  Widget _buildSelectableTile({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      title: Text(title),
      subtitle: Text(subtitle, style: TextStyle(color: Colors.grey[600])),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }

  // ===== 對話框選擇器 =====

  void _showLanguagePicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('選擇語言'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildLanguageOption('繁體中文'),
              _buildLanguageOption('簡體中文'),
              _buildLanguageOption('English'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLanguageOption(String language) {
    return RadioListTile<String>(
      title: Text(language),
      value: language,
      groupValue: _selectedLanguage,
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _selectedLanguage = value;
          });
          Navigator.pop(context);
        }
      },
    );
  }

  void _showTemperaturePicker(BuildContext context) {
    double temp = _preferredTemperature;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('設定偏好溫度'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setStateInner) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${temp.toInt()}°C',
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  Slider(
                    value: temp,
                    min: 16,
                    max: 30,
                    divisions: 14,
                    onChanged: (newValue) {
                      setStateInner(() {
                        temp = newValue;
                      });
                    },
                    activeColor: Colors.blue.shade600,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _preferredTemperature = temp;
                          });
                          Navigator.pop(context);
                        },
                        child: const Text('確定'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showBrightnessPicker(BuildContext context) {
    double brightness = _preferredBrightness;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('設定偏好亮度'),
          content: StatefulBuilder(
            builder: (BuildContext context, StateSetter setStateInner) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${brightness.toInt()}%',
                    style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 20),
                  Slider(
                    value: brightness,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    onChanged: (newValue) {
                      setStateInner(() {
                        brightness = newValue;
                      });
                    },
                    activeColor: Colors.blue.shade600,
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _preferredBrightness = brightness;
                          });
                          Navigator.pop(context);
                        },
                        child: const Text('確定'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  void _showColorTempPicker(BuildContext context) {
    final colorTemps = ['暖色', '中性白', '冷色'];
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('設定偏好色溫'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: colorTemps.map((colorTemp) {
              return RadioListTile<String>(
                title: Text(colorTemp),
                value: colorTemp,
                groupValue: _preferredColorTemp,
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _preferredColorTemp = value;
                    });
                    Navigator.pop(context);
                  }
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }
}