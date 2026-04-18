import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../config.dart';

class BankAccountsAdminPage extends StatefulWidget {
  final int dormId;
  const BankAccountsAdminPage({super.key, required this.dormId});

  @override
  State<BankAccountsAdminPage> createState() => _BankAccountsAdminPageState();
}

class _BankAccountsAdminPageState extends State<BankAccountsAdminPage> {
  // 🎨 Palette Earth Tone (ปรับให้ละมุนขึ้น)
  static const Color cBg = Color(0xFFF4EFE6);       
  static const Color cCard = Color(0xFFFFFFFF);     
  static const Color cTextMain = Color(0xFF523D2D); 
  static const Color cIcon = Color(0xFF523D2D);     

  // 📏 Typography
  static const double fTitle = 15.0;   
  static const double fBody = 13.0;    
  static const double fDetail = 12.0;  
  static const double fCaption = 11.0;

  String get apiUrl => AppConfig.url("dashboard_api.php");
  bool _loading = true;
  List<Map<String, dynamic>> _accounts = [];

  @override
  void initState() {
    super.initState();
    _loadAccounts();
  }

  // ✅ ฟังก์ชันเลือกสีตามธนาคาร (คงสีเอกลักษณ์ธนาคารไว้แต่ปรับความเข้มให้เข้ากับธีม)
  Color _getBankColor(String? bankName) {
    final name = bankName?.toLowerCase() ?? "";
    if (name.contains("กสิกร")) return const Color(0xFF13804E);
    if (name.contains("ไทยพาณิชย์") || name.contains("scb")) return const Color(0xFF4E2E7F);
    if (name.contains("กรุงเทพ")) return const Color(0xFF1E4598);
    if (name.contains("กรุงไทย")) return const Color(0xFF00A1E0);
    if (name.contains("กรุงศรี")) return const Color(0xFFB59300);
    if (name.contains("ttb") || name.contains("ทหารไทย")) return const Color(0xFFE65A28);
    if (name.contains("ออมสิน")) return const Color(0xFFD81B60);
    return cIcon;
  }

