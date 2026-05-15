import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'auth_screen.dart';
import 'profile_screen.dart';
import 'band_library_screen.dart';
import 'notification_service.dart';   // ✅ Import your notification service

// Professional Black/White/Smoke Palette
const Color primaryBlack = Color(0xFF000000);
const Color primaryWhite = Color(0xFFFFFFFF);
const Color smokeGrey = Color(0xFFF5F5F5);
const Color darkSmoke = Color(0xFF2C2C2C);
const Color mediumGrey = Color(0xFF757575);
const Color lightGrey = Color(0xFFBDBDBD);
const Color almostBlack = Color(0xFF1E1E1E);

// Functional highlights
const Color highlightSuccess = Color(0xFF4CAF50);
const Color highlightWarning = Color(0xFFFFA726);
const Color highlightError = Color(0xFFEF5350);
const Color highlightInfo = Color(0xFF78909C);

// Fixed music positions (6)
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
      setState(() => _musicians = updatedList);
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
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    for (var s in _assignments) {
      if (s.status == 'proposed' && s.sendDate != null) {
        final daysSinceSend = now.difference(s.sendDate!.toDate()).inDays;
        final DateTime? assignmentDate = DateTime.tryParse(s.dateKey);
        final bool dateReached = assignmentDate != null && (assignmentDate.isBefore(today) || assignmentDate == today);
        if (daysSinceSend >= 5 || dateReached) {
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
      setState(() => _assignments = updatedAssignments);
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

  // ==================== MUSICIANS MANAGEMENT (ADD/DELETE) ====================
  Future<void> _addMusician(String name) async {
    try {
      final docRef = await FirebaseFirestore.instance.collection('musicians').add({
        'name': name.trim(),
        'email': '',
        'phone': '',
        'instruments': [],
        'isActive': true,
        'createdAt': FieldValue.serverTimestamp(),
        'addedBy': FirebaseAuth.instance.currentUser?.uid ?? 'admin',
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Musician added successfully!'), backgroundColor: highlightSuccess),
        );
      }
      // ✅ Send push notification to all music directors (or all users)
      final currentUserName = await _getCurrentUserName();
      await NotificationService.sendToRole(
        role: 'music_director',
        title: "🎵 New Musician Added",
        message: "$currentUserName added $name to the musicians list",
        data: {'type': 'musician', 'id': docRef.id},
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: highlightError),
        );
      }
    }
  }

  Future<void> _deleteMusician(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: almostBlack,
        title: const Text('Delete Musician', style: TextStyle(color: primaryWhite)),
        content: Text('Are you sure you want to delete "$name"?', style: TextStyle(color: lightGrey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: mediumGrey))),
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
      // ✅ Send push notification (optional)
      final currentUserName = await _getCurrentUserName();
      await NotificationService.sendToRole(
        role: 'music_director',
        title: "🗑️ Musician Removed",
        message: "$currentUserName removed $name from the musicians list",
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting: $e'), backgroundColor: highlightError),
        );
      }
    }
  }

  void _showAddMusicianDialog() {
    final TextEditingController nameController = TextEditingController();
    bool isAdding = false;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: almostBlack,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('Add New Musician', style: TextStyle(color: lightGrey)),
            content: TextFormField(
              controller: nameController,
              style: const TextStyle(color: primaryWhite),
              decoration: InputDecoration(
                labelText: 'Full Name',
                labelStyle: TextStyle(color: lightGrey),
                hintText: 'e.g., John Smith',
                hintStyle: TextStyle(color: mediumGrey),
                enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: mediumGrey)),
                focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: lightGrey, width: 2)),
              ),
              autofocus: true,
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel', style: TextStyle(color: mediumGrey))),
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
                        await _addMusician(nameController.text);
                        setDialogState(() => isAdding = false);
                        if (mounted) Navigator.pop(dialogContext);
                      },
                style: ElevatedButton.styleFrom(backgroundColor: highlightSuccess),
                child: isAdding
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: primaryWhite))
                    : const Text('Add'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ==================== ASSIGN MUSICIAN TO POSITION ====================
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

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ $musicianName assigned to $position'), backgroundColor: highlightSuccess),
      );
    }

    // ✅ Send push notification to the assigned musician
    await NotificationService.sendToUser(
      userId: musicianId,
      title: "🎸 New Assignment",
      message: "You have been assigned as $position for ${DateFormat('MMMM yyyy').format(_currentDate)}",
      data: {'type': 'assignment', 'position': position},
    );
  }

  Future<void> _unassignMusicianFromPosition(String position) async {
    try {
      final monthKey = DateFormat('yyyy-MM').format(_currentDate);
      final docRef = FirebaseFirestore.instance.collection('monthly_music_assignments').doc(monthKey);
      
      // Get current assigned musician ID before deleting
      String? oldMusicianId;
      if (_monthlyBandAssignments != null && _monthlyBandAssignments!.containsKey(position)) {
        oldMusicianId = _monthlyBandAssignments![position]!.musicianId;
      }
      
      await docRef.update({
        'musicians.$position': FieldValue.delete(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ Musician removed from $position'), backgroundColor: highlightWarning),
        );
      }
      
      // ✅ Send push notification to the removed musician
      if (oldMusicianId != null && oldMusicianId.isNotEmpty) {
        await NotificationService.sendToUser(
          userId: oldMusicianId,
          title: "⚠️ Assignment Removed",
          message: "You are no longer assigned as $position for ${DateFormat('MMMM yyyy').format(_currentDate)}",
          data: {'type': 'assignment', 'position': position},
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
              gradient: LinearGradient(colors: [primaryBlack, almostBlack, darkSmoke]),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
            ),
            child: Column(
              children: [
                Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: mediumGrey, borderRadius: BorderRadius.circular(2))),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: darkSmoke.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
                        child: Text(position.split(' ')[0], style: TextStyle(color: lightGrey, fontSize: 20, fontWeight: FontWeight.bold))),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(position, style: const TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold)),
                          const Text('Choose a musician', style: TextStyle(color: mediumGrey, fontSize: 12)),
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
                      decoration: BoxDecoration(color: almostBlack.withOpacity(0.5), borderRadius: BorderRadius.circular(12), border: Border.all(color: mediumGrey)),
                      child: Row(
                        children: [
                          const Icon(Icons.person, color: highlightSuccess),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('Currently Assigned', style: TextStyle(color: mediumGrey, fontSize: 11)),
                            Text(currentMusicianName, style: const TextStyle(color: primaryWhite, fontSize: 16)),
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
                      Text('Select Musician', style: TextStyle(color: lightGrey, fontSize: 14, fontWeight: FontWeight.w600)),
                      Text('${_musicians.length} musicians', style: const TextStyle(color: mediumGrey, fontSize: 11)),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: _musicians.isEmpty
                      ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.people_outline, size: 48, color: lightGrey.withOpacity(0.5)),
                          const SizedBox(height: 12),
                          Text('No musicians added yet', style: TextStyle(color: lightGrey)),
                          const SizedBox(height: 8),
                          Text('Tap + button to add musicians', style: TextStyle(color: mediumGrey, fontSize: 11)),
                        ]))
                      : ListView.builder(
                          itemCount: _musicians.length,
                          itemBuilder: (context, index) {
                            final musician = _musicians[index];
                            final isSelected = selectedMusicianId == musician.id;
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              decoration: BoxDecoration(
                                color: isSelected ? darkSmoke.withOpacity(0.5) : Colors.transparent,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isSelected ? lightGrey : mediumGrey, width: 1.5),
                              ),
                              child: ListTile(
                                leading: CircleAvatar(backgroundColor: mediumGrey, child: Text(musician.name[0].toUpperCase(), style: const TextStyle(color: primaryWhite))),
                                title: Text(musician.name, style: const TextStyle(color: primaryWhite)),
                                subtitle: Text(musician.email, style: const TextStyle(color: mediumGrey, fontSize: 12)),
                                trailing: isSelected
                                    ? Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(color: highlightSuccess, borderRadius: BorderRadius.circular(20)),
                                        child: const Text('Selected', style: TextStyle(color: primaryWhite, fontSize: 11)))
                                    : ElevatedButton(
                                        onPressed: () => setSheetState(() => selectedMusicianId = musician.id),
                                        style: ElevatedButton.styleFrom(backgroundColor: darkSmoke, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
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
                        Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), style: OutlinedButton.styleFrom(side: BorderSide(color: mediumGrey)), child: const Text('Cancel'))),
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
      statusColor = mediumGrey;
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
          gradient: LinearGradient(colors: [primaryBlack, almostBlack, darkSmoke]),
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(margin: const EdgeInsets.only(top: 12), width: 40, height: 4, decoration: BoxDecoration(color: mediumGrey, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: darkSmoke.withOpacity(0.5), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.visibility, color: lightGrey)),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(assignment.assignedMemberName, style: const TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold)),
                      Text(assignment.date, style: TextStyle(color: lightGrey, fontSize: 14)),
                      Text(assignment.time, style: TextStyle(color: mediumGrey, fontSize: 12)),
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
                    const Text('Song Line Up', style: TextStyle(color: primaryWhite, fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: primaryBlack.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: mediumGrey.withOpacity(0.5)),
                      ),
                      child: notepadContent.isEmpty
                          ? Center(child: Text('No lineup yet.', style: TextStyle(color: lightGrey, fontSize: 12)))
                          : _buildClickableNotepadTextView(context, notepadContent),
                    ),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text('Notes', style: TextStyle(color: primaryWhite, fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: primaryBlack.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: mediumGrey.withOpacity(0.5)),
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
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: mediumGrey, minimumSize: const Size(double.infinity, 48)),
                child: const Text('Close'),
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
            child: Text(line, style: const TextStyle(color: primaryWhite, fontSize: 12, height: 1.4)),
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
        Container(width: 45, height: 45, decoration: BoxDecoration(gradient: LinearGradient(colors: [mediumGrey, lightGrey]), borderRadius: BorderRadius.circular(22.5)),
          child: Center(child: Text(initials, style: const TextStyle(color: primaryWhite, fontWeight: FontWeight.bold, fontSize: 18)))),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(UserSession.userName ?? 'Music Director', style: const TextStyle(color: primaryWhite, fontSize: 16, fontWeight: FontWeight.w600)),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: darkSmoke, borderRadius: BorderRadius.circular(12)),
            child: const Text('Music Director', style: TextStyle(color: lightGrey, fontSize: 10))),
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
        color: darkSmoke.withOpacity(0.8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: mediumGrey, width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: Icon(Icons.chevron_left, color: lightGrey), onPressed: _previousMonth, constraints: const BoxConstraints()),
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(_currentMonth, style: const TextStyle(color: primaryWhite, fontSize: 16, fontWeight: FontWeight.bold)),
            Text(_currentYear.toString(), style: const TextStyle(color: mediumGrey, fontSize: 12)),
          ]),
          IconButton(icon: Icon(Icons.chevron_right, color: lightGrey), onPressed: _nextMonth, constraints: const BoxConstraints()),
        ],
      ),
    );
  }

  // Band Assignment tab - always shows all slots (non-expandable)
 Widget _buildBandAssignmentContent() {
  return RefreshIndicator(
    onRefresh: _refreshData,
    color: lightGrey,
    child: SafeArea(
      child: SingleChildScrollView(                 // ✅ Makes the whole content scrollable
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildSimpleHeader(),
            const SizedBox(height: 20),
            _buildMonthNavigator(),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: BoxDecoration(
                color: darkSmoke.withOpacity(0.8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: mediumGrey.withOpacity(0.5), width: 1),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.music_note, color: lightGrey, size: 16),
                            const SizedBox(width: 6),
                            const Text(
                              'Band Members for this Month',
                              style: TextStyle(
                                color: primaryWhite,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
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
                  const SizedBox(height: 10),
                  ...musicPositions.map((position) {
                    String assignedName = 'Not Assigned';
                    String assignedId = '';
                    Color textColor = mediumGrey;
                    if (_monthlyBandAssignments != null &&
                        _monthlyBandAssignments!.containsKey(position)) {
                      final musician = _monthlyBandAssignments![position]!;
                      if (musician.musicianId.isNotEmpty) {
                        assignedName = musician.musicianName;
                        assignedId = musician.musicianId;
                        textColor = highlightSuccess;
                      }
                    }
                    return GestureDetector(
                      onTap: () =>
                          _showPositionAssignDialog(position, assignedId, assignedName),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: primaryBlack.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: mediumGrey.withOpacity(0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.person,
                                color: assignedId.isNotEmpty
                                    ? highlightSuccess
                                    : mediumGrey,
                                size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(position,
                                      style: TextStyle(
                                          color: lightGrey, fontSize: 12)),
                                  Text(assignedName,
                                      style: TextStyle(
                                          color: textColor,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500)),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right, color: lightGrey),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 4),
                ],
              ),
            ),
            const SizedBox(height: 20), // extra bottom padding
          ],
        ),
      ),
    ),
  );
}

  Widget _buildMusiciansContent() {
    return RefreshIndicator(
      onRefresh: _refreshData,
      color: lightGrey,
      child: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                _buildSimpleHeader(),
                const SizedBox(height: 20),
                const Row(
                  children: [
                    Icon(Icons.people, color: lightGrey, size: 24),
                    SizedBox(width: 8),
                    Text('All Musicians', style: TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _musicians.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.person_off, size: 64, color: lightGrey.withOpacity(0.5)),
                              const SizedBox(height: 16),
                              Text('No musicians added yet.', style: TextStyle(color: lightGrey)),
                              const SizedBox(height: 8),
                              Text('Tap + button to add musicians', style: TextStyle(color: mediumGrey, fontSize: 12)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _musicians.length,
                          itemBuilder: (context, index) {
                            final musician = _musicians[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: almostBlack,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: mediumGrey, width: 1.5),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor: mediumGrey,
                                    radius: 25,
                                    child: Text(
                                      musician.name.isNotEmpty ? musician.name[0].toUpperCase() : '?',
                                      style: const TextStyle(color: primaryWhite, fontSize: 18),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(musician.name, style: const TextStyle(color: primaryWhite, fontSize: 16, fontWeight: FontWeight.w600)),
                                        Text(musician.email, style: const TextStyle(color: mediumGrey, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: musician.isActive ? highlightSuccess.withOpacity(0.2) : highlightError.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      musician.isActive ? 'Active' : 'Inactive',
                                      style: TextStyle(color: musician.isActive ? highlightSuccess : highlightError, fontSize: 10),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: highlightError),
                                    onPressed: () => _deleteMusician(musician.id, musician.name),
                                    tooltip: 'Delete musician',
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
          floatingActionButton: FloatingActionButton(
            onPressed: _showAddMusicianDialog,
            backgroundColor: highlightSuccess,
            child: const Icon(Icons.add, color: primaryWhite),
          ),
        ),
      ),
    );
  }

  Widget _buildScheduleContent() {
    final filteredAssignments = _assignments.where((a) => _availableSundays.any((s) => s['dateKey'] == a.dateKey)).toList();
    filteredAssignments.sort((a, b) => a.dateKey.compareTo(b.dateKey));

    return RefreshIndicator(
      onRefresh: _refreshData,
      color: lightGrey,
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
                    ? Center(child: Text('No Sundays in ${DateFormat('MMMM yyyy').format(_currentDate)}', style: TextStyle(color: lightGrey)))
                    : ListView.builder(
                        itemCount: filteredAssignments.length,
                        itemBuilder: (context, index) {
                          final assignment = filteredAssignments[index];
                          final isAssigned = assignment.assignedMemberId.isNotEmpty;
                          String statusText;
                          Color statusColor;
                          if (assignment.status == 'empty') {
                            statusText = 'Empty';
                            statusColor = mediumGrey;
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
                            color: almostBlack,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: mediumGrey)),
                            child: InkWell(
                              onTap: () => _showViewOnlyLineupDialog(assignment),
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    Container(width: 50, height: 50, decoration: BoxDecoration(color: darkSmoke, borderRadius: BorderRadius.circular(25)),
                                      child: Icon(Icons.calendar_today, color: lightGrey)),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(assignment.date, style: const TextStyle(color: primaryWhite, fontSize: 16, fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 4),
                                          Row(
                                            children: [
                                              const Icon(Icons.person, size: 12, color: mediumGrey),
                                              const SizedBox(width: 4),
                                              Text('Worship Leader: ', style: TextStyle(color: mediumGrey, fontSize: 12)),
                                              Text(isAssigned ? assignment.assignedMemberName : 'Not Assigned',
                                                  style: TextStyle(color: isAssigned ? highlightSuccess : lightGrey, fontSize: 12, fontWeight: FontWeight.w500)),
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
                                    Icon(Icons.chevron_right, color: lightGrey),
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
        backgroundColor: almostBlack,
        title: const Text('Delete Announcements', style: TextStyle(color: primaryWhite)),
        content: Text('Delete ${_selectedAnnouncementIds.length} announcement(s)?', style: TextStyle(color: lightGrey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: mediumGrey))),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), style: ElevatedButton.styleFrom(backgroundColor: highlightError), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    showDialog(context: context, barrierDismissible: false, builder: (context) => const Center(child: CircularProgressIndicator(color: lightGrey)));
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

  void _showAddAnnouncementDialog() {
    TextEditingController titleCtrl = TextEditingController();
    TextEditingController contentCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: almostBlack,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Add Announcement', style: TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: titleCtrl,
                style: const TextStyle(color: primaryWhite),
                decoration: InputDecoration(
                  labelText: 'Title',
                  labelStyle: TextStyle(color: lightGrey),
                  filled: true,
                  fillColor: primaryBlack.withOpacity(0.5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
                )
              ),
              const SizedBox(height: 12),
              TextField(
                controller: contentCtrl,
                maxLines: 5,
                style: const TextStyle(color: primaryWhite),
                decoration: InputDecoration(
                  labelText: 'Content',
                  labelStyle: TextStyle(color: lightGrey),
                  filled: true,
                  fillColor: primaryBlack.withOpacity(0.5),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))
                )
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(side: BorderSide(color: mediumGrey)),
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
                        final docRef = await FirebaseFirestore.instance.collection('announcements').add({
                          'title': titleCtrl.text.trim(),
                          'content': contentCtrl.text.trim(),
                          'createdAt': FieldValue.serverTimestamp(),
                          'createdBy': realName,
                        });
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Announcement posted!'), backgroundColor: highlightSuccess),
                        );
                        
                        // ✅ Send push notification to all users
                        await NotificationService.sendToAllUsers(
                          title: "📢 New Announcement: ${titleCtrl.text}",
                          message: "$realName posted: ${contentCtrl.text}",
                          data: {'type': 'announcement', 'id': docRef.id},
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

  Widget _buildUpdatesContent() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _saveCurrentViewTime());
    return RefreshIndicator(
      onRefresh: () async { setState(() {}); },
      color: lightGrey,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            _buildSimpleHeader(),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Announcements', style: TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold)),
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
                      icon: Icon(Icons.more_vert, color: lightGrey),
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
                      Icon(Icons.announcement, size: 64, color: lightGrey.withOpacity(0.5)),
                      const SizedBox(height: 16),
                      Text('No announcements', style: TextStyle(color: lightGrey)),
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
                            color: isSelected ? darkSmoke.withOpacity(0.5) : almostBlack,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: isSelected ? lightGrey : mediumGrey, width: isSelected ? 2 : 1),
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: darkSmoke.withOpacity(0.5),
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
                                        checkColor: primaryWhite,
                                      ),
                                    const Icon(Icons.announcement, color: lightGrey),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(child: Text(a.title, style: const TextStyle(color: primaryWhite, fontWeight: FontWeight.bold))),
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
                                            style: TextStyle(color: lightGrey.withOpacity(0.7), fontSize: 10),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!_isSelectionMode)
                                      PopupMenuButton<String>(
                                        icon: Icon(Icons.more_vert, color: lightGrey),
                                        onSelected: (value) async {
                                          if (value == 'delete') {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                backgroundColor: almostBlack,
                                                title: const Text('Delete Announcement', style: TextStyle(color: primaryWhite)),
                                                content: Text('Delete "${a.title}"?', style: TextStyle(color: lightGrey)),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel', style: TextStyle(color: mediumGrey))),
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
                                    color: primaryBlack.withOpacity(0.3),
                                    borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_note, color: lightGrey, size: 16),
                                      const SizedBox(width: 12),
                                      Expanded(child: Text(a.content, style: TextStyle(color: primaryWhite.withOpacity(0.7), fontSize: 13))),
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
      backgroundColor: almostBlack,
      child: Container(
        decoration: BoxDecoration(gradient: LinearGradient(colors: [primaryBlack, almostBlack, darkSmoke])),
        child: Column(
          children: [
            Container(padding: const EdgeInsets.fromLTRB(20, 50, 20, 24), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: mediumGrey.withOpacity(0.5)))),
              child: Row(children: [
                Container(width: 60, height: 60, decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [mediumGrey, lightGrey]), border: Border.all(color: lightGrey, width: 2)),
                  child: Center(child: Text(initials, style: const TextStyle(color: primaryWhite, fontSize: 24, fontWeight: FontWeight.bold)))),
                const SizedBox(width: 16),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(UserSession.userName ?? 'Music Director', style: const TextStyle(color: primaryWhite, fontSize: 18, fontWeight: FontWeight.bold)),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: darkSmoke, borderRadius: BorderRadius.circular(12)),
                    child: const Text('Music Director', style: TextStyle(color: lightGrey, fontSize: 11))),
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
                  await prefs.remove('mdLastSeenAnnouncement');
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
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), color: isSelected ? darkSmoke : Colors.transparent,
          border: isSelected ? Border.all(color: lightGrey.withOpacity(0.5)) : null),
      child: ListTile(
        leading: Icon(icon, color: isSelected ? lightGrey : mediumGrey),
        title: Text(title, style: TextStyle(color: isSelected ? primaryWhite : mediumGrey, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
        trailing: badge != null
            ? Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2), decoration: BoxDecoration(color: highlightError, borderRadius: BorderRadius.circular(20)),
                child: Text(badge, style: const TextStyle(color: primaryWhite, fontSize: 11, fontWeight: FontWeight.bold)))
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
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [primaryBlack, almostBlack, darkSmoke],
          ),
        ),
        child: const Center(child: CircularProgressIndicator(color: lightGrey)),
      );
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
          leading: Builder(builder: (context) => IconButton(icon: const Icon(Icons.menu, color: lightGrey), onPressed: () => Scaffold.of(context).openDrawer())),
          actions: _selectedIndex == 3 && _isSelectionMode
              ? [TextButton(onPressed: _exitSelectionMode, child: const Text('Cancel', style: TextStyle(color: lightGrey)))]
              : null,
        ),
        drawer: _buildDrawer(),
        body: body,
      ),
    );
  }
}