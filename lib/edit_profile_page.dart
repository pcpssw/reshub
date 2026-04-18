import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

class EditProfilePage extends StatefulWidget {
  final String username;
  final String fullName;
  final String phone;

  const EditProfilePage({
    super.key,
    required this.username,
    required this.fullName,
    required this.phone,
  });

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  // 🎨 Palette: Deep Coffee & Cream
  static const Color cBg = Color(0xFFF4EFE6);       
  static const Color cAccent = Color(0xFFDCD2C1);   
  static const Color cTextMain = Color(0xFF2A1F17); 
  static const Color cDark = Color(0xFF523D2D);     

  final _profileFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();

  late final TextEditingController usernameCtrl;
  late final TextEditingController fullNameCtrl;
  late final TextEditingController phoneCtrl;
  late final TextEditingController oldPassCtrl;
  late final TextEditingController newPassCtrl;
  late final TextEditingController confirmPassCtrl;

  bool _isSaving = false;
  bool _isChangingPass = false;
  bool _obOld = true;
  bool _obNew = true;
  bool _obConfirm = true;

  @override
  void initState() {
    super.initState();
    usernameCtrl = TextEditingController(text: widget.username);
    fullNameCtrl = TextEditingController(text: widget.fullName);
    phoneCtrl = TextEditingController(text: widget.phone);
    oldPassCtrl = TextEditingController();
    newPassCtrl = TextEditingController();
    confirmPassCtrl = TextEditingController();
  }

