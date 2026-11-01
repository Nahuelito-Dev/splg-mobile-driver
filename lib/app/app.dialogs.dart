// dart format width=80
// GENERATED CODE - DO NOT MODIFY BY HAND

// **************************************************************************
// StackedDialogGenerator
// **************************************************************************

import 'package:stacked_services/stacked_services.dart';

import 'app.locator.dart';
import '../ui/dialogs/info_alert/info_alert_dialog.dart';
import '../ui/dialogs/order_offer/order_offer_dialog.dart';
import '../ui/dialogs/route_batch_offer/route_batch_offer_dialog.dart';

enum DialogType {
  infoAlert,
  orderOffer,
  routeBatchOffer,
}

void setupDialogUi() {
  final dialogService = locator<DialogService>();

  final Map<DialogType, DialogBuilder> builders = {
    DialogType.infoAlert: (context, request, completer) =>
        InfoAlertDialog(request: request, completer: completer),
    DialogType.orderOffer: (context, request, completer) =>
        OrderOfferDialog(request: request, completer: completer),
    DialogType.routeBatchOffer: (context, request, completer) =>
        RouteBatchOfferDialog(request: request, completer: completer),
  };

  dialogService.registerCustomDialogBuilders(builders);
}
