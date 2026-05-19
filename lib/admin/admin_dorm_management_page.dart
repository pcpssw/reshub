import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../config.dart';

// =========================================================================
// 🏢 1. หน้าหลัก: รายการหอพักทั้งหมดในระบบ (PlatformDormListPage)
// =========================================================================
class PlatformDormListPage extends StatefulWidget {
  const PlatformDormListPage({super.key});

  @override
  State<PlatformDormListPage> createState() => _PlatformDormListPageState();
}

class _PlatformDormListPageState extends State<PlatformDormListPage> {
  final TextEditingController searchCtrl = TextEditingController();
  bool loading = true;

  String statusFilter = "all"; 
  List<Map<String, dynamic>> dorms = [];

  // 🎨 Palette: Deep Coffee & Cream ☕
  static const Color cBg = Color(0xFFF4EFE6);       
  static const Color cAccent = Color(0xFFDCD2C1);   
  static const Color cTextMain = Color(0xFF2A1F17); 
  static const Color cDark = Color(0xFF523D2D);     

  final Map<String, String> statusMap = const {
    "all": "ทั้งหมด",
    "active": "ใช้งานอยู่",
    "suspended": "ปิดใช้งาน",
  };

  @override
  void initState() {
    super.initState();
    fetchDorms();
  }

