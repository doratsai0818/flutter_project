import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

// 確保這個匯入路徑正確
// import 'package:iot_project/main.dart'; // 如果需要使用 ApiService

class NotificationHistoryPage extends StatefulWidget {
  const NotificationHistoryPage({super.key});

  @override
  State<NotificationHistoryPage> createState() => _NotificationHistoryPageState();
}

class _NotificationHistoryPageState extends State<NotificationHistoryPage> {
  final String _baseUrl = 'http://localhost:3000/api';

  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchNotificationHistory();
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

  /// 從後端 API 獲取通知歷史紀錄
  Future<void> _fetchNotificationHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final headers = await _getAuthHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/notifications/history'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _notifications = data.map((item) => Map<String, dynamic>.from(item)).toList();
          _isLoading = false;
        });
        print('成功獲取通知歷史紀錄: $_notifications');
      } else if (response.statusCode == 401) {
        setState(() {
          _errorMessage = '認證失敗，請重新登入';
          _isLoading = false;
        });
        print('認證失敗: ${response.statusCode}');
        _handleAuthError();
      } else if (response.statusCode == 404) {
        setState(() {
          _notifications = [];
          _isLoading = false;
        });
        print('沒有找到通知歷史紀錄');
      } else {
        final errorBody = json.decode(response.body);
        setState(() {
          _errorMessage = errorBody['message'] ?? '載入失敗: ${response.statusCode}';
          _isLoading = false;
        });
        print('獲取通知歷史紀錄失敗: ${response.statusCode}, ${response.body}');
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
      print('獲取通知歷史紀錄時發生錯誤: $e');
    }
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
                // 這裡可以導航回登入頁面
                Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
              },
              child: const Text('確定'),
            ),
          ],
        );
      },
    );
  }

  /// 格式化時間顯示
  String _formatDateTime(String dateTimeStr) {
    try {
      final dateTime = DateTime.parse(dateTimeStr);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inDays > 0) {
        return '${difference.inDays}天前';
      } else if (difference.inHours > 0) {
        return '${difference.inHours}小時前';
      } else if (difference.inMinutes > 0) {
        return '${difference.inMinutes}分鐘前';
      } else {
        return '剛剛';
      }
    } catch (e) {
      return dateTimeStr; // 如果解析失敗，返回原始字串
    }
  }

  /// 取得通知圖示
  IconData _getNotificationIcon(String message) {
    if (message.contains('用電異常') || message.contains('功耗')) {
      return Icons.power_off;
    } else if (message.contains('溫度') || message.contains('冷氣')) {
      return Icons.thermostat;
    } else if (message.contains('燈光') || message.contains('亮度')) {
      return Icons.lightbulb;
    } else if (message.contains('感測器')) {
      return Icons.sensors;
    } else if (message.contains('系統模式')) {
      return Icons.settings;
    } else {
      return Icons.notifications;
    }
  }

  /// 取得通知顏色
  Color _getNotificationColor(String message) {
    if (message.contains('異常') || message.contains('警告')) {
      return Colors.red.shade100;
    } else if (message.contains('提醒')) {
      return Colors.orange.shade100;
    } else if (message.contains('成功') || message.contains('正常')) {
      return Colors.green.shade100;
    } else {
      return Colors.blue.shade50;
    }
  }

  /// 建構通知卡片
  Widget _buildNotificationCard(Map<String, dynamic> notification) {
    final message = notification['message']?.toString() ?? '';
    final createdAt = notification['created_at']?.toString() ?? '';
    final formattedTime = _formatDateTime(createdAt);

    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      elevation: 2,
      color: _getNotificationColor(message),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 通知圖示
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getNotificationIcon(message),
                color: Colors.blue.shade600,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            
            // 通知內容和時間
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formattedTime,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 建構主要內容區域
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text(
              '載入通知歷史...',
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
              onPressed: _fetchNotificationHistory,
              child: const Text('重試'),
            ),
          ],
        ),
      );
    }

    if (_notifications.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.notifications_none,
              size: 64,
              color: Colors.grey,
            ),
            SizedBox(height: 16),
            Text(
              '目前沒有通知歷史紀錄',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '系統通知將會顯示在這裡',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchNotificationHistory,
      child: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        itemCount: _notifications.length,
        itemBuilder: (context, index) {
          return _buildNotificationCard(_notifications[index]);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('通知歷史紀錄'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _fetchNotificationHistory,
              tooltip: '重新整理',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }
}