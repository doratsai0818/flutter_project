import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:iot_project/config.dart';

class NotificationHistoryPage extends StatefulWidget {
  const NotificationHistoryPage({super.key});

  @override
  State<NotificationHistoryPage> createState() => _NotificationHistoryPageState();
}

class _NotificationHistoryPageState extends State<NotificationHistoryPage> {
  final String _baseUrl = Config.apiUrl;

  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;
  String _errorMessage = '';
  
  // 📊 分頁相關
  int _currentPage = 1;
  int _totalPages = 1;
  int _totalCount = 0;
  final int _pageSize = 10;
  bool _hasNextPage = false;
  bool _hasPreviousPage = false;
  
  // 📅 日期篩選
  DateTime? _startDate;
  DateTime? _endDate;

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
      'ngrok-skip-browser-warning': 'true',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// 從後端 API 獲取通知歷史記錄 (支援分頁)
  Future<void> _fetchNotificationHistory({int page = 1}) async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final headers = await _getAuthHeaders();
      
      // 構建查詢參數
      final queryParams = {
        'page': page.toString(),
        'limit': _pageSize.toString(),
        if (_startDate != null) 'startDate': _startDate!.toIso8601String(),
        if (_endDate != null) 'endDate': _endDate!.toIso8601String(),
      };
      
      final uri = Uri.parse('$_baseUrl/notifications/history').replace(queryParameters: queryParams);
      
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final jsonData = json.decode(response.body);
        
        setState(() {
          _notifications = (jsonData['data'] as List)
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
          
          // 更新分頁資訊
          final pagination = jsonData['pagination'];
          _currentPage = pagination['currentPage'];
          _totalPages = pagination['totalPages'];
          _totalCount = pagination['totalCount'];
          _hasNextPage = pagination['hasNextPage'];
          _hasPreviousPage = pagination['hasPreviousPage'];
          
          _isLoading = false;
        });
        
