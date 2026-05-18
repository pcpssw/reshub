import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../../login_page.dart';
import '../edit_profile_page.dart';
import '../config.dart'; 
import 'admin_add_dorm_page.dart';
import 'admin_dorm_management_page.dart';
import 'admin_user_management_page.dart';

class PlatformHomePage extends StatefulWidget {
  const PlatformHomePage({super.key});

  @override
  State<PlatformHomePage> createState() => _PlatformHomePageState();
}

class _PlatformHomePageState extends State<PlatformHomePage> {
  bool _checking = true;
  bool _loadingStats = true;
  String _fullName = "กำลังโหลด...";
  String _username = "";
  String _phone = "";

  int totalDorms = 0;
  int totalUsers = 0;
  int activeDorms = 0;

  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cAccent = Color(0xFFDCD2C1);
  static const Color cTextMain = Color(0xFF2A1F17); 
  static const Color cDark = Color(0xFF523D2D);     

  @override
  void initState() {
    super.initState();
    _guard();
  }

  Future<void> _guard() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final platformRole = prefs.getString("platform_role") ?? "user";

      if (platformRole != "platform_admin") {
        _logout();
        return;
      }

      setState(() {
        _fullName = prefs.getString("full_name") ?? "Platform Admin";
        _username = prefs.getString("username") ?? "admin";
        _phone = prefs.getString("phone") ?? "";
        _checking = false;
      });

      fetchDashboardStats();
    } catch (e) {
      setState(() => _checking = false);
    }
  }

  Future<void> fetchDashboardStats() async {
    if (!mounted) return;
    setState(() => _loadingStats = true);

    try {
      final url = Uri.parse("${AppConfig.baseUrl}/dashboard_api.php");
      final res = await http.post(url, body: {
        "action": "dashboard",
      }).timeout(const Duration(seconds: 12));

      final data = jsonDecode(res.body);

      if (!mounted) return;

      if (res.statusCode == 200 && data["success"] == true) {
        final m = Map<String, dynamic>.from(data["data"] ?? {});
        final ds = Map<String, dynamic>.from(m["dorm_status"] ?? {});

        setState(() {
          totalDorms = int.tryParse((m["total_dorms"] ?? "0").toString()) ?? 0;
          totalUsers = int.tryParse((m["total_users"] ?? "0").toString()) ?? 0;
          activeDorms = int.tryParse((ds["active"] ?? "0").toString()) ?? 0;
        });
      }
    } catch (e) {
      debugPrint("Fetch stats error: $e");
    } finally {
      if (mounted) setState(() => _loadingStats = false);
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

  void _goToEditProfile() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfilePage(
          username: _username,
          fullName: _fullName,
          phone: _phone,
        ),
      ),
    );

    if (result != null && result['ok'] == true) {
      _guard();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: cBg,
        body: Center(child: CircularProgressIndicator(color: cDark)),
      );
    }

    return Scaffold(
      backgroundColor: cBg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: fetchDashboardStats,
          color: cDark,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: _buildWelcomeCard(),
              ),
              Expanded(
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    const SizedBox(height: 10),
                    
                    // 📊 1. ส่วนแสดงสถิติตัวเลข ขาว คลีน ขนาดเท่ากันเป๊ะ ไม่ล้นจอ
                    _buildPerfectEqualStatsSection(),
                    const SizedBox(height: 28),
                    
                    // 🔳 2. ส่วนเมนูหลัก 3 อัน ดีไซน์เป็นแถวยาวมินิมอลแบบไม่มีรายละเอียดเนื้อหา
                    Column(
                      children: [
                        _buildRowMenuTile(
                          context,
                          icon: Icons.apartment_rounded,
                          title: "จัดการหอพัก",
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PlatformDormListPage(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildRowMenuTile(
                          context,
                          icon: Icons.add_business_rounded,
                          title: "เพิ่มหอพัก",
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PlatformAddDormPage(),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildRowMenuTile(
                          context,
                          icon: Icons.people_alt_rounded,
                          title: "รายชื่อผู้ใช้งาน",
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PlatformUserListPage(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPerfectEqualStatsSection() {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch, 
        children: [
          _buildExactStatCard(
            label: "หอพักทั้งหมด",
            value: _loadingStats ? "..." : "$totalDorms",
            icon: Icons.apartment_rounded,
          ),
          const SizedBox(width: 10), 
          _buildExactStatCard(
            label: "เปิดใช้งานอยู่",
            value: _loadingStats ? "..." : "$activeDorms",
            icon: Icons.check_circle_rounded,
          ),
          const SizedBox(width: 10),
          _buildExactStatCard(
            label: "ผู้ใช้งานรวม",
            value: _loadingStats ? "..." : "$totalUsers",
            icon: Icons.people_alt_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildExactStatCard({
    required String label,
    required String value,
    required IconData icon,
  }) {
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: cDark.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon, 
                  color: cDark, 
                  size: 18,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: cTextMain,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: cTextMain.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 🔳 ปุ่มเมนูหลักแถวยาวแบบไม่มีรายละเอียด (คลีนขึ้น กระชับขึ้น)
  Widget _buildRowMenuTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cBg,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, size: 22, color: cDark),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: cTextMain,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios_rounded, 
                  size: 12, 
                  color: cDark.withOpacity(0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cTextMain,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 20,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: cAccent.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: cAccent.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: Color(0xFFDCD2C1),
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "ยินดีต้อนรับ",
                          style: TextStyle(
                            color: Color(0xFFDCD2C1),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fullName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1611),
                border: Border(
                  top: BorderSide(color: Colors.white.withOpacity(0.05)),
                ),
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: _goToEditProfile,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.manage_accounts_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text(
                                "แก้ไขโปรไฟล์",
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    VerticalDivider(
                      width: 1,
                      indent: 15,
                      endIndent: 15,
                      color: Colors.white.withOpacity(0.1),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: _logout,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.power_settings_new_rounded,
                                color: Color(0xFFFF8A8A),
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text(
                                "ออกจากระบบ",
                                style: TextStyle(
                                  color: Color(0xFFFF8A8A),
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}