import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config.dart';

class AdminPendingPage extends StatefulWidget {
  const AdminPendingPage({super.key});

  @override
  State<AdminPendingPage> createState() => _AdminPendingPageState();
}

class _AdminPendingPageState extends State<AdminPendingPage> {
  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cAccent = Color(0xFFDCD2C1);
  static const Color cIcon = Color(0xFF523D2D);
  static const Color cTextMain = Color(0xFF523D2D);

  static const double fHeader = 15.0;
  static const double fBody = 14.0;
  static const double fDetail = 13.0;
  static const double fCaption = 11.0;

  bool loading = true, saving = false;
  int savingUserDormId = 0;
  List<Map<String, dynamic>> pending = [], rooms = [];
  int dormId = 0, adminUserId = 0;
  String keyword = "";

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    dormId =
        prefs.getInt("dorm_id") ??
        int.tryParse(prefs.getString("dorm_id") ?? "0") ??
        0;
    adminUserId =
        prefs.getInt("user_id") ??
        int.tryParse(prefs.getString("user_id") ?? "0") ??
        0;
    if (!mounted) return;
    await _reload();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() => loading = true);
    await _loadBundle();
    if (mounted) setState(() => loading = false);
  }

  Future<void> _loadBundle() async {
    try {
      final res = await http.post(
        Uri.parse(AppConfig.url("tenants_api.php")),
        body: {
          "action": "pending",
          "dorm_id": dormId.toString(),
          "admin_user_id": adminUserId.toString(),
        },
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      if (data["success"] == true) {
        pending = List<Map<String, dynamic>>.from(data["pending"] ?? []);
        rooms = List<Map<String, dynamic>>.from(data["rooms"] ?? []);
      } else {
        pending = [];
        rooms = [];
      }
    } catch (e) {
      debugPrint("Load Error: $e");
      pending = [];
      rooms = [];
    }
  }

  int _toInt(dynamic v) => int.tryParse(v?.toString() ?? "0") ?? 0;

  String _prettyThaiDate(String? raw) {
    if (raw == null || raw.isEmpty) return "";
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
      return "${dt.day} ${thMonths[dt.month - 1]} ${dt.year + 543}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} น.";
    } catch (_) {
      return raw;
    }
  }

  String _fmtDateApi(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return "${d.year}-${two(d.month)}-${two(d.day)}";
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _performApproveApi(
    int udId,
    int uId,
    String? roomId,
    String date,
    String role,
  ) async {
    setState(() {
      saving = true;
      savingUserDormId = udId;
    });

    try {
      final Map<String, String> body = {
        "action": "approve",
        "dorm_id": dormId.toString(),
        "admin_user_id": adminUserId.toString(),
        "user_dorm_id": udId.toString(),
        "user_id": uId.toString(),
        "room_id": roomId ?? "",
        "move_in_date": date,
        "role": role,
      };

      final response = await http.post(
        Uri.parse(AppConfig.url("tenants_api.php")),
        body: body,
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (data["success"] == true) {
        _snack("ดำเนินการเรียบร้อยแล้ว ✅");
        await _reload();
      } else {
        _snack("ล้มเหลว: ${data["message"]}");
      }
    } catch (e) {
      _snack("เกิดข้อผิดพลาดในการเชื่อมต่อ");
    } finally {
      if (mounted) {
        setState(() {
          saving = false;
          savingUserDormId = 0;
        });
      }
    }
  }

  Future<void> _handleApproveSelection(Map<String, dynamic> p) async {
    final udId = _toInt(p["user_dorm_id"]);
    final uId = _toInt(p["user_id"]);
    final String name = (p["full_name"] ?? p["username"] ?? "-").toString();

    if (udId == 0) {
      _snack("ข้อมูลไม่ถูกต้อง");
      return;
    }

    final String? role = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        title: Text(
          "อนุมัติ: $name",
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: fHeader,
            color: cTextMain,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              "เลือกประเภทผู้ใช้งาน",
              style: TextStyle(fontSize: fDetail, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _buildCompactRoleButton(
                    ctx,
                    "tenant",
                    Icons.person_outline_rounded,
                    "ผู้เช่า",
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCompactRoleButton(
                    ctx,
                    "admin",
                    Icons.admin_panel_settings_outlined,
                    "ผู้ดูแล",
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text(
              "ยกเลิก",
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      ),
    );

    if (role == null) return;

    if (role == "admin") {
      await _performApproveApi(
        udId,
        uId,
        null,
        _fmtDateApi(DateTime.now()),
        "admin",
      );
    } else {
      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (_) => RoomSelectionPage(
            rooms: rooms,
            userName: name,
          ),
        ),
      );

      if (result != null) {
        await _performApproveApi(
          udId,
          uId,
          result["room_id"].toString(),
          result["date"],
          "tenant",
        );
      }
    }
  }

  Future<void> _reject(int udId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("ปฏิเสธคำขอ?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("ยกเลิก"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              "ปฏิเสธ",
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (ok == true) {
      await http.post(
        Uri.parse(AppConfig.url("tenants_api.php")),
        body: {
          "action": "reject",
          "dorm_id": dormId.toString(),
          "admin_user_id": adminUserId.toString(),
          "user_dorm_id": udId.toString(),
        },
      );
      await _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = pending.where((p) {
      final name = (p["full_name"] ?? p["username"] ?? "")
          .toString()
          .toLowerCase();
      final phone = (p["phone"] ?? "").toString();
      return name.contains(keyword.toLowerCase()) || phone.contains(keyword);
    }).toList();

    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 50,
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: cTextMain,
            size: 18,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "อนุมัติผู้เช่าใหม่",
          style: TextStyle(
            color: cTextMain,
            fontWeight: FontWeight.bold,
            fontSize: fHeader,
          ),
        ),
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(color: cTextMain),
            )
          : RefreshIndicator(
              onRefresh: _reload,
              color: cTextMain,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _headerCard(filtered.length),
                  const SizedBox(height: 12),
                  _searchField(),
                  const SizedBox(height: 12),
                  if (filtered.isEmpty) _emptyState() else ...filtered.map(_pendingCard),
                  const SizedBox(height: 100),
                ],
              ),
            ),
    );
  }

  Widget _headerCard(int count) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: cTextMain.withOpacity(0.04),
            blurRadius: 10,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cAccent.withOpacity(0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.how_to_reg_rounded,
              color: cIcon,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "รายการรออนุมัติ",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: fBody,
                    color: cTextMain,
                  ),
                ),
                Text(
                  "ทั้งหมด $count รายการ",
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: fCaption,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: cBg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              "$count",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: fCaption,
                color: cTextMain,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return SizedBox(
      height: 40,
      child: TextField(
        onChanged: (v) => setState(() => keyword = v),
        decoration: InputDecoration(
          hintText: "ค้นหาชื่อ หรือ เบอร์โทร",
          hintStyle: const TextStyle(fontSize: fDetail, color: Colors.grey),
          prefixIcon: const Icon(Icons.search, size: 18, color: cIcon),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 64,
              color: Colors.green.withOpacity(0.3),
            ),
            const SizedBox(height: 16),
            const Text(
              "ไม่มีรายการรออนุมัติ",
              style: TextStyle(
                color: cTextMain,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pendingCard(Map<String, dynamic> p) {
    final udId = _toInt(p["user_dorm_id"]);
    final name = (p["full_name"] ?? p["username"] ?? "-").toString();
    final dateRaw = (p["created_at"] ?? "").toString();
    final isRowSaving = saving && savingUserDormId == udId;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: cTextMain.withOpacity(0.03),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: cAccent.withOpacity(0.5),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : "?",
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: cIcon,
                fontSize: fHeader,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: fBody,
                    color: cTextMain,
                  ),
                ),
                Text(
                  _prettyThaiDate(dateRaw),
                  style: const TextStyle(
                    fontSize: fCaption,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              _actionBtn(
                Icons.check_rounded,
                Colors.green,
                isRowSaving,
                () => _handleApproveSelection(p),
              ),
              const SizedBox(width: 8),
              _actionBtn(
                Icons.close_rounded,
                Colors.redAccent,
                false,
                () => _reject(udId),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(
    IconData icon,
    Color color,
    bool isLoad,
    VoidCallback onTap,
  ) {
    return InkWell(
      onTap: saving ? null : onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: isLoad
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(icon, color: color, size: 20),
      ),
    );
  }

  Widget _buildCompactRoleButton(
    BuildContext ctx,
    String value,
    IconData icon,
    String label,
  ) {
    return InkWell(
      onTap: () => Navigator.pop(ctx, value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cAccent),
        ),
        child: Column(
          children: [
            Icon(icon, color: cIcon),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: fBody,
                color: cTextMain,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RoomSelectionPage extends StatefulWidget {
  final List<Map<String, dynamic>> rooms;
  final String userName;

  const RoomSelectionPage({
    super.key,
    required this.rooms,
    required this.userName,
  });

  @override
  State<RoomSelectionPage> createState() => _RoomSelectionPageState();
}

class _RoomSelectionPageState extends State<RoomSelectionPage> {
  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cAccent = Color(0xFFDCD2C1);
  static const Color cTextMain = Color(0xFF523D2D);
  static const Color cIcon = Color(0xFF523D2D);

  int? selectedRoomId;
  String keyword = "";
  DateTime selectedMoveInDate = DateTime.now();

  String _roomLabel(Map<String, dynamic> r) {
    final b = (r["building"] ?? "").toString().trim();
    final n = (r["room_number"] ?? "").toString().trim();
    return b.isEmpty ? n : (n.isEmpty ? b : "$b-$n");
  }

  String _fmtDateApi(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return "${d.year}-${two(d.month)}-${two(d.day)}";
  }

  String _prettyThaiDate(DateTime d) {
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
    return "${d.day} ${thMonths[d.month - 1]} ${d.year + 543}";
  }

  Future<void> _pickMoveInDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedMoveInDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: "เลือกวันย้ายเข้า",
    );

    if (picked != null) {
      setState(() => selectedMoveInDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = widget.rooms.where((r) {
      return _roomLabel(r).toLowerCase().contains(keyword.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        toolbarHeight: 50,
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: cTextMain, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "จัดสรรห้องพัก",
          style: TextStyle(
            color: cTextMain,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            color: Colors.white,
            child: Column(
              children: [
                const Text(
                  "ผู้ขอเข้าพัก",
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.userName,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: cTextMain,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: SizedBox(
              height: 40,
              child: TextField(
                onChanged: (v) => setState(() => keyword = v),
                decoration: InputDecoration(
                  hintText: "ค้นหาเลขห้อง...",
                  prefixIcon: const Icon(Icons.search, size: 20, color: cIcon),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: InkWell(
              onTap: _pickMoveInDate,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: cAccent.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.calendar_month_rounded,
                        color: cIcon,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        "วันย้ายเข้า",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: cTextMain,
                        ),
                      ),
                    ),
                    Text(
                      _prettyThaiDate(selectedMoveInDate),
                      style: const TextStyle(
                        fontSize: 13,
                        color: cTextMain,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: Colors.grey,
                    ),
                  ],
                ),
              ),
            ),
          ),

          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Text(
                      "ไม่พบห้องพักที่ว่าง",
                      style: TextStyle(color: cIcon.withOpacity(0.5)),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: filtered.length,
                    itemBuilder: (ctx, i) {
                      final r = filtered[i];
                      final rid = int.parse(r["room_id"].toString());
                      final isSel = selectedRoomId == rid;
                      final label = _roomLabel(r);

                      return GestureDetector(
                        onTap: () => setState(() => selectedRoomId = rid),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSel ? cTextMain : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: isSel
                                    ? cTextMain
                                    : cAccent.withOpacity(0.5),
                                child: Text(
                                  label.isNotEmpty ? label[0] : "?",
                                  style: TextStyle(
                                    color: isSel ? Colors.white : cIcon,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  "ห้อง $label",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: cTextMain,
                                  ),
                                ),
                              ),
                              if (isSel)
                                const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                  size: 20,
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              child: ElevatedButton(
                onPressed: selectedRoomId == null
                    ? null
                    : () {
                        Navigator.pop(context, {
                          "room_id": selectedRoomId,
                          "date": _fmtDateApi(selectedMoveInDate),
                        });
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: cTextMain,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  "ยืนยันการย้ายเข้า",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}