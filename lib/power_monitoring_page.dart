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
import 'package:excel/excel.dart' as excel_pkg;
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
    {'id': '3c0b59a0261b', 'name': '1號插座'},
    {'id': '3c0b59a03293', 'name': '2號插座'},
    {'id': '80647cafe420', 'name': '3號插座'},
    {'id': '80647cafb7dd', 'name': '4號插座'},
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
      
      // 獲取所有四個插座的歷史資料
      List<List<dynamic>> allDevicesLogs = [];
      
      for (var device in _devices) {
        try {
          final response = await ApiService.get(
            '/api/power-logs?device_id=${device['id']}&start_time=$startTimeStr&end_time=$endTimeStr&limit=1000'
          );

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data['success'] == true && data['data'] != null && data['data'].isNotEmpty) {
              allDevicesLogs.add(data['data']);
            }
          }
        } catch (e) {
          print('獲取 ${device['name']} 歷史資料失敗: $e');
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

  // 🔧 CSV 導出時也需要修復標籤格式
  Future<void> _exportToCSV() async {
    try {
      if (_chartData.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無數據可匯出')),
        );
        return;
      }

      List<List<dynamic>> rows = [];
      
      // 標題行
      rows.add([_getTableHeaderText(), '區間用電量 (Wh)']);
      
      // 數據行
      final sortedKeys = _chartData.keys.toList()
        ..sort((a, b) => (_safeToDouble(a) as Comparable).compareTo(_safeToDouble(b)));
      
      for (var key in sortedKeys) {
        String label;
        if (_selectedChartMode == ChartMode.daily) {
          int hour = _safeToDouble(key).toInt();
          int nextHour = (hour + 1) % 24;
          label = '$hour-$nextHour';
          
        } else if (_selectedChartMode == ChartMode.weekly) {
          // ✅ 修復:週模式 CSV 標籤
          List<String> weekdays = ['一', '二', '三', '四', '五', '六', '日'];
          int index = _safeToDouble(key).toInt();
          label = (index >= 1 && index <= 7) ? '週${weekdays[index - 1]}' : key.toString();
          
        } else {
          // ✅ 修復:月模式 CSV 標籤
          int day = _safeToDouble(key).toInt();
          label = '$day日';
        }
        
        rows.add([label, _chartData[key]!.toStringAsFixed(1)]);
      }
      
      String csv = const ListToCsvConverter().convert(rows);
      
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final path = '${directory.path}/power_report_$timestamp.csv';
      
      final file = File(path);
      await file.writeAsString(csv);
      
      await Share.shareXFiles([XFile(path)], text: '用電報表');
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('CSV 已匯出: $path')),
      );
      
    } catch (e) {
      print('匯出 CSV 失敗: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('匯出失敗: $e')),
      );
    }
  }

  // 🔧 Excel 導出時也需要修復標籤格式
  Future<void> _exportToExcel() async {
    try {
      if (_chartData.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無數據可匯出')),
        );
        return;
      }

      var excelFile = excel_pkg.Excel.createExcel();
      
      if (excelFile.tables.containsKey('Sheet1')) {
        excelFile.delete('Sheet1');
      }
      
      excelFile.copy('Sheet1', '用電報表');
      excel_pkg.Sheet sheet = excelFile['用電報表'];
      
      // 標題行
      sheet.cell(excel_pkg.CellIndex.indexByString('A1')).value = 
          excel_pkg.TextCellValue(_getTableHeaderText());
      sheet.cell(excel_pkg.CellIndex.indexByString('B1')).value = 
          excel_pkg.TextCellValue('區間用電量 (Wh)');
      
      // 數據行
      final sortedKeys = _chartData.keys.toList()
        ..sort((a, b) => (_safeToDouble(a) as Comparable).compareTo(_safeToDouble(b)));
      
      int rowIndex = 2;
      for (var key in sortedKeys) {
        String label;
        if (_selectedChartMode == ChartMode.daily) {
          int hour = _safeToDouble(key).toInt();
          int nextHour = (hour + 1) % 24;
          label = '$hour-$nextHour';
          
        } else if (_selectedChartMode == ChartMode.weekly) {
          // ✅ 修復:週模式 Excel 標籤
          List<String> weekdays = ['一', '二', '三', '四', '五', '六', '日'];
          int index = _safeToDouble(key).toInt();
          label = (index >= 1 && index <= 7) ? '週${weekdays[index - 1]}' : key.toString();
          
        } else {
          // ✅ 修復:月模式 Excel 標籤
          int day = _safeToDouble(key).toInt();
          label = '$day日';
        }
        
        sheet.cell(excel_pkg.CellIndex.indexByString('A$rowIndex')).value = 
            excel_pkg.TextCellValue(label);
        sheet.cell(excel_pkg.CellIndex.indexByString('B$rowIndex')).value = 
            excel_pkg.TextCellValue(_chartData[key]!.toStringAsFixed(1));
        rowIndex++;
      }
      
      final directory = await getApplicationDocumentsDirectory();
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final path = '${directory.path}/power_report_$timestamp.xlsx';
      
      final file = File(path);
      var bytes = excelFile.encode();
      if (bytes != null) {
        await file.writeAsBytes(bytes);
        await Share.shareXFiles([XFile(path)], text: '用電報表');
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Excel 已匯出: $path')),
        );
      }
      
    } catch (e) {
      print('匯出 Excel 失敗: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('匯出失敗: $e')),
      );
    }
  }

    /// 顯示匯出格式選擇對話框
    void _showExportDialog() {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('選擇匯出格式'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.description, color: Colors.green),
                  title: const Text('CSV檔'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _exportToCSV();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.table_chart, color: Colors.blue),
                  title: const Text('Excel檔'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _exportToExcel();
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ],
          );
        },
      );
    }