        print('✅ 成功獲取第 $_currentPage 頁 (共 $_totalPages 頁)');
        
      } else if (response.statusCode == 401) {
        setState(() {
          _errorMessage = '認證失敗,請重新登入';
          _isLoading = false;
        });
        _handleAuthError();
        
      } else if (response.statusCode == 404) {
        setState(() {
          _notifications = [];
          _isLoading = false;
        });
        
      } else {
        final errorBody = json.decode(response.body);
        setState(() {
          _errorMessage = errorBody['message'] ?? '載入失敗: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } on SocketException {
      setState(() {
        _errorMessage = '無法連接到伺服器,請檢查網路連線';
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = '發生未知錯誤: $e';
        _isLoading = false;
      });
    }
  }

  /// 處理認證錯誤
  void _handleAuthError() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('認證錯誤'),
          content: const Text('您的登入狀態已過期,請重新登入。'),
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

  /// 📅 顯示日期選擇器
  Future<void> _showDatePicker({required bool isStartDate}) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      locale: const Locale('zh', 'TW'),
    );
    
    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
      });
      
      // 重新載入第1頁
      _fetchNotificationHistory(page: 1);
    }
  }

  /// 🔄 清除日期篩選
  void _clearDateFilter() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
    _fetchNotificationHistory(page: 1);
  }

  /// ⏰ 格式化時間顯示 (智能顯示)
  String _formatDateTime(String dateTimeStr) {
    try {
      final dateTime = DateTime.parse(dateTimeStr).toLocal();
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      // 1小時內 → "N分鐘前"
      if (difference.inMinutes < 60) {
        if (difference.inMinutes < 1) {
          return '剛剛';
        }
        return '${difference.inMinutes}分鐘前';
      }
      
      // 1天內 → "N小時前"
      else if (difference.inHours < 24) {
        return '${difference.inHours}小時前';
      }
      
      // 3天內 → "N天前"
      else if (difference.inDays <= 3) {
        return '${difference.inDays}天前';
      }
      
      // 超過3天 → "年/月/日"
      else {
        return '${dateTime.year}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.day.toString().padLeft(2, '0')}';
      }
      
    } catch (e) {
      return dateTimeStr;
    }
  }

  /// 📝 優化離線通知顯示
  String _optimizeMessage(String message) {
    // 移除 "已離線超過 X 分鐘" → 只顯示 "已離線"
    if (message.contains('已離線超過')) {
      final deviceName = message.split('已離線')[0].trim();
      return '$deviceName已離線';
    }
    return message;
  }

  /// 🎨 取得通知圖示
  IconData _getNotificationIcon(String message) {
    if (message.contains('恢復') || message.contains('正常')) {
      return Icons.check_circle;
    } else if (message.contains('用電異常') || message.contains('功耗')) {
      return Icons.power_off;
    } else if (message.contains('溫度') || message.contains('冷氣')) {
      return Icons.thermostat;
    } else if (message.contains('燈光') || message.contains('亮度')) {
      return Icons.lightbulb;
    } else if (message.contains('感測器') || message.contains('離線')) {
      return Icons.sensors_off;
    } else if (message.contains('系統模式')) {
      return Icons.settings;
    } else {
      return Icons.notifications;
    }
  }

  /// 🎨 取得通知顏色
  Color _getNotificationColor(String message) {
    if (message.contains('恢復') || message.contains('正常')) {
      return Colors.green.shade100;
    } else if (message.contains('異常') || message.contains('警告') || message.contains('嚴重')) {
      return Colors.red.shade100;
    } else if (message.contains('提醒')) {
      return Colors.orange.shade100;
    } else if (message.contains('成功')) {
      return Colors.green.shade100;
    } else {
      return Colors.blue.shade50;
    }
  }

  /// 🎨 建構通知卡片
  Widget _buildNotificationCard(Map<String, dynamic> notification) {
    final rawMessage = notification['message']?.toString() ?? '';
    final message = _optimizeMessage(rawMessage);  // ✅ 優化訊息顯示
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
                color: message.contains('恢復') ? Colors.green : Colors.blue.shade600,
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

  /// 📄 建構分頁控制列
  Widget _buildPaginationBar() {
    if (_totalPages <= 1) return const SizedBox.shrink();
    
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 上一頁按鈕
          IconButton(
            icon: const Icon(Icons.chevron_left),
            onPressed: _hasPreviousPage && !_isLoading
                ? () => _fetchNotificationHistory(page: _currentPage - 1)
                : null,
          ),
          
          // 頁數資訊
          Text(
            '第 $_currentPage / $_totalPages 頁 (共 $_totalCount 則)',
            style: const TextStyle(fontSize: 14),
          ),
          
          // 下一頁按鈕
          IconButton(
            icon: const Icon(Icons.chevron_right),
            onPressed: _hasNextPage && !_isLoading
                ? () => _fetchNotificationHistory(page: _currentPage + 1)
                : null,
          ),
        ],
      ),
    );
  }

  /// 🎯 建構主要內容區域
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
              onPressed: () => _fetchNotificationHistory(page: 1),
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
              '目前沒有通知歷史記錄',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              '系統通知會顯示在這裡',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _fetchNotificationHistory(page: _currentPage),
            child: ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: _notifications.length,
              itemBuilder: (context, index) {
                return _buildNotificationCard(_notifications[index]);
              },
            ),
          ),
        ),
        _buildPaginationBar(),  // ✅ 分頁控制列
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('通知歷史記錄'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 1,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // 📅 日期篩選按鈕
          IconButton(
            icon: Icon(
              Icons.filter_list,
              color: (_startDate != null || _endDate != null) ? Colors.blue : null,
            ),
            onPressed: _showFilterDialog,
            tooltip: '日期篩選',
          ),
          if (!_isLoading)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _fetchNotificationHistory(page: _currentPage),
              tooltip: '重新整理',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  /// 📅 顯示篩選對話框
  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('日期篩選'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('開始日期'),
              subtitle: Text(_startDate != null 
                  ? '${_startDate!.year}/${_startDate!.month}/${_startDate!.day}'
                  : '未設定'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () {
                Navigator.pop(context);
                _showDatePicker(isStartDate: true);
              },
            ),
            ListTile(
              title: const Text('結束日期'),
              subtitle: Text(_endDate != null 
                  ? '${_endDate!.year}/${_endDate!.month}/${_endDate!.day}'
                  : '未設定'),
              trailing: const Icon(Icons.calendar_today),
              onTap: () {
                Navigator.pop(context);
                _showDatePicker(isStartDate: false);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _clearDateFilter();
            },
            child: const Text('清除篩選'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }
}