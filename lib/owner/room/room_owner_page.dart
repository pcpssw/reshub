import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../config.dart';
import 'room_model.dart';
import 'room_detail_page.dart';

class AdminRoomPage extends StatefulWidget {
  const AdminRoomPage({super.key});

  @override
  State<AdminRoomPage> createState() => _AdminRoomPageState();
}

class _AdminRoomPageState extends State<AdminRoomPage> {
  // --- สีและขนาดตัวอักษร (ResHub Theme) ---
  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cAccent = Color(0xFFDCD2C1);
  static const Color cIcon = Color(0xFF523D2D);
  static const Color cTextMain = Color(0xFF523D2D);

  static const double fHeader = 15.0;
  static const double fBody = 14.0;
  static const double fDetail = 13.0;

  // --- ข้อมูลสถานะ ---
  int dormId = 0;
  List<Room> rooms = [];
  bool loading = true;

  RoomStatus? selectedStatus;
  RoomType? selectedType;

  final ScrollController _scrollController = ScrollController();
  bool _showBackToTop = false;

  @override
  void initState() {
    super.initState();
    _init();

    _scrollController.addListener(() {
      if (_scrollController.offset > 300 && !_showBackToTop) {
        setState(() => _showBackToTop = true);
      } else if (_scrollController.offset <= 300 && _showBackToTop) {
        setState(() => _showBackToTop = false);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutQuart,
    );
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    dormId = prefs.getInt("dorm_id") ?? prefs.getInt("selected_dorm_id") ?? 0;
    if (dormId > 0) {
      await fetchRooms(showLoading: true);
    } else if (mounted) {
      setState(() => loading = false);
    }
  }

  Future<void> fetchRooms({bool showLoading = true}) async {
    if (!mounted) return;
    if (showLoading) setState(() => loading = true);

    try {
      final res = await http.post(
        Uri.parse(AppConfig.url("rooms_api.php")),
        body: {
          "action": "list",
          "dorm_id": dormId.toString(),
        },
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(res.body);
      if (data["ok"] == true || data["success"] == true) {
        final List list = data["data"] ?? data["rooms"] ?? [];
        if (mounted) {
          setState(() {
            rooms = list
                .map((e) => Room.fromJson(Map<String, dynamic>.from(e)))
                .toList();
          });
        }
      }
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      if (mounted && showLoading) setState(() => loading = false);
    }
  }

  Map<String, Map<int, List<Room>>> get groupedRooms {
    final Map<String, Map<int, List<Room>>> groups = {};
    for (final room in filteredRooms) {
      groups.putIfAbsent(room.building, () => {});
      groups[room.building]!.putIfAbsent(room.floor, () => []);
      groups[room.building]![room.floor]!.add(room);
    }
    return groups;
  }

  List<Room> get filteredRooms {
    return rooms.where((room) {
      final statusOk = selectedStatus == null || room.status == selectedStatus;
      final typeOk = selectedType == null || room.type == selectedType;
      return statusOk && typeOk;
    }).toList();
  }

  Widget _buildFilterSection() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      child: Row(
        children: [
          Expanded(
            child: _dropClassic<RoomStatus?>(
              label: "สถานะ",
              val: selectedStatus,
              items: const [
                DropdownMenuItem(value: null, child: Text("ทั้งหมด")),
                DropdownMenuItem(value: RoomStatus.available, child: Text("ห้องว่าง")),
                DropdownMenuItem(value: RoomStatus.occupied, child: Text("ไม่ว่าง")),
                DropdownMenuItem(value: RoomStatus.maintenance, child: Text("ซ่อมแซม")),
              ],
              on: (v) => setState(() => selectedStatus = v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _dropClassic<RoomType?>(
              label: "ประเภท",
              val: selectedType,
              items: const [
                DropdownMenuItem(value: null, child: Text("ทั้งหมด")),
                DropdownMenuItem(value: RoomType.air, child: Text("แอร์")),
                DropdownMenuItem(value: RoomType.fan, child: Text("พัดลม")),
              ],
              on: (v) => setState(() => selectedType = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dropClassic<T>({
    required String label,
    required T val,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> on,
  }) {
    return SizedBox(
      height: 46,
      child: DropdownButtonFormField<T>(
        value: val,
        selectedItemBuilder: (context) => items.map((i) {
          return Text(
            (i.child as Text).data ?? "",
            style: const TextStyle(fontSize: fDetail, color: cTextMain, overflow: TextOverflow.ellipsis),
          );
        }).toList(),
        items: items.map((i) {
          return DropdownMenuItem<T>(
            value: i.value,
            child: Text((i.child as Text).data ?? "", style: const TextStyle(fontSize: fDetail)),
          );
        }).toList(),
        onChanged: on,
        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: cIcon, size: 18),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: cIcon, fontSize: 12),
          filled: true,
          fillColor: cAccent.withOpacity(0.25),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
    );
  }

  Widget _roomListWithGroupHeaders() {
    if (filteredRooms.isEmpty && !loading) {
      return const Center(
        child: Text("ไม่พบข้อมูลห้องพัก", style: TextStyle(color: cTextMain, fontSize: fBody)),
      );
    }

    final groups = groupedRooms;
    final buildings = groups.keys.toList()..sort();

    return RefreshIndicator(
      onRefresh: () => fetchRooms(showLoading: false),
      color: cTextMain,
      backgroundColor: Colors.white,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
        itemCount: buildings.length,
        itemBuilder: (context, bIndex) {
          final bName = buildings[bIndex];
          final floors = groups[bName]!.keys.toList()..sort();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: floors.map((fNum) {
              final roomsInFloor = groups[bName]![fNum]!;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.business, size: 15, color: cIcon),
                        const SizedBox(width: 8),
                        Text(" $bName - ชั้น $fNum", 
                          style: const TextStyle(fontSize: fHeader, fontWeight: FontWeight.bold, color: cTextMain)
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Divider(color: cAccent.withOpacity(0.5), thickness: 1)),
                      ],
                    ),
                  ),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      childAspectRatio: 0.92,
                    ),
                    itemCount: roomsInFloor.length,
                    itemBuilder: (context, rIndex) => _roomCard(roomsInFloor[rIndex]),
                  ),
                  const SizedBox(height: 8),
                ],
              );
            }).toList(),
          );
        },
      ),
    );
  }

  Widget _roomCard(Room room) {
    Color sColor;
    String sLabel;
    IconData sIcon;
    Color bgColor;

    if (room.status == RoomStatus.available) {
      sColor = Colors.green.shade700;
      sLabel = "ว่าง";
      sIcon = room.type == RoomType.air ? Icons.ac_unit_rounded : Icons.air_rounded;
      bgColor = Colors.green.shade50;
    } else if (room.status == RoomStatus.occupied) {
      sColor = Colors.red.shade700;
      sLabel = "ไม่ว่าง";
      sIcon = room.type == RoomType.air ? Icons.ac_unit_rounded : Icons.air_rounded;
      bgColor = Colors.red.shade50;
    } else {
      sColor = cIcon;
      sLabel = "ซ่อม";
      sIcon = Icons.build_circle_rounded;
      bgColor = cAccent.withOpacity(0.2);
    }

    return InkWell(
      onTap: () async {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => RoomDetailPage(dormId: dormId, room: room)),
        );
        if (result == true) fetchRooms();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: Stack(
          children: [
            Column(
              children: [
                Expanded(
                  flex: 5,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(color: bgColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
                    child: Icon(sIcon, size: 22, color: sColor),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(room.roomNo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: cTextMain)),
                        const SizedBox(height: 4),
                        _statusBadgeSmall(sLabel, sColor),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            Positioned(
              top: 4,
              right: 4,
              child: Text(
                room.type == RoomType.air ? "แอร์" : "พัดลม",
                style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: room.type == RoomType.air ? Colors.blue : Colors.orange),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusBadgeSmall(String label, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
      child: Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canGoBack = Navigator.canPop(context);

    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        centerTitle: true,
        automaticallyImplyLeading: false,
        leading: canGoBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new, color: cTextMain, size: 18),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: const Text("จัดการห้องพัก", style: TextStyle(color: cTextMain, fontWeight: FontWeight.bold, fontSize: fHeader)),
        // --- เพิ่มปุ่มรีเฟรชตรงนี้ ---
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: cIcon),
            onPressed: () => fetchRooms(showLoading: true),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildFilterSection(),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator(color: cTextMain, strokeWidth: 2))
                : _roomListWithGroupHeaders(),
          ),
        ],
      ),
      floatingActionButton: _showBackToTop
          ? Padding(
              padding: const EdgeInsets.only(bottom: 80.0),
              child: FloatingActionButton(
                onPressed: _scrollToTop,
                backgroundColor: cIcon,
                elevation: 6,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.arrow_upward_rounded, 
                  color: Colors.white,
                  size: 28,
                ),
              ),
            )
          : null,
    );
  }
}