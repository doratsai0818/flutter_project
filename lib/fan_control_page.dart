import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:iot_project/config.dart';

// 風扇控制頁面
class FanControlPage extends StatefulWidget {
  final String jwtToken;
  const FanControlPage({super.key, required this.jwtToken});

  @override
  State<FanControlPage> createState() => _FanControlPageState();
}

class _FanControlPageState extends State<FanControlPage> {
  final String _baseUrl = Config.apiUrl;

  // 風扇狀態變數
  bool _isFanOn = false;
  bool _isManualMode = true; // 從後端同步的全局模式
  int _fanSpeed = 0; // 風速現在代表 1-8 級,0 代表關閉
  bool _isOscillationOn = false; // 左右擺頭
  bool _isVerticalSwingOn = false; // 上下擺頭
  bool _isDisplayOn = true; // 液晶顯示
  bool _isMuteOn = false; // 靜音
  String _currentMode = 'normal'; // 模式新增 'eco'
  bool _isLoading = false;
  bool _hasError = false;
  String _errorMessage = '';

  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _fetchFanStatus();
    // 啟動定時刷新，確保狀態與後端同步
    _statusTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (!_isLoading) {
        _fetchFanStatus();
      }
    });
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    super.dispose();
  }

  // 獲取風扇狀態 (同時獲取風扇細節和全局模式)
  Future<void> _fetchFanStatus() async {
    setState(() => _isLoading = true);
    try {
      // 同時發送兩個請求：獲取風扇狀態和全局模式
      final results = await Future.wait([
        http.get(
          Uri.parse('$_baseUrl/fan/status'),
          headers: {
            'Content-Type': 'application/json',
            'ngrok-skip-browser-warning': 'true',
            'Authorization': 'Bearer ${widget.jwtToken}',
          },
        ),
        http.get(
          Uri.parse('$_baseUrl/system/global-mode'),
          headers: {
            'Content-Type': 'application/json',
            'ngrok-skip-browser-warning': 'true',
            'Authorization': 'Bearer ${widget.jwtToken}',
          },
        ),
      ]);

      final fanResponse = results[0];
      final globalModeResponse = results[1];

      if (fanResponse.statusCode == 200 && globalModeResponse.statusCode == 200) {
        final fanData = jsonDecode(fanResponse.body)['data'];
        final globalModeData = jsonDecode(globalModeResponse.body);

        setState(() {
          // 1. 同步風扇本地狀態
          _isFanOn = fanData['isOn'] ?? false;
          _fanSpeed = fanData['speed'] ?? 0;
          if (_fanSpeed < 0 || _fanSpeed > 8) _fanSpeed = 0;
          _isOscillationOn = fanData['oscillation'] ?? false;
          _isVerticalSwingOn = fanData['verticalSwing'] ?? false;
          _isDisplayOn = fanData['isDisplayOn'] ?? true;
          _isMuteOn = fanData['isMuteOn'] ?? false;
          _currentMode = fanData['mode'] ?? 'normal';
          
          // 2. 同步全局模式狀態 (關鍵)
          _isManualMode = globalModeData['isManualMode'] ?? true;

          _hasError = false;
          _errorMessage = '';
        });
      } else {
        // 處理錯誤
        final String errorBody = fanResponse.statusCode != 200 ? fanResponse.body : globalModeResponse.body;
        final int statusCode = fanResponse.statusCode != 200 ? fanResponse.statusCode : globalModeResponse.statusCode;

        debugPrint('獲取風扇狀態失敗: $statusCode $errorBody');
        setState(() {
          _hasError = true;
          _errorMessage = '無法獲取風扇狀態 (HTTP $statusCode)';
        });
      }
    } catch (e) {
      debugPrint('無法獲取風扇狀態: $e');
      setState(() {
        _hasError = true;
        _errorMessage = '網路連線失敗,請檢查伺服器狀態';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 發送控制指令 (核心方法) - 使用紅外線 API
  Future<void> _sendControlCommand(String endpoint, Map<String, dynamic> body) async {
    // 檢查是否為模式或風速控制,且不在手動模式
    if (endpoint == 'speed' || endpoint == 'mode' || endpoint == 'oscillation' || endpoint == 'verticalSwing') {
      if (!_isManualMode) {
        _showSnackBar('請先切換到手動模式才能調整風扇', isError: true);
        return;
      }
    }

    // 特殊處理:電源按鈕邏輯 (這裡的邏輯可以簡化,直接讓 IR 處理)

    setState(() => _isLoading = true);
    
    try {
      // 映射前端指令到 IR 動作
      String irAction = _mapEndpointToIRAction(endpoint, body);
      
      debugPrint('發送指令: endpoint=$endpoint, action=$irAction');
      
      // 發送紅外線控制指令
      final response = await http.post(
        Uri.parse('$_baseUrl/aircon'),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
          'Authorization': 'Bearer ${widget.jwtToken}',
        },
        body: jsonEncode({
          'device': 'fan',
          'action': irAction
        }),
      );
      
      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          // 成功時等待後端 DB 更新，然後從 DB 獲取最新的狀態
          await Future.delayed(const Duration(milliseconds: 500)); 
          await _fetchFanStatus();
          
          _showSnackBar('操作成功');
        } else {
          _showSnackBar(responseData['message'] ?? '控制失敗', isError: true);
        }
      } else if (response.statusCode == 401) {
        _showSnackBar('認證失效,請重新登入', isError: true);
      } else {
        final responseData = jsonDecode(response.body);
        _showSnackBar(responseData['message'] ?? '控制失敗', isError: true);
      }
    } catch (e) {
      debugPrint('發送控制指令失敗: $e');
      _showSnackBar('網路連線失敗,請檢查伺服器狀態', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  // 映射前端指令到紅外線動作
  String _mapEndpointToIRAction(String endpoint, Map<String, dynamic> body) {
    switch (endpoint) {
      case 'power':
        return 'power';
      case 'speed_up':
        return 'speed_up';
      case 'speed_down':
        return 'speed_down';
      case 'speed':
        // 如果是直接設定速度,則需要根據差異發送多個指令 (但 IR 邏輯已在後端處理,這裡應該只發送一次升或降)
        int currentSpeed = _fanSpeed;
        int targetSpeed = body['speed'] ?? 1;
        
        if (targetSpeed > currentSpeed) return 'speed_up';
        if (targetSpeed < currentSpeed) return 'speed_down';
        
        // 速度相同,不發送,或返回一個無害指令
        return 'power'; 

      case 'oscillation':
        return 'swing_horizontal'; // 使用後端 IR 動作名稱
        
      case 'verticalSwing':
        return 'swing_vertical'; // 使用後端 IR 動作名稱
        
      case 'mode':
        return 'mode';
        
      case 'mute':
        return 'voice'; // 使用後端 IR 動作名稱
        
      case 'display':
        return 'light'; // 使用後端 IR 動作名稱
        
      default:
        return 'power';
    }
  }
  
  // 更新本地狀態 (由於 IR 指令後端會更新 DB,前端只需要同步 DB 狀態即可,這裡保留為輔助)
  Future<void> _updateLocalState(String endpoint, Map<String, dynamic> body) async {
    // 實際上,由於 _sendControlCommand 會調用 _fetchFanStatus,這個函數的作用已經減弱,
    // 僅用於 UI 快速響應,但在 IR 控制下最好依賴 DB 刷新。
    // 我們讓它保持輕量，並且不應該再直接更新 DB。
    
    // 由於後端 API 會處理狀態更新，這裡可以簡化，或直接依賴 _fetchFanStatus。
    // 為了更好的 UI 響應速度，我們仍然可以進行樂觀更新。
    setState(() {
      switch (endpoint) {
        case 'power':
          _isFanOn = !_isFanOn;
          if (!_isFanOn) _fanSpeed = 0;
          break;
        case 'oscillation':
          _isOscillationOn = !_isOscillationOn;
          break;
        case 'verticalSwing':
          _isVerticalSwingOn = !_isVerticalSwingOn;
          break;
        case 'mute':
          _isMuteOn = !_isMuteOn;
          break;
        case 'display':
          _isDisplayOn = !_isDisplayOn;
          break;
        case 'mode':
          // 樂觀更新模式
          switch (_currentMode) {
            case 'normal':
              _currentMode = 'natural';
              break;
            case 'natural':
              _currentMode = 'sleep';
              break;
            case 'sleep':
              _currentMode = 'eco';
              break;
            case 'eco':
            default:
              _currentMode = 'normal';
          }
          break;
      }
    });
  }
  
  // 更新手動/自動模式 (呼叫全局 API)
  Future<void> _updateManualMode(bool value) async {
    setState(() => _isLoading = true); // 鎖定 UI

    try {
      // 💡 呼叫全局模式 API，後端會同步所有設備 (AC, Light, Fan)
      final response = await http.post(
        Uri.parse('$_baseUrl/system/global-mode'),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
          'Authorization': 'Bearer ${widget.jwtToken}',
        },
        body: jsonEncode({'isManualMode': value}),
      );
      
      if (response.statusCode == 200) {
        // 成功後，讓 _fetchFanStatus 從 DB 讀取最新的全局同步狀態
        await _fetchFanStatus(); 
        _showSnackBar(value ? '系統已切換到手動模式' : '系統已切換到自動模式');
      } else {
        final responseData = jsonDecode(response.body);
        _showSnackBar(responseData['message'] ?? '更新模式失敗', isError: true);
        
        // 切換失敗，UI 狀態恢復
        setState(() {
          _isManualMode = !value; 
        });
      }
    } catch (e) {
      debugPrint('更新全局模式失敗: $e');
      _showSnackBar('網路連線錯誤，無法切換模式', isError: true);
      // 網路錯誤，UI 狀態恢復
      setState(() {
        _isManualMode = !value; 
      });
    } finally {
      setState(() => _isLoading = false); // 解鎖 UI
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
          duration: Duration(seconds: isError ? 4 : 2),
        ),
      );
    }
  }

  // 獲取風類標籤
  String _getModeLabel(String mode) {
    switch (mode) {
      case 'natural':
        return '自然風';
      case 'sleep':
        return '睡眠風';
      case 'eco':
        return 'ECO溫控';
      default:
        return '一般風';
    }
  }

  // 模式按鈕的 UI (改為單一按鈕)
  Widget _buildModeButton() {
    // 根據當前模式顯示不同文字和顏色
    String modeLabel;
    Color modeColor;
    
    switch (_currentMode) {
      case 'natural':
        modeLabel = '自然風';
        modeColor = Colors.green;
        break;
      case 'sleep':
        modeLabel = '睡眠風';
        modeColor = const Color.fromARGB(255, 186, 107, 255);
        break;
      case 'eco':
        modeLabel = 'ECO溫控';
        modeColor = const Color.fromARGB(255, 10, 200, 206);
        break;
      default: // 'normal'
        modeLabel = '一般風';
        modeColor = Colors.blue;
    }
    
    bool isDisabled = !_isManualMode;
    
    return ElevatedButton.icon(
      // 按鈕點擊後應該發送 mode 指令給後端,讓後端去循環切換
      onPressed: isDisabled ? null : () => _sendControlCommand('mode', {}),
      style: ElevatedButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: isDisabled ? Colors.grey : modeColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      ),
      icon: const Icon(Icons.air, size: 24),
      label: Text(
        '風類: $modeLabel',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
  
  // 建構功能按鈕的 Helper Widget
  Widget _buildFeatureButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onPressed,
  }) {
    bool isDisabled = !_isManualMode;

    return Column(
      children: [
        IconButton(
          onPressed: isDisabled ? null : onPressed,
          icon: Icon(
            icon,
            size: 40,
            color: isDisabled ? Colors.grey : (isActive ? Colors.blue : Colors.black),
          ),
        ),
        Text(label, style: TextStyle(color: isDisabled ? Colors.grey : Colors.black)),
      ],
    );
  }
  
  // 風速增減控制邏輯 - 支持 1-8 級
  void _changeSpeed(bool isIncrement) async {
    if (!_isManualMode) {
      _showSnackBar('請先切換到手動模式才能調整風速', isError: true);
      return;
    }
    
    int newSpeed = _fanSpeed;
    if (isIncrement) {
      if (_fanSpeed >= 8) {
        _showSnackBar('已達最大風速 (8 級)', isError: true);
        return;
      }
      newSpeed = _fanSpeed + 1;
    } else {
      if (_fanSpeed <= 1) {
        _showSnackBar('已達最小風速 (1 級)', isError: true);
        return;
      }
      newSpeed = _fanSpeed - 1;
    }

    setState(() => _isLoading = true);
    
    try {
      // 呼叫 _sendControlCommand,讓後端處理風速指令的發送和 DB 更新
      if (isIncrement) {
        await _sendControlCommand('speed_up', {});
      } else {
        await _sendControlCommand('speed_down', {});
      }
      
      // 樂觀更新,之後會被 _fetchFanStatus 覆蓋
      setState(() {
        _fanSpeed = newSpeed;
      });
      
      _showSnackBar('風速已調整至 $newSpeed 級');
    } catch (e) {
      debugPrint('調整風速失敗: $e');
      _showSnackBar('風速調整失敗', isError: true);
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  // 自動/手動模式控制區塊
  Widget _buildFanModeControl() {
    return Row(
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
                fontSize: 18,
                fontWeight: FontWeight.bold,
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
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _isManualMode ? Theme.of(context).primaryColor : Colors.grey,
              ),
            ),
          ],
        ),
      ],
    );
  }


  @override
  Widget build(BuildContext context) {
    final primaryColor = Colors.blue;

    return Scaffold(
      body: _hasError
          ? Center(
              // 錯誤訊息顯示區塊
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Colors.red.shade400,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '連線失敗',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _errorMessage,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: _fetchFanStatus,
                      child: const Text('重新連線'),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _fetchFanStatus,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 狀態顯示區塊
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
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
                            Text(
                              _isFanOn ?
                              '風扇狀態:開啟' : '風扇狀態:關閉',
                              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _isFanOn ? primaryColor : Colors.red),
                            ),
                            const SizedBox(height: 10),
                            // 模式狀態提示
                            Text(
                              _isManualMode ? '當前模式:手動' : '當前模式:自動 (由中央系統控制)',
                              style: TextStyle(fontSize: 16, color: _isManualMode ? Colors.black87 : Colors.orange),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '當前風類: ${_getModeLabel(_currentMode)}',
                              style: const TextStyle(fontSize: 16),
                            ),
                            Text(
                              '當前風速:${_isFanOn ? _fanSpeed : 0} 級 (Max 8)',
                              style: const TextStyle(fontSize: 18),
                            ),
                            if (_isMuteOn) ...[
                              const SizedBox(height: 5),
                              const Text(
                                '提示音已關閉 (靜音)',
                                style: TextStyle(fontSize: 14, color: Colors.teal),
                              ),
                            ],
                            if (!_isDisplayOn) ...[
                              const SizedBox(height: 5),
                              const Text(
                                '液晶顯示已關閉',
                                style: TextStyle(fontSize: 14, color: Colors.orange),
                              ),
                            ],
                          ],
                        ),
                      ),
                      
                      const SizedBox(height: 20),

                      // 控制按鈕區塊
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
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
                            // 自動/手動模式控制
                            _buildFanModeControl(),
                            const SizedBox(height: 20),

                            // 電源按鈕
                            Column(
                              children: [
                                ElevatedButton(
                                  // 只有在手動模式下才允許操作
                                  onPressed: _isManualMode ? () => _sendControlCommand('power', {'isOn': !_isFanOn}) : null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _isFanOn ? Colors.red : Colors.green,
                                    shape: const CircleBorder(),
                                    padding: const EdgeInsets.all(20),
                                  ),
                                  child: const Icon(
                                    Icons.power_settings_new,
                                    color: Colors.white,
                                    size: 40,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _isFanOn ? '風扇:開啟' : '風扇:關閉',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: _isFanOn ? Colors.green : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),

                            // 風速控制 - 左右箭頭切換 1-8 級
                            const Text('風速控制 (1-8 級)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                // 減風速按鈕
                                IconButton(
                                  icon: const Icon(Icons.arrow_left, size: 48),
                                  onPressed: (_isLoading || !_isManualMode || _fanSpeed <= 1) ? null : () => _changeSpeed(false),
                                  color: (_isManualMode && _fanSpeed > 1) ? primaryColor : Colors.grey,
                                ),
                                
                                // 當前風速顯示
                                Container(
                                  width: 80,
                                  height: 80,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: primaryColor, width: 2),
                                  ),
                                  child: Text(
                                    '${_isFanOn ? _fanSpeed : 0}',
                                    style: TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.bold,
                                      color: _isManualMode ? primaryColor : Colors.grey
                                    ),
                                  ),
                                ),

                                // 加風速按鈕
                                IconButton(
                                  icon: const Icon(Icons.arrow_right, size: 48),
                                  onPressed: (_isLoading || !_isManualMode || _fanSpeed >= 8) ? null : () => _changeSpeed(true),
                                  color: (_isManualMode && _fanSpeed < 8) ? primaryColor : Colors.grey,
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            
                            // 模式控制 (風類) - 改為單一按鈕
                            const Text('風類切換', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            Center(child: _buildModeButton()),
                            const SizedBox(height: 8),
                            Center(
                              child: Text(
                                '按下按鈕循環切換: 一般風 → 自然風 → 睡眠風 → ECO',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 20),


                            // 功能按鈕:擺頭、靜音、顯示
                            const Text('功能控制', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 10),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceAround,
                                children: [
                                  // 左右擺頭按鈕
                                  _buildFeatureButton(
                                    icon: Icons.swap_horiz,
                                    label: '左右擺頭',
                                    isActive: _isOscillationOn,
                                    onPressed: _isManualMode ? () => _sendControlCommand('oscillation', {'oscillation': !_isOscillationOn}) : () {},
                                  ),
                                  const SizedBox(width: 16),

                                  // 上下擺頭按鈕
                                  _buildFeatureButton(
                                    icon: Icons.swap_vert,
                                    label: '上下擺頭',
                                    isActive: _isVerticalSwingOn,
                                    onPressed: _isManualMode ? () => _sendControlCommand('verticalSwing', {'verticalSwing': !_isVerticalSwingOn}) : () {},
                                  ),
                                  const SizedBox(width: 16),

                                  // 液晶顯示按鈕
                                  _buildFeatureButton(
                                    icon: _isDisplayOn ? Icons.lightbulb : Icons.lightbulb_outline,
                                    label: '液晶顯示',
                                    isActive: _isDisplayOn,
                                    onPressed: _isManualMode ? () => _sendControlCommand('display', {'isDisplayOn': !_isDisplayOn}) : () {},
                                  ),

                                  const SizedBox(width: 16),

                                  // 靜音按鈕
                                  _buildFeatureButton(
                                    icon: _isMuteOn ? Icons.volume_off : Icons.volume_up,
                                    label: '靜音',
                                    isActive: _isMuteOn,
                                    onPressed: _isManualMode ? () => _sendControlCommand('mute', {'isMuteOn': !_isMuteOn}) : () {},
                                  ),
                                ],
                              ),
                            ),

                            // 載入指示器
                            if (_isLoading) ...[
                              const SizedBox(height: 20),
                              const Card(
                                child: Padding(
                                  padding: EdgeInsets.all(16.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                      SizedBox(width: 12),
                                      Text('處理中...'),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}