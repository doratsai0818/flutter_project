// main.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// 確保這些匯入路徑是正確的
import 'package:iot_project/home_page.dart';
import 'package:iot_project/lighting_control_page.dart';
import 'package:iot_project/ac_control_page.dart';
import 'package:iot_project/power_monitoring_page.dart';
import 'package:iot_project/my_account_page.dart';
import 'package:iot_project/fan_control_page.dart';
import 'package:iot_project/sensor_data_page.dart';

const String baseUrl = 'http://localhost:3000/api';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '智慧節能系統',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        useMaterial3: true,
      ),
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Token 管理服務
class TokenService {
  static const String _tokenKey = 'auth_token';
  static const String _userIdKey = 'user_id';
  static const String _userNameKey = 'user_name';
  static const String _userEmailKey = 'user_email';

  static Future<void> saveAuthData({
    required String token,
    required String userId,
    required String userName,
    required String userEmail,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, token);
    await prefs.setString(_userIdKey, userId);
    await prefs.setString(_userNameKey, userName);
    await prefs.setString(_userEmailKey, userEmail);
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_tokenKey);
  }

  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }

  static Future<Map<String, String?>> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'userId': prefs.getString(_userIdKey),
      'userName': prefs.getString(_userNameKey),
      'userEmail': prefs.getString(_userEmailKey),
    };
  }

  static Future<void> clearAuthData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userIdKey);
    await prefs.remove(_userNameKey);
    await prefs.remove(_userEmailKey);
  }

  static Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}

