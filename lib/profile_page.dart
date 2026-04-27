import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'login_page.dart';
import 'edit_profile_page.dart';

// --- Global Helpers ---
Color repairTypeColor(String type) {
  switch (type.trim()) {
    case "ไฟฟ้า":
      return const Color(0xFFFBC02D);
    case "น้ำ":
      return const Color(0xFF0288D1);
    case "เครื่องใช้":
      return const Color.fromARGB(255, 236, 137, 71); 
    case "อื่นๆ":
      return const Color(0xFF455A64);
    default:
      return const Color(0xFF455A64);
  }
}

IconData repairTypeIcon(String type) {
  switch (type.trim()) {
    case "ไฟฟ้า": return Icons.bolt_rounded;
    case "น้ำ": return Icons.water_drop_rounded;
    case "เครื่องใช้": return Icons.ac_unit_rounded; 
    default: return Icons.construction_rounded;
  }
}

class ProfilePage extends StatefulWidget {
  final Map<String, dynamic>? tenantData;
  const ProfilePage({super.key, this.tenantData});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  // --- Design System ---
  static const Color cVanilla = Color(0xFFF4EFE6);
  static const Color cTeddy = Color(0xFF523D2D);
  static const Color cBrown = Color(0xFF8D7456);
  static const Color cCard = Color(0xFFFFFFFF);
  static const Color cTextMain = Color(0xFF523D2D);

  static const double fHeader = 16.0;
  static const double fBody = 14.0;
  static const double fDetail = 13.0;
  static const double fCaption = 11.0;

  bool _loading = true;
  bool _isAdminViewing = false;

  String username = "";
  String fullName = "ไม่มีข้อมูล";
  String phone = "ไม่มีข้อมูล";
  String dormName = "";
  String roleInDorm = "tenant";
  String tenantStatus = "waiting";
  String roomText = "ยังไม่ได้รับการจัดห้อง";
  String moveInDate = "-";
  String moveOutDate = "-";
  int _targetUserId = 0;

  bool get isDormAdmin => roleInDorm == "owner" || roleInDorm == "admin";
  bool get isFormerTenant => !isDormAdmin && (tenantStatus == "former" || (moveOutDate.trim().isNotEmpty && moveOutDate != "-"));

