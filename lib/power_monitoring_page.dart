import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart'; // ✅ 必須導入
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'package:iot_project/config.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:csv/csv.dart';
// import 'package:excel/excel.dart' as excel_pkg; // 移除對 excel_pkg 的引用
import 'package:share_plus/share_plus.dart';

// Token 管理服務
class TokenService {
  static const String _tokenKey = 'auth_token';
  
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }
}

// API 服務
class ApiService {
  static const String baseUrl = Config.baseUrl;
  
  static Future<Map<String, String>> _getHeaders() async {
    final token = await TokenService.getToken();
    return {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<http.Response> get(String endpoint) async {
    final headers = await _getHeaders();
    return await http.get(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
    );
  }
}

// 插座資料模型
class PowerPlugData {
  final String deviceId;
  final String deviceName;
  final bool switchState;
  final double voltage;
  final double current;
  final double power;
  final double totalKwh;
  final String timestamp;

  PowerPlugData({
    required this.deviceId,
    required this.deviceName,
    required this.switchState,
    required this.voltage,
    required this.current,
    required this.power,
    required this.totalKwh,
    required this.timestamp,
  });
}

class PowerMonitoringPage extends StatefulWidget {
  const PowerMonitoringPage({super.key});

  @override
  State<PowerMonitoringPage> createState() => _PowerMonitoringPageState();
}

enum ChartMode { daily, weekly, monthly }

class _PowerMonitoringPageState extends State<PowerMonitoringPage> {
  // 四個插座的即時資料
  final List<PowerPlugData> _plugsData = [];
  
  // 四個插座的設備資訊 (MAC 地址)
  final List<Map<String, String>> _devices = [
    {'id': '3c0b59a0261b', 'name': '1號門口燈泡插座'},
    {'id': '3c0b59a03293', 'name': '冷氣插座'},
    {'id': '80647cafe420', 'name': '2號門口燈泡插座'},
    {'id': '80647cafb7dd', 'name': '風扇插座'},
  ];

  // 當前選中的插座索引
  int _selectedPlugIndex = 0;

  // 圖表資料 - 四個插座的加總累積用電量
  Map<dynamic, double> _chartData = {};

  DateTime _selectedDate = DateTime.now();
  ChartMode _selectedChartMode = ChartMode.daily;
  bool _isLoading = false;
  String? _errorMessage;
  Timer? _refreshTimer;
  bool _isUpdating = false; // ✅ 新增: 防止重複更新


  @override
  void initState() {
    super.initState();
    // ✅ 延遲初始加載,避免在 build 期間更新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchAllPlugsRealtimeData();
      _fetchHistoricalData();
    });
    
    // 每 10 秒自動刷新即時資料
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (!_isUpdating && mounted) {
        _fetchAllPlugsRealtimeData();
      }
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// 安全地將任何類型的值轉換為 double
  double _safeToDouble(dynamic value) {
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

  /// 🔧 修復版本: 獲取所有插座的即時資料
  Future<void> _fetchAllPlugsRealtimeData() async {
    if (_isUpdating || !mounted) return;
    
    _isUpdating = true;
    List<PowerPlugData> newPlugsData = [];
    
    try {
      for (var device in _devices) {
        try {
          final response = await ApiService.get(
            '/api/power-logs/latest/${device['id']}'
          );

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            
            if (data['success'] == true && data['data'] != null) {
              final latestLog = data['data'];
              
              newPlugsData.add(PowerPlugData(
                deviceId: device['id']!,
                deviceName: device['name']!,
                switchState: latestLog['switch_state'] ?? false,
                voltage: _safeToDouble(latestLog['voltage_v']),
                current: _safeToDouble(latestLog['current_a']),
                power: _safeToDouble(latestLog['power_w']),
                totalKwh: _safeToDouble(latestLog['total_kwh']),
                timestamp: latestLog['timestamp'] ?? '',
              ));
            }
          }
        } catch (e) {
          print('獲取設備 ${device['name']} 資料時發生錯誤: $e');
        }
      }
      
      // ✅ 關鍵修復: 使用 SchedulerBinding 延遲 setState
      if (newPlugsData.isNotEmpty && mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _plugsData.clear();
              _plugsData.addAll(newPlugsData);
              _errorMessage = null;
            });
          }
        });
      }
    } finally {
      _isUpdating = false;
    }
  }

    /// 🔧 修復版本: 獲取歷史資料(用於圖表)
  Future<void> _fetchHistoricalData() async {
    if (!mounted) return;
    
    // ✅ 使用 post frame callback 確保在 build 完成後更新
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }
    });

    try {
    // 計算時間範圍
    DateTime endTime = _selectedDate;
    DateTime startTime;
    
    switch (_selectedChartMode) {
      case ChartMode.daily:
        startTime = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 0, 0);
        endTime = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59);
        break;
      case ChartMode.weekly:
        startTime = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
        startTime = DateTime(startTime.year, startTime.month, startTime.day, 0, 0);
        endTime = startTime.add(const Duration(days: 6, hours: 23, minutes: 59));
        break;
      case ChartMode.monthly:
        startTime = DateTime(_selectedDate.year, _selectedDate.month, 1, 0, 0);
        endTime = DateTime(_selectedDate.year, _selectedDate.month + 1, 0, 23, 59);
        break;
    }

    final startTimeStr = startTime.toIso8601String();
    final endTimeStr = endTime.toIso8601String();
    
    // ✅ 添加這個調試輸出
    print('🔍 查詢時間範圍: $startTimeStr 到 $endTimeStr');
    
    // 獲取所有四個插座的歷史資料
    List<List<dynamic>> allDevicesLogs = [];
    
    for (var device in _devices) {
      try {
        final response = await ApiService.get(
          '/api/power-logs?device_id=${device['id']}&start_time=$startTimeStr&end_time=$endTimeStr'
        );


        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] == true && data['data'] != null && data['data'].isNotEmpty) {
            // ✅ 添加這個調試輸出
            print('📦 ${device['name']} 返回 ${data['data'].length} 筆資料');
            
            // ✅ 打印前3筆數據的時間戳
            for (int i = 0; i < (data['data'].length > 3 ? 3 : data['data'].length); i++) {
              print('   ├─ [$i] ${data['data'][i]['timestamp']}');
            }
            
            allDevicesLogs.add(data['data']);
          } else {
            print('⚠️ ${device['name']} 無數據');
          }
        }
      } catch (e) {
        print('❌ 獲取 ${device['name']} 歷史資料失敗: $e');
      }
    }

    if (allDevicesLogs.isNotEmpty) {
      _processHistoricalDataSum(allDevicesLogs);
    } else {
        // ✅ 使用延遲更新
        if (mounted) {
          SchedulerBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _chartData = {};
                _errorMessage = '此時間範圍內無資料';
                _isLoading = false;
              });
            }
          });
        }
      }
    } catch (e) {
      print('獲取歷史資料錯誤: $e');
      if (mounted) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _errorMessage = '網路連線失敗: $e';
              _isLoading = false;
            });
          }
        });
      }
    }
  }

  /// ✅ 修正版本: 直接匯出 CSV (移除選擇對話框)
  Future<void> _exportToCSV() async {
    try {
      print('📊 開始匯出 CSV...');
      print('   _chartData.isEmpty: ${_chartData.isEmpty}');
      print('   _chartData.length: ${_chartData.length}');
      
      if (_chartData.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ 無數據可匯出,請先選擇日期並載入數據')),
        );
        return;
      }

      // ✅ 手動構建 CSV 內容 (不使用 ListToCsvConverter)
      StringBuffer csvContent = StringBuffer();
      
      // 標題區
      String modeText = _getChartModeText();
      String dateRange = _getExportDateRange();
      
      csvContent.writeln('用電報表 - $modeText');
      csvContent.writeln('統計期間,$dateRange');
      csvContent.writeln('匯出時間,${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
      csvContent.writeln(); // 空行
      csvContent.writeln('${_getTableHeaderText()},區間用電量 (Wh)');
      
      // 數據行
      final sortedKeys = _chartData.keys.toList()
        ..sort((a, b) => (_safeToDouble(a) as Comparable).compareTo(_safeToDouble(b)));
      
      print('   排序後的 keys: $sortedKeys');
      
      for (var key in sortedKeys) {
        String label = _formatLabelForExport(key);
        String value = _chartData[key]!.toStringAsFixed(1);
        csvContent.writeln('$label,$value');
        print('   寫入: $label,$value');
      }
      
      // 統計資訊
      double totalEnergy = _chartData.values.fold(0.0, (sum, val) => sum + val);
      csvContent.writeln();
      csvContent.writeln('總用電量,${totalEnergy.toStringAsFixed(1)} Wh');
      csvContent.writeln('平均用電量,${(totalEnergy / _chartData.length).toStringAsFixed(1)} Wh');
      
      print('✅ CSV 內容構建完成,長度: ${csvContent.length}');
      
      // ✅ 添加 UTF-8 BOM 並寫入檔案
      List<int> bytes = [0xEF, 0xBB, 0xBF]; // UTF-8 BOM
      bytes.addAll(utf8.encode(csvContent.toString()));
      
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final filename = 'power_report_${_selectedChartMode.name}_$timestamp.csv';
      final path = '${directory.path}/$filename';
      
      print('📁 檔案路徑: $path');
      
      final file = File(path);
      await file.writeAsBytes(bytes);
      
      // 驗證檔案
      final fileExists = await file.exists();
      final fileSize = await file.length();
      print('   檔案存在: $fileExists');
      print('   檔案大小: $fileSize bytes');
      
      if (fileSize == 0) {
        throw Exception('檔案大小為 0 bytes');
      }
      
      await Share.shareXFiles([XFile(path)], text: '用電報表');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ CSV 已匯出: $filename\n大小: $fileSize bytes'),
          duration: const Duration(seconds: 3),
        ),
      );
      
    } catch (e, stackTrace) {
      print('❌ 匯出 CSV 失敗: $e');
      print('   Stack trace: $stackTrace');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ 匯出失敗: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // 移除 _exportToExcel

  /// ✅ 輔助函數:取得匯出用的日期範圍文字
  String _getExportDateRange() {
    DateTime startTime;
    DateTime endTime;
    
    switch (_selectedChartMode) {
      case ChartMode.daily:
        startTime = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
        endTime = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59);
        return DateFormat('yyyy-MM-dd').format(startTime);
        
      case ChartMode.weekly:
        startTime = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
        endTime = startTime.add(const Duration(days: 6));
        return '${DateFormat('yyyy-MM-dd').format(startTime)} ~ ${DateFormat('yyyy-MM-dd').format(endTime)}';
        
      case ChartMode.monthly:
        startTime = DateTime(_selectedDate.year, _selectedDate.month, 1);
        endTime = DateTime(_selectedDate.year, _selectedDate.month + 1, 0);
        return DateFormat('yyyy-MM').format(startTime);
    }
  }

  /// ✅ 輔助函數:格式化標籤用於匯出
  String _formatLabelForExport(dynamic key) {
    try {
      if (_selectedChartMode == ChartMode.daily) {
        int hour = _safeToDouble(key).toInt();
        int nextHour = (hour + 1) % 24;
        return '$hour:00-$nextHour:00';
        
      } else if (_selectedChartMode == ChartMode.weekly) {
        List<String> weekdays = ['週一', '週二', '週三', '週四', '週五', '週六', '週日'];
        int index = _safeToDouble(key).toInt();
        
        if (index >= 1 && index <= 7) {
          // 計算實際日期
          DateTime weekStart = _selectedDate.subtract(Duration(days: _selectedDate.weekday - 1));
          DateTime actualDate = weekStart.add(Duration(days: index - 1));
          return '${weekdays[index - 1]} (${DateFormat('MM/dd').format(actualDate)})';
        }
        return key.toString();
        
      } else {
        int day = _safeToDouble(key).toInt();
        DateTime actualDate = DateTime(_selectedDate.year, _selectedDate.month, day);
        return '${day}日 (${DateFormat('MM/dd').format(actualDate)})';
      }
    } catch (e) {
      print('格式化標籤時發生錯誤: $e');
      return key.toString();
    }
  }
  
  // 移除 _showExportDialog

