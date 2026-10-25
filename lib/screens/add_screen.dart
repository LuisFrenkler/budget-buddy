import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import '../models/transaction.dart';
import '../models/recurring.dart';
import '../services/db.dart';
import '../services/recurring_service.dart';
import '../utils/theme.dart';
import '../utils/money.dart';

class AddScreen extends StatefulWidget {
  // tx = null → create new transaction
  // tx = given → update existing transaction
  final Transaction? tx;
  
  const AddScreen({super.key, this.tx});
  
  @override
  State<AddScreen> createState() => _AddScreenState();
}

class _AddScreenState extends State<AddScreen> {
  // key for form validation
  final _formKey = GlobalKey<FormState>();
  
  // controllers for text input fields
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  
  // form state variables
  bool _isIncome = false;      // false = expense, true = income
  String? _category;
  DateTime _date = DateTime.now();
  String _repeat = 'Einmalig';  // 'Einmalig' or one of RecurringService.intervals
  bool _isSaving = false;

  // helper to check if we're editing or adding
  bool get _isEdit => widget.tx != null;

  @override
  void initState() {
    super.initState();
    
    // if editing -> fill form with existing data
    if (_isEdit) {
      // show the stored amount as an editable number with a German comma
      _amountCtrl.text =
          (widget.tx!.amountCents / 100).toStringAsFixed(2).replaceAll('.', ',');
      _noteCtrl.text = widget.tx!.note ?? '';
      _isIncome = widget.tx!.isIncome;
      _category = widget.tx!.category;
      _date = widget.tx!.date;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  // get the right categories based on income/expense selection
  List<Map<String, String>> get _categories {
    if (_isIncome) {
      return Categories.income;
    } else {
      return Categories.expense;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'Bearbeiten' : 'Neue Transaktion')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // toggle between expense and income
            _buildTypeToggle(),
            const SizedBox(height: 24),
            
            // amount input field
            _buildAmountField(),
            const SizedBox(height: 24),
            
            // category dropdown
            _buildCategoryDropdown(),
            const SizedBox(height: 24),
            
            // date picker
            _buildDateField(),
            const SizedBox(height: 24),

            // repeat option (only when creating a new transaction)
            if (!_isEdit) ...[
              _buildRepeatField(),
              const SizedBox(height: 24),
            ],

            // optional note field
            _buildNoteField(),
            const SizedBox(height: 32),
            
            // save button
            _buildSaveButton(),
          ],
        ),
      ),
    );
  }

  // toggle buttons to switch between expense and income
  Widget _buildTypeToggle() {
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          _buildToggleButton('Ausgabe', false, AppColors.error, Icons.arrow_upward),
          _buildToggleButton('Einnahme', true, AppColors.primary, Icons.arrow_downward),
        ],
      ),
    );
  }

  // single toggle button (expense or income)
  Widget _buildToggleButton(String label, bool isIncome, Color color, IconData icon) {
    final isActive = _isIncome == isIncome;
    
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() {
          _isIncome = isIncome;
          // reset category because expense/income have different categories
          _category = null;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            // highlight active button
            color: isActive ? color.withValues(alpha: 0.15) : null,
            borderRadius: BorderRadius.circular(12),
            border: isActive ? Border.all(color: color) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: isActive ? color : AppColors.textDim),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isActive ? color : AppColors.textDim,
                  fontWeight: isActive ? FontWeight.bold : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // input field for the amount
  Widget _buildAmountField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Betrag', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextFormField(
          controller: _amountCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          // allow digits and a single decimal separator (comma or dot), max 2 decimals
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^\d*[.,]?\d{0,2}')),
          ],
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
            hintText: '0,00',
            prefixText: '€ ',
            prefixStyle: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
          ),
          // validation
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Bitte eingeben';
            }
            final cents = Money.parseToCents(value);
            if (cents == null || cents <= 0) {
              return 'Ungültig';
            }
            return null;
          },
        ),
      ],
    );
  }

  // dropdown to select category
  Widget _buildCategoryDropdown() {
    // build dropdown items from categories
    final dropdownItems = <DropdownMenuItem<String>>[];
    for (var cat in _categories) {
      dropdownItems.add(
        DropdownMenuItem(
          value: cat['name'],
          child: Row(
            children: [
              Text(cat['emoji']!, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 12),
              Text(cat['name']!),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Kategorie', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _category,
          decoration: const InputDecoration(hintText: 'Wählen...'),
          items: dropdownItems,
          onChanged: (value) => setState(() => _category = value),
        ),
      ],
    );
  }

  // field to select date
  Widget _buildDateField() {
    final dateText = '${_date.day.toString().padLeft(2, '0')}.${_date.month.toString().padLeft(2, '0')}.${_date.year}';
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Datum', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        InkWell(
          onTap: _openDatePicker,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12)),
            child: Row(
              children: [
                const Icon(Icons.calendar_today, color: AppColors.primary),
                const SizedBox(width: 12),
                Text(dateText),
                const Spacer(),
                Icon(Icons.arrow_forward_ios, size: 16, color: AppColors.textDim),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // dropdown to make the transaction repeat on a schedule
  Widget _buildRepeatField() {
    final options = ['Einmalig', ...RecurringService.intervals];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Wiederholen', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          initialValue: _repeat,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.repeat, color: AppColors.primary),
          ),
          items: [
            for (final o in options) DropdownMenuItem(value: o, child: Text(o)),
          ],
          onChanged: (v) => setState(() => _repeat = v ?? 'Einmalig'),
        ),
      ],
    );
  }

  // optional text field for notes
  Widget _buildNoteField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Notiz (optional)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextFormField(
          controller: _noteCtrl,
          maxLines: 2,
          maxLength: 100,
          decoration: const InputDecoration(hintText: 'Notiz...'),
        ),
      ],
    );
  }

  // save button with loading spinner
  Widget _buildSaveButton() {
    return ElevatedButton(
      // disable button while saving
      onPressed: _isSaving ? null : _saveTransaction,
      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
      child: _isSaving
          // show spinner while saving
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
            )
          : Text(_isEdit ? 'Aktualisieren' : 'Speichern'),
    );
  }

  // opens the date picker dialog
  void _openDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      // style the date picker to match our app theme
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.dark(primary: AppColors.primary, surface: AppColors.surface),
          ),
          child: child!,
        );
      },
    );
    
    // update date if user picked one
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  // validates form and saves transaction to database
  void _saveTransaction() async {
    // check if form is valid
    if (!_formKey.currentState!.validate()) {
      return;
    }
    
    // check if category is selected
    if (_category == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bitte Kategorie wählen')),
      );
      return;
    }

    // show loading spinner
    setState(() => _isSaving = true);
    
    try {
      final cents = Money.parseToCents(_amountCtrl.text)!;
      final date = DateTime(_date.year, _date.month, _date.day);
      final note = _noteCtrl.text.isEmpty ? null : _noteCtrl.text;

      if (!_isEdit && _repeat != 'Einmalig') {
        // create a recurring rule; the engine generates the due transactions
        final rule = RecurringRule(
          id: const Uuid().v4(),
          amountCents: cents,
          category: _category!,
          isIncome: _isIncome,
          note: note,
          interval: _repeat,
          startDate: date,
        );
        await DB.addRule(rule);
        await RecurringService.process();
      } else {
        // one-off transaction (also the path for editing)
        final transaction = Transaction(
          id: _isEdit ? widget.tx!.id : const Uuid().v4(),
          amountCents: cents,
          category: _category!,
          date: date,
          isIncome: _isIncome,
          note: note,
        );
        await DB.addTx(transaction);
        await DB.checkBadges();
      }

      // go back to previous screen
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (error) {
      // show error message if something went wrong
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $error')),
        );
      }
    } finally {
      // hide loading spinner
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}