  @override
  void initState() {
    super.initState();
    _isAdminViewing = widget.tenantData != null;
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      if (_isAdminViewing) {
        final t = widget.tenantData!;
        _applyTenantData(t);
        _targetUserId = _toInt(t["user_id"] ?? t["id"]);
      } else {
        final prefs = await SharedPreferences.getInstance();
        _targetUserId = prefs.getInt("user_id") ?? 0;
      }
      
      if (_targetUserId == 0) return;

      final res = await http.post(
        Uri.parse(AppConfig.url("auth_api.php")),
        body: {"action": "get", "user_id": _targetUserId.toString()},
      );
      final data = jsonDecode(res.body);
      if (data["success"] == true) {
        final profileData = data["data"] is Map<String, dynamic>
            ? Map<String, dynamic>.from(data["data"])
            : Map<String, dynamic>.from(data);
        if (mounted) setState(() => _applyTenantData(profileData));
      }
    } catch (e) {
      debugPrint("ERROR FETCH PROFILE: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyTenantData(Map<String, dynamic> t) {
    fullName = t["full_name"]?.toString() ?? "ไม่มีข้อมูล";
    phone = t["phone"]?.toString() ?? "ไม่มีข้อมูล";
    username = t["username"]?.toString() ?? "";
    dormName = t["dorm_name"]?.toString() ?? "";
    roleInDorm = t["role_in_dorm"]?.toString() ?? "tenant";
    tenantStatus = (t["tenant_status"]?.toString() ?? "waiting").toLowerCase();

    final rNo = t["room_number"]?.toString().trim() ?? "";
    final building = (t["building"]?.toString().trim().isNotEmpty == true)
        ? t["building"].toString().trim()
        : (t["building_name"]?.toString().trim() ?? "");

    roomText = (rNo.isNotEmpty && building.isNotEmpty) 
        ? "$building / ห้อง $rNo" 
        : (rNo.isNotEmpty ? rNo : "ยังไม่ได้รับการจัดห้อง");
        
    moveInDate = _prettyThaiDate(t["move_in_date"]?.toString());
    moveOutDate = _prettyThaiDate(t["move_out_date"]?.toString());
  }

  int _toInt(dynamic v) => int.tryParse(v?.toString() ?? "") ?? 0;

  // --- ฟังก์ชันแปลงวันที่เป็นไทย (วัน เดือนย่อ ปี พ.ศ.) ---
  String _prettyThaiDate(String? raw) {
    if (raw == null || raw.trim().isEmpty || raw.trim() == "-") return "-";
    try {
      final dt = DateTime.parse(raw.replaceFirst(" ", "T"));
      const thMonths = ["ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.", "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค."];
      return "${dt.day} ${thMonths[dt.month - 1]} ${dt.year + 543}";
    } catch (_) { return raw; }
  }

  Future<void> _showHistorySheet({required String title, required String apiFile, required String action}) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: const BoxDecoration(color: cVanilla, borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
        child: Column(children: [
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40, height: 4,
            decoration: BoxDecoration(color: cTeddy.withOpacity(0.1), borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cTextMain)),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const CircleAvatar(radius: 14, backgroundColor: Colors.white, child: Icon(Icons.close, size: 16, color: cTeddy)),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE8E1D5)),
          Expanded(
            child: FutureBuilder(
              future: http.post(Uri.parse(AppConfig.url(apiFile)), body: {"action": action, "user_id": _targetUserId.toString()}),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator(color: cTeddy));
                if (snapshot.hasError) return const Center(child: Text("เกิดข้อผิดพลาดในการเชื่อมต่อ"));
                
                try {
                  final data = jsonDecode(snapshot.data!.body);
                  final List items = data["data"] ?? [];
                  if (items.isEmpty) return const Center(child: Text("ไม่มีข้อมูลประวัติย้อนหลัง", style: TextStyle(color: Colors.grey)));

                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 15, 20, 30),
                    itemCount: items.length,
                    itemBuilder: (context, i) {
                      final item = items[i];
                      return (apiFile == "repairs_api.php") ? _buildRepairCard(item) : _buildBillCard(item);
                    },
                  );
                } catch (e) {
                  return const Center(child: Text("การประมวลผลข้อมูลผิดพลาด"));
                }
              },
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildRepairCard(Map item) {
    final String? rawImg = item['repair_image']?.toString() ?? item['image_path']?.toString();
    String firstImage = "";
    if (rawImg != null && rawImg.trim().isNotEmpty && rawImg != "null") {
      firstImage = rawImg.split(',').first.trim();
    }
    
    String imageUrl = "";
    if (firstImage.isNotEmpty) {
      String baseUrl = AppConfig.url(""); 
      if (!baseUrl.endsWith('/')) baseUrl += '/';
      
      if (firstImage.contains('uploads/')) {
        imageUrl = "$baseUrl$firstImage";
      } else {
        imageUrl = "${baseUrl}uploads/repairs/$firstImage";
      }
    }
        
    final String typeName = item['type_name'] ?? 'แจ้งซ่อม';
    final String detail = item['detail'] ?? 'ไม่มีรายละเอียด';
    final Color mainColor = repairTypeColor(typeName);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: IntrinsicHeight(
          child: Row(children: [
            Container(
              width: 110,
              color: const Color(0xFFF9F7F2),
              child: AspectRatio(
                aspectRatio: 1.0,
                child: imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => _buildPlaceholderIcon(typeName),
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: cBrown)));
                        },
                      )
                    : _buildPlaceholderIcon(typeName),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(detail, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: cTextMain), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: mainColor.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(repairTypeIcon(typeName), size: 13, color: mainColor),
                      const SizedBox(width: 6),
                      Text(typeName, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: mainColor)),
                    ]),
                  ),
                  const Spacer(),
                  // แสดงวันที่แจ้งซ่อมแบบไทย
                  Text(_prettyThaiDate(item['created_at']), style: const TextStyle(fontSize: 11, color: Colors.black38)),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  // --- แสดงผลบิลค่าเช่าด้วยเดือนไทยปีไทย ---
  Widget _buildBillCard(Map item) {
    const thFullMonths = [
      "มกราคม", "กุมภาพันธ์", "มีนาคม", "เมษายน", "พฤษภาคม", "มิถุนายน",
      "กรกฎาคม", "สิงหาคม", "กันยายน", "ตุลาคม", "พฤศจิกายน", "ธันวาคม"
    ];

    final int monthIdx = int.tryParse(item['month'].toString()) ?? 1;
    final String monthName = thFullMonths[monthIdx - 1];
    final int yearTh = (int.tryParse(item['year'].toString()) ?? 0) + 543;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: [BoxShadow(color: cTeddy.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: IntrinsicHeight(
          child: Row(children: [
            Container(width: 5, color: cBrown.withOpacity(0.4)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: cVanilla, borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.receipt_long_rounded, color: cBrown, size: 20)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text("งวดเดือน $monthName $yearTh", style: const TextStyle(fontWeight: FontWeight.bold, color: cTextMain)),
                    Text("${item['total']} บาท", style: const TextStyle(fontSize: 13, color: cBrown, fontWeight: FontWeight.bold)),
                  ])),
                  _badge(item['status_label'] ?? '', hex: item['status_color']),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildPlaceholderIcon(String? type) => Center(child: Icon(repairTypeIcon(type ?? ""), size: 32, color: const Color(0xFFD6C8B5)));

  Widget _badge(String text, {Color? color, String? hex}) {
    final displayColor = hex != null ? Color(int.parse(hex.replaceAll('#', '0xFF'))) : color ?? cTeddy;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: displayColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
      child: Text(text, style: TextStyle(color: displayColor, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cVanilla,
      appBar: _isAdminViewing
          ? AppBar(
              backgroundColor: Colors.white, elevation: 0.5, centerTitle: true,
              title: Text(isFormerTenant ? "ประวัติผู้เช่าเก่า" : "ข้อมูลผู้เช่า", style: const TextStyle(color: cTextMain, fontWeight: FontWeight.bold, fontSize: fHeader)),
              leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new, color: cTextMain, size: 18), onPressed: () => Navigator.pop(context)),
            )
          : null,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: cTeddy))
            : RefreshIndicator(
                onRefresh: _fetchProfile, color: cTeddy,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
                  child: Column(children: [
                    _avatar(),
                    const SizedBox(height: 16),
                    Text(fullName, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cTextMain)),
                    const SizedBox(height: 6),
                    _buildRoleBadge(),
                    const SizedBox(height: 30),
                    _section("ข้อมูลส่วนตัว"),
                    _info(Icons.account_circle_outlined, "username", username),
                    _info(Icons.person_outline, "ชื่อ - นามสกุล", fullName),
                    _info(Icons.phone_android_outlined, "เบอร์โทรศัพท์", phone),
                    const SizedBox(height: 25),
                    _section(isDormAdmin ? "ข้อมูลหอพัก" : "รายละเอียดห้องพัก"),
                    _info(Icons.apartment_rounded, "ชื่อหอพัก", dormName.isEmpty ? "ไม่มีข้อมูล" : dormName),
                    if (!isDormAdmin) ...[
                      _info(Icons.meeting_room_outlined, "เลขห้องพัก", roomText),
                      if (moveInDate != "-") _info(Icons.login_rounded, "วันย้ายเข้า", moveInDate),
                      if (moveOutDate != "-") _info(Icons.logout_rounded, "วันย้ายออก", moveOutDate),
                    ],
                    if (_isAdminViewing && isFormerTenant) ...[
                      const SizedBox(height: 25),
                      _section("ประวัติย้อนหลัง"),
                      _historyMenuCard(icon: Icons.receipt_long_rounded, title: "ประวัติการชำระเงิน", subtitle: "ดูรายการบิลทั้งหมด", color: Colors.blueGrey, onTap: () => _showHistorySheet(title: "ประวัติการเงิน", apiFile: "bills_api.php", action: "list_user_history")),
                      _historyMenuCard(icon: Icons.build_circle_outlined, title: "รายการแจ้งซ่อม", subtitle: "ดูประวัติแจ้งซ่อมย้อนหลัง", color: Colors.orange.shade800, onTap: () => _showHistorySheet(title: "ประวัติแจ้งซ่อม", apiFile: "repairs_api.php", action: "list_user_history")),
                    ],
                    const SizedBox(height: 40),
                    if (_isAdminViewing && !isFormerTenant && !isDormAdmin) _removeTenantBtn() else if (!_isAdminViewing) _logoutBtn(),
                  ]),
                ),
              ),
      ),
    );
  }

  // --- UI Components ---
  Widget _historyMenuCard({required IconData icon, required String title, required String subtitle, required Color color, required VoidCallback onTap}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: cCard, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: cTeddy.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))]),
          child: Row(children: [
            Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(icon, color: color, size: 22)),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: fBody, fontWeight: FontWeight.bold, color: cTextMain)),
              Text(subtitle, style: TextStyle(fontSize: fCaption, color: cTeddy.withOpacity(0.5))),
            ])),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: cTeddy.withOpacity(0.2)),
          ]),
        ),
      ),
    );
  }

  Widget _section(String t) => Align(alignment: Alignment.centerLeft, child: Padding(padding: const EdgeInsets.only(bottom: 12, left: 4), child: Text(t, style: const TextStyle(fontSize: fHeader, fontWeight: FontWeight.bold, color: cTextMain))));

  Widget _info(IconData i, String l, String v) => Container(
    margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(color: cCard, borderRadius: BorderRadius.circular(15), boxShadow: [BoxShadow(color: cTeddy.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4))]),
    child: Row(children: [
      Icon(i, color: cBrown, size: 22), const SizedBox(width: 16),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l, style: TextStyle(fontSize: fCaption, color: cTeddy.withOpacity(0.5))),
        const SizedBox(height: 2),
        Text(v, style: const TextStyle(fontSize: fBody, fontWeight: FontWeight.bold, color: cTextMain)),
      ])),
    ]),
  );

  Widget _avatar() => Stack(alignment: Alignment.bottomRight, children: [
    CircleAvatar(radius: 50, backgroundColor: const Color(0xFFDCD2C1), child: Icon(isDormAdmin ? Icons.admin_panel_settings_outlined : (isFormerTenant ? Icons.person_remove_alt_1_rounded : Icons.person_rounded), size: 55, color: cTeddy)),
    if (!_isAdminViewing)
      GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => EditProfilePage(username: username, fullName: fullName, phone: phone))).then((_) => _fetchProfile()),
        child: const CircleAvatar(radius: 16, backgroundColor: cTeddy, child: Icon(Icons.edit, color: Colors.white, size: 16)),
      ),
  ]);

  Widget _buildRoleBadge() {
    final bool isAdmin = isDormAdmin;
    final bool isFormer = isFormerTenant;
    final Color badgeColor = isAdmin ? cTeddy : isFormer ? const Color(0xFF8D6E63) : const Color(0xFF2E7D32);
    final Color bgColor = isAdmin ? const Color(0xFFDCD2C1).withOpacity(0.5) : isFormer ? const Color(0xFFEFEBE9) : const Color(0xFFE8F5E9);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(12), border: Border.all(color: badgeColor.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(isAdmin ? Icons.admin_panel_settings : isFormer ? Icons.person_remove_alt_1_rounded : Icons.person_pin_rounded, size: 14, color: badgeColor),
        const SizedBox(width: 6),
        Text(isAdmin ? "ผู้ดูแลหอพัก" : isFormer ? "ผู้เช่าเก่า" : "ผู้เช่า", style: TextStyle(fontSize: fCaption, fontWeight: FontWeight.bold, color: badgeColor)),
      ]),
    );
  }

  Widget _logoutBtn() => SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _logout, icon: const Icon(Icons.logout_rounded), label: const Text("ออกจากระบบ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: fBody)), style: ElevatedButton.styleFrom(backgroundColor: cTeddy, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))));

  Widget _removeTenantBtn() => SizedBox(width: double.infinity, child: ElevatedButton.icon(onPressed: _showRemoveConfirm, icon: const Icon(Icons.logout_rounded), label: const Text("ออกจากหอพัก", style: TextStyle(fontWeight: FontWeight.bold, fontSize: fBody)), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))));

  Future<void> _showRemoveConfirm() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 80, height: 80, decoration: BoxDecoration(color: Colors.red.shade50, shape: BoxShape.circle), child: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 45)),
            const SizedBox(height: 20),
            const Text("ยืนยันการออก", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cTextMain)),
            const SizedBox(height: 10),
            Text("คุณต้องการให้คุณ $fullName\nออกจากหอพักใช่หรือไม่?", textAlign: TextAlign.center, style: const TextStyle(fontSize: fDetail, color: Colors.grey)),
            const SizedBox(height: 30),
            Row(children: [
              Expanded(child: ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: cTeddy, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)), child: const Text("ยืนยัน", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
              const SizedBox(width: 12),
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(ctx, false), style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFDCD2C1)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), padding: const EdgeInsets.symmetric(vertical: 12)), child: const Text("ยกเลิก", style: TextStyle(color: cTextMain, fontWeight: FontWeight.bold)))),
            ]),
          ]),
        ),
      ),
    );
    if (confirm == true) _processRemoveTenant();
  }

  Future<void> _processRemoveTenant() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final res = await http.post(Uri.parse(AppConfig.url("tenants_api.php")), body: {
        "action": "remove",
        "dorm_id": (prefs.getInt("dorm_id") ?? 0).toString(),
        "admin_user_id": (prefs.getInt("user_id") ?? 0).toString(),
        "user_id": _targetUserId.toString(),
      });
      final data = jsonDecode(res.body);
      if ((data["ok"] == true || data["success"] == true) && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ดำเนินการเรียบร้อยแล้ว ✅"), backgroundColor: cTeddy));
        Navigator.pop(context, true);
      }
    } catch (e) { debugPrint(e.toString()); } finally { if (mounted) setState(() => _loading = false); }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => const LoginPage()), (_) => false);
  }
}