import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math';
import 'package:iot_project/main.dart'; // 引入 main.dart 以使用 ApiService

class EnergySavingSettingsPage extends StatefulWidget {
  const EnergySavingSettingsPage({super.key});

  @override
  State<EnergySavingSettingsPage> createState() => _EnergySavingSettingsPageState();
}

class _EnergySavingSettingsPageState extends State<EnergySavingSettingsPage> {
  // 節能設定選項
  double? _selectedActivityMet;
  List<String> _selectedClothingItems = []; // 改為多選列表
  String? _selectedAirflowSpeed;

  // 編輯模式的暫存變數
  double? _tempSelectedActivityMet;
  List<String> _tempSelectedClothingItems = [];
  String? _tempSelectedAirflowSpeed;

  // PMV 數據
  int _pmvValue = 0;
  int _currentRoomTemp = 0;
  double _currentHumidity = 0.0;
  int _recommendedTemp = 0;

  // 狀態控制
  bool _isEditing = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isActivityExpanded = false;
  bool _isClothingExpanded = false;
  bool _isAirflowExpanded = false;

  // ✅ 替換成新的
static const List<String> _activityOptions = [
  '睡覺', '斜倚', '靜坐', '坐著閱讀', '寫作', '打字',
  '放鬆站立', '坐著歸檔', '站著歸檔', '四處走動', '烹飪',
  '提舉/打包', '坐著,肢體大量活動', '輕型機械操作', '打掃房屋',
  '跳舞', '徒手體操',
];

static const Map<String, double> activityMETs = {
  '睡覺': 0.7, '斜倚': 0.8, '靜坐': 1.0, '坐著閱讀': 1.0,   
  '寫作': 1.0, '打字': 1.1, '放鬆站立': 1.2, '坐著歸檔': 1.2,    
  '站著歸檔': 1.4, '四處走動': 1.7, '烹飪': 1.8, '提舉/打包': 2.1,
  '坐著,肢體大量活動': 2.2, '輕型機械操作': 2.2, '打掃房屋': 2.7,
  '跳舞': 3.4, '徒手體操': 3.5,
};

// ✅ 新增衣物多選資料
static const Map<String, double> clothingItems = {
  'T-shirt': 0.08, 'Polo衫': 0.11, '長袖襯衫': 0.20,
  '薄長袖外套': 0.20, '毛衣': 0.28, '厚外套': 0.50,
  '長褲': 0.25, '短褲': 0.06, '帽子': 0.03,
  '襪子': 0.02, '鞋子': 0.02,
};

static const Map<String, List<String>> presetClothingCombos = {
  '典型夏季室內服裝': ['T-shirt', '短褲', '鞋子', '襪子'],
  '典型冬季室內服裝': ['長袖襯衫', '長褲', '毛衣', '鞋子', '襪子'],
};

  static const List<String> _airflowOptions = ['無風扇', '有風扇'];

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  /// 載入所有數據
  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    
    await Future.wait([
      _fetchEnergySavingSettings(),
      _fetchACStatus(),
    ]);
    
    setState(() => _isLoading = false);
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