// HTTP 請求服務
class ApiService {
  static Future<Map<String, String>> _getHeaders() async {
    final token = await TokenService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<http.Response> get(String endpoint) async {
    final headers = await _getHeaders();
    return await http.get(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
    );
  }

  static Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    final headers = await _getHeaders();
    return await http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: json.encode(body),
    );
  }

  static Future<http.Response> put(String endpoint, Map<String, dynamic> body) async {
    final headers = await _getHeaders();
    return await http.put(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: json.encode(body),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isLoggedIn = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final isLoggedIn = await TokenService.isLoggedIn();
    if (mounted) {
      setState(() {
        _isLoggedIn = isLoggedIn;
        _isLoading = false;
      });
    }
  }

  void _loginSuccess() {
    if (mounted) {
      setState(() {
        _isLoggedIn = true;
      });
    }
  }

  Future<void> _logout() async {
    await TokenService.clearAuthData();
    if (mounted) {
      setState(() {
        _isLoggedIn = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_isLoggedIn) {
      return MainScreen(onLogout: _logout);
    } else {
      return AuthPage(onLoginSuccess: _loginSuccess);
    }
  }
}

class AuthPage extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  const AuthPage({super.key, required this.onLoginSuccess});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool isRegistering = false;
  bool _isLoading = false;

  // 登入表單控制器
  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _loginFormKey = GlobalKey<FormState>();

  // 註冊表單控制器
  final _registerNameController = TextEditingController();
  final _registerEmailController = TextEditingController();
  final _registerPasswordController = TextEditingController();
  final _registerFormKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _registerNameController.dispose();
    _registerEmailController.dispose();
    _registerPasswordController.dispose();
    super.dispose();
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
        ),
      );
    }
  }

  Future<void> _handleRegister() async {
    if (!_registerFormKey.currentState!.validate() || _isLoading) return;

    setState(() => _isLoading = true);

    try {
      final response = await ApiService.post('/auth/register', {
        'name': _registerNameController.text,
        'email': _registerEmailController.text,
        'password': _registerPasswordController.text,
      });

      if (response.statusCode == 201) {
        _showSnackBar('註冊成功！現在可以登入了。');
        if (mounted) {
          setState(() {
            isRegistering = false;
            // 清空註冊表單
            _registerNameController.clear();
            _registerEmailController.clear();
            _registerPasswordController.clear();
          });
        }
      } else {
        final responseBody = json.decode(response.body);
        _showSnackBar(responseBody['message'] ?? '註冊失敗', isError: true);
      }
    } catch (e) {
      _showSnackBar('連線失敗，請檢查伺服器是否運行。', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLogin() async {
    if (!_loginFormKey.currentState!.validate() || _isLoading) return;

    setState(() => _isLoading = true);

    try {
      final response = await ApiService.post('/auth/login', {
        'email': _loginEmailController.text,
        'password': _loginPasswordController.text,
      });

      if (response.statusCode == 200) {
        final responseBody = json.decode(response.body);
        
        // 保存認證資料
        await TokenService.saveAuthData(
          token: responseBody['token'] ?? '',
          userId: responseBody['user']['id'] ?? '',
          userName: responseBody['user']['name'] ?? '',
          userEmail: responseBody['user']['email'] ?? '',
        );

        _showSnackBar('登入成功！歡迎回來。');
        widget.onLoginSuccess();
      } else {
        final responseBody = json.decode(response.body);
        _showSnackBar(responseBody['message'] ?? '登入失敗', isError: true);
      }
    } catch (e) {
      _showSnackBar('連線失敗，請檢查伺服器是否運行。', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isRegistering ? '用戶註冊' : '用戶登入'),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: isRegistering ? _buildRegisterForm() : _buildLoginForm(),
            ),
          ),
          if (_isLoading)
            const Opacity(
              opacity: 0.8,
              child: ModalBarrier(dismissible: false, color: Colors.black26),
            ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }

  Widget _buildLoginForm() {
    return Form(
      key: _loginFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.lock_person, size: 80, color: Colors.blue),
          const SizedBox(height: 24),
          TextFormField(
            controller: _loginEmailController,
            decoration: const InputDecoration(
              labelText: '電子郵件',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.email),
            ),
            keyboardType: TextInputType.emailAddress,
            enabled: !_isLoading,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '請輸入電子郵件';
              }
              if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                return '請輸入有效的電子郵件地址';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _loginPasswordController,
            decoration: const InputDecoration(
              labelText: '密碼',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock),
            ),
            obscureText: true,
            enabled: !_isLoading,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '請輸入密碼';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isLoading ? null : _handleLogin,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('登入', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _isLoading ? null : () {
              if (mounted) {
                setState(() {
                  isRegistering = true;
                });
              }
            },
            child: const Text('沒有帳號？點此註冊'),
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterForm() {
    return Form(
      key: _registerFormKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person_add_alt_1, size: 80, color: Colors.green),
          const SizedBox(height: 24),
          TextFormField(
            controller: _registerNameController,
            decoration: const InputDecoration(
              labelText: '姓名',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person),
            ),
            enabled: !_isLoading,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '請輸入姓名';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _registerEmailController,
            decoration: const InputDecoration(
              labelText: '電子郵件',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.email),
            ),
            keyboardType: TextInputType.emailAddress,
            enabled: !_isLoading,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return '請輸入電子郵件';
              }
              if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(value)) {
                return '請輸入有效的電子郵件地址';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _registerPasswordController,
            decoration: const InputDecoration(
              labelText: '密碼',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock),
            ),
            obscureText: true,
            enabled: !_isLoading,
            validator: (value) {
              if (value == null || value.length < 6) {
                return '密碼必須至少為6個字元';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isLoading ? null : _handleRegister,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            child: _isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Text('註冊', style: TextStyle(fontSize: 18)),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _isLoading ? null : () {
              if (mounted) {
                setState(() {
                  isRegistering = false;
                });
              }
            },
            child: const Text('已經有帳號？點此登入'),
          ),
        ],
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const MainScreen({super.key, required this.onLogout});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  Map<String, String?> _userData = {};
  List<Widget>? _pages; // 將 _pages 設為可為 null
  bool _isLoadingPages = true;

  @override
  void initState() {
    super.initState();
    _loadAllData(); // 建立一個方法來載入所有非同步資料
  }
  
  // 處理所有非同步資料載入
  Future<void> _loadAllData() async {
    await _loadUserData();
    await _initPages();
  }

  Future<void> _initPages() async {
    final token = await TokenService.getToken();
    if (mounted) {
      setState(() {
        _pages = <Widget>[
          const HomePage(),
          const LightingControlPage(),
          const ACControlPage(),
          const PowerMonitoringPage(),
          FanControlPage(jwtToken: token!),
          const SensorDataPage(),
        ];
        _isLoadingPages = false; // 頁面載入完成
      });
    }
  }

  Future<void> _loadUserData() async {
    final userData = await TokenService.getUserData();
    if (mounted) {
      setState(() {
        _userData = userData;
      });
    }
  }

  String _getPageTitle(int index) {
    if (_pages == null || index >= _pages!.length) return '智慧節能系統';
    switch (_pages![index].runtimeType) {
      case HomePage:
        return '首頁';
      case LightingControlPage:
        return '燈光控制';
      case ACControlPage:
        return '冷氣控制';
      case PowerMonitoringPage:
        return '用電監控';
      case FanControlPage:
        return '風扇控制';
      case SensorDataPage:
        return '感測數據監控';
      default:
        return '智慧節能系統';
    }
  }

  void _onDrawerItemTapped(int index) {
    if (_isLoadingPages) return;
    setState(() {
      _selectedIndex = index;
    });
    Navigator.pop(context);
  }

  void _navigateToMyAccount() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MyAccountPage(onLogout: widget.onLogout),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('確認登出'),
          content: const Text('您確定要登出嗎？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onLogout();
              },
              child: const Text('登出', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingPages) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_getPageTitle(_selectedIndex)),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle),
            onPressed: _navigateToMyAccount,
            tooltip: '我的帳戶',
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            UserAccountsDrawerHeader(
              decoration: const BoxDecoration(
                color: Colors.deepPurple,
              ),
              accountName: Text(_userData['userName'] ?? '用戶'),
              accountEmail: Text(_userData['userEmail'] ?? ''),
              currentAccountPicture: const CircleAvatar(
                backgroundColor: Colors.white,
                child: Icon(
                  Icons.person,
                  color: Colors.deepPurple,
                  size: 40,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.home),
              title: const Text('首頁'),
              selected: _selectedIndex == 0,
              onTap: () => _onDrawerItemTapped(0),
            ),
            ListTile(
              leading: const Icon(Icons.lightbulb),
              title: const Text('燈光控制'),
              selected: _selectedIndex == 1,
              onTap: () => _onDrawerItemTapped(1),
            ),
            ListTile(
              leading: const Icon(Icons.ac_unit),
              title: const Text('冷氣控制'),
              selected: _selectedIndex == 2,
              onTap: () => _onDrawerItemTapped(2),
            ),
            ListTile(
              leading: const Icon(Icons.power),
              title: const Text('用電監控'),
              selected: _selectedIndex == 3,
              onTap: () => _onDrawerItemTapped(3),
            ),
            ListTile(
              leading: const Icon(Icons.air),
              title: const Text('風扇控制'),
              selected: _selectedIndex == 4,
              onTap: () => _onDrawerItemTapped(4),
            ),
            ListTile(
              leading: const Icon(Icons.sensors),
              title: const Text('感測數據監控'),
              selected: _selectedIndex == 5,
              onTap: () => _onDrawerItemTapped(5),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('登出', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _showLogoutDialog();
              },
            ),
          ],
        ),
      ),
      body: _pages![_selectedIndex],
    );
  }
}