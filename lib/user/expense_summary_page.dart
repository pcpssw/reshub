import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

enum YearMetric { paid, water, electric }

// =============================================================
// 1. หน้าสรุปรายปี (ExpensePage)
// =============================================================
class ExpensePage extends StatefulWidget {
  const ExpensePage({super.key});

  @override
  State<ExpensePage> createState() => _ExpensePageState();
}

class _ExpensePageState extends State<ExpensePage> {
  static const Color _bgColor = Color(0xFFF4EFE6);
  static const Color _textColor = Color(0xFF523D2D);
  static const Color _mutedColor = Color(0xFF8D7456);
  static const Color _lineColor = Color(0xFFDCD2C1);
  static const Color _primaryColor = Color(0xFF523D2D);

  static const double fHeader = 15.0;
  static const double fBody = 14.0;
  static const double fDetail = 13.0;
  static const double fCaption = 11.0;

  int selectedYear = DateTime.now().year;
  int userId = 0;
  bool loading = true;
  String? loadError;
  YearMetric yearMetric = YearMetric.paid;

  final money = NumberFormat("#,##0", "en_US");

  final monthsText = const [
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
    "ธันวาคม"
  ];

  final monthsShort = const [
    "",
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

  double yearPaidSum = 0;
  List<Map<String, dynamic>> yearMonths = [];

  int _be(int ad) => ad + 543;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    userId =
        prefs.getInt("user_id") ??
        int.tryParse(prefs.getString("user_id") ?? "0") ??
        0;
    await fetchYearSummary();
  }

