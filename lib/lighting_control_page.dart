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
        print('燈泡控制成功');
      } else {
        _showErrorSnackBar('控制失敗');
      }
    } catch (e) {
      print('控制燈泡錯誤: $e');
      _showErrorSnackBar('網路連線錯誤');
    }
  }

  Future<void> _toggleLightPower(int index) async {
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
      updateState(value);
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        if (type == 'temp') {
          _controlLight(lightIndex, temp: value);
        } else if (type == 'dimming') {
          _controlLight(lightIndex, dimming: value);
        }
      });
    };
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
              
              // 控制滑塊
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '色溫', 
                          style: TextStyle(fontSize: 16, color: textColor),
                        ),
                        Text(
                          '${light.temp.round()}K',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                    _buildSlider(
                      value: light.temp.clamp(2200, 6500),
                      min: 2200,
                      max: 6500,
                      divisions: 43,
                      onChanged: _isManualMode
                          ? _createDebouncedHandler(
                              index,
                              'temp',
                              (value) => setState(() => light.temp = value.clamp(2200, 6500)),
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
          
          // RGB 控制區
          if (_isManualMode) ...[
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'RGB 色彩調整',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: textColor,
              ),
            ),
            const SizedBox(height: 12),
            _buildRGBSlider('紅', light.r.toDouble(), Colors.red, (value) {
              setState(() => light.r = value.round());
              _debounceTimer?.cancel();
              _debounceTimer = Timer(const Duration(milliseconds: 500), () {
                _controlLight(index, r: light.r, g: light.g, b: light.b);
              });
            }),
            _buildRGBSlider('綠', light.g.toDouble(), Colors.green, (value) {
              setState(() => light.g = value.round());
              _debounceTimer?.cancel();
              _debounceTimer = Timer(const Duration(milliseconds: 500), () {
                _controlLight(index, r: light.r, g: light.g, b: light.b);
              });
            }),
            _buildRGBSlider('藍', light.b.toDouble(), Colors.blue, (value) {
              setState(() => light.b = value.round());
              _debounceTimer?.cancel();
              _debounceTimer = Timer(const Duration(milliseconds: 500), () {
                _controlLight(index, r: light.r, g: light.g, b: light.b);
              });
            }),
            const SizedBox(height: 8),
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: Color.fromRGBO(light.r, light.g, light.b, 1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: const Center(
                child: Text(
                  '當前顏色預覽',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        offset: Offset(1, 1),
                        blurRadius: 3,
                        color: Colors.black,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          
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
                  Text(
                    light.error!,
                    style: TextStyle(color: Colors.red[700], fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRGBSlider(String label, double value, Color color, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                activeTrackColor: color,
                inactiveTrackColor: color.withOpacity(0.3),
                thumbColor: color,
              ),
              child: Slider(
                value: value,
                min: 0,
                max: 255,
                divisions: 255,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 35,
            child: Text(
              '${value.round()}',
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.right,
            ),
          ),
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