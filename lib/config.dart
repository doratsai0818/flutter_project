class Config {
  // 私有建構子，避免被實例化
  Config._();

  // ★★★ 之後 ngrok 網址變更，只要改這裡 ★★★
  // (這是我從 fan_control_page.dart 刪除的舊網址)
  static const String baseUrl = "https://unequatorial-cenogenetically-margrett.ngrok-free.dev";
  
  // API 統一前綴
  static const String apiUrl = "$baseUrl/api";
}