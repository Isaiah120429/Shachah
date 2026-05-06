import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'auth_screen.dart';
import 'band_library_screen.dart';
import 'profile_screen.dart';

// Color Palette
const Color smokyBlack = Color(0xFF110703);
const Color licorice = Color(0xFF230F08);
const Color blackBean = Color(0xFF34170D);
const Color kobicha = Color(0xFF6E3C19);
const Color chamoisee = Color(0xFFA7795E);
const Color highlightSuccess = Color(0xFF558B2F);
const Color highlightWarning = Color(0xFFD4A017);
const Color highlightError = Color(0xFFC62828);
const Color highlightInfo = Color(0xFF5D6D7E);

// Music Positions
const List<String> musicPositions = [
  'Guitar 1 🎸',
  'Guitar 2 🎸',
  'Bass 🎸',
  'Rhythm 🥁',
  'Drums 🥁',
  'Keyboard 🎹',
];

class AssignedMusician {
  final String musicianId;
  final String musicianName;
  final String instrument;
  final bool confirmed;
  AssignedMusician({
    required this.musicianId,
    required this.musicianName,
    required this.instrument,
    this.confirmed = false,
  });
  factory AssignedMusician.fromMap(Map<String, dynamic> map) {
    return AssignedMusician(
      musicianId: map['musicianId'] ?? '',
      musicianName: map['musicianName'] ?? '',
      instrument: map['instrument'] ?? '',
      confirmed: map['confirmed'] ?? false,
    );
  }
}

class ScheduleDisplayForMember {
  String id, name, email, date, dateKey, time, notepadContent, notes, userId;
  bool hasLineUp;
  String status;
  Timestamp? sendDate;
  ScheduleDisplayForMember({
    required this.id,
    required this.name,
    required this.email,
    required this.date,
    required this.dateKey,
    required this.time,
    required this.hasLineUp,
    required this.notepadContent,
    required this.notes,
    required this.userId,
    required this.status,
    this.sendDate,
  });
}

class AnnouncementForUser {
  final String id, title, content, createdBy;
  final DateTime createdAt;
  AnnouncementForUser({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.createdBy,
  });
}

class MusicianDashboardScreen extends StatefulWidget {
  const MusicianDashboardScreen({super.key});

  @override
  State<MusicianDashboardScreen> createState() => _MusicianDashboardScreenState();
}

