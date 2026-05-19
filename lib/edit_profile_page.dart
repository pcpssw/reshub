import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; 
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

  // 🔴 ตัวแปรสำหรับควบคุมการเปิดเผยสีแดงแจ้งเตือนทันทีหลังกดปุ่ม
  AutovalidateMode _profileAutovalidateMode = AutovalidateMode.disabled;
  AutovalidateMode _passwordAutovalidateMode = AutovalidateMode.disabled;

  // 🔴 ตัวแปรสำหรับสลักข้อความแจ้งเตือนสีแดงลงใต้กล่องข้อความแต่ละช่อง
  String? _usernameError;
  String? _fullNameError;
  String? _phoneError;
  String? _oldPassError;
  String? _newPassError;

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

  // ✨ ล้างข้อความเตือนสีแดงเก่าทิ้งเมื่อเริ่มทำรายการใหม่
  void _clearValidationErrors() {
    setState(() {
      _usernameError = null;
      _fullNameError = null;
      _phoneError = null;
      _oldPassError = null;
      _newPassError = null;
    });
  }

  Future<void> _saveProfile() async {
    _clearValidationErrors();
    
    if (!_profileFormKey.currentState!.validate()) {
      setState(() {
        _profileAutovalidateMode = AutovalidateMode.onUserInteraction;
      });
      return;
    }
    
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
        final String msg = data["message"] ?? "ข้อมูลไม่ถูกต้อง";
        
        setState(() {
          if (msg.contains("ภาษาไทย") || msg.contains("ชื่อผู้ใช้") || msg.contains("Username") || msg.contains("6 ตัว")) {
            _usernameError = msg;
          } else if (msg.contains("ชื่อ-นามสกุล") || msg.contains("นามสกุล") || msg.contains("กรอกชื่อ")) {
            _fullNameError = msg;
          } else if (msg.contains("เบอร์โทรศัพท์") || msg.contains("โทรศัพท์") || msg.contains("phone")) {
            _phoneError = msg;
          } else {
            _usernameError = msg;
          }
          _profileAutovalidateMode = AutovalidateMode.onUserInteraction;
        });
      }
    } catch (e) {
      _toast("เชื่อมต่อล้มเหลว กรุณาลองใหม่");
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _changePassword() async {
    _clearValidationErrors();
    
    if (!_passwordFormKey.currentState!.validate()) {
      setState(() {
        _passwordAutovalidateMode = AutovalidateMode.onUserInteraction;
      });
      return;
    }

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
        setState(() {
          _passwordAutovalidateMode = AutovalidateMode.disabled; 
        });
        _toast("เปลี่ยนรหัสผ่านสำเร็จ"); 
      } else {
        final String msg = data["message"] ?? "ข้อมูลไม่ถูกต้อง";
        
        setState(() {
          if (msg.contains("เดิม") || msg.contains("เก่า") || msg.contains("ไม่ถูกต้อง")) {
            _oldPassError = msg;
          } else if (msg.contains("ภาษาไทย") || msg.contains("รหัสผ่านใหม่") || msg.contains("6 ตัว")) {
            _newPassError = msg;
          } else {
            _newPassError = msg;
          }
          _passwordAutovalidateMode = AutovalidateMode.onUserInteraction;
        });
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
              autovalidateMode: _profileAutovalidateMode, 
              child: _buildSectionCard(
                title: "ข้อมูลส่วนตัว",
                icon: Icons.person_outline_rounded,
                children: [
                  _buildInput(
                    usernameCtrl, "ชื่อผู้ใช้งาน", Icons.alternate_email, 
                    (v) {
                      final val = v?.trim() ?? "";
                      if (val.isEmpty) return "กรุณากรอกชื่อผู้ใช้งาน";
                      
                      // 🛠️ เช็คห้ามมีภาษาไทย
                      if (RegExp(r'[ก-๙]').hasMatch(val)) {
                        return "ชื่อผู้ใช้งานต้องไม่ใช้ภาษาไทย";
                      }
                      // 🛠️ เช็คความยาวต้องอย่างน้อย 6 ตัวอักษรขึ้นไป
                      if (val.length < 6) {
                        return "ชื่อผู้ใช้งานต้องมีความยาวอย่างน้อย 6 ตัวอักษร";
                      }
                      return null;
                    },
                    errorText: _usernameError,
                    onChanged: (v) { if (_usernameError != null) setState(() => _usernameError = null); },
                  ),
                  
                  _buildInput(
                    fullNameCtrl, "ชื่อ-นามสกุล", Icons.badge_outlined, 
                    (v) => (v == null || v.isEmpty) ? "กรุณากรอกชื่อ-นามสกุล" : null,
                    errorText: _fullNameError,
                    onChanged: (v) { if (_fullNameError != null) setState(() => _fullNameError = null); },
                  ),
                  
                  _buildInput(
                    phoneCtrl, "เบอร์โทรศัพท์", Icons.phone_android_rounded, 
                    (v) {
                      if (v == null || v.isEmpty) return "กรุณากรอกเบอร์โทรศัพท์";
                      if (v.length < 10) return "เบอร์โทรศัพท์ต้องมี 10 หลัก";
                      return null;
                    }, 
                    errorText: _phoneError,
                    onChanged: (v) { if (_phoneError != null) setState(() => _phoneError = null); },
                    keyboard: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildBtn("บันทึก", _isSaving, _saveProfile),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Form(
              key: _passwordFormKey,
              autovalidateMode: _passwordAutovalidateMode, 
              child: _buildSectionCard(
                title: "เปลี่ยนรหัสผ่าน",
                icon: Icons.shield_outlined,
                children: [
                  _buildPasswordInput(
                    oldPassCtrl, "รหัสผ่านเดิม", _obOld, 
                    () => setState(() => _obOld = !_obOld), 
                    (v) => (v == null || v.isEmpty) ? "กรุณากรอกรหัสผ่านเดิม" : null,
                    errorText: _oldPassError,
                    onChanged: (v) { if (_oldPassError != null) setState(() => _oldPassError = null); },
                  ),
                  _buildPasswordInput(
                    newPassCtrl, "รหัสผ่านใหม่", _obNew, 
                    () => setState(() => _obNew = !_obNew), 
                    (v) {
                      final val = v?.trim() ?? "";
                      if (val.isEmpty) return "กรุณากรอกรหัสผ่านใหม่";
                      
                      // 🛠️ เช็คห้ามมีภาษาไทย
                      if (RegExp(r'[ก-๙]').hasMatch(val)) {
                        return "รหัสผ่านใหม่ต้องไม่ใช้ภาษาไทย";
                      }
                      // 🛠️ เช็คความยาวต้องอย่างน้อย 6 ตัวอักษรขึ้นไป
                      if (val.length < 6) {
                        return "รหัสผ่านใหม่ต้องมีความยาวอย่างน้อย 6 ตัวอักษร";
                      }
                      return null;
                    },
                    errorText: _newPassError,
                    onChanged: (v) { if (_newPassError != null) setState(() => _newPassError = null); },
                  ),
                  _buildPasswordInput(
                    confirmPassCtrl, "ยืนยันรหัสผ่านใหม่", _obConfirm, 
                    () => setState(() => _obConfirm = !_obConfirm), 
                    (v) {
                      if (v != newPassCtrl.text) return "รหัสผ่านไม่ตรงกัน";
                      return null;
                    }
                  ),
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

  Widget _buildInput(
    TextEditingController c, 
    String label, 
    IconData icon, 
    String? Function(String?)? validator, {
    TextInputType keyboard = TextInputType.text,
    List<TextInputFormatter>? inputFormatters, 
    String? errorText,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: c,
        validator: validator, 
        keyboardType: keyboard,
        inputFormatters: inputFormatters,
        onChanged: (v) {
          onChanged?.call(v);
          if (_profileAutovalidateMode != AutovalidateMode.disabled) {
            setState(() {});
          }
        },
        style: const TextStyle(fontSize: 14, color: cTextMain, fontWeight: FontWeight.w600),
        decoration: _inputDec(label, icon, errorText: errorText),
      ),
    );
  }

  Widget _buildPasswordInput(
    TextEditingController c, 
    String label, 
    bool ob, 
    VoidCallback toggle, 
    String? Function(String?)? validator, {
    String? errorText,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextFormField(
        controller: c,
        obscureText: ob,
        validator: validator,
        onChanged: (v) {
          onChanged?.call(v);
          if (_passwordAutovalidateMode != AutovalidateMode.disabled) {
            setState(() {});
          }
        },
        style: const TextStyle(fontSize: 14, color: cTextMain, fontWeight: FontWeight.w600),
        decoration: _inputDec(label, Icons.lock_outline_rounded, errorText: errorText).copyWith(
          suffixIcon: IconButton(
            icon: Icon(ob ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20, color: cDark), 
            onPressed: toggle
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDec(String label, IconData icon, {String? errorText}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF757575), fontSize: 13, fontWeight: FontWeight.w600),
      prefixIcon: Icon(icon, size: 20, color: cDark),
      isDense: false, 
      filled: true,
      fillColor: cBg.withOpacity(0.4),
      errorText: errorText, 
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: cAccent)),
      errorStyle: const TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent, fontSize: 12),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: cAccent.withOpacity(0.5))),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: cDark, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.redAccent, width: 1.2)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.redAccent, width: 1.8)),
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