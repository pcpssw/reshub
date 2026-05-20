import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../profile_page.dart';

class TenantListAdminPage extends StatefulWidget {
  const TenantListAdminPage({super.key});

  @override
  State<TenantListAdminPage> createState() => _TenantListAdminPageState();
}

class _TenantListAdminPageState extends State<TenantListAdminPage>
    with SingleTickerProviderStateMixin {
  // --- Style Configuration ---
  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cAccent = Color(0xFFDCD2C1);
  static const Color cIcon = Color(0xFF523D2D);
  static const Color cTextMain = Color(0xFF603F26);

  static const double fHeader = 15.0;
  static const double fBody = 14.0;
  static const double fDetail = 13.0;

  // --- State Variables ---
  bool loading = true;
  int dormId = 0;
  late TabController _tabController;
  
  // ✅ แก้ไข: แยก ScrollController ออกเป็น 3 ตัว เพื่อไม่ให้แย่งสิทธิ์ควบคุมกันระหว่างแท็บ
  final ScrollController _scrollTenant = ScrollController();
  final ScrollController _scrollOldTenant = ScrollController();
  final ScrollController _scrollAdmin = ScrollController();
  
  bool _showBackToTopButton = false; 

  List<Map<String, dynamic>> allUsers = [];
  String keyword = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // ✅ ติดตามตำแหน่งการเลื่อนแยกแต่ละตัว
    _scrollTenant.addListener(_scrollListener);
    _scrollOldTenant.addListener(_scrollListener);
    _scrollAdmin.addListener(_scrollListener);

    _init();
  }

  // ✅ ฟังก์ชันตรวจจับการเลื่อนจอของทุกแท็บ
  void _scrollListener() {
    bool shouldShow = (_scrollTenant.hasClients && _scrollTenant.offset >= 300) ||
                      (_scrollOldTenant.hasClients && _scrollOldTenant.offset >= 300) ||
                      (_scrollAdmin.hasClients && _scrollAdmin.offset >= 300);

    if (shouldShow != _showBackToTopButton) {
      setState(() => _showBackToTopButton = shouldShow);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    // ✅ คืน Memory ของ Controller ทั้ง 3 ตัว
    _scrollTenant.dispose();
    _scrollOldTenant.dispose();
    _scrollAdmin.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    dormId = prefs.getInt("dorm_id") ??
        int.tryParse(prefs.getString("dorm_id") ?? "0") ??
        0;

    if (!mounted) return;
    await _fetchTenants();
  }

  Future<void> _fetchTenants() async {
    if (!mounted) return;
    setState(() => loading = true);

    try {
      final uri = Uri.parse(AppConfig.url("tenants_api.php")).replace(
        queryParameters: {
          "action": "list",
          "dorm_id": dormId.toString(),
        },
      );

      // 🔍 ดักจับดู URL บน Console
      debugPrint("🔗 Request URL: $uri");

      // ✅ ขยายเวลา Timeout เป็น 15 วินาที เผื่ออินเทอร์เน็ตระบบเซิร์ฟเวอร์จริงหน่วง
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      
      // 🔍 ดักดู JSON ที่เซิร์ฟเวอร์ตอบกลับมาจริง ๆ
      debugPrint("📥 Server Response: ${res.body}");

      final data = jsonDecode(res.body);

      if (data is Map && (data["ok"] == true || data["success"] == true)) {
        final list = (data["data"] as List?) ?? [];
        if (!mounted) return;

        setState(() {
          allUsers = list.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      } else {
        if (!mounted) return;
        setState(() => allUsers = []);
        
        // ⚠️ แจ้งเตือนกรณีส่ง JSON สำเร็จ แต่ค่า ok/success กลับมาเป็น false
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("เซิร์ฟเวอร์ปฏิเสธข้อมูล: ${data['message'] ?? 'ไม่ทราบสาเหตุ'}")),
        );
      }
    } catch (e) {
      debugPrint("❌ Error เซิร์ฟเวอร์จริง: $e");
      if (!mounted) return;
      setState(() => allUsers = []);
      
      // ⚠️ เด้งฟ้องทันทีถ้าตัวแอปต่อระบบจริงไม่ติด หรือแปลง JSON ไม่ผ่าน
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("เชื่อมต่อระบบจริงล้มเหลว: $e")),
      );
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ✅ ฟังก์ชันเลื่อนกลับขึ้นไปบนสุด โดยจะตรวจสอบว่าเราอยู่แท็บไหนแล้วสั่งงานตัวนั้น
  void _scrollToTop() {
    ScrollController activeController;
    switch (_tabController.index) {
      case 1:
        activeController = _scrollOldTenant;
        break;
      case 2:
        activeController = _scrollAdmin;
        break;
      case 0:
      default:
        activeController = _scrollTenant;
        break;
    }

    if (activeController.hasClients) {
      activeController.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  // --- Helper Methods ---
  bool _isAdmin(Map<String, dynamic> u) {
    final role = (u["role"] ?? "").toString().toLowerCase();
    return role == "admin";
  }

  bool _isFormerTenant(Map<String, dynamic> u) {
    if (_isAdmin(u)) return false;
    final tenantStatus = (u["tenant_status"] ?? "").toString().toLowerCase();
    return tenantStatus == "former";
  }

  String _roomLabel(Map<String, dynamic> t) {
    if (_isAdmin(t)) {
      final roleInDorm = (t["role_in_dorm"] ?? "").toString().toLowerCase();
      return roleInDorm == "owner" ? "ผู้ดูแลหอพัก" : "ผู้ดูแลหอพัก";
    }

    if (_isFormerTenant(t)) {
      final history = (t["all_rooms_history"] ?? "").toString().trim();
      return history.isNotEmpty ? "ห้องที่เคยอยู่: $history" : "ไม่มีประวัติห้องพัก";
    }

    final b = (t["building"] ?? "").toString().trim();
    final r = (t["room_number"] ?? "").toString().trim();
    if (b.isEmpty && r.isEmpty) return "รอการจัดห้อง";
    return b.isEmpty ? r : (r.isEmpty ? b : "$b-$r");
  }

  List<Map<String, dynamic>> _filteredList(String role) {
    final k = keyword.trim().toLowerCase();
    Iterable<Map<String, dynamic>> list = allUsers.where((u) {
      if (role == "admin") return _isAdmin(u);
      if (role == "old_tenant") return !_isAdmin(u) && _isFormerTenant(u);
      return !_isAdmin(u) && !_isFormerTenant(u);
    });

    if (k.isEmpty) return list.toList();

    return list.where((u) {
      final name = (u["full_name"] ?? "").toString().toLowerCase();
      final room = _roomLabel(u).toLowerCase();
      final phone = (u["phone"] ?? "").toString().toLowerCase();
      return name.contains(k) || room.contains(k) || phone.contains(k);
    }).toList();
  }

  // ✅ ช่วยระบุจับคู่เจาะจง Controller ให้กับ ListView แต่ละประเภทกลุ่มผู้ใช้
  ScrollController _getControllerForRole(String role) {
    if (role == "admin") return _scrollAdmin;
    if (role == "old_tenant") return _scrollOldTenant;
    return _scrollTenant;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 50,
        title: const Text(
          "จัดการผู้เช่า",
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: fHeader,
            color: cTextMain,
          ),
        ),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: cTextMain, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: cTextMain,
              unselectedLabelColor: Colors.grey,
              indicatorColor: cTextMain,
              indicatorSize: TabBarIndicatorSize.tab,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: const [
                Tab(text: "ผู้เช่าห้อง"),
                Tab(text: "ประวัติผู้เช่าเก่า"),
                Tab(text: "ผู้ดูแลหอพัก"),
              ],
            ),
          ),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: cTextMain))
          : Column(
              children: [
                _buildSearchField(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildListView("tenant"),
                      _buildListView("old_tenant"),
                      _buildListView("admin"),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: _showBackToTopButton
          ? FloatingActionButton(
              onPressed: _scrollToTop,
              backgroundColor: cTextMain,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.arrow_upward_rounded, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildSearchField() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: SizedBox(
        height: 40,
        child: TextField(
          onChanged: (v) => setState(() => keyword = v),
          style: const TextStyle(fontSize: fBody),
          decoration: InputDecoration(
            hintText: "ค้นหาชื่อ เบอร์โทรศัพท์ หรือ เลขห้องพัก",
            hintStyle: const TextStyle(fontSize: fDetail),
            prefixIcon: const Icon(Icons.search, size: 20, color: cIcon),
            filled: true,
            fillColor: cBg.withOpacity(0.3),
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildListView(String role) {
    final filtered = _filteredList(role);
    final currentController = _getControllerForRole(role); // ✅ เรียกเอา Controller ที่จับคู่ไว้มาใช้

    if (filtered.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchTenants,
        color: cTextMain,
        child: ListView(
          controller: currentController, // ✅ เปลี่ยนเป็นตัวแปรแท็บนั้น ๆ
          physics: const AlwaysScrollableScrollPhysics(), // ช่วยให้ลากนิ้วรีเฟรชได้เสมอแม้จอว่างเปล่า
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.55,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      role == "old_tenant" ? Icons.person_off_rounded : Icons.person_search_rounded,
                      size: 60,
                      color: cAccent,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      role == "old_tenant" ? "ไม่พบประวัติผู้เช่าเก่า" : "ไม่พบข้อมูลรายชื่อ",
                      style: const TextStyle(color: cTextMain, fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchTenants,
      color: cTextMain,
      child: ListView.builder(
        controller: currentController, // ✅ เปลี่ยนเป็นตัวแปรแยกส่วนบุคคลเรียบร้อย
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final u = filtered[index];
          final name = (u["full_name"] ?? u["username"] ?? "-").toString();
          
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 4)),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ProfilePage(tenantData: u)),
                ).then((value) => _fetchTenants());
              },
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: cAccent.withOpacity(0.4),
                      child: Icon(
                        role == "admin" ? Icons.admin_panel_settings_rounded : 
                        role == "old_tenant" ? Icons.person_remove_alt_1_rounded : Icons.person_rounded,
                        color: cIcon,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: cTextMain),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _roomLabel(u),
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Color(0xFFD7CCC8)),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}