/// 🔧 修復版本: 處理歷史資料
  void _processHistoricalDataSum(List<List<dynamic>> allDevicesLogs) {
    Map<dynamic, double> intervalConsumption = {};

    for (var logs in allDevicesLogs) {
      if (logs.isEmpty) continue;

      Map<dynamic, List<Map<String, dynamic>>> groupedData = {};

      for (var log in logs) {
        try {
          final timestampUtc = DateTime.parse(log['timestamp']);
          final timestamp = timestampUtc.toLocal();
          final power = _safeToDouble(log['power_w']);
          
          dynamic key;
          
          switch (_selectedChartMode) {
            case ChartMode.daily:
              key = timestamp.hour;
              break;
            case ChartMode.weekly:
              key = timestamp.weekday; // 1-7 (週一到週日)
              break;
            case ChartMode.monthly:
              key = timestamp.day; // 1-31
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
          print('處理記錄時發生錯誤: $e');
        }
      }

      // 計算該插座每組的區間用電量 (Wh)
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
          double energy = (p1 + p2) / 2 * timeDiffHours;
          totalEnergy += energy;
        }
        
        if (!intervalConsumption.containsKey(key)) {
          intervalConsumption[key] = 0.0;
        }
        intervalConsumption[key] = intervalConsumption[key]! + totalEnergy;
      });
    }

    // ✅ 關鍵修復: 延遲 setState
    if (mounted) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _chartData = intervalConsumption;
            if (_chartData.isEmpty) {
              _errorMessage = '此時間範圍內無資料';
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
              // ... 其餘的 UI 代碼保持不變
              
              // 插座切換標籤
              Container(
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Row(
                  children: List.generate(4, (index) {
                    final isSelected = _selectedPlugIndex == index;
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
                            child: Text(
                              '${index + 1}號',
                              style: TextStyle(
                                fontSize: 14,
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

              // 匯出報表按鈕
              Center(
                child: ElevatedButton.icon(
                  onPressed: _showExportDialog,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.download, size: 24),
                  label: const Text('匯出報表', style: TextStyle(fontSize: 18)),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: statusColor, width: 1.5),
                ),
                child: Text(
                  isOn ? '開啟' : '關閉',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
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
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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