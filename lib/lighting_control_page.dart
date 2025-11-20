// lib/wiz_light_control_page.dart

import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:iot_project/main.dart';

class LightingControlPage extends StatefulWidget {
  const LightingControlPage({super.key});

  @override
  State<LightingControlPage> createState() => _LightingControlPage();
}

class _LightingControlPage extends State<LightingControlPage> {
  // 燈泡狀態
  List<LightState> _lights = [
    LightState(name: '燈泡door', ip: '192.168.98.57'),
    LightState(name: '燈泡pc', ip: '192.168.98.58'),
  ];

  String? _activeScene;
  bool _isLoading = true;
  bool _isManualMode = false;
  Timer? _refreshTimer;
  Timer? _debounceTimer;
  
  // ✨ 新增:追蹤是否正在手動控制
  bool _isManualControlling = false;
  DateTime? _lastManualControl;

  // 情境配置
  final List<SceneConfig> _scenes = [
    SceneConfig(
      id: 'daily',
      name: '日常情境',
      description: '根據時間自動調整',
      icon: Icons.wb_sunny,
      color: Colors.orange,
    ),
    SceneConfig(
      id: 'christmas',
      name: '聖誕節',
      description: '紅綠白交替閃爍',
      icon: Icons.celebration,
      color: Colors.red,
    ),
    SceneConfig(
      id: 'party',
      name: '派對',
      description: '多彩快速變換',
      icon: Icons.party_mode,
      color: Colors.purple,
    ),
    SceneConfig(
      id: 'halloween',
      name: '萬聖節',
      description: '橙紫神秘氛圍',
      icon: Icons.nightlight,
      color: Colors.deepOrange,
    ),
  ];

  // 預設色彩選項 
  final List<ColorOption> _colorPresets = [
    ColorOption(name: '紅色', r: 255, g: 0, b: 0),
    ColorOption(name: '橙色', r: 255, g: 165, b: 0),
    ColorOption(name: '黃色', r: 255, g: 255, b: 0),
    ColorOption(name: '綠色', r: 0, g: 255, b: 0),
    ColorOption(name: '青色', r: 0, g: 255, b: 255),
    ColorOption(name: '藍色', r: 0, g: 0, b: 255),
    ColorOption(name: '紫色', r: 128, g: 0, b: 128),
    ColorOption(name: '粉色', r: 255, g: 192, b: 203),
  ];

  @override
  void initState() {
    super.initState();
    _initializePage();
  }
  
