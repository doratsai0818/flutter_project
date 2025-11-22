import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart'; // 用於圖表展示
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:iot_project/config.dart'; // 假定用於API_URL

class EnergyEfficiencyDemoPage extends StatefulWidget {
  final String jwtToken;
  const EnergyEfficiencyDemoPage({super.key, required this.jwtToken});

  @override
  State<EnergyEfficiencyDemoPage> createState() => _EnergyEfficiencyDemoPageState();
}

class _EnergyEfficiencyDemoPageState extends State<EnergyEfficiencyDemoPage> {
  // 假定API地址
  final String _baseUrl = Config.apiUrl;
  bool _isLoading = true;
  Map<String, dynamic>? _comparisonData;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _fetchComparisonData();
  }

  // 步驟 1: 呼叫後端 API 取得比較數據
  Future<void> _fetchComparisonData() async {
    // ... (實作 HTTP GET 請求，參考 ac_control_page.dart.txt 中的模式) ...
    // 成功後將數據存入 _comparisonData
    // 為了示範，先使用假數據
    await Future.delayed(const Duration(seconds: 1)); 
    setState(() {
      _comparisonData = {
        "simulation": {
          "scenario1": { "name": "傳統開24-25°C", "kwh": 1.50, "time_ac": 60, "time_fan": 0, "time_light": 60 },
          "scenario2": { "name": "風扇輔助開26-27°C", "kwh": 0.90, "time_ac": 60, "time_fan": 60, "time_light": 60 },
          "scenario3_our_system": { "name": "我們的系統 (智慧感應)", "kwh": 0.65, "time_ac": 30, "time_fan": 5, "time_light": 5 }
        },
        "actual": {
          "scenario1": { "name": "傳統開25°C (無人續行)", "kwh": 0.25, "time_ac": 10, "time_fan": 10, "time_light": 10 },
          "scenario2_our_system": { "name": "我們的系統 (無人關閉)", "kwh": 0.15, "time_ac": 5, "time_fan": 5, "time_light": 5 }
        },
        "savings": {
          "simulation_savings_kwh": 0.85, 
          "actual_savings_kwh": 0.10,
          "simulation_savings_percent": 56.7
        }
      };
      _isLoading = false;
    });
  }
  
  // 步驟 2: 構建 UI 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _buildSystemOverviewCard(),
                  const SizedBox(height: 30),
                  // 第一種比較：模擬法 (1小時情境)
                  _buildSimulationComparisonSection(_comparisonData!['simulation'], _comparisonData!['savings']),
                  const SizedBox(height: 30),
                  // 第二種比較：實際情境 (10分鐘情境)
                  _buildActualComparisonSection(_comparisonData!['actual'], _comparisonData!['savings']),
                ],
              ),
            ),
    );
  }

  // 區域 1: 系統優勢概述
  Widget _buildSystemOverviewCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '🎯 我們的系統 (情境3) 節能原理',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo.shade800),
            ),
            const Divider(),
            const Text(
              '1. 提升冷氣設定溫度：搭配風扇輔助，冷氣只需要 26-27°C 即可達到 PMV≈0 的舒適度。',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              '2. 智慧感應關閉設備：系統感應無人時，冷氣在 30 分鐘後關閉，燈泡與風扇在 5 分鐘後關閉，避免空跑能耗。',
              style: TextStyle(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  // 區域 2: 模擬法比較 (1小時)
  Widget _buildSimulationComparisonSection(Map<String, dynamic> data, Map<String, dynamic> savings) {
    final s1_kwh = data['scenario1']['kwh'] as double;
    final s2_kwh = data['scenario2']['kwh'] as double;
    final s3_kwh = data['scenario3_our_system']['kwh'] as double;
    final savings_kwh = savings['simulation_savings_kwh'] as double;
    final savings_percent = savings['simulation_savings_percent'] as double;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '一、模擬法比較：1小時能耗 (kWh)',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(
          height: 250,
          child: BarChart(
            // 參考 power_monitoring_page.dart 中的 fl_chart 實作
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: s1_kwh * 1.2,
              titlesData: FlTitlesData(
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 30, getTitlesWidget: (value, meta) {
                      String title = '';
                      switch (value.toInt()) {
                        case 0: title = '情境1 (傳統)'; break;
                        case 1: title = '情境2 (風扇輔助)'; break;
                        case 2: title = '情境3 (智慧系統)'; break;
                      }
                      return SideTitleWidget(axisSide: meta.axisSide, child: Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)));
                    })),
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40, getTitlesWidget: (value, meta) => Text('${value.toStringAsFixed(1)}度', style: const TextStyle(fontSize: 10)))),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              barGroups: [
                BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: s1_kwh, color: Colors.redAccent)]),
                BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: s2_kwh, color: Colors.orange)]),
                BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: s3_kwh, color: Colors.green)]),
              ],
            ),
          ),
        ),
        Card(
          color: Colors.green.shade50,
          child: ListTile(
            leading: const Icon(Icons.flash_on, color: Colors.green, size: 30),
            title: const Text('節能總結 (情境3 vs. 情境1)', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              '智慧系統相較於傳統模式，節省了 ${savings_kwh.toStringAsFixed(2)} 度電 (${savings_percent.toStringAsFixed(1)}%)。',
              style: const TextStyle(color: Colors.green, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }

  // 區域 3: 實際情境比較 (10分鐘)
  Widget _buildActualComparisonSection(Map<String, dynamic> data, Map<String, dynamic> savings) {
    final s1_kwh = data['scenario1']['kwh'] as double;
    final s2_kwh = data['scenario2_our_system']['kwh'] as double;
    final savings_kwh = savings['actual_savings_kwh'] as double;
    final savings_percent = ((s1_kwh - s2_kwh) / s1_kwh) * 100;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '二、實際情境比較：10分鐘能耗 (無人離開)',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 15),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildConsumptionPill('傳統模式 (情境1)', s1_kwh, Colors.red.shade400, '運行10分鐘'),
            _buildConsumptionPill('智慧系統 (情境2)', s2_kwh, Colors.green.shade400, '運行5分鐘後全部關閉'),
          ],
        ),
        const SizedBox(height: 15),
        Card(
          color: Colors.green.shade50,
          child: ListTile(
            leading: const Icon(Icons.compare_arrows, color: Colors.green, size: 30),
            title: const Text('即時節能效益總結', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              '在人離開的 10 分鐘內，智慧系統節省了 ${savings_kwh.toStringAsFixed(2)} 度電 (${savings_percent.toStringAsFixed(1)}%)。',
              style: const TextStyle(color: Colors.green, fontSize: 16),
            ),
          ),
        ),
      ],
    );
  }

  // 輔助函式: 比較卡片
  Widget _buildConsumptionPill(String title, double kwh, Color color, String subtitle) {
    return Container(
      width: MediaQuery.of(context).size.width / 2 - 25,
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Column(
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 5),
          Text('${kwh.toStringAsFixed(2)} kWh', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
          const SizedBox(height: 5),
          Text(subtitle, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
        ],
      ),
    );
  }
}