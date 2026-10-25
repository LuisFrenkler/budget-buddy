class Badge {
  final String id;
  final String name;
  final String description;
  final String emoji;
  bool isUnlocked;           // true if earned
  DateTime? unlockedDate;    // when it was unlocked

  Badge({
    required this.id,
    required this.name,
    required this.description,
    required this.emoji,
    this.isUnlocked = false,
    this.unlockedDate,
  });

  // convert to map for saving to hive
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'emoji': emoji,
      'isUnlocked': isUnlocked,
      'unlockedDate': unlockedDate?.millisecondsSinceEpoch,
    };
  }

  // create from hive map
  factory Badge.fromMap(Map<String, dynamic> map) {
    return Badge(
      id: map['id'],
      name: map['name'],
      description: map['description'],
      emoji: map['emoji'],
      isUnlocked: map['isUnlocked'] ?? false,
      unlockedDate: map['unlockedDate'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(map['unlockedDate']) 
          : null,
    );
  }

  // unlock badge and set the date
  void unlock() {
    isUnlocked = true;
    unlockedDate = DateTime.now();
  }
}
