import 'package:flutter/material.dart';
import 'dart:convert';

// 匯入 main.dart 中的服務類別
import 'package:iot_project/main.dart';

class EditProfilePage extends StatefulWidget {
  final String name;
  final String email;

  const EditProfilePage({
    super.key,
    required this.name,
    required this.email,
  });

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  // Controllers for input fields
  late TextEditingController _nameController;
  late TextEditingController _emailController;
  final TextEditingController _passwordController = TextEditingController();

  // State management
  bool _isEditing = false;
  bool _isLoading = false;
  bool _hasUnsavedChanges = false;

  // Form validation
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.name);
    _emailController = TextEditingController(text: widget.email);
    _passwordController.text = '******';
    
    // 監聽輸入變化
    _nameController.addListener(_onTextChanged);
    _emailController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_onTextChanged);
    _emailController.removeListener(_onTextChanged);
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// 監聽文字變化
  void _onTextChanged() {
    final hasChanges = _nameController.text != widget.name || 
                      _emailController.text != widget.email;
    
    if (hasChanges != _hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = hasChanges;
      });
    }
  }

  /// 使用 JWT token 發送更新用戶資料到後端
  Future<void> _updateUserProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // 使用 ApiService 發送帶有 JWT token 的請求
      final response = await ApiService.post('/user/profile', {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
      });

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        print('成功更新個人資料: $responseData');
        
        _showSnackBar('個人資料已成功更新！', isError: false);
        
        setState(() {
          _isEditing = false;
          _hasUnsavedChanges = false;
        });
        
        // 返回 true 告知上一頁資料已更新
        Navigator.pop(context, true);
        
      } else if (response.statusCode == 401) {
        // Token 過期
        _showSnackBar('登入已過期，請重新登入', isError: true);
        await _handleTokenExpired();
        
      } else if (response.statusCode == 409) {
        // 電子郵件已存在
        final errorData = json.decode(response.body);
        _showSnackBar(errorData['message'] ?? '此電子郵件已被使用', isError: true);
        
      } else {
        final errorData = json.decode(response.body);
        print('更新個人資料失敗: ${response.statusCode} - ${response.body}');
        _showSnackBar(errorData['message'] ?? '更新失敗，請重試', isError: true);
      }
      
    } catch (e) {
      print('更新個人資料時發生錯誤: $e');
      _showSnackBar('網路連線錯誤，請檢查伺服器狀態', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 處理 Token 過期
  Future<void> _handleTokenExpired() async {
    await TokenService.clearAuthData();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
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

  /// 切換編輯模式
  void _toggleEditMode() {
    if (_isLoading) return;

    if (_isEditing) {
      // 保存模式
      _updateUserProfile();
    } else {
      // 進入編輯模式
      setState(() {
        _isEditing = true;
      });
      print('進入編輯模式，可以修改個人資料');
    }
  }

  /// 顯示未保存變更對話框
  void _showUnsavedChangesDialog() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('放棄修改？'),
          content: const Text('您有未保存的更改，確定要離開嗎？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _resetToOriginalValues();
                Navigator.of(context).pop(false);
              },
              child: const Text(
                '放棄',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
        );
      },
    );
  }

  /// 重置到原始值
  void _resetToOriginalValues() {
    _nameController.text = widget.name;
    _emailController.text = widget.email;
    _passwordController.text = '******';
    setState(() {
      _isEditing = false;
      _hasUnsavedChanges = false;
    });
  }

  /// 處理返回按鈕
  void _handleBackButtonPressed() {
    if (_isEditing && _hasUnsavedChanges) {
      _showUnsavedChangesDialog();
    } else {
      Navigator.pop(context, false);
    }
  }

  /// Email 驗證
  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '請輸入電子郵件';
    }
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value.trim())) {
      return '請輸入有效的電子郵件地址';
    }
    return null;
  }

  /// 姓名驗證
  String? _validateName(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '請輸入姓名';
    }
    if (value.trim().length < 2) {
      return '姓名至少需要2個字元';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_isEditing && _hasUnsavedChanges) {
          _showUnsavedChangesDialog();
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('修改帳戶資料'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _isLoading ? null : _handleBackButtonPressed,
          ),
          actions: [
            if (_isEditing && _hasUnsavedChanges)
              TextButton(
                onPressed: _isLoading ? null : _resetToOriginalValues,
                child: const Text(
                  '重置',
                  style: TextStyle(color: Colors.orange),
                ),
              ),
          ],
        ),
        body: Stack(
          children: [
            Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildAvatarSection(),
                    const SizedBox(height: 24),
                    _buildNameField(),
                    const SizedBox(height: 16),
                    _buildEmailField(),
                    const SizedBox(height: 16),
                    _buildPasswordField(),
                    const SizedBox(height: 32),
                    _buildActionButton(),
                    const SizedBox(height: 20),
                    if (_isEditing) _buildEditingHint(),
                  ],
                ),
              ),
            ),
            if (_isLoading)
              Container(
                color: Colors.black26,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(
                        '正在更新...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarSection() {
    return Center(
      child: Stack(
        children: [
          CircleAvatar(
            radius: 60,
            backgroundColor: Theme.of(context).primaryColor.withOpacity(0.1),
            child: const Icon(Icons.person, size: 60, color: Colors.grey),
          ),
          if (_isEditing)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor,
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.camera_alt, color: Colors.white, size: 20),
                  onPressed: () {
                    // 未來可以實作頭像更換功能
                    _showSnackBar('頭像更換功能即將推出');
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    return _buildProfileInputField(
      label: '姓名',
      controller: _nameController,
      keyboardType: TextInputType.text,
      readOnly: !_isEditing,
      validator: _validateName,
      prefixIcon: Icons.person,
    );
  }

  Widget _buildEmailField() {
    return _buildProfileInputField(
      label: '電子郵件',
      controller: _emailController,
      keyboardType: TextInputType.emailAddress,
      readOnly: !_isEditing,
      validator: _validateEmail,
      prefixIcon: Icons.email,
    );
  }

  Widget _buildPasswordField() {
    return _buildProfileInputField(
      label: '密碼',
      controller: _passwordController,
      obscureText: true,
      keyboardType: TextInputType.visiblePassword,
      readOnly: true,
      prefixIcon: Icons.lock,
      suffixWidget: TextButton(
        onPressed: () {
          // 未來可以實作密碼修改功能
          _showSnackBar('密碼修改功能即將推出');
        },
        child: const Text('修改'),
      ),
    );
  }

  Widget _buildActionButton() {
    return Center(
      child: ElevatedButton(
        onPressed: _isLoading ? null : _toggleEditMode,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isEditing ? Colors.green : Theme.of(context).primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isLoading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else
              Icon(_isEditing ? Icons.save : Icons.edit),
            const SizedBox(width: 8),
            Text(
              _isLoading ? '處理中...' : (_isEditing ? '保存' : '編輯'),
              style: const TextStyle(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditingHint() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.blue.shade600),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '您正在編輯模式中。修改完成後請點擊"保存"按鈕。',
              style: TextStyle(
                color: Colors.blue.shade700,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileInputField({
    required String label,
    required TextEditingController controller,
    bool obscureText = false,
    TextInputType keyboardType = TextInputType.text,
    bool readOnly = false,
    String? Function(String?)? validator,
    IconData? prefixIcon,
    Widget? suffixWidget,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          keyboardType: keyboardType,
          readOnly: readOnly,
          validator: validator,
          style: TextStyle(
            color: readOnly ? Colors.grey[600] : Theme.of(context).primaryColor,
            fontSize: 16,
          ),
          decoration: InputDecoration(
            prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
            suffix: suffixWidget,
            filled: true,
            fillColor: readOnly
                ? Colors.grey[200]
                : Theme.of(context).primaryColor.withOpacity(0.1),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: Theme.of(context).primaryColor.withOpacity(0.3),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: Theme.of(context).primaryColor,
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Colors.red),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }
}