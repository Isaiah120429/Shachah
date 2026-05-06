import 'package:cloud_firestore/cloud_firestore.dart';

// Available music positions (6 slots)
const List<String> musicPositions = [
  'Keyboard 🎹',
  'Guitar 1 🎸',
  'Guitar 2 🎸',
  'Bass 🎸',
  'Rhythm 🥁',
  'Drums 🥁',
];

class MusicianModel {
  final String id;
  final String name;
  final String email;
  final String phone;
  final List<String> instruments;
  final bool isActive;
  final DateTime createdAt;
  final String addedBy;

  MusicianModel({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.instruments,
    required this.isActive,
    required this.createdAt,
    required this.addedBy,
  });

  factory MusicianModel.fromMap(String id, Map<String, dynamic> map) {
    return MusicianModel(
      id: id,
      name: map['name'] ?? '',
      email: map['email'] ?? '',
      phone: map['phone'] ?? '',
      instruments: List<String>.from(map['instruments'] ?? []),
      isActive: map['isActive'] ?? true,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      addedBy: map['addedBy'] ?? '',
    );
  }
}

class MusicAssignmentModel {
  final String dateKey;
  final String date;
  final String time;
  final String worshipLeaderId;
  final String worshipLeaderName;
  final Map<String, AssignedMusician> musicians;
  final String notes;
  final DateTime updatedAt;

  MusicAssignmentModel({
    required this.dateKey,
    required this.date,
    required this.time,
    required this.worshipLeaderId,
    required this.worshipLeaderName,
    required this.musicians,
    required this.notes,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'date': date,
      'time': time,
      'worshipLeaderId': worshipLeaderId,
      'worshipLeaderName': worshipLeaderName,
      'musicians': musicians.map((key, value) => MapEntry(key, value.toMap())),
      'notes': notes,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  factory MusicAssignmentModel.fromMap(String dateKey, Map<String, dynamic> map) {
    final musiciansMap = map['musicians'] as Map<String, dynamic>? ?? {};
    return MusicAssignmentModel(
      dateKey: dateKey,
      date: map['date'] ?? '',
      time: map['time'] ?? '9:00 AM',
      worshipLeaderId: map['worshipLeaderId'] ?? '',
      worshipLeaderName: map['worshipLeaderName'] ?? '',
      musicians: musiciansMap.map((key, value) => 
        MapEntry(key, AssignedMusician.fromMap(value as Map<String, dynamic>))),
      notes: map['notes'] ?? '',
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

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

  Map<String, dynamic> toMap() {
    return {
      'musicianId': musicianId,
      'musicianName': musicianName,
      'instrument': instrument,
      'confirmed': confirmed,
    };
  }

  factory AssignedMusician.fromMap(Map<String, dynamic> map) {
    return AssignedMusician(
      musicianId: map['musicianId'] ?? '',
      musicianName: map['musicianName'] ?? '',
      instrument: map['instrument'] ?? '',
      confirmed: map['confirmed'] ?? false,
    );
  }
}