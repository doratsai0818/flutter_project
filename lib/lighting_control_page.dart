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
    LightState(name: '燈泡fang', ip: '192.168.1.108'),
    LightState(name: '燈泡yaa', ip: '192.168.1.109'),
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
    _fetchLightStatus();
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
      _fetchLightStatus();
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
      final response = await ApiService.get('/wiz-lights/status');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          if (data['lights'] != null) {
            for (int i = 0; i < _lights.length && i < data['lights'].length; i++) {
              final lightData = data['lights'][i];
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
              
              _lights[i].error = lightData['error'];
            }
          }
          _activeScene = data['activeScene'];
          _isManualMode = _activeScene == null;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('獲取燈泡狀態失敗: $e');
      if (mounted) {
        setState(() => _isLoading = false);
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
            _buildModeControl(),
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
            _buildSceneSection(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildModeControl() {
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
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            '模式控制',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Row(
            children: [
              Text(
                '自動',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: !_isManualMode ? Theme.of(context).primaryColor : Colors.grey,
                ),
              ),
              Switch(
                value: _isManualMode,
                onChanged: _updateManualMode,
                activeColor: Theme.of(context).primaryColor,
              ),
              Text(
                '手動',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: _isManualMode ? Theme.of(context).primaryColor : Colors.grey,
                ),
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
    final Color sliderActiveColor = _isManualMode 
        ? Theme.of(context).primaryColor 
        : Colors.grey;
    final Color sliderInactiveColor = _isManualMode 
        ? Colors.grey[300]! 
        : Colors.grey[200]!;
    final Color textColor = _isManualMode ? Colors.black87 : Colors.grey;

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
                      onTap: _isManualMode ? () => _toggleLightPower(index) : null,
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
                      onChanged: _isManualMode
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
          if (_isManualMode) ...[
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
                    onTap: () => _setPresetColor(index, colorOption),
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
                  );
                }).toList(),
              ),
            ],
          ],
          
          // 自動模式提示
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
          ],
          
          // 錯誤訊息
          if (light.error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red[700], size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      light.error!,
                      style: TextStyle(color: Colors.red[700], fontSize: 12),
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

  Widget _buildSceneSection() {
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
          const Text(
            '燈光情境',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
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
                onTap: () => _setScene(scene.id),
                borderRadius: BorderRadius.circular(12),
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
                    ],
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