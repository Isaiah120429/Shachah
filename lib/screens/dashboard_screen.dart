import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_screen.dart';
import 'profile_screen.dart';
import 'band_library_screen.dart';
import 'notification_service.dart';   // ✅ Push notification service

// Professional Black/White/Smoke Palette
const Color primaryBlack = Color(0xFF000000);
const Color primaryWhite = Color(0xFFFFFFFF);
const Color smokeGrey = Color(0xFFF5F5F5);
const Color darkSmoke = Color(0xFF2C2C2C);
const Color mediumGrey = Color(0xFF757575);
const Color lightGrey = Color(0xFFBDBDBD);
const Color almostBlack = Color(0xFF1E1E1E);

// Functional highlights – toned to fit the monochrome theme
const Color highlightSuccess = Color(0xFF4CAF50);
const Color highlightWarning = Color(0xFFFFA726);
const Color highlightError = Color(0xFFEF5350);
const Color highlightInfo = Color(0xFF78909C);

// ✅ UNIFIED 6 music positions
const List<String> musicPositions = [
  'Guitar 1 🎸',
  'Guitar 2 🎸',
  'Bass 🎸',
  'Rhythm 🎸',
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

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  DateTime _currentDate = DateTime.now();
  late int _currentYear;
  late String _currentMonth;
  late List<Map<String, dynamic>> _sundaysInCurrentMonth;
  List<ScheduleDisplayForMember> _allSchedules = [];

  List<AnnouncementForUser> _announcements = [];
  String _currentUserName = UserSession.userName ?? 'Member';
  final String _currentUserEmail = UserSession.userEmail ?? 'user@example.com';
  final String _currentUserId = UserSession.userId ?? '';
  bool _isLoading = true;
  String? _profileImageUrl;
  List<MemberForDashboard> _members = [];

  DateTime? _lastSeenAnnouncement;
  int _unreadCount = 0;

  Map<String, AssignedMusician>? _monthlyBandAssignment;
  int _monthlyAssignedCount = 0;
  bool _isMusicianListExpanded = false;

  late StreamSubscription<QuerySnapshot> _assignmentsSubscription;
  late StreamSubscription<QuerySnapshot> _announcementsSubscription;
  late StreamSubscription<DocumentSnapshot> _monthlyAssignmentSubscription;

  @override
  void initState() {
    super.initState();
    _initMonth();
    _loadLastSeenTime();
    _loadInitialData();
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
    await _loadMembers();
    _listenToAssignmentsRealTime();
    _listenToAnnouncementsRealTime();
    _listenToMonthlyBandAssignment();
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  Future<void> _refreshData() async {
    await _monthlyAssignmentSubscription.cancel();
    await _loadUserProfile();
    await _loadMembers();
    _listenToMonthlyBandAssignment();
    setState(() {});
  }

  // ✅ Updated: Send push to members (worship leaders), music directors and admins
  Future<void> _createLineupUpdateAnnouncement(String date, String action) async {
    final user = FirebaseAuth.instance.currentUser;
    String userName = _currentUserName;
    if (user != null && (userName == 'Member' || userName.isEmpty)) {
      try {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists && doc.data()?['name'] != null) {
          userName = doc.data()!['name'];
        }
      } catch (e) {}
    }
    
    // Create Firestore announcement
    await FirebaseFirestore.instance.collection('announcements').add({
      'title': '📝 Lineup ${action == 'created' ? 'Created' : 'Updated'}',
      'content': '$userName has ${action == 'created' ? 'created' : 'updated'} the lineup for $date.',
      'createdAt': FieldValue.serverTimestamp(),
      'createdBy': userName,
    });

    // ✅ Send push notification to members (worship leaders)
    await NotificationService.sendToRole(
      role: 'member',
      title: "📝 Lineup ${action == 'created' ? 'Created' : 'Updated'}",
      message: "$userName has $action the lineup for $date",
      data: {'type': 'lineup', 'dateKey': date},
    );
    
    await NotificationService.sendToRole(
      role: 'music_director',
      title: "📝 Lineup ${action == 'created' ? 'Created' : 'Updated'}",
      message: "$userName has $action the lineup for $date",
      data: {'type': 'lineup', 'dateKey': date},
    );
    
    await NotificationService.sendToRole(
      role: 'admin',
      title: "📝 Lineup ${action == 'created' ? 'Created' : 'Updated'}",
      message: "$userName has $action the lineup for $date",
      data: {'type': 'lineup', 'dateKey': date},
    );
  }

  // ✅ Send push when lineup is sealed
  Future<void> _sendSealedNotification(String date, String userName) async {
    await NotificationService.sendToRole(
      role: 'member',
      title: "🔒 Lineup Sealed",
      message: "$userName's lineup for $date has been sealed",
      data: {'type': 'lineup_sealed', 'dateKey': date},
    );
    
    await NotificationService.sendToRole(
      role: 'music_director',
      title: "🔒 Lineup Sealed",
      message: "$userName's lineup for $date has been sealed",
      data: {'type': 'lineup_sealed', 'dateKey': date},
    );
    
    await NotificationService.sendToRole(
      role: 'admin',
      title: "🔒 Lineup Sealed",
      message: "$userName's lineup for $date has been sealed",
      data: {'type': 'lineup_sealed', 'dateKey': date},
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

  List<ScheduleDisplayForMember> get _displaySchedules {
    if (_sundaysInCurrentMonth.isEmpty) return [];
    List<ScheduleDisplayForMember> result = [];
    for (var sunday in _sundaysInCurrentMonth) {
      final dateKey = sunday['dateKey'];
      final existing = _allSchedules.firstWhere(
        (s) => s.dateKey == dateKey,
        orElse: () => ScheduleDisplayForMember(
          id: dateKey,
          name: 'Not Assigned',
          email: '',
          date: sunday['date'],
          dateKey: dateKey,
          time: sunday['time'],
          hasLineUp: false,
          notepadContent: '',
          notes: '',
          userId: '',
          status: 'empty',
          sendDate: null,
        ),
      );
      result.add(existing);
    }
    return result;
  }

  // ✅ Auto‑seal after 5 days or when the assigned Sunday arrives + send push
  void _autoSealExpiredAssignments(List<ScheduleDisplayForMember> schedules) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    for (var s in schedules) {
      if (s.status == 'proposed' && s.sendDate != null && _isCurrentUser(s)) {
        final daysSinceSend = now.difference(s.sendDate!.toDate()).inDays;
        final bool timeExpired = daysSinceSend >= 5;
        final DateTime? assignmentDate = DateTime.tryParse(s.dateKey);
        final bool dateReached = assignmentDate != null &&
            (assignmentDate.isBefore(today) || assignmentDate == today);

        if (timeExpired || dateReached) {
          FirebaseFirestore.instance.collection('assignments').doc(s.id).update({
            'status': 'sealed',
          });
          _sendSealedNotification(s.date, _currentUserName);
          NotificationService.sendToUser(
            userId: _currentUserId,
            title: "🔒 Lineup Sealed",
            message: "Your lineup for ${s.date} has been sealed and cannot be edited.",
            data: {'type': 'lineup', 'dateKey': s.dateKey},
          );
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
      List<AnnouncementForUser> updated = snapshot.docs.map((doc) {
        final data = doc.data();
        return AnnouncementForUser(
          id: doc.id,
          title: data['title'] ?? '',
          content: data['content'] ?? '',
          createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(), // ✅ fixed null safety
          createdBy: data['createdBy'] ?? '',
        );
      }).toList();
      final newOnes = updated.where((a) => !_announcements.any((old) => old.id == a.id)).toList();
      setState(() {
        _announcements = updated;
        _calculateUnreadCount();
      });
      if (mounted && newOnes.isNotEmpty && _selectedIndex != 2) {
        _showNewAnnouncementPopup(newOnes.first);
      }
    });
  }

  void _showNewAnnouncementPopup(AnnouncementForUser announcement) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: almostBlack,
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
              const Text('New Announcement', style: TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(announcement.title, style: TextStyle(color: lightGrey, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: primaryBlack.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  announcement.content.length > 100 ? '${announcement.content.substring(0, 100)}...' : announcement.content,
                  style: TextStyle(color: primaryWhite.withOpacity(0.7), fontSize: 13),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(side: BorderSide(color: mediumGrey)),
                      child: const Text('Later'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        setState(() {
                          _selectedIndex = 2;
                          _updateLastSeenTime();
                        });
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

  Future<void> _loadLastSeenTime() async {
    final prefs = await SharedPreferences.getInstance();
    final ts = prefs.getString('lastSeenAnnouncement');
    if (ts != null) _lastSeenAnnouncement = DateTime.parse(ts);
  }

  Future<void> _updateLastSeenTime() async {
    _lastSeenAnnouncement = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastSeenAnnouncement', _lastSeenAnnouncement!.toIso8601String());
    _calculateUnreadCount();
  }

  void _calculateUnreadCount() {
    if (_lastSeenAnnouncement == null) {
      _unreadCount = _announcements.length;
    } else {
      _unreadCount = _announcements.where((a) => a.createdAt.isAfter(_lastSeenAnnouncement!)).length;
    }
    setState(() {});
  }

  Future<void> _loadMembers() async {
    try {
      QuerySnapshot snap = await FirebaseFirestore.instance.collection('users').get();
      setState(() {
        _members = snap.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return MemberForDashboard(
            id: doc.id,
            name: data['name'] ?? 'Unknown',
            email: data['email'] ?? '',
            isAdmin: data['isAdmin'] ?? false,
          );
        }).toList();
      });
    } catch (e) {
      print("Load members error: $e");
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(_currentUserId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        setState(() {
          _profileImageUrl = data['profileImageUrl'];
          _currentUserName = data['name'] ?? _currentUserName;
        });
      }
    } catch (e) {
      print("Load profile error: $e");
    }
  }

  bool _isCurrentUser(ScheduleDisplayForMember schedule) {
    return schedule.userId == _currentUserId || schedule.email.toLowerCase() == _currentUserEmail.toLowerCase();
  }

  bool _isAssigned(ScheduleDisplayForMember schedule) {
    return schedule.userId.isNotEmpty && schedule.name != 'Not Assigned';
  }

  Future<void> _declineSchedule(String dateKey, String date, String name) async {
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: almostBlack,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Decline Schedule', style: TextStyle(color: lightGrey, fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to decline your assignment as Worship Leader on this date?', style: TextStyle(color: primaryWhite)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel', style: TextStyle(color: mediumGrey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: highlightError, foregroundColor: primaryWhite),
            child: const Text('Yes, Decline'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await FirebaseFirestore.instance.collection('assignments').doc(dateKey).update({
        'assignedMemberId': '',
        'assignedMemberName': 'Not Assigned',
        'assignedMemberEmail': '',
        'hasLineUp': false,
        'notepadContent': '',
        'notes': '',
        'status': 'empty',
        'sendDate': null,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You declined the schedule on $date'), backgroundColor: highlightWarning, duration: const Duration(seconds: 3)),
        );
      }
      await NotificationService.sendToRole(
        role: 'music_director',
        title: "⚠️ Schedule Declined",
        message: "$_currentUserName declined the assignment as Worship Leader on $date",
        data: {'type': 'schedule', 'dateKey': dateKey},
      );
      await NotificationService.sendToRole(
        role: 'admin',
        title: "⚠️ Schedule Declined",
        message: "$_currentUserName declined the assignment as Worship Leader on $date",
        data: {'type': 'schedule', 'dateKey': dateKey},
      );
      await NotificationService.sendToRole(
        role: 'member',
        title: "⚠️ Schedule Declined",
        message: "$_currentUserName declined the assignment as Worship Leader on $date",
        data: {'type': 'schedule', 'dateKey': dateKey},
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: highlightError),
        );
      }
    }
  }

  void _showLineupDialog(ScheduleDisplayForMember schedule) {
    bool isOwner = _isCurrentUser(schedule);
    bool isSealed = schedule.status == 'sealed';
    bool hasContent = schedule.notepadContent.isNotEmpty;

    TextEditingController songsController = TextEditingController(text: schedule.notepadContent);
    TextEditingController notesController = TextEditingController(text: schedule.notes);
    bool isInputMode = false;
    bool isEditMode = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            bool showInputField = (isInputMode || isEditMode);
            return Container(
              height: MediaQuery.of(context).size.height * 0.85,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [primaryBlack, almostBlack, darkSmoke],
                ),
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: mediumGrey, borderRadius: BorderRadius.circular(2)),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: darkSmoke.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
                          child: Icon(isSealed ? Icons.lock : Icons.edit_note, color: lightGrey, size: 24),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(schedule.name, style: const TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold)),
                              Text(schedule.date, style: TextStyle(color: lightGrey, fontSize: 14)),
                              Text(schedule.time, style: TextStyle(color: mediumGrey, fontSize: 12)),
                            ],
                          ),
                        ),
                        if (schedule.status == 'proposed' && schedule.sendDate != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: highlightWarning.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                            child: Text('Proposed', style: TextStyle(color: highlightWarning, fontSize: 12)),
                          ),
                        if (schedule.status == 'sealed')
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(color: highlightSuccess.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                            child: Text('Sealed', style: TextStyle(color: highlightSuccess, fontSize: 12)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.white24, height: 1),
                  const SizedBox(height: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Song Line Up', style: TextStyle(color: primaryWhite, fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          if (showInputField)
                            _buildEditableTextField(controller: songsController, hint: 'Enter songs, links, notes...', maxLines: 12)
                          else
                            _buildReadOnlyContent(context, hasContent: hasContent, content: schedule.notepadContent),
                          if (isOwner && !isSealed) ...[
                            const SizedBox(height: 16),
                            const Text('Additional Notes', style: TextStyle(color: primaryWhite, fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            if (showInputField)
                              _buildEditableTextField(controller: notesController, hint: 'Add service notes...', maxLines: 3)
                            else
                              _buildReadOnlyContent(context, hasContent: schedule.notes.isNotEmpty, content: schedule.notes, isNotes: true),
                          ] else if (!isOwner && schedule.notes.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            const Text('Notes', style: TextStyle(color: primaryWhite, fontSize: 14, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            _buildReadOnlyContent(context, hasContent: true, content: schedule.notes, isNotes: true),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (isOwner && !isSealed && !hasContent && !showInputField)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: ElevatedButton(
                        onPressed: () {
                          setSheetState(() {
                            isInputMode = true;
                            songsController.clear();
                            notesController.clear();
                          });
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: highlightSuccess, minimumSize: const Size(double.infinity, 48)),
                        child: const Text('Input'),
                      ),
                    ),
                  if (isOwner && !isSealed && hasContent && !showInputField)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(side: BorderSide(color: mediumGrey)),
                              child: const Text('Close'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                setSheetState(() {
                                  isEditMode = true;
                                  songsController.text = schedule.notepadContent;
                                  notesController.text = schedule.notes;
                                });
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: highlightSuccess),
                              child: const Text('Edit'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (isInputMode)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: ElevatedButton(
                        onPressed: () async {
                          if (songsController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter your lineup'), backgroundColor: highlightWarning),
                            );
                            return;
                          }
                          await FirebaseFirestore.instance.collection('assignments').doc(schedule.id).update({
                            'hasLineUp': true,
                            'notepadContent': songsController.text,
                            'notes': notesController.text,
                            'status': 'proposed',
                            'sendDate': Timestamp.now(),
                          });
                          await _createLineupUpdateAnnouncement(schedule.date, 'created');
                          if (mounted) Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Lineup saved! 5‑day clock started.'), backgroundColor: highlightSuccess),
                          );
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: highlightSuccess, minimumSize: const Size(double.infinity, 48)),
                        child: const Text('Save and start the 5-day clock'),
                      ),
                    ),
                  if (isEditMode)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                setSheetState(() {
                                  isEditMode = false;
                                  songsController.text = schedule.notepadContent;
                                  notesController.text = schedule.notes;
                                });
                              },
                              style: OutlinedButton.styleFrom(side: BorderSide(color: mediumGrey)),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () async {
                                await FirebaseFirestore.instance.collection('assignments').doc(schedule.id).update({
                                  'notepadContent': songsController.text,
                                  'notes': notesController.text,
                                });
                                schedule.notepadContent = songsController.text;
                                schedule.notes = notesController.text;
                                schedule.hasLineUp = songsController.text.isNotEmpty;
                                await _createLineupUpdateAnnouncement(schedule.date, 'updated');
                                setSheetState(() {
                                  isEditMode = false;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Lineup updated!'), backgroundColor: highlightSuccess),
                                );
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: highlightSuccess),
                              child: const Text('Save Changes'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (isOwner && !isSealed && !showInputField)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          _declineSchedule(schedule.dateKey, schedule.date, schedule.name);
                        },
                        icon: const Icon(Icons.cancel, size: 18),
                        label: const Text('Decline Schedule'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: highlightError,
                          side: const BorderSide(color: highlightError),
                          backgroundColor: highlightError.withOpacity(0.1),
                        ),
                      ),
                    ),
                  if (!isOwner)
                    Padding(
                      padding: const EdgeInsets.all(20),
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(backgroundColor: mediumGrey, minimumSize: const Size(double.infinity, 48)),
                        child: const Text('Close'),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildReadOnlyContent(BuildContext context, {required bool hasContent, required String content, bool isNotes = false}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: primaryBlack.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mediumGrey.withOpacity(0.5)),
      ),
      child: hasContent
          ? _buildClickableNotepadTextView(context, content)
          : Center(child: Text(isNotes ? 'No notes added.' : 'No lineup yet.', style: TextStyle(color: mediumGrey, fontSize: 12))),
    );
  }

  Widget _buildEditableTextField({required TextEditingController controller, required String hint, required int maxLines}) {
    return Container(
      decoration: BoxDecoration(
        color: primaryBlack.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: mediumGrey.withOpacity(0.5)),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(color: primaryWhite, fontSize: 12, height: 1.5),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: mediumGrey),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(12),
        ),
      ),
    );
  }

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
                    return Text(part, style: const TextStyle(color: primaryWhite, fontSize: 12, height: 1.4));
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
                    child: Text(urlString, style: const TextStyle(color: Colors.blue, fontSize: 12, decoration: TextDecoration.underline, height: 1.4)),
                  );
                }),
              ],
            ),
          );
        } else if (line.contains('🎵') || line.contains('📝') || line.contains('✅')) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(line, style: TextStyle(color: lightGrey, fontSize: 12, fontWeight: FontWeight.w500)),
          );
        } else if (line.trim().isEmpty) {
          return const SizedBox(height: 6);
        } else {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text(line, style: const TextStyle(color: primaryWhite, fontSize: 12, height: 1.4)),
          );
        }
      }).toList(),
    );
  }

  String _getAppBarTitle() {
    switch (_selectedIndex) {
      case 0: return 'My Schedule';
      case 1: return 'Worship Team';
      case 2: return 'Announcements';
      case 3: return 'Profile';
      case 4: return 'Band Library';
      default: return 'Dashboard';
    }
  }

  Widget _buildMonthNavigator() {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(color: darkSmoke.withOpacity(0.8), borderRadius: BorderRadius.circular(16), border: Border.all(color: mediumGrey, width: 1.5)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: Icon(Icons.chevron_left, color: lightGrey), onPressed: _previousMonth, constraints: const BoxConstraints()),
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [Text(_currentMonth, style: const TextStyle(color: primaryWhite, fontSize: 16, fontWeight: FontWeight.bold)), Text(_currentYear.toString(), style: const TextStyle(color: mediumGrey, fontSize: 12))]),
          IconButton(icon: Icon(Icons.chevron_right, color: lightGrey), onPressed: _nextMonth, constraints: const BoxConstraints()),
        ],
      ),
    );
  }

  Widget _buildScheduleContent() {
    final schedules = _displaySchedules;
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: lightGrey,
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
                Text('Sundays in $_currentMonth $_currentYear', style: const TextStyle(color: primaryWhite, fontSize: 16, fontWeight: FontWeight.bold)),
                Text('Tap card to view lineup', style: TextStyle(color: mediumGrey, fontSize: 10)),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: schedules.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.calendar_today, size: 60, color: mediumGrey),
                      const SizedBox(height: 12),
                      Text('No Sundays in $_currentMonth $_currentYear', style: TextStyle(color: mediumGrey, fontSize: 14)),
                    ]))
                  : ListView.builder(
                      itemCount: schedules.length,
                      itemBuilder: (context, index) => _buildScheduleCard(schedules[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScheduleCard(ScheduleDisplayForMember schedule) {
    final isCurrentUser = _isCurrentUser(schedule);
    final dayOfMonth = DateTime.tryParse(schedule.dateKey)?.day ?? 0;
    String statusText;
    Color statusColor;
    if (schedule.status == 'empty') {
      statusText = 'Empty';
      statusColor = mediumGrey;
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: lightGrey.withOpacity(0.5), width: 1),
      ),
      color: isCurrentUser ? darkSmoke.withOpacity(0.6) : almostBlack,
      child: InkWell(
        onTap: () => _showLineupDialog(schedule),
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: isCurrentUser ? mediumGrey.withOpacity(0.3) : darkSmoke,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Center(
                  child: Text(dayOfMonth.toString(), style: TextStyle(color: isCurrentUser ? lightGrey : primaryWhite.withOpacity(0.7), fontSize: 18, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          schedule.name,
                          style: TextStyle(
                            color: _isAssigned(schedule) ? highlightSuccess : primaryWhite,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        if (isCurrentUser) ...[
                          const SizedBox(width: 6),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: mediumGrey.withOpacity(0.3), borderRadius: BorderRadius.circular(10)), child: Text('You', style: TextStyle(color: lightGrey, fontSize: 9))),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(schedule.date, style: const TextStyle(color: mediumGrey, fontSize: 11)),
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
              Icon(Icons.chevron_right, color: lightGrey, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTeamContent() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: lightGrey,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            const Row(
              children: [
                Icon(Icons.people, color: lightGrey, size: 24),
                SizedBox(width: 8),
                Text('Worship Team Members', style: TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _members.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.people_outline, size: 64, color: mediumGrey),
                          const SizedBox(height: 16),
                          Text('No members yet', style: TextStyle(color: mediumGrey, fontSize: 16)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _members.length,
                      itemBuilder: (context, index) {
                        final member = _members[index];
                        final isCurrentUser = member.id == _currentUserId;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isCurrentUser ? darkSmoke.withOpacity(0.6) : almostBlack,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: isCurrentUser ? lightGrey : mediumGrey, width: isCurrentUser ? 1.5 : 1),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: mediumGrey,
                                radius: 24,
                                child: Text(
                                  member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                                  style: const TextStyle(color: primaryWhite, fontSize: 16),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(member.name, style: const TextStyle(color: primaryWhite, fontSize: 16, fontWeight: FontWeight.w600)),
                                        if (isCurrentUser) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(color: mediumGrey.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
                                            child: Text('You', style: TextStyle(color: lightGrey, fontSize: 9)),
                                          ),
                                        ],
                                        if (member.isAdmin && !isCurrentUser) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(color: lightGrey.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                                            child: Text('Admin', style: TextStyle(color: lightGrey, fontSize: 8)),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(member.email, style: const TextStyle(color: mediumGrey, fontSize: 12)),
                                  ],
                                ),
                              ),
                              if (isCurrentUser)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(color: highlightSuccess.withOpacity(0.2), borderRadius: BorderRadius.circular(16)),
                                  child: Text('Active', style: TextStyle(color: highlightSuccess, fontSize: 9)),
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

  Widget _buildUpdatesContent() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateLastSeenTime());
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: lightGrey,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.notifications, color: lightGrey, size: 24),
                    SizedBox(width: 8),
                    Text('Announcements & Updates', style: TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                if (_unreadCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: highlightError, borderRadius: BorderRadius.circular(20)),
                    child: Text('$_unreadCount new', style: const TextStyle(color: primaryWhite, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _announcements.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_none, size: 64, color: mediumGrey),
                          const SizedBox(height: 16),
                          Text('No announcements yet', style: TextStyle(color: mediumGrey, fontSize: 16)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _announcements.length,
                      itemBuilder: (context, index) {
                        final a = _announcements[index];
                        final isNew = _lastSeenAnnouncement == null || a.createdAt.isAfter(_lastSeenAnnouncement!);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: almostBlack,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: isNew ? highlightSuccess : mediumGrey, width: isNew ? 2 : 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: darkSmoke.withOpacity(0.5),
                                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.announcement, color: isNew ? highlightSuccess : lightGrey, size: 20),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(child: Text(a.title, style: const TextStyle(color: primaryWhite, fontSize: 15, fontWeight: FontWeight.bold))),
                                              if (isNew)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(color: highlightSuccess.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                                                  child: Text('NEW', style: TextStyle(color: highlightSuccess, fontSize: 9, fontWeight: FontWeight.bold)),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            'Posted by ${a.createdBy} • ${DateFormat('MMM d, yyyy').format(a.createdAt)}',
                                            style: TextStyle(color: lightGrey.withOpacity(0.7), fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: primaryBlack.withOpacity(0.3),
                                  borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(14), bottomRight: Radius.circular(14)),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.edit_note, color: lightGrey, size: 14),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(a.content, style: TextStyle(color: primaryWhite.withOpacity(0.7), fontSize: 12, height: 1.4))),
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

  // ✅ FIXED OVERFLOW: Musician slots now scrollable when expanded
  Widget _buildMusicianSlots() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: darkSmoke.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: mediumGrey.withOpacity(0.5), width: 1),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isMusicianListExpanded = !_isMusicianListExpanded;
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(_isMusicianListExpanded ? Icons.expand_less : Icons.expand_more,
                          color: lightGrey, size: 20),
                      const SizedBox(width: 8),
                      Icon(Icons.music_note, color: lightGrey, size: 16),
                      const SizedBox(width: 6),
                      const Text('Musicians of this Month',
                          style: TextStyle(
                              color: primaryWhite,
                              fontSize: 14,
                              fontWeight: FontWeight.w500)),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _monthlyAssignedCount > 0
                          ? highlightSuccess.withOpacity(0.2)
                          : highlightWarning.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$_monthlyAssignedCount/${musicPositions.length} assigned',
                      style: TextStyle(
                        color: _monthlyAssignedCount > 0 ? highlightSuccess : highlightWarning,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_isMusicianListExpanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 400),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    const SizedBox(height: 10),
                    ...musicPositions.map((position) {
                      String assignedName = 'Not Assigned';
                      Color textColor = mediumGrey;
                      if (_monthlyBandAssignment != null &&
                          _monthlyBandAssignment!.containsKey(position)) {
                        final musician = _monthlyBandAssignment![position]!;
                        if (musician.musicianId.isNotEmpty) {
                          assignedName = musician.musicianName;
                          textColor = highlightSuccess;
                        }
                      }
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: primaryBlack.withOpacity(0.4),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: mediumGrey.withOpacity(0.3)),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(position,
                                    style: TextStyle(color: lightGrey, fontSize: 13),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 12),
                              Flexible(
                                child: Text(assignedName,
                                    style: TextStyle(color: textColor, fontSize: 13,
                                        fontWeight: FontWeight.w500),
                                    textAlign: TextAlign.end,
                                    overflow: TextOverflow.ellipsis),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSettingsContent() => const ProfileScreen();
  Widget _buildBandLibraryContent() => const BandLibraryScreen();

  Widget _buildHeader() {
    String initials = _currentUserName.isNotEmpty ? _currentUserName[0].toUpperCase() : 'U';
    if (_currentUserName.contains(' ') && _currentUserName.length > 2) {
      initials = _currentUserName[0].toUpperCase() + _currentUserName[_currentUserName.indexOf(' ') + 1].toUpperCase();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(color: darkSmoke.withOpacity(0.6), borderRadius: BorderRadius.circular(14), border: Border.all(color: mediumGrey.withOpacity(0.3))),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [mediumGrey, lightGrey])),
            child: ClipOval(
              child: _profileImageUrl != null && _profileImageUrl!.isNotEmpty
                  ? Image.network(_profileImageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Center(child: Text(initials, style: const TextStyle(color: primaryBlack, fontWeight: FontWeight.bold, fontSize: 16))))
                  : Center(child: Text(initials, style: const TextStyle(color: primaryBlack, fontWeight: FontWeight.bold, fontSize: 16))),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_currentUserName, style: const TextStyle(color: primaryWhite, fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: darkSmoke, borderRadius: BorderRadius.circular(10)), child: const Text('Worship Leader', style: TextStyle(color: lightGrey, fontSize: 9))),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    String drawerInitials = _currentUserName.isNotEmpty ? _currentUserName[0].toUpperCase() : 'U';
    if (_currentUserName.contains(' ') && _currentUserName.length > 2) {
      drawerInitials = _currentUserName[0].toUpperCase() + _currentUserName[_currentUserName.indexOf(' ') + 1].toUpperCase();
    }
    return Drawer(
      backgroundColor: almostBlack,
      elevation: 16,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(topRight: Radius.circular(0), bottomRight: Radius.circular(0)),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [primaryBlack, almostBlack, darkSmoke]),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 50, 20, 24),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: mediumGrey.withOpacity(0.5)))),
              child: Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(colors: [mediumGrey, lightGrey]),
                      border: Border.all(color: lightGrey, width: 2),
                    ),
                    child: ClipOval(
                      child: _profileImageUrl != null && _profileImageUrl!.isNotEmpty
                          ? Image.network(_profileImageUrl!, fit: BoxFit.cover)
                          : Center(child: Text(drawerInitials, style: const TextStyle(color: primaryBlack, fontSize: 24, fontWeight: FontWeight.bold))),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_currentUserName, style: const TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: darkSmoke, borderRadius: BorderRadius.circular(12)),
                          child: const Text('Worship Leader', style: TextStyle(color: lightGrey, fontSize: 11)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildDrawerItem(icon: Icons.calendar_today, title: 'Schedule', index: 0, isSelected: _selectedIndex == 0),
            _buildDrawerItem(icon: Icons.people, title: 'Team', index: 1, isSelected: _selectedIndex == 1),
            _buildDrawerItem(icon: Icons.notifications, title: 'Updates', index: 2, isSelected: _selectedIndex == 2, badge: _unreadCount > 0 ? '$_unreadCount' : null),
            _buildDrawerItem(icon: Icons.settings, title: 'Profile', index: 3, isSelected: _selectedIndex == 3),
            _buildDrawerItem(icon: Icons.library_music, title: 'Band Library', index: 4, isSelected: _selectedIndex == 4),
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
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.remove('userId');
                  await prefs.remove('userRole');
                  await prefs.remove('userName');
                  await prefs.remove('userEmail');
                  await prefs.remove('lastSeenAnnouncement');
                  if (mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const AuthScreen()),
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawerItem({required IconData icon, required String title, required int index, required bool isSelected, String? badge}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: isSelected ? darkSmoke : Colors.transparent, border: isSelected ? Border.all(color: lightGrey.withOpacity(0.5)) : null),
      child: ListTile(
        leading: Icon(icon, color: isSelected ? lightGrey : mediumGrey),
        title: Text(title, style: TextStyle(color: isSelected ? primaryWhite : mediumGrey, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
        trailing: badge != null
            ? Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: highlightError, borderRadius: BorderRadius.circular(20)), child: Text(badge, style: const TextStyle(color: primaryWhite, fontSize: 11, fontWeight: FontWeight.bold)))
            : null,
        onTap: () {
          setState(() {
            _selectedIndex = index;
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        color: primaryBlack,
        child: const Center(child: CircularProgressIndicator(color: lightGrey)),
      );
    }
    Widget body;
    switch (_selectedIndex) {
      case 0:
        body = _buildScheduleContent();
        break;
      case 1:
        body = _buildTeamContent();
        break;
      case 2:
        body = _buildUpdatesContent();
        break;
      case 3:
        body = _buildSettingsContent();
        break;
      case 4:
        body = _buildBandLibraryContent();
        break;
      default:
        body = _buildScheduleContent();
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [primaryBlack, almostBlack, darkSmoke],
        ),
      ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: Text(_getAppBarTitle()),
          backgroundColor: Colors.transparent,
          elevation: 0,
          foregroundColor: lightGrey,
          leading: Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.menu, color: lightGrey),
              onPressed: () {
                Scaffold.of(context).openDrawer();
              },
            ),
          ),
        ),
        drawer: _buildDrawer(),
        body: body,
      ),
    );
  }
}

// Helper classes
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

class MemberForDashboard {
  String id, name, email;
  bool isAdmin;
  MemberForDashboard({required this.id, required this.name, required this.email, this.isAdmin = false});
}

class AnnouncementForUser {
  final String id, title, content, createdBy;
  final DateTime createdAt;
  AnnouncementForUser({required this.id, required this.title, required this.content, required this.createdAt, required this.createdBy});
}