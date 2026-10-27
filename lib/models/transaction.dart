import '../utils/money.dart';
import '../utils/theme.dart';

class Transaction {
  final String id;
  final int amountCents;   // always stored as a positive integer in cents
  final String category;
  final DateTime date;
  final bool isIncome;    // true = income, false = expense
  final String? note;

  // money back for a purchase (a return, a refund): it comes in, but under the
  // spending category it reverses, so it lowers that spending instead of
  // counting as income
  bool get isRefund => isIncome && Categories.isExpenseOnly(category);

  // part of spending (a purchase, or a refund that takes some back)
  bool get isSpending => !isIncome || isRefund;

  // real income: salary, side jobs, gifts, not money back
  bool get isEarning => isIncome && !isRefund;

  // what this booking adds to spending: the amount, minus for a refund
  int get spendCents => isIncome ? (isRefund ? -amountCents : 0) : amountCents;

  Transaction({
    required this.id,
    required this.amountCents,
    required this.category,
    required this.date,
    required this.isIncome,
    this.note,
  });

  // convert to map for saving to hive
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'amountCents': amountCents,
      'category': category,
      'date': date.millisecondsSinceEpoch,
      'isIncome': isIncome,
      'note': note,
    };
  }

  // create from hive map
  factory Transaction.fromMap(Map<String, dynamic> map) {
    return Transaction(
      id: map['id'],
      // read new cent format if present, otherwise migrate the old
      // double-euro format ('amount') from existing stored data
      amountCents: map['amountCents'] != null
          ? (map['amountCents'] as num).toInt()
          : ((map['amount'] as num).toDouble() * 100).round(),
      category: map['category'],
      date: DateTime.fromMillisecondsSinceEpoch(map['date']),
      isIncome: map['isIncome'],
      note: map['note'],
    );
  }

  // formatted amount, e.g. "-12,99 €"
  String get amountText => Money.withSign(amountCents, isIncome);

  // formatted date
  String get dateText {
    String day = date.day.toString().padLeft(2, '0');
    String month = date.month.toString().padLeft(2, '0');
    return '$day.$month.${date.year}';
  }
}