/// 🔧 修復版本: 處理歷史資料
void _processHistoricalDataSum(List<List<dynamic>> allDevicesLogs) {
  Map<dynamic, double> intervalConsumption = {};
  
  // ✅ 添加調試計數器
  int totalRecordsProcessed = 0;
  Map<int, int> dayRecordCount = {};

  for (var logs in allDevicesLogs) {
    if (logs.isEmpty) continue;

    logs.sort((a, b) {
      try {
        final timeA = DateTime.parse(a['timestamp']);
        final timeB = DateTime.parse(b['timestamp']);
        return timeA.compareTo(timeB);
      } catch (e) {
        return 0;
      }
    });

    Map<dynamic, List<Map<String, dynamic>>> groupedData = {};

    for (var log in logs) {
      try {
        final timestampUtc = DateTime.parse(log['timestamp']);
        final timestamp = timestampUtc.toLocal();
        final power = _safeToDouble(log['power_w']);
        
        totalRecordsProcessed++;
        
        dynamic key;
        
        switch (_selectedChartMode) {
          case ChartMode.daily:
            key = timestamp.hour;
            break;
          case ChartMode.weekly:
            key = timestamp.weekday;
            break;
          case ChartMode.monthly:
            key = timestamp.day;
            
            // ✅ 統計每天的記錄數
            dayRecordCount[timestamp.day] = (dayRecordCount[timestamp.day] ?? 0) + 1;
            
            // ✅ 打印幾個樣本
            if (totalRecordsProcessed <= 5) {
              print('📅 處理記錄: ${timestamp.toString()} -> day=$key, power=$power');
            }
            break;
        }

        if (!groupedData.containsKey(key)) {
          groupedData[key] = [];
        }
        
        groupedData[key]!.add({
          'timestamp': timestamp,
          'power': power,
        });
        
      } catch (e) {
        print('❌ 處理記錄時發生錯誤: $e');
      }
    }

    // 計算能量
    groupedData.forEach((key, records) {
      if (records.isEmpty) return;
      
      records.sort((a, b) => a['timestamp'].compareTo(b['timestamp']));
      
      double totalEnergy = 0.0;
      
      for (int i = 0; i < records.length - 1; i++) {
        DateTime t1 = records[i]['timestamp'];
        DateTime t2 = records[i + 1]['timestamp'];
        double p1 = records[i]['power'];
        double p2 = records[i + 1]['power'];
        
        double timeDiffHours = t2.difference(t1).inSeconds / 3600.0;
        
        if (timeDiffHours > 0 && timeDiffHours < 1.0) {
          double energy = (p1 + p2) / 2 * timeDiffHours;
          totalEnergy += energy;
        }
      }
      
      if (!intervalConsumption.containsKey(key)) {
        intervalConsumption[key] = 0.0;
      }
      intervalConsumption[key] = intervalConsumption[key]! + totalEnergy;
    });
  }

  // ✅ 打印統計信息
  print('📊 ========== 處理完成 ==========');
  print('   總共處理: $totalRecordsProcessed 筆記錄');
  print('   每日記錄數: ${dayRecordCount.keys.toList()..sort()}');
  dayRecordCount.forEach((day, count) {
    print('      $day日: $count 筆');
  });
  print('   最終結果: ${intervalConsumption.keys.toList()..sort()}');
  print('================================');

  if (mounted) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _chartData = intervalConsumption;
          if (_chartData.isEmpty) {
            _errorMessage = '此時間範圍內無資料';
          } else {
            _errorMessage = null;
          }
          _isLoading = false;
        });
      }
    });
  }
}

  /// 🔧 修復版本: 選擇日期
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    
    if (picked != null && picked != _selectedDate && mounted) {
      // ✅ 延遲更新
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selectedDate = picked;
          });
          _fetchHistoricalData();
        }
      });
    }
  }

  /// 🔧 修復版本: 重新整理資料
  Future<void> _refreshData() async {
    if (_isUpdating || !mounted) return;
    
    await Future.wait([
      _fetchAllPlugsRealtimeData(),
      _fetchHistoricalData(),
    ]);
  }

  // ✅ 修復 RefreshIndicator 的問題
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshData,
        // ✅ 添加 notificationPredicate 避免觸發錯誤
        notificationPredicate: (notification) {
          return notification.depth == 0;
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
            
              Container(
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Row(
                  // ✅ 遍歷 _devices 列表來獲取名稱
                  children: List.generate(_devices.length, (index) {
                    final isSelected = _selectedPlugIndex == index;
                    final deviceName = _devices[index]['name'] ?? '插座 ${index + 1}'; // 獲取設備名稱
                    
                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (mounted && _selectedPlugIndex != index) {
                            setState(() {
                              _selectedPlugIndex = index;
                            });
                          }
                        },
                        child: Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white : Colors.transparent,
                            borderRadius: BorderRadius.circular(21),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: Colors.grey.withOpacity(0.3),
                                      spreadRadius: 1,
                                      blurRadius: 3,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Center(
                            // ✅ 顯示設備名稱，並調整字體大小以適應
                            child: Text(
                              deviceName, // <--- 修正後的關鍵點
                              textAlign: TextAlign.center,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12, // 為了讓較長的名稱能顯示，將字體縮小
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                color: isSelected ? Theme.of(context).primaryColor : Colors.grey[600],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ),
              const SizedBox(height: 16),

              // 插座卡片 - 顯示當前選中的插座
              if (_plugsData.isEmpty)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32.0),
                    child: Text('暫無設備資料', style: TextStyle(fontSize: 16, color: Colors.grey)),
                  ),
                )
              else if (_selectedPlugIndex < _plugsData.length)
                _buildPlugCard(_plugsData[_selectedPlugIndex]),

              const SizedBox(height: 24),

              // 趨勢圖標題與控制項
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '用電趨勢圖',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  Row(
                    children: [
                      // 日期選擇按鈕
                      GestureDetector(
                        onTap: () => _selectDate(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            DateFormat('MMM dd, yyyy').format(_selectedDate),
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),

                      // 模式選擇
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: PopupMenuButton<ChartMode>(
                          icon: const Icon(Icons.date_range, color: Colors.grey),
                          onSelected: (ChartMode result) {
                            setState(() {
                              _selectedChartMode = result;
                            });
                            _fetchHistoricalData();
                          },
                          itemBuilder: (BuildContext context) => <PopupMenuEntry<ChartMode>>[
                            const PopupMenuItem<ChartMode>(
                              value: ChartMode.daily,
                              child: Text('每日'),
                            ),
                            const PopupMenuItem<ChartMode>(
                              value: ChartMode.weekly,
                              child: Text('每週'),
                            ),
                            const PopupMenuItem<ChartMode>(
                              value: ChartMode.monthly,
                              child: Text('每月'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 趨勢圖表
              Container(
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
                  children: [
                    Text(
                      '區間用電量 (Wh) - ${_getChartModeText()}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 250,
                      child: _chartData.isEmpty
                          ? const Center(child: Text('此時間範圍內無資料'))
                          : BarChart(_buildBarChartData()),
                    ),
                    const SizedBox(height: 20),
                    // 詳細數據表格
                    _buildPowerDetailsTable(),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // 匯出報表按鈕 (直接匯出 CSV)
              Center(
                child: ElevatedButton.icon(
                  onPressed: _exportToCSV, // 直接調用 CSV 匯出
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.download, size: 24),
                  label: const Text('匯出報表 (CSV)', style: TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================
// 🔧 額外建議的改進 (可選)
// ============================================

// 建議 1: 在錯誤訊息區塊添加安全更新
Widget buildErrorMessage() {
  if (_errorMessage == null) return const SizedBox.shrink();
  
  return Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.red[100],
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.red),
    ),
    child: Row(
      children: [
        const Icon(Icons.error, color: Colors.red),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _errorMessage!,
            style: TextStyle(color: Colors.red[800]),
          ),
        ),
        TextButton(
          onPressed: () {
            // ✅ 添加安全檢查
            if (mounted && !_isUpdating) {
              _refreshData();
            }
          },
          child: const Text('重試'),
        ),
      ],
    ),
  );
}

// 建議 2: 添加 loading 狀態的安全顯示
Widget buildLoadingIndicator() {
  if (!_isLoading) return const SizedBox.shrink();
  
  return const Center(
    child: Padding(
      padding: EdgeInsets.all(20.0),
      child: CircularProgressIndicator(),
    ),
  );
}

  /// 構建插座卡片 - 精簡橫式版本
Widget _buildPlugCard(PowerPlugData plug) {
  final bool isOn = plug.switchState;
  final Color statusColor = isOn ? Colors.green : Colors.grey;
  
  return Container(
    padding: const EdgeInsets.all(16.0),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: statusColor.withOpacity(0.2), width: 1.5),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withOpacity(0.15),
          spreadRadius: 1,
          blurRadius: 4,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 設備名稱與狀態
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.power, color: statusColor, size: 24),
                const SizedBox(width: 8),
                Text(
                  plug.deviceName,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
          
          // 三個主要數據 - 橫式排列
          Row(
            children: [
              Expanded(
                child: _buildCompactDataItem(
                  icon: Icons.flash_on,
                  label: '功率',
                  value: '${plug.power.toStringAsFixed(1)} W',
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCompactDataItem(
                  icon: Icons.electric_bolt,
                  label: '電壓',
                  value: '${plug.voltage.toStringAsFixed(1)} V',
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildCompactDataItem(
                  icon: Icons.electrical_services,
                  label: '電流',
                  value: '${plug.current.toStringAsFixed(3)} A',
                  color: Colors.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // 更新時間 - 置中顯示
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.access_time, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Text(
                '更新: ${_formatTimestamp(plug.timestamp)}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
}

  /// 構建精簡數據項目
  Widget _buildCompactDataItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(10.0),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color.withOpacity(0.8),
              fontWeight: FontWeight.w500,
            ),
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
      ),
    );
  }

  /// 構建詳細數據表格 - 顯示四插座加總累積用電量(移除成長率)
  Widget _buildPowerDetailsTable() {
    if (_chartData.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('無可用數據', style: TextStyle(fontSize: 16, color: Colors.grey)),
        ),
      );
    }

    final List<dynamic> sortedKeys = _chartData.keys.toList()
      ..sort((a, b) => (_safeToDouble(a) as Comparable).compareTo(_safeToDouble(b)));

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10.0),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: Center(
                  child: Text(
                    _getTableHeaderText(),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              const Expanded(
                child: Center(
                  child: Text(
                    '區間用電量 (Wh)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // 數據行
        ...sortedKeys.map((key) {
          try {
            final double energy = _safeToDouble(_chartData[key]);
            return _buildTableRow(key, energy);
          } catch (e) {
            print('構建表格行時發生錯誤: $e');
            return _buildTableRow(key, 0.0);
          }
        }).toList(),
      ],
    );
  }

  /// 🔧 修復:根據模式獲取表格標題文字
  String _getTableHeaderText() {
    switch (_selectedChartMode) {
      case ChartMode.daily:
        return '時間';
      case ChartMode.weekly:
        return '星期'; // ✅ 週模式顯示 "星期"
      case ChartMode.monthly:
        return '日期'; // ✅ 月模式顯示 "日期"
    }
  }


  /// 🔧 修復:表格行(移除成長率)
  Widget _buildTableRow(dynamic label, double energy) {
    String formattedLabel;
    try {
      if (_selectedChartMode == ChartMode.daily) {
        // 日模式:顯示時間區間 (如 22-23)
        int hour = _safeToDouble(label).toInt();
        int nextHour = (hour + 1) % 24;
        formattedLabel = '$hour-$nextHour';
        
      } else if (_selectedChartMode == ChartMode.weekly) {
        // ✅ 修復:週模式顯示星期幾
        List<String> weekdays = ['一', '二', '三', '四', '五', '六', '日'];
        int index = _safeToDouble(label).toInt();
        
        if (index >= 1 && index <= 7) {
          formattedLabel = '週${weekdays[index - 1]}'; // ✅ "週一" 到 "週日"
        } else {
          formattedLabel = label.toString();
        }
        
      } else {
        // ✅ 修復:月模式顯示日期
        int day = _safeToDouble(label).toInt();
        formattedLabel = '$day日'; // ✅ "1日" 到 "31日"
      }
    } catch (e) {
      print('格式化標籤時發生錯誤: $e');
      formattedLabel = label.toString();
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        children: [
          Expanded(
            child: Center(
              child: Text(
                formattedLabel,
                style: const TextStyle(color: Colors.black, fontSize: 13),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: Text(
                energy.toStringAsFixed(1),
                style: const TextStyle(color: Colors.black, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 構建長條圖資料
  BarChartData _buildBarChartData() {
    if (_chartData.isEmpty) {
      return BarChartData(
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        barGroups: [],
      );
    }

    final List<MapEntry<dynamic, double>> sortedEntries = _chartData.entries.toList()
      ..sort((a, b) => _safeToDouble(a.key).compareTo(_safeToDouble(b.key)));

    double maxY = sortedEntries.map((e) => e.value).reduce((a, b) => a > b ? a : b) + 10;
    if (maxY == 10) maxY = 100;

    final barGroups = sortedEntries.asMap().entries.map((entry) {
      int index = entry.key;
      double value = entry.value.value;
      
      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: value,
            color: Theme.of(context).primaryColor,
            width: 16,
            borderRadius: BorderRadius.circular(4),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: maxY,
              color: Colors.grey.withOpacity(0.1),
            ),
          ),
        ],
      );
    }).toList();

    return BarChartData(
      maxY: maxY,
      minY: 0,
      barGroups: barGroups,
      gridData: FlGridData(
        show: true,
        drawHorizontalLine: true,
        drawVerticalLine: false,
        horizontalInterval: maxY / 5,
        getDrawingHorizontalLine: (value) {
          return const FlLine(
            color: Colors.grey,
            strokeWidth: 0.5,
          );
        },
      ),
      titlesData: FlTitlesData(
        show: true,
        rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 30,
            getTitlesWidget: (value, meta) {
              if (value.toInt() >= sortedEntries.length) return const SizedBox.shrink();
              
              final key = sortedEntries[value.toInt()].key;
              return SideTitleWidget(
                axisSide: meta.axisSide,
                space: 8.0,
                child: Text(
                  _getBottomTitleText(_safeToDouble(key)),
                  style: const TextStyle(fontSize: 10, color: Colors.black),
                ),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 45,
            interval: maxY / 5,
            getTitlesWidget: (value, meta) {
              return Text(
                value.toInt().toString(),
                style: const TextStyle(fontSize: 10, color: Colors.black),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(
        show: true,
        border: Border.all(color: const Color(0xff37434d), width: 1),
      ),
      barTouchData: BarTouchData(
        touchTooltipData: BarTouchTooltipData(
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            final key = sortedEntries[group.x.toInt()].key;
            return BarTooltipItem(
              '${_getBottomTitleText(_safeToDouble(key))}\n${rod.toY.toStringAsFixed(1)} Wh',
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            );
          },
        ),
      ),
    );
  }

  /// 根據選定的模式獲取 X 軸標籤間隔
  double _getBottomTitleInterval() {
    switch (_selectedChartMode) {
      case ChartMode.daily:
        return 3;
      case ChartMode.weekly:
        return 1;
      case ChartMode.monthly:
        return 5;
    }
  }

  /// 根據選定的模式獲取 X 軸網格間隔
  double _getVerticalInterval() {
    switch (_selectedChartMode) {
      case ChartMode.daily:
        return 1;
      case ChartMode.weekly:
        return 1;
      case ChartMode.monthly:
        return 1;
    }
  }

  /// 🔧 修復:根據模式獲得 X 軸標籤文字
  String _getBottomTitleText(double value) {
    try {
      switch (_selectedChartMode) {
        case ChartMode.daily:
          // 日模式:顯示時間區間 (如 22-23)
          int hour = value.toInt();
          int nextHour = (hour + 1) % 24;
          return '$hour-$nextHour';
          
        case ChartMode.weekly:
          // ✅ 修復:週模式顯示星期幾 (1=週一, 7=週日)
          List<String> weekdays = ['一', '二', '三', '四', '五', '六', '日'];
          int index = value.toInt();
          
          // weekday 範圍是 1-7 (週一到週日)
          if (index >= 1 && index <= 7) {
            return '週${weekdays[index - 1]}'; // ✅ 顯示 "週一", "週二" 等
          }
          return '';
          
        case ChartMode.monthly:
          // ✅ 修復:月模式顯示日期 (1-31)
          int day = value.toInt();
          return '$day日'; // ✅ 顯示 "1日", "2日" 等
      }
    } catch (e) {
      print('格式化標籤時發生錯誤: $e');
      return '';
    }
  }

  /// 🔧 修復:獲取圖表模式文字
  String _getChartModeText() {
    switch (_selectedChartMode) {
      case ChartMode.daily:
        return '每日';
      case ChartMode.weekly:
        return '每週'; // ✅ 週模式
      case ChartMode.monthly:
        return '每月'; // ✅ 月模式
    }
  }

  /// 格式化時間戳記
  String _formatTimestamp(String timestamp) {
    try {
      final dt = DateTime.parse(timestamp).toLocal();
      return DateFormat('HH:mm:ss').format(dt);
    } catch (e) {
      return timestamp;
    }
  }
}