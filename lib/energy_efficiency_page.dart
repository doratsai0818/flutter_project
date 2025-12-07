// lib/energy_efficiency_page.dart

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:convert';
import 'package:iot_project/main.dart';
import 'package:intl/intl.dart';

class EnergyEfficiencyPage extends StatefulWidget {
  const EnergyEfficiencyPage({super.key});

@override
  State<EnergyEfficiencyPage> createState() => _EnergyEfficiencyPageState();
}

class _EnergyEfficiencyPageState extends State<EnergyEfficiencyPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  Map<String, dynamic>? _simulationData;
  Map<String, dynamic>? _realComparisonData; // ✅ 新增實際比較數據
  
  bool _isLoading = true;
  String? _errorMessage;

  // ✅ 只保留實際使用的輔助函數
  double _safeParseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
  
  // ✅ 輔助函數：從格式化字串中提取數字，用於計算（不影響顯示的字串）
  double _parseCost(dynamic cost) {
    if (cost is num) return cost.toDouble();
    if (cost is String) {
      // 移除 'NT$' 和逗號後嘗試解析
      return double.tryParse(cost.replaceAll('NT\$', '').replaceAll(',', '').trim()) ?? 0.0;
    }
    return 0.0;
  }

  // ✅ 輔助函數：將數值格式化為純字串（例如：2.97）
  String _formatCostValue(dynamic cost) {
    return _parseCost(cost).toStringAsFixed(2);
  }

  @override
  void initState() {
    super.initState();
    // ✅ TabController 長度改為 1
    _tabController = TabController(length: 2, vsync: this); // ✅ 改回 2
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllData() async {
  setState(() {
    _isLoading = true;
    _errorMessage = null;
  });
  try {
    await Future.wait([
      _fetchSimulationData(),
      _fetchRealComparisonData(), // ✅ 新增
    ]);
  } catch (e) {
    setState(() {
      _errorMessage = '載入數據失敗: $e';
    });
  } finally {
    setState(() {
      _isLoading = false;
    });
  }
}

  // ✅ 修改為固定獲取兩個時段的數據
  Future<void> _fetchRealComparisonData() async {
    try {
      // 固定日期: 2025-12-01
      const dateStr = '2025-12-01';
      
      // 同時獲取兩個時段的數據
      final afternoonParams = 'start_time=${dateStr}T14:00:00&end_time=${dateStr}T17:00:00';
      final eveningParams = 'start_time=${dateStr}T17:00:00&end_time=${dateStr}T20:00:00';
      
      final responses = await Future.wait([
        ApiService.get('/power-logs?$afternoonParams'),
        ApiService.get('/power-logs?$eveningParams'),
      ]);
      
      if (responses[0].statusCode == 200 && responses[1].statusCode == 200) {
        final afternoonData = json.decode(responses[0].body);
        final eveningData = json.decode(responses[1].body);
        
        if (afternoonData['success'] && eveningData['success']) {
          setState(() {
            _realComparisonData = {
              'afternoon': _processRealData(afternoonData['data']),
              'evening': _processRealData(eveningData['data']),
            };
          });
        }
      }
    } catch (e) {
      print('獲取實際數據失敗: $e');
    }
  }

  // ✅ 處理實際數據,計算統計資訊
  Map<String, dynamic> _processRealData(List rawData) {
    // 按設備分組
    Map<String, List> deviceData = {};
    for (var log in rawData) {
      String deviceId = log['device_id'];
      if (!deviceData.containsKey(deviceId)) {
        deviceData[deviceId] = [];
      }
      deviceData[deviceId]!.add(log);
    }
    
    // 計算每個設備的耗電量
    Map<String, double> deviceEnergy = {};
    double totalEnergy = 0;
    
    deviceData.forEach((deviceId, logs) {
      if (logs.isNotEmpty) {
        logs.sort((a, b) => a['timestamp'].compareTo(b['timestamp']));
        double startKwh = _safeParseDouble(logs.first['total_kwh']);
        double endKwh = _safeParseDouble(logs.last['total_kwh']);
        double energy = (endKwh - startKwh) * 1000; // 轉換為 Wh
        deviceEnergy[deviceId] = energy;
        totalEnergy += energy;
      }
    });
    
    return {
      'deviceEnergy': deviceEnergy,
      'totalEnergy': totalEnergy,
      'logs': rawData,
      'deviceData': deviceData,
    };
  }

  Future<void> _fetchSimulationData() async {
    try {
      final response = await ApiService.get('/energy-efficiency/simulation');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            _simulationData = data['data'];
          });
        }
      }
    } catch (e) {
      print('獲取模擬數據失敗: $e');
    }
  }

  // ❌ 移除所有與實際對比相關的數據獲取和模式切換方法

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // TabBar - 只有一個分頁
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
  
              labelColor: Colors.green[700]!,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.green[700]!,
              tabs: const [
                Tab(icon: Icon(Icons.science), text: '模擬比較'),
                Tab(icon: Icon(Icons.assessment), text: '實際比較'), // ✅ 新增
              ],
            ),
          ),

          // 內容區
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
              
                    : _errorMessage != null
                    ? _buildErrorView()
                    : TabBarView(
                        controller: _tabController,
                        children: [
                          _buildSimulationTab(),
                          _buildRealComparisonTab(), // ✅ 新增
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  // 錯誤視圖
  Widget _buildErrorView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(_errorMessage!, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadAllData,
            child: const Text('重新載入'),
          ),
        ],
      ),
    );
  }

  // ===== 模擬說明卡片 =====
