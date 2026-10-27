import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/forecast_service.dart';
import '../utils/dates.dart';
import '../utils/money.dart';
import '../utils/theme.dart';

// Start screen card: what is still free this month and per day. Tapping it
// shows how the number comes about, so it can be trusted.
class ForecastCard extends StatelessWidget {
  final MonthForecast forecast;
  const ForecastCard(this.forecast, {super.key});

  @override
  Widget build(BuildContext context) {
    final f = forecast;
    final (color, label) = switch (f.pace) {
      ForecastPace.relaxed => (AppColors.positive, 'Im Plan'),
      ForecastPace.tight => (AppColors.warning, 'Wird knapp'),
      ForecastPace.over => (AppColors.error, 'Über Budget'),
    };
    final next = f.due.isEmpty ? null : f.due.first;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          HapticFeedback.selectionClick();
          _details(context);
        },
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('Diesen Monat noch frei',
                    style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(999)),
                child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 6),
            // wraps onto a second line on narrow phones instead of overflowing
            Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 10, runSpacing: 2, children: [
              Text(Money.format(f.freeCents),
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      color: f.freeCents < 0 ? AppColors.errorText : AppColors.text)),
              if (f.freeCents > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text('≈ ${Money.format(f.perDayCents)} pro Tag',
                      style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.w600)),
                ),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: f.usedShare,
                minHeight: 7,
                backgroundColor: AppColors.surfaceAlt,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              next != null
                  ? 'Noch ${f.daysLeft} ${f.daysLeft == 1 ? 'Tag' : 'Tage'} · als Nächstes ${next.name} '
                      '${Money.format(next.cents)} am ${Dates.dayMonth(next.date)}'
                  : 'Noch ${f.daysLeft} ${f.daysLeft == 1 ? 'Tag' : 'Tage'} · alle Fixkosten sind schon abgebucht',
              style: TextStyle(color: AppColors.textDim, fontSize: 12.5),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ]),
        ),
      ),
    );
  }

  void _details(BuildContext context) {
    final f = forecast;
    Widget line(String a, int cents, {bool bold = false, bool minus = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w500)),
            const Spacer(),
            Text('${minus ? '− ' : ''}${Money.format(cents)}',
                style: TextStyle(
                    fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                    color: bold && cents < 0 ? AppColors.errorText : null)),
          ]),
        );
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('So rechnet Buddy', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('Aus deinen Umsätzen der letzten Monate, ohne dass du etwas einstellen musst.',
                style: TextStyle(color: AppColors.textDim)),
            const SizedBox(height: 16),
            line('Übliches Einkommen', f.incomeCents),
            line('Fixkosten (Miete, Abos …)', f.fixedCents, minus: true),
            if (f.goalsCents > 0) line('Für deine Sparziele', f.goalsCents, minus: true),
            line('Bisher ausgegeben', f.spentCents, minus: true),
            Divider(color: AppColors.border, height: 20),
            line('Noch frei', f.freeCents, bold: true),
            if (f.limitedByBalance)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    'Begrenzt durch deinen Kontostand: Auf dem Konto ist gerade weniger, '
                    'als die Rechnung hergibt (z. B. bevor das Gehalt kommt).',
                    style: TextStyle(color: AppColors.textDim, fontSize: 12, height: 1.35)),
              ),
            if (f.due.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Noch fällig diesen Monat',
                  style: TextStyle(color: AppColors.textDim, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 6),
              for (final d in f.due.take(6))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    Icon(Icons.event_rounded, size: 18, color: AppColors.textDim),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${d.name} · ${Dates.dayMonth(d.date)}')),
                    Text(Money.format(d.cents), style: const TextStyle(fontWeight: FontWeight.w600)),
                  ]),
                ),
              Text('Schon eingerechnet in den Fixkosten.', style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            ],
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.surfaceAlt, borderRadius: BorderRadius.circular(14)),
              child: Text(
                switch (f.pace) {
                  ForecastPace.relaxed =>
                    'Bei deinem üblichen Tempo gibst du bis Monatsende etwa ${Money.format(f.paceCents)} aus. Das passt.',
                  ForecastPace.tight =>
                    'Bei deinem üblichen Tempo wären es bis Monatsende etwa ${Money.format(f.paceCents)}, '
                        'mehr als noch frei ist. Ein paar ruhige Tage reichen schon.',
                  ForecastPace.over => 'Du liegst diesen Monat über deinem Budget. Buddy hilft dir, wo es sich '
                      'am leichtesten sparen lässt.',
                },
                style: const TextStyle(height: 1.4),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