  @override
  void dispose() {
    searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get filtered {
    if (statusFilter == "all") return dorms;
    return dorms.where((d) => (d["status"] ?? "") == statusFilter).toList();
  }

  Color _getFilterColor(String key) {
    switch (key) {
      case "all":       return cDark; 
      case "active":    return const Color(0xFF2E7D32); 
      case "suspended": return const Color(0xFFD32F2F); 
      default:          return Colors.grey;
    }
  }

  Future<void> fetchDorms() async {
    if (!mounted) return;
    setState(() => loading = true);
    try {
      final url = Uri.parse("${AppConfig.baseUrl}/dashboard_api.php");
      
      final res = await http.post(url, body: {
        "action": "listDorms",
        "q": searchCtrl.text.trim(),
      }).timeout(const Duration(seconds: 12));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data["success"] == true) {
        final List list = (data["data"] as List?) ?? [];
        setState(() {
          dorms = list.map((e) => Map<String, dynamic>.from(e)).toList();
        });
      }
    } catch (e) { 
      debugPrint("Fetch dorms error: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _setDormStatus(int dormId, String newStatus) async {
    try {
      final url = Uri.parse("${AppConfig.baseUrl}/dashboard_api.php");
      
      final res = await http.post(url, body: {
        "action": "setDormStatus",
        "dorm_id": dormId.toString(),
        "status": newStatus,
      }).timeout(const Duration(seconds: 12));

      final data = jsonDecode(res.body);
      if (res.statusCode == 200 && data["success"] == true) {
        fetchDorms();
      }
    } catch (e) {
      debugPrint("Set status error: $e");
    }
  }

  void _showStatusPicker(int dormId, String currentStatus) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 55, vertical: 24), 
        child: Padding(
          padding: const EdgeInsets.all(20), 
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.edit_attributes_rounded, color: cDark, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    "จัดการสถานะหอพัก",
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: cTextMain),
                  ),
                ],
              ),
              const Divider(height: 20, thickness: 1),
              _statusOption(
                label: "เปิดใช้งาน",
                icon: Icons.check_circle_rounded,
                color: const Color(0xFF2E7D32),
                isSelected: currentStatus == "active",
                onTap: () {
                  Navigator.pop(context);
                  _setDormStatus(dormId, "active");
                },
              ),
              _statusOption(
                label: "ปิดการใช้งาน",
                icon: Icons.block_flipped,
                color: const Color(0xFFD32F2F),
                isSelected: currentStatus == "suspended",
                onTap: () {
                  Navigator.pop(context);
                  _setDormStatus(dormId, "suspended");
                },
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 40,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  child: const Text(
                    "ยกเลิก",
                    style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusOption({required String label, required IconData icon, required Color color, required bool isSelected, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.08) : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? color : Colors.grey[200]!, width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 12),
            Text(label, style: TextStyle(fontWeight: FontWeight.w800, color: isSelected ? color : cTextMain, fontSize: 13)),
            const Spacer(),
            Icon(isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded, color: isSelected ? color : Colors.grey[300], size: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final list = filtered;
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        backgroundColor: Colors.white, elevation: 0.5, toolbarHeight: 60,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: cTextMain), onPressed: () => Navigator.pop(context)),
        title: const Text("จัดการหอพัก", style: TextStyle(fontWeight: FontWeight.w900, color: cTextMain, fontSize: 16)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildTopSearchAndFilter(),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator(color: cDark))
                : list.isEmpty
                    ? const Center(child: Text("ไม่พบข้อมูลหอพัก", style: TextStyle(fontWeight: FontWeight.bold, color: cDark)))
                    : RefreshIndicator(
                        onRefresh: fetchDorms,
                        color: cDark,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 14),
                          itemBuilder: (_, i) => _dormCard(list[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopSearchAndFilter() {
    return Container(
      color: Colors.white, padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), // 🛠️ ปรับ Padding ให้กะทัดรัดเท่ารูปที่สอง
      child: Column(children: [
        SizedBox(
          height: 40, // 🛠️ บังคับความสูงกล่องคลีน ๆ 40 เท่ารูปสอง
          child: TextField(
            controller: searchCtrl, onSubmitted: (_) => fetchDorms(),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cTextMain),
            decoration: InputDecoration(
              hintText: "ค้นหา ชื่อหอ / โค้ดหอ", 
              hintStyle: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold),
              prefixIcon: const Icon(Icons.search_rounded, size: 20, color: cDark), // 🛠️ ปรับขนาดไอคอนลดลงเหลือ 20 เท่ารูปสอง
              filled: true, 
              fillColor: cBg.withOpacity(0.3), // 🛠️ ล็อกความโปร่งแสงสีพื้นหลังเท่ารูปสอง
              contentPadding: EdgeInsets.zero, // 🛠️ ใส่เซ็ตติ้งล้าง padding ภายใน เพื่อให้ขนาดยุบลงมาเท่ากันเป๊ะ
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), // 🛠️ ความมนเหลี่ยมมุมปรับเป็น 12 เท่ารูปสองจ้า
            ),
          ),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: statusMap.entries.map((entry) {
            final isSelected = statusFilter == entry.key;
            final color = _getFilterColor(entry.key);
            return Padding(
              padding: const EdgeInsets.only(right: 10),
              child: InkWell(
                onTap: () => setState(() => statusFilter = entry.key),
                borderRadius: BorderRadius.circular(20),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(color: isSelected ? color : color.withOpacity(0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: isSelected ? color : color.withOpacity(0.3), width: 1.5)),
                  child: Row(children: [
                    if (isSelected) ...[const Icon(Icons.check_circle_rounded, size: 14, color: Colors.white), const SizedBox(width: 8)],
                    Text(entry.value, style: TextStyle(color: isSelected ? Colors.white : color, fontWeight: FontWeight.w900, fontSize: 12)),
                  ]),
                ),
              ),
            );
          }).toList()),
        ),
      ]),
    );
  }

  Widget _dormCard(Map<String, dynamic> d) {
    final dormId = int.tryParse((d["dorm_id"] ?? "0").toString()) ?? 0;
    final status = d["status"] ?? "active";
    final String dormName = d["dorm_name"] ?? "-";
    
    final String dormAddress = (d["dorm_address"] != null && d["dorm_address"].toString().trim().isNotEmpty) 
        ? d["dorm_address"].toString() 
        : "ยังไม่ได้กรอกที่อยู่หอพัก";
    final String dormPhone = (d["dorm_phone"] != null && d["dorm_phone"].toString().trim().isNotEmpty) 
        ? d["dorm_phone"].toString() 
        : "ยังไม่ได้กรอกเบอร์โทรศัพท์โทรหอพัก";

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PlatformDormUserSummaryPage(
            dormId: dormId, 
            dormName: dormName,
            dormAddress: dormAddress, 
            dormPhone: dormPhone,     
          ),
        ),
      ),
      onLongPress: () => _showStatusPicker(dormId, status), 
      child: Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12, offset: const Offset(0, 4))]),
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(children: [
              Container(width: 48, height: 48, decoration: BoxDecoration(color: _statusColor(status).withOpacity(0.1), borderRadius: BorderRadius.circular(15)), child: Icon(Icons.apartment_rounded, color: _statusColor(status), size: 26)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(dormName, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: cTextMain)),
                const SizedBox(height: 2),
                Text("รหัส : ${d["dorm_code"] ?? "-"}", style: const TextStyle(color: Color(0xFF757575), fontSize: 11, fontWeight: FontWeight.w800)),
              ])),
              GestureDetector(
                onTap: () => _showStatusPicker(dormId, status),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: _statusColor(status).withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: _statusColor(status).withOpacity(0.2))),
                  child: Row(children: [
                    Text(_statusText(status), style: TextStyle(fontWeight: FontWeight.w900, color: _statusColor(status), fontSize: 10)),
                    const SizedBox(width: 4),
                    Icon(Icons.sync_alt_rounded, size: 10, color: _statusColor(status)),
                  ]),
                ),
              ),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(color: cBg.withOpacity(0.3), borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24))),
            child: Row(children: [
              Expanded(
                child: _miniBoxClickable(
                  label: "ผู้เช่า",
                  value: d["tenant_count"]?.toString() ?? "0",
                  icon: Icons.people_alt_rounded,
                  color: cDark,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlatformDormUserSummaryPage(
                        dormId: dormId, 
                        dormName: dormName,
                        dormAddress: dormAddress, 
                        dormPhone: dormPhone,     
                      ),
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 25, color: cAccent.withOpacity(0.5)),
              Expanded(
                child: _miniBoxClickable(
                  label: "ผู้ดูแลหอพัก",
                  value: d["admin_count"]?.toString() ?? "0",
                  icon: Icons.admin_panel_settings_rounded,
                  color: cDark,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlatformDormUserSummaryPage(
                        dormId: dormId, 
                        dormName: dormName,
                        dormAddress: dormAddress, 
                        dormPhone: dormPhone,     
                      ),
                    ),
                  ),
                ),
              ),
              Container(width: 1, height: 25, color: cAccent.withOpacity(0.5)),
              Expanded(
                child: _miniBoxClickable(
                  label: "รออนุมัติ",
                  value: d["pending_count"]?.toString() ?? "0",
                  icon: Icons.hourglass_empty_rounded,
                  color: const Color(0xFFEF6C00),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlatformDormUserSummaryPage(
                        dormId: dormId, 
                        dormName: dormName,
                        dormAddress: dormAddress, 
                        dormPhone: dormPhone,     
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _miniBoxClickable({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: cTextMain),
            ),
          ],
        ),
      ),
    );
  }

  Color _statusColor(dynamic s) => s == "active" ? const Color(0xFF2E7D32) : const Color(0xFFD32F2F);
  String _statusText(dynamic s) => s == "active" ? "ใช้งานอยู่" : "ปิดใช้งาน";
}

