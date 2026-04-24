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
  final ScrollController _scrollController = ScrollController(); // สำหรับควบคุมการเลื่อน
  bool _showBackToTopButton = false; // สถานะการแสดงปุ่มเด้งขึ้นบน

  List<Map<String, dynamic>> allUsers = [];
  String keyword = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);

    // ตรวจสอบตำแหน่งการเลื่อนเพื่อโชว์/ซ่อนปุ่ม
    _scrollController.addListener(() {
      if (_scrollController.offset >= 300) {
        if (!_showBackToTopButton) {
          setState(() => _showBackToTopButton = true);
        }
      } else {
        if (_showBackToTopButton) {
          setState(() => _showBackToTopButton = false);
        }
      }
    });

    _init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scrollController.dispose(); // คืนคืน Memory
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

      final res = await http.get(uri).timeout(const Duration(seconds: 10));
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
      }
    } catch (e) {
      debugPrint("Error: $e");
      if (!mounted) return;
      setState(() => allUsers = []);
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  // ฟังก์ชันเลื่อนกลับขึ้นไปบนสุด
  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  // --- Helper Methods ---
  bool _isAdmin(Map<String, dynamic> u) {
    final role = (u["role"] ?? "").toString().toLowerCase();
    return role == "admin";
  }

  bool _isFormerTenant(Map<String, dynamic> u) {
    if (_isAdmin(u)) return false;
    final tenantStatus = (u["tenant_status"] ?? "").toString().toLowerCase();
    final moveOutDate = (u["move_out_date"] ?? "").toString().trim();
    return tenantStatus == "former" || moveOutDate.isNotEmpty;
  }

  String _roomLabel(Map<String, dynamic> t) {
    if (_isAdmin(t)) {
      final roleInDorm = (t["role_in_dorm"] ?? "").toString().toLowerCase();
      return roleInDorm == "owner" ? "เจ้าของหอพัก" : "ผู้ดูแลหอพัก";
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
                Tab(text: "ผู้ดูแลห้อง"),
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
      // ปุ่มเด้งขึ้นบน (จะแสดงเมื่อเลื่อนลงมาเกิน 300px)
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
            hintText: "ค้นหาชื่อ เบอร์โทร หรือ เลขห้องพัก",
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
    if (filtered.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchTenants,
        color: cTextMain,
        child: ListView(
          controller: _scrollController, // ใส่ Controller เพื่อให้เช็คตำแหน่งได้
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
        controller: _scrollController, // ใส่ Controller ตรงนี้เพื่อให้ปุ่มทำงาน
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