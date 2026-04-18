import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  static const Color cVanilla = Color(0xFFF4EFE6);
  static const Color cTeddy = Color(0xFF523D2D);
  static const Color cBrown = Color(0xFF8D7456);
  static const Color cDark = Color(0xFF523D2D);

  static const double fTitle = 22.0;
  static const double fBody = 13.0;
  static const double fCaption = 11.0;

  final _formKey = GlobalKey<FormState>();
  final fullNameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final userCtrl = TextEditingController();
  final passCtrl = TextEditingController();
  final confirmCtrl = TextEditingController();
  final dormCodeCtrl = TextEditingController();

  bool loading = false;
  bool obscure1 = true;
  bool obscure2 = true;
  bool checkingDorm = false;

  String? serverUserError;
  String? serverDormError;
  String? dormName;

  Timer? _dormDebounce;

  @override
  void dispose() {
    _dormDebounce?.cancel();
    fullNameCtrl.dispose();
    phoneCtrl.dispose();
    userCtrl.dispose();
    passCtrl.dispose();
    confirmCtrl.dispose();
    dormCodeCtrl.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _lookupDorm({bool showSnackOnError = false}) async {
    final dormCode = dormCodeCtrl.text.trim();

    if (dormCode.isEmpty) {
      if (mounted) {
        setState(() {
          checkingDorm = false;
          dormName = null;
          serverDormError = null;
        });
      }
      return null;
    }

    if (mounted) {
      setState(() {
        checkingDorm = true;
        dormName = null;
        serverDormError = null;
      });
    }

    try {
      final uri = Uri.parse("${AppConfig.baseUrl}/auth_api.php");
      final res = await http.post(uri, body: {
        "action": "lookup_dorm",
        "dorm_code": dormCode,
      }).timeout(const Duration(seconds: 12));

      final data = jsonDecode(res.body);
      if (!mounted) return null;

      if (res.statusCode == 200 && data["success"] == true) {
        final foundDormName = (data["dorm_name"] ?? "").toString().trim();
        setState(() {
          checkingDorm = false;
          dormName = foundDormName;
          serverDormError = null;
        });
        return {
          "dorm_id": data["dorm_id"],
          "dorm_name": foundDormName,
          "dorm_code": (data["dorm_code"] ?? "").toString(),
        };
      }

      final msg = data["message"]?.toString() ?? "โค้ดหอพักไม่ถูกต้อง";
      setState(() {
        checkingDorm = false;
        dormName = null;
        serverDormError = msg;
      });

      if (showSnackOnError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
      return null;
    } catch (e) {
      debugPrint("Lookup dorm error: $e");
      if (!mounted) return null;

      setState(() {
        checkingDorm = false;
        dormName = null;
        serverDormError = "ไม่สามารถตรวจสอบโค้ดหอพักได้";
      });

      if (showSnackOnError) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("ไม่สามารถตรวจสอบชื่อหอพักได้")),
        );
      }
      return null;
    }
  }

  void _onDormCodeChanged(String value) {
    _dormDebounce?.cancel();

    if (serverDormError != null || dormName != null || checkingDorm) {
      setState(() {
        serverDormError = null;
        dormName = null;
        checkingDorm = false;
      });
    }

    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return;
    }

    _dormDebounce = Timer(const Duration(milliseconds: 500), () {
      _lookupDorm();
    });
  }

  Future<void> _previewBeforeRegister() async {
    if (loading) return;

    setState(() {
      serverUserError = null;
    });

    if (!_formKey.currentState!.validate()) return;

    setState(() => loading = true);
    final dormInfo = await _lookupDorm(showSnackOnError: true);
    if (mounted) {
      setState(() => loading = false);
    }

    if (!mounted || dormInfo == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        final dormText = (dormInfo["dorm_name"]?.toString().trim().isNotEmpty ?? false)
            ? dormInfo["dorm_name"].toString().trim()
            : "-";

        return PopScope(
          canPop: false,
          child: Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            backgroundColor: Colors.white,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.fact_check_rounded,
                      color: Colors.orange.shade700,
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    "ตรวจสอบข้อมูล",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: cDark,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: cVanilla.withOpacity(0.75),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: cBrown.withOpacity(0.18)),
                    ),
                    child: Column(
                      children: [
                        _popupInfoRow("ชื่อ-นามสกุล", fullNameCtrl.text.trim()),
                        const SizedBox(height: 10),
                        _popupInfoRow("เบอร์โทร", phoneCtrl.text.trim()),
                        const SizedBox(height: 10),
                        _popupInfoRow("Username", userCtrl.text.trim()),
                        const SizedBox(height: 10),
                        _popupInfoRow("โค้ดหอพัก", dormCodeCtrl.text.trim()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.orange.shade100),
                    ),
                    child: Column(
                      children: [
                        Text(
                          "ชื่อหอพัก",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.orange.shade800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          dormText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: cDark,
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cTeddy,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        "ยืนยันสมัคร",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: cBrown,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        side: BorderSide(color: cBrown.withOpacity(0.35)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "ยกเลิก",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (confirmed == true) {
      await _register();
    }
  }

  Future<void> _register() async {
    if (loading) return;

    setState(() {
      serverUserError = null;
      serverDormError = null;
    });

    if (!_formKey.currentState!.validate()) return;

    setState(() => loading = true);

    try {
      final uri = Uri.parse("${AppConfig.baseUrl}/auth_api.php");
      final res = await http.post(uri, body: {
        "full_name": fullNameCtrl.text.trim(),
        "phone": phoneCtrl.text.trim(),
        "username": userCtrl.text.trim(),
        "password": passCtrl.text.trim(),
        "dorm_code": dormCodeCtrl.text.trim(),
      }).timeout(const Duration(seconds: 12));

      final data = jsonDecode(res.body);
      if (!mounted) return;

      if (res.statusCode == 200 && data["success"] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt("user_id", int.tryParse(data["user_id"].toString()) ?? 0);
        await prefs.setString("approve_status", "pending");

        Navigator.pushNamedAndRemoveUntil(context, "/pending", (r) => false);
      } else {
        final msg = data["message"]?.toString() ?? "";
        setState(() {
          if (msg.contains("Username") || msg.contains("username")) {
            serverUserError = "ชื่อผู้ใช้นี้ถูกใช้งานแล้ว";
          } else if (msg.contains("หอพัก") || msg.contains("โค้ดหอพัก")) {
            serverDormError = "โค้ดหอพักไม่ถูกต้อง";
            dormName = null;
          }
        });
        _formKey.currentState!.validate();
      }
    } catch (e) {
      debugPrint("Register error: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("เกิดข้อผิดพลาดในการสมัครสมาชิก")),
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [cVanilla, Color(0xFFE8DFD0)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, color: cTeddy, size: 18),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    width: 360,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: cTeddy.withOpacity(0.1),
                          blurRadius: 15,
                          offset: const Offset(0, 8),
                        )
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            "สร้างบัญชี",
                            style: TextStyle(
                              fontSize: fTitle,
                              fontWeight: FontWeight.w900,
                              color: cTeddy,
                              letterSpacing: 1.0,
                            ),
                          ),
                          Text(
                            "กรอกข้อมูลเพื่อลงทะเบียนผู้เช่า",
                            style: TextStyle(
                              color: cTeddy.withOpacity(0.7),
                              fontSize: fCaption,
                            ),
                          ),
                          const SizedBox(height: 20),
                          _sectionLabel("ข้อมูลส่วนตัว"),
                          _field(fullNameCtrl, "ชื่อ-นามสกุล", Icons.person_outline),
                          const SizedBox(height: 10),
                          _field(
                            phoneCtrl,
                            "เบอร์โทร",
                            Icons.phone_android_outlined,
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 10),
                          _field(
                            dormCodeCtrl,
                            "โค้ดหอพัก",
                            Icons.apartment_outlined,
                            sErr: serverDormError,
                            onChanged: _onDormCodeChanged,
                          ),
                          _buildDormStatus(),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Divider(color: Colors.black12, height: 1),
                          ),
                          _sectionLabel("ข้อมูลบัญชี"),
                          _field(
                            userCtrl,
                            "Username",
                            Icons.alternate_email,
                            sErr: serverUserError,
                          ),
                          const SizedBox(height: 10),
                          _field(
                            passCtrl,
                            "รหัสผ่าน",
                            Icons.lock_outline,
                            isPass: true,
                            obs: obscure1,
                            toggle: () => setState(() => obscure1 = !obscure1),
                          ),
                          const SizedBox(height: 10),
                          _field(
                            confirmCtrl,
                            "ยืนยันรหัสผ่าน",
                            Icons.lock_reset,
                            isPass: true,
                            obs: obscure2,
                            toggle: () => setState(() => obscure2 = !obscure2),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: ElevatedButton(
                              onPressed: loading ? null : _previewBeforeRegister,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: cTeddy,
                                foregroundColor: cVanilla,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                              child: loading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        color: cVanilla,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text(
                                      "สมัครสมาชิก",
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
            fontSize: fBody,
            fontWeight: FontWeight.bold,
            color: cBrown,
          ),
        ),
      ),
    );
  }

  Widget _buildDormStatus() {
    final hasCode = dormCodeCtrl.text.trim().isNotEmpty;

    if (!hasCode) return const SizedBox.shrink();

    if (checkingDorm) {
      return const Padding(
        padding: EdgeInsets.only(top: 6, left: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "กำลังตรวจสอบชื่อหอพัก...",
            style: TextStyle(fontSize: 11, color: cBrown),
          ),
        ),
      );
    }

    if (dormName != null && dormName!.trim().isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, left: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            "ชื่อหอพัก: $dormName",
            style: const TextStyle(
              fontSize: 11,
              color: cBrown,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    if (serverDormError != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 6, left: 4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            serverDormError!,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.redAccent,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Widget _popupInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: cBrown,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value.isEmpty ? "-" : value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cTeddy,
              height: 1.35,
            ),
          ),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    IconData icon, {
    bool isPass = false,
    bool obs = false,
    VoidCallback? toggle,
    TextInputType keyboardType = TextInputType.text,
    String? sErr,
    ValueChanged<String>? onChanged,
  }) {
    return TextFormField(
      controller: ctrl,
      obscureText: obs,
      keyboardType: keyboardType,
      onChanged: (v) {
        if (label == "โค้ดหอพัก") {
          onChanged?.call(v);
          return;
        }

        if (sErr != null || serverUserError != null) {
          setState(() {
            serverUserError = null;
          });
        }
        onChanged?.call(v);
      },
      style: const TextStyle(
        fontSize: fBody,
        color: cTeddy,
        fontWeight: FontWeight.w600,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: cTeddy.withOpacity(0.6), fontSize: fBody),
        errorText: label == "โค้ดหอพัก" ? null : sErr,
        errorStyle: const TextStyle(fontSize: 10, color: Colors.redAccent),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
        helperText: (label == "รหัสผ่าน")
            ? "8 ตัวขึ้นไป (ต้องมีตัวอักษรและตัวเลข)"
            : null,
        helperStyle: const TextStyle(fontSize: 9, color: cBrown),
        prefixIcon: Icon(icon, color: cBrown, size: 18),
        suffixIcon: isPass
            ? IconButton(
                icon: Icon(
                  obs ? Icons.visibility_off : Icons.visibility,
                  color: cBrown,
                  size: 18,
                ),
                onPressed: toggle,
              )
            : null,
        filled: true,
        fillColor: Colors.white.withOpacity(0.9),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: (label == "โค้ดหอพัก" && serverDormError != null)
                ? Colors.redAccent
                : Colors.grey.shade300,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: (label == "โค้ดหอพัก" && serverDormError != null)
                ? Colors.redAccent
                : cTeddy,
            width: 1.5,
          ),
        ),
      ),
      validator: (v) {
        final val = v?.trim() ?? "";
        if (val.isEmpty) return "กรุณากรอก$label";
        if (label == "โค้ดหอพัก" && serverDormError != null) return serverDormError;
        if (label == "Username" && val.length < 6) return "อย่างน้อย 6 ตัวอักษร";
        if (label == "รหัสผ่าน") {
          if (val.length < 8) return "อย่างน้อย 8 ตัวอักษร";
          if (!RegExp(r'^(?=.*[A-Za-z])(?=.*\d)').hasMatch(val)) {
            return "ต้องมีตัวอักษรและตัวเลข";
          }
        }
        if (label == "ยืนยันรหัสผ่าน" && val != passCtrl.text) return "รหัสผ่านไม่ตรงกัน";
        return null;
      },
    );
  }
}
