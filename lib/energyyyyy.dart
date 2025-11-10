import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:iot_project/main.dart'; // 引入 main.dart 以使用 ApiService

class EnergySavingSettingsPage extends StatefulWidget {
  const EnergySavingSettingsPage({super.key});

  @override
  State<EnergySavingSettingsPage> createState() => _EnergySavingSettingsPageState();
}

class _EnergySavingSettingsPageState extends State<EnergySavingSettingsPage> {
  // 節能設定選項
  String? _selectedActivityType;
  String? _selectedClothingType;
  String? _selectedAirflowSpeed;

  // 編輯模式的暫存變數
  String? _tempSelectedActivityType;
  String? _tempSelectedClothingType;
  String? _tempSelectedAirflowSpeed;

  // 狀態控制
  bool _isEditing = false;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isActivityExpanded = false;
  bool _isClothingExpanded = false;
  bool _isAirflowExpanded = false;

  // 靜態選項資料
  static const List<String> _activityOptions = [
    '睡覺', '斜倚', '靜坐', '坐著閱讀', '寫作', '打字',
    '放鬆站立', '坐著歸檔', '站著歸檔', '四處走動', '烹飪',
    '提舉/打包', '坐著，肢體大量活動', '輕型機械操作', '打掃房屋',
    '健美操/徒手體操', '跳舞',
  ];

  static const Map<String, double> activityMETs = {
  '睡覺': 0.7,
  '斜倚': 0.8,
  '靜坐': 1.0,
  '坐著閱讀': 1.0,
  '寫作': 1.0,
  '打字': 1.1,
  '放鬆站立': 1.2,
  '坐著歸檔': 1.2,
  '站著歸檔': 1.4,
  '四處走動': 1.7,
  '烹飪': 1.8,
  '提舉/打包': 2.1,
  '坐著，肢體大量活動': 2.2,
  '輕型機械操作': 2.2,
  '打掃房屋': 2.7,
  '健美操/徒手體操': 3.5,
  '跳舞': 3.4,
};


  static const List<String> _clothingOptions = [
    '短褲、短袖襯衫', '典型夏季室內服裝', '及膝裙、短袖襯衫、涼鞋、內衣褲',
    '長褲、短袖襯衫、襪子、鞋子、內衣褲', '長褲、長袖襯衫',
    '及膝裙、長袖襯衫、連身襯裙', '運動長褲、長袖運動衫',
    '夾克、長褲、長袖襯衫', '典型冬季室內服裝',
  ];

  static const Map<String, double> clothingClo = {
  '短褲、短袖襯衫': 0.36,
  '典型夏季室內服裝': 0.50,
  '及膝裙、短袖襯衫、涼鞋、內衣褲': 0.45,
  '長褲、短袖襯衫、襪子、鞋子、內衣褲': 0.57,
  '長褲、長袖襯衫': 0.61,
  '及膝裙、長袖襯衫、連身襯裙': 0.67,
  '運動長褲、長袖運動衫': 0.74,
  '夾克、長褲、長袖襯衫': 0.96,
  '典型冬季室內服裝': 1.00,
};


  static const List<String> _airflowOptions = ['無風扇', '有風扇'];

  @override
  void initState() {
    super.initState();
    _fetchEnergySavingSettings();
  }

  /// 從後端獲取節能設定
  Future<void> _fetchEnergySavingSettings() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiService.get('/energy-saving/settings');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          // 根據資料庫欄位名稱映射
          _selectedActivityType = data['activity_type'];
          _selectedClothingType = data['clothing_type'];
          _selectedAirflowSpeed = data['airflow_speed'];

