import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

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
  static const String baseUrl = 'http://localhost:3000';
  
  static Future<Map<String, String>> _getHeaders() async {
    final token = await TokenService.getToken();
    return {
      'Content-Type': 'application/json',
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

  @override
  void initState() {
    super.initState();
    _fetchAllPlugsRealtimeData();
    _fetchHistoricalData();
    
    // 每 10 秒自動刷新即時資料
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      _fetchAllPlugsRealtimeData();
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

  /// 獲取所有插座的即時資料
  Future<void> _fetchAllPlugsRealtimeData() async {
    List<PowerPlugData> newPlugsData = [];
    
    for (var device in _devices) {
      try {
        final response = await ApiService.get(
          '/api/power-logs/latest/${device['id']}'
        );

        print('設備 ${device['name']} 回應: ${response.statusCode}');

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          
          print('設備 ${device['name']} 資料: $data');
          
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
    
    if (newPlugsData.isNotEmpty) {
      setState(() {
        _plugsData.clear();
        _plugsData.addAll(newPlugsData);
        _errorMessage = null;
      });
    }
  }

  /// 獲取歷史資料(用於圖表) - 四個插座加總
  Future<void> _fetchHistoricalData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
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
      
      print('查詢時間範圍: $startTimeStr 到 $endTimeStr');
      
      // 獲取所有四個插座的歷史資料
      List<List<dynamic>> allDevicesLogs = [];
      
      for (var device in _devices) {
        try {
          final response = await ApiService.get(
            '/api/power-logs?device_id=${device['id']}&start_time=$startTimeStr&end_time=$endTimeStr&limit=1000'
          );

          print('設備 ${device['name']} 歷史資料回應: ${response.statusCode}');

          if (response.statusCode == 200) {
            final data = json.decode(response.body);
            if (data['success'] == true && data['data'] != null && data['data'].isNotEmpty) {
              print('設備 ${device['name']} 獲取到 ${data['data'].length} 筆資料');
              allDevicesLogs.add(data['data']);
            } else {
              print('設備 ${device['name']} 無資料');
            }
          }
        } catch (e) {
          print('獲取 ${device['name']} 歷史資料失敗: $e');
        }
      }

      print('總共獲取 ${allDevicesLogs.length} 個插座的資料');

      if (allDevicesLogs.isNotEmpty) {
        _processHistoricalDataSum(allDevicesLogs);
      } else {
        setState(() {
          _chartData = {};
          _errorMessage = '此時間範圍內無資料';
        });
      }
    } catch (e) {
      print('獲取歷史資料錯誤: $e');
      setState(() {
        _errorMessage = '網路連線失敗: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

/// 處理歷史資料並生成圖表資料 - 四個插座加總累積用電量
void _processHistoricalDataSum(List<List<dynamic>> allDevicesLogs) {
  Map<dynamic, double> totalEnergyByKey = {};

  // 遍歷每個插座的記錄
  for (var logs in allDevicesLogs) {
    if (logs.isEmpty) continue;

    // 按時間分組
    Map<dynamic, List<Map<String, dynamic>>> groupedData = {};

    for (var log in logs) {
      try {
        // 解析為 UTC 時間,然後轉換為本地時間
        final timestampUtc = DateTime.parse(log['timestamp']);
        final timestamp = timestampUtc.toLocal();
        final power = _safeToDouble(log['power_w']);
        
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

    // 計算該插座每組的累積用電量 (Wh)
    groupedData.forEach((key, records) {
      if (records.isNotEmpty) {
        // 按時間排序
        records.sort((a, b) => a['timestamp'].compareTo(b['timestamp']));
        
        double totalEnergy = 0.0;
        
        // 使用梯形法則計算累積用電量
        for (int i = 0; i < records.length - 1; i++) {
          DateTime t1 = records[i]['timestamp'];
          DateTime t2 = records[i + 1]['timestamp'];
          double p1 = records[i]['power'];
          double p2 = records[i + 1]['power'];
          
          // 計算時間差(小時)
          double timeDiffHours = t2.difference(t1).inSeconds / 3600.0;
          
          // 梯形法則: Energy = (P1 + P2) / 2 * ΔT
          double energy = (p1 + p2) / 2 * timeDiffHours;
          totalEnergy += energy;
        }
        
        // 累加到總能量
        if (!totalEnergyByKey.containsKey(key)) {
          totalEnergyByKey[key] = 0.0;
        }
        totalEnergyByKey[key] = totalEnergyByKey[key]! + totalEnergy;
      }
    });
  }

  print('處理後的圖表資料: $totalEnergyByKey');

  setState(() {
    _chartData = totalEnergyByKey;
    if (_chartData.isEmpty) {
      _errorMessage = '此時間範圍內無資料';
    }
  });
}

  /// 選擇日期
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
      _fetchHistoricalData();
    }
  }

  /// 重新整理資料
  Future<void> _refreshData() async {
    await Future.wait([
      _fetchAllPlugsRealtimeData(),
      _fetchHistoricalData(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 錯誤訊息顯示
              if (_errorMessage != null)
                Container(
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
                        onPressed: _refreshData,
                        child: const Text('重試'),
                      ),
                    ],
                  ),
                ),

              // 載入指示器
              if (_isLoading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: CircularProgressIndicator(),
                  ),
                ),

              // 即時資料標題
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '即時資料',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _isLoading ? null : _refreshData,
                    tooltip: '重新整理',
                  ),
                ],
              ),
              const SizedBox(height: 16),

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
                          setState(() {
                            _selectedPlugIndex = index;
                          });
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
                      '累積用電量 (Wh) - ${_getChartModeText()}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      height: 250,
                      child: _chartData.isEmpty
                          ? const Center(child: Text('此時間範圍內無資料'))
                          : LineChart(_buildLineChartData()),
                    ),
                    const SizedBox(height: 20),
                    // 詳細數據表格
                    _buildPowerDetailsTable(),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // 匯出報表和下拉選單
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('匯出報表功能待實現')),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.download),
                    label: const Text('匯出報表', style: TextStyle(fontSize: 18)),
                  ),
                  const SizedBox(width: 16),

                  // 下拉選單按鈕
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 30),
                      onSelected: (String result) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('選擇匯出為 $result 格式')),
                        );
                      },
                      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                        const PopupMenuItem<String>(
                          value: 'CSV檔',
                          child: Text('CSV檔'),
                        ),
                        const PopupMenuItem<String>(
                          value: 'Excel檔',
                          child: Text('Excel檔'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
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

  /// 構建詳細數據表格 - 顯示四插座加總累積用電量
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
                    '累積用電量 (Wh)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text(
                    _getGrowthRateHeaderText(),
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
            String growthRate = '-';
            int index = sortedKeys.indexOf(key);
            if (index > 0) {
              final double previousEnergy = _safeToDouble(_chartData[sortedKeys[index - 1]]);
              if (previousEnergy != 0) {
                final double rate = (energy - previousEnergy) / previousEnergy * 100;
                growthRate = '${rate.toStringAsFixed(1)}%';
              }
            }

            return _buildTableRow(key, energy, growthRate);
          } catch (e) {
            print('構建表格行時發生錯誤: $e');
            return _buildTableRow(key, 0.0, '-');
          }
        }).toList(),
      ],
    );
  }

  /// 根據模式獲取表格成長率標題文字
  String _getGrowthRateHeaderText() {
    switch (_selectedChartMode) {
      case ChartMode.daily:
        return '小時成長率';
      case ChartMode.weekly:
        return '日成長率';
      case ChartMode.monthly:
        return '日成長率';
    }
  }

  /// 根據模式獲取表格標題文字
  String _getTableHeaderText() {
    switch (_selectedChartMode) {
      case ChartMode.daily:
        return '時間';
      case ChartMode.weekly:
        return '星期';
      case ChartMode.monthly:
        return '日期';
    }
  }

  /// 表格行
  Widget _buildTableRow(
    dynamic label,
    double energy,
    String growthRate,
  ) {
    String formattedLabel;
    try {
      if (_selectedChartMode == ChartMode.weekly) {
        List<String> weekdays = ['一', '二', '三', '四', '五', '六', '日'];
        int index = _safeToDouble(label).toInt();
        if (index >= 1 && index <= 7) {
          formattedLabel = weekdays[index - 1];
        } else {
          formattedLabel = label.toString();
        }
      } else {
        formattedLabel = _safeToDouble(label).toInt().toString();
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
          Expanded(
            child: Center(
              child: Text(
                growthRate,
                style: TextStyle(
                  color: growthRate.startsWith('-') 
                      ? Colors.black 
                      : (growthRate.contains('-') ? Colors.red : Colors.green),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 構建折線圖資料
  LineChartData _buildLineChartData() {
    if (_chartData.isEmpty) {
      return LineChartData(
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        gridData: const FlGridData(show: false),
        lineBarsData: [],
      );
    }

    final List<FlSpot> spots = _chartData.entries.map((entry) {
      return FlSpot(_safeToDouble(entry.key), _safeToDouble(entry.value));
    }).toList()
      ..sort((a, b) => a.x.compareTo(b.x));

    double minX = 0.0, maxX = 1.0, minY = 0.0, maxY = 100.0;
    
    try {
      final xValues = spots.map((e) => e.x).toList();
      final yValues = spots.map((e) => e.y).toList();
      
      if (xValues.isNotEmpty && yValues.isNotEmpty) {
        minX = xValues.reduce((a, b) => a < b ? a : b);
        maxX = xValues.reduce((a, b) => a > b ? a : b);
        minY = (yValues.reduce((a, b) => a < b ? a : b) - 10).clamp(0, double.infinity);
        maxY = yValues.reduce((a, b) => a > b ? a : b) + 10;
        
        if (maxX == minX) maxX = minX + 1;
        if (maxY == minY) maxY = minY + 100;
      }
    } catch (e) {
      print('計算圖表範圍時發生錯誤: $e');
    }

    return LineChartData(
      gridData: FlGridData(
        show: true,
        drawHorizontalLine: true,
        drawVerticalLine: true,
        horizontalInterval: (maxY - minY) / 5,
        verticalInterval: _getVerticalInterval(),
        getDrawingHorizontalLine: (value) {
          return const FlLine(
            color: Colors.grey,
            strokeWidth: 0.5,
          );
        },
        getDrawingVerticalLine: (value) {
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
            interval: _getBottomTitleInterval(),
            getTitlesWidget: (value, meta) {
              return SideTitleWidget(
                axisSide: meta.axisSide,
                space: 8.0,
                child: Text(
                  _getBottomTitleText(value),
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
            interval: (maxY - minY) / 5,
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
      minX: minX,
      maxX: maxX,
      minY: minY,
      maxY: maxY,
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          gradient: LinearGradient(
            colors: [
              Theme.of(context).primaryColor,
              Theme.of(context).primaryColor.withOpacity(0.5),
            ],
          ),
          barWidth: 3,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            gradient: LinearGradient(
              colors: [
                Theme.of(context).primaryColor.withOpacity(0.3),
                Theme.of(context).primaryColor.withOpacity(0),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
        ),
      ],
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

  /// 根據選定的模式獲取 X 軸標籤文字
  String _getBottomTitleText(double value) {
    try {
      switch (_selectedChartMode) {
        case ChartMode.daily:
          return '${value.toInt()}時';
        case ChartMode.weekly:
          List<String> weekdays = ['一', '二', '三', '四', '五', '六', '日'];
          int index = value.toInt();
          if (index >= 1 && index <= 7) {
            return weekdays[index - 1];
          }
          return '';
        case ChartMode.monthly:
          return value.toInt().toString();
      }
    } catch (e) {
      return '';
    }
  }

  /// 根據模式獲取圖表模式文字
  String _getChartModeText() {
    switch (_selectedChartMode) {
      case ChartMode.daily:
        return '每日';
      case ChartMode.weekly:
        return '每週';
      case ChartMode.monthly:
        return '每月';
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