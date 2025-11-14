import 'package:flutter/material.dart';
import 'dart:convert';

import 'package:iot_project/notification_settings_page.dart';
import 'package:iot_project/edit_profile_page.dart';
import 'package:iot_project/main.dart';

class MyAccountPage extends StatefulWidget {
  final VoidCallback onLogout;
  final VoidCallback? onProfileUpdated; // ✅ 新增回調函數

  const MyAccountPage({
    super.key, 
    required this.onLogout,
    this.onProfileUpdated, // ✅ 可選參數
  });

  @override
  State<MyAccountPage> createState() => _MyAccountPageState();
}

class _MyAccountPageState extends State<MyAccountPage> {
  String _userName = '載入中...';
  String _userEmail = '載入中...';
  String _userId = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchUserProfile();
  }

  /// 從後端獲取用戶資料(使用 JWT token)
  Future<void> _fetchUserProfile() async {
    if (_isLoading) return;
    
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiService.get('/user/profile');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true && data['data'] != null) {
          if (mounted) {
            setState(() {
              _userId = data['data']['user_id'] ?? '';
              _userName = data['data']['name'] ?? '未設定';
              _userEmail = data['data']['email'] ?? '未設定';
            });
            
            // ✅ 同步更新 SharedPreferences 中的用戶資料
            await TokenService.saveAuthData(
              token: await TokenService.getToken() ?? '',
              userId: _userId,
              userName: _userName,
              userEmail: _userEmail,
            );
          }
          print('成功獲取用戶資料: ${data['data']}');
        } else {
          if (mounted) {
            setState(() {
              _userName = data['name'] ?? '未設定';
              _userEmail = data['email'] ?? '未設定';
            });
          }
          print('成功獲取用戶資料: $data');
        }
      } else if (response.statusCode == 401) {
        _showSnackBar('登入已過期,請重新登入', isError: true);
        await _handleTokenExpired();
      } else if (response.statusCode == 404) {
        _showSnackBar('找不到用戶資料', isError: true);
        if (mounted) {
          setState(() {
            _userName = '找不到資料';
            _userEmail = '找不到資料';
          });
        }
      } else {
        print('獲取用戶資料失敗: ${response.statusCode}');
        final errorBody = json.decode(response.body);
        _showSnackBar(errorBody['message'] ?? '獲取用戶資料失敗', isError: true);
        if (mounted) {
          setState(() {
            _userName = '載入失敗';
            _userEmail = '載入失敗';
          });
        }
      }
    } catch (e) {
      print('獲取用戶資料時發生錯誤: $e');
      if (mounted) {
        _showSnackBar('網路連線錯誤,請檢查伺服器狀態', isError: true);
        setState(() {
          _userName = '載入錯誤';
          _userEmail = '載入錯誤';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 處理 Token 過期的情況
  Future<void> _handleTokenExpired() async {
    await TokenService.clearAuthData();
    if (mounted) {
      widget.onLogout();
    }
  }

  /// 顯示訊息
  void _showSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// 登出確認對話框
  void _showLogoutConfirmationDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('確認登出'),
          content: const Text('您確定要登出帳戶嗎?'),
          actions: <Widget>[
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                
                try {
                  await ApiService.post('/auth/logout', {});
                } catch (e) {
                  print('登出 API 呼叫失敗: $e');
                }
                
                await TokenService.clearAuthData();
                widget.onLogout();
              },
              child: const Text(
                '確定登出',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 重新整理用戶資料
  Future<void> _refreshUserProfile() async {
    await _fetchUserProfile();
    
    // ✅ 通知 MainScreen 更新側邊欄
    if (widget.onProfileUpdated != null) {
      widget.onProfileUpdated!();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的帳戶'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refreshUserProfile,
            tooltip: '重新整理',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshUserProfile,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 個人資料區域
              Center(
                child: Column(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundColor: Colors.grey[200],
                          child: _isLoading
                              ? const CircularProgressIndicator()
                              : Text(
                                  _userName.isNotEmpty && _userName != '載入中...' 
                                      ? _userName[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    fontSize: 40,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                        if (_isLoading)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.blue,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.sync,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _userName,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _userEmail,
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          '更新中...',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // 設定選項列表
              _buildSettingsItem(
                context,
                title: '通知設定',
                icon: Icons.notifications,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const NotificationSettingsPage(),
                    ),
                  );
                },
              ),
              _buildSettingsItem(
                context,
                title: '修改帳戶資料',
                icon: Icons.edit,
                onTap: () async {
                  if (_userName == '載入中...' || _userName == '載入失敗' || _userName == '載入錯誤') {
                    _showSnackBar('請先等待用戶資料載入完成', isError: true);
                    return;
                  }

                  if (_userId.isEmpty) {
                    _showSnackBar('無法獲取用戶 ID,請重新整理頁面', isError: true);
                    return;
                  }

                  final result = await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => EditProfilePage(
                        name: _userName,
                        email: _userEmail,
                        userId: _userId,
                      ),
                    ),
                  );

                  // 如果編輯成功,重新獲取用戶資料
                  if (result != null && result is Map) {
                    if (result['updated'] == true) {
                      _showSnackBar('帳戶資料更新成功');
                      
                      // 重新獲取最新資料
                      await _refreshUserProfile();
                    }
                  }
                },
              ),
              _buildSettingsItem(
                context,
                title: '登出',
                icon: Icons.logout,
                isDestructive: true,
                onTap: () {
                  _showLogoutConfirmationDialog(context);
                },
              ),

              const SizedBox(height: 40),

              // 版本資訊
              Center(
                child: Column(
                  children: [
                    Text(
                      '智慧節能系統 v1.0.0',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[500],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '© 2024 Smart Energy System',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 設定選項列表項
  Widget _buildSettingsItem(
    BuildContext context, {
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12.0),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 16.0,
            vertical: 12.0,
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isDestructive ? Colors.red : Colors.grey[600],
                size: 24,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: isDestructive ? Colors.red : null,
                  ),
                ),
              ),
              if (!isDestructive)
                const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.grey,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}