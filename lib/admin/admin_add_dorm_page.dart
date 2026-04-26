import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../../login_page.dart';

class PlatformAddDormPage extends StatefulWidget {
  const PlatformAddDormPage({super.key});

  @override
  State<PlatformAddDormPage> createState() => _PlatformAddDormPageState();
}

class _PlatformAddDormPageState extends State<PlatformAddDormPage> {
  final _formKey = GlobalKey<FormState>();

  // 🎨 Palette: Deep Coffee & Cream
  static const Color cBg = Color(0xFFF4EFE6);       // ครีมสว่าง
  static const Color cAccent = Color(0xFFDCD2C1);   // ครีมเข้ม
  static const Color cTextMain = Color(0xFF2A1F17); // น้ำตาลเข้มจัด (คมชัด)
  static const Color cDark = Color(0xFF523D2D);     // น้ำตาลไอคอน

  // 📏 Typography System
  static const double fTitle   = 14.0; 
  static const double fHeader  = 16.0; 
  static const double fBody    = 13.0; 
  static const double fCaption = 11.0;

  // Controllers
  final dormNameCtrl = TextEditingController();
  final dormCodeCtrl = TextEditingController();
  final ownerNameCtrl = TextEditingController();
  final ownerPhoneCtrl = TextEditingController();
  final ownerUserCtrl = TextEditingController();
  final ownerPassCtrl = TextEditingController();
  final confirmPassCtrl = TextEditingController(); 