// =========================================================================
// 🚀 2. หน้ารายชื่อสรุปแบบเจาะลึกเฉพาะผู้ดูแลหอพัก ดีไซน์กล่องตามสไตล์หน้าโฮม 🏠
// =========================================================================
class PlatformDormUserSummaryPage extends StatefulWidget {
  final int dormId;
  final String dormName;
  final String dormAddress; 
  final String dormPhone;   

  const PlatformDormUserSummaryPage({
    super.key,
    required this.dormId,
    required this.dormName,
    required this.dormAddress, 
    required this.dormPhone,   
  });

  @override
  State<PlatformDormUserSummaryPage> createState() => _PlatformDormUserSummaryPageState();
}

class _PlatformDormUserSummaryPageState extends State<PlatformDormUserSummaryPage>
    with SingleTickerProviderStateMixin {
  bool _loading = true;
  List<dynamic> _dormAdmins = [];
  late TabController _tabController; 
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cCard = Color(0xFFFFFFFF);
  static const Color cAccent = Color(0xFFDCD2C1);
  static const Color cTextMain = Color(0xFF2A1F17);
  static const Color cDark = Color(0xFF523D2D);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 1, vsync: this);
    _fetchDormAdmins();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchDormAdmins() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final res = await http.post(
        Uri.parse("${AppConfig.baseUrl}/dashboard_api.php"),
        body: {"action": "getDormUsers", "dorm_id": widget.dormId.toString(), "role_type": "admin"},
      ).timeout(const Duration(seconds: 12));

      final data = jsonDecode(res.body);
      if (data["success"] == true) {
        setState(() {
          _dormAdmins = data["data"] ?? [];
        });
      }
    } catch (e) {
      debugPrint("Error loading dorm admins: $e");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<dynamic> get _filteredAdmins {
    if (_searchQuery.isEmpty) return _dormAdmins;
    return _dormAdmins.where((u) {
      final String name = (u["full_name"] ?? "").toString().toLowerCase();
      final String phone = (u["phone"] ?? "").toString().toLowerCase();
      return name.contains(_searchQuery) || phone.contains(_searchQuery);
    }).toList();
  }

  String _formatThaiDateOnly(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty || dateStr == "null") return "-";
    try {
      final dt = DateTime.parse(dateStr.trim().replaceFirst(" ", "T"));
      const months = [
        "ม.ค.", "ก.พ.", "มี.ค.", "เม.ย.", "พ.ค.", "มิ.ย.", 
        "ก.ค.", "ส.ค.", "ก.ย.", "ต.ค.", "พ.ย.", "ธ.ค."
      ];
      return "${dt.day} ${months[dt.month - 1]} ${dt.year + 543}";
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    String adminStartDate = "-";
    if (_dormAdmins.isNotEmpty && _dormAdmins[0]["start_date"] != null) {
      adminStartDate = _formatThaiDateOnly(_dormAdmins[0]["start_date"]);
    }

    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5, 
        toolbarHeight: 60, 
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: cTextMain), 
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.dormName, 
          style: const TextStyle(fontWeight: FontWeight.w900, color: cTextMain, fontSize: 16), 
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: SizedBox(
              height: 40,
              child: TextField(
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cTextMain), 
                decoration: InputDecoration(
                  hintText: "ค้นหาชื่อ หรือเบอร์โทรศัพท์โทรผู้ดูแล...",
                  hintStyle: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.bold), 
                  prefixIcon: const Icon(Icons.search_rounded, size: 20, color: cDark), 
                  filled: true,
                  fillColor: cBg.withOpacity(0.3), 
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none), 
                ),
              ),
            ),
          ),

          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cCard,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: cTextMain.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: cBg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.business_rounded,
                        color: cTextMain,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        widget.dormName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: cTextMain,
                        ),
                      ),
                    ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Divider(height: 1),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    "โทร : ${widget.dormPhone}",
                    style: const TextStyle(color: cTextMain, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    "ที่อยู่ : ${widget.dormAddress}",
                    style: const TextStyle(color: cTextMain, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                const SizedBox(height: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    "เริ่มใช้งานเมื่อ : $adminStartDate", 
                    style: const TextStyle(color: cTextMain, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: cDark))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAdminListView(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminListView() {
    final list = _filteredAdmins;

    if (list.isEmpty) {
      return ListView(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.45,
            child: const Center(
              child: Text(
                "ไม่พบข้อมูลผู้ดูแลหอพัก 📭",
                style: TextStyle(color: cDark, fontWeight: FontWeight.w900, fontSize: 14),
              ),
            ),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchDormAdmins,
      color: cDark,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        itemCount: list.length,
        itemBuilder: (context, index) {
          final user = list[index];

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: cBg, 
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(Icons.people_alt_rounded, color: cDark, size: 20),
                  ),
                  const SizedBox(width: 14),
                  
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user["full_name"] ?? "-",
                          style: const TextStyle(fontWeight: FontWeight.w900, color: cTextMain, fontSize: 14),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          "โทร : ${user["phone"] ?? "-"}",
                          style: const TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}