// lib/home_page.dart

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:iot_project/main.dart';
import 'dart:async';

class HomePage extends StatefulWidget {
    const HomePage({super.key});

    @override
    State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
    String _totalPowerToday = '...';
    String _currentTemperature = '...';
    String _currentHumidity = '...';
    String _acSetTemp = '(未設置)';
    String _fanSpeed = '(未設置)';

    List<Map<String, dynamic>> _devices = [];
    
    bool _isLoading = true;

    @override
    void initState() {
        super.initState();
        _fetchData();
    }

    Future<void> _fetchData() async {
        setState(() {
            _isLoading = true;
        });
        
        try {
            final results = await Future.wait([
                ApiService.get('/power-total-today'),
                ApiService.get('/temp-humidity/status'),
                ApiService.get('/ac/status'),
                ApiService.get('/fan/status'),
            ], eagerError: false).timeout(
                const Duration(seconds: 10),
                onTimeout: () => throw TimeoutException('請求超時', const Duration(seconds: 10))
            );

            if (results[0].statusCode == 200) {
                final data = json.decode(results[0].body);
                setState(() {
                    _totalPowerToday = data['total_kwh']?.toString() ?? '0.0';
                });
            }

            if (results[1].statusCode == 200) {
                final data = json.decode(results[1].body);
                if (data['success'] == true && data['data'] != null) {
                    setState(() {
                        _currentTemperature = data['data']['temperature_c']?.toString() ?? '...';
                        _currentHumidity = data['data']['humidity_percent']?.toString() ?? '...';
                    });
                }
            }

            if (results[2].statusCode == 200) {
                final data = json.decode(results[2].body);
                if (data['success'] == true && data['data'] != null) {
                    final temp = data['data']['current_set_temp'];
                    setState(() {
                        _acSetTemp = temp != null ? '${temp}°C' : '(未設置)';
                    });
                }
            }

            if (results[3].statusCode == 200) {
                final data = json.decode(results[3].body);
                if (data['success'] == true && data['data'] != null) {
                    final isOn = data['data']['isOn'] ?? false;
                    final speed = data['data']['speed'] ?? 0;
                    setState(() {
                        if (isOn && speed > 0) {
                            _fanSpeed = '第 $speed 檔';
                        } else {
                            _fanSpeed = '(未設置)';
                        }
                    });
                }
            }

            setState(() {
                _isLoading = false;
            });

            _fetchDevices();

        } on TimeoutException catch (e) {
            print('Request timeout: $e');
            setState(() {
                _isLoading = false;
            });
            _showErrorSnackBar('請求超時,請檢查網路連線');
        } catch (e) {
            print('Error fetching data: $e');
            setState(() {
                _isLoading = false;
            });
            _showErrorSnackBar('載入資料失敗: ${e.toString()}');
        }
    }

