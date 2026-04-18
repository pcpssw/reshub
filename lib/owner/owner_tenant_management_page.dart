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
  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cAccent = Color(0xFFDCD2C1);
  static const Color cIcon = Color(0xFF523D2D);
  static const Color cTextMain = Color(0xFF603F26);

  static const double fHeader = 15.0;
  static const double fBody = 14.0;
  static const double fDetail = 13.0;
  static const double fCaption = 11.0;

  bool loading = true;
  int dormId = 0;
  late TabController _tabController;

  List<Map<String, dynamic>> allUsers = [];
  String keyword = "";

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    dormId =
        prefs.getInt("dorm_id") ??
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

  bool _isAdmin(Map<String, dynamic> u) {
    final role = (u["role"] ?? "").toString().toLowerCase();
    return role == "admin";
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

  bool _isFormerTenant(Map<String, dynamic> u) {
    if (_isAdmin(u)) return false;

    final tenantStatus = (u["tenant_status"] ?? "").toString().toLowerCase();
    final moveOutDate = (u["move_out_date"] ?? "").toString().trim();

    return tenantStatus == "former" || moveOutDate.isNotEmpty;
  }

  List<Map<String, dynamic>> _filteredList(String role) {
    final k = keyword.trim().toLowerCase();

    Iterable<Map<String, dynamic>> list = allUsers.where((u) {
      if (role == "admin") {
        return _isAdmin(u);
      }

      if (role == "old_tenant") {
        return !_isAdmin(u) && _isFormerTenant(u);
      }

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

  String _subLabel(Map<String, dynamic> u, String role) {
    if (role == "admin") {
      final roleInDorm = (u["role_in_dorm"] ?? "").toString().toLowerCase();
      return roleInDorm == "owner" ? "เจ้าของหอพัก" : "ผู้ดูแลหอพัก";
    }

    final room = _roomLabel(u);

    if (role == "old_tenant") {
      return room == "รอการจัดห้อง" ? "ผู้เช่าเก่า" : "ห้อง $room";
    }

    return room == "รอการจัดห้อง" ? room : "ห้อง $room";
  }

  IconData _leadingIcon(String role) {
    if (role == "admin") return Icons.admin_panel_settings_rounded;
    if (role == "old_tenant") return Icons.person_remove_alt_1_rounded;
    return Icons.person_rounded;
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
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: cTextMain,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: cTextMain,
          unselectedLabelColor: Colors.grey,
          indicatorColor: cTextMain,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: fBody,
          ),
          tabs: const [
            Tab(text: "ผู้เช่าหอพัก"),
            Tab(text: "ประวัติผู้เช่าเก่า"),
            Tab(text: "ผู้ดูแลหอพัก"),
          ],
        ),
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: cTextMain),
            )
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
    final bool isAdminPage = role == "admin";

    if (filtered.isEmpty) {
      String emptyText = "ไม่พบข้อมูลรายชื่อ";
      if (role == "old_tenant") emptyText = "ไม่พบประวัติผู้เช่าเก่า";
      if (role == "admin") emptyText = "ไม่พบข้อมูลผู้ดูแลหอพัก";

      return RefreshIndicator(
        onRefresh: _fetchTenants,
        color: cTextMain,
        child: ListView(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.55,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      role == "old_tenant"
                          ? Icons.person_off_rounded
                          : Icons.person_search_rounded,
                      size: 60,
                      color: cAccent,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      emptyText,
                      style: const TextStyle(
                        color: cTextMain,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final u = filtered[index];
          final name = (u["full_name"] ?? u["username"] ?? "-").toString();
          final subLabel = _subLabel(u, role);

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfilePage(tenantData: u),
                  ),
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
                        _leadingIcon(role),
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
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: cTextMain,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            subLabel,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      isAdminPage
                          ? Icons.arrow_forward_ios_rounded
                          : role == "old_tenant"
                              ? Icons.person_remove_alt_1_rounded
                              : Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: const Color(0xFFD7CCC8),
                    ),
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