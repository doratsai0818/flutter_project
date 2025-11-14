import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:iot_project/main.dart';

class EditProfilePage extends StatefulWidget {
  final String name;
  final String email;
  final String userId;

  const EditProfilePage({
    Key? key,
    required this.name,
    required this.email,
    required this.userId,
  }) : super(key: key);

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  // Controllers
  late TextEditingController _nameController;
  late TextEditingController _emailController;

  // State
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
    
    _nameController.addListener(_onTextChanged);
    _emailController.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _nameController.removeListener(_onTextChanged);
    _emailController.removeListener(_onTextChanged);
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final hasChanges = _nameController.text.trim() != widget.name || 
                      _emailController.text.trim() != widget.email;
    
    if (hasChanges != _hasUnsavedChanges) {
      setState(() {
        _hasUnsavedChanges = hasChanges;
      });
    }
  }

  Future<void> _updateUserProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiService.post('/user/profile', {
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
      });

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        
        if (responseData['success'] == true) {
          _showSnackBar('個人資料已成功更新!', isError: false);
          
          setState(() {
            _isEditing = false;
            _hasUnsavedChanges = false;
          });
          
          Navigator.pop(context, {
            'updated': true,
            'name': responseData['data']['name'],
            'email': responseData['data']['email'],
          });
        } else {
          _showSnackBar(responseData['message'] ?? '更新失敗', isError: true);
        }
        
      } else if (response.statusCode == 401) {
        _showSnackBar('登入已過期,請重新登入', isError: true);
        await _handleTokenExpired();
        
      } else if (response.statusCode == 409) {
        final errorData = json.decode(response.body);
        _showSnackBar(errorData['message'] ?? '此電子郵件已被使用', isError: true);
        
      } else if (response.statusCode == 400) {
        final errorData = json.decode(response.body);
        _showSnackBar(errorData['message'] ?? '輸入格式錯誤', isError: true);
        
      } else {
        final errorData = json.decode(response.body);
        _showSnackBar(errorData['message'] ?? '更新失敗,請重試', isError: true);
      }
      
    } catch (e) {
      print('更新個人資料時發生錯誤: $e');
      _showSnackBar('網路連線錯誤,請檢查伺服器狀態', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleTokenExpired() async {
    await TokenService.clearAuthData();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _toggleEditMode() {
    if (_isLoading) return;

    if (_isEditing) {
      _updateUserProfile();
    } else {
      setState(() {
        _isEditing = true;
      });
    }
  }

  void _showUnsavedChangesDialog() {
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('放棄修改?'),
          content: const Text('您有未保存的更改,確定要離開嗎?'),
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

  void _resetToOriginalValues() {
    _nameController.text = widget.name;
    _emailController.text = widget.email;
    setState(() {
      _isEditing = false;
      _hasUnsavedChanges = false;
    });
  }

  void _handleBackButtonPressed() {
    if (_isEditing && _hasUnsavedChanges) {
      _showUnsavedChangesDialog();
    } else {
      Navigator.pop(context, {'updated': false});
    }
  }

  void _showChangePasswordDialog() {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool obscureCurrent = true;
    bool obscureNew = true;
    bool obscureConfirm = true;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('修改密碼'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: currentPasswordController,
                      obscureText: obscureCurrent,
                      decoration: InputDecoration(
                        labelText: '當前密碼',
                        suffixIcon: IconButton(
                          icon: Icon(obscureCurrent ? Icons.visibility : Icons.visibility_off),
                          onPressed: () {
                            setDialogState(() {
                              obscureCurrent = !obscureCurrent;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: newPasswordController,
                      obscureText: obscureNew,
                      decoration: InputDecoration(
                        labelText: '新密碼',
                        suffixIcon: IconButton(
                          icon: Icon(obscureNew ? Icons.visibility : Icons.visibility_off),
                          onPressed: () {
                            setDialogState(() {
                              obscureNew = !obscureNew;
                            });
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: confirmPasswordController,
                      obscureText: obscureConfirm,
                      decoration: InputDecoration(
                        labelText: '確認新密碼',
                        suffixIcon: IconButton(
                          icon: Icon(obscureConfirm ? Icons.visibility : Icons.visibility_off),
                          onPressed: () {
                            setDialogState(() {
                              obscureConfirm = !obscureConfirm;
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (newPasswordController.text != confirmPasswordController.text) {
                      _showSnackBar('新密碼與確認密碼不符', isError: true);
                      return;
                    }
                    
                    if (newPasswordController.text.length < 6) {
                      _showSnackBar('密碼至少需要6個字元', isError: true);
                      return;
                    }

                    Navigator.of(dialogContext).pop();
                    await _changePassword(
                      currentPasswordController.text,
                      newPasswordController.text,
                    );
                  },
                  child: const Text('確認修改'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _changePassword(String currentPassword, String newPassword) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await ApiService.post('/user/change-password', {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      });

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        if (responseData['success'] == true) {
          _showSnackBar('密碼已成功更新!', isError: false);
        }
      } else if (response.statusCode == 401) {
        final errorData = json.decode(response.body);
        _showSnackBar(errorData['message'] ?? '當前密碼不正確', isError: true);
      } else {
        final errorData = json.decode(response.body);
        _showSnackBar(errorData['message'] ?? '密碼修改失敗', isError: true);
      }
    } catch (e) {
      _showSnackBar('網路連線錯誤', isError: true);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return '請輸入電子郵件';
    }
    if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value.trim())) {
      return '請輸入有效的電子郵件地址';
    }
    return null;
  }

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
                    _buildPasswordSection(),
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
            child: Text(
              widget.name.isNotEmpty ? widget.name[0].toUpperCase() : '?',
              style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold),
            ),
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

  Widget _buildPasswordSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '密碼',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.grey[200],
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.lock),
              const SizedBox(width: 12),
              const Text('••••••••'),
              const Spacer(),
              TextButton(
                onPressed: _showChangePasswordDialog,
                child: const Text('修改'),
              ),
            ],
          ),
        ),
      ],
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