    Future<void> _fetchDevices() async {
    try {
        print('\n========== 開始載入裝置列表 ==========');
        List<Map<String, dynamic>> devicesList = [];
        
        // ✅ 使用 Set 來追蹤已添加的裝置 ID,避免重複
        Set<String> addedDeviceIds = {};

        // ==================== 1. 溫溼度感測器 ====================
        print('\n[1/3] 正在請求溫溼度感測器...');
        try {
            final tempResponse = await ApiService.get('/temp-humidity/status')
                .timeout(const Duration(seconds: 5));
            
            print('溫溼度感測器 HTTP 狀態碼: ${tempResponse.statusCode}');
            
            if (tempResponse.statusCode == 200) {
                final data = json.decode(tempResponse.body);
                print('溫溼度感測器回應: $data');
                
                // 🔥 修改：只要 API 成功就顯示（不檢查 success 和 data）
                final deviceId = 'temp_sensor';
                
                if (!addedDeviceIds.contains(deviceId)) {
                    print('✅ 溫溼度感測器 API 成功,新增到列表');
                    devicesList.add({
                        'id': deviceId,
                        'name': '溫溼度感測器',
                        'type': 'sensor',
                        'status': '線上',
                        'icon': Icons.sensors,
                        'color': Colors.green,
                    });
                    addedDeviceIds.add(deviceId);
                } else {
                    print('⚠️ 溫溼度感測器已存在,跳過重複添加');
                }
            } else {
                print('❌ 溫溼度感測器請求失敗: HTTP ${tempResponse.statusCode}');
            }
        } catch (e) {
            print('❌ 溫溼度感測器請求異常: $e');
        }

        // ==================== 2. Tuya 插座 ====================
        print('\n[2/3] 正在請求 Tuya 插座...');
        try {
            final plugResponse = await ApiService.get('/tuya-plugs/status')
                .timeout(const Duration(seconds: 5));
            
            print('Tuya 插座 HTTP 狀態碼: ${plugResponse.statusCode}');
            
            if (plugResponse.statusCode == 200) {
                final data = json.decode(plugResponse.body);
                print('Tuya 插座回應: $data');
                
                if (data['success'] == true && data['data'] != null) {
                    final List<dynamic> plugs = data['data'];
                    print('插座總數: ${plugs.length}');
                    
                    for (int i = 0; i < plugs.length; i++) {
                        final plug = plugs[i];
                        final plugName = plug['name'] ?? '插座${i + 1}';
                        final deviceId = 'plug_${i + 1}';
                        
                        // 🔥 關鍵：排除溫溼度感測器
                        if (plugName.contains('溫溼度') || plugName.contains('溫濕度')) {
                            print('  插座 ${i + 1}: $plugName - 跳過溫溼度感測器');
                            continue;
                        }
                        
                        print('  插座 ${i + 1}: $plugName');
                        
                        // 🔥 修改：只要有資料就顯示（不檢查 connected）
                        if (!addedDeviceIds.contains(deviceId)) {
                            print('  ✅ 插座資料存在,新增到列表');
                            devicesList.add({
                                'id': deviceId,
                                'name': plugName,
                                'type': 'plug',
                                'status': '線上',
                                'icon': Icons.power,
                                'color': Colors.green,
                            });
                            addedDeviceIds.add(deviceId);
                        } else {
                            print('  ⚠️ 已存在,跳過重複添加');
                        }
                    }
                } else {
                    print('⚠️ Tuya 插座回應格式錯誤');
                }
            } else {
                print('❌ Tuya 插座請求失敗: HTTP ${plugResponse.statusCode}');
            }
        } catch (e) {
            print('❌ Tuya 插座請求異常: $e');
        }

        // ==================== 3. WIZ 燈泡 ====================
        print('\n[3/3] 正在請求 WIZ 燈泡...');
        try {
            final lightResponse = await ApiService.get('/wiz-lights/status')
                .timeout(const Duration(seconds: 10));
            
            print('WIZ 燈泡 HTTP 狀態碼: ${lightResponse.statusCode}');
            
            if (lightResponse.statusCode == 200) {
                final data = json.decode(lightResponse.body);
                print('WIZ 燈泡回應: $data');
                
                if (data['success'] == true && data['lights'] != null) {
                    final List<dynamic> lights = data['lights'];
                    print('燈泡總數: ${lights.length}');
                    
                    for (int i = 0; i < lights.length; i++) {
                        final light = lights[i];
                        final hasError = light['error'] != null;
                        final isOn = light['isOn'] ?? false;
                        final deviceId = 'light_${i + 1}';
                        
                        print('  燈泡 ${i + 1}: ${light['name']} - isOn: $isOn, hasError: $hasError');
                        
                        // ✅ 檢查是否無錯誤且未重複添加
                        if (!hasError && !addedDeviceIds.contains(deviceId)) {
                            print('  ✅ 無錯誤,新增到列表');
                            devicesList.add({
                                'id': deviceId,
                                'name': light['name'] ?? '燈泡${i + 1}',
                                'type': 'light',
                                'status': isOn ? '開啟' : '關閉',
                                'icon': Icons.lightbulb,
                                'color': isOn ? Colors.amber : Colors.grey,
                            });
                            addedDeviceIds.add(deviceId);
                        } else if (hasError) {
                            print('  ⚠️ 有錯誤: ${light['error']},跳過');
                        } else {
                            print('  ⚠️ 已存在,跳過重複添加');
                        }
                    }
                } else {
                    print('⚠️ WIZ 燈泡不符合條件 (success=${data['success']}, lights=${data['lights']})');
                }
            } else {
                print('❌ WIZ 燈泡請求失敗: HTTP ${lightResponse.statusCode}');
            }
        } catch (e) {
            print('❌ WIZ 燈泡請求異常: $e');
        }

        // ==================== 結果 ====================
        print('\n========== 裝置載入完成 ==========');
        print('總共找到 ${devicesList.length} 個裝置 (已去除重複)');
        for (var device in devicesList) {
            print('  - ${device['name']} (${device['type']}) - ${device['status']}');
        }
        print('====================================\n');

        if (mounted) {
            setState(() {
                _devices = devicesList;
            });
        }

    } catch (e) {
        print('❌ 載入裝置時發生嚴重錯誤: $e');
        print('錯誤類型: ${e.runtimeType}');
        print('Stack trace: ${StackTrace.current}');
        
        if (mounted) {
            setState(() {
                _devices = [];
            });
            _showErrorSnackBar('載入裝置失敗: ${e.toString()}');
        }
    }
}

