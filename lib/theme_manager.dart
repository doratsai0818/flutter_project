import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// ThemeManager 將用於管理應用程式的主題模式
class ThemeManager with ChangeNotifier {
  final String _baseUrl = 'https://unequatorial-cenogenetically-margrett.ngrok-free.dev/api'; // 後端 API 的基礎 URL

  ThemeMode _themeMode = ThemeMode.system; // 預設為系統主題
  bool _isLoading = false; // 用於表示是否正在載入設定
  String _errorMessage = ''; // 用於儲存錯誤訊息

  // Getters
  ThemeMode get themeMode => _themeMode;
  bool get isLoading => _isLoading;
  String get errorMessage => _errorMessage;

  ThemeManager() {
    _fetchThemeSettings(); // 初始化時從後端獲取主題設定
  }

  /// 從後端獲取主題設定
  Future<void> _fetchThemeSettings() async {
    _isLoading = true;
    _errorMessage = '';
    notifyListeners(); // 通知監聽器開始載入

    try {
      final response = await http.get(Uri.parse('$_baseUrl/system/settings'));
      
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        bool isDarkMode = data['isDarkMode'] ?? false; // 從後端獲取 isDarkMode
        _themeMode = isDarkMode ? ThemeMode.dark : ThemeMode.light; // 轉換為 ThemeMode
      } else {
        _errorMessage = '載入主題設定失敗: ${response.statusCode}';
        print(_errorMessage);
      }
    } catch (e) {
      _errorMessage = '無法連接到伺服器以獲取主題設定: $e';
      print(_errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners(); // 通知監聽器載入完成 (或發生錯誤)
    }
  }

  /// 設定新的主題模式並更新後端
  Future<void> setThemeMode(ThemeMode newMode) async {
    if (_themeMode == newMode) return; // 如果主題模式沒有改變，則不執行任何操作

    _themeMode = newMode;
    notifyListeners(); // 先通知前端更新UI

    // 將 ThemeMode 轉換為 boolean 以發送到後端
    bool isDarkModeForBackend = (newMode == ThemeMode.dark);

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/system/settings'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'isDarkMode': isDarkModeForBackend}),
      );

      if (response.statusCode == 200) {
        print('成功更新後端主題設定為: $isDarkModeForBackend');
      } else {
        print('更新後端主題設定失敗: ${response.statusCode} - ${response.body}');
        // 如果後端更新失敗，可以考慮回滾前端狀態或通知用戶
      }
    } catch (e) {
      print('更新後端主題設定時發生錯誤: $e');
      // 處理網路錯誤
    }
  }
}