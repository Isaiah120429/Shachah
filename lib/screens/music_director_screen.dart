import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'auth_screen.dart';
import 'profile_screen.dart';
import 'band_library_screen.dart';

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

// Fixed music positions
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
  Map<String, dynamic> toMap() {
    return {
      'musicianId': musicianId,
      'musicianName': musicianName,
      'instrument': instrument,
      'confirmed': confirmed,
    };
  }
}

class MusicianFromCollection {
  final String id;
  final String name;
  final String email;
  final bool isActive;
  MusicianFromCollection({
    required this.id,
    required this.name,
    required this.email,
    required this.isActive,
  });
}

class ScheduleAssignmentForAdmin {
  String dateKey;
  String date;
  String time;
  String assignedMemberId;
  String assignedMemberName;
  String assignedMemberEmail;
  String status;
  Timestamp? sendDate;
  ScheduleAssignmentForAdmin({
    required this.dateKey,
    required this.date,
    required this.time,
    required this.assignedMemberId,
    required this.assignedMemberName,
    required this.assignedMemberEmail,
    required this.status,
    this.sendDate,
  });
}

class Announcement {
  final String id;
  final String title;
  final String content;
  final DateTime createdAt;
  final String createdBy;
  Announcement({
    required this.id,
    required this.title,
    required this.content,
    required this.createdAt,
    required this.createdBy,
  });
}

class MusicDirectorDashboard extends StatefulWidget {
  const MusicDirectorDashboard({super.key});

  @override
  State<MusicDirectorDashboard> createState() => _MusicDirectorDashboardState();
}