    void _showErrorSnackBar(String message) {
        if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(message),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 3),
                ),
            );
        }
    }

    Future<void> _refreshData() async {
        await _fetchData();
    }

    @override
    Widget build(BuildContext context) {
        final double cardGeneralWidth = (MediaQuery.of(context).size.width - 16 * 2 - 16) / 2;
        final double cardGeneralHeight = 150.0;

        return RefreshIndicator(
            onRefresh: _refreshData,
            child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: _isLoading 
                    ? _buildLoadingView()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            const Text(
                                '概況總覽',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            
                            Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                    _buildOverviewCard(
                                        width: cardGeneralWidth,
                                        height: cardGeneralHeight,
                                        children: [
                                            const Text(
                                                '今日累積用電量',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(fontSize: 14, color: Colors.black54),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                                _totalPowerToday,
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                    fontSize: 28,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.blue,
                                                ),
                                            ),
                                            const Text(
                                                'kWh',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(fontSize: 14, color: Colors.black54),
                                            ),
                                        ],
                                    ),
                                    _buildOverviewCard(
                                        width: cardGeneralWidth,
                                        height: cardGeneralHeight,
                                        children: [
                                            const Text(
                                                '目前環境溫溼度',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(fontSize: 14, color: Colors.black54),
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                    Icon(
                                                        Icons.thermostat,
                                                        size: 20,
                                                        color: Colors.orange,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                        _currentTemperature,
                                                        style: const TextStyle(
                                                            fontSize: 22,
                                                            fontWeight: FontWeight.bold,
                                                            color: Colors.orange,
                                                        ),
                                                    ),
                                                    const Text(
                                                        '°C',
                                                        style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.bold,
                                                            color: Colors.orange,
                                                        ),
                                                    ),
                                                ],
                                            ),
                                            const SizedBox(height: 4),
                                            Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                    Icon(
                                                        Icons.water_drop,
                                                        size: 20,
                                                        color: Colors.blueAccent,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                        _currentHumidity,
                                                        style: const TextStyle(
                                                            fontSize: 22,
                                                            fontWeight: FontWeight.bold,
                                                            color: Colors.blueAccent,
                                                        ),
                                                    ),
                                                    const Text(
                                                        '%',
                                                        style: TextStyle(
                                                            fontSize: 12,
                                                            fontWeight: FontWeight.bold,
                                                            color: Colors.blueAccent,
                                                        ),
                                                    ),
                                                ],
                                            ),
                                        ],
                                    ),
                                ],
                            ),
                            const SizedBox(height: 16),
                            
                            Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                    _buildOverviewCard(
                                        width: cardGeneralWidth,
                                        height: cardGeneralHeight,
                                        children: [
                                            const Text(
                                                '冷氣設置溫度',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(fontSize: 14, color: Colors.black54),
                                            ),
                                            const SizedBox(height: 8),
                                            Icon(
                                                Icons.ac_unit,
                                                size: 36,
                                                color: _acSetTemp == '(未設置)' ? Colors.grey : Colors.cyan,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                                _acSetTemp,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.bold,
                                                    color: _acSetTemp == '(未設置)' ? Colors.grey : Colors.cyan,
                                                ),
                                            ),
                                        ],
                                    ),
                                    _buildOverviewCard(
                                        width: cardGeneralWidth,
                                        height: cardGeneralHeight,
                                        children: [
                                            const Text(
                                                '風扇設置檔數',
                                                textAlign: TextAlign.center,
                                                style: TextStyle(fontSize: 14, color: Colors.black54),
                                            ),
                                            const SizedBox(height: 8),
                                            Icon(
                                                Icons.air,
                                                size: 36,
                                                color: _fanSpeed == '(未設置)' ? Colors.grey : Colors.teal,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                                _fanSpeed,
                                                textAlign: TextAlign.center,
                                                style: TextStyle(
                                                    fontSize: 20,
                                                    fontWeight: FontWeight.bold,
                                                    color: _fanSpeed == '(未設置)' ? Colors.grey : Colors.teal,
                                                ),
                                            ),
                                        ],
                                    ),
                                ],
                            ),
                            const SizedBox(height: 32),

                            Text(
                                '我的裝置(${_devices.length})',
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            _devices.isEmpty 
                                ? _buildEmptyDevicesView()
                                : Wrap(
                                    spacing: 16.0,
                                    runSpacing: 16.0,
                                    children: _devices.map((device) {
                                        return _buildDeviceCard(
                                            icon: device['icon'] as IconData,
                                            title: device['name'] as String,
                                            status: device['status'] as String,
                                            color: device['color'] as Color,
                                        );
                                    }).toList(),
                                ),
                            const SizedBox(height: 20),
                        ],
                    ),
            ),
        );
    }

    Widget _buildLoadingView() {
        return SizedBox(
            height: MediaQuery.of(context).size.height * 0.7,
            child: const Center(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text(
                            '載入中...',
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                    ],
                ),
            ),
        );
    }

    Widget _buildEmptyDevicesView() {
        return Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.grey[300]!),
            ),
            child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                    Icon(
                        Icons.devices_other,
                        size: 60,
                        color: Colors.grey,
                    ),
                    SizedBox(height: 16),
                    Text(
                        '目前沒有連線裝置',
                        style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                        ),
                    ),
                    SizedBox(height: 8),
                    Text(
                        '請確認裝置連線狀態',
                        style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                        ),
                    ),
                ],
            ),
        );
    }

    Widget _buildOverviewCard({
        required List<Widget> children,
        double? width,
        double? height,
    }) {
        return Container(
            width: width,
            height: height,
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
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: children,
            ),
        );
    }

    Widget _buildDeviceCard({
        required IconData icon,
        required String title,
        required String status,
        required Color color,
    }) {
        final double deviceCardWidth = (MediaQuery.of(context).size.width - 32 - 16) / 2;
        final double deviceCardHeight = 180.0;

        return Container(
            width: deviceCardWidth,
            height: deviceCardHeight,
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
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                    Icon(
                        icon,
                        size: 60,
                        color: color,
                    ),
                    const SizedBox(height: 10),
                    Text(
                        title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                        status,
                        style: TextStyle(
                            fontSize: 14,
                            color: _getStatusColor(status),
                            fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                    ),
                ],
            ),
        );
    }

    Color _getStatusColor(String status) {
        if (status.contains('開啟') || status.contains('線上')) {
            return Colors.green;
        } else if (status.contains('關閉')) {
            return Colors.grey;
        } else {
            return Colors.black54;
        }
    }
}