// main.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb; // ✅ 新增
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iot_project/config.dart';
import 'package:flutter_localizations/flutter_localizations.dart'; // ✅ 新增
// 在文件開頭添加導入
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ✅ 修改 Firebase 相關導入 - 使用條件導入
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';

import 'package:iot_project/home_page.dart';
import 'package:iot_project/lighting_control_page.dart';
import 'package:iot_project/ac_control_page.dart';
import 'package:iot_project/power_monitoring_page.dart';
import 'package:iot_project/my_account_page.dart';
import 'package:iot_project/fan_control_page.dart';
import 'package:iot_project/sensor_data_page.dart';
import 'package:iot_project/energy_saving_settings_page.dart';
// ✅ 需要在文件開頭添加這個導入
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

// 創建全局變量
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = 
    FlutterLocalNotificationsPlugin();

// ✅ 修改背景訊息處理器 - 只在移動平台有效
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // 只在非 Web 和非桌面平台執行
  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || 
                  defaultTargetPlatform == TargetPlatform.iOS)) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    print('📬 背景訊息: ${message.notification?.title}');
  }
}

// ✅ 修改 main 函數
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ✅ 只在 Android/iOS 上初始化 Firebase
  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || 
                  defaultTargetPlatform == TargetPlatform.iOS)) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      print('✅ Firebase 初始化成功');
      
      // 設定背景訊息處理器
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    } catch (e) {
      print('❌ Firebase 初始化失敗: $e');
    }
  } else {
    print('ℹ️ 當前平台不支援 Firebase 推播通知');
  }
  
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
      
      // ✅ 添加本地化支援
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('zh', 'TW'), // 繁體中文
        Locale('en', 'US'), // 英文
      ],
      locale: const Locale('zh', 'TW'), // 預設語言
      
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Token 管理服務 (保持不變)
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

// HTTP 請求服務 (保持不變)
class ApiService {
  static Future<Map<String, String>> _getHeaders() async {
    final token = await TokenService.getToken();
    return {
      'Content-Type': 'application/json',
      'ngrok-skip-browser-warning': 'true',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<http.Response> get(String endpoint) async {
    final headers = await _getHeaders();
    return await http.get(
      Uri.parse('${Config.apiUrl}$endpoint'),
      headers: headers,
    );
  }

  static Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    final headers = await _getHeaders();
    return await http.post(
      Uri.parse('${Config.apiUrl}$endpoint'),
      headers: headers,
      body: json.encode(body),
    );
  }

  static Future<http.Response> put(String endpoint, Map<String, dynamic> body) async {
    final headers = await _getHeaders();
    return await http.put(
      Uri.parse('${Config.apiUrl}$endpoint'),
      headers: headers,
      body: json.encode(body),
    );
  }
}

// AuthWrapper (保持不變)
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

// AuthPage (保持不變,只修改 _handleLogin 方法)
class AuthPage extends StatefulWidget {
  final VoidCallback onLoginSuccess;
  const AuthPage({super.key, required this.onLoginSuccess});

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  bool isRegistering = false;
  bool _isLoading = false;

  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _loginFormKey = GlobalKey<FormState>();

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
        _showSnackBar('註冊成功!現在可以登入了。');
        if (mounted) {
          setState(() {
            isRegistering = false;
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
      _showSnackBar('連線失敗,請檢查伺服器是否運行。', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ✅ 修改登入方法
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
        
        await TokenService.saveAuthData(
          token: responseBody['token'] ?? '',
          userId: responseBody['user']['id'] ?? '',
          userName: responseBody['user']['name'] ?? '',
          userEmail: responseBody['user']['email'] ?? '',
        );

        _showSnackBar('登入成功!歡迎回來。');
        
        // ✅ 只在 Android/iOS 上設定推播通知
        if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || 
                        defaultTargetPlatform == TargetPlatform.iOS)) {
          try {
            await setupPushNotifications();
            print('✓ FCM Token 已上傳');
          } catch (fcmError) {
            print('⚠️ FCM 設定失敗: $fcmError');
            // 不阻擋登入流程
          }
        } else {
          print('ℹ️ Windows/Web 平台跳過 FCM 設定');
        }
        
        widget.onLoginSuccess();
      } else {
        final responseBody = json.decode(response.body);
        _showSnackBar(responseBody['message'] ?? '登入失敗', isError: true);
      }
    } catch (e) {
      _showSnackBar('連線失敗,請檢查伺服器是否運行。', isError: true);
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
            child: const Text('沒有帳號?點此註冊'),
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
            child: const Text('已經有帳號?點此登入'),
          ),
        ],
      ),
    );
  }
}