class _MusicDirectorDashboardState extends State<MusicDirectorDashboard> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  // Month navigation
  late DateTime _currentDate;
  late String _currentMonth;
  late int _currentYear;
  late List<Map<String, dynamic>> _availableSundays;
  late List<ScheduleAssignmentForAdmin> _assignments;
  late List<MusicianFromCollection> _musicians;
  bool _isLoading = true;

  // Monthly band assignments
  Map<String, AssignedMusician>? _monthlyBandAssignments;
  int _monthlyAssignedCount = 0;

  // Notepad cache
  final Map<String, Map<String, dynamic>> _notepadCache = {};
  List<Announcement> _announcements = [];

  // Announcement selection
  bool _isSelectionMode = false;
  final Set<String> _selectedAnnouncementIds = {};

  // Unread announcements tracking
  DateTime? _lastSeenTime;
  int _unreadCount = 0;

  // Stream subscriptions
  late StreamSubscription<QuerySnapshot> _assignmentsSubscription;
  late StreamSubscription<QuerySnapshot> _announcementsSubscription;
  late StreamSubscription<DocumentSnapshot> _monthlyAssignmentSubscription;
  late StreamSubscription<QuerySnapshot> _musiciansSubscription;

  @override
  void initState() {
    super.initState();
    _initData();
    _loadLastSeenTime();
    _listenToAssignmentsRealTime();
    _listenToAnnouncementsRealTime();
    _listenToMonthlyBandAssignments();
    _listenToMusiciansRealTime();
    _setupOneSignal();
  }

  // ==================== ONESIGNAL SETUP ====================
  void _setupOneSignal() {
    OneSignal.Notifications.addClickListener((event) {
      print("📱 Notification clicked: ${event.notification.title}");
      final additionalData = event.notification.additionalData;
      final type = additionalData?['type'];
      
      if (type == 'assignment') {
        print("🎵 Navigate to Schedule tab");
        setState(() => _selectedIndex = 2);
      } else if (type == 'announcement') {
        print("📢 Navigate to Updates tab");
        setState(() => _selectedIndex = 3);
      }
    });
    print("✅ OneSignal listener setup complete");
  }

  // ==================== SEND PUSH NOTIFICATION ====================
  Future<void> _sendPushNotification(String title, String message, String type) async {
    const String appId = "6eed93c0-d444-4990-9c6d-cc151a557578";
    const String apiKey = "os_v2_app_n3wzhqguirezbhdnzqkruvlvpccdd4gdjw5e3onkmjwi2cdilvitmvr4euh7gcwac45ofj3dyk6or6mn5jwqexc5esk5xnlkrdu3tgy";
    
    try {
      final response = await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic $apiKey',
        },
        body: jsonEncode({
          'app_id': appId,
          'headings': {'en': title},
          'contents': {'en': message},
          'data': {'type': type},
          'included_segments': ['All'],
        }),
      );
      
      if (response.statusCode == 200) {
        print("✅ Push notification sent: $title");
      } else {
        print("❌ Failed: ${response.body}");
      }
    } catch (e) {
      print("❌ Error: $e");
    }
  }

  // ==================== SEND PERSONALIZED PUSH NOTIFICATION ====================
  Future<void> _sendPersonalizedPushNotification(String title, String message, String type, String userId) async {
    const String appId = "6eed93c0-d444-4990-9c6d-cc151a557578";
    const String apiKey = "os_v2_app_n3wzhqguirezbhdnzqkruvlvpccdd4gdjw5e3onkmjwi2cdilvitmvr4euh7gcwac45ofj3dyk6or6mn5jwqexc5esk5xnlkrdu3tgy";
    
    try {
      final response = await http.post(
        Uri.parse('https://onesignal.com/api/v1/notifications'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic $apiKey',
        },
        body: jsonEncode({
          'app_id': appId,
          'headings': {'en': title},
          'contents': {'en': message},
          'data': {'type': type},
          'filters': [
            {'field': 'tag', 'key': 'user_id', 'relation': '=', 'value': userId}
          ],
        }),
      );
      
      if (response.statusCode == 200) {
        print("✅ Personalized push notification sent to user: $userId");
      } else {
        print("❌ Failed: ${response.body}");
      }
    } catch (e) {
      print("❌ Error: $e");
    }
  }

  void _initData() {
    _currentDate = DateTime.now();
    _currentMonth = DateFormat('MMMM').format(_currentDate);
    _currentYear = _currentDate.year;
    _availableSundays = _getSundaysOfMonth(_currentYear, _currentDate.month);
    _musicians = [];
    _isLoading = false;
  }

  Future<void> _refreshData() async {
    await Future.delayed(const Duration(milliseconds: 500));
    setState(() {});
  }

  Future<void> _loadLastSeenTime() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('mdLastSeenAnnouncement');
    if (saved != null) _lastSeenTime = DateTime.parse(saved);
  }

  Future<void> _saveCurrentViewTime() async {
    _lastSeenTime = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('mdLastSeenAnnouncement', _lastSeenTime!.toIso8601String());
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

  Future<String> _getCurrentUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'Unknown';
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      if (doc.exists && doc.data()?['name'] != null && doc.data()!['name'].toString().isNotEmpty) {
        return doc.data()!['name'];
      } else {
        return user.email?.split('@').first ?? 'User';
      }
    } catch (e) {
      return user.email?.split('@').first ?? 'User';
    }
  }

  void _listenToMusiciansRealTime() {
    _musiciansSubscription = FirebaseFirestore.instance
        .collection('musicians')
        .snapshots()
        .listen((snapshot) {
      List<MusicianFromCollection> updatedList = [];
      for (var doc in snapshot.docs) {
        final data = doc.data();
        updatedList.add(MusicianFromCollection(
          id: doc.id,
          name: data['name'] ?? 'Unknown',
          email: data['email'] ?? '',
          isActive: data['isActive'] ?? true,
        ));
      }
      setState(() {
        _musicians = updatedList;
      });
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

  void _previousMonth() {
    setState(() {
      _isLoading = true;
      DateTime prev = DateTime(_currentYear, _currentDate.month - 1);
      _currentYear = prev.year;
      _currentDate = prev;
      _currentMonth = DateFormat('MMMM').format(prev);
      _availableSundays = _getSundaysOfMonth(_currentYear, prev.month);
      _isLoading = false;
    });
    _monthlyAssignmentSubscription.cancel();
    _listenToMonthlyBandAssignments();
  }

  void _nextMonth() {
    setState(() {
      _isLoading = true;
      DateTime next = DateTime(_currentYear, _currentDate.month + 1);
      _currentYear = next.year;
      _currentDate = next;
      _currentMonth = DateFormat('MMMM').format(next);
      _availableSundays = _getSundaysOfMonth(_currentYear, next.month);
      _isLoading = false;
    });
    _monthlyAssignmentSubscription.cancel();
    _listenToMonthlyBandAssignments();
  }

  void _autoSealExpiredAssignments() {
    for (var s in _assignments) {
      if (s.status == 'proposed' && s.sendDate != null) {
        final daysSinceSend = DateTime.now().difference(s.sendDate!.toDate()).inDays;
        if (daysSinceSend >= 5) {
          FirebaseFirestore.instance.collection('assignments').doc(s.dateKey).update({'status': 'sealed'});
        }
      }
    }
  }

  void _listenToAssignmentsRealTime() {
    _assignmentsSubscription = FirebaseFirestore.instance
        .collection('assignments')
        .snapshots()
        .listen((snapshot) {
      List<ScheduleAssignmentForAdmin> updatedAssignments = [];
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
        updatedAssignments.add(ScheduleAssignmentForAdmin(
          dateKey: doc.id,
          date: data['date'] ?? '',
          time: data['time'] ?? '9:00 AM',
          assignedMemberId: data['assignedMemberId'] ?? '',
          assignedMemberName: data['assignedMemberName'] ?? 'Not Assigned',
          assignedMemberEmail: data['assignedMemberEmail'] ?? '',
          status: status,
          sendDate: sendDate,
        ));
        _notepadCache[doc.id] = {
          'notepadContent': data['notepadContent'] ?? '',
          'notes': data['notes'] ?? '',
          'hasLineUp': data['hasLineUp'] ?? false,
        };
      }
      for (var date in _availableSundays) {
        if (!updatedAssignments.any((a) => a.dateKey == date['dateKey'])) {
          updatedAssignments.add(ScheduleAssignmentForAdmin(
            dateKey: date['dateKey'],
            date: date['date'],
            time: '9:00 AM',
            assignedMemberId: '',
            assignedMemberName: 'Not Assigned',
            assignedMemberEmail: '',
            status: 'empty',
            sendDate: null,
          ));
        }
      }
      setState(() {
        _assignments = updatedAssignments;
      });
      _autoSealExpiredAssignments();
    });
  }

  void _listenToAnnouncementsRealTime() {
    _announcementsSubscription = FirebaseFirestore.instance
        .collection('announcements')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
      List<Announcement> updated = snapshot.docs.map((doc) {
        final data = doc.data();
        return Announcement(
          id: doc.id,
          title: data['title'] ?? '',
          content: data['content'] ?? '',
          createdAt: (data['createdAt'] as Timestamp).toDate(),
          createdBy: data['createdBy'] ?? '',
        );
      }).toList();
      
      final newOnes = updated.where((a) => !_announcements.any((old) => old.id == a.id)).toList();
      
      setState(() {
        _announcements = updated;
        _updateUnreadCount();
        if (_isSelectionMode) _exitSelectionMode();
      });
      
      if (mounted && newOnes.isNotEmpty && _selectedIndex != 3) {
        _showNewAnnouncementPopup(newOnes.first);
      }
    });
  }

  void _showNewAnnouncementPopup(Announcement announcement) {
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
              Text(announcement.title, style: TextStyle(color: chamoisee, fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: smokyBlack.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  announcement.content.length > 100 ? '${announcement.content.substring(0, 100)}...' : announcement.content,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
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
                        setState(() {
                          _selectedIndex = 3;
                          _saveCurrentViewTime();
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

  void _listenToMonthlyBandAssignments() {
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
          _monthlyBandAssignments = assignments;
          _monthlyAssignedCount = count;
        });
      } else {
        setState(() {
          _monthlyBandAssignments = {};
          _monthlyAssignedCount = 0;
        });
      }
    });
  }

  @override
  void dispose() {
    _assignmentsSubscription.cancel();
    _announcementsSubscription.cancel();
    _monthlyAssignmentSubscription.cancel();
    _musiciansSubscription.cancel();
    super.dispose();
  }

  // ==================== ASSIGN MUSICIAN TO POSITION (WITH PUSH NOTIFICATION) ====================
  Future<void> _assignMusicianToPosition(String position, String musicianId, String musicianName, String musicianEmail) async {
    final monthKey = DateFormat('yyyy-MM').format(_currentDate);
    final docRef = FirebaseFirestore.instance.collection('monthly_music_assignments').doc(monthKey);
    final newAssignment = AssignedMusician(
      musicianId: musicianId,
      musicianName: musicianName,
      instrument: position,
      confirmed: false,
    );
    await docRef.set({
      'musicians': {
        ...?_monthlyBandAssignments?.map((k, v) => MapEntry(k, v.toMap())),
        position: newAssignment.toMap(),
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    
    // ✅ Send personalized push notification to the assigned musician
    await _sendPersonalizedPushNotification(
      '🎵 New Band Assignment',
      'You have been assigned as $position for $_currentMonth',
      'assignment',
      musicianId,
    );
    
    // ✅ Send general announcement to all users
    final currentUserName = await _getCurrentUserName();
    await _sendPushNotification(
      '🎵 Band Member Assigned',
      '$currentUserName assigned $musicianName as $position',
      'announcement',
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ $musicianName assigned to $position'), backgroundColor: highlightSuccess),
      );
    }
  }

  Future<void> _unassignMusicianFromPosition(String position) async {
    try {
      final monthKey = DateFormat('yyyy-MM').format(_currentDate);
      final docRef = FirebaseFirestore.instance.collection('monthly_music_assignments').doc(monthKey);
      await docRef.update({
        'musicians.$position': FieldValue.delete(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Musician removed from $position'), backgroundColor: highlightWarning),
        );
      }
    } catch (e) {
      if (e.toString().contains('not found')) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: highlightError),
        );
      }
    }
  }

  // ==================== ASSIGN WORSHIP LEADER (WITH PUSH NOTIFICATION) ====================
  Future<void> _assignWorshipLeader(ScheduleAssignmentForAdmin assignment, String memberId, String memberName, String memberEmail) async {
    await FirebaseFirestore.instance.collection('assignments').doc(assignment.dateKey).update({
      'assignedMemberId': memberId,
      'assignedMemberName': memberName,
      'assignedMemberEmail': memberEmail,
      'status': 'empty', // Will become 'proposed' when they add lineup
      'sendDate': null,
    });
    
    // ✅ Send personalized push notification to the assigned worship leader
    await _sendPersonalizedPushNotification(
      '📅 Worship Leader Assignment',
      'You have been assigned as Worship Leader on ${assignment.date}',
      'assignment',
      memberId,
    );
    
    // ✅ Send general announcement to all users
    final currentUserName = await _getCurrentUserName();
    await _sendPushNotification(
      '📅 Schedule Update',
      '$currentUserName assigned $memberName as Worship Leader on ${assignment.date}',
      'announcement',
    );
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ $memberName assigned as Worship Leader on ${assignment.date}'), backgroundColor: highlightSuccess),
      );
    }
  }

  void _showAssignWorshipLeaderDialog(ScheduleAssignmentForAdmin assignment) {
    String? selectedMemberId;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          final activeMusicians = _musicians.where((m) => m.isActive).toList();
          
          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
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
                        child: const Icon(Icons.assignment_ind, color: chamoisee, size: 28)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Assign Worship Leader', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          Text(assignment.date, style: TextStyle(color: chamoisee, fontSize: 14)),
                          Text(assignment.time, style: TextStyle(color: chamoisee.withOpacity(0.7), fontSize: 12)),
                        ]),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white24, height: 1),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Select Worship Leader', style: TextStyle(color: chamoisee, fontSize: 14, fontWeight: FontWeight.w600)),
                      Text('${activeMusicians.length} musicians', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: activeMusicians.isEmpty
                      ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.people_outline, size: 48, color: chamoisee.withOpacity(0.5)),
                          const SizedBox(height: 12),
                          Text('No active musicians available', style: TextStyle(color: chamoisee)),
                          const SizedBox(height: 8),
                          Text('Add musicians from the Musicians tab', style: TextStyle(color: Colors.grey, fontSize: 11)),
                        ]))
                      : ListView.builder(
                          itemCount: activeMusicians.length,
                          itemBuilder: (context, index) {
                            final musician = activeMusicians[index];
                            final isSelected = selectedMemberId == musician.id;
                            final isCurrentAssigned = assignment.assignedMemberId == musician.id;
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected ? kobicha.withOpacity(0.3) : (isCurrentAssigned ? highlightSuccess.withOpacity(0.1) : Colors.transparent),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isSelected ? chamoisee : (isCurrentAssigned ? highlightSuccess : kobicha), width: 1.5),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(backgroundColor: kobicha, child: Text(musician.name[0].toUpperCase())),
                                title: Text(musician.name, style: const TextStyle(color: Colors.white)),
                                subtitle: Text(musician.email, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                trailing: isCurrentAssigned && assignment.assignedMemberId.isNotEmpty
                                    ? Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(color: highlightSuccess, borderRadius: BorderRadius.circular(20)),
                                        child: const Text('Current', style: TextStyle(color: Colors.white, fontSize: 11)))
                                    : ElevatedButton(
                                        onPressed: () => setSheetState(() => selectedMemberId = musician.id),
                                        style: ElevatedButton.styleFrom(backgroundColor: kobicha, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                                        child: const Text('Select'),
                                      ),
                              ),
                            );
                          },
                        ),
                ),
                if (selectedMemberId != null)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), style: OutlinedButton.styleFrom(side: BorderSide(color: kobicha)), child: const Text('Cancel'))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              final selected = activeMusicians.firstWhere((m) => m.id == selectedMemberId);
                              _assignWorshipLeader(assignment, selected.id, selected.name, selected.email);
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: highlightSuccess),
                            child: const Text('Confirm Assignment'),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showPositionAssignDialog(String position, String currentMusicianId, String currentMusicianName) {
    String? selectedMusicianId = currentMusicianId.isNotEmpty ? currentMusicianId : null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            height: MediaQuery.of(context).size.height * 0.7,
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
                        child: Text(position.split(' ')[0], style: TextStyle(color: chamoisee, fontSize: 20, fontWeight: FontWeight.bold))),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(position, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          const Text('Choose a musician', style: TextStyle(color: Colors.grey, fontSize: 12)),
                        ]),
                      ),
                      if (currentMusicianId.isNotEmpty)
                        Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: highlightSuccess.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                          child: Text('Assigned', style: TextStyle(color: highlightSuccess, fontSize: 12))),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white24, height: 1),
                const SizedBox(height: 16),
                if (currentMusicianId.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: licorice.withOpacity(0.5), borderRadius: BorderRadius.circular(12), border: Border.all(color: kobicha)),
                      child: Row(
                        children: [
                          const Icon(Icons.person, color: highlightSuccess),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Currently Assigned', style: TextStyle(color: Colors.grey, fontSize: 11)),
                            Text(currentMusicianName, style: const TextStyle(color: Colors.white, fontSize: 16)),
                          ])),
                          OutlinedButton.icon(
                            onPressed: () async {
                              Navigator.pop(context);
                              await _unassignMusicianFromPosition(position);
                            },
                            icon: const Icon(Icons.clear, size: 16),
                            label: const Text('Remove'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: highlightError,
                              side: const BorderSide(color: highlightError),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Select Musician', style: TextStyle(color: chamoisee, fontSize: 14, fontWeight: FontWeight.w600)),
                      Text('${_musicians.length} musicians', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _musicians.isEmpty
                      ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.people_outline, size: 48, color: chamoisee.withOpacity(0.5)),
                          const SizedBox(height: 12),
                          Text('No musicians added yet', style: TextStyle(color: chamoisee)),
                          const SizedBox(height: 8),
                          Text('Add musicians from Musician Dashboard', style: TextStyle(color: Colors.grey, fontSize: 11)),
                        ]))
                      : ListView.builder(
                          itemCount: _musicians.length,
                          itemBuilder: (context, index) {
                            final musician = _musicians[index];
                            final isSelected = selectedMusicianId == musician.id;
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected ? kobicha.withOpacity(0.3) : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isSelected ? chamoisee : kobicha, width: 1.5),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(backgroundColor: kobicha, child: Text(musician.name[0].toUpperCase())),
                                title: Text(musician.name, style: const TextStyle(color: Colors.white)),
                                subtitle: Text(musician.email, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                trailing: isSelected
                                    ? Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(color: highlightSuccess, borderRadius: BorderRadius.circular(20)),
                                        child: const Text('Selected', style: TextStyle(color: Colors.white, fontSize: 11)))
                                    : ElevatedButton(
                                        onPressed: () => setSheetState(() => selectedMusicianId = musician.id),
                                        style: ElevatedButton.styleFrom(backgroundColor: kobicha, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                                        child: const Text('Assign'),
                                      ),
                              ),
                            );
                          },
                        ),
                ),
                if (selectedMusicianId != null && selectedMusicianId != currentMusicianId)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), style: OutlinedButton.styleFrom(side: BorderSide(color: kobicha)), child: const Text('Cancel'))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              final selected = _musicians.firstWhere((m) => m.id == selectedMusicianId);
                              _assignMusicianToPosition(position, selected.id, selected.name, selected.email);
                              Navigator.pop(context);
                            },
                            style: ElevatedButton.styleFrom(backgroundColor: highlightSuccess),
                            child: const Text('Confirm Assignment'),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showViewOnlyLineupDialog(ScheduleAssignmentForAdmin assignment) {
    final cache = _notepadCache[assignment.dateKey];
    final notepadContent = cache?['notepadContent'] ?? '';
    final notes = cache?['notes'] ?? '';

    String statusText;
    Color statusColor;
    if (assignment.status == 'empty') {
      statusText = 'Empty';
      statusColor = Colors.grey;
    } else if (assignment.status == 'proposed') {
      if (assignment.sendDate != null) {
        final daysLeft = 5 - DateTime.now().difference(assignment.sendDate!.toDate()).inDays;
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
                    child: const Icon(Icons.visibility, color: chamoisee)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(assignment.assignedMemberName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(assignment.date, style: TextStyle(color: chamoisee, fontSize: 14)),
                      Text(assignment.time, style: TextStyle(color: chamoisee.withOpacity(0.7), fontSize: 12)),
                    ]),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: statusColor.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(assignment.status == 'empty' ? Icons.hourglass_empty : (assignment.status == 'sealed' ? Icons.lock : Icons.edit), size: 12, color: statusColor),
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
                      decoration: BoxDecoration(
                        color: smokyBlack.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: kobicha.withOpacity(0.5)),
                      ),
                      child: notepadContent.isEmpty
                          ? Center(child: Text('No lineup yet.', style: TextStyle(color: chamoisee, fontSize: 12)))
                          : _buildClickableNotepadTextView(context, notepadContent),
                    ),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text('Notes', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: smokyBlack.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kobicha.withOpacity(0.5)),
                        ),
                        child: _buildClickableNotepadTextView(context, notes),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(backgroundColor: kobicha),
                      child: const Text('Close'),
                    ),
                  ),
                  if (assignment.assignedMemberId.isEmpty)
                    const SizedBox(width: 12),
                  if (assignment.assignedMemberId.isEmpty)
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(context);
                          _showAssignWorshipLeaderDialog(assignment);
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: highlightSuccess),
                        child: const Text('Assign Leader'),
                      ),
                    ),
                ],
              ),
            ),
          ],
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
                            SnackBar(content: Text('Could not open link: $urlString'), backgroundColor: highlightError),
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

  // ==================== UI BUILDERS ====================
  Widget _buildSimpleHeader() {
    String initials = UserSession.userName?.isNotEmpty == true ? UserSession.userName![0].toUpperCase() : 'M';
    return Row(
      children: [
        Container(width: 45, height: 45, decoration: BoxDecoration(gradient: LinearGradient(colors: [kobicha, chamoisee]), borderRadius: BorderRadius.circular(22.5)),
          child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)))),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(UserSession.userName ?? 'Music Director', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: kobicha.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
            child: const Text('Music Director', style: TextStyle(color: chamoisee, fontSize: 10))),
        ]),
      ],
    );
  }

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
          IconButton(icon: Icon(Icons.chevron_left, color: chamoisee), onPressed: _previousMonth, constraints: const BoxConstraints()),
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(_currentMonth, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            Text(_currentYear.toString(), style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ]),
          IconButton(icon: Icon(Icons.chevron_right, color: chamoisee), onPressed: _nextMonth, constraints: const BoxConstraints()),
        ],
      ),
    );
  }

  // ✅ BAND ASSIGNMENT TAB with pull-to-refresh
  Widget _buildBandAssignmentContent() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: chamoisee,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildSimpleHeader(),
              const SizedBox(height: 20),
              _buildMonthNavigator(),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                decoration: BoxDecoration(
                  color: licorice.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: kobicha.withOpacity(0.5)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(children: [Icon(Icons.music_note, color: chamoisee), const SizedBox(width: 6),
                          const Text('Band Members for this Month', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500))]),
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: _monthlyAssignedCount > 0 ? highlightSuccess.withOpacity(0.2) : highlightWarning.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                          child: Text('$_monthlyAssignedCount/${musicPositions.length} assigned',
                              style: TextStyle(color: _monthlyAssignedCount > 0 ? highlightSuccess : highlightWarning, fontSize: 10))),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ...musicPositions.map((position) {
                      String assignedName = 'Not Assigned';
                      String assignedId = '';
                      Color textColor = Colors.grey;
                      if (_monthlyBandAssignments != null && _monthlyBandAssignments!.containsKey(position)) {
                        final musician = _monthlyBandAssignments![position]!;
                        if (musician.musicianId.isNotEmpty) {
                          assignedName = musician.musicianName;
                          assignedId = musician.musicianId;
                          textColor = highlightSuccess;
                        }
                      }
                      return GestureDetector(
                        onTap: () => _showPositionAssignDialog(position, assignedId, assignedName),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: smokyBlack.withOpacity(0.5), borderRadius: BorderRadius.circular(12), border: Border.all(color: kobicha.withOpacity(0.3))),
                          child: Row(
                            children: [
                              Icon(Icons.person, color: assignedId.isNotEmpty ? highlightSuccess : kobicha, size: 20),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(position, style: TextStyle(color: chamoisee, fontSize: 12)),
                                Text(assignedName, style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w500)),
                              ])),
                              Icon(Icons.chevron_right, color: chamoisee),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ MUSICIANS TAB with pull-to-refresh
  Widget _buildMusiciansContent() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: chamoisee,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildSimpleHeader(),
              const SizedBox(height: 20),
              Expanded(
                child: _musicians.isEmpty
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.person_off, size: 64, color: chamoisee),
                        const SizedBox(height: 16),
                        Text('No musicians added yet', style: TextStyle(color: chamoisee)),
                        const SizedBox(height: 8),
                        Text('Add musicians from the Musician Dashboard', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      ]))
                    : ListView.builder(
                        itemCount: _musicians.length,
                        itemBuilder: (context, index) {
                          final musician = _musicians[index];
                          return Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(color: licorice.withOpacity(0.6), borderRadius: BorderRadius.circular(16), border: Border.all(color: kobicha)),
                            child: Row(
                              children: [
                                CircleAvatar(backgroundColor: kobicha, radius: 25, child: Text(musician.name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 18))),
                                const SizedBox(width: 16),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(musician.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                                  Text(musician.email, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                ])),
                                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(color: musician.isActive ? highlightSuccess.withOpacity(0.2) : highlightError.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                                  child: Text(musician.isActive ? 'Active' : 'Inactive', style: TextStyle(color: musician.isActive ? highlightSuccess : highlightError, fontSize: 10))),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ✅ SCHEDULE TAB (with pull-to-refresh and assign button)
  Widget _buildScheduleContent() {
    final filteredAssignments = _assignments.where((a) => _availableSundays.any((s) => s['dateKey'] == a.dateKey)).toList();
    filteredAssignments.sort((a, b) => a.dateKey.compareTo(b.dateKey));

    return RefreshIndicator(
      onRefresh: _refreshData,
      color: chamoisee,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              _buildSimpleHeader(),
              const SizedBox(height: 20),
              _buildMonthNavigator(),
              const SizedBox(height: 8),
              Expanded(
                child: filteredAssignments.isEmpty
                    ? Center(child: Text('No Sundays in ${DateFormat('MMMM yyyy').format(_currentDate)}', style: TextStyle(color: chamoisee)))
                    : ListView.builder(
                        itemCount: filteredAssignments.length,
                        itemBuilder: (context, index) {
                          final assignment = filteredAssignments[index];
                          final isAssigned = assignment.assignedMemberId.isNotEmpty;
                          String statusText;
                          Color statusColor;
                          if (assignment.status == 'empty') {
                            statusText = 'Empty';
                            statusColor = Colors.grey;
                          } else if (assignment.status == 'proposed') {
                            if (assignment.sendDate != null) {
                              final daysLeft = 5 - DateTime.now().difference(assignment.sendDate!.toDate()).inDays;
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
                            margin: const EdgeInsets.only(bottom: 12),
                            color: licorice.withOpacity(0.6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: kobicha)),
                            child: InkWell(
                              onTap: () => _showViewOnlyLineupDialog(assignment),
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(width: 50, height: 50, decoration: BoxDecoration(color: kobicha.withOpacity(0.3), borderRadius: BorderRadius.circular(25)),
                                      child: Icon(Icons.calendar_today, color: chamoisee)),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(assignment.date, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(Icons.person, size: 12, color: Colors.grey),
                                              const SizedBox(width: 4),
                                              Text('Worship Leader: ', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                              Text(isAssigned ? assignment.assignedMemberName : 'Not Assigned',
                                                  style: TextStyle(color: isAssigned ? highlightSuccess : chamoisee, fontSize: 12, fontWeight: FontWeight.w500)),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(color: statusColor.withOpacity(0.15), borderRadius: BorderRadius.circular(10),
                                                border: Border.all(color: statusColor.withOpacity(0.5), width: 0.8)),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(assignment.status == 'empty' ? Icons.hourglass_empty : (assignment.status == 'sealed' ? Icons.lock : Icons.edit), size: 10, color: statusColor),
                                                const SizedBox(width: 4),
                                                Text(statusText, style: TextStyle(color: statusColor, fontSize: 9)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!isAssigned)
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(color: highlightSuccess.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                                        child: const Text('Tap to Assign', style: TextStyle(color: highlightSuccess, fontSize: 10)),
                                      ),
                                    Icon(Icons.chevron_right, color: chamoisee),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _enterSelectionMode() {
    setState(() {
      _isSelectionMode = true;
      _selectedAnnouncementIds.clear();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedAnnouncementIds.clear();
    });
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedAnnouncementIds.length == _announcements.length) {
        _selectedAnnouncementIds.clear();
      } else {
        _selectedAnnouncementIds.addAll(_announcements.map((a) => a.id));
      }
    });
  }

  Future<void> _deleteSelectedAnnouncements() async {
    if (_selectedAnnouncementIds.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: licorice,
        title: const Text('Delete Announcements', style: TextStyle(color: Colors.white)),
        content: Text('Delete ${_selectedAnnouncementIds.length} announcement(s)?', style: TextStyle(color: chamoisee)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: Colors.grey))),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: highlightError), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator(color: chamoisee)));
    try {
      final batch = FirebaseFirestore.instance.batch();
      for (String id in _selectedAnnouncementIds) {
        batch.delete(FirebaseFirestore.instance.collection('announcements').doc(id));
      }
      await batch.commit();
      _exitSelectionMode();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deleted ${_selectedAnnouncementIds.length} announcement(s)'), backgroundColor: highlightSuccess));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: highlightError));
      }
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  // ==================== ADD ANNOUNCEMENT DIALOG (WITH PUSH NOTIFICATION) ====================
  void _showAddAnnouncementDialog() {
    TextEditingController titleCtrl = TextEditingController();
    TextEditingController contentCtrl = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: licorice,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min, 
            children: [
              const Text('Add Announcement', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl, 
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Title', 
                  labelStyle: TextStyle(color: chamoisee), 
                  filled: true, 
                  fillColor: smokyBlack.withOpacity(0.5), 
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
                )
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl, 
                maxLines: 5, 
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Content', 
                  labelStyle: TextStyle(color: chamoisee), 
                  filled: true, 
                  fillColor: smokyBlack.withOpacity(0.5), 
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
                )
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context), 
                      child: const Text('Cancel')
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        if (titleCtrl.text.trim().isEmpty || contentCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Please fill in all fields'), backgroundColor: highlightError),
                          );
                          return;
                        }
                        
                        final realName = await _getCurrentUserName();
                        
                        // Save to Firestore
                        await FirebaseFirestore.instance.collection('announcements').add({
                          'title': titleCtrl.text.trim(),
                          'content': contentCtrl.text.trim(),
                          'createdAt': FieldValue.serverTimestamp(),
                          'createdBy': realName,
                        });
                        
                        // ✅ Send push notification to all users
                        await _sendPushNotification(
                          '📢 New Announcement',
                          titleCtrl.text.trim(),
                          'announcement',
                        );
                        
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Announcement posted!'), backgroundColor: highlightSuccess),
                        );
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: highlightSuccess),
                      child: const Text('Post'),
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

  // ✅ UPDATES TAB with pull-to-refresh
  Widget _buildUpdatesContent() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _saveCurrentViewTime());
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {});
      },
      color: chamoisee,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildSimpleHeader(),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Announcements', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: _showAddAnnouncementDialog,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('New'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: highlightSuccess,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_vert, color: chamoisee),
                      onSelected: (value) {
                        if (value == 'select_all') {
                          _enterSelectionMode();
                          _toggleSelectAll();
                        } else if (value == 'delete_selected') {
                          if (_selectedAnnouncementIds.isNotEmpty) {
                            _deleteSelectedAnnouncements();
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('No announcements selected'), backgroundColor: highlightWarning),
                            );
                          }
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'select_all', child: Text('Select All')),
                        PopupMenuItem(value: 'delete_selected', child: Text('Delete Selected', style: TextStyle(color: highlightError))),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _announcements.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.announcement, size: 64, color: chamoisee.withOpacity(0.5)),
                      const SizedBox(height: 16),
                      Text('No announcements', style: TextStyle(color: chamoisee)),
                    ]))
                  : ListView.builder(
                      itemCount: _announcements.length,
                      itemBuilder: (context, index) {
                        final a = _announcements[index];
                        final isSelected = _selectedAnnouncementIds.contains(a.id);
                        final isNew = _lastSeenTime == null || a.createdAt.isAfter(_lastSeenTime!);
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isSelected ? kobicha.withOpacity(0.3) : licorice.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isSelected ? chamoisee : kobicha, width: isSelected ? 2 : 1),
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: kobicha.withOpacity(0.3),
                                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                                ),
                                child: Row(
                                  children: [
                                    if (_isSelectionMode)
                                      Checkbox(
                                        value: isSelected,
                                        onChanged: (checked) {
                                          setState(() {
                                            if (checked == true) {
                                              _selectedAnnouncementIds.add(a.id);
                                            } else {
                                              _selectedAnnouncementIds.remove(a.id);
                                            }
                                          });
                                        },
                                        activeColor: highlightSuccess,
                                        checkColor: Colors.white,
                                      ),
                                    const Icon(Icons.announcement, color: chamoisee),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(child: Text(a.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                                              if (isNew)
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(color: highlightSuccess.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                                                  child: Text('NEW', style: TextStyle(color: highlightSuccess, fontSize: 9, fontWeight: FontWeight.bold)),
                                                ),
                                            ],
                                          ),
                                          Text(
                                            'Posted by ${a.createdBy} • ${DateFormat('MMM d, yyyy').format(a.createdAt)}',
                                            style: TextStyle(color: chamoisee.withOpacity(0.7), fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!_isSelectionMode)
                                      PopupMenuButton<String>(
                                        icon: Icon(Icons.more_vert, color: chamoisee),
                                        onSelected: (value) async {
                                          if (value == 'delete') {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                backgroundColor: licorice,
                                                title: const Text('Delete Announcement', style: TextStyle(color: Colors.white)),
                                                content: Text('Delete "${a.title}"?', style: TextStyle(color: chamoisee)),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                                  ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: highlightError), child: const Text('Delete')),
                                                ],
                                              ),
                                            );
                                            if (confirm == true) {
                                              await FirebaseFirestore.instance.collection('announcements').doc(a.id).delete();
                                              if (mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('Announcement deleted'), backgroundColor: highlightSuccess),
                                                );
                                              }
                                            }
                                          }
                                        },
                                        itemBuilder: (context) => const [
                                          PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: highlightError))),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                              if (!_isSelectionMode)
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: smokyBlack.withOpacity(0.3),
                                    borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_note, color: chamoisee, size: 16),
                                      const SizedBox(width: 12),
                                      Expanded(child: Text(a.content, style: const TextStyle(color: Colors.white70, fontSize: 13))),
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

  Widget _buildBandLibraryContent() => const BandLibraryScreen();
  Widget _buildSettingsContent() => const ProfileScreen();

  Widget _buildDrawer() {
    String initials = UserSession.userName?.isNotEmpty == true ? UserSession.userName![0].toUpperCase() : 'M';
    return Drawer(
      backgroundColor: licorice,
      child: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [smokyBlack, blackBean, licorice])),
        child: Column(
          children: [
            Container(padding: const EdgeInsets.fromLTRB(20, 50, 20, 24), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: kobicha.withOpacity(0.5)))),
              child: Row(children: [
                Container(width: 60, height: 60, decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [kobicha, chamoisee]), border: Border.all(color: chamoisee, width: 2)),
                  child: Center(child: Text(initials, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)))),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(UserSession.userName ?? 'Music Director', style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: kobicha.withOpacity(0.3), borderRadius: BorderRadius.circular(12)),
                    child: const Text('Music Director', style: TextStyle(color: chamoisee, fontSize: 11))),
                ])),
              ]),
            ),
            const SizedBox(height: 16),
            _buildDrawerItem(icon: Icons.people, title: 'Band Assignment', index: 0, isSelected: _selectedIndex == 0),
            _buildDrawerItem(icon: Icons.group, title: 'Musicians', index: 1, isSelected: _selectedIndex == 1),
            _buildDrawerItem(icon: Icons.calendar_month, title: 'Schedule', index: 2, isSelected: _selectedIndex == 2),
            _buildDrawerItem(icon: Icons.announcement, title: 'Updates', index: 3, isSelected: _selectedIndex == 3, badge: _unreadCount > 0 ? '$_unreadCount' : null),
            _buildDrawerItem(icon: Icons.library_music, title: 'Band Library', index: 4, isSelected: _selectedIndex == 4),
            _buildDrawerItem(icon: Icons.settings, title: 'Profile', index: 5, isSelected: _selectedIndex == 5),
            const Spacer(),
            Container(margin: const EdgeInsets.all(16), decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), border: Border.all(color: highlightError.withOpacity(0.5))),
              child: ListTile(leading: Icon(Icons.logout, color: highlightError), title: Text('Sign Out', style: TextStyle(color: highlightError, fontWeight: FontWeight.w600)),
                onTap: () async {
                  await FirebaseAuth.instance.signOut();
                  UserSession.isLoggedIn = false;
                  UserSession.userId = null;
                  UserSession.userName = null;
                  UserSession.userEmail = null;
                  UserSession.userRole = null;
                  if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AuthScreen()));
                }),
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
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: isSelected ? kobicha.withOpacity(0.3) : Colors.transparent,
          border: isSelected ? Border.all(color: chamoisee.withOpacity(0.5)) : null),
      child: ListTile(
        leading: Icon(icon, color: isSelected ? chamoisee : Colors.grey),
        title: Text(title, style: TextStyle(color: isSelected ? Colors.white : Colors.grey, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
        trailing: badge != null
            ? Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: highlightError, borderRadius: BorderRadius.circular(20)),
                child: Text(badge, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)))
            : null,
        onTap: () {
          setState(() => _selectedIndex = index);
          if (_isSelectionMode) _exitSelectionMode();
          Navigator.pop(context);
        },
      ),
    );
  }

  String _getAppBarTitle() {
    switch (_selectedIndex) {
      case 0: return 'Band Assignment';
      case 1: return 'Musicians';
      case 2: return 'Schedule & Lineups';
      case 3: return 'Announcements';
      case 4: return 'Band Library';
      case 5: return 'Profile';
      default: return 'Music Director';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(decoration: const BoxDecoration(image: DecorationImage(image: AssetImage('assets/music.png'), fit: BoxFit.cover)),
        child: const Center(child: CircularProgressIndicator(color: chamoisee)));
    }
    Widget body;
    switch (_selectedIndex) {
      case 0: body = _buildBandAssignmentContent(); break;
      case 1: body = _buildMusiciansContent(); break;
      case 2: body = _buildScheduleContent(); break;
      case 3: body = _buildUpdatesContent(); break;
      case 4: body = _buildBandLibraryContent(); break;
      case 5: body = _buildSettingsContent(); break;
      default: body = _buildBandAssignmentContent();
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
          actions: _selectedIndex == 3 && _isSelectionMode
              ? [TextButton(onPressed: _exitSelectionMode, child: const Text('Cancel', style: TextStyle(color: chamoisee)))]
              : null,
        ),
        drawer: _buildDrawer(),
        body: body,
      ),
    );
  }
}