  Future<void> fetchYearSummary() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      loadError = null;
    });

    try {
      final uri = Uri.parse(AppConfig.url("finance_api.php")).replace(
        queryParameters: {
          "action": "summary_income",
          "user_id": userId.toString(),
          "year": selectedYear.toString(),
        },
      );

      final res = await http.get(uri).timeout(const Duration(seconds: 12));
      final data = jsonDecode(res.body);

      if (data["ok"] == true || data["success"] == true) {
        setState(() {
          yearPaidSum = (data["received_income"] as num?)?.toDouble() ?? 0;
          yearMonths = List<Map<String, dynamic>>.from(data["months"] ?? []);
        });
      } else {
        throw Exception(data["message"] ?? "โหลดข้อมูลไม่สำเร็จ");
      }
    } catch (e) {
      setState(() => loadError = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  double _yearValue(int m) {
    final row = yearMonths.firstWhere(
      (e) => (e["month"] ?? 0) == m,
      orElse: () => {},
    );
    if (yearMetric == YearMetric.paid) {
      return (row["received_income"] as num?)?.toDouble() ?? 0;
    }
    if (yearMetric == YearMetric.water) {
      return (row["water"] as num?)?.toDouble() ?? 0;
    }
    return (row["electric"] as num?)?.toDouble() ?? 0;
  }

  double _yearMonthsMax() {
    double m = 0;
    for (int i = 1; i <= 12; i++) {
      double v = _yearValue(i);
      if (v > m) m = v;
    }
    return m > 0 ? m : 1000;
  }

  int _yearBillCount(int m) {
    final row = yearMonths.firstWhere(
      (e) => (e["month"] ?? 0) == m,
      orElse: () => {},
    );
    return int.tryParse("${row["bill_count"] ?? 0}") ?? 0;
  }

  String _compact(double v) =>
      v.abs() >= 1000 ? "${(v / 1000).toStringAsFixed(1)}K" : v.toStringAsFixed(0);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        centerTitle: true,
        elevation: 0.5,
        backgroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(
            Icons.chevron_left_rounded,
            size: 28,
            color: _textColor,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          "สรุปค่าใช้จ่ายรายปี",
          style: TextStyle(
            color: _textColor,
            fontWeight: FontWeight.bold,
            fontSize: fHeader,
          ),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: _primaryColor))
          : loadError != null
              ? _buildErrorState()
              : _buildBody(),
    );
  }

  Widget _buildBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildYearSelector(),
        const SizedBox(height: 16),
        _buildHeroYearPaidCard(),
        const SizedBox(height: 20),
        Text(
          "สถิติรายปี ${_be(selectedYear)}",
          style: const TextStyle(
            fontSize: fBody,
            fontWeight: FontWeight.bold,
            color: _textColor,
          ),
        ),
        const SizedBox(height: 12),
        _buildYearMetricToggle(),
        const SizedBox(height: 16),
        _buildYearMetricChart(),
        const SizedBox(height: 20),
        for (int m = 1; m <= 12; m++) ...[
          _buildYearMonthRow(m),
          const SizedBox(height: 10),
        ],
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildYearSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _lineColor),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: selectedYear,
          isExpanded: true,
          dropdownColor: Colors.white,
          style: const TextStyle(
            color: _textColor,
            fontSize: fDetail,
            fontWeight: FontWeight.bold,
          ),
          items: [2024, 2025, 2026, 2027]
              .map(
                (y) => DropdownMenuItem(
                  value: y,
                  child: Text(" ${_be(y)}"),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) {
              setState(() => selectedYear = v);
              fetchYearSummary();
            }
          },
        ),
      ),
    );
  }

  Widget _buildHeroYearPaidCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _primaryColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: _primaryColor.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 5),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "ยอดชำระรวมทั้งปี",
            style: TextStyle(color: Colors.white70, fontSize: fDetail),
          ),
          const SizedBox(height: 8),
          Text(
            "${money.format(yearPaidSum)} ฿",
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYearMetricToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _lineColor.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _toggleItem("ยอดรวม", YearMetric.paid),
          _toggleItem("ค่าน้ำ", YearMetric.water),
          _toggleItem("ค่าไฟ", YearMetric.electric),
        ],
      ),
    );
  }

  Widget _toggleItem(String label, YearMetric m) {
    final active = yearMetric == m;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => yearMetric = m),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? _textColor : _mutedColor,
              fontWeight: FontWeight.bold,
              fontSize: fCaption,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildYearMetricChart() {
    Color mainColor = yearMetric == YearMetric.paid
        ? _primaryColor
        : yearMetric == YearMetric.water
            ? const Color(0xFF548CA8)
            : const Color(0xFFAD8B73);

    double maxVal = _yearMonthsMax();
    double chartMax = (maxVal * 1.2).ceilToDouble();
    if (chartMax <= 0) chartMax = 1000;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _lineColor),
      ),
      child: AspectRatio(
        aspectRatio: 1.7,
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            minY: 0,
            maxY: chartMax,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (value) {
                return FlLine(
                  color: _lineColor.withOpacity(0.45),
                  strokeWidth: 1,
                );
              },
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 38,
                  interval: chartMax / 4,
                  getTitlesWidget: (value, meta) {
                    return Text(
                      _compact(value),
                      style: const TextStyle(
                        fontSize: 10,
                        color: _mutedColor,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    final i = value.toInt();
                    if (i < 1 || i > 12) return const SizedBox();

                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        monthsShort[i],
                        style: const TextStyle(
                          fontSize: 10,
                          color: _mutedColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            barTouchData: BarTouchData(
              enabled: true,
              touchTooltipData: BarTouchTooltipData(
                getTooltipColor: (_) => _primaryColor,
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final month = group.x.toInt();
                  return BarTooltipItem(
                    "${monthsText[month - 1]}\n",
                    const TextStyle(
                      color: Colors.white70,
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                    children: [
                      TextSpan(
                        text: "${money.format(rod.toY)} ฿",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            barGroups: List.generate(12, (index) {
              final month = index + 1;
              final value = _yearValue(month);

              return BarChartGroupData(
                x: month,
                barsSpace: 0,
                barRods: [
                  BarChartRodData(
                    toY: value,
                    width: 18,
                    color: mainColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(6),
                      topRight: Radius.circular(6),
                    ),
                  ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildYearMonthRow(int m) {
    final val = _yearValue(m);
    final hasData = _yearBillCount(m) > 0;

    return InkWell(
      onTap: hasData
          ? () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => BillHistoryPage(
                    userId: userId,
                    year: selectedYear,
                    month: m,
                    monthName: monthsText[m - 1],
                  ),
                ),
              )
          : null,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: _lineColor),
        ),
        child: Row(
          children: [
            Text(
              monthsText[m - 1],
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: fDetail,
                color: hasData ? _textColor : _mutedColor.withOpacity(0.5),
              ),
            ),
            const Spacer(),
            Text(
              hasData ? "${money.format(val)} ฿" : "ยังไม่มีข้อมูล",
              style: TextStyle(
                fontWeight: hasData ? FontWeight.w900 : FontWeight.normal,
                fontSize: fDetail,
                color: hasData ? _textColor : Colors.grey.shade400,
              ),
            ),
            if (hasData) ...[
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: _mutedColor,
                size: 22,
              ),
            ]
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
          const SizedBox(height: 16),
          Text(
            "เกิดข้อผิดพลาด: $loadError",
            textAlign: TextAlign.center,
            style: const TextStyle(color: _textColor),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: fetchYearSummary,
            style: ElevatedButton.styleFrom(backgroundColor: _primaryColor),
            child: const Text("ลองใหม่", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// 2. หน้าประวัติบิลรายเดือน (BillHistoryPage)
// =============================================================
class BillHistoryPage extends StatefulWidget {
  final int userId, year, month;
  final String monthName;

  const BillHistoryPage({
    super.key,
    required this.userId,
    required this.year,
    required this.month,
    required this.monthName,
  });

  @override
  State<BillHistoryPage> createState() => _BillHistoryPageState();
}

class _BillHistoryPageState extends State<BillHistoryPage> {
  static const Color cBg = Color(0xFFF4EFE6);
  static const Color cText = Color(0xFF523D2D);
  static const Color cMuted = Color(0xFF8D7456);
  static const Color cLine = Color(0xFFDCD2C1);

  final money = NumberFormat("#,##0", "en_US");
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> items = [];

  @override
  void initState() {
    super.initState();
    _fetchBills();
  }

  Future<void> _fetchBills() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      final res = await http
          .get(
            Uri.parse(
              AppConfig.url(
                "finance_api.php?action=bill_list&user_id=${widget.userId}&year=${widget.year}&month=${widget.month}",
              ),
            ),
          )
          .timeout(const Duration(seconds: 12));
      final data = jsonDecode(res.body);

      if (data["ok"] == true) {
        setState(() => items = List<Map<String, dynamic>>.from(data["items"] ?? []));
      } else {
        error = data["message"]?.toString() ?? "โหลดข้อมูลไม่สำเร็จ";
      }
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Color _statusColor(String status) {
    final s = status.toLowerCase();
    if (s == "verified" || s == "paid") return const Color(0xFF4CAF50);
    if (s == "pending") return const Color(0xFFEF6C00);
    return const Color(0xFFD32F2F);
  }

  String _statusText(String status) {
    final s = status.toLowerCase();
    if (s == "verified" || s == "paid") return "ชำระแล้ว";
    if (s == "pending") return "รอตรวจสอบ";
    return "ยังไม่ชำระ";
  }

  double _d(dynamic v) => double.tryParse(v.toString()) ?? 0;
  int _i(dynamic v) => int.tryParse(v.toString()) ?? 0;

  String _formatSlipDate(dynamic raw) {
    final text = (raw ?? "").toString().trim();
    if (text.isEmpty) return "";
    try {
      final dt = DateTime.parse(text.replaceFirst(" ", "T")).toLocal();
      const months = [
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
      return "${dt.day} ${months[dt.month - 1]} ${dt.year + 543} • ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} น.";
    } catch (_) {
      return text;
    }
  }

  String _roomLabel(Map<String, dynamic> it) {
    final building =
        (it["building"] ?? it["building_name"] ?? it["zone"] ?? "")
            .toString()
            .trim();
    final roomNumber =
        (it["room_number"] ?? it["room_no"] ?? it["room"] ?? "")
            .toString()
            .trim();
    if (building.isNotEmpty && roomNumber.isNotEmpty) {
      return "ห้อง $building-$roomNumber";
    }
    if (roomNumber.isNotEmpty) return "ห้อง $roomNumber";
    if (building.isNotEmpty) return "ห้อง $building";
    return "ห้อง -";
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: cBg,
      appBar: AppBar(
        elevation: 0.5,
        backgroundColor: Colors.white,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded, size: 28, color: cText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          "บิลเดือน${widget.monthName} ${widget.year + 543}",
          style: const TextStyle(
            color: cText,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: cText))
          : error != null
              ? Center(child: Text(error!, style: const TextStyle(color: cText)))
              : items.isEmpty
                  ? const Center(
                      child: Text("ไม่มีบิลในเดือนนี้", style: TextStyle(color: cText)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      itemBuilder: (_, i) => _buildBillCard(items[i]),
                    ),
    );
  }

  Widget _buildBillCard(Map<String, dynamic> it) {
    final status = (it["status"] ?? "").toString();
    final slipUrl = (it["slip_url"] ?? "").toString().trim();
    final slipDateText = _formatSlipDate(it["pay_date"]);

    final double rent = _d(it["rent"]);
    final double water = _d(it["water"]);
    final double electric = _d(it["electric"]);
    final double totalFromApi = _d(it["total"]);
    final double finalTotal = totalFromApi > 0 ? totalFromApi : (rent + water + electric);

    final int waterUnit = _i(it["water_unit"]);
    final int electricUnit = _i(it["electric_unit"]);
    final double waterRate = _d(it["water_rate"]);
    final double electricRate = _d(it["electric_rate"]);

    final Color statusColor = _statusColor(status);
    final String statusText = _statusText(status);
    final bool isPaid =
        status.toLowerCase() == "verified" || status.toLowerCase() == "paid";

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: cLine),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: const BoxDecoration(
              color: cText,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Text(
                        "ห้อง ",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        _roomLabel(it).replaceFirst("ห้อง ", ""),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isPaid
                            ? Icons.check_circle_rounded
                            : Icons.access_time_filled_rounded,
                        size: 15,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        statusText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (slipUrl.isNotEmpty) ...[
                  InkWell(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SlipPreviewPage(imageUrl: slipUrl),
                      ),
                    ),
                    child: Container(
                      height: 190,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cLine),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          slipUrl,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => const Center(
                            child: Icon(
                              Icons.broken_image,
                              color: Colors.grey,
                              size: 42,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (slipDateText.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Center(
                      child: Text(
                        "วันที่ส่งสลิป: $slipDateText",
                        style: const TextStyle(
                          color: cMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
                _summaryTile(
                  title: "ค่าเช่า",
                  subtitle: "",
                  value: "${money.format(rent)} ฿",
                ),
                const SizedBox(height: 10),
                _summaryTile(
                  title: "ค่าน้ำ",
                  subtitle: "$waterUnit หน่วย × ${money.format(waterRate)} ฿/หน่วย",
                  value: "${money.format(water)} ฿",
                ),
                const SizedBox(height: 10),
                _summaryTile(
                  title: "ค่าไฟ",
                  subtitle:
                      "$electricUnit หน่วย × ${money.format(electricRate)} ฿/หน่วย",
                  value: "${money.format(electric)} ฿",
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCD2C1).withOpacity(0.35),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: cLine),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          "รวมสุทธิ",
                          style: TextStyle(
                            color: cText,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Text(
                        "${money.format(finalTotal)} ฿",
                        style: const TextStyle(
                          color: cText,
                          fontWeight: FontWeight.w900,
                          fontSize: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _summaryTile({
    required String title,
    required String subtitle,
    required String value,
  }) {
    final hasSubtitle = subtitle.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFDCD2C1).withOpacity(0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cLine),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: cText,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                if (hasSubtitle) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      "($subtitle)",
                      style: const TextStyle(color: cMuted, fontSize: 11),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: const TextStyle(
              color: cText,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================
// 3. หน้าพรีวิวสลิป (SlipPreviewPage)
// =============================================================
class SlipPreviewPage extends StatelessWidget {
  final String imageUrl;
  const SlipPreviewPage({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text("สลิป", style: TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: InteractiveViewer(
          child: Image.network(imageUrl),
        ),
      ),
    );
  }
}