Widget _buildSimulationNotesCard(Map<String, dynamic> notes) {
  return Container(
    padding: const EdgeInsets.all(16.0),
    margin: const EdgeInsets.only(bottom: 16.0),
    decoration: BoxDecoration(
      color: Colors.blue.shade50,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.blue.shade300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
     
            Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
            const SizedBox(width: 8),
            Text(
              '本估算為 ${notes['roomSize']} / ${notes['acModel']}',
              style: TextStyle(
                fontSize: 14,
              
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        
        // PMV=0 假設條件
        
        Text(
          '假設條件 (PMV=0):',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade800,
          ),
        ),
        const SizedBox(height: 8),
        
   
        _buildAssumptionRow('室內溫度', '${notes['assumptions']['indoorTemp']}°C'),
        _buildAssumptionRow('輻射溫度', '${notes['assumptions']['radiationTemp']}°C (假設與空氣溫度相同)'),
        _buildAssumptionRow('風速', '${notes['assumptions']['airVelocity']} m/s (無風扇)'),
        _buildAssumptionRow('相對濕度', '${notes['assumptions']['relativeHumidity']}%'),
        _buildAssumptionRow('活動強度', '${notes['assumptions']['activityMET']} MET (一般坐著或輕度活動)'),
        _buildAssumptionRow('衣著', '${notes['assumptions']['clothingCLO']} CLO (典型夏季服飾)'),
        
        const SizedBox(height: 12),
        Divider(color: Colors.blue.shade200),
        const SizedBox(height: 8),
     
        // 冷氣功率說明
        Text(
          '冷氣功率階段 (達到 PMV=0):',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade800,
          ),
        
        ),
        const SizedBox(height: 8),
        
        _buildPowerStageRow('剛開機', notes['acPowerStages']['startup']),
        _buildPowerStageRow('接近設定', notes['acPowerStages']['approaching']),
        _buildPowerStageRow('維持穩態', notes['acPowerStages']['steady']),
      ],
    ),
  );
}