  Future<void> _initializePage() async {
    // 設置初始超時時間
    try {
      await _fetchLightStatus().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          // 超時後仍然顯示頁面,但標記所有燈泡為離線
          if (mounted) {
            setState(() {
              for (var light in _lights) {
                light.error = '連線超時,請檢查網路或伺服器狀態';
                light.isOn = false;
              }
              _isLoading = false;
            });
          }
        },
      );
    } catch (e) {
      print('初始化失敗: $e');
      if (mounted) {
        setState(() {
          for (var light in _lights) {
            light.error = '無法連接至伺服器';
            light.isOn = false;
          }
          _isLoading = false;
        });
      }
    }
    
    // 啟動自動刷新(即使初始化失敗也要啟動,以便後續自動重連)
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      // 只在非載入狀態時才自動刷新
      if (!_isLoading) {
        _fetchLightStatus();
      }
    });
  }

  Future<void> _fetchLightStatus() async {
    // ✨ 如果正在手動控制,跳過此次更新
    if (_isManualControlling) {
      print('⏸️ 手動控制中,跳過狀態更新');
      return;
    }
    
    // ✨ 如果最近 4 秒內有手動控制,也跳過
    if (_lastManualControl != null && 
        DateTime.now().difference(_lastManualControl!) < const Duration(seconds: 4)) {
      print('⏸️ 手動控制後緩衝期,跳過狀態更新');
      return;
    }

    try {
      final response = await ApiService.get('/wiz-lights/status').timeout(
        const Duration(seconds: 3),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            if (data['lights'] != null) {
              for (int i = 0; i < _lights.length && i < data['lights'].length; i++) {
                final lightData = data['lights'][i];
                
                // ✨ 檢查燈泡是否有錯誤(離線)
                if (lightData['error'] != null) {
                  _lights[i].error = lightData['error'];
                  _lights[i].isOn = false;
                } else {
                  _lights[i].error = null;
                  _lights[i].isOn = lightData['isOn'] ?? false;
                  
                  // 確保 temp 值在有效範圍內 (2200-6500)
                  double tempValue = (lightData['temp'] ?? 4000).toDouble();
                  if (tempValue == 0) tempValue = 4000; // 關閉時預設值
                  if (tempValue < 2200) tempValue = 2200;
                  if (tempValue > 6500) tempValue = 6500;
                  _lights[i].temp = tempValue;
                  
                  // 確保 dimming 值在有效範圍內
                  double dimmingValue = (lightData['dimming'] ?? 50).toDouble();
                  if (dimmingValue < 10) dimmingValue = 10;
                  if (dimmingValue > 100) dimmingValue = 100;
                  _lights[i].dimming = dimmingValue;
                  
                  // RGB 值
                  _lights[i].r = (lightData['r'] ?? 255);
                  _lights[i].g = (lightData['g'] ?? 255);
                  _lights[i].b = (lightData['b'] ?? 255);
                  
                  // ✨ 讀取燈光模式
                  _lights[i].lightMode = lightData['lightMode'] ?? 'white';
                }
              }
            }
            _activeScene = data['activeScene'];
            _isManualMode = _activeScene == null;
            _isLoading = false;
          });
        }
      } else {
        // HTTP 錯誤狀態碼
        if (mounted) {
          setState(() {
            for (var light in _lights) {
              light.error = '伺服器回應錯誤 (${response.statusCode})';
              light.isOn = false;
            }
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      print('獲取燈泡狀態失敗: $e');
      if (mounted) {
        setState(() {
          // ✨ 即使發生錯誤也要顯示頁面,將所有燈泡標記為離線
          for (var light in _lights) {
            if (e.toString().contains('TimeoutException')) {
              light.error = '連線超時,請檢查網路';
            } else if (e.toString().contains('Failed to fetch')) {
              light.error = '無法連接到伺服器 (localhost:3000)';
            } else {
              light.error = '連線異常';
            }
            light.isOn = false;
          }
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _controlLight(int index, {double? temp, double? dimming, int? r, int? g, int? b}) async {
    try {
      final body = <String, dynamic>{
        'lightIndex': index,
      };
      if (temp != null) body['temp'] = temp.round();
      if (dimming != null) body['dimming'] = dimming.round();
      if (r != null) body['r'] = r;
      if (g != null) body['g'] = g;
      if (b != null) body['b'] = b;

      final response = await ApiService.post('/wiz-lights/control', body);

      if (response.statusCode == 200) {
        print('✅ 燈泡控制成功');
      } else {
        _showErrorSnackBar('控制失敗');
      }
    } catch (e) {
      print('控制燈泡錯誤: $e');
      _showErrorSnackBar('網路連線錯誤');
    }
  }

  Future<void> _toggleLightPower(int index) async {
    // 標記為手動控制中
    _isManualControlling = true;
    _lastManualControl = DateTime.now();
    
    try {
      final response = await ApiService.post('/wiz-lights/power', {
        'lightIndex': index,
        'isOn': !_lights[index].isOn,
      });

      if (response.statusCode == 200) {
        setState(() {
          _lights[index].isOn = !_lights[index].isOn;
        });
        _showSuccessSnackBar(_lights[index].isOn ? '已開啟' : '已關閉');
      }
    } catch (e) {
      _showErrorSnackBar('操作失敗');
    } finally {
      // ✨ 操作完成後,延遲 4 秒再允許狀態更新
      Future.delayed(const Duration(milliseconds: 4000), () {
        if (mounted) {
          _isManualControlling = false;
        }
      });
    }
  }

  // ✨ 新增:模式切換函數
  Future<void> _switchLightMode(int lightIndex, String newMode) async {
    _isManualControlling = true;
    _lastManualControl = DateTime.now();
    
    setState(() {
      _lights[lightIndex].lightMode = newMode;
    });
    
    try {
      if (newMode == 'white') {
        // 切換到白光模式:設定 RGB = (255, 255, 255) 並使用預設色溫
        await _controlLight(lightIndex, temp: 4000, r: 255, g: 255, b: 255);
        setState(() {
          _lights[lightIndex].r = 255;
          _lights[lightIndex].g = 255;
          _lights[lightIndex].b = 255;
          _lights[lightIndex].temp = 4000;
        });
      } else {
        // 切換到彩光模式:設定一個預設顏色(紅色)
        await _controlLight(lightIndex, r: 255, g: 0, b: 0);
        setState(() {
          _lights[lightIndex].r = 255;
          _lights[lightIndex].g = 0;
          _lights[lightIndex].b = 0;
        });
      }
      
      _showSuccessSnackBar('已切換至${newMode == 'white' ? '白光' : '彩光'}模式');
    } catch (e) {
      _showErrorSnackBar('切換模式失敗');
    } finally {
      Future.delayed(const Duration(milliseconds: 4000), () {
        if (mounted) {
          _isManualControlling = false;
        }
      });
    }
  }

  Future<void> _setScene(String sceneId) async {
    try {
      final response = await ApiService.post('/wiz-lights/scene', {
        'scene': sceneId,
      });

      if (response.statusCode == 200) {
        setState(() {
          _activeScene = sceneId;
          _isManualMode = false;
        });
        final sceneName = _scenes.firstWhere((s) => s.id == sceneId).name;
        _showSuccessSnackBar('已啟動$sceneName');
        await _fetchLightStatus();
      }
    } catch (e) {
      _showErrorSnackBar('設定情境失敗');
    }
  }

  Future<void> _stopScene() async {
    try {
      final response = await ApiService.post('/wiz-lights/scene/stop', {});

      if (response.statusCode == 200) {
        setState(() {
          _activeScene = null;
          _isManualMode = true;
        });
        _showSuccessSnackBar('已停止情境模式');
      }
    } catch (e) {
      _showErrorSnackBar('停止失敗');
    }
  }

  Future<void> _updateManualMode(bool value) async {
    if (value) {
      // 切換到手動模式,停止情境
      await _stopScene();
    }
    setState(() {
      _isManualMode = value;
    });
  }

  void Function(double) _createDebouncedHandler(
    int lightIndex,
    String type,
    void Function(double) updateState,
  ) {
    return (value) {
      // 標記為手動控制中
      _isManualControlling = true;
      _lastManualControl = DateTime.now();
      
      updateState(value);
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
        if (type == 'temp') {
          await _controlLight(lightIndex, temp: value);
        } else if (type == 'dimming') {
          await _controlLight(lightIndex, dimming: value);
        }
        
        // ✨ 指令發送完成後,延遲 4 秒再允許狀態更新
        Future.delayed(const Duration(milliseconds: 4000), () {
          if (mounted) {
            _isManualControlling = false;
          }
        });
      });
    };
  }

  // 設定預設顏色
  void _setPresetColor(int lightIndex, ColorOption color) {
    // 標記為手動控制中
    _isManualControlling = true;
    _lastManualControl = DateTime.now();
    
    setState(() {
      _lights[lightIndex].r = color.r;
      _lights[lightIndex].g = color.g;
      _lights[lightIndex].b = color.b;
      _lights[lightIndex].lightMode = 'rgb'; // ✨ 自動切換到彩光模式
    });
    
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () async {
      await _controlLight(lightIndex, r: color.r, g: color.g, b: color.b);
      
      // ✨ 指令發送完成後,延遲 4 秒再允許狀態更新
      Future.delayed(const Duration(milliseconds: 4000), () {
        if (mounted) {
          _isManualControlling = false;
        }
      });
    });
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('載入燈光設定中...', style: TextStyle(fontSize: 16)),
          ],
        ),
      );
    }

    // ✨ 檢查是否所有燈泡都離線
    final bool allLightsOffline = _lights.every((light) => light.error != null);

    return RefreshIndicator(
      onRefresh: _fetchLightStatus,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 頂部圖標
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 150,
                    color: Theme.of(context).primaryColor,
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),

            // 模式控制
            _buildModeControl(allLightsOffline),
            const SizedBox(height: 32),

            // 各區燈光顯示
            const Text(
              '各區燈光顯示',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // 燈泡 A (fang)
            _buildLightControlCard(
              context,
              index: 0,
              light: _lights[0],
              area: 'A',
            ),
            const SizedBox(height: 16),

            // 燈泡 B (yaa)
            _buildLightControlCard(
              context,
              index: 1,
              light: _lights[1],
              area: 'B',
            ),
            const SizedBox(height: 32),

            // 燈光情境
            _buildSceneSection(allLightsOffline),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildModeControl(bool allLightsOffline) {
    return Container(
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
          // ✨ 全部離線時顯示警告
          if (allLightsOffline) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: Colors.red[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '所有燈泡離線，模式控制已禁用',
                      style: TextStyle(
                        color: Colors.red[700],
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '模式控制',
                style: TextStyle(
                  fontSize: 20, 
                  fontWeight: FontWeight.bold,
                  color: allLightsOffline ? Colors.grey : Colors.black87,
                ),
              ),
              Row(
                children: [
                  Text(
                    '自動',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: allLightsOffline 
                          ? Colors.grey 
                          : (!_isManualMode ? Theme.of(context).primaryColor : Colors.grey),
                    ),
                  ),
                  Switch(
                    value: _isManualMode,
                    // ✨ 全部離線時禁用開關
                    onChanged: allLightsOffline ? null : _updateManualMode,
                    activeColor: Theme.of(context).primaryColor,
                  ),
                  Text(
                    '手動',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: allLightsOffline 
                          ? Colors.grey 
                          : (_isManualMode ? Theme.of(context).primaryColor : Colors.grey),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLightControlCard(
    BuildContext context, {
    required int index,
    required LightState light,
    required String area,
  }) {
    // ✨ 檢查裝置是否離線
    final bool isOffline = light.error != null;
    
    // ✨ 離線時所有控制都禁用
    final Color sliderActiveColor = (_isManualMode && !isOffline)
        ? Theme.of(context).primaryColor 
        : Colors.grey;
    final Color sliderInactiveColor = (_isManualMode && !isOffline)
        ? Colors.grey[300]! 
        : Colors.grey[200]!;
    final Color textColor = (_isManualMode && !isOffline) ? Colors.black87 : Colors.grey;

    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 錯誤訊息 - 裝置離線時顯示在最上方
          if (light.error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_off, color: Colors.red[700], size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '裝置離線',
                          style: TextStyle(
                            color: Colors.red[700],
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          light.error!,
                          style: TextStyle(
                            color: Colors.red[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          
          Row(
            children: [
              // 區域標識和開關
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: light.isOn
                      ? Colors.amber.withOpacity(0.3)
                      : Colors.grey.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      area,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: light.isOn 
                            ? Theme.of(context).primaryColor 
                            : Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      // ✨ 離線時禁用開關
                      onTap: (_isManualMode && !isOffline) ? () => _toggleLightPower(index) : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: light.isOn ? Colors.green : Colors.grey,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          light.isOn ? 'ON' : 'OFF',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              
              // 控制滑桿
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 亮度控制
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '實時亮度', 
                          style: TextStyle(fontSize: 16, color: textColor),
                        ),
                        Text(
                          '${light.dimming.round()}%',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    _buildSlider(
                      value: light.dimming.clamp(10, 100),
                      min: 10,
                      max: 100,
                      divisions: 90,
                      // ✨ 離線時禁用滑桿
                      onChanged: (_isManualMode && !isOffline)
                          ? _createDebouncedHandler(
                              index,
                              'dimming',
                              (value) => setState(() => light.dimming = value.clamp(10, 100)),
                            )
                          : null,
                      activeColor: sliderActiveColor,
                      inactiveColor: sliderInactiveColor,
                    ),
                  ],
                ),
              ),
            ],
          ),
          
          // ✨ 手動模式下的燈光模式選擇和控制
          if (_isManualMode && !isOffline) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 12),
            
            // 模式選擇器
            Row(
              children: [
                Text(
                  '燈光模式',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'white',
                        label: Text('白光', style: TextStyle(fontSize: 12)),
                        icon: Icon(Icons.wb_sunny, size: 16),
                      ),
                      ButtonSegment(
                        value: 'rgb',
                        label: Text('彩光', style: TextStyle(fontSize: 12)),
                        icon: Icon(Icons.palette, size: 16),
                      ),
                    ],
                    selected: {light.lightMode},
                    onSelectionChanged: (Set<String> newSelection) {
                      _switchLightMode(index, newSelection.first);
                    },
                    style: ButtonStyle(
                      backgroundColor: MaterialStateProperty.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return Theme.of(context).primaryColor.withOpacity(0.2);
                        }
                        return Colors.grey[100];
                      }),
                      foregroundColor: MaterialStateProperty.resolveWith((states) {
                        if (states.contains(MaterialState.selected)) {
                          return Theme.of(context).primaryColor;
                        }
                        return Colors.grey[600];
                      }),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // 根據模式顯示對應控制
            if (light.lightMode == 'white') ...[
              // 白光模式:顯示色溫控制
              Text(
                '色溫調整',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Icons.wb_sunny, size: 14, color: Colors.orange),
                      const SizedBox(width: 4),
                      Text('暖光', style: TextStyle(fontSize: 12, color: Colors.orange)),
                    ],
                  ),
                  Text(
                    '${light.temp.round()}K',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Row(
                    children: [
                      Text('冷光', style: TextStyle(fontSize: 12, color: Colors.blue[700])),
                      const SizedBox(width: 4),
                      Icon(Icons.ac_unit, size: 14, color: Colors.blue[700]),
                    ],
                  ),
                ],
              ),
              _buildSlider(
                value: light.temp.clamp(2200, 6500),
                min: 2200,
                max: 6500,
                divisions: 43,
                onChanged: _createDebouncedHandler(
                  index,
                  'temp',
                  (value) => setState(() => light.temp = value.clamp(2200, 6500)),
                ),
                activeColor: sliderActiveColor,
                inactiveColor: sliderInactiveColor,
              ),
            ] else ...[
              // 彩光模式:顯示 RGB 色彩選擇器
              Text(
                'RGB 色彩選擇',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _colorPresets.map((colorOption) {
                  final isSelected = light.r == colorOption.r && 
                                     light.g == colorOption.g && 
                                     light.b == colorOption.b;
                  
                  return GestureDetector(
                    // ✨ 離線時禁用顏色選擇
                    onTap: !isOffline ? () => _setPresetColor(index, colorOption) : null,
                    child: Opacity(
                      // ✨ 離線時降低透明度
                      opacity: isOffline ? 0.4 : 1.0,
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: Color.fromRGBO(colorOption.r, colorOption.g, colorOption.b, 1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? Colors.blue : Colors.grey[300]!,
                            width: isSelected ? 3 : 1,
                          ),
                          boxShadow: isSelected ? [
                            BoxShadow(
                              color: Colors.blue.withOpacity(0.3),
                              blurRadius: 8,
                              spreadRadius: 2,
                            ),
                          ] : null,
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 24,
                                shadows: [
                                  Shadow(
                                    offset: Offset(1, 1),
                                    blurRadius: 3,
                                    color: Colors.black,
                                  ),
                                ],
                              )
                            : null,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
          
          // 自動模式提示 或 離線時的操作禁用提示
          if (!_isManualMode) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.auto_awesome, size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _activeScene != null 
                          ? '${_scenes.firstWhere((s) => s.id == _activeScene).name}模式運行中'
                          : '自動模式 - 系統智慧調節中',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (isOffline) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.block, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '裝置離線 - 所有控制功能已禁用',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSlider({
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double>? onChanged,
    required Color activeColor,
    required Color inactiveColor,
  }) {
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 4,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
        activeTrackColor: activeColor,
        inactiveTrackColor: inactiveColor,
        thumbColor: activeColor,
        overlayColor: activeColor.withOpacity(0.2),
      ),
      child: Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildSceneSection(bool allLightsOffline) {
    return Container(
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '燈光情境',
                style: TextStyle(
                  fontSize: 20, 
                  fontWeight: FontWeight.bold,
                  color: allLightsOffline ? Colors.grey : Colors.black87,
                ),
              ),
              // ✨ 顯示當前情境狀態
              if (_activeScene != null && !allLightsOffline)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green[300]!),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 14, color: Colors.green[700]),
                      const SizedBox(width: 4),
                      Text(
                        '運行中',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          // ✨ 全部離線時顯示警告
          if (allLightsOffline) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.block, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '所有燈泡離線，情境功能已禁用',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.5,
            ),
            itemCount: _scenes.length,
            itemBuilder: (context, index) {
              final scene = _scenes[index];
              final isActive = _activeScene == scene.id;

              return InkWell(
                // ✨ 修改點擊邏輯：如果已啟動則關閉，否則啟動
                onTap: allLightsOffline 
                    ? null 
                    : () {
                        if (isActive) {
                          // 已啟動，點擊關閉
                          _stopScene();
                        } else {
                          // 未啟動，點擊啟動
                          _setScene(scene.id);
                        }
                      },
                borderRadius: BorderRadius.circular(12),
                child: Opacity(
                  // ✨ 全部離線時降低透明度
                  opacity: allLightsOffline ? 0.4 : 1.0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: isActive ? scene.color.withOpacity(0.2) : Colors.grey[100],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isActive ? scene.color : Colors.grey[300]!,
                        width: isActive ? 2 : 1,
                      ),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          scene.icon,
                          size: 32,
                          color: isActive ? scene.color : Colors.grey[600],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          scene.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                            color: isActive ? scene.color : Colors.black87,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          scene.description,
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        // ✨ 已啟動時顯示提示
                        if (isActive) ...[
                          const SizedBox(height: 4),
                          Text(
                            '點擊關閉',
                            style: TextStyle(
                              fontSize: 8,
                              color: scene.color,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ✨ 修改 LightState 類別,新增 lightMode 屬性
class LightState {
  final String name;
  final String ip;
  bool isOn;
  double temp;
  double dimming;
  int r;
  int g;
  int b;
  String? error;
  String lightMode; // ✨ 新增:記錄當前模式 ('white' 或 'rgb')

  LightState({
    required this.name,
    required this.ip,
    this.isOn = false,
    this.temp = 4000,
    this.dimming = 50,
    this.r = 255,
    this.g = 255,
    this.b = 255,
    this.error,
    this.lightMode = 'white', // ✨ 預設為白光模式
  });
}

class SceneConfig {
  final String id;
  final String name;
  final String description;
  final IconData icon;
  final Color color;

  SceneConfig({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.color,
  });
}

class ColorOption {
  final String name;
  final int r;
  final int g;
  final int b;

  ColorOption({
    required this.name,
    required this.r,
    required this.g,
    required this.b,
  });
}