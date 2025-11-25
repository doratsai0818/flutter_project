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
  Map<String, dynamic>? _realComparisonData;
  
  bool _isLoading = true;
  String? _errorMessage;

  String _currentTestMode = 'manual';
  bool _isTestingMode = false;

  // ✅ 只保留實際使用的輔助函數
  double _safeParseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  // ❌ 刪除未使用的函數
  // int _safeParseInt(dynamic value) { ... }
  // String _formatDate(dynamic date) { ... }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
          _currentTestMode = data['data']['currentMode'] ?? 'manual'; // ✅ 新增這行
        });
      }
    }
  } catch (e) {
    print('獲取實際比較數據失敗: $e');
  }
}

// ✅ 修復後的測試模式切換函數
  Future<void> _switchTestMode(String mode) async {
    setState(() {
      _isTestingMode = true;
    });

    try {
      final response = await ApiService.post(
        '/energy-efficiency/test-mode',
        {'mode': mode},  // ✅ 修復:直接傳遞 Map
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
              setState(() {
            _currentTestMode = mode; // ✅ 立即更新 UI
        });
          await _fetchRealComparisonData();
          
          if (mounted) {  // ✅ 添加 mounted 檢查
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(data['message']),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 2),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {  // ✅ 添加 mounted 檢查
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('切換模式失敗: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {  // ✅ 添加 mounted 檢查
        setState(() {
          _isTestingMode = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // TabBar - 只有兩個分頁
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.green[700]!,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.green[700]!,
              tabs: const [
                Tab(icon: Icon(Icons.science), text: '模擬比較'),
                Tab(icon: Icon(Icons.compare_arrows), text: '實際對比'),
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

    return RefreshIndicator(
      onRefresh: _fetchSimulationData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
  // ✅ 修復所有顏色使用
  Widget _buildScenarioCard(Map<String, dynamic> scenario, bool isOurSystem, int number) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: isOurSystem ? Colors.green[50] : Colors.grey[100],  // ✅ 修復
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOurSystem ? Colors.green[300]! : Colors.grey[300]!,  // ✅ 修復
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
                        color: isOurSystem ? Colors.green[700] : Colors.black87,  // ✅ 修復
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
                Icon(Icons.stars, color: Colors.green[700], size: 28),  // ✅ 修復
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
  // ✅ 修復節省效益總結中的顏色
  Widget _buildSavingsSummary(Map<String, dynamic> comparison, List scenarios) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green[600]!, Colors.green[400]!],  // ✅ 修復
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.savings, color: Colors.white, size: 48),
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
                  '相較情境1',
                  '${comparison['savingsVsScenario1']}%',
                  '節省 ${comparison['energySavedVsScenario1']} Wh',
                ),
              ),
              Container(width: 1, height: 60, color: Colors.white.withOpacity(0.3)),
              Expanded(
                child: _buildSavingsItem(
                  '相較情境2',
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

  // Tab 2: 實際對比 (包含溫濕度資訊)
  Widget _buildRealComparisonTab() {
    if (_realComparisonData == null) {
      return const Center(child: Text('無數據'));
    }

    final scenarios = _realComparisonData!['scenarios'] as List;
    final comparison = _realComparisonData!['comparison'];
    final projections = comparison['projections'];
    final devicesPower = _realComparisonData!['devicesPower']; // ✅ 新增這行
    
    // 從模擬數據獲取環境資訊
    final environment = _simulationData?['currentEnvironment'];

    return RefreshIndicator(
      onRefresh: _fetchRealComparisonData,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ 當前環境條件卡片 (從模擬比較移過來)
            if (environment != null) _buildEnvironmentCard(environment),
            if (environment != null) const SizedBox(height: 20),

            // ✅ 新增:測試模式切換按鈕
            _buildTestModeSwitch(),
            const SizedBox(height: 20),

            // ✅ 新增:各設備即時功率顯示
            _buildDevicesPowerCard(devicesPower),
            const SizedBox(height: 20),

            // 情景說明
            Text(
              '10分鐘實際使用比較',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // 兩個情景對比
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

  // ✅ 修復實際場景卡片中的顏色
  Widget _buildRealScenarioCard(Map<String, dynamic> scenario, bool isSmartSystem) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: isSmartSystem ? Colors.green[50] : Colors.orange[50],  // ✅ 修復
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSmartSystem ? Colors.green[300]! : Colors.orange[300]!,  // ✅ 修復
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
                color: isSmartSystem ? Colors.green[700] : Colors.orange[700],  // ✅ 修復
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

          // ✅ 新增:顯示模式狀態
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('系統模式', style: TextStyle(fontSize: 14)),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: isSmartSystem ? Colors.green.shade100 : Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isSmartSystem ? '自動模式' : '手動模式',
                  style: TextStyle(
                    fontSize: 12, 
                    fontWeight: FontWeight.w600,
                    color: isSmartSystem ? Colors.green.shade700 : Colors.orange.shade700,
                  ),
                ),
              ),
            ],
          ),
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

  // ✅ 修復實際節省卡片
  Widget _buildRealSavingsCard(Map<String, dynamic> comparison) {
    return Container(
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: Colors.green[600],  // ✅ 修復
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.bolt, color: Colors.white, size: 48),
          const SizedBox(height: 12),
          const Text(
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
            style: const TextStyle(
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

  // ✅ 修復長期預估卡片中的顏色
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
          const Text(
            '長期節能預估',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildProjectionRow('每日', projections['daily']),
          const Divider(),
          _buildProjectionRow('每月', projections['monthly']),
          const Divider(),
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
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${data['energy']} Wh',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[700],  // ✅ 修復
                ),
              ),
              Text(
                '節省 NT\$ ${data['cost']}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ✅ 完整新增:測試模式切換開關
Widget _buildTestModeSwitch() {
  return Container(
    padding: const EdgeInsets.all(16.0),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.grey.shade300),
      boxShadow: [
        BoxShadow(
          color: Colors.grey.withOpacity(0.1),
          spreadRadius: 2,
          blurRadius: 5,
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.science, color: Colors.purple.shade700, size: 24),
            const SizedBox(width: 8),
            Text(
              '測試模式選擇',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.purple.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '選擇要測試的使用模式,系統會根據模式顯示對應的設備功率',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 16),
        
        Row(
          children: [
            Expanded(
              child: _buildModeButton(
                '傳統模式',
                'manual',
                Icons.settings,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildModeButton(
                '智慧系統',
                'auto',
                Icons.smart_toy,
                Colors.green,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

// ✅ 完整新增:模式按鈕
Widget _buildModeButton(String label, String mode, IconData icon, Color color) {
  final isSelected = _currentTestMode == mode;
  
  return ElevatedButton(
    onPressed: _isTestingMode ? null : () => _switchTestMode(mode),
    style: ElevatedButton.styleFrom(
      backgroundColor: isSelected ? color : Colors.white,
      foregroundColor: isSelected ? Colors.white : color,
      padding: EdgeInsets.symmetric(vertical: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: color, width: 2),
      ),
      elevation: isSelected ? 4 : 0,
    ),
    child: _isTestingMode && isSelected
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(
                isSelected ? Colors.white : color,
              ),
            ),
          )
        : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
  );
}

// ✅ 完整新增:設備即時功率卡片
Widget _buildDevicesPowerCard(Map<String, dynamic> devicesPower) {
  return Container(
    padding: const EdgeInsets.all(16.0),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [Colors.blue.shade50, Colors.blue.shade100],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.blue.shade300),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.flash_on, color: Colors.blue.shade700, size: 24),
            const SizedBox(width: 8),
            Text(
              '各設備即時功率',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        
        // ✅ 門口燈泡功率
        _buildPowerItem(
          '門口燈泡',
          devicesPower['light1'],
          Icons.lightbulb_outline,
          Colors.amber,
        ),
        const SizedBox(height: 8),
        
        // ✅ 冷氣功率
        _buildPowerItem(
          '冷氣',
          devicesPower['acPower'],
          Icons.ac_unit,
          Colors.blue,
        ),
        const SizedBox(height: 8),
        
        // ✅ 燈泡功率
        _buildPowerItem(
          '燈泡',
          devicesPower['light2'],
          Icons.lightbulb,
          Colors.amber,
        ),
        const SizedBox(height: 8),
        
        // ✅ 風扇功率
        _buildPowerItem(
          '風扇',
          devicesPower['fanPower'],
          Icons.mode_fan_off,
          Colors.cyan,
        ),
        
        const SizedBox(height: 12),
        Divider(),
        const SizedBox(height: 8),
        
        // ✅ 總功率
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '總功率',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade900,
              ),
            ),
            Text(
              '${_safeParseDouble(devicesPower['totalPower']).toStringAsFixed(1)} W',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.blue.shade900,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

// ✅ 完整新增:單個設備功率項目
Widget _buildPowerItem(String label, dynamic power, IconData icon, Color color) {
  return Row(
    children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          label,
          style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
        ),
      ),
      Text(
        '${_safeParseDouble(power).toStringAsFixed(1)} W',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color, 
        ),
      ),
    ],
  );
}
}