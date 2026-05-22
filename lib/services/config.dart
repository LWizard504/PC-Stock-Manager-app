class AppConfig {
  static const String signalingUrl = 'https://api-stockm-call-service.onrender.com';
  static const String webAdminUrl = 'https://stockmanager-wine.vercel.app';
  static const String appVersion = '20.1.7';
  
  static const String supabaseUrl = 'https://fctewfmsofdcqrwlxoyo.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZjdGV3Zm1zb2ZkY3Fyd2x4b3lvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzY3NDYzNDUsImV4cCI6MjA5MjMyMjM0NX0.efBvCsV_hfUYWskDoVmc5PPEB97RoCsDkgctj7X8g4g';

  static const Map<String, dynamic> iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject'
      },
    ]
  };
}
