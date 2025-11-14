// lib/home_page.dart

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:iot_project/main.dart'; // 引入 main.dart 以使用 ApiService

class HomePage extends StatefulWidget {
    const HomePage({super.key});

    @override
    State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
    // 一鍵切換
    String _selectedToggleMode = '...';
    
    // 概況總覽數據
    String _totalPowerToday = '...';
    String _currentTemperature = '...';
    String _currentHumidity = '...';
    String _acSetTemp = '(未設置)';
    String _fanSpeed = '(未設置)';

    // 裝置列表
    List<Map<String, dynamic>> _devices = [];
    
    // 載入狀態
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
            // 使用 ApiService 獲取一鍵切換模式
            final toggleResponse = await ApiService.get('/toggle-mode');
            if (toggleResponse.statusCode == 200) {
                final mode = json.decode(toggleResponse.body)['mode'];
                setState(() {
                    _selectedToggleMode = mode ?? '...';
                });
            } else {
                print('獲取切換模式失敗: ${toggleResponse.statusCode}');
            }

            // 獲取今日累積用電量
            final powerResponse = await ApiService.get('/power-total-today');
            if (powerResponse.statusCode == 200) {
                final data = json.decode(powerResponse.body);
                setState(() {
                    _totalPowerToday = data['total_kwh']?.toString() ?? '0.0';
                });
            } else {
                print('獲取用電量失敗: ${powerResponse.statusCode}');
            }

            // 獲取目前環境溫溼度
            final tempHumidityResponse = await ApiService.get('/temp-humidity/status');
            if (tempHumidityResponse.statusCode == 200) {
                final data = json.decode(tempHumidityResponse.body);
                if (data['success'] == true && data['data'] != null) {
                    setState(() {
                        _currentTemperature = data['data']['temperature_c']?.toString() ?? '...';
                        _currentHumidity = data['data']['humidity_percent']?.toString() ?? '...';
                    });
                }
            } else {
                print('獲取溫溼度失敗: ${tempHumidityResponse.statusCode}');
            }

            // 獲取冷氣設置溫度
            final acResponse = await ApiService.get('/ac/status');
            if (acResponse.statusCode == 200) {
                final data = json.decode(acResponse.body);
                final temp = data['current_set_temp'];
                setState(() {
                    _acSetTemp = temp != null ? '${temp}°C' : '(未設置)';
                });
            } else {
                print('獲取冷氣設置失敗: ${acResponse.statusCode}');
            }

            // 獲取風扇設置檔數
            final fanResponse = await ApiService.get('/fan/status');
            if (fanResponse.statusCode == 200) {
                final data = json.decode(fanResponse.body);
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
            } else {
                print('獲取風扇狀態失敗: ${fanResponse.statusCode}');
            }

