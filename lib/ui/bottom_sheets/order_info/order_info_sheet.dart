import 'package:flutter/material.dart';
import 'package:splg_driver/ui/common/ui_helpers.dart';
import 'package:stacked/stacked.dart';
import 'package:stacked_services/stacked_services.dart';

import 'order_info_sheet_model.dart';
import 'package:splg_lib/theme/brasa_palette.dart';

class OrderInfoSheet extends StackedView<OrderInfoSheetModel> {
  final Function(SheetResponse response)? completer;
  final SheetRequest request;
  const OrderInfoSheet({
    Key? key,
    required this.completer,
    required this.request,
  }) : super(key: key);

  @override
  Widget builder(
    BuildContext context,
    OrderInfoSheetModel viewModel,
    Widget? child,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(10),
          topRight: Radius.circular(10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            request.title ?? 'Hello Stacked Sheet!!',
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
          ),
          if (request.description != null) ...[
            verticalSpaceTiny,
            Text(
              request.description!,
              style: TextStyle(fontSize: 14, color: context.brasa.muted),
              maxLines: 3,
              softWrap: true,
            ),
          ],
          verticalSpaceLarge,
        ],
      ),
    );
  }

  @override
  OrderInfoSheetModel viewModelBuilder(BuildContext context) =>
      OrderInfoSheetModel();
}