  Future<void> _loadAccounts() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final uri = Uri.parse(apiUrl).replace(queryParameters: {
        "action": "bank_list",
        "dorm_id": widget.dormId.toString(),
      });
      final res = await http.get(uri);
      final data = jsonDecode(res.body);
      if (data["success"] == true) {
        setState(() => _accounts = List<Map<String, dynamic>>.from(data["accounts"] ?? []));
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goToForm({Map<String, dynamic>? item}) async {
    final refresh = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BankAccountFormPage(
          dormId: widget.dormId,
          initialData: item,
        ),
      ),
    );
    if (refresh == true) _loadAccounts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 50,
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: cTextMain, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "บัญชีธนาคาร",
          style: TextStyle(color: cTextMain, fontWeight: FontWeight.w800, fontSize: fTitle),
        ),
        actions: [
          IconButton(
            onPressed: () => _goToForm(),
            icon: const Icon(Icons.add_circle_outline, color: cTextMain, size: 20),
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: cTextMain, strokeWidth: 2))
          : _buildList(),
    );
  }

  Widget _buildList() {
    if (_accounts.isEmpty) {
      return const Center(child: Text("ยังไม่มีข้อมูลบัญชี", style: TextStyle(color: cIcon, fontSize: fBody)));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      itemCount: _accounts.length,
      itemBuilder: (ctx, i) {
        final a = _accounts[i];
        final bankColor = _getBankColor(a["bank_name"]);

        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          decoration: BoxDecoration(
            color: cCard,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: bankColor.withOpacity(0.1),
                blurRadius: 15,
                offset: const Offset(0, 8),
              )
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: bankColor.withOpacity(0.06),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: bankColor,
                      child: const Icon(Icons.account_balance, color: Colors.white, size: 14),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      a["bank_name"] ?? "",
                      style: TextStyle(fontSize: fBody, fontWeight: FontWeight.bold, color: bankColor),
                    ),
                    const Spacer(),
                    _actionBtn(Icons.edit_outlined, bankColor, () => _goToForm(item: a)),
                    const SizedBox(width: 8),
                    _actionBtn(Icons.delete_outline, Colors.redAccent, () => _confirmDelete(a)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text("เลขที่บัญชี", 
                      style: TextStyle(color: Colors.grey, fontSize: fCaption, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                    const SizedBox(height: 6),
                    Text(
                      a["account_no"] ?? "",
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: bankColor, letterSpacing: 1.2),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      "ชื่อบัญชี: ${a["account_name"] ?? ""}",
                      style: const TextStyle(fontSize: fDetail, color: cIcon, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _actionBtn(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, size: 18, color: color),
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> a) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.red[50], shape: BoxShape.circle),
                child: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent, size: 40),
              ),
              const SizedBox(height: 20),
              const Text("ลบบัญชีธนาคาร", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cTextMain)),
              const SizedBox(height: 12),
              Text(
                "คุณต้องการลบบัญชี ${a["bank_name"]} ใช่หรือไม่?",
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        elevation: 0, backgroundColor: Colors.redAccent,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("ลบ", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: ElevatedButton.styleFrom(
                        elevation: 0, backgroundColor: cTextMain,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text("ยกเลิก", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (ok == true) {
      _deleteAccount(a["bank_id"]);
    }
  }

  Future<void> _deleteAccount(dynamic bankId) async {
    setState(() => _loading = true);
    try {
      await http.post(Uri.parse(apiUrl), body: {
        "action": "bank_delete",
        "bank_id": bankId.toString(),
        "dorm_id": widget.dormId.toString(),
      });
      _loadAccounts();
    } catch (e) {
      debugPrint("Delete Error: $e");
    }
  }
}

class BankAccountFormPage extends StatefulWidget {
  final int dormId;
  final Map<String, dynamic>? initialData;
  const BankAccountFormPage({super.key, required this.dormId, this.initialData});

  @override
  State<BankAccountFormPage> createState() => _BankAccountFormPageState();
}

class _BankAccountFormPageState extends State<BankAccountFormPage> {
  final _bCtrl = TextEditingController();
  final _nCtrl = TextEditingController();
  final _noCtrl = TextEditingController();
  bool _busy = false;
  bool get isEdit => widget.initialData != null;

  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cTextMain = Color(0xFF523D2D);
  static const Color cIcon = Color(0xFF523D2D);

  @override
  void initState() {
    super.initState();
    if (isEdit) {
      _bCtrl.text = widget.initialData!["bank_name"] ?? "";
      _nCtrl.text = widget.initialData!["account_name"] ?? "";
      _noCtrl.text = widget.initialData!["account_no"] ?? "";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 55,
        elevation: 0.5,
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: cTextMain, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isEdit ? "แก้ไขบัญชีธนาคาร" : "เพิ่มบัญชีใหม่",
          style: const TextStyle(color: cTextMain, fontWeight: FontWeight.w900, fontSize: 16),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(color: cTextMain.withOpacity(0.06), blurRadius: 20, offset: const Offset(0, 10))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildFieldSection(
                  label: "ธนาคาร",
                  hint: "เช่น กสิกรไทย, ไทยพาณิชย์",
                  controller: _bCtrl,
                  icon: Icons.account_balance_rounded,
                ),
                const SizedBox(height: 24),
                _buildFieldSection(
                  label: "ชื่อบัญชี",
                  hint: "ระบุชื่อเจ้าของบัญชี",
                  controller: _nCtrl,
                  icon: Icons.person_pin_rounded,
                ),
                const SizedBox(height: 24),
                _buildFieldSection(
                  label: "เลขที่บัญชี",
                  hint: "000-0-00000-0",
                  controller: _noCtrl,
                  icon: Icons.numbers_rounded,
                  isNum: true,
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _busy ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: cTextMain,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                elevation: 4,
                shadowColor: cTextMain.withOpacity(0.4),
              ),
              child: _busy
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text("บันทึก", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldSection({
    required String label,
    required String hint,
    required TextEditingController controller,
    required IconData icon,
    bool isNum = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: cTextMain),
          ),
        ),
        TextField(
          controller: controller,
          keyboardType: isNum ? TextInputType.number : TextInputType.text,
          style: const TextStyle(fontWeight: FontWeight.w600, color: cTextMain, fontSize: 14),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, size: 18, color: cIcon.withOpacity(0.7)),
            hintText: hint,
            hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14, fontWeight: FontWeight.normal),
            filled: true,
            fillColor: cBg.withOpacity(0.2),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: Colors.transparent),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: cTextMain, width: 1.2),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (_bCtrl.text.isEmpty || _nCtrl.text.isEmpty || _noCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("กรุณากรอกข้อมูลให้ครบถ้วน")));
      return;
    }
    setState(() => _busy = true);
    try {
      await http.post(Uri.parse(AppConfig.url("dashboard_api.php")), body: {
        "action": isEdit ? "bank_update" : "bank_add",
        "dorm_id": widget.dormId.toString(),
        if (isEdit) "bank_id": widget.initialData!["bank_id"].toString(),
        "bank_name": _bCtrl.text.trim(),
        "account_name": _nCtrl.text.trim(),
        "account_no": _noCtrl.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("เกิดข้อผิดพลาด")));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}