          // 同步暫存變數
          _tempSelectedActivityType = _selectedActivityType;
          _tempSelectedClothingType = _selectedClothingType;
          _tempSelectedAirflowSpeed = _selectedAirflowSpeed;
        });
        print('成功獲取節能設定: $data');
      } else if (response.statusCode == 404) {
        _showErrorSnackBar('找不到節能設定，請檢查帳戶設定');
      } else {
        _showErrorSnackBar('載入節能設定失敗');
        print('獲取節能設定失敗: ${response.statusCode}');
      }
    } catch (e) {
      print('獲取節能設定時發生錯誤: $e');
      _showErrorSnackBar('網路連線錯誤，請檢查連線狀態');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 向後端更新節能設定
  Future<void> _updateEnergySavingSettings() async {
    setState(() {
      _isSaving = true;
    });

    try {
      final response = await ApiService.post('/energy-saving/settings', {
        'activityType': _tempSelectedActivityType,
        'clothingType': _tempSelectedClothingType,
        'airflowSpeed': _tempSelectedAirflowSpeed,
      });

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('成功更新節能設定到後端: ${responseData['message']}');
        
        setState(() {
          // 將暫存值同步到正式值
          _selectedActivityType = _tempSelectedActivityType;
          _selectedClothingType = _tempSelectedClothingType;
          _selectedAirflowSpeed = _tempSelectedAirflowSpeed;
          
          // 退出編輯模式並收起所有選單
          _isEditing = false;
          _collapseAllExpansions();
        });

        _showSuccessSnackBar('節能設定已保存！');
      } else {
        final errorData = json.decode(response.body);
        _showErrorSnackBar('保存失敗：${errorData['message'] ?? '請重試'}');
        print('更新節能設定失敗: ${response.statusCode}');
      }
    } catch (e) {
      print('更新節能設定時發生錯誤: $e');
      _showErrorSnackBar('保存失敗，請檢查網路連接！');
    } finally {
      setState(() {
        _isSaving = false;
      });
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
        // 保存模式
        _updateEnergySavingSettings();
      } else {
        // 進入編輯模式
        _tempSelectedActivityType = _selectedActivityType;
        _tempSelectedClothingType = _selectedClothingType;
        _tempSelectedAirflowSpeed = _selectedAirflowSpeed;
        _isEditing = true;
        print('進入編輯模式');
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
          content: const Text('您有未保存的節能設定。是否要放棄更改並返回？'),
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
  void _handleOptionChanged(String type, String? newValue) {
    setState(() {
      switch (type) {
        case 'activity':
          _tempSelectedActivityType = newValue;
          _isActivityExpanded = false;
          break;
        case 'clothing':
          _tempSelectedClothingType = newValue;
          _isClothingExpanded = false;
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
      // 先收起所有選單
      _collapseAllExpansions();
      
      // 再展開指定的選單
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
    await _fetchEnergySavingSettings();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isEditing,
      onPopInvoked: (didPop) {
        if (!didPop && _isEditing) {
          _handleBackPress();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('節能設定'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _handleBackPress,
          ),
          actions: [
            if (_isEditing)
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _refreshData,
                tooltip: '重新整理',
              ),
          ],
        ),
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
                              '這些設定將影響系統的智慧節能計算，請根據您的實際情況選擇適合的選項。',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.blue.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 編輯/保存按鈕
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

                      // 活動類型
                      _buildExpansionTileCard(
                        title: '活動類型',
                        selectedValue: _isEditing ? _tempSelectedActivityType : _selectedActivityType,
                        isExpanded: _isActivityExpanded,
                        onExpansionChanged: (expanded) => _handleExpansionChanged('activity', expanded),
                        options: _activityOptions,
                        onOptionChanged: (value) => _handleOptionChanged('activity', value),
                        icon: Icons.directions_run,
                      ),
                      const SizedBox(height: 16),

                      // 穿著類型
                      _buildExpansionTileCard(
                        title: '穿著類型',
                        selectedValue: _isEditing ? _tempSelectedClothingType : _selectedClothingType,
                        isExpanded: _isClothingExpanded,
                        onExpansionChanged: (expanded) => _handleExpansionChanged('clothing', expanded),
                        options: _clothingOptions,
                        onOptionChanged: (value) => _handleOptionChanged('clothing', value),
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
                      const SizedBox(height: 20),

                      // 當前設定總覽
                      if (!_isEditing && 
                          _selectedActivityType != null && 
                          _selectedClothingType != null && 
                          _selectedAirflowSpeed != null)
                        _buildCurrentSettingsSummary(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  /// 建構當前設定總覽
  Widget _buildCurrentSettingsSummary() {
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
          _buildSummaryItem('活動類型', _selectedActivityType!),
          _buildSummaryItem('穿著類型', _selectedClothingType!),
          _buildSummaryItem('空氣流速', _selectedAirflowSpeed!),
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
              '$label：',
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

  /// 建構展開選單卡片
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

  /// 建構單選按鈕群組
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