            // 使用 ApiService 獲取裝置列表
            final devicesResponse = await ApiService.get('/devices');
            if (devicesResponse.statusCode == 200) {
                final List<dynamic> data = json.decode(devicesResponse.body);
                setState(() {
                    _devices = data.map((item) => {
                        'imagePath': 'assets/${item['id']}.png',
                        'title': item['name'] ?? '未知裝置',
                        'status': item['status'] ?? '未知狀態',
                    }).toList();
                });
            } else {
                print('獲取裝置列表失敗: ${devicesResponse.statusCode}');
                setState(() {
                    _devices = []; // 設置為空列表以避免顯示問題
                });
            }
        } catch (e) {
            print('Error fetching data: $e');
            _showErrorSnackBar('載入資料失敗,請檢查網路連線');
        } finally {
            setState(() {
                _isLoading = false;
            });
        }
    }

    Future<void> _updateToggleMode(String newMode) async {
        try {
            final response = await ApiService.post('/toggle-mode', {'mode': newMode});

            if (response.statusCode == 200) {
                setState(() {
                    _selectedToggleMode = newMode;
                });
                _showSuccessSnackBar('切換模式已更新為:$newMode');
            } else {
                final responseBody = json.decode(response.body);
                print('Failed to update toggle mode: ${responseBody['message']}');
                _showErrorSnackBar('更新切換模式失敗');
            }
        } catch (e) {
            print('Error updating toggle mode: $e');
            _showErrorSnackBar('網路連線錯誤,請稍後再試');
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

    void _showSuccessSnackBar(String message) {
        if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                    content: Text(message),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
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
                            // 一鍵切換區域
                            const Text(
                                '一鍵切換',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            Container(
                                padding: const EdgeInsets.all(4.0),
                                decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(30),
                                ),
                                child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                        _buildToggleButton(
                                            text: '智慧節能',
                                            isSelected: _selectedToggleMode == '智慧節能',
                                            onTap: () => _updateToggleMode('智慧節能'),
                                        ),
                                        _buildToggleButton(
                                            text: '手動設定',
                                            isSelected: _selectedToggleMode == '手動設定',
                                            onTap: () => _updateToggleMode('手動設定'),
                                        ),
                                        _buildToggleButton(
                                            text: '我的偏好',
                                            isSelected: _selectedToggleMode == '我的偏好',
                                            onTap: () => _updateToggleMode('我的偏好'),
                                        ),
                                    ],
                                ),
                            ),
                            const SizedBox(height: 32),

                            // 概況總覽區域
                            const Text(
                                '概況總覽',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            
                            // 第一行:今日累積用電量 & 目前環境溫溼度
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
                            
                            // 第二行:冷氣設置溫度 & 風扇設置檔數
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

                            // 裝置列表區域
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
                                            imagePath: device['imagePath'] as String,
                                            title: device['title'] as String,
                                            status: device['status'] as String,
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
                        '目前沒有裝置',
                        style: TextStyle(
                            fontSize: 18,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold,
                        ),
                    ),
                    SizedBox(height: 8),
                    Text(
                        '請添加智慧裝置以開始使用',
                        style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey,
                        ),
                    ),
                ],
            ),
        );
    }

    Widget _buildToggleButton({
        required String text,
        required bool isSelected,
        required VoidCallback onTap,
    }) {
        IconData icon = Icons.star;
        Color selectedColor = Theme.of(context).primaryColor;

        if (text == '智慧節能') {
            icon = Icons.bolt;
            selectedColor = Colors.green;
        } else if (text == '手動設定') {
            icon = Icons.build;
            selectedColor = Colors.orange;
        } else if (text == '我的偏好') {
            icon = Icons.favorite;
            selectedColor = Colors.blue;
        }

        return GestureDetector(
            onTap: onTap,
            child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                    color: isSelected
                        ? selectedColor.withOpacity(0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(30),
                ),
                child: Row(
                    children: [
                        Icon(
                            icon,
                            color: isSelected ? selectedColor : Colors.black54,
                            size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                            text,
                            style: TextStyle(
                                color: isSelected ? selectedColor : Colors.black54,
                                fontWeight: FontWeight.bold,
                            ),
                        ),
                    ],
                ),
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
        required String imagePath,
        required String title,
        required String status,
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
                    // 使用 Icon 替代 Image.asset 以避免資源文件問題
                    Icon(
                        _getDeviceIcon(title),
                        size: 60,
                        color: _getDeviceColor(status),
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

    IconData _getDeviceIcon(String deviceName) {
        if (deviceName.contains('冷氣') || deviceName.contains('AC')) {
            return Icons.ac_unit;
        } else if (deviceName.contains('燈') || deviceName.contains('Light')) {
            return Icons.lightbulb;
        } else if (deviceName.contains('插座') || deviceName.contains('Socket')) {
            return Icons.power;
        } else if (deviceName.contains('感測器') || deviceName.contains('Sensor')) {
            return Icons.sensors;
        } else {
            return Icons.device_unknown;
        }
    }

    Color _getDeviceColor(String status) {
        if (status.contains('開啟') || status.contains('Online')) {
            return Colors.green;
        } else if (status.contains('關閉') || status.contains('Offline')) {
            return Colors.grey;
        } else {
            return Colors.blue;
        }
    }

    Color _getStatusColor(String status) {
        if (status.contains('開啟') || status.contains('Online')) {
            return Colors.green;
        } else if (status.contains('關閉') || status.contains('Offline')) {
            return Colors.red;
        } else {
            return Colors.black54;
        }
    }
}