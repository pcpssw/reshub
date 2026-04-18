import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class DormLinkSettingsPage extends StatefulWidget {
  const DormLinkSettingsPage({super.key});

  @override
  State<DormLinkSettingsPage> createState() => _DormLinkSettingsPageState();
}

class _DormLinkSettingsPageState extends State<DormLinkSettingsPage> {
  // ✅ ปรับ Palette สีเป็น Earth Tone (F4EFE6 / 523D2D)
  static const Color cBg = Color(0xFFF4EFE6);       // สีครีมพื้นหลัง
  static const Color cCard = Color(0xFFFFFFFF);     // สีขาวการ์ด
  static const Color cAccent = Color(0xFFDCD2C1);   // สีน้ำตาลอ่อน (Accent)
  static const Color cTextMain = Color(0xFF523D2D); // สีน้ำตาลเข้ม (Main)
  static const Color cIcon = Color(0xFF523D2D);     // สีไอคอน

  static const double fTitle = 16.0;   
  static const double fBody = 14.0;    
  static const double fCaption = 12.0;

  bool _loading = true;
  bool _saving = false;
  int dormId = 0;

  final nameCtrl = TextEditingController();
  final addrCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFromDb();
  }

  @override
  void dispose() {
    nameCtrl.dispose(); addrCtrl.dispose(); phoneCtrl.dispose(); codeCtrl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), 
      behavior: SnackBarBehavior.floating, 
      backgroundColor: cTextMain
    ));
  }

  Future<void> _loadFromDb() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      dormId = prefs.getInt("dorm_id") ?? 0;
      final res = await http.get(Uri.parse("${AppConfig.baseUrl}/rooms_api.php?action=get&dorm_id=$dormId"));
      final json = jsonDecode(res.body);
      if (json["ok"] == true) {
        final d = json["dorm"];
        nameCtrl.text = d["dorm_name"] ?? "";
        addrCtrl.text = d["dorm_address"] ?? "";
        phoneCtrl.text = d["dorm_phone"] ?? "";
        codeCtrl.text = d["dorm_code"] ?? "";
      }
    } catch (_) {} finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _saveToDb() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final res = await http.post(Uri.parse("${AppConfig.baseUrl}/rooms_api.php?action=save"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "dorm_id": dormId,
          "dorm_name": nameCtrl.text.trim(),
          "dorm_address": addrCtrl.text.trim(),
          "dorm_phone": phoneCtrl.text.trim(),
          "dorm_code": codeCtrl.text.trim(),
        }),
      );
      if (jsonDecode(res.body)["ok"] == true) _toast("บันทึกข้อมูลสำเร็จ ✅");
    } catch (_) { _toast("บันทึกไม่สำเร็จ"); } finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        elevation: 0.5, 
        backgroundColor: Colors.white, 
        centerTitle: true,
        title: const Text("ตั้งค่าหอพัก", style: TextStyle(color: cTextMain, fontWeight: FontWeight.bold, fontSize: fTitle)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: cTextMain), 
          onPressed: () => Navigator.pop(context)
        ),
      ),
      body: _loading ? const Center(child: CircularProgressIndicator(color: cTextMain)) : ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ✅ ส่วนข้อมูลหอพัก
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cCard, 
              borderRadius: BorderRadius.circular(20), 
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 15)]
            ),
            child: Column(
              children: [
                _field("ชื่อหอพัก", nameCtrl, icon: Icons.home_work_rounded),
                const SizedBox(height: 16),
                _field("ที่ตั้ง", addrCtrl, icon: Icons.location_on_rounded, maxLines: 2),
                const SizedBox(height: 16),
                _field("เบอร์ติดต่อ", phoneCtrl, icon: Icons.phone_rounded, keyboard: TextInputType.phone),
                const SizedBox(height: 16),
                
                // ✅ ช่องโค้ดหอพัก
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(child: _field("โค้ดหอพัก", codeCtrl, icon: Icons.vpn_key_rounded)),
                    const SizedBox(width: 10),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: SizedBox(
                        height: 48, width: 48,
                        child: IconButton.filledTonal(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: codeCtrl.text));
                            _toast("คัดลอกโค้ดแล้ว");
                          },
                          // ปรับสีปุ่ม Copy เป็น Accent Brown
                          style: IconButton.styleFrom(
                            backgroundColor: cAccent, 
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
                          ),
                          icon: const Icon(Icons.copy_rounded, color: cTextMain, size: 20),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 30),
          
          // ✅ ปุ่มบันทึก (น้ำตาลเข้ม)
          SizedBox(
            width: double.infinity, height: 50,
            child: ElevatedButton(
              onPressed: _saving ? null : _saveToDb,
              style: ElevatedButton.styleFrom(
                backgroundColor: cTextMain, 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))
              ),
              child: _saving 
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text("บันทึก", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {IconData? icon, TextInputType? keyboard, int maxLines = 1}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6), 
          child: Text(label, style: const TextStyle(fontSize: fCaption, fontWeight: FontWeight.bold, color: cTextMain))
        ),
        TextField(
          controller: ctrl, 
          keyboardType: keyboard, 
          maxLines: maxLines,
          style: const TextStyle(fontSize: fBody, color: cTextMain),
          decoration: InputDecoration(
            filled: true, 
            fillColor: cBg.withOpacity(0.4), // ปรับพื้นหลังในช่องกรอกให้จางลง (นวลตา)
            isDense: true,
            prefixIcon: Icon(icon, size: 20, color: cIcon),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), 
              borderSide: const BorderSide(color: Color(0xFFDCD2C1)) // ใช้สี Accent จางๆ เป็นขอบ
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12), 
              borderSide: const BorderSide(color: cIcon, width: 1.5)
            ),
          ),
        ),
      ],
    );
  }
}