Widget _buildAssumptionRow(String label, String value) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4.0),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '• ',
          style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
        ),
        Expanded(
          child: RichText(
      
            text: TextSpan(
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
   
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _buildPowerStageRow(String stage, String power) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 4.0),
    child: Row(
      children: [
        Container(
          width: 80,
          child: Text(
            stage,
            style: TextStyle(
              fontSize: 12,
   
              color: Colors.grey.shade600,
            ),
          ),
        ),
        Text(
          power,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
   
            color: Colors.blue.shade700,
          ),
        ),
      ],
    ),
  );
}

  // Tab 1: 模擬比較
  Widget _buildSimulationTab() {
    if (_simulationData == null) {
      return const Center(child: Text('無數據'));
    }

    final scenarios = _simulationData!['scenarios'] as List;
    final comparison = _simulationData!['comparison'];
    final simulationNotes = _simulationData!['simulationNotes'];

    return RefreshIndicator(
      onRefresh: _fetchSimulationData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 說明卡片
            if (simulationNotes != null) _buildSimulationNotesCard(simulationNotes),
       
            // 情景對比圖表
            _buildScenarioComparisonChart(scenarios),
            const SizedBox(height: 20),

            // 情景詳細列表
            ...scenarios.asMap().entries.map((entry) {
              int index = entry.key;
              var scenario = entry.value;
        
              bool isOurSystem = index == 2;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _buildScenarioCard(scenario, isOurSystem, index + 1),
              );
            }).toList(),

        
            const SizedBox(height: 20),

            // 節省效益總結
            _buildSavingsSummary(comparison, scenarios),
          ],
        ),
      ),
    );
  }

  // ❌ 移除 _buildEnvironmentCard, _buildEnvItem (與實際對比相關)


  // 情景對比圖表
  Widget _buildScenarioComparisonChart(List scenarios) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 2,
         
            blurRadius: 5,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '1小時耗電量對比 (Wh)',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (() {
 
                  final maxEnergy = scenarios.map((s) => _safeParseDouble(s['totalEnergy'])).reduce((a, b) => a > b ?
                  a : b);
                  // 計算合適的上限(取整到最近的100)
                  return ((maxEnergy / 100).ceil() * 100).toDouble();
                })(),
                barTouchData: BarTouchData(enabled: true),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
      
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        const titles = ['傳統模式', '風扇輔助', '智慧節能'];
                        if (value.toInt() >= 0 && 
                        value.toInt() < titles.length) {
                          return Text(
                            titles[value.toInt()],
                            style: TextStyle(fontSize: 12),
            
                          );
                        }
                        return const Text('');
                      },
              
                      ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                  ),
               
                  topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(show: true, drawVerticalLine: false),
                borderData: FlBorderData(show: false),
                barGroups: scenarios.asMap().entries.map((entry) {
 
                  int index = entry.key;
                  var scenario = entry.value;
                  Color barColor = index == 2 ? Colors.green : Colors.orange;
                  return BarChartGroupData(
                    x: index,
                    barRods: [
                      BarChartRodData(
                        toY: _safeParseDouble(scenario['totalEnergy']),
          
                        color: barColor,
                        width: 40,
                        borderRadius: BorderRadius.circular(4),
                      ),
             
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 情景卡片
  Widget _buildScenarioCard(Map<String, dynamic> scenario, bool isOurSystem, int number) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: isOurSystem ? Colors.green[50] : Colors.grey[100], 
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOurSystem ? Colors.green[300]! : Colors.grey[300]!,  
         
          width: isOurSystem ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
 
                height: 36,
                decoration: BoxDecoration(
                  color: isOurSystem ? Colors.green : Colors.orange,
                  shape: BoxShape.circle,
                ),
         
                child: Center(
                  child: Text(
                    '$number',
                    style: const TextStyle(
                      color: Colors.white,
        
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
        
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
         
                    Text(
                      scenario['name'],
                      style: TextStyle(
                        fontSize: 16,
                   
                        fontWeight: FontWeight.bold,
                        color: isOurSystem ?
                        Colors.green[700] : Colors.black87,
                      ),
                    ),
                    Text(
                      scenario['description'],
          
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              if (isOurSystem)
 
                Icon(Icons.stars, color: Colors.green[700], size: 28),
            ],
          ),
          const SizedBox(height: 12),
          Divider(),
          const SizedBox(height: 8),
          _buildScenarioDetail('冷氣溫度', '${scenario['acTemp']}°C'),
          
          _buildScenarioDetail('冷氣功率', '${scenario['acPower']} W'),
          _buildScenarioDetail('風扇檔位', '${scenario['fanSpeed']} (${scenario['fanPower']} W)'),
          _buildScenarioDetail('運行時間', '${scenario['runningTime']} 分鐘'),
          Divider(),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
             
                '總耗電量',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            
              Text(
                '${_safeParseDouble(scenario['totalEnergy']).toStringAsFixed(1)} Wh',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isOurSystem ?
                  Colors.green.shade700 : Colors.orange,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScenarioDetail(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey.shade700)),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // 節省效益總結
  Widget _buildSavingsSummary(Map<String, dynamic> comparison, List scenarios) {
    // 獲取原始的單次節省金額（格式化字串，例如 'NT$ 5.3'）
    final String cost1Str = comparison['costSavedVsScenario1'] ?? 'NT\$ 0.0';
    final String cost2Str = comparison['costSavedVsScenario2'] ?? 'NT\$ 0.0';

    // 轉換為數值，用於乘法計算
    final double singleCost1 = _parseCost(cost1Str);
    final double singleCost2 = _parseCost(cost2Str);

    // 提取純金額字串，用於 _buildSavingsItem
    final String costValue1 = _formatCostValue(cost1Str);
    final String costValue2 = _formatCostValue(cost2Str);

  return Container(
    padding: const EdgeInsets.all(20.0),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Colors.green[600]!, Colors.green[400]!],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        const Icon(Icons.savings, color: 
          Colors.white, size: 48),
        const SizedBox(height: 12),
        const Text(
          '智慧節能效益',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
 
        const SizedBox(height: 20),
        
        Row(
          children: [
            Expanded(
              child: _buildSavingsItem(
                '相較無風扇',
          
                '${comparison['savingsVsScenario1']}%',
                '節省 ${comparison['energySavedVsScenario1']} Wh',
                costValue1, // 單次節省金額 (純數值字串)
                singleCost1, // 單次金額 (數值)
              ),
            ),
            Container(width: 1, height: 80, color: Colors.white.withOpacity(0.3)),
            Expanded(
 
              child: _buildSavingsItem(
                '相較風扇輔助',
                '${comparison['savingsVsScenario2']}%',
                '節省 ${comparison['energySavedVsScenario2']} Wh',
                costValue2, // 單次節省金額 (純數值字串)
                singleCost2, // 單次金額 (數值)
              ),
  
            ),
          ],
        ),
      ],
    ),
  );
}

// ✅ 修改 _buildSavingsItem 函數：調整顯示格式
Widget _buildSavingsItem(String title, String percent, String detail, String costValue, double singleCost) {
  // 1. 計算月度節省金額 (單次節省金額 * 30)
  final double monthlyCostValue = singleCost * 30.0;
  // 2. 格式化月度金額為純數值字串
  final String monthlyCost = monthlyCostValue.toStringAsFixed(1); // 使用 1 位小數，與原月度金額格式一致

  return Column(
    children: [
      Text(
        title,
        style: TextStyle(
          fontSize: 12,
          color: Colors.white.withOpacity(0.9),
        ),
      ),
      const SizedBox(height: 4),
      Text(
       
        percent,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      const SizedBox(height: 2),
      Text(
        detail,
        style: TextStyle(
          fontSize: 
          11,
          color: Colors.white.withOpacity(0.8),
        ),
      ),
      const SizedBox(height: 4),
      // ✅ 顯示單次金額 (格式：節省NT$ [數值])
      Text(
        '節省NT\$ $costValue',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.white,
  
        ),
      ),
      const SizedBox(height: 4), 
      // ✅ 顯示月度金額 (格式：一個月節省NT$ [數值])
      Text(
        '一個月節省NT\$ $monthlyCost',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: Colors.white.withOpacity(0.8),
        ),
      ),
    ],
  );
}

Widget _buildRealComparisonTab() {
  if (_realComparisonData == null) {
    return const Center(child: Text('無數據'));
  }

  return RefreshIndicator(
    onRefresh: _fetchRealComparisonData,
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 固定日期標題卡片
          _buildFixedDateHeader(),
          const SizedBox(height: 20),

          // ✅ 新增:用電情境描述卡片
          _buildScenarioDescriptionCard(),
          const SizedBox(height: 20),
          
          // 對比卡片標題
          Text(
            '實際用電對比分析',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 16),
          
          // 兩個時段的對比卡片
          _buildTimeSlotComparisonCards(),
          const SizedBox(height: 20),
          
          // 節能效益總結
          _buildRealSavingsSummary(),
          const SizedBox(height: 20),
          
          // 詳細設備數據 (左右排列)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左側:下午時段
              Expanded(
                child: _buildDeviceDetailSection('afternoon', '下午時段 (14:00-17:00)'),
              ),
              
              const SizedBox(width: 16), // 左右間距
              
              // 右側:晚上時段
              Expanded(
                child: _buildDeviceDetailSection('evening', '晚上時段 (17:00-20:00)'),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

// ✅ 固定日期標題卡片
Widget _buildFixedDateHeader() {
  return Container(
    padding: const EdgeInsets.all(16.0),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Colors.blue[700]!, Colors.blue[500]!],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.calendar_today,
            color: Colors.white,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '對比日期',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                '2025年12月1日',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildTimeChip('下午 14:00-17:00', Icons.wb_sunny),
                  const SizedBox(width: 8),
                  _buildTimeChip('晚上 17:00-20:00', Icons.nightlight_round),
                ],
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

// ✅ 新增:用電情境描述卡片
Widget _buildScenarioDescriptionCard() {
  return Container(
    padding: const EdgeInsets.all(16.0),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Colors.indigo.shade50, Colors.blue.shade50],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.blue.shade200),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 標題
        Row(
          children: [
            Icon(Icons.description, color: Colors.indigo.shade700, size: 24),
            const SizedBox(width: 8),
            Text(
              '當日用電情境說明',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.indigo.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // 下午時段描述
        _buildScenarioItem(
          '下午時段 (14:00-17:00)',
          '智慧節能模式運行',
          [
            '14:00 - 實驗室保持開燈狀態',
            '14:01 - 離開去買午餐',
            '14:06 - 系統偵測無人,自動關閉設備',
            '14:21 - 返回實驗室,設備自動開啟',
            '15:00 - 離開去上課',
            '15:05 - 系統再次偵測無人,關閉所有設備',
            '15:05-17:00 - 設備保持關閉狀態',
          ],
          Colors.green,
        ),
        
        const SizedBox(height: 16),
        Divider(color: Colors.blue.shade200),
        const SizedBox(height: 16),
        
        // 晚上時段描述
        _buildScenarioItem(
          '晚上時段 (17:00-20:00)',
          '傳統持續模式',
          [
            '17:00 - 人員未回實驗室',
            '17:00-20:00 - 兩顆燈泡 + 風扇2檔持續運行',
            '系統未啟動自動關閉,設備運行3小時',
          ],
          Colors.orange,
        ),
        
        const SizedBox(height: 12),
        
      ],
    ),
  );
}

// 輔助函數:情境項目
Widget _buildScenarioItem(String title, String subtitle, List<String> steps, Color color) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // 標題
      Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      
      // 步驟列表
      ...steps.map((step) => Padding(
        padding: const EdgeInsets.only(left: 20, bottom: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '• ',
              style: TextStyle(color: color, fontSize: 12),
            ),
            Expanded(
              child: Text(
                step,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      )).toList(),
    ],
  );
}

Widget _buildTimeChip(String text, IconData icon) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.2),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 14),
        const SizedBox(width: 4),
        Text(
          text,
          style: const TextStyle(
            fontSize: 11,
            color: Colors.white,
          ),
        ),
      ],
    ),
  );
}

