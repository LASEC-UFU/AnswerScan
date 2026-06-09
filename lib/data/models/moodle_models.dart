class MoodleCourse {
  const MoodleCourse({
    required this.id,
    required this.shortname,
    required this.fullname,
  });

  final int id;
  final String shortname;
  final String fullname;

  factory MoodleCourse.fromJson(Map<String, dynamic> json) => MoodleCourse(
    id: json['id'] as int,
    shortname: (json['shortname'] as String?) ?? '',
    fullname: (json['fullname'] as String?) ?? '',
  );
}

class MoodleStudent {
  const MoodleStudent({
    required this.id,
    required this.fullname,
    required this.email,
  });

  final int id;
  final String fullname;
  final String email;

  factory MoodleStudent.fromJson(Map<String, dynamic> json) => MoodleStudent(
    id: json['id'] as int,
    fullname: (json['fullname'] as String?) ?? '',
    email: (json['email'] as String?) ?? '',
  );
}

enum MoodleGradeSource { manual, automatic, unknown }

class MoodleStudentGrade {
  const MoodleStudentGrade({required this.value, required this.source});

  final double? value;
  final MoodleGradeSource source;

  bool get exists => value != null;
  bool get isManual => source == MoodleGradeSource.manual;
}

class MoodleGradeItem {
  const MoodleGradeItem({
    required this.id,
    required this.name,
    required this.itemType,
    this.itemModule,
    this.itemInstance,
    required this.itemNumber,
    required this.gradeMax,
    this.locked = false,
  });

  final int id;
  final String name;
  final String itemType; // 'mod', 'manual', 'course', 'category'
  final String? itemModule; // 'assign', 'quiz', etc.
  final int? itemInstance; // module instance id for mod items
  final int itemNumber;
  final double gradeMax;

  /// True if this grade item is locked in the Moodle gradebook.
  /// Locked items require the 'moodle/grade:override' capability or unlocking.
  final bool locked;

  /// Returns true for items that can receive a grade via mod_assign_save_grade.
  bool get isSubmittable => itemType == 'assign';

  String get displayType => itemModule ?? itemType;

  /// Builds a [MoodleGradeItem] from a [mod_assign_get_assignments] assignment
  /// that passed the grade-column filter.
  ///
  /// [json['id']] is the assignment INSTANCE ID — required by mod_assign_save_grade.
  factory MoodleGradeItem.fromAssignment(Map<String, dynamic> json) {
    return MoodleGradeItem(
      id: json['id'] as int, // assignment instance ID
      name: (json['name'] as String?) ?? 'Avaliação',
      itemType: 'assign',
      itemModule: 'assign',
      itemInstance: json['cmid'] as int?, // course module ID (for reference)
      itemNumber: 0,
      gradeMax: ((json['grade'] as num?) ?? 10).toDouble(),
    );
  }

  // Keep fromJson for session store backwards-compatibility.
  factory MoodleGradeItem.fromJson(Map<String, dynamic> json) {
    return MoodleGradeItem(
      id: json['id'] as int,
      name: (json['name'] as String?) ?? 'Avaliação',
      itemType: (json['itemType'] as String?) ?? 'assign',
      itemModule: json['itemModule'] as String?,
      itemInstance: json['itemInstance'] as int?,
      itemNumber: (json['itemNumber'] as int?) ?? 0,
      gradeMax: ((json['gradeMax'] as num?) ?? 10).toDouble(),
    );
  }
}

class MoodleSession {
  const MoodleSession({
    required this.baseUrl,
    required this.token,
    required this.userId,
    required this.fullname,
    this.serviceName = 'moodle_mobile_app',
    this.availableFunctions = const {},
  });

  final String baseUrl;
  final String token;
  final int userId;
  final String fullname;
  final String serviceName;

  /// WS functions available in the current external service.
  /// Populated from core_webservice_get_site_info at login.
  final Set<String> availableFunctions;

  bool hasFunction(String name) => availableFunctions.contains(name);
}
