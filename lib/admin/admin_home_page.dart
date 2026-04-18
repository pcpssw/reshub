import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../login_page.dart';
import '../edit_profile_page.dart';
import 'admin_add_dorm_page.dart';
import 'admin_dorm_management_page.dart';
import 'admin_dashboard_page.dart';
import 'admin_user_management_page.dart';

class PlatformHomePage extends StatefulWidget {
  const PlatformHomePage({super.key});

  @override
  State<PlatformHomePage> createState() => _PlatformHomePageState();
}

class _PlatformHomePageState extends State<PlatformHomePage> {
  bool _checking = true;
  String _fullName = "กำลังโหลด...";
  String _username = "";
  String _phone = "";

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
    } catch (e) {
      setState(() => _checking = false);
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
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: _buildWelcomeCard(),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      mainAxisSpacing: 18,
                      crossAxisSpacing: 18,
                      childAspectRatio: 0.95,
                      children: [
                        _buildMenu(
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
                        _buildMenu(
                          context,
                          icon: Icons.analytics_rounded,
                          title: "สรุปภาพรวม",
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PlatformDashboardPage(),
                            ),
                          ),
                        ),
                        _buildMenu(
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
                        _buildMenu(
                          context,
                          icon: Icons.people_alt_rounded,
                          title: "รายชื่อผู้ใช้งาน",
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const PlatformUserListPage(),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                  ],
                ),
              ),
            ),
          ],
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

  Widget _buildMenu(
    BuildContext context, {
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, size: 30, color: cDark),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                  color: cTextMain,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}