class _MusicianDashboardScreenState extends State<MusicianDashboardScreen> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Month navigation
  DateTime _currentDate = DateTime.now();
  late String _currentMonth;
  late int _currentYear;
  late List<Map<String, dynamic>> _sundaysInCurrentMonth;
  List<ScheduleDisplayForMember> _allSchedules = [];

  List<AnnouncementForUser> _announcements = [];
  String _currentUserName = 'Musician';
  final String _currentUserEmail = UserSession.userEmail ?? 'musician@example.com';
  final String _currentUserId = UserSession.userId ?? '';
  bool _isLoading = true;
  String? _profileImageUrl;

  DateTime? _lastSeenTime;
  int _unreadCount = 0;

  Map<String, AssignedMusician>? _monthlyBandAssignment;
  int _monthlyAssignedCount = 0;

  late StreamSubscription<QuerySnapshot> _assignmentsSubscription;
  late StreamSubscription<QuerySnapshot> _announcementsSubscription;
  late StreamSubscription<DocumentSnapshot> _monthlyAssignmentSubscription;

  @override
  void initState() {
    super.initState();
    _initMonth();
    _loadLastSeenTime();
    _loadInitialData();
    _setupOneSignal();
  }

  // ✅ ==================== ONESIGNAL SETUP ====================
  void _setupOneSignal() {
    // Listen to notification clicks (when user taps on notification)
    OneSignal.Notifications.addClickListener((event) {
      print("📱 Notification clicked: ${event.notification.title}");
      
      // Extract custom data from the notification (if any)
      final additionalData = event.notification.additionalData;
      final type = additionalData?['type'];
      
      if (type == 'assignment') {
        print("🎵 Navigate to Schedule tab");
        setState(() => _selectedIndex = 0); // Schedule tab
      } else if (type == 'announcement') {
        print("📢 Navigate to Updates tab");
        setState(() => _selectedIndex = 1); // Updates tab
      } else {
        print("🔔 Generic notification tapped");
      }
    });

    print("✅ OneSignal listener setup complete for MusicianDashboardScreen");
  }

  void _initMonth() {
    _currentYear = _currentDate.year;
    _currentMonth = DateFormat('MMMM').format(_currentDate);
    _sundaysInCurrentMonth = _getSundaysOfMonth(_currentYear, _currentDate.month);
  }

  void _previousMonth() {
    setState(() {
      DateTime prev = DateTime(_currentYear, _currentDate.month - 1);
      _currentDate = prev;
      _currentYear = prev.year;
      _currentMonth = DateFormat('MMMM').format(prev);
      _sundaysInCurrentMonth = _getSundaysOfMonth(_currentYear, prev.month);
      _monthlyAssignmentSubscription.cancel();
      _listenToMonthlyBandAssignment();
    });
  }

  void _nextMonth() {
    setState(() {
      DateTime next = DateTime(_currentYear, _currentDate.month + 1);
      _currentDate = next;
      _currentYear = next.year;
      _currentMonth = DateFormat('MMMM').format(next);
      _sundaysInCurrentMonth = _getSundaysOfMonth(_currentYear, next.month);
      _monthlyAssignmentSubscription.cancel();
      _listenToMonthlyBandAssignment();
    });
  }

  @override
  void dispose() {
    _assignmentsSubscription.cancel();
    _announcementsSubscription.cancel();
    _monthlyAssignmentSubscription.cancel();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    await _loadUserProfile();
    _listenToAssignmentsRealTime();
    _listenToAnnouncementsRealTime();
    _listenToMonthlyBandAssignment();
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  // Pull-to-refresh: reload profile and monthly band assignments
  Future<void> _refreshData() async {
    await _loadUserProfile();
    await _monthlyAssignmentSubscription.cancel();
    _listenToMonthlyBandAssignment();
    setState(() {});
  }

  // ==================== LAST SEEN TIME FOR ANNOUNCEMENTS ====================
  Future<void> _loadLastSeenTime() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('musicianLastSeenAnnouncement');
    if (saved != null) _lastSeenTime = DateTime.parse(saved);
  }

  Future<void> _saveCurrentViewTime() async {
    _lastSeenTime = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('musicianLastSeenAnnouncement', _lastSeenTime!.toIso8601String());
    _updateUnreadCount();
  }

  void _updateUnreadCount() {
    if (_lastSeenTime == null) {
      _unreadCount = _announcements.length;
    } else {
      _unreadCount = _announcements.where((a) => a.createdAt.isAfter(_lastSeenTime!)).length;
    }
    setState(() {});
  }

  void _showNewAnnouncementPopup(AnnouncementForUser a) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: licorice,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: highlightSuccess.withOpacity(0.2), shape: BoxShape.circle),
                child: const Icon(Icons.notifications_active, color: highlightSuccess, size: 32),
              ),
              const SizedBox(height: 16),
              const Text('New Announcement', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(a.title, style: TextStyle(color: chamoisee, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: smokyBlack.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
                child: Text(a.content.length > 100 ? '${a.content.substring(0, 100)}...' : a.content, style: const TextStyle(color: Colors.white70, fontSize: 13)),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(side: BorderSide(color: kobicha)),
                      child: const Text('Later'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() => _selectedIndex = 1);
                        _saveCurrentViewTime();
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: highlightSuccess),
                      child: const Text('View Now'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _listenToMonthlyBandAssignment() {
    final monthKey = DateFormat('yyyy-MM').format(_currentDate);
    _monthlyAssignmentSubscription = FirebaseFirestore.instance
        .collection('monthly_music_assignments')
        .doc(monthKey)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists) {
        final data = snapshot.data() as Map<String, dynamic>;
        final musiciansMap = data['musicians'] as Map<String, dynamic>? ?? {};
        final assignments = <String, AssignedMusician>{};
        int count = 0;
        for (var entry in musiciansMap.entries) {
          final musician = AssignedMusician.fromMap(entry.value as Map<String, dynamic>);
          assignments[entry.key] = musician;
          if (musician.musicianId.isNotEmpty) count++;
        }
        setState(() {
          _monthlyBandAssignment = assignments;
          _monthlyAssignedCount = count;
        });
      } else {
        setState(() {
          _monthlyBandAssignment = null;
          _monthlyAssignedCount = 0;
        });
      }
    });
  }

  List<Map<String, dynamic>> _getSundaysOfMonth(int year, int month) {
    List<Map<String, dynamic>> sundays = [];
    DateTime firstDay = DateTime(year, month, 1);
    int daysToAdd = (DateTime.sunday - firstDay.weekday) % 7;
    DateTime firstSunday = firstDay.add(Duration(days: daysToAdd));
    DateTime current = firstSunday;
    while (current.month == month) {
      sundays.add({
        'date': DateFormat('MMMM d, yyyy').format(current),
        'dateKey': DateFormat('yyyy-MM-dd').format(current),
        'time': '9:00 AM',
        'dayOfMonth': current.day,
      });
      current = current.add(const Duration(days: 7));
    }
    return sundays;
  }

  List<ScheduleDisplayForMember> get _currentMonthSchedules {
    if (_sundaysInCurrentMonth.isEmpty) return [];
    final Map<String, ScheduleDisplayForMember> map = {};
    for (var s in _allSchedules) {
      map[s.dateKey] = s;
    }
    return _sundaysInCurrentMonth.map((s) {
      final key = s['dateKey'];
      return map.containsKey(key)
          ? map[key]!
          : ScheduleDisplayForMember(
              id: key,
              name: 'Not Assigned',
              email: '',
              date: s['date'],
              dateKey: key,
              time: s['time'],
              hasLineUp: false,
              notepadContent: '',
              notes: '',
              userId: '',
              status: 'empty',
              sendDate: null,
            );
    }).toList();
  }

  void _autoSealExpiredAssignments(List<ScheduleDisplayForMember> schedules) {
    for (var s in schedules) {
      if (s.status == 'proposed' && s.sendDate != null) {
        final daysSinceSend = DateTime.now().difference(s.sendDate!.toDate()).inDays;
        if (daysSinceSend >= 5) {
          FirebaseFirestore.instance.collection('assignments').doc(s.id).update({
            'status': 'sealed',
          });
        }
      }
    }
  }

  void _listenToAssignmentsRealTime() {
    _assignmentsSubscription = FirebaseFirestore.instance
        .collection('assignments')
        .snapshots()
        .listen((snapshot) {
      List<ScheduleDisplayForMember> list = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        String status = data['status'] ?? 'empty';
        Timestamp? sendDate = data['sendDate'] as Timestamp?;
        // Auto‑seal check (client side)
        if (status == 'proposed' && sendDate != null) {
          final daysSinceSend = DateTime.now().difference(sendDate.toDate()).inDays;
          if (daysSinceSend >= 5) {
            FirebaseFirestore.instance.collection('assignments').doc(doc.id).update({'status': 'sealed'});
            status = 'sealed';
          }
        }
        list.add(ScheduleDisplayForMember(
          id: doc.id,
          name: data['assignedMemberName'] ?? 'Unknown',
          email: data['assignedMemberEmail'] ?? '',
          date: data['date'] ?? '',
          dateKey: data['dateKey'] ?? doc.id,
          time: data['time'] ?? '9:00 AM',
          hasLineUp: data['hasLineUp'] ?? false,
          notepadContent: data['notepadContent'] ?? '',
          notes: data['notes'] ?? '',
          userId: data['assignedMemberId'] ?? '',
          status: status,
          sendDate: sendDate,
        ));
      }
      setState(() => _allSchedules = list);
      _autoSealExpiredAssignments(list);
    });
  }

  void _listenToAnnouncementsRealTime() {
    _announcementsSubscription = FirebaseFirestore.instance
        .collection('announcements')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      final List<AnnouncementForUser> updated = snapshot.docs.map((doc) {
        final data = doc.data();
        return AnnouncementForUser(
          id: doc.id,
          title: data['title'] ?? '',
          content: data['content'] ?? '',
          createdAt: (data['createdAt'] as Timestamp).toDate(),
          createdBy: data['createdBy'] ?? '',
        );
      }).toList();
      final fresh = updated.where((a) => !_announcements.any((old) => old.id == a.id)).toList();
      setState(() {
        _announcements = updated;
        _updateUnreadCount();
      });
      if (mounted && fresh.isNotEmpty && _selectedIndex != 1) {
        _showNewAnnouncementPopup(fresh.first);
      }
    });
  }

  Future<void> _loadUserProfile() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(_currentUserId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _profileImageUrl = data['profileImageUrl'];
          _currentUserName = data['name'] ?? 'Musician';
        });
      }
    } catch (e) {}
  }

  // Build clickable text with URL detection
  Widget _buildClickableNotepadTextView(BuildContext context, String text) {
    final lines = text.split('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines.map((line) {
        final urlRegex = RegExp(r'(https?:\/\/[^\s]+)');
        final hasUrl = urlRegex.hasMatch(line);
        if (hasUrl) {
          final parts = line.split(RegExp(r'(https?:\/\/[^\s]+)'));
          final urls = urlRegex.allMatches(line).map((m) => m.group(0)).whereType<String>().toList();
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ...parts.asMap().entries.map((entry) {
                  final part = entry.value;
                  if (part.isNotEmpty) {
                    return Text(part, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4));
                  }
                  return const SizedBox.shrink();
                }),
                ...urls.map((urlString) {
                  return GestureDetector(
                    onTap: () async {
                      final Uri uri = Uri.parse(urlString);
                      try {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Cannot open link: $urlString'), backgroundColor: highlightError),
                          );
                        }
                      }
                    },
                    child: Text(
                      urlString,
                      style: const TextStyle(
                        color: Colors.blue,
                        fontSize: 12,
                        decoration: TextDecoration.underline,
                        height: 1.4,
                      ),
                    ),
                  );
                }),
              ],
            ),
          );
        } else if (line.trim().isEmpty) {
          return const SizedBox(height: 6);
        } else {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(line, style: const TextStyle(color: Colors.white, fontSize: 12, height: 1.4)),
          );
        }
      }).toList(),
    );
  }

  void _showLineupDialog(ScheduleDisplayForMember schedule) {
    String statusText;
    Color statusColor;
    if (schedule.status == 'empty') {
      statusText = 'Empty';
      statusColor = Colors.grey;
    } else if (schedule.status == 'proposed') {
      if (schedule.sendDate != null) {
        final daysLeft = 5 - DateTime.now().difference(schedule.sendDate!.toDate()).inDays;
        statusText = 'Proposed ($daysLeft days left)';
        statusColor = highlightWarning;
      } else {
        statusText = 'Proposed (draft)';
        statusColor = highlightInfo;
      }
    } else {
      statusText = 'Sealed';
      statusColor = highlightSuccess;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [smokyBlack, blackBean, kobicha]),
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: chamoisee, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: kobicha.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.visibility, color: chamoisee, size: 24)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(schedule.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(schedule.date, style: TextStyle(color: chamoisee, fontSize: 14)),
                        Text(schedule.time, style: TextStyle(color: chamoisee.withOpacity(0.7), fontSize: 12)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: statusColor.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(schedule.status == 'empty' ? Icons.hourglass_empty : (schedule.status == 'sealed' ? Icons.lock : Icons.edit), size: 12, color: statusColor),
                        const SizedBox(width: 4),
                        Text(statusText, style: TextStyle(color: statusColor, fontSize: 11)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: Colors.white24),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Song Line Up', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: smokyBlack.withOpacity(0.5), borderRadius: BorderRadius.circular(12), border: Border.all(color: kobicha)),
                      child: schedule.notepadContent.isEmpty
                          ? Center(child: Text('No lineup yet.', style: TextStyle(color: chamoisee, fontSize: 12)))
                          : _buildClickableNotepadTextView(context, schedule.notepadContent),
                    ),
                    if (schedule.notes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text('Notes', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: smokyBlack.withOpacity(0.5), borderRadius: BorderRadius.circular(12), border: Border.all(color: kobicha)),
                        child: _buildClickableNotepadTextView(context, schedule.notes),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: kobicha, minimumSize: const Size(double.infinity, 48)),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getAppBarTitle() {
    switch (_selectedIndex) {
      case 0: return 'Schedule';
      case 1: return 'Updates';
      case 2: return 'Band Library';
      case 3: return 'Profile';
      case 4: return 'Musicians';
      default: return 'Musician Hub';
    }
  }

  // ==================== MONTH NAVIGATOR ====================
  Widget _buildMonthNavigator() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: licorice.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kobicha, width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.chevron_left, color: chamoisee),
            onPressed: _previousMonth,
            constraints: const BoxConstraints(),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_currentMonth, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              Text(_currentYear.toString(), style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ],
          ),
          IconButton(
            icon: Icon(Icons.chevron_right, color: chamoisee),
            onPressed: _nextMonth,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _buildMusicianSlots() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(color: licorice.withOpacity(0.6), borderRadius: BorderRadius.circular(16), border: Border.all(color: kobicha.withOpacity(0.5))),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [Icon(Icons.music_note, color: chamoisee, size: 16), const SizedBox(width: 6),
                const Text('Band Members for this Month', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500))]),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: _monthlyAssignedCount > 0 ? highlightSuccess.withOpacity(0.2) : highlightWarning.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                child: Text('$_monthlyAssignedCount/${musicPositions.length} assigned', style: TextStyle(color: _monthlyAssignedCount > 0 ? highlightSuccess : highlightWarning, fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: musicPositions.map((position) {
              String assignedName = 'Not Assigned';
              Color textColor = Colors.grey;
              if (_monthlyBandAssignment != null && _monthlyBandAssignment!.containsKey(position)) {
                final musician = _monthlyBandAssignment![position]!;
                if (musician.musicianId.isNotEmpty) {
                  assignedName = musician.musicianName;
                  textColor = highlightSuccess;
                }
              }
              return Expanded(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  decoration: BoxDecoration(color: smokyBlack.withOpacity(0.5), borderRadius: BorderRadius.circular(10), border: Border.all(color: kobicha.withOpacity(0.3))),
                  child: Column(
                    children: [
                      Text(position, style: TextStyle(color: chamoisee, fontSize: 9), textAlign: TextAlign.center),
                      const SizedBox(height: 4),
                      Text(assignedName, style: TextStyle(color: textColor, fontSize: 9), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  // ==================== SCHEDULE TAB (already has pull-to-refresh) ====================
  Widget _buildScheduleContent() {
    final schedules = _currentMonthSchedules;
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: chamoisee,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 16),
            _buildMusicianSlots(),
            const SizedBox(height: 16),
            _buildMonthNavigator(),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Sundays in $_currentMonth $_currentYear', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                Text('Tap card to view lineup', style: TextStyle(color: chamoisee, fontSize: 10)),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: schedules.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.calendar_today, size: 60, color: chamoisee),
                      const SizedBox(height: 12),
                      Text('No Sundays in $_currentMonth $_currentYear', style: TextStyle(color: chamoisee, fontSize: 14)),
                    ]))
                  : ListView.builder(
                      itemCount: schedules.length,
                      itemBuilder: (context, index) {
                        final schedule = schedules[index];
                        return _buildScheduleCard(schedule);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleCard(ScheduleDisplayForMember schedule) {
    final day = DateTime.tryParse(schedule.dateKey)?.day ?? 0;
    // Status badge
    String statusText;
    Color statusColor;
    if (schedule.status == 'empty') {
      statusText = 'Empty';
      statusColor = Colors.grey;
    } else if (schedule.status == 'proposed') {
      if (schedule.sendDate != null) {
        final daysLeft = 5 - DateTime.now().difference(schedule.sendDate!.toDate()).inDays;
        statusText = 'Proposed ($daysLeft days left)';
        statusColor = highlightWarning;
      } else {
        statusText = 'Proposed (draft)';
        statusColor = highlightInfo;
      }
    } else {
      statusText = 'Sealed';
      statusColor = highlightSuccess;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: licorice.withOpacity(0.6),
      child: InkWell(
        onTap: () => _showLineupDialog(schedule),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(color: licorice.withOpacity(0.8), borderRadius: BorderRadius.circular(24)),
                child: Center(child: Text(day.toString(), style: const TextStyle(color: Colors.white70, fontSize: 18, fontWeight: FontWeight.bold))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(schedule.name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(schedule.date, style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: statusColor.withOpacity(0.5), width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(schedule.status == 'empty' ? Icons.hourglass_empty : (schedule.status == 'sealed' ? Icons.lock : Icons.edit), size: 10, color: statusColor),
                          const SizedBox(width: 4),
                          Text(statusText, style: TextStyle(color: statusColor, fontSize: 9)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: chamoisee, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== UPDATES TAB (already has pull-to-refresh) ====================
  Widget _buildUpdatesContent() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _saveCurrentViewTime());
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: chamoisee,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(children: [Icon(Icons.notifications, color: chamoisee, size: 24), SizedBox(width: 8),
                  Text('Announcements & Updates', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))]),
                if (_unreadCount > 0) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: highlightError, borderRadius: BorderRadius.circular(20)),
                  child: Text('$_unreadCount new', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _announcements.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.notifications_none, size: 64, color: chamoisee.withOpacity(0.5)),
                      const SizedBox(height: 16),
                      Text('No announcements yet', style: TextStyle(color: chamoisee, fontSize: 16)),
                    ]))
                  : ListView.builder(
                      itemCount: _announcements.length,
                      itemBuilder: (context, index) {
                        final a = _announcements[index];
                        final isNew = _lastSeenTime == null || a.createdAt.isAfter(_lastSeenTime!);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(color: licorice.withOpacity(0.6), borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: isNew ? highlightSuccess : kobicha, width: isNew ? 2 : 1)),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(color: kobicha.withOpacity(0.3), borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14))),
                                child: Row(
                                  children: [
                                    Icon(Icons.announcement, color: isNew ? highlightSuccess : chamoisee, size: 20),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(children: [
                                            Expanded(child: Text(a.title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold))),
                                            if (isNew) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: highlightSuccess.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                                              child: Text('NEW', style: TextStyle(color: highlightSuccess, fontSize: 9, fontWeight: FontWeight.bold))),
                                          ]),
                                          const SizedBox(height: 4),
                                          Text('Posted by ${a.createdBy} • ${DateFormat('MMM d, yyyy').format(a.createdAt)}', style: TextStyle(color: chamoisee.withOpacity(0.7), fontSize: 10)),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(color: smokyBlack.withOpacity(0.3), borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14))),
                                child: Row(
                                  children: [
                                    Icon(Icons.edit_note, color: chamoisee, size: 14),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(a.content, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4))),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsContent() => const ProfileScreen();

  Widget _buildHeader() {
    String initials = _currentUserName.isNotEmpty ? _currentUserName[0].toUpperCase() : 'M';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: licorice.withOpacity(0.4), borderRadius: BorderRadius.circular(14), border: Border.all(color: kobicha.withOpacity(0.3))),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [kobicha, chamoisee])),
            child: ClipOval(
              child: _profileImageUrl != null && _profileImageUrl!.isNotEmpty
                  ? Image.network(_profileImageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))))
                  : Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_currentUserName, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: kobicha.withOpacity(0.3), borderRadius: BorderRadius.circular(10)),
                child: const Text('Musician', style: TextStyle(color: chamoisee, fontSize: 9))),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== MUSICIANS TAB (with pull-to-refresh) ====================
  Widget _buildMusiciansTab() {
    final TextEditingController nameController = TextEditingController();
    bool isAdding = false;

    Future<bool> addMusician(String name) async {
      try {
        await FirebaseFirestore.instance.collection('musicians').add({
          'name': name.trim(),
          'email': '',
          'phone': '',
          'instruments': [],
          'isActive': true,
          'createdAt': FieldValue.serverTimestamp(),
          'addedBy': FirebaseAuth.instance.currentUser?.uid ?? 'musician_account',
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Musician added successfully!'), backgroundColor: highlightSuccess),
          );
        }
        return true;
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: highlightError),
          );
        }
        return false;
      }
    }

    void showAddDialog() {
      nameController.clear();
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: licorice,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Text('Add New Musician', style: TextStyle(color: chamoisee)),
              content: TextFormField(
                controller: nameController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Full Name',
                  labelStyle: TextStyle(color: chamoisee),
                  hintText: 'e.g., John Smith',
                  hintStyle: TextStyle(color: Colors.grey),
                  enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: kobicha)),
                  focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: chamoisee, width: 2)),
                ),
                autofocus: true,
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
                ElevatedButton(
                  onPressed: isAdding
                      ? null
                      : () async {
                          if (nameController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(dialogContext).showSnackBar(
                              const SnackBar(content: Text('Please enter a name'), backgroundColor: highlightError),
                            );
                            return;
                          }
                          setDialogState(() => isAdding = true);
                          bool success = await addMusician(nameController.text);
                          setDialogState(() => isAdding = false);
                          if (success && mounted) Navigator.pop(dialogContext);
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: highlightSuccess),
                  child: isAdding
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Add'),
                ),
              ],
            );
          },
        ),
      );
    }

    Future<void> deleteMusician(String id, String name) async {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: licorice,
          title: const Text('Delete Musician', style: TextStyle(color: Colors.white)),
          content: Text('Are you sure you want to delete "$name"?', style: TextStyle(color: chamoisee)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: highlightError),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      try {
        await FirebaseFirestore.instance.collection('musicians').doc(id).delete();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Musician "$name" deleted'), backgroundColor: highlightSuccess),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting: $e'), backgroundColor: highlightError),
          );
        }
      }
    }

    return RefreshIndicator(
      onRefresh: _refreshData,
      color: chamoisee,
      child: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _buildHeader(),
                const SizedBox(height: 20),
                const Row(
                  children: [
                    Icon(Icons.person_add, color: chamoisee, size: 24),
                    SizedBox(width: 8),
                    Text('Musicians List', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance.collection('musicians').orderBy('createdAt', descending: true).snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}', style: TextStyle(color: highlightError)));
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator(color: chamoisee));
                      }
                      final docs = snapshot.data!.docs;
                      if (docs.isEmpty) {
                        return Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.person_off, size: 64, color: chamoisee.withOpacity(0.5)),
                              const SizedBox(height: 16),
                              Text('No musicians yet.', style: TextStyle(color: chamoisee, fontSize: 16)),
                              const SizedBox(height: 8),
                              Text('Tap + button to add one.', style: TextStyle(color: chamoisee, fontSize: 12)),
                            ],
                          ),
                        );
                      }
                      return ListView.builder(
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final data = doc.data() as Map<String, dynamic>;
                          final name = data['name'] ?? 'Unknown';
                          final isActive = data['isActive'] ?? true;
                          final instruments = List<String>.from(data['instruments'] ?? []);
                          final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: licorice.withOpacity(0.6),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: kobicha),
                            ),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: kobicha,
                                child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
                              ),
                              title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (instruments.isNotEmpty)
                                    Text('🎸 ${instruments.take(2).join(', ')}${instruments.length > 2 ? '...' : ''}',
                                        style: TextStyle(color: chamoisee, fontSize: 12)),
                                  if (createdAt != null)
                                    Text('Added: ${DateFormat('MMM d, yyyy').format(createdAt)}',
                                        style: TextStyle(color: chamoisee.withOpacity(0.7), fontSize: 10)),
                                ],
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isActive ? highlightSuccess.withOpacity(0.2) : highlightError.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(isActive ? 'Active' : 'Inactive',
                                        style: TextStyle(color: isActive ? highlightSuccess : highlightError, fontSize: 10)),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: highlightError),
                                    onPressed: () => deleteMusician(doc.id, name),
                                    tooltip: 'Delete musician',
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: showAddDialog,
            backgroundColor: highlightSuccess,
            child: const Icon(Icons.add, color: Colors.white),
          ),
        ),
      ),
    );
  }

  // ==================== DRAWER ====================
  Widget _buildDrawer() {
    String drawerInitials = _currentUserName.isNotEmpty ? _currentUserName[0].toUpperCase() : 'M';
    return Drawer(
      backgroundColor: licorice,
      child: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [smokyBlack, blackBean, licorice])),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 50, 20, 24),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: kobicha.withOpacity(0.5)))),
              child: Row(
                children: [
                  Container(
                    width: 60, height: 60,
                    decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [kobicha, chamoisee]), border: Border.all(color: chamoisee, width: 2)),
                    child: ClipOval(
                      child: _profileImageUrl != null && _profileImageUrl!.isNotEmpty
                          ? Image.network(_profileImageUrl!, fit: BoxFit.cover)
                          : Center(child: Text(drawerInitials, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold))),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_currentUserName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: kobicha.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
                          child: const Text('Musician', style: TextStyle(color: chamoisee, fontSize: 11))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildDrawerItem(icon: Icons.calendar_today, title: 'Schedule', index: 0, isSelected: _selectedIndex == 0),
            _buildDrawerItem(icon: Icons.notifications, title: 'Updates', index: 1, isSelected: _selectedIndex == 1,
                badge: _unreadCount > 0 ? '$_unreadCount' : null),
            _buildDrawerItem(icon: Icons.library_music, title: 'Band Library', index: 2, isSelected: _selectedIndex == 2),
            _buildDrawerItem(icon: Icons.settings, title: 'Profile', index: 3, isSelected: _selectedIndex == 3),
            _buildDrawerItem(icon: Icons.person_add, title: 'Musicians', index: 4, isSelected: _selectedIndex == 4),
            const Spacer(),
            Container(
              margin: const EdgeInsets.all(16),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: highlightError.withOpacity(0.5))),
              child: ListTile(
                leading: Icon(Icons.logout, color: highlightError),
                title: Text('Sign Out', style: TextStyle(color: highlightError, fontWeight: FontWeight.w600)),
                onTap: () async {
                  await FirebaseAuth.instance.signOut();
                  UserSession.isLoggedIn = false;
                  UserSession.userId = null;
                  UserSession.userName = null;
                  UserSession.userEmail = null;
                  UserSession.userRole = null;
                  if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AuthScreen()));
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({
    required IconData icon,
    required String title,
    required int index,
    required bool isSelected,
    String? badge,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: isSelected ? kobicha.withOpacity(0.3) : Colors.transparent,
        border: isSelected ? Border.all(color: chamoisee.withOpacity(0.5)) : null,
      ),
      child: ListTile(
        leading: Icon(icon, color: isSelected ? chamoisee : Colors.grey),
        title: Text(title, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
        trailing: badge != null
            ? Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: highlightError, borderRadius: BorderRadius.circular(20)),
                child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)))
            : null,
        onTap: () {
          setState(() => _selectedIndex = index);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        decoration: const BoxDecoration(image: DecorationImage(image: AssetImage('assets/music.png'), fit: BoxFit.cover)),
        child: const Center(child: CircularProgressIndicator(color: chamoisee)),
      );
    }
    Widget body;
    switch (_selectedIndex) {
      case 0: body = _buildScheduleContent(); break;
      case 1: body = _buildUpdatesContent(); break;
      case 2: body = const BandLibraryScreen(); break;
      case 3: body = _buildSettingsContent(); break;
      case 4: body = _buildMusiciansTab(); break;
      default: body = _buildScheduleContent();
    }
    return Container(
      decoration: const BoxDecoration(image: DecorationImage(image: AssetImage('assets/music.png'), fit: BoxFit.cover)),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_getAppBarTitle()),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: chamoisee,
          leading: Builder(builder: (context) => IconButton(icon: const Icon(Icons.menu, color: chamoisee), onPressed: () => Scaffold.of(context).openDrawer())),
        ),
        drawer: _buildDrawer(),
        body: body,
      ),
    );
  }
}