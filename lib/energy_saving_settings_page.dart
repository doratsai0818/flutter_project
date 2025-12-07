import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:async'; 
import 'package:iot_project/main.dart'; // 引入 main.dart 以使用 ApiService

// ----------------------------------------------------
// 1. 主要頁面 StateFul Widget
// ----------------------------------------------------

class EnergySavingSettingsPage extends StatefulWidget {
  const EnergySavingSettingsPage({super.key});

  @override
  State<EnergySavingSettingsPage> createState() =>
      _EnergySavingSettingsPageState();
}

// ----------------------------------------------------
// 2. State 類 (修正後)
// ----------------------------------------------------

class _EnergySavingSettingsPageState extends State<EnergySavingSettingsPage> {
  // 温濕度數據
  double _currentTemp = 0.0;
  double _currentHumidity = 0.0;

  bool _isMotionDetected = false;
  DateTime? _lastMotionUpdate; 

  // 節能設定選項
  double? _selectedActivityMet;
  String? _selectedActivityName; // ✨ 當前選中的活動名稱 (合併後的唯一名稱)
  List<String> _selectedClothingItems = [];
  
  // 設備狀態 (新增)
  bool _isAcOn = false;
  int _acSetTemp = 0;
  bool _isFanOn = false;
  int _fanSpeed = 0;
  double _pmvRaw = 0.0; 
  double _currentAirVelocity = 0.1;
  // ✨ 模型建議的目標狀態
  int _modelAcDelta = 0;
  int _modelFanLevel = 0;

  // 編輯模式的暫存變數
  double? _tempSelectedActivityMet;
  String? _tempSelectedActivityName; // ✨ 編輯模式的名稱暫存
  List<String> _tempSelectedClothingItems = [];

  // PMV 數據
  int _pmvValue = 0;
  int _recommendedTemp = 0;

  // 狀態控制
  bool _isEditing = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isActivityExpanded = false;
  bool _isClothingExpanded = false;
  
  Timer? _timer; 

  // MET 數據 (已修改為合併選項)
  static const Map<String, double> activityMETs = {
    '睡覺': 0.7,
    '斜倚': 0.8,
    '靜坐、坐著閱讀、寫作': 1.0,
    '打字': 1.1,
    '放鬆站立、坐著歸檔': 1.2,
    '站著歸檔': 1.4,
    '四處走動': 1.7,
    '烹飪': 1.8,
    '提舉/打包': 2.1,
    '坐著,肢體大量活動、輕型機械操作': 2.2,
    '打掃房屋': 2.7,
    '跳舞': 3.4,
    '徒手體操': 3.5,
  };

  // 活動選項列表 (對應合併後的鍵值)
  static const List<String> _activityOptions = [
    '睡覺','斜倚','靜坐、坐著閱讀、寫作','打字','放鬆站立、坐著歸檔','站著歸檔','四處走動','烹飪','提舉/打包',
    '坐著,肢體大量活動、輕型機械操作','打掃房屋','跳舞','徒手體操',
  ];

  // 衣物 clo 值數據
  static const Map<String, double> clothingItems = {
    'T-shirt': 0.08,
    'Polo衫': 0.11,
    '長袖襯衫': 0.20,
    '薄長袖外套': 0.20,
    '毛衣': 0.28,
    '厚外套': 0.50,
    '長褲': 0.25,
    '短褲': 0.06,
    '帽子': 0.03,
    '襪子': 0.02,
    '鞋子': 0.02,
  };

  static const Map<String, List<String>> presetClothingCombos = {
    '典型夏季室內服裝': ['T-shirt', '短褲', '鞋子', '襪子'],
    '典型冬季室內服裝': ['長袖襯衫', '長褲', '毛衣', '鞋子', '襪子'],
  };