  @override
  void dispose() {
    usernameCtrl.dispose();
    fullNameCtrl.dispose();
    phoneCtrl.dispose();
    oldPassCtrl.dispose();
    newPassCtrl.dispose();
    confirmPassCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: cTextMain,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _saveProfile() async {
    if (!_profileFormKey.currentState!.validate()) return;
    
    setState(() => _isSaving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt("user_id") ?? 0;
      
      final payload = {
        "action": "update", 
        "user_id": userId, 
        "username": usernameCtrl.text.trim(), 
        "full_name": fullNameCtrl.text.trim(), 
        "phone": phoneCtrl.text.trim()
      };

      final res = await http.post(
        Uri.parse(AppConfig.url("auth_api.php")), 
        headers: {"Content-Type": "application/json; charset=utf-8"}, 
        body: jsonEncode(payload)
      ).timeout(const Duration(seconds: 12));
      
      final data = jsonDecode(res.body);
      if (data["success"] == true) {
        await prefs.setString("username", usernameCtrl.text.trim());
        await prefs.setString("full_name", fullNameCtrl.text.trim());
        await prefs.setString("phone", phoneCtrl.text.trim());
        if (mounted) Navigator.of(context).pop({"ok": true});
      } else {
        _toast(data["message"] ?? "บันทึกไม่สำเร็จ");
      }
    } catch (e) {
      _toast("เชื่อมต่อล้มเหลว กรุณาลองใหม่");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _changePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;

    setState(() => _isChangingPass = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt("user_id") ?? 0;
      
      final payload = {
        "action": "change_password", 
        "user_id": userId, 
        "old_password": oldPassCtrl.text.trim(), 
        "new_password": newPassCtrl.text.trim()
      };

      final res = await http.post(
        Uri.parse(AppConfig.url("auth_api.php")), 
        headers: {"Content-Type": "application/json; charset=utf-8"}, 
        body: jsonEncode(payload)
      ).timeout(const Duration(seconds: 12));
      
      final data = jsonDecode(res.body);
      if (data["success"] == true) {
        oldPassCtrl.clear(); newPassCtrl.clear(); confirmPassCtrl.clear();
        _toast("เปลี่ยนรหัสผ่านสำเร็จ ✅");
      } else {
        _toast(data["message"] ?? "เปลี่ยนไม่สำเร็จ");
      }
    } catch (e) {
      _toast("เชื่อมต่อล้มเหลว");
    } finally {
      if (mounted) setState(() => _isChangingPass = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        backgroundColor: Colors.white, 
        elevation: 0.5,
        centerTitle: true,
        title: const Text("แก้ไขข้อมูลส่วนตัว", 
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: cTextMain)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: cTextMain, size: 20), 
          onPressed: () => Navigator.pop(context)
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Form(
              key: _profileFormKey,
              child: _buildSectionCard(
                title: "ข้อมูลส่วนตัว",
                icon: Icons.person_outline_rounded,
                children: [
                  _buildInput(usernameCtrl, "Username", Icons.alternate_email, 
                    (v) => (v == null || v.isEmpty) ? "กรุณากรอก Username" : null),
                  _buildInput(fullNameCtrl, "ชื่อ-นามสกุล", Icons.badge_outlined, 
                    (v) => (v == null || v.isEmpty) ? "กรุณากรอกชื่อ-นามสกุล" : null),
                  _buildInput(phoneCtrl, "เบอร์โทรศัพท์", Icons.phone_android_rounded, (v) {
                    if (v == null || v.isEmpty) return "กรุณากรอกเบอร์โทรศัพท์";
                    if (v.length < 10) return "เบอร์โทรศัพท์ต้องมี 10 หลัก";
                    return null;
                  }, keyboard: TextInputType.phone),
                  const SizedBox(height: 10),
                  _buildBtn("อัปเดตข้อมูล", _isSaving, _saveProfile),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Form(
              key: _passwordFormKey,
              child: _buildSectionCard(
                title: "เปลี่ยนรหัสผ่าน",
                icon: Icons.shield_outlined,
                children: [
                  _buildPasswordInput(oldPassCtrl, "รหัสผ่านเดิม", _obOld, 
                    () => setState(() => _obOld = !_obOld), 
                    (v) => (v == null || v.isEmpty) ? "กรุณากรอกรหัสผ่านเดิม" : null),
                  _buildPasswordInput(newPassCtrl, "รหัสผ่านใหม่", _obNew, 
                    () => setState(() => _obNew = !_obNew), (v) {
                    if (v == null || v.isEmpty) return "กรุณากรอกรหัสผ่านใหม่";
                    if (v.length < 8) return "รหัสต้องมีความยาวอย่างน้อย 8 ตัวอักษร";
                    if (!RegExp(r'^(?=.*?[A-Z])').hasMatch(v)) return "ต้องมีตัวพิมพ์ใหญ่ (A-Z) อย่างน้อย 1 ตัว";
                    if (!RegExp(r'^(?=.*?[a-z])').hasMatch(v)) return "ต้องมีตัวพิมพ์เล็ก (a-z) อย่างน้อย 1 ตัว";
                    if (!RegExp(r'^(?=.*?[0-9])').hasMatch(v)) return "ต้องมีตัวเลข (0-9) อย่างน้อย 1 ตัว";
                    return null;
                  }),
                  _buildPasswordInput(confirmPassCtrl, "ยืนยันรหัสผ่านใหม่", _obConfirm, 
                    () => setState(() => _obConfirm = !_obConfirm), (v) {
                    if (v != newPassCtrl.text) return "รหัสผ่านไม่ตรงกัน";
                    return null;
                  }),
                  const SizedBox(height: 10),
                  _buildBtn("เปลี่ยนรหัสผ่าน", _isChangingPass, _changePassword),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white, 
        borderRadius: BorderRadius.circular(28), 
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15, offset: const Offset(0, 5))]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, 
        children: [
          Row(children: [
            Icon(icon, size: 20, color: cDark), 
            const SizedBox(width: 10), 
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: cTextMain))
          ]),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14), 
            child: Divider(height: 1, thickness: 1, color: Color(0xFFF4EFE6))
          ),
          ...children,
        ]
      ),
    );
  }

  Widget _buildInput(TextEditingController c, String label, IconData icon, String? Function(String?)? validator, {TextInputType keyboard = TextInputType.text}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: c,
        validator: validator, 
        keyboardType: keyboard,
        style: const TextStyle(fontSize: 14, color: cTextMain, fontWeight: FontWeight.w600),
        decoration: _inputDec(label, icon),
      ),
    );
  }

  Widget _buildPasswordInput(TextEditingController c, String label, bool ob, VoidCallback toggle, String? Function(String?)? validator) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: c,
        obscureText: ob,
        validator: validator,
        style: const TextStyle(fontSize: 14, color: cTextMain, fontWeight: FontWeight.w600),
        decoration: _inputDec(label, Icons.lock_outline_rounded).copyWith(
          suffixIcon: IconButton(
            icon: Icon(ob ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20, color: cDark), 
            onPressed: toggle
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDec(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF757575), fontSize: 13, fontWeight: FontWeight.w600),
      prefixIcon: Icon(icon, size: 20, color: cDark),
      isDense: true,
      filled: true,
      fillColor: cBg.withOpacity(0.4),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      errorStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent, fontSize: 11),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: cAccent.withOpacity(0.5))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: cDark, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.redAccent, width: 1)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.redAccent, width: 1.5)),
    );
  }

  Widget _buildBtn(String text, bool isLoading, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: isLoading ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: cTextMain, 
          foregroundColor: Colors.white, 
          elevation: 0, 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))
        ),
        child: isLoading
            ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
            : Text(text, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      ),
    );
  }
}