  bool obscure = true;
  bool obscureConfirm = true; 
  bool loadingRole = true;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    _ensurePlatformAdmin();
  }

  @override
  void dispose() {
    dormNameCtrl.dispose();
    dormCodeCtrl.dispose();
    ownerNameCtrl.dispose();
    ownerPhoneCtrl.dispose();
    ownerUserCtrl.dispose();
    ownerPassCtrl.dispose();
    confirmPassCtrl.dispose(); 
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: fBody, fontWeight: FontWeight.bold)), 
        backgroundColor: cTextMain,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _ensurePlatformAdmin() async {
    final prefs = await SharedPreferences.getInstance();
    final platformRole = prefs.getString("platform_role") ?? "user";

    if (platformRole != "platform_admin") {
      if (!mounted) return;
      _logout();
      return;
    }
    if (mounted) setState(() => loadingRole = false);
  }

  void _logout() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  String _normalizeCode(String s) => s.trim().replaceAll(" ", "").toUpperCase();

  Future<void> _save() async {
    if (saving) return;
    if (!_formKey.currentState!.validate()) return;

    if (ownerPassCtrl.text != confirmPassCtrl.text) {
      _snack("รหัสผ่านไม่ตรงกัน กรุณาตรวจสอบอีกครั้ง");
      return;
    }

    setState(() => saving = true);

    try {
      final url = Uri.parse("${AppConfig.baseUrl}/dashboard_api.php");
      final body = <String, String>{
        "action": "createDorm",
        "dorm_name": dormNameCtrl.text.trim(),
        "dorm_code": _normalizeCode(dormCodeCtrl.text),
        "create_owner": "1",
        "owner_full_name": ownerNameCtrl.text.trim(),
        "owner_phone": ownerPhoneCtrl.text.trim(),
        "owner_username": ownerUserCtrl.text.trim(),
        "owner_password": ownerPassCtrl.text,
      };

      final res = await http.post(url, body: body).timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body);

      if (res.statusCode == 200 && data["success"] == true) {
        _snack("ลงทะเบียนหอพักเรียบร้อย ✅");
        Navigator.pop(context, true);
      } else {
        _snack(data["message"] ?? "บันทึกไม่สำเร็จ");
      }
    } catch (e) {
      _snack("เชื่อมต่อไม่ได้: $e");
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  InputDecoration _dec(String label, IconData icon, {Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(fontSize: fBody, color: Colors.grey, fontWeight: FontWeight.bold),
      prefixIcon: Icon(icon, color: cDark, size: 20),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18), 
        borderSide: BorderSide(color: cAccent.withOpacity(0.6), width: 1.5)
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18), 
        borderSide: const BorderSide(color: cDark, width: 2)
      ),
      errorStyle: const TextStyle(fontSize: fCaption, fontWeight: FontWeight.bold),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loadingRole) return const Scaffold(backgroundColor: cBg, body: Center(child: CircularProgressIndicator(color: cDark)));

    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        centerTitle: true,
        toolbarHeight: 60,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: cTextMain),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("เพิ่มหอพัก", style: TextStyle(fontWeight: FontWeight.w900, color: cTextMain, fontSize: 16)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // 🏢 Section 1: Dorm Info
              _buildSectionCard(
                title: "ข้อมูลหอพัก",
                icon: Icons.apartment_rounded,
                iconColor: cDark, // เปลี่ยนเป็นสีน้ำตาลแล้ว
                children: [
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: dormNameCtrl,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cTextMain),
                    decoration: _dec("ชื่อหอพัก", Icons.business_rounded),
                    validator: (v) => (v == null || v.trim().isEmpty) ? "กรุณากรอกชื่อหอพัก" : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: dormCodeCtrl,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: cTextMain, letterSpacing: 1.5),
                    decoration: _dec("โค้ดหอพัก", Icons.qr_code_rounded),
                    onChanged: (v) {
                      final val = _normalizeCode(v);
                      dormCodeCtrl.value = dormCodeCtrl.value.copyWith(
                        text: val,
                        selection: TextSelection.collapsed(offset: val.length),
                      );
                    },
                    validator: (v) => (v == null || v.isEmpty) ? "กรุณากรอกโค้ดหอ" : null,
                  ),
                ],
              ),

              const SizedBox(height: 20),

              // 👤 Section 2: Owner Info
              _buildSectionCard(
                title: "บัญชีผู้ดูแลหอพัก",
                icon: Icons.person_add_alt_1_rounded,
                iconColor: cDark, 
                children: [
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: ownerNameCtrl,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cTextMain),
                    decoration: _dec("ชื่อ-นามสกุล", Icons.person_outline),
                    validator: (v) => (v == null || v.isEmpty) ? "กรุณากรอกชื่อ-นามสกุล" : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: ownerPhoneCtrl,
                    keyboardType: TextInputType.phone,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cTextMain),
                    decoration: _dec("เบอร์โทรศัพท์", Icons.phone_android_rounded),
                    validator: (v) => (v == null || v.isEmpty) ? "กรุณากรอกเบอร์โทร" : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: ownerUserCtrl,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cTextMain),
                    decoration: _dec("Username", Icons.alternate_email_rounded),
                    validator: (v) => (v == null || v.isEmpty) ? "กรุณากรอก username" : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: ownerPassCtrl,
                    obscureText: obscure,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cTextMain),
                    decoration: _dec(
                      "รหัสผ่าน", 
                      Icons.lock_outline_rounded,
                      suffixIcon: IconButton(
                        icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, size: 20, color: cDark),
                        onPressed: () => setState(() => obscure = !obscure),
                      ),
                    ),
                    validator: (v) => (v == null || v.length < 6) ? "รหัสผ่านต้อง 6 ตัวขึ้นไป" : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: confirmPassCtrl,
                    obscureText: obscureConfirm,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: cTextMain),
                    decoration: _dec(
                      "ยืนยันรหัสผ่านอีกครั้ง", 
                      Icons.lock_reset_rounded,
                      suffixIcon: IconButton(
                        icon: Icon(obscureConfirm ? Icons.visibility_off : Icons.visibility, size: 20, color: cDark),
                        onPressed: () => setState(() => obscureConfirm = !obscureConfirm),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return "กรุณายืนยันรหัสผ่าน";
                      if (v != ownerPassCtrl.text) return "รหัสผ่านไม่ตรงกัน";
                      return null;
                    },
                  ),
                ],
              ),

              const SizedBox(height: 35),

              // 💾 Save Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cDark,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    elevation: 0,
                  ),
                  child: saving
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                      : const Text("เพิ่มหอพัก", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Color iconColor, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: cAccent.withOpacity(0.5), width: 1.5),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 15, offset: const Offset(0, 5))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: iconColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 12),
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: cTextMain)),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12), 
            child: Divider(thickness: 1, height: 1),
          ),
          ...children,
        ],
      ),
    );
  }
}