  // ✅ 替換成新的
  /// 計算衣物總 clo 值 (多件加總 × 0.82)
  double _calculateTotalClo(List<String> items) {
    if (items.isEmpty) return 0.0;
    double sum = items.fold(0.0, (prev, item) => prev + (clothingItems[item] ?? 0.0));
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
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _selectedActivityMet = (data['activity_met'] as num).toDouble();
          
          // ✅ 優先使用 clothing_items_json,否則用 clo 值反推
          if (data['clothing_items_json'] != null && data['clothing_items_json'] != '') {
            try {
              final itemsList = json.decode(data['clothing_items_json']) as List;
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
          
          _selectedAirflowSpeed = data['airflow_speed'];

          _tempSelectedActivityMet = _selectedActivityMet;
          _tempSelectedClothingItems = List.from(_selectedClothingItems);
          _tempSelectedAirflowSpeed = _selectedAirflowSpeed;
        });
        print('成功獲取節能設定: $data');
        print('已選擇衣物: $_selectedClothingItems');
      } else if (response.statusCode == 404) {
        _showErrorSnackBar('找不到節能設定,請檢查帳戶設定');
      } else {
        _showErrorSnackBar('載入節能設定失敗');
      }
    } catch (e) {
      print('獲取節能設定時發生錯誤: $e');
      _showErrorSnackBar('網路連線錯誤,請檢查連線狀態');
    }
  }

  /// 從後端獲取冷氣狀態 (用於 PMV 數據)
  Future<void> _fetchACStatus() async {
    try {
      final response = await ApiService.get('/ac/status');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _currentRoomTemp = _safeParseInt(data['current_room_temp']);
          _currentHumidity = _safeParseDouble(data['current_humidity']);
          _pmvValue = _safeParseInt(data['pmv_value']);
          _recommendedTemp = _safeParseInt(data['recommended_temp']);
        });
      }
    } catch (e) {
      print('獲取冷氣狀態時發生錯誤: $e');
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

  /// 向後端更新節能設定
  Future<void> _updateEnergySavingSettings() async {
    setState(() => _isSaving = true);

    try {
      // 計算總 clo 值
      double totalClo = _calculateTotalClo(_tempSelectedClothingItems);
      
      // ✅ 將衣物列表轉為 JSON 字串
      String clothingItemsJson = json.encode(_tempSelectedClothingItems);
      
      final response = await ApiService.post('/energy-saving/settings', {
        'activityMet': _tempSelectedActivityMet,
        'clothingClo': totalClo,
        'clothingItemsJson': clothingItemsJson, // ✅ 新增這行
        'airflowSpeed': _tempSelectedAirflowSpeed,
      });

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('成功更新節能設定到後端: ${responseData['message']}');
        
        setState(() {
          _selectedActivityMet = _tempSelectedActivityMet;
          _selectedClothingItems = List.from(_tempSelectedClothingItems);
          _selectedAirflowSpeed = _tempSelectedAirflowSpeed;
          
          _isEditing = false;
          _collapseAllExpansions();
        });

        // 更新後重新獲取 PMV 數據
        await _fetchACStatus();
        
        _showSuccessSnackBar('節能設定已保存!');
      } else {
        final errorData = json.decode(response.body);
        _showErrorSnackBar('保存失敗:${errorData['message'] ?? '請重試'}');
      }
    } catch (e) {
      print('更新節能設定時發生錯誤: $e');
      _showErrorSnackBar('保存失敗,請檢查網路連接!');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  /// 收起所有展開的選單
  void _collapseAllExpansions() {
    _isActivityExpanded = false;
    _isClothingExpanded = false;
    _isAirflowExpanded = false;
  }

  /// 切換編輯模式
  void _toggleEditMode() {
    setState(() {
      if (_isEditing) {
        _updateEnergySavingSettings();
      } else {
        _tempSelectedActivityMet = _selectedActivityMet;
        _tempSelectedClothingItems = List.from(_selectedClothingItems); // ✅ 改這行
        _tempSelectedAirflowSpeed = _selectedAirflowSpeed;
        _isEditing = true;
      }
    });
  }

  /// 處理返回按鈕邏輯
  void _handleBackPress() {
    if (_isEditing) {
      _showUnsavedChangesDialog();
    } else {
      Navigator.pop(context);
    }
  }

  /// 顯示未保存變更的對話框
  void _showUnsavedChangesDialog() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('未保存的更改'),
          content: const Text('您有未保存的節能設定。是否要放棄更改並返回?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _isEditing = false;
                  _fetchEnergySavingSettings();
                  _collapseAllExpansions();
                });
                Navigator.of(dialogContext).pop();
                Navigator.pop(context);
              },
              child: const Text('放棄', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  /// 處理選項變更
  void _handleOptionChanged(String type, dynamic newValue) { // ✅ 改參數型別
    setState(() {
      switch (type) {
        case 'activity':
          _tempSelectedActivityMet = activityMETs[newValue];
          _isActivityExpanded = false;
          break;
        case 'clothing':
        // ✅ 新增多選邏輯
        if (newValue is String) {
          if (_tempSelectedClothingItems.contains(newValue)) {
            _tempSelectedClothingItems.remove(newValue);
          } else {
            _tempSelectedClothingItems.add(newValue);
          }
        }
        break;
        case 'airflow':
          _tempSelectedAirflowSpeed = newValue;
          _isAirflowExpanded = false;
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
        case 'airflow':
          _isAirflowExpanded = expanded;
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

  Future<void> _refreshData() async {
    await _loadAllData();
  }

  String _getPMVComfortLevel(int pmv) {
    if (pmv >= -1 && pmv <= 1) {
      return '舒適';
    } else if (pmv >= -2 && pmv <= 2) {
      return pmv < 0 ? '稍冷' : '稍熱';
    } else if (pmv >= -3 && pmv <= 3) {
      return pmv < 0 ? '冷' : '熱';
    } else {
      return pmv < -3 ? '很冷' : '很熱';
    }
  }

  @override
  Widget build(BuildContext context) {
    final activityDisplayName = _getActivityNameByMet(
      _isEditing ? (_tempSelectedActivityMet ?? 0.0) : (_selectedActivityMet ?? 0.0)
    );
    // ✅ 替換成新的
    final displayClothingItems = _isEditing ? _tempSelectedClothingItems : _selectedClothingItems;
    final totalClo = _calculateTotalClo(displayClothingItems);
    final clothingDisplayText = displayClothingItems.isEmpty 
        ? '未選擇' 
        : '${displayClothingItems.join(", ")} (總clo: ${totalClo.toStringAsFixed(2)})';
    
    // 移除 PopScope 和 Scaffold 的 AppBar
    return Scaffold( // 保持 Scaffold 以提供基礎結構
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
          : RefreshIndicator(
              onRefresh: _refreshData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // *** 新增: 將原 AppBar 中的 Refresh 按鈕移到這裡 (可選) ***
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (_isEditing)
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            onPressed: _refreshData,
                            tooltip: '重新整理',
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

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

                    // PMV 儀表板區域
                    _buildPMVSection(),
                    const SizedBox(height: 32),

                    // 活動類型
                    _buildExpansionTileCard(
                      title: '活動類型',
                      selectedValue: activityDisplayName,
                      isExpanded: _isActivityExpanded,
                      onExpansionChanged: (expanded) => _handleExpansionChanged('activity', expanded),
                      options: _activityOptions,
                      onOptionChanged: (value) => _handleOptionChanged('activity', value),
                      icon: Icons.directions_run,
                    ),
                    const SizedBox(height: 16),

                    // ✅ 替換成新的多選卡片
                    _buildClothingMultiSelectCard(
                      title: '穿著類型',
                      selectedItems: displayClothingItems,
                      totalClo: totalClo,
                      isExpanded: _isClothingExpanded,
                      onExpansionChanged: (expanded) => _handleExpansionChanged('clothing', expanded),
                      onItemToggle: (item) => _handleOptionChanged('clothing', item),
                      icon: Icons.checkroom,
                    ),
                    const SizedBox(height: 16),

                    // 空氣流速
                    _buildExpansionTileCard(
                      title: '空氣流速',
                      selectedValue: _isEditing ? _tempSelectedAirflowSpeed : _selectedAirflowSpeed,
                      isExpanded: _isAirflowExpanded,
                      onExpansionChanged: (expanded) => _handleExpansionChanged('airflow', expanded),
                      options: _airflowOptions,
                      onOptionChanged: (value) => _handleOptionChanged('airflow', value),
                      icon: Icons.air,
                    ),
                    const SizedBox(height: 32),

                    // *** 移動: 編輯/保存按鈕區塊 (放到所有展開設定下方) ***
                    Center(
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _toggleEditMode,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).primaryColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
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
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  ),
                                  SizedBox(width: 8),
                                  Text('保存中...', style: TextStyle(fontSize: 18)),
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
                    ),
                    const SizedBox(height: 32),
                    
                    // 當前設定總覽 (在編輯按鈕下方)
                    if (!_isEditing && 
                        activityDisplayName != null && 
                        displayClothingItems.isNotEmpty && // ✅ 改這行
                        _selectedAirflowSpeed != null)
                      _buildCurrentSettingsSummary(
                        activityDisplayName,
                        clothingDisplayText, // ✅ 改這行
                        _selectedAirflowSpeed!
                      ),
                  ],
                ),
              ),
            ),
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
    final Color cardBackgroundColor = _isEditing
        ? Theme.of(context).primaryColor.withOpacity(0.1)
        : Colors.grey.shade100;
    
    final Color titleColor = _isEditing ? Colors.black87 : Colors.black;
    final Color subtitleColor = _isEditing ? Colors.black54 : Colors.black87;
    final Color trailingColor = _isEditing 
        ? Theme.of(context).primaryColor 
        : Colors.grey;
    final Color iconColor = _isEditing 
        ? Theme.of(context).primaryColor 
        : Colors.grey.shade600;

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
            fontWeight: selectedItems.isNotEmpty ? FontWeight.w500 : FontWeight.normal,
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
  Widget _buildPresetButton(String presetName, ValueChanged<String> onItemToggle) {
    return ElevatedButton.icon(
      onPressed: _isEditing ? () {
        setState(() {
          _tempSelectedClothingItems.clear();
          _tempSelectedClothingItems.addAll(presetClothingCombos[presetName]!);
        });
      } : null,
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

  /// 構建 PMV 儀表板區域
  Widget _buildPMVSection() {
    return Container(
      padding: const EdgeInsets.all(20.0),
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
          // 環境資訊
          Row(
            children: [
              const Text(
                '當前環境資訊',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildInfoChip('溫度', '$_currentRoomTemp°C', Icons.device_thermostat),
              _buildInfoChip('濕度', '${_currentHumidity.toStringAsFixed(1)}%', Icons.water_drop),
              _buildInfoChip('建議', '$_recommendedTemp°C', Icons.recommend),
            ],
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
                const SizedBox(height: 16),
                CustomPaint(
                  size: const Size(220, 110),
                  painter: HalfCircleGaugePainter(pmvValue: _pmvValue),
                  child: Container(
                    width: 220,
                    height: 110,
                    alignment: Alignment.bottomCenter,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'PMV',
                          style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                        ),
                        Text(
                          '$_pmvValue',
                          style: TextStyle(
                            fontSize: 40,
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
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: _getComfortColor(_pmvValue),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _getPMVComfortLevel(_pmvValue),
                    style: const TextStyle(
                      fontSize: 18,
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

  /// 構建資訊晶片
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

  /// 根據 PMV 值獲取舒適度顏色
  Color _getComfortColor(int pmv) {
    if (pmv >= -1 && pmv <= 1) {
      return Colors.green;
    } else if (pmv >= -2 && pmv <= 2) {
      return Colors.orange;
    } else {
      return Colors.red;
    }
  }

  /// 構建當前設定總覽
  Widget _buildCurrentSettingsSummary(String activity, String clothing, String airflow) {
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
          _buildSummaryItem('活動類型', activity),
          _buildSummaryItem('穿著類型', clothing),
          _buildSummaryItem('空氣流速', airflow),
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

  /// 構建展開選單卡片
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
    final Color trailingColor = _isEditing 
        ? Theme.of(context).primaryColor 
        : Colors.grey;
    final Color iconColor = _isEditing 
        ? Theme.of(context).primaryColor 
        : Colors.grey.shade600;

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
            fontWeight: selectedValue != null ? FontWeight.w500 : FontWeight.normal,
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

  /// 構建單選按鈕群組
  Widget _buildRadioGroup({
    required String? currentValue,
    required List<String> options,
    required ValueChanged<String?>? onChanged,
  }) {
    return Column(
      children: options
          .map((option) => RadioListTile<String>(
                title: Text(
                  option,
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

// PMV 儀表板繪製器
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

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi,
      pi,
      false,
      arcPaint,
    );
  }

  void _drawTicks(Canvas canvas, Offset center, double radius) {
    const double tickLength = 10;
    final Paint tickPaint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2;

    // 繪製刻度線和標籤
    _drawTickWithLabel(canvas, center, radius, tickLength, tickPaint,
        Offset(center.dx - radius, center.dy), '-3', -15, 0);

    _drawTickWithLabel(canvas, center, radius, tickLength, tickPaint,
        Offset(center.dx, center.dy - radius), '0', -5, -tickLength - 5);

    _drawTickWithLabel(canvas, center, radius, tickLength, tickPaint,
        Offset(center.dx + radius, center.dy), '3', 5, 0);
  }

  void _drawTickWithLabel(
    Canvas canvas,
    Offset center,
    double radius,
    double tickLength,
    Paint tickPaint,
    Offset tickStart,
    String label,
    double labelOffsetX,
    double labelOffsetY,
  ) {
    canvas.drawLine(
      tickStart,
      Offset(tickStart.dx, tickStart.dy - tickLength),
      tickPaint,
    );

    TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: Colors.black, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )
      ..layout()
      ..paint(
        canvas,
        Offset(
          tickStart.dx + labelOffsetX,
          tickStart.dy - tickLength + labelOffsetY - 5,
        ),
      );
  }

  void _drawPointer(Canvas canvas, Offset center, double radius) {
    final double pointerLength = radius - 15;
    // 將 PMV 值從 -3 到 +3 映射到 0 到 1
    final double normalizedValue = (pmvValue.clamp(-3, 3) + 3) / 6;
    // 將標準化值映射到半圓弧(從左到右,即從 π 到 0)
    final double pointerAngle = pi * (1 - normalizedValue);

    final Paint pointerPaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      center,
      Offset(
        center.dx + pointerLength * cos(pointerAngle),
        center.dy - pointerLength * sin(pointerAngle),
      ),
      pointerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant HalfCircleGaugePainter oldDelegate) {
    return oldDelegate.pmvValue != pmvValue;
  }
}