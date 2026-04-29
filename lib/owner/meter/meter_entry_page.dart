import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config.dart';
import '../utility_rates_page.dart';

class MeterEntryPage extends StatefulWidget {
  const MeterEntryPage({super.key});

  @override
  State<MeterEntryPage> createState() => _MeterEntryPageState();
}

class _MeterEntryPageState extends State<MeterEntryPage>
    with SingleTickerProviderStateMixin {
  static const String apiFile = "meter_api.php";

  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cTextMain = Color(0xFF523D2D);
  static const Color cIcon = Color(0xFF523D2D);
  static const Color cAccent = Color(0xFFDCD2C1);

  static const double fTitle = 16.0;
  static const double fHeader = 15.0;
  static const double fBody = 14.0;
  static const double fDetail = 13.0;
  static const double fCaption = 11.0;

  late TabController _tabController;
  bool _isTabControllerInitialized = false;
  bool loading = true, saving = false;
  int dormId = 0;
  late DateTime selectedMonth;
  List<_RoomRow> rooms = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    setState(() => _isTabControllerInitialized = true);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
    final now = DateTime.now();
    selectedMonth = DateTime(now.year, now.month);
    _init();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (var r in rooms) {
      r.dispose();
    }
    super.dispose();
  }

  bool _hasUnsavedData() {
    for (var r in rooms) {
      if (!r.hasTenant) continue;
      if (r.waterCtrl.text != r.initWater || r.elecCtrl.text != r.initElec) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _showExitConfirmation() async {
    final confirm = await showDialog<bool>(
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
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.redAccent,
                  size: 40,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "ออกจากหน้านี้",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: cTextMain,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                "ข้อมูลที่คุณแก้ไขยังไม่ได้บันทึก\nยืนยันที่จะออกจากหน้านี้หรือไม่?",
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: cTextMain,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "ยืนยัน",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: cAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        "ยกเลิก",
                        style: TextStyle(
                          color: cTextMain,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
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
    return confirm ?? false;
  }

  Future<void> _init() async {
    if (!mounted) return;
    setState(() => loading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      dormId = prefs.getInt("dorm_id") ?? prefs.getInt("selected_dorm_id") ?? 0;
      if (dormId > 0) await _loadData();
    } catch (e) {
      debugPrint("Init Error: $e");
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _loadData() async {
    final uri = Uri.parse(AppConfig.url(apiFile)).replace(queryParameters: {
      "action": "get",
      "dorm_id": dormId.toString(),
      "month": selectedMonth.month.toString(),
      "year": selectedMonth.year.toString(),
    });

    try {
      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      final data = jsonDecode(res.body);

      if (data["ok"] == true) {
        for (var r in rooms) {
          r.dispose();
        }
        rooms.clear();

        for (var item in (data["rooms"] as List)) {
          final map = Map<String, dynamic>.from(item);

          final String currentWater =
              map["current_water_meter"]?.toString() ?? "";
          final String currentElec =
              map["current_electric_meter"]?.toString() ?? "";

          final String valW =
              (currentWater == "0" || currentWater == "") ? "" : currentWater;
          final String valE =
              (currentElec == "0" || currentElec == "") ? "" : currentElec;

          final int tenantId =
              int.tryParse(map["tenant_id"]?.toString() ?? "0") ?? 0;
          final String tenantName =
              (map["full_name"] ?? "").toString().trim();

          // 💡 ตรวจสอบวันที่เข้าอยู่ (ถ้าชื่อฟิลด์ใน DB ไม่ใช่ move_in_date ให้เปลี่ยนตรงนี้นะครับ)
          final String moveInDateStr = map["move_in_date"]?.toString() ?? "";
          bool isActuallyLivingHere = true; // ตัวแปรเช็กว่าอยู่จริงในเดือนที่เลือกไหม

          if (moveInDateStr.isNotEmpty) {
            try {
              final moveInDate = DateTime.parse(moveInDateStr);
              // ถ้าย้ายเข้ามาในปี/เดือนที่ "มากกว่า" เดือนที่กำลังเลือกใน Dropdown แปลว่ายังไม่เข้าอยู่
              if (moveInDate.year > selectedMonth.year || 
                 (moveInDate.year == selectedMonth.year && moveInDate.month > selectedMonth.month)) {
                isActuallyLivingHere = false; 
              }
            } catch (e) {
              debugPrint("Parse date error: $e");
            }
          }

          // 💡 เช็กว่ามีผู้เช่าและย้ายเข้ามาในเดือนนั้นแล้วจริงๆ
          final bool hasTenant = (tenantId > 0 || tenantName.isNotEmpty) && isActuallyLivingHere;

          rooms.add(
            _RoomRow(
              roomId: int.tryParse(map["room_id"]?.toString() ?? "0") ?? 0,
              roomNumber: map["room_number"]?.toString() ?? "-",
              building: map["building"]?.toString() ?? "",
              prevWater:
                  int.tryParse(map["prev_water_meter"]?.toString() ?? "0") ?? 0,
              prevElec:
                  int.tryParse(map["prev_electric_meter"]?.toString() ?? "0") ??
                      0,
              waterCtrl: TextEditingController(text: valW),
              elecCtrl: TextEditingController(text: valE),
              initWater: valW,
              initElec: valE,
              hasTenant: hasTenant,
            ),
          );
        }

        if (mounted) setState(() {});
      }
    } catch (e) {
      debugPrint("Load Error: $e");
    }
  }

  // ✅ แก้ไข: ฟังก์ชันบันทึกข้อมูลแบบไม่ให้ค่าหาย
  Future<void> _saveAllData() async {
    final items = <Map<String, dynamic>>[];

    for (var r in rooms) {
      if (!r.hasTenant) continue;

      final wVal = r.waterCtrl.text.trim();
      final eVal = r.elecCtrl.text.trim();

      // เช็คว่ามีการเปลี่ยนแปลงค่าใดค่าหนึ่งหรือไม่
      bool waterChanged = wVal != r.initWater;
      bool elecChanged = eVal != r.initElec;

      if (waterChanged || elecChanged) {
        final Map<String, dynamic> row = {"room_id": r.roomId};

        // ตรวจสอบและใส่เลขนน้ำ
        final intW = int.tryParse(wVal) ?? 0;
        if (wVal.isNotEmpty && intW < r.prevWater) {
          _snack("เลขน้ำห้อง ${r.label} ต่ำกว่าเดือนก่อน");
          return;
        }
        row["water_meter"] = wVal.isEmpty ? 0 : intW;

        // ตรวจสอบและใส่เลขไฟ
        final intE = int.tryParse(eVal) ?? 0;
        if (eVal.isNotEmpty && intE < r.prevElec) {
          _snack("เลขไฟห้อง ${r.label} ต่ำกว่าเดือนก่อน");
          return;
        }
        row["electric_meter"] = eVal.isEmpty ? 0 : intE;

        items.add(row);
      }
    }

    if (items.isEmpty) {
      _snack("ไม่มีข้อมูลที่เปลี่ยนแปลง");
      return;
    }

    setState(() => saving = true);
    try {
      final url = Uri.parse(AppConfig.url(apiFile)).replace(
        queryParameters: {"action": "save"},
      );

      final res = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "dorm_id": dormId,
          "month": selectedMonth.month,
          "year": selectedMonth.year,
          "items": items,
        }),
      ).timeout(const Duration(seconds: 15));

      final resp = jsonDecode(res.body);
      if (resp["ok"] == true) {
        _snack("บันทึกเรียบร้อย");
        await _loadData(); // โหลดข้อมูลใหม่เพื่อรีเซ็ตค่า initWater/initElec
      } else {
        _snack("บันทึกไม่สำเร็จ: ${resp["message"] ?? "ลองใหม่อีกครั้ง"}");
      }
    } catch (e) {
      debugPrint("Save Error: $e");
      _snack("การเชื่อมต่อมีปัญหา กรุณาลองใหม่");
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget _buildRoomCard(_RoomRow r, bool isWater) {
    final themeColor = isWater ? const Color(0xFF4A90E2) : cTextMain;
    final ctrl = isWater ? r.waterCtrl : r.elecCtrl;
    final prev = isWater ? r.prevWater : r.prevElec;
    final initVal = isWater ? r.initWater : r.initElec;
    final nowText = ctrl.text.trim();
    final now = int.tryParse(nowText) ?? 0;
    final used = nowText.isEmpty ? 0 : max(0, now - prev);
    final bool isError = r.hasTenant && nowText.isNotEmpty && now < prev;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: r.hasTenant ? Colors.white : const Color(0xFFF7F4EF),
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: cTextMain.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          )
        ],
        border: Border.all(
          color: isError
              ? Colors.red
              : (r.hasTenant ? Colors.transparent : cAccent),
          width: 1.2,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.label,
                  style: GoogleFonts.kanit(
                    fontWeight: FontWeight.w600,
                    fontSize: fTitle,
                    color: cTextMain,
                  ),
                ),
                const SizedBox(height: 2),
                if (r.hasTenant)
                  Text(
                    "ครั้งก่อน: $prev",
                    style: GoogleFonts.kanit(
                      color: Colors.grey,
                      fontSize: fDetail,
                      fontWeight: FontWeight.normal,
                    ),
                  )
                else
                  Row(
                    children: [
                      const Icon(
                        Icons.lock_outline_rounded,
                        size: 14,
                        color: Colors.grey,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        "ห้องว่าง",
                        style: GoogleFonts.kanit(
                          color: Colors.grey,
                          fontSize: fDetail,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
          Column(
            children: [
              Text(
                r.hasTenant ? "ใช้ไป" : "สถานะ",
                style: GoogleFonts.kanit(
                  color: Colors.grey,
                  fontSize: fCaption,
                  fontWeight: FontWeight.normal,
                ),
              ),
              Text(
                r.hasTenant ? "$used" : "-",
                style: GoogleFonts.kanit(
                  fontWeight: FontWeight.bold,
                  color: r.hasTenant ? themeColor : Colors.grey,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: TextField(
              controller: ctrl,
              enabled: r.hasTenant,
              readOnly: !r.hasTenant,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: GoogleFonts.kanit(
                fontWeight: FontWeight.normal,
                fontSize: fBody,
                color: r.hasTenant ? cTextMain : Colors.grey,
              ),
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                hintText: r.hasTenant ? "$prev" : "-",
                hintStyle: GoogleFonts.kanit(
                  fontSize: fBody,
                  color: Colors.grey.withOpacity(0.4),
                ),
                filled: true,
                isDense: true,
                fillColor: !r.hasTenant
                    ? const Color(0xFFEDE7DD)
                    : isError
                        ? Colors.red.shade50
                        : (nowText != initVal
                            ? themeColor.withOpacity(0.05)
                            : cBg.withOpacity(0.4)),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: r.hasTenant ? (_) => setState(() {}) : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading || !_isTabControllerInitialized) {
      return const Scaffold(
        backgroundColor: cBg,
        body: Center(
          child: CircularProgressIndicator(color: cTextMain),
        ),
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (!_hasUnsavedData()) {
          Navigator.pop(context);
          return;
        }
        final shouldPop = await _showExitConfirmation();
        if (shouldPop && mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: cBg,
        appBar: AppBar(
          toolbarHeight: 50,
          elevation: 0.5,
          backgroundColor: Colors.white,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new,
              color: cTextMain,
              size: 18,
            ),
            onPressed: () async {
              if (!_hasUnsavedData()) {
                Navigator.pop(context);
              } else {
                final result = await _showExitConfirmation();
                if (result == true && mounted) Navigator.pop(context);
              }
            },
          ),
          title: Text(
            "กรอกมิเตอร์",
            style: TextStyle(
              color: cTextMain,
              fontWeight: FontWeight.bold,
              fontSize: fHeader,
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12, top: 10, bottom: 10),
              child: OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DormRatesPage()),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: cAccent, width: 1.2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                child: const Text(
                  "เรทราคา",
                  style: TextStyle(
                    color: cTextMain,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            _buildMonthPickerHeader(),
            _buildCustomTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildListPage(true),
                  _buildListPage(false),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: _buildTotalSaveButton(),
      ),
    );
  }

  Widget _buildTotalSaveButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          )
        ],
      ),
      child: SafeArea(
        child: ElevatedButton(
          onPressed: saving ? null : _saveAllData,
          style: ElevatedButton.styleFrom(
            backgroundColor: cTextMain,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  "บันทึก",
                  style: GoogleFonts.kanit(
                    fontSize: fBody,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildMonthPickerHeader() {
    final months = List.generate(12, (i) {
      final now = DateTime.now();
      return DateTime(now.year, now.month - i);
    });

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: DropdownButtonFormField<DateTime>(
        value: selectedMonth,
        decoration: InputDecoration(
          labelText: "ประจำเดือน",
          labelStyle: GoogleFonts.kanit(
            fontSize: fDetail,
            color: cTextMain,
          ),
          filled: true,
          fillColor: cBg.withOpacity(0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
        items: months.map((m) {
          return DropdownMenuItem(
            value: m,
            child: Text(
              "${_getMonthName(m.month)} / ${m.year + 543}",
              style: GoogleFonts.kanit(
                fontSize: fBody,
                color: cTextMain,
              ),
            ),
          );
        }).toList(),
        onChanged: (m) {
          if (m != null) {
            setState(() => selectedMonth = m);
            _init();
          }
        },
      ),
    );
  }

  Widget _buildCustomTabBar() {
    return Container(
      color: Colors.white,
      child: TabBar(
        controller: _tabController,
        indicatorColor: cTextMain,
        labelColor: cTextMain,
        unselectedLabelColor: Colors.grey,
        labelStyle: GoogleFonts.kanit(
          fontWeight: FontWeight.w600,
          fontSize: fBody,
        ),
        tabs: const [
          Tab(text: "มิเตอร์น้ำ"),
          Tab(text: "มิเตอร์ไฟ"),
        ],
      ),
    );
  }

  Widget _buildListPage(bool isWater) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: rooms.length,
      itemBuilder: (context, index) => _buildRoomCard(rooms[index], isWater),
    );
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.kanit()),
        behavior: SnackBarBehavior.floating,
        backgroundColor: cTextMain,
      ),
    );
  }

  String _getMonthName(int m) => [
        "",
        "มกราคม",
        "กุมภาพันธ์",
        "มีนาคม",
        "เมษายน",
        "พฤษภาคม",
        "มิถุนายน",
        "กรกฎาคม",
        "สิงหาคม",
        "กันยายน",
        "ตุลาคม",
        "พฤศจิกายน",
        "ธันวาคม",
      ][m];
}

class _RoomRow {
  final int roomId, prevWater, prevElec;
  final String roomNumber, building;
  final TextEditingController waterCtrl, elecCtrl;
  final String initWater, initElec;
  final bool hasTenant;

  _RoomRow({
    required this.roomId,
    required this.roomNumber,
    required this.building,
    required this.prevWater,
    required this.prevElec,
    required this.waterCtrl,
    required this.elecCtrl,
    required this.initWater,
    required this.initElec,
    required this.hasTenant,
  });

  String get label => "ห้อง $building-$roomNumber";

  void dispose() {
    waterCtrl.dispose();
    elecCtrl.dispose();
  }
}