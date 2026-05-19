import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // สำหรับจำกัดรูปแบบการพิมพ์ (สำคัญ)
import 'package:http/http.dart' as http;
import 'config.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  // 🎨 Palette
  static const Color cBg       = Color(0xFFF4EFE6);
  static const Color cTextMain = Color(0xFF2A1F17);
  static const Color cDark     = Color(0xFF523D2D);
  static const Color cAccent   = Color(0xFFD7CCC8);

  // 📏 Micro Typography
  static const double fTitle   = 22.0;   
  static const double fBody    = 13.0;    
  static const double fCaption = 11.0;

  final _formKey = GlobalKey<FormState>();
  final usernameCtrl = TextEditingController();
  final dormCodeCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final newPassCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();

  bool _loading = false;
  bool obscure1 = true;
  bool obscure2 = true;

  @override
  void dispose() {
    usernameCtrl.dispose();
    dormCodeCtrl.dispose();
    phoneCtrl.dispose();
    newPassCtrl.dispose();
    confirmCtrl.dispose();
    super.dispose();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontSize: fBody, color: Colors.white)), 
        behavior: SnackBarBehavior.floating,
        backgroundColor: cDark,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final res = await http.post(
        Uri.parse(AppConfig.url("auth_api.php")),
        body: {
          "action": "forgot_password", 
          "username": usernameCtrl.text.trim(),
          "dorm_code": dormCodeCtrl.text.trim(),
          "phone": phoneCtrl.text.trim(),
          "new_password": newPassCtrl.text.trim(),
        },
      ).timeout(const Duration(seconds: 12));

      final data = jsonDecode(res.body);
      if (!mounted) return;

      if (res.statusCode == 200 && data["success"] == true) {
        _snack("เปลี่ยนรหัสผ่านเรียบร้อย");
        Navigator.pop(context);
      } else {
        _snack(data["message"] ?? "เปลี่ยนรหัสไม่สำเร็จ");
      }
    } catch (e) {
      _snack("เชื่อมต่อไม่ได้ หรือข้อมูลไม่ถูกต้อง");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 4),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: cDark, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Center(
                  child: Container(
                    width: 360,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: cDark.withOpacity(0.08), 
                          blurRadius: 20, 
                          offset: const Offset(0, 10)
                        )
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text("ลืมรหัสผ่าน", 
                            style: TextStyle(
                              fontSize: fTitle, 
                              fontWeight: FontWeight.w900, 
                              color: cTextMain,
                              letterSpacing: 0.5
                            )
                          ),
                          const SizedBox(height: 6),
                          Text(
                            "กรอกข้อมูลเพื่อตั้งรหัสผ่านใหม่",
                            textAlign: TextAlign.center,
                            style: TextStyle(color: cTextMain.withOpacity(0.6), fontSize: fCaption),
                          ),
                          const SizedBox(height: 24),

                          _sectionLabel("ตรวจสอบตัวตน"),
                          // ชื่อผู้ใช้งาน (อังกฤษ/เลข)
                          _field(
                            usernameCtrl, "ชื่อผู้ใช้งาน", Icons.person_outline,
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]'))],
                          ),
                          const SizedBox(height: 12),
                          // โค้ดหอพัก (อังกฤษ/เลข)
                          _field(
                            dormCodeCtrl, "โค้ดหอพัก", Icons.vpn_key_outlined,
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]'))],
                          ),
                          const SizedBox(height: 12),
                          // เบอร์โทรศัพท์ (ตัวเลข 10 หลัก)
                          _field(
                            phoneCtrl, "เบอร์โทรศัพท์", Icons.phone_android_outlined, 
                            keyboardType: TextInputType.phone,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(10),
                            ],
                          ),
                          
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 20),
                            child: Divider(color: cAccent.withOpacity(0.5), height: 1),
                          ),
                          
                          _sectionLabel("ตั้งรหัสผ่านใหม่"),
                          // รหัสผ่านใหม่ (อังกฤษ/เลข)
                          _field(
                            newPassCtrl, "รหัสผ่านใหม่", Icons.lock_outline,
                            isPass: true,
                            obs: obscure1,
                            toggle: () => setState(() => obscure1 = !obscure1),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]'))],
                          ),
                          const SizedBox(height: 12),
                          // ยืนยันรหัสผ่านใหม่ (อังกฤษ/เลข)
                          _field(
                            confirmCtrl, "ยืนยันรหัสผ่านใหม่", Icons.lock_reset,
                            isPass: true,
                            obs: obscure2,
                            toggle: () => setState(() => obscure2 = !obscure2),
                            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9]'))],
                          ),

                          const SizedBox(height: 30),
                          
                          SizedBox(
                            width: double.infinity,
                            height: 48, 
                            child: ElevatedButton(
                              onPressed: _loading ? null : _submit,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: cDark,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                elevation: 0,
                              ),
                              child: _loading
                                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                  : const Text("ยืนยันการเปลี่ยนรหัส", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            ),
                          ),
                          
                          const SizedBox(height: 20),
                          Text(
                            "หากคุณลืมโค้ดหอพัก กรุณาติดต่อผู้ดูแลหอพัก",
                            style: TextStyle(color: cTextMain.withOpacity(0.5), fontSize: fCaption),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: const TextStyle(fontSize: fBody, fontWeight: FontWeight.bold, color: cDark)),
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl, 
    String label, 
    IconData icon, 
    {bool isPass = false, bool obs = false, VoidCallback? toggle, TextInputType keyboardType = TextInputType.text, List<TextInputFormatter>? inputFormatters}
  ) {
    return TextFormField(
      controller: ctrl,
      obscureText: obs,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(fontSize: fBody, color: cTextMain, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: cTextMain.withOpacity(0.5), fontSize: fBody),
        prefixIcon: Icon(icon, color: cDark, size: 18),
        suffixIcon: isPass ? IconButton(icon: Icon(obs ? Icons.visibility_off : Icons.visibility, color: cDark, size: 18), onPressed: toggle) : null,
        filled: true,
        fillColor: cBg.withOpacity(0.3),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cAccent, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: cDark, width: 1.5),
        ),
        errorStyle: const TextStyle(fontSize: 10),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.red.shade300),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.red, width: 1),
        ),
      ),
      validator: (v) {
        final val = v?.trim() ?? "";
        if (val.isEmpty) return "กรุณากรอกข้อมูล";
        
        if ((label == "ชื่อผู้ใช้งาน" || label == "โค้ดหอพัก") && !RegExp(r'^[a-zA-Z0-9]+$').hasMatch(val)) {
          return "ต้องเป็นภาษาอังกฤษหรือตัวเลขเท่านั้น";
        }

        if (label == "รหัสผ่านใหม่") {
          if (val.length < 6) return "อย่างน้อย 6 ตัว";
          if (!RegExp(r'^[a-zA-Z0-9]+$').hasMatch(val)) return "ต้องเป็นภาษาอังกฤษหรือตัวเลขเท่านั้น";
        }
        
        if (label == "ยืนยันรหัสผ่านใหม่" && val != newPassCtrl.text) return "รหัสไม่ตรงกัน";
        
        if (label == "เบอร์โทรศัพท์" && val.length != 10) return "ต้องครบ 10 หลัก";
        
        return null;
      },
    );
  }
}