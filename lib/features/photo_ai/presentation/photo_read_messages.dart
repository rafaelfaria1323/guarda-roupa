import '../../../l10n/app_localizations.dart';
import '../domain/photo_reader.dart';

String photoReadMessage(AppLocalizations l10n, PhotoReadFailure failure) =>
    switch (failure) {
      PhotoReadFailure.notConfigured => l10n.geminiNotConfigured,
      PhotoReadFailure.notAllowed => l10n.geminiNotAllowed,
      PhotoReadFailure.limit => l10n.geminiLimit,
      PhotoReadFailure.busy => l10n.geminiBusy,
      PhotoReadFailure.failed => l10n.geminiFailed,
    };
