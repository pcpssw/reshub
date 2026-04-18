import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart';

class PendingPage extends StatefulWidget {
  const PendingPage({super.key});

  @override
  State<PendingPage> createState() => _PendingPageState();
}

class _PendingPageState extends State<PendingPage> {
  // 🎨 Palette สี: Vanilla Bean & Teddy Bear
  static const Color cVanilla  = Color(0xFFF4EFE6);
  static const Color cTeddy    = Color(0xFF523D2D);
  static const Color cBrown    = Color(0xFF8D7456);
  static const Color cWhite    = Colors.white;

  // 📏 Typography
  static const double fTitle   = 20.0;
  static const double fCaption = 12.0;

  Timer? _timer;
  bool _loading = false;


  @override
  void initState() {
    super.initState();
    _checkOnce();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _checkOnce());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _checkOnce() async {
    if (_loading) return;

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt("user_id") ?? 0;

    if (userId == 0) return;

    setState(() => _loading = true);

    try {
      final url = Uri.parse(AppConfig.url("auth_api.php"));
      final res = await http
          .post(url, body: {"user_id": userId.toString()})
          .timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);

      if (!mounted) return;

      if (res.statusCode == 200 && data["success"] == true) {
        final user = Map<String, dynamic>.from(data["user"] ?? {});
        final approveStatus = (user["approve_status"] ?? "pending").toString();

        if (approveStatus == "approved") {
          await prefs.setBool("isLogin", true);
          await prefs.setString("username", (user["username"] ?? "").toString());
          await prefs.setString("full_name", (user["full_name"] ?? "").toString());
          await prefs.setString("platform_role", (user["platform_role"] ?? "user").toString());
          await prefs.setString("role_in_dorm", (user["role_in_dorm"] ?? "tenant").toString());
          await prefs.setString("approve_status", approveStatus);
          await prefs.setInt("dorm_id", int.tryParse(user["dorm_id"].toString()) ?? 0);

          _timer?.cancel();

          final platformRole = (user["platform_role"] ?? "user").toString();
          final roleInDorm = (user["role_in_dorm"] ?? "tenant").toString();

          if (platformRole == "platform_admin") {
            Navigator.pushNamedAndRemoveUntil(context, "/platform", (r) => false);
          } else if (roleInDorm == "owner" || roleInDorm == "admin") {
            Navigator.pushNamedAndRemoveUntil(context, "/admin", (r) => false);
          } else {
            Navigator.pushNamedAndRemoveUntil(context, "/home", (r) => false);
          }
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _backToLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, "/", (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cVanilla,

      body: SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 30),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon อนิเมชั่น
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: cWhite.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.hourglass_top_rounded, size: 80, color: cBrown),
              ),
              const SizedBox(height: 30),
              
              const Text(
                "รอการอนุมัติ",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: fTitle, 
                  fontWeight: FontWeight.w900, 
                  color: cTeddy,
                  letterSpacing: 0.5
                ),
              ),
              
              
              const SizedBox(height: 40),

              // ปุ่มเช็คสถานะ
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _loading ? null : _checkOnce,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cTeddy,
                    foregroundColor: cVanilla,
                    elevation: 0,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: cVanilla, strokeWidth: 2),
                        )
                      : const Text("เช็คสถานะอีกครั้ง", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // ปุ่มกลับหน้าเข้าสู่ระบบ
              SizedBox(
                width: double.infinity,
                height: 50,
                child: OutlinedButton(
                  onPressed: _backToLogin,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: cTeddy, width: 1.5),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                  ),
                  child: const Text(
                    "กลับไปหน้าเข้าสู่ระบบ",
                    style: TextStyle(fontSize: 16, color: cTeddy, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              Text(
                "หากรอนานเกินไป กรุณาติดต่อเจ้าหน้าที่หอพัก",
                style: TextStyle(color: cTeddy.withOpacity(0.4), fontSize: fCaption),
              ),
            ],
          ),
        ),
      ),
    );
  }
}