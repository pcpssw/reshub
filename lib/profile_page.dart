import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'config.dart';
import 'login_page.dart';
import 'edit_profile_page.dart';

class ProfilePage extends StatefulWidget {
  final Map<String, dynamic>? tenantData;
  const ProfilePage({super.key, this.tenantData});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  static const Color cVanilla = Color(0xFFF4EFE6);
  static const Color cTeddy = Color(0xFF523D2D);
  static const Color cBrown = Color(0xFF8D7456);
  static const Color cCard = Color(0xFFFFFFFF);
  static const Color cTextMain = Color(0xFF523D2D);

  static const double fHeader = 15.0;
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

  bool get isFormerTenant {
    if (isDormAdmin) return false;
    return tenantStatus == "former" ||
        (moveOutDate.trim().isNotEmpty && moveOutDate != "-");
  }

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
        body: {
          "action": "get",
          "user_id": _targetUserId.toString(),
        },
      );

      final data = jsonDecode(res.body);
      if (data["success"] == true) {
        final profileData = data["data"] is Map<String, dynamic>
            ? Map<String, dynamic>.from(data["data"])
            : Map<String, dynamic>.from(data);

        if (mounted) {
          setState(() => _applyTenantData(profileData));
        }
      }
    } catch (e) {
      debugPrint("ERROR: $e");
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

    if (rNo.isNotEmpty && building.isNotEmpty) {
      roomText = "$building / ห้อง $rNo";
    } else if (rNo.isNotEmpty) {
      roomText = rNo;
    } else {
      roomText = "ยังไม่ได้รับการจัดห้อง";
    }

    moveInDate = _prettyThaiDate(t["move_in_date"]?.toString());
    moveOutDate = _prettyThaiDate(t["move_out_date"]?.toString());
  }

  int _toInt(dynamic v) => int.tryParse(v?.toString() ?? "") ?? 0;

  String _prettyThaiDate(String? raw) {
    if (raw == null || raw.trim().isEmpty || raw.trim() == "-") return "-";
    try {
      final dt = DateTime.parse(raw.replaceFirst(" ", "T"));
      const thMonths = [
        "ม.ค.",
        "ก.พ.",
        "มี.ค.",
        "เม.ย.",
        "พ.ค.",
        "มิ.ย.",
        "ก.ค.",
        "ส.ค.",
        "ก.ย.",
        "ต.ค.",
        "พ.ย.",
        "ธ.ค."
      ];
      return "${dt.day} ${thMonths[dt.month - 1]} ${dt.year + 543}";
    } catch (_) {
      return raw;
    }
  }

  Future<void> _showRemoveConfirm() async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.delete_forever_rounded,
                  color: Colors.redAccent,
                  size: 45,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "ยืนยันการออก",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cTextMain,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                "คุณต้องการให้คุณ $fullName\nออกจากหอพักใช่หรือไม่?",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: fDetail,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 30),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: cTeddy,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        "ยืนยัน",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFDCD2C1)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        "กลับ",
                        style: TextStyle(
                          color: cTextMain,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (confirm == true) _processRemoveTenant();
  }

  Future<void> _processRemoveTenant() async {
    setState(() => _loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final dormId = prefs.getInt("dorm_id") ?? 0;
      final adminUserId = prefs.getInt("user_id") ?? 0;

      final res = await http.post(
        Uri.parse(AppConfig.url("tenants_api.php")),
        body: {
          "action": "remove",
          "dorm_id": dormId.toString(),
          "admin_user_id": adminUserId.toString(),
          "user_id": _targetUserId.toString(),
        },
      );

      final data = jsonDecode(res.body);
      if (data["ok"] == true || data["success"] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("ดำเนินการเรียบร้อยแล้ว ✅"),
              behavior: SnackBarBehavior.floating,
              backgroundColor: cTeddy,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(data["message"]?.toString() ?? "เกิดข้อผิดพลาด"),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("เกิดข้อผิดพลาด"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cVanilla,
      appBar: _isAdminViewing
          ? AppBar(
              backgroundColor: Colors.white,
              elevation: 0.5,
              centerTitle: true,
              title: Text(
                isFormerTenant ? "ประวัติผู้เช่า" : "ข้อมูลผู้เช่า",
                style: const TextStyle(
                  color: cTextMain,
                  fontWeight: FontWeight.bold,
                  fontSize: fHeader,
                ),
              ),
              leading: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new,
                  color: cTextMain,
                  size: 18,
                ),
                onPressed: () => Navigator.pop(context),
              ),
            )
          : null,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator(color: cTeddy))
            : RefreshIndicator(
                onRefresh: _fetchProfile,
                color: cTeddy,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
                  child: Column(
                    children: [
                      _avatar(),
                      const SizedBox(height: 16),
                      Text(
                        fullName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: cTextMain,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildRoleBadge(),
                      const SizedBox(height: 30),
                      _section("ข้อมูลส่วนตัว"),
                      _info(Icons.account_circle_outlined, "username", username),
                      _info(Icons.person_outline, "ชื่อ - นามสกุล", fullName),
                      _info(Icons.phone_android_outlined, "เบอร์โทรศัพท์", phone),
                      const SizedBox(height: 25),
                      _section(isDormAdmin ? "ข้อมูลหอพัก" : "รายละเอียดห้องพัก"),
                      _info(
                        Icons.apartment_rounded,
                        "ชื่อหอพัก",
                        dormName.isEmpty ? "ไม่มีข้อมูล" : dormName,
                      ),
                      if (!isDormAdmin)
                        _info(
                          Icons.meeting_room_outlined,
                          "เลขห้องพัก",
                          roomText,
                        ),
                      if (!isDormAdmin && moveInDate != "-")
                        _info(
                          Icons.login_rounded,
                          "วันย้ายเข้า",
                          moveInDate,
                        ),
                      if (!isDormAdmin && moveOutDate != "-")
                        _info(
                          Icons.logout_rounded,
                          "วันย้ายออก",
                          moveOutDate,
                        ),
                      const SizedBox(height: 40),
                      if (_isAdminViewing && !isFormerTenant && !isDormAdmin)
                        _removeTenantBtn()
                      else if (!_isAdminViewing)
                        _logoutBtn(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _removeTenantBtn() => SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _showRemoveConfirm,
          icon: const Icon(Icons.logout_rounded),
          label: const Text(
            "ออกจากหอพัก",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: fBody,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.redAccent,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );

  Widget _buildRoleBadge() {
    final bool isAdmin = isDormAdmin;
    final bool isFormer = isFormerTenant;

    final Color badgeColor = isAdmin
        ? cTeddy
        : isFormer
            ? const Color(0xFF8D6E63)
            : const Color(0xFF2E7D32);

    final Color bgColor = isAdmin
        ? const Color(0xFFDCD2C1).withOpacity(0.5)
        : isFormer
            ? const Color(0xFFEFEBE9)
            : const Color(0xFFE8F5E9);

    final IconData icon = isAdmin
        ? Icons.admin_panel_settings
        : isFormer
            ? Icons.person_remove_alt_1_rounded
            : Icons.person_pin_rounded;

    final String label = isAdmin
        ? "ผู้ดูแลหอพัก"
        : isFormer
            ? "ผู้เช่าเก่า"
            : "ผู้เช่า";

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: badgeColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: badgeColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: fCaption,
              fontWeight: FontWeight.bold,
              color: badgeColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar() => Stack(
        alignment: Alignment.bottomRight,
        children: [
          CircleAvatar(
            radius: 50,
            backgroundColor: const Color(0xFFDCD2C1),
            child: Icon(
              isDormAdmin
                  ? Icons.admin_panel_settings_outlined
                  : isFormerTenant
                      ? Icons.person_remove_alt_1_rounded
                      : Icons.person_rounded,
              size: 55,
              color: cTeddy,
            ),
          ),
          if (!_isAdminViewing)
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => EditProfilePage(
                    username: username,
                    fullName: fullName,
                    phone: phone,
                  ),
                ),
              ).then((_) => _fetchProfile()),
              child: const CircleAvatar(
                radius: 16,
                backgroundColor: cTeddy,
                child: Icon(Icons.edit, color: Colors.white, size: 16),
              ),
            ),
        ],
      );

  Widget _section(String t) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12, left: 4),
          child: Text(
            t,
            style: const TextStyle(
              fontSize: fHeader,
              fontWeight: FontWeight.bold,
              color: cTextMain,
            ),
          ),
        ),
      );

  Widget _info(IconData i, String l, String v) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: cCard,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: cTeddy.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(i, color: cBrown, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l,
                    style: TextStyle(
                      fontSize: fCaption,
                      color: cTeddy.withOpacity(0.5),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    v,
                    style: const TextStyle(
                      fontSize: fBody,
                      fontWeight: FontWeight.bold,
                      color: cTextMain,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _logoutBtn() => SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _logout,
          icon: const Icon(Icons.logout_rounded),
          label: const Text(
            "ออกจากระบบ",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: fBody,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: cTeddy,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      );
}