  @override
  void initState() {
    super.initState();
    // 首次載入時顯示 Loading
    _loadAllData(showLoading: true); 
    
    // 設置定時器，每 5 秒執行一次靜默刷新
    _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_isEditing) { // 僅在非編輯模式下才自動刷新
        // 靜默刷新
        _loadAllData(showLoading: false);
      }
    });
  }
  
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 載入所有數據
  // 【關鍵修正】新增 showLoading 參數，控制是否顯示全螢幕 Loading
  Future<void> _loadAllData({bool showLoading = false}) async {
    // 只有在需要顯示 Loading 且當前不是編輯模式時才設置為 true
    if (showLoading && !_isEditing) {
      setState(() => _isLoading = true);
    }
    

    // 確保先載入依賴，然後並行載入其他狀態
    await _fetchEnergySavingSettings();
    
    // 使用 Future.wait 並行載入環境和設備狀態，這部分會觸發 setState
    await Future.wait([
      _fetchACStatus(), 
      _fetchMotionStatus(), 
    ]);
    
    // 只有在需要顯示 Loading 的情況下，才在完成時將 _isLoading 設為 false
    if (showLoading && mounted) {
      setState(() => _isLoading = false);
    }
    // 注意: 定時器觸發時 (showLoading=false)，此處不會執行 setState
  }

  /// 根據 MET 值反查活動名稱
  String? _getActivityNameByMet(double met) {
    for (var entry in activityMETs.entries) {
      if ((entry.value - met).abs() < 0.01) {
        return entry.key;
      }
    }
    return null;
  }

  /// 計算衣物總 clo 值 (多件加總 × 0.82)
  double _calculateTotalClo(List<String> items) {
    if (items.isEmpty) return 0.0;
    double sum =
        items.fold(0.0, (prev, item) => prev + (clothingItems[item] ?? 0.0));
    return sum * 0.82; // ISO 9920 修正係數
  }

  /// 根據 clo 值反查可能的衣物組合
  List<String> _getClothingItemsByClo(double clo) {
    for (var entry in presetClothingCombos.entries) {
      double presetClo = _calculateTotalClo(entry.value);
      if ((presetClo - clo).abs() < 0.05) {
        return entry.value;
      }
    }
    return []; // 非預設組合,返回空
  }

  /// 從後端獲取節能設定
  Future<void> _fetchEnergySavingSettings() async {
    try {
      final response = await ApiService.get('/energy-saving/settings');

      if (response.statusCode == 200 && mounted) {
        final data = json.decode(response.body);
        setState(() {
          final fetchedMet = (data['activity_met'] as num).toDouble();
          _selectedActivityMet = fetchedMet;
          // 確保使用合併後的名稱作為顯示值
          _selectedActivityName = _getActivityNameByMet(fetchedMet);
          if (data['clothing_items_json'] != null &&
              data['clothing_items_json'] != '') {
            try {
              final itemsList =
                  json.decode(data['clothing_items_json']) as List;
              _selectedClothingItems = itemsList.cast<String>();
            } catch (e) {
              print('解析 clothing_items_json 失敗: $e');
              double clo = (data['clothing_clo'] as num).toDouble();
              _selectedClothingItems = _getClothingItemsByClo(clo);
            }
          } else {
            // 後端沒有 JSON,用 clo 值反推 (向下兼容舊數據)
            double clo = (data['clothing_clo'] as num).toDouble();
            _selectedClothingItems = _getClothingItemsByClo(clo);
          }
          _tempSelectedActivityName = _selectedActivityName;
          _tempSelectedActivityMet = _selectedActivityMet;
          _tempSelectedClothingItems = List.from(_selectedClothingItems);
        });
      }
    } catch (e) {
      print('獲取節能設定時發生錯誤: $e');
    }
  }

  /// 從後端獲取 PMV 數據及設備狀態
  Future<void> _fetchACStatus() async {
  try {
    final response = await ApiService.get('/pmv/current');

    if (response.statusCode == 200 && mounted) {
      final data = json.decode(response.body);

      if (data['success'] == true && data['data'] != null) {
        setState(() {
          // 溫濕度數據
          _currentTemp = _safeParseDouble(
              data['data']['currentEnvironment']['temperature']);
          _currentHumidity = _safeParseDouble(
              data['data']['currentEnvironment']['humidity']);

          // PMV 數據
          _pmvValue = _safeParseInt(data['data']['pmv']);
          _pmvRaw = _safeParseDouble(data['data']['pmvRaw'] ?? 0.0);
          _recommendedTemp = _safeParseInt(data['data']['recommendedTemp']);

          // ✨ 獲取當前氣流速度
          if (data['data']['deviceStatus'] != null &&
              data['data']['deviceStatus']['fan'] != null) {
            _currentAirVelocity = _safeParseDouble(
                data['data']['deviceStatus']['fan']['airVelocity']);
          }

          // 模型推薦設定
          if (data['data']['modelRecommendations'] != null) {
            final recs = data['data']['modelRecommendations'];
            _modelAcDelta = _safeParseInt(recs['acDelta']);
            _modelFanLevel = _safeParseInt(recs['fanLevel']);
          }
        });
      }
    }
  } catch (e) {
      print('獲取 PMV 數據時發生錯誤: $e');
    }
  }

  int _safeParseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) {
      try {
        return double.parse(value).round();
      } catch (e) {
        return 0;
      }
    }
    return 0;
  }

  double _safeParseDouble(dynamic value) {
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

  /// 從後端獲取人體移動狀態
  Future<void> _fetchMotionStatus() async {
    try {
      final response = await ApiService.get('/system/motion-status');

      if (response.statusCode == 200 && mounted) {
        final motionData = json.decode(response.body);
        
        if (motionData['success'] == true) {
          setState(() {
            _isMotionDetected = motionData['is_motion_detected'] ?? false;
            
            final lastUpdateStr = motionData['last_motion_update'];
            
            if (lastUpdateStr != null && lastUpdateStr.isNotEmpty) {
              try {
                final utcTime = DateTime.parse(lastUpdateStr);
                _lastMotionUpdate = utcTime.toLocal();
              } catch (e) {
                print('⚠️ 時間解析失敗: $e');
                _lastMotionUpdate = null;
              }
            } else {
              _lastMotionUpdate = null;
            }
          });
        }
      }
    } catch (e) {
      print('❌ 獲取人體移動狀態時發生錯誤: $e');
    }
  }

  /// 向後端更新節能設定
  Future<void> _updateEnergySavingSettings() async {
    setState(() => _isSaving = true);

    try {
      double totalClo = _calculateTotalClo(_tempSelectedClothingItems);
      String clothingItemsJson = json.encode(_tempSelectedClothingItems);

      final response = await ApiService.post('/energy-saving/settings', {
        'activityMet': _tempSelectedActivityMet,
        'clothingClo': totalClo,
        'clothingItemsJson': clothingItemsJson,
      });

      if (response.statusCode == 200) {
        setState(() {
          _selectedActivityMet = _tempSelectedActivityMet;
          _selectedActivityName = _tempSelectedActivityName; // ✨ 保持選中名稱同步
          _selectedClothingItems = List.from(_tempSelectedClothingItems);

          _isEditing = false;
          _collapseAllExpansions();
        });

        await _fetchACStatus();
        _showSuccessSnackBar('節能設定已保存!');
      } else {
        final errorData = json.decode(response.body);
        _showErrorSnackBar('保存失敗:${errorData['message'] ?? '請重試'}');
      }
    } catch (e) {
      _showErrorSnackBar('保存失敗,請檢查網路連接!');
    } finally {
      setState(() => _isSaving = false);
      // 確保保存完成後重啟定時器
      _startTimerIfNeeded(); 
    }
  }

  /// 收起所有展開的選單
  void _collapseAllExpansions() {
    _isActivityExpanded = false;
    _isClothingExpanded = false;
  }

  /// 【優化】切換編輯模式，同時處理定時器
  void _toggleEditMode() {
    setState(() {
      if (_isEditing) {
        _updateEnergySavingSettings();
      } else {
        _timer?.cancel(); // 進入編輯模式時，暫停自動刷新
        // 確保同步 MET 和 Name
        _tempSelectedActivityMet = _selectedActivityMet;
        _tempSelectedActivityName = _selectedActivityName;
        _tempSelectedClothingItems = List.from(_selectedClothingItems);
        _isEditing = true;
      }
    });
  }
  
  /// 【新增】退出編輯模式時，重新啟動自動刷新
  void _cancelEditMode() {
    setState(() {
      _isEditing = false;
      _collapseAllExpansions();
    });
    _startTimerIfNeeded();
  }

  // 【新增】檢查並啟動定時器 (避免重複啟動)
  void _startTimerIfNeeded() {
    if (_timer == null || !_timer!.isActive) {
        _timer = Timer.periodic(const Duration(seconds: 5), (timer) {
          if (!_isEditing) {
            _loadAllData(showLoading: false);
          }
        });
    }
  }

  /// 處理選項變更
  void _handleOptionChanged(String type, dynamic newValue) {
    setState(() {
      switch (type) {
        case 'activity':
          // 更新 MET (用於保存) 和 Name (用於 UI)
          _tempSelectedActivityMet = activityMETs[newValue];
          _tempSelectedActivityName = newValue;
          _isActivityExpanded = false;
          break;
        case 'clothing':
          if (newValue is String) {
            if (_tempSelectedClothingItems.contains(newValue)) {
              _tempSelectedClothingItems.remove(newValue);
            } else {
              _tempSelectedClothingItems.add(newValue);
            }
          }
          break;
      }
    });
  }

  /// 處理展開狀態變更
  void _handleExpansionChanged(String type, bool expanded) {
    if (!_isEditing) return;

    setState(() {
      _collapseAllExpansions();

      switch (type) {
        case 'activity':
          _isActivityExpanded = expanded;
          break;
        case 'clothing':
          _isClothingExpanded = expanded;
          break;
      }
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

  // 【調整】手動下拉刷新仍然使用 _loadAllData，但強制顯示 Loading
  Future<void> _manualRefreshData() async {
    await _loadAllData(showLoading: true);
  }

  /// 根據 PMV 值獲取舒適度級別描述
  String _getPMVComfortLevel(int pmv) {
    if (pmv >= -1 && pmv <= 1) {
      return '舒適';
    } else if (pmv >= -2 && pmv <= 2) {
      return pmv < 0 ? '稍冷' : '稍熱';
    } else if (pmv >= -3 && pmv <= 3) {
      return pmv < 0 ? '冷' : '熱';
    } else {
      return pmv < -3 ? '極冷 (超出範圍)' : '極熱 (超出範圍)';
    }
  }

  /// 根據 PMV 值獲取舒適度顏色
  Color _getComfortColor(int pmv) {
    if (pmv >= -1 && pmv <= 1) {
      return Colors.green;
    } else if (pmv >= -2 && pmv <= 2) {
      return Colors.orange;
    } else if (pmv >= -3 && pmv <= 3) {
      return Colors.red;
    } else {
      return Colors.purple;
    }
  }

  // ----------------------------------------------------
  // 3. 介面構建 (Build Methods)
  // ----------------------------------------------------

  @override
Widget build(BuildContext context) {
  // 獲取當前活動名稱和 MET 值
  final currentActivityName =
      _isEditing ? _tempSelectedActivityName : _selectedActivityName;

  final currentMet =
      _isEditing ? _tempSelectedActivityMet : _selectedActivityMet;

  // ✨ 修正：組合顯示字串 (名稱 + MET 值)
  String activityDisplayValue = '未選擇';
  if (currentActivityName != null && currentMet != null) {
    activityDisplayValue =
        '$currentActivityName (MET: ${currentMet.toStringAsFixed(1)})';
  } else if (currentActivityName != null) {
    // 確保至少顯示名稱，如果 MET 莫名丟失
    activityDisplayValue = currentActivityName;
  }

  final displayClothingItems =
      _isEditing ? _tempSelectedClothingItems : _selectedClothingItems;
  final totalClo = _calculateTotalClo(displayClothingItems);

  final clothingDisplayText = displayClothingItems.isEmpty
      ? '未選擇'
      : '${displayClothingItems.join(", ")} (總clo: ${totalClo.toStringAsFixed(2)})';

  return Scaffold(
    body: _isLoading
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text(
                  '載入節能設定中...',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          )
        // 【優化】使用 RefreshIndicator 處理手動下拉刷新
        : RefreshIndicator(
            onRefresh: _manualRefreshData,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 頂部說明卡片
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16.0),
                    margin: const EdgeInsets.only(bottom: 24.0),
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
                            Icon(
                              Icons.info_outline,
                              color: Colors.blue.shade700,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '節能設定說明',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue.shade700,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '這些設定將影響系統的智慧節能計算,請根據您的實際情況選擇適合的選項。',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.blue.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 【移動到此處的新位置】當前設定總覽 (僅在非編輯模式下顯示)
                  if (!_isEditing &&
                      currentActivityName != null &&
                      displayClothingItems.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24.0),
                      child: _buildCurrentSettingsSummary(
                        activityDisplayValue,
                        clothingDisplayText,
                      ),
                    ),

                  // 💡 左右分欄區域 (PMV + 設備狀態)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 左半邊: PMV 儀表板
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: _buildPMVSection(),
                        ),
                      ),

                      // 右半邊: 設備狀態卡片
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8.0),
                          child: _buildDeviceStatusCard(),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 32),

                    // 活動類型 (全寬)
                    _buildExpansionTileCard(
                      title: '活動類型',
                      // 傳遞單純的名稱給 ExpansionTile 的 Subtitle
                      selectedValue: currentActivityName, 
                      isExpanded: _isActivityExpanded,
                      onExpansionChanged: (expanded) =>
                          _handleExpansionChanged('activity', expanded),
                      options: _activityOptions,
                      onOptionChanged: (value) =>
                          _handleOptionChanged('activity', value),
                      icon: Icons.directions_run,
                    ),
                    const SizedBox(height: 16),

                    // 穿著類型 (全寬)
                    _buildClothingMultiSelectCard(
                      title: '穿著類型',
                      selectedItems: displayClothingItems,
                      totalClo: totalClo,
                      isExpanded: _isClothingExpanded,
                      onExpansionChanged: (expanded) =>
                          _handleExpansionChanged('clothing', expanded),
                      onItemToggle: (item) =>
                          _handleOptionChanged('clothing', item),
                      icon: Icons.checkroom,
                    ),
                    const SizedBox(height: 32),

                    // 編輯/保存按鈕區塊
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isEditing)
                          Padding(
                            padding: const EdgeInsets.only(right: 16.0),
                            child: OutlinedButton(
                              onPressed: _cancelEditMode,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 30, vertical: 15),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                side: const BorderSide(color: Colors.red),
                              ),
                              child: const Text('取消',
                                  style: TextStyle(fontSize: 18)),
                            ),
                          ),
                        ElevatedButton(
                          onPressed: _isSaving ? null : _toggleEditMode,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).primaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 40, vertical: 15),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: _isSaving
                              ? const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                            Colors.white),
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Text('保存中...',
                                        style: TextStyle(fontSize: 18)),
                                  ],
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(_isEditing ? Icons.save : Icons.edit),
                                    const SizedBox(width: 8),
                                    Text(
                                      _isEditing ? '保存' : '編輯',
                                      style: const TextStyle(fontSize: 18),
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // 當前設定總覽
                    
                  ],
                ),
              ),
            ),
    );
  }

  // ----------------------------------------------------
  // 4. 構建子組件 (Widgets)
  // ----------------------------------------------------

  /// 構建 PMV 儀表板區域 (左側卡片)
  Widget _buildPMVSection() {
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
          const SizedBox(height: 12), // 額外增加間距
          const Text(
            '環境與舒適度',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildInfoChip('溫度', '${_currentTemp.toStringAsFixed(1)}°C',
                  Icons.device_thermostat),
              _buildInfoChip('濕度', '${_currentHumidity.toStringAsFixed(0)}%',
                  Icons.water_drop)
            ],
          ),
          const SizedBox(height: 16),
          Center(
            child: _buildInfoChip(
              '當前風速 (VEL)',
              '${_currentAirVelocity.toStringAsFixed(2)} m/s',
              Icons.air,
            ),
          ),
          const SizedBox(height: 24),

          // PMV 儀表
          Center(
            child: Column(
              children: [
                const Text(
                  'PMV 舒適度指標',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 32),
                CustomPaint(
                  size: const Size(200, 100), // 縮小以適應欄位寬度
                  painter: HalfCircleGaugePainter(pmvValue: _pmvValue),
                  child: Container(
                    width: 200,
                    height: 100,
                    alignment: Alignment.bottomCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'PMV',
                          style: TextStyle(
                              fontSize: 14, color: Colors.grey.shade600),
                        ),
                        Text(
                              _pmvRaw.toStringAsFixed(2),
                          style: TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: _getComfortColor(_pmvValue),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _getPMVComfortLevel(_pmvValue),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 構建右側設備狀態卡片 (右側卡片)
  Widget _buildDeviceStatusCard() {
  // 顯示模型建議值
  String acSuggestion = _modelAcDelta > 0
      ? '降溫 ${_modelAcDelta}°C'
      : '關閉';
  Color acSuggestionColor =
      _modelAcDelta > 0 ? Colors.red.shade700 : Colors.green.shade700;

  String fanSuggestion = _modelFanLevel > 0
      ? '調整至 ${_modelFanLevel} 檔'
      : '關閉';
  Color fanSuggestionColor =
      _modelFanLevel > 0 ? Colors.deepOrange : Colors.green.shade700;

    // 新增: 處理人體移動狀態的顯示
  String motionStatus = _isMotionDetected ? '偵測到有人' : '長時間無人';
  Color motionColor = _isMotionDetected ? Colors.green.shade700 : Colors.orange.shade700;
  String lastUpdateText = _lastMotionUpdate != null
    ? '上次更新: ${_lastMotionUpdate!.hour.toString().padLeft(2, '0')}:${_lastMotionUpdate!.minute.toString().padLeft(2, '0')}:${_lastMotionUpdate!.second.toString().padLeft(2, '0')}'
    : '無記錄'; // 確保這行代碼正確

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
          '人體移動狀態',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const Divider(height: 10),
        _buildDeviceSuggestionItem(
          '當前狀態',
          motionStatus,
          _isMotionDetected ? Icons.person : Icons.person_off,
          motionColor,
        ),
        Padding(
          padding: const EdgeInsets.only(left: 34.0, top: 4.0, bottom: 16.0),
          child: Text(
            lastUpdateText,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
        ),
        const Divider(height: 20),
        const Text(
          '模型建議 (PMV 基準)',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const Divider(height: 20),

        // 顯示冷氣建議
        _buildDeviceSuggestionItem(
          '冷氣建議',
          acSuggestion,
          Icons.ac_unit,
          acSuggestionColor,
        ),
        const SizedBox(height: 10),

        // 顯示風扇建議
        _buildDeviceSuggestionItem(
          '風扇建議',
          fanSuggestion,
          Icons.mode_fan_off,
          fanSuggestionColor,
        ),
        const SizedBox(height: 16),
        
      ],
    ),
  );
}

// 【新增的子組件，用於顯示模型建議】
Widget _buildDeviceSuggestionItem(
    String label, String suggestion, IconData icon, Color color) {
  return Row(
    children: [
      Icon(icon, size: 24, color: color),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            Text(
              suggestion,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

  /// 構建設備狀態單項
  Widget _buildDeviceStatusItem(
      String label, String status, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, size: 24, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              Text(
                status,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 構建資訊晶片 (PMV Section 內的溫濕度)
  Widget _buildInfoChip(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 28, color: Theme.of(context).primaryColor),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
      ],
    );
  }

  /// 構建衣物多選卡片
  Widget _buildClothingMultiSelectCard({
    required String title,
    required List<String> selectedItems,
    required double totalClo,
    required bool isExpanded,
    required ValueChanged<bool> onExpansionChanged,
    required ValueChanged<String> onItemToggle,
    required IconData icon,
  }) {
    // ... (保持原有的 _buildClothingMultiSelectCard 邏輯不變) ...
    final Color cardBackgroundColor = _isEditing
        ? Theme.of(context).primaryColor.withOpacity(0.1)
        : Colors.grey.shade100;

    final Color titleColor = _isEditing ? Colors.black87 : Colors.black;
    final Color subtitleColor = _isEditing ? Colors.black54 : Colors.black87;
    final Color trailingColor =
        _isEditing ? Theme.of(context).primaryColor : Colors.grey;
    final Color iconColor =
        _isEditing ? Theme.of(context).primaryColor : Colors.grey.shade600;

    // 顯示文字
    String displayText = selectedItems.isEmpty
        ? '未選擇'
        : '${selectedItems.length} 件 (總clo: ${totalClo.toStringAsFixed(2)})';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        color: cardBackgroundColor,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ExpansionTile(
        key: PageStorageKey(title),
        leading: Icon(icon, color: iconColor),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: titleColor,
          ),
        ),
        subtitle: Text(
          displayText,
          style: TextStyle(
            fontSize: 14,
            color: subtitleColor,
            fontWeight:
                selectedItems.isNotEmpty ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
        trailing: Icon(
          isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          color: trailingColor,
        ),
        initiallyExpanded: isExpanded,
        onExpansionChanged: onExpansionChanged,
        controlAffinity: ListTileControlAffinity.trailing,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                // 預設組合按鈕
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildPresetButton('典型夏季室內服裝', onItemToggle),
                      _buildPresetButton('典型冬季室內服裝', onItemToggle),
                    ],
                  ),
                ),
                const Divider(),
                // 個別衣物選項
                _buildClothingCheckboxGroup(
                  selectedItems: selectedItems,
                  onChanged: _isEditing ? onItemToggle : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 構建預設組合按鈕
  Widget _buildPresetButton(
      String presetName, ValueChanged<String> onItemToggle) {
    return ElevatedButton.icon(
      onPressed: _isEditing
          ? () {
              setState(() {
                _tempSelectedClothingItems.clear();
                _tempSelectedClothingItems
                    .addAll(presetClothingCombos[presetName]!);
              });
            }
          : null,
      icon: const Icon(Icons.category, size: 16),
      label: Text(presetName),
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  /// 構建衣物多選框組
  Widget _buildClothingCheckboxGroup({
    required List<String> selectedItems,
    required ValueChanged<String>? onChanged,
  }) {
    return Column(
      children: clothingItems.keys
          .map((item) => CheckboxListTile(
                title: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      item,
                      style: TextStyle(
                        fontSize: 14,
                        color: onChanged == null ? Colors.grey : Colors.black87,
                      ),
                    ),
                    Text(
                      'clo: ${clothingItems[item]!.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
                value: selectedItems.contains(item),
                onChanged: onChanged != null
                    ? (checked) => onChanged(item)
                    : null,
                activeColor: Theme.of(context).primaryColor,
                dense: true,
              ))
          .toList(),
    );
  }

  /// 構建當前設定總覽
  Widget _buildCurrentSettingsSummary(String activity, String clothing) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                color: Colors.green.shade700,
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                '當前節能設定',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 這裡的 activity 參數已經是包含 MET 數值的組合字串
          _buildSummaryItem('活動類型', activity), 
          _buildSummaryItem('穿著類型', clothing),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.green.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                color: Colors.green.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 構建展開選單卡片 (活動類型)
  Widget _buildExpansionTileCard({
    required String title,
    required String? selectedValue,
    required bool isExpanded,
    required ValueChanged<bool> onExpansionChanged,
    required List<String> options,
    required ValueChanged<String?> onOptionChanged,
    required IconData icon,
  }) {
    final Color cardBackgroundColor = _isEditing
        ? Theme.of(context).primaryColor.withOpacity(0.1)
        : Colors.grey.shade100;

    final Color titleColor = _isEditing ? Colors.black87 : Colors.black;
    final Color subtitleColor = _isEditing ? Colors.black54 : Colors.black87;
    final Color trailingColor =
        _isEditing ? Theme.of(context).primaryColor : Colors.grey;
    final Color iconColor =
        _isEditing ? Theme.of(context).primaryColor : Colors.grey.shade600;

    // 這裡的 selectedValue 是單純的活動名稱 (例如 '靜坐、坐著閱讀、寫作')
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      decoration: BoxDecoration(
        color: cardBackgroundColor,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 3,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ExpansionTile(
        key: PageStorageKey(title),
        leading: Icon(icon, color: iconColor),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: titleColor,
          ),
        ),
        subtitle: Text(
          selectedValue ?? '未選擇',
          style: TextStyle(
            fontSize: 14,
            color: subtitleColor,
            fontWeight:
                selectedValue != null ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
        trailing: Icon(
          isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          color: trailingColor,
        ),
        initiallyExpanded: isExpanded,
        onExpansionChanged: onExpansionChanged,
        controlAffinity: ListTileControlAffinity.trailing,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _buildRadioGroup(
              currentValue: selectedValue,
              options: options,
              onChanged: _isEditing ? onOptionChanged : null,
            ),
          ),
        ],
      ),
    );
  }

  /// 構建單選按鈕群組 (活動類型)
  Widget _buildRadioGroup({
    required String? currentValue,
    required List<String> options,
    required ValueChanged<String?>? onChanged,
  }) {
    return Column(
      children: options
          .map((option) => RadioListTile<String>(
                title: Text(
                  '$option (MET: ${activityMETs[option]!.toStringAsFixed(1)})',
                  style: TextStyle(
                    fontSize: 14,
                    color: onChanged == null ? Colors.grey : Colors.black87,
                  ),
                ),
                value: option,
                groupValue: currentValue,
                onChanged: onChanged,
                activeColor: Theme.of(context).primaryColor,
                dense: true,
              ))
          .toList(),
    );
  }
}

// ----------------------------------------------------

// 5. PMV 儀表板繪製器 (Custom Painter)

// ----------------------------------------------------



class HalfCircleGaugePainter extends CustomPainter {

  final int pmvValue;



  HalfCircleGaugePainter({required this.pmvValue});



  @override

  void paint(Canvas canvas, Size size) {

    final center = Offset(size.width / 2, size.height);

    final radius = size.width / 2;



    _drawArc(canvas, center, radius);

    _drawTicks(canvas, center, radius);

    _drawPointer(canvas, center, radius);

  }



  void _drawArc(Canvas canvas, Offset center, double radius) {

  final Paint arcPaint = Paint()

    ..color = Colors.grey.shade300

    ..style = PaintingStyle.stroke

    ..strokeWidth = 5;



  // 繪製背景灰弧

  // 從 pi (180度, 左側) 逆時針掃描 pi (到 360/0度, 右側)

  canvas.drawArc(

    Rect.fromCircle(center: center, radius: radius),

    pi, 

    pi, 

    false,

    arcPaint,

  );

  

  // ----------------------------------------------------------------------

  // 修正舒適區間繪製位置：強制將其畫在上半圓 (0 到 pi) 區間內

  // ----------------------------------------------------------------------



  // 繪製嚴格舒適區間：從 PMV +0.5 到 -0.5

  final Paint comfortPaint = Paint()

      ..color = Colors.green.shade600 

      ..style = PaintingStyle.stroke

      ..strokeWidth = 10; 



    // PMV +0.5 的角度 (5pi/12) + pi 

    const double comfortStartAngle = pi * 5 / 12 + pi; 

    

    // 掃描角度: pi/6 (保持逆時針)

    const double comfortSweepAngle = pi / 6;



    canvas.drawArc(

      Rect.fromCircle(center: center, radius: radius),

      comfortStartAngle,

      comfortSweepAngle,

      false, 

      comfortPaint,

  );

}

// 這是與修正後的 _drawTickWithLabel 匹配的 _drawTicks 函數：

void _drawTicks(Canvas canvas, Offset center, double radius) {

  const double tickLength = 10; 

  final Paint tickPaint = Paint()

    ..color = Colors.black

    ..strokeWidth = 2;



  // 繪製刻度線和標籤

  

  // PMV -3 (180°)

  _drawTickWithLabel(canvas, center, radius, tickLength, tickPaint, pi,

      '-3'); 



  // PMV -2 (150°)

  _drawTickWithLabel(canvas, center, radius, tickLength, tickPaint, pi * 5 / 6,

      '-2');



  // PMV -1 (120°)

  _drawTickWithLabel(canvas, center, radius, tickLength, tickPaint, pi * 4 / 6,

      '-1');



  // PMV 0 (90°)

  _drawTickWithLabel(canvas, center, radius, tickLength, tickPaint, pi * 3 / 6,

      '0');



  // PMV 1 (60°)

  _drawTickWithLabel(canvas, center, radius, tickLength, tickPaint, pi * 2 / 6,

      '1');



  // PMV 2 (30°)

  _drawTickWithLabel(canvas, center, radius, tickLength, tickPaint, pi * 1 / 6,

      '2');



  // PMV 3 (0°)

  _drawTickWithLabel(canvas, center, radius, tickLength, tickPaint, 0, 

      '3'); 

}



void _drawTickWithLabel(

    Canvas canvas,

    Offset center,

    double radius,

    double tickLength,

    Paint tickPaint,

    double angle,

    String label) {

    

  // 標籤到圓心的半徑，使其位於圓弧外側

  const double labelRadiusOffset = 25; // 這是確保標籤在圓弧外側的關鍵距離

  final double labelRadius = radius + labelRadiusOffset;

    

  final double cosAngle = cos(angle);

  final double sinAngle = sin(angle);

    

  // 刻度線起點 (圓弧內側)

  final Offset tickStart = Offset(

    center.dx + radius * cosAngle,

    center.dy - radius * sinAngle,

  );



  // 刻度線終點 (圓弧外側，即灰色背景外緣)

  final Offset tickEnd = Offset(

    center.dx + (radius + tickLength) * cosAngle,

    center.dy - (radius + tickLength) * sinAngle,

  );



  // 繪製刻度線

  canvas.drawLine(

    tickStart,

    tickEnd,

    tickPaint,

  );



  // 計算標籤的繪圖位置

  final TextPainter tp = TextPainter(

    text: TextSpan(

      text: label,

      // 使用與其他標籤相同的樣式

      style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.bold),

    ),

    textDirection: TextDirection.ltr,

    textAlign: TextAlign.center, // 確保文本繪圖是居中對齊

  )..layout();

    

  // 計算標籤中心點的理想位置 (沿徑向方向推開)

  final double textX = center.dx + labelRadius * cosAngle;

  final double textY = center.dy - labelRadius * sinAngle;



  // 調整標籤位置以使其底部或中心點與目標對齊

  tp.paint(

    canvas,
    
    // 這裡我們假設你希望標籤沿著圓弧居中對齊
    Offset(
      textX - tp.width / 2, 
      textY - tp.height / 2, 
    ),

  );

}



  void _drawPointer(Canvas canvas, Offset center, double radius) {

    final double pointerLength = radius - 15;

    // [修正] 確保 pmvValue 介於 -3 到 3 之間，避免指針超出儀表板邊界

    final double clampedPmv = pmvValue.clamp(-3, 3).toDouble();

    // 將 PMV 值從 -3 到 +3 映射到 0 到 1

    final double normalizedValue = (clampedPmv + 3) / 6;

    // 將標準化值映射到半圓弧(從左到右,即從 π 到 0)

    final double pointerAngle = pi * (1 - normalizedValue);



    final Paint pointerPaint = Paint()

      ..color = Colors.red

      ..style = PaintingStyle.stroke

      ..strokeWidth = 3

      ..strokeCap = StrokeCap.round;



    // 指針線

    canvas.drawLine(

      center,

      Offset(

        center.dx + pointerLength * cos(pointerAngle),

        center.dy - pointerLength * sin(pointerAngle),

      ),

      pointerPaint,

    );

    

    // 指針中心圓點

     final Paint centerDotPaint = Paint()

      ..color = Colors.red

      ..style = PaintingStyle.fill;

      

    canvas.drawCircle(center, 5, centerDotPaint);

  }



  @override

  bool shouldRepaint(covariant HalfCircleGaugePainter oldDelegate) {

    return oldDelegate.pmvValue != pmvValue;

  }

}