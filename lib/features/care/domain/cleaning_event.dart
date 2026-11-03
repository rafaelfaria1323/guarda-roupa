import '../../wardrobe/domain/garment.dart';
import '../../wear/domain/calendar_day.dart';

/// "Lavei/limpei esta peça neste dia". Reinicia a contagem de utilizações
/// para o aviso de lavagem; não muda a disponibilidade.
final class CleaningEvent {
  const CleaningEvent({
    required this.id,
    required this.garmentId,
    required this.cleanedOn,
    required this.createdAt,
  });

  final String id;
  final GarmentId garmentId;
  final CalendarDay cleanedOn;
  final DateTime createdAt;
}