// 修改 setupPushNotifications 函數
Future<void> setupPushNotifications() async {
  if (kIsWeb || (defaultTargetPlatform != TargetPlatform.android && 
                 defaultTargetPlatform != TargetPlatform.iOS)) {
    print('ℹ️ 當前平台不支援 FCM 推播通知');
    return;
  }
  
  try {
    final messaging = FirebaseMessaging.instance;
    
    // ✅ 1. 初始化本地通知(用於前景通知)
    const AndroidInitializationSettings androidSettings = 
        AndroidInitializationSettings('@mipmap/ic_launcher');
    
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
    );
    
    await flutterLocalNotificationsPlugin.initialize(initSettings);
    
    // ✅ 2. 創建 Android 通知頻道
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'smart_home_alerts', // 必須與後端一致
      '智慧家庭警報',
      description: '接收設備異常、用電警告等重要通知',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    
    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>() 
        ?.createNotificationChannel(channel); // 修正語法錯誤
    print('✅ Android 通知頻道已創建');
    
    // 請求通知權限
    final settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('✅ 用戶已授權通知');
    } else {
      print('❌ 用戶拒絕通知權限');
      return;
    }
    
    // 獲取 FCM Token
    final fcmToken = await messaging.getToken();
    
    if (fcmToken != null) {
      print('📱 FCM Token: ${fcmToken.substring(0, 30)}...');
      
      // 上傳到後端
      try {
        final response = await ApiService.post('/user/fcm-token', {
          'fcm_token': fcmToken,
        });
        
        if (response.statusCode == 200) {
          print('✅ FCM Token 已上傳到伺服器');
        }
      } catch (e) {
        print('❌ 上傳 FCM Token 時發生錯誤: $e');
      }
    }
    
    // ✅ 3. 監聽前台訊息(APP 開啟時)
    FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
      print('📨 收到前台訊息');
      print('標題: ${message.notification?.title}');
      print('內容: ${message.notification?.body}');
      
      // 在前台顯示通知
      if (message.notification != null) {
        await flutterLocalNotificationsPlugin.show(
          message.hashCode,
          message.notification!.title,
          message.notification!.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channel.id,
              channel.name,
              channelDescription: channel.description,
              importance: Importance.high,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
          ),
        );
      }
    });
    
    // 監聽通知點擊
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('📲 用戶點擊了通知');
      print('數據: ${message.data}');
    });
    
  } catch (e) {
    print('❌ 設定推播通知失敗: $e');
    rethrow;
  }
}

// MainScreen (保持完全不變)
class MainScreen extends StatefulWidget {
  final VoidCallback onLogout;
  const MainScreen({super.key, required this.onLogout});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  Map<String, String?> _userData = {};
  List<Widget>? _pages;
  bool _isLoadingPages = true;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }
  
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
          ACControlPage(jwtToken: token!),
          const PowerMonitoringPage(),
          FanControlPage(jwtToken: token),
          const SensorDataPage(),
          const EnergySavingSettingsPage(),
        ];
        _isLoadingPages = false;
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
    switch (index) {
      case 0:
        return '首頁';
      case 1:
        return '燈光控制';
      case 2:
        return '冷氣控制';
      case 3:
        return '用電監控';
      case 4:
        return '風扇控制';
      case 5:
        return '感測數據監控';
      case 6:
        return '節能設定';
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
        builder: (context) => MyAccountPage(
          onLogout: widget.onLogout,
          onProfileUpdated: () {
            _loadUserData();
          },
        ),
      ),
    ).then((_) {
      _loadUserData();
    });
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('確認登出'),
          content: const Text('您確定要登出嗎?'),
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
              leading: const Icon(Icons.offline_bolt),
              title: const Text('省電效能展示'),
              selected: _selectedIndex == 5,
              onTap: () => _onDrawerItemTapped(5),
            ),
            ListTile(
              leading: const Icon(Icons.eco),
              title: const Text('節能設定'),
              selected: _selectedIndex == 6,
              onTap: () => _onDrawerItemTapped(6),
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