Widget _buildTimeSlotComparisonCards() {
  final afternoonData = _realComparisonData!['afternoon'];
  final afternoonEnergy = afternoonData['totalEnergy'] ?? 0.0;
  
  final eveningData = _realComparisonData!['evening'];
  final eveningEnergy = eveningData['totalEnergy'] ?? 0.0;
  
  return Row(
    children: [
      // 左側:下午時段
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '下午時段 (14:00-17:00)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),
            _buildEnergyCard(
              '系統運行',
              '人離開後5分鐘自動關閉設備',
              afternoonEnergy,
              Colors.green,
              Icons.eco,
            ),
          ],
        ),
      ),
      
      const SizedBox(width: 16), // 左右間距
      
      // 右側:晚上時段
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '晚上時段 (17:00-20:00)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 12),
            _buildEnergyCard(
              '系統關閉',
              '所有設備持續運行3小時',
              eveningEnergy,
              Colors.orange,
              Icons.lightbulb_outline,
            ),
          ],
        ),
      ),
    ],
  );
}

Widget _buildEnergyCard(
  String title,
  String description,
  double energy,
  Color color,
  IconData icon,
) {
  final cost = (energy / 1000) * 2.77;
  
  return Container(
    padding: const EdgeInsets.all(16.0),
    decoration: BoxDecoration(
      color: color.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color, width: 2),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                  Text(
                    description,
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Divider(color: color.withOpacity(0.3)),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '總耗電量',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
            Text(
              '${energy.toStringAsFixed(1)} Wh',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '電費',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
            Text(
              'NT\$ ${cost.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}



Widget _buildRealSavingsSummary() {
  // 下午時段
  final afternoonData = _realComparisonData!['afternoon'];
  final afternoonEnergy = afternoonData['totalEnergy'] ?? 0.0;
  
  // 晚上時段
  final eveningData = _realComparisonData!['evening'];
  final eveningEnergy = eveningData['totalEnergy'] ?? 0.0;
  
  // 計算差異
  final energyDiff = (eveningEnergy - afternoonEnergy).abs();
  final percentDiff = eveningEnergy > 0 
      ? ((energyDiff / eveningEnergy) * 100) 
      : 0.0;
  final costDiff = (energyDiff / 1000) * 2.77;
  
  // 判斷哪個時段更省電
  final isMorningBetter = afternoonEnergy < eveningEnergy;
  
  return Container(
    padding: const EdgeInsets.all(20.0),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Colors.blue[600]!, Colors.blue[400]!],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      children: [
        const Icon(Icons.analytics, color: Colors.white, size: 48),
        const SizedBox(height: 12),
        const Text(
          '當日實際用電對比',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '2025年12月1日',
          style: TextStyle(
            fontSize: 13,
            color: Colors.white.withOpacity(0.9),
          ),
        ),
        const SizedBox(height: 20),
        
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildRealSavingsMetric(
              '用電差異',
              '${energyDiff.toStringAsFixed(1)} Wh',
              Icons.bolt,
            ),
            Container(width: 1, height: 60, color: Colors.white30),
            _buildRealSavingsMetric(
              '差異比例',
              '${percentDiff.toStringAsFixed(1)}%',
              Icons.trending_down,
            ),
            Container(width: 1, height: 60, color: Colors.white30),
            _buildRealSavingsMetric(
              '電費差異',
              'NT\$ ${costDiff.toStringAsFixed(2)}',
              Icons.attach_money,
            ),
          ],
        ),
        
        const SizedBox(height: 16),
        Divider(color: Colors.white30),
        const SizedBox(height: 12),
        
        // 分時段顯示
        Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Text(
                    '下午時段',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${afternoonEnergy.toStringAsFixed(1)} Wh',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (isMorningBetter)
                    const Text(
                      '✓ 較省電',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
            Container(width: 1, height: 40, color: Colors.white30),
            Expanded(
              child: Column(
                children: [
                  Text(
                    '晚上時段',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.8),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${eveningEnergy.toStringAsFixed(1)} Wh',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (!isMorningBetter)
                    const Text(
                      '✓ 較省電',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.greenAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

Widget _buildRealSavingsMetric(String label, String value, IconData icon) {
  return Column(
    children: [
      Icon(icon, color: Colors.white, size: 28),
      const SizedBox(height: 8),
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: Colors.white.withOpacity(0.9),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        value,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
    ],
  );
}

// 📍 插入位置:第 1120 行之前



// ✅ 新增數據處理函數
Map<String, dynamic> _getTimeSlotTableData(String timeSlot) {
  if (timeSlot == 'afternoon') {
    return {
      'period': '14:00-17:00',
      'mode': '系統運行',
      'time': '50分鐘',
      'device1': '6.6Wh',
      'device2': '6.6Wh',
      'fan': '0.0Wh',
      'total': '13.2Wh',
      'cost': 'NT\$0.04',
      'yearCost': 'NT\$13.50',
      'color': Colors.green,
      'icon': Icons.eco,
    };
  } else {
    return {
      'period': '17:00-20:00',
      'mode': '系統關閉',
      'time': '180分鐘',
      'device1': '27.0Wh',
      'device2': '27.0Wh',
      'fan': '12.6Wh',
      'total': '66.6Wh',
      'cost': 'NT\$0.19',
      'yearCost': 'NT\$68.50',
      'color': Colors.orange,
      'icon': Icons.lightbulb_outline,
    };
  }
}

Widget _buildDeviceDetailSection(String timeSlot, String title) {
  // 獲取該時段的實際數據
  final timeSlotData = _realComparisonData![timeSlot];
  final deviceEnergy = timeSlotData['deviceEnergy'] as Map<String, double>;
  final totalEnergy = timeSlotData['totalEnergy'] as double;
  final deviceData = timeSlotData['deviceData'] as Map<String, List>;
  
  // ✅ 修改：年度電費直接從原始數據計算，避免累積誤差
  final totalCost = (totalEnergy / 1000) * 2.77;           // 單次電費
  final yearCost = (totalEnergy / 1000) * 2.77 * 365;      // 年度電費（一次計算完成）

  // ✅ 先判斷是下午還是晚上
  final isAfternoon = timeSlot == 'afternoon';
  
  // ✅ 固定運行時間:下午50分鐘,晚上180分鐘
  final int totalMinutes = isAfternoon ? 50 : 180;
  
  // 判斷顏色和圖標
  final color = isAfternoon ? Colors.green : Colors.orange;
  final icon = isAfternoon ? Icons.eco : Icons.lightbulb_outline;
  final mode = isAfternoon ? '系統運行' : '系統關閉';
  final period = isAfternoon ? '14:00-17:00' : '17:00-20:00';
  
  // ✅ 固定設備順序:根據 MAC 地址明確定義
final Map<String, String> deviceNameMap = {
  '3c0b59a0261b': '1號燈泡總耗電量',  // 門口燈泡
  '80647cafe420': '2號燈泡總耗電量',  // 燈泡
  '80647cafb7dd': '風扇總耗電量',     // 電扇
};

// ✅ 按照固定順序排列設備
final List<String> deviceIds = [
  '3c0b59a0261b',  // 1號燈泡
  '80647cafe420',  // 2號燈泡
  '80647cafb7dd',  // 風扇
];

// ✅ 只保留有資料的設備
final List<String> availableDeviceIds = deviceIds
    .where((id) => deviceEnergy.containsKey(id))
    .toList();

// 設備名稱映射函數
String getDeviceName(String deviceId) {
  return deviceNameMap[deviceId] ?? '未知設備';
}
  
  return Container(
    padding: const EdgeInsets.all(16.0),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withOpacity(0.2),
          spreadRadius: 2,
          blurRadius: 5,
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 標題
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // 表格
        Table(
          border: TableBorder.all(
            color: Colors.grey.shade300,
            width: 1,
            borderRadius: BorderRadius.circular(8),
          ),
          columnWidths: const {
            0: FlexColumnWidth(1.2),
            1: FlexColumnWidth(1.0),
          },
          children: [
            // 表頭
            TableRow(
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
              ),
              children: [
                _buildTableCell('項目', isHeader: true),
                _buildTableCell('數值', isHeader: true),
              ],
            ),
            // 數據行
            _buildDataRow('時間段', period),
            _buildDataRow('情況', mode),
            _buildDataRow('總運行時間', '$totalMinutes分鐘'),
            
            // ✅ 改成這樣
            // 動態顯示各設備耗電量
            ...availableDeviceIds.map((deviceId) {
              final energy = deviceEnergy[deviceId] ?? 0.0;
              final deviceName = getDeviceName(deviceId);
              return _buildDataRow(
                deviceName, 
                '${energy.toStringAsFixed(1)}Wh'
              );
            }).toList(),
            
            _buildDataRow('整體總耗電量', '${totalEnergy.toStringAsFixed(1)}Wh', isBold: true),
            _buildDataRow('單次電費', 'NT\$${totalCost.toStringAsFixed(2)}', isBold: true),
            _buildDataRow('年度電費', 'NT\$${yearCost.toStringAsFixed(2)}', 
              isBold: true, 
              color: color,
            ),
          ],
        ),
      ],
    ),
  );
}

// 表格單元格
Widget _buildTableCell(String text, {bool isHeader = false}) {
  return Padding(
    padding: const EdgeInsets.all(12.0),
    child: Text(
      text,
      style: TextStyle(
        fontSize: isHeader ? 14 : 13,
        fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
        color: isHeader ? Colors.grey.shade800 : Colors.grey.shade700,
      ),
      textAlign: isHeader ? TextAlign.center : TextAlign.left,
    ),
  );
}

// 數據行
TableRow _buildDataRow(String label, String value, {bool isBold = false, Color? color}) {
  return TableRow(
    children: [
      Padding(
        padding: const EdgeInsets.all(12.0),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: Colors.grey.shade700,
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(12.0),
        child: Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
            color: color ?? Colors.grey.shade800,
          ),
          textAlign: TextAlign.right,
        ),
      ),
    ],
  );
}
}