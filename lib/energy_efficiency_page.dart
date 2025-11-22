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
  
  // 模擬法數據
  Map<String, dynamic>? _simulationData;
  
  // 實際比較數據
  Map<String, dynamic>? _realComparisonData;
  
  // 歷史統計數據
  Map<String, dynamic>? _historyData;
  
  bool _isLoading = true;
  String? _errorMessage;
  int _historyDays = 7;

  // ✅ ADD THESE HELPER FUNCTIONS HERE
  double _safeParseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  int _safeParseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  String _formatDate(dynamic date) {
  if (date == null) return 'N/A';
  if (date is String) return date;
  if (date is DateTime) return DateFormat('yyyy-MM-dd').format(date);
  return date.toString();
}

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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
        _fetchRealComparisonData(),
        _fetchHistoryData(),
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

  Future<void> _fetchRealComparisonData() async {
    try {
      final response = await ApiService.get('/energy-efficiency/real-comparison');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            _realComparisonData = data['data'];
          });
        }
      }
    } catch (e) {
      print('獲取實際比較數據失敗: $e');
    }
  }

  Future<void> _fetchHistoryData() async {
    try {
      final response = await ApiService.get('/energy-efficiency/history?days=$_historyDays');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            _historyData = data['data'];
          });
        }
      }
    } catch (e) {
      print('獲取歷史數據失敗: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // TabBar
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.green.shade700,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.green.shade700,
              tabs: const [
                Tab(icon: Icon(Icons.science), text: '模擬比較'),
                Tab(icon: Icon(Icons.compare_arrows), text: '實際小比'),
                Tab(icon: Icon(Icons.history), text: '歷史統計'),
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
                          _buildRealComparisonTab(),
                          _buildHistoryTab(),
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

  // Tab 1: 模擬比較
  Widget _buildSimulationTab() {
    if (_simulationData == null) {
      return const Center(child: Text('無數據'));
    }

    final scenarios = _simulationData!['scenarios'] as List;
    final comparison = _simulationData!['comparison'];
    final environment = _simulationData!['currentEnvironment'];

    return RefreshIndicator(
      onRefresh: _fetchSimulationData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 環境資訊卡片
            _buildEnvironmentCard(environment),
            const SizedBox(height: 20),

            // 情景小比圖表
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

  // 環境資訊卡片
  Widget _buildEnvironmentCard(Map<String, dynamic> environment) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.wb_sunny, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Text(
                '當前環境條件',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildEnvItem(
                icon: Icons.thermostat,
                label: '室溫',
                value: '${_safeParseDouble(environment['temperature']).toStringAsFixed(1)}°C',
                color: Colors.orange,
              ),
              _buildEnvItem(
                icon: Icons.water_drop,
                label: '濕度',
                value: '${_safeParseDouble(environment['humidity']).toStringAsFixed(0)}%',
                color: Colors.blue,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEnvItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  // 情景小比圖表
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
              maxY: scenarios.map((s) => _safeParseDouble(s['totalEnergy'])).reduce((a, b) => a > b ? a : b) * 1.2,
              barTouchData: BarTouchData(enabled: true),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      const titles = ['情境1', '情境2', '情境3'];
                      if (value.toInt() >= 0 && value.toInt() < titles.length) {
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
                      toY: _safeParseDouble(scenario['totalEnergy']), // ✅ Fixed
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
        color: isOurSystem ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOurSystem ? Colors.green.shade300 : Colors.grey.shade300,
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
                    style: TextStyle(
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
                        color: isOurSystem ? Colors.green.shade700 : Colors.black87,
                      ),
                    ),
                    Text(
                      scenario['description'],
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              if (isOurSystem)
                Icon(Icons.stars, color: Colors.green.shade700, size: 28),
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
                  color: isOurSystem ? Colors.green.shade700 : Colors.orange,
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
    final ourSystemEnergy = scenarios[2]['totalEnergy'];
    final scenario1Energy = scenarios[0]['totalEnergy'];
    final scenario2Energy = scenarios[1]['totalEnergy'];
    
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade600, Colors.green.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.savings, color: Colors.white, size: 48),
          const SizedBox(height: 12),
          Text(
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
                  '相較情景1',
                  '${comparison['savingsVsScenario1']}%',
                  '節省 ${comparison['energySavedVsScenario1']} Wh',
                ),
              ),
              Container(width: 1, height: 60, color: Colors.white.withOpacity(0.3)),
              Expanded(
                child: _buildSavingsItem(
                  '相較情景2',
                  '${comparison['savingsVsScenario2']}%',
                  '節省 ${comparison['energySavedVsScenario2']} Wh',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSavingsItem(String title, String percent, String detail) {
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
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          detail,
          style: TextStyle(
            fontSize: 11,
            color: Colors.white.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  // Tab 2: 實際小比
  Widget _buildRealComparisonTab() {
    if (_realComparisonData == null) {
      return const Center(child: Text('無數據'));
    }

    final scenarios = _realComparisonData!['scenarios'] as List;
    final comparison = _realComparisonData!['comparison'];
    final projections = comparison['projections'];

    return RefreshIndicator(
      onRefresh: _fetchRealComparisonData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 情景說明
            Text(
              '10分鐘實際使用小比',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // 兩個情景小比
            ...scenarios.asMap().entries.map((entry) {
              bool isSmartSystem = entry.key == 1;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _buildRealScenarioCard(entry.value, isSmartSystem),
              );
            }).toList(),

            const SizedBox(height: 20),

            // 節省數據
            _buildRealSavingsCard(comparison),
            const SizedBox(height: 20),

            // 長期節能預估
            _buildProjectionsCard(projections),
          ],
        ),
      ),
    );
  }

  Widget _buildRealScenarioCard(Map<String, dynamic> scenario, bool isSmartSystem) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: isSmartSystem ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSmartSystem ? Colors.green.shade300 : Colors.orange.shade300,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isSmartSystem ? Icons.smart_toy : Icons.settings,
                color: isSmartSystem ? Colors.green.shade700 : Colors.orange.shade700,
                size: 28,
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
                        color: isSmartSystem ? Colors.green.shade700 : Colors.orange.shade700,
                      ),
                    ),
                    Text(
                      scenario['description'],
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('運行時間', style: TextStyle(fontSize: 14)),
              Text('${scenario['duration']} 分鐘', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '耗電量',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                '${_safeParseDouble(scenario['totalEnergy']).toStringAsFixed(1)} Wh',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isSmartSystem ? Colors.green.shade700 : Colors.orange.shade700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRealSavingsCard(Map<String, dynamic> comparison) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: Colors.green.shade600,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.bolt, color: Colors.white, size: 48),
          const SizedBox(height: 12),
          Text(
            '單次使用節省',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${comparison['savingsPercent']}%',
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          Text(
            '節省 ${comparison['energySavedPerUse']} Wh',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProjectionsCard(Map<String, dynamic> projections) {
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
            '長期節能預估',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildProjectionRow('每日', projections['daily']),
          Divider(),
          _buildProjectionRow('每月', projections['monthly']),
          Divider(),
          _buildProjectionRow('每年', projections['yearly']),
        ],
      ),
    );
  }

  Widget _buildProjectionRow(String period, Map<String, dynamic> data) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            period,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${data['energy']} Wh',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
              Text(
                '節省 NT\$ ${data['cost']}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  

  // Tab 3: 歷史統計
  Widget _buildHistoryTab() {
    if (_historyData == null) {
      return const Center(child: Text('無數據'));
    }

    final dailyStats = _historyData!['dailyStats'] as List;
    final summary = _historyData!['summary'];

    return RefreshIndicator(
      onRefresh: _fetchHistoryData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 期間選擇
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '歷史節能記錄',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                DropdownButton<int>(
                  value: _historyDays,
                  items: [7, 14, 30].map((days) {
                    return DropdownMenuItem(
                      value: days,
                      child: Text('$days 天'),
                    );
                  }).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _historyDays = value;
                      });
                      _fetchHistoryData();
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 20),

            // 總結卡片
            _buildHistorySummaryCard(summary),
            const SizedBox(height: 20),

            // 每日趨勢圖
            _buildDailyTrendChart(dailyStats),
            const SizedBox(height: 20),

            // 每日詳細列表
            Text(
              '每日詳細記錄',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...dailyStats.map((day) => _buildDailyStatCard(day)).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyStatCard(Map<String, dynamic> day) {
  return Container(
    margin: const EdgeInsets.only(bottom: 12.0),
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
        // 日期標題
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _formatDate(day['date']),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${day['savingsPercent']}%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Divider(),
        const SizedBox(height: 8),
        
        // 實際耗電
        _buildStatRow(
          '實際耗電',
          '${day['actualEnergy']} Wh',
          Colors.blue.shade600,
        ),
        const SizedBox(height: 8),
        
        // 預估傳統耗電
        _buildStatRow(
          '傳統模式',
          '${day['estimatedTraditionalEnergy']} Wh',
          Colors.orange.shade600,
        ),
        const SizedBox(height: 8),
        
        // 節省電量
        _buildStatRow(
          '節省電量',
          '${day['energySaved']} Wh',
          Colors.green.shade600,
        ),
        
        // 預估在室時間
        if (day['estimatedOccupiedHours'] != null) ...[
          const SizedBox(height: 8),
          _buildStatRow(
            '預估在室時間',
            '${day['estimatedOccupiedHours']} 小時',
            Colors.grey.shade600,
          ),
        ],
      ],
    ),
  );
}

Widget _buildStatRow(String label, String value, Color color) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey.shade700,
        ),
      ),
      Text(
        value,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    ],
  );
}

  Widget _buildHistorySummaryCard(Map<String, dynamic> summary) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade600, Colors.blue.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            '累計節能效益',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryItem(
                '總節省',
                '${summary['totalEnergySaved']} Wh',
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.white.withOpacity(0.3),
              ),
              _buildSummaryItem(
                '節省金額',
                'NT\$ ${summary['totalCostSaved']}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '平均每日: ${(_safeParseDouble(summary['totalEnergySaved']) / _historyDays).toStringAsFixed(1)} Wh',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String title, String value) {
    return Column(
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 14,
            color: Colors.white.withOpacity(0.9),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _buildDailyTrendChart(List dailyStats) {
  if (dailyStats.isEmpty) {
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
      child: const Center(
        child: Text('無數據可顯示'),
      ),
    );
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
        Text(
          '每日節省趨勢 (Wh)',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(show: true),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      if (value.toInt() >= 0 && value.toInt() < dailyStats.length) {
                        final date = dailyStats[value.toInt()]['date'].toString();
                        return Text(
                          date.substring(5, 10),
                          style: TextStyle(fontSize: 10),
                        );
                      }
                      return const Text('');
                    },
                    reservedSize: 30,
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 40),
                ),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: dailyStats.asMap().entries.map((entry) {
                    return FlSpot(
                      entry.key.toDouble(),
                      _safeParseDouble(entry.value['energySaved']), // ✅ Fixed
                    );
                  }).toList(),
                  isCurved: true,
                  color: Colors.green.shade400,
                  barWidth: 3,
                  dotData: FlDotData(show: true),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
}