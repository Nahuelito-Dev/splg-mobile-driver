import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/core/config/app_config.dart';
import 'package:splg_driver/models/driver_data.dart';
import 'package:splg_driver/services/navigation_launcher.dart';
import 'package:splg_driver/ui/widgets/driver_menu_drawer.dart';
import 'package:splg_driver/ui/dialogs/order_offer/order_offer_dialog.dart'
    show paymentLabel;

import 'delivery_extras.dart';
import 'delivery_viewmodel.dart';

/// Pedido en curso con la distribución de la referencia de diseño: mapa a pantalla
/// completa con la dirección arriba ("Pedido aceptado" / "En camino") y abajo
/// la hoja con el cliente, la dirección, las garrafas y las acciones.
class DeliveryView extends StackedView<DeliveryViewModel> {
  final String orderId;

  const DeliveryView({super.key, required this.orderId});

  /// Sólo para tests: reemplaza el mapa de Google por un placeholder.
  @visibleForTesting
  static Widget Function(BuildContext, DeliveryViewModel)? debugMapBuilder;

  /// Sólo para tests: fabrica el ViewModel.
  @visibleForTesting
  static DeliveryViewModel Function(String)? debugViewModelFactory;

  @override
  Widget builder(BuildContext context, DeliveryViewModel model, Widget? child) {
    // No se sale de un pedido en curso con "atrás": hay acciones para eso.
    return PopScope(
      canPop: false,
      child: Scaffold(
        drawer: model.order == null ? null : const DriverMenuDrawer(),
        body: model.isBusy
            ? const Center(child: CircularProgressIndicator())
            : model.order == null
                ? _LoadError(model: model)
                : _Trip(model: model),
      ),
    );
  }

  @override
  DeliveryViewModel viewModelBuilder(BuildContext context) =>
      debugViewModelFactory?.call(orderId) ??
      DeliveryViewModel(orderId: orderId);

  @override
  void onViewModelReady(DeliveryViewModel viewModel) {
    viewModel.initialize();
    super.onViewModelReady(viewModel);
  }
}

/// Mapa con la dirección, la ruta por calles y el vehículo animado.
class _TripMap extends StatelessWidget {
  const _TripMap({required this.model});
  final DeliveryViewModel model;

  @override
  Widget build(BuildContext context) {
    Widget map(Set<Marker> markers) => GoogleMap(
          mapType: MapType.terrain,
          initialCameraPosition: CameraPosition(
            target: model.destination ??
                LatLng(AppConfig.mapFallbackLat, AppConfig.mapFallbackLng),
            zoom: 14,
          ),
          onMapCreated: model.onMapCreated,
          markers: markers,
          polylines: model.polylines,
          // Deja libre el centro del mapa: el vehículo y la ruta no quedan
          // tapados por la tarjeta de arriba ni por la hoja de abajo.
          padding: const EdgeInsets.only(top: 190, bottom: 380),
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: false,
          mapToolbarEnabled: false,
        );
    final pos = model.driverPosition;
    if (pos == null) return map(model.markers);
    return SplgAnimatedVehicle(
      position: pos,
      heading: model.vehicleHeading,
      icon: model.vehicleIcon,
      builder: (_, vehicle) => map({...model.markers, vehicle}),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.model});
  final DeliveryViewModel model;

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SplgIllustration.noNetwork.image(height: context.sp(90)),
            const SizedBox(height: 16),
            Text(model.loadError ?? 'No pudimos cargar el pedido.',
                key: const Key('delivery-load-error'),
                textAlign: TextAlign.center,
                style: type.body),
            const SizedBox(height: 20),
            SplgButton(title: 'Reintentar', onPressed: model.retry),
          ],
        ),
      ),
    );
  }
}

class _Trip extends StatelessWidget {
  const _Trip({required this.model});
  final DeliveryViewModel model;

  @override
  Widget build(BuildContext context) {
    final order = model.order!;
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            // Tocar el mapa suelta la cámara; el botón de recentrar la vuelve
            // a enganchar al vehículo.
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => model.userMovedMap(),
            child: DeliveryView.debugMapBuilder?.call(context, model) ??
                _TripMap(model: model),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Builder(
                  builder: (ctx) => SplgFloatingButton(
                    key: const Key('trip-menu'),
                    tooltip: 'Menú',
                    icon: SplgIcons.menu,
                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(child: _AddressCard(model: model, order: order)),
              ],
            ),
          ),
        ),
        Positioned(
          left: 8,
          bottom: context.sp(190),
          child: SplgFloatingButton(
            key: const Key('trip-locate'),
            tooltip: 'Recentrar',
            label: model.followCamera ? null : 'Recentrar',
            icon: SplgIcons.locate,
            onPressed: model.recenter,
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: _TripSheet(model: model),
        ),
      ],
    );
  }
}

/// Tarjeta superior: pin, dirección y la píldora de estado.
class _AddressCard extends StatelessWidget {
  const _AddressCard({required this.model, required this.order});
  final DeliveryViewModel model;
  final dynamic order;

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    final brasa = context.brasa;
    return Material(
      color: brasa.primaryStrong,
      borderRadius: BorderRadius.circular(16),
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SplgRouteRow(
              icon: SplgIcons.location,
              text: order.address ?? 'Dirección no disponible',
              caption: order.windowText == null
                  ? null
                  : 'Franja ${order.windowText}',
              color: brasa.accent,
              onDark: true,
            ),
            const SizedBox(height: 10),
            Container(
              key: const Key('trip-status-pill'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(model.isOnTheWay ? SplgIcons.truck : SplgIcons.clock,
                      size: 16, color: Colors.white),
                  const SizedBox(width: 6),
                  Text(model.statusText,
                      key: const Key('trip-status-text'),
                      style: type.body.copyWith(color: Colors.white)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripSheet extends StatelessWidget {
  const _TripSheet({required this.model});
  final DeliveryViewModel model;

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    final brasa = context.brasa;
    final order = model.order!;
    final summary = model.tripSummary;
    return SplgBottomPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(SplgIcons.down, size: 18, color: brasa.ink2),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        model.isOnTheWay
                            ? 'Yendo al cliente'
                            : 'Salí hacia el cliente',
                        key: const Key('trip-title'),
                        style: type.subtitle),
                    if (summary != null)
                      Text(summary,
                          key: const Key('trip-summary'), style: type.caption),
                  ],
                ),
              ),
              IconButton(
                key: const Key('trip-more'),
                tooltip: 'Más opciones',
                icon: Icon(SplgIcons.more, color: brasa.ink2),
                onPressed: () => _showMore(context, model),
              ),
            ],
          ),
          Divider(color: brasa.outline, height: 12),
          SplgPartyRow(
            name: order.customerName ?? 'Cliente',
            subtitle: order.customerPhone,
            initials: _initials(order.customerName),
            rating: model.customerRating?.average,
            ratingCount: model.customerRating?.count,
          ),
          const SizedBox(height: 10),
          SplgRouteRow(
            icon: SplgIcons.flame,
            text: order.lines.isEmpty ? 'Sin detalle' : order.linesText,
            caption:
                '${paymentLabel(order.paymentMethod)} - ${formatTotal(order.amountToCollect)}',
            color: brasa.primaryStrong,
          ),
          if (model.showEmpties) EmptiesCard(model: model),
          PickupCard(model: model.pickups),
          if (model.errorMessage != null || model.notice != null) ...[
            const SizedBox(height: 8),
            Text(model.errorMessage ?? model.notice!,
                key: const Key('trip-message'),
                style: type.caption.copyWith(
                    color: model.errorMessage != null
                        ? brasa.danger
                        : brasa.muted)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SplgButton(
                  key: const Key('trip-call'),
                  title: 'Llamar',
                  style: SplgButtonStyle.outlined,
                  onPressed:
                      order.customerPhone == null ? null : model.callCustomer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SplgButton(
                  key: const Key('trip-navigate'),
                  title: 'Navegar',
                  style: SplgButtonStyle.outlined,
                  onPressed: model.destination == null
                      ? null
                      : () => _chooseMap(context, model),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (model.isAccepted)
            SplgActionButton(
              key: const Key('trip-leave'),
              title: 'Salir hacia el cliente',
              loading: model.isUpdatingStatus || model.isReleasing,
              onPressed: model.markOnTheWay,
            )
          else
            SplgActionButton(
              key: const Key('trip-arrive'),
              title: 'Llegué / Entregar',
              loading: model.isUpdatingStatus || model.isReleasing,
              onPressed: model.arriveAndDeliver,
            ),
        ],
      ),
    );
  }

  static String formatTotal(num n) => formatMoney(n);

  static String? _initials(String? name) {
    if (name == null || name.trim().isEmpty) return null;
    final p = name.trim().split(RegExp(r'\s+'));
    return (p.first[0] + (p.length > 1 ? p.last[0] : '')).toUpperCase();
  }
}

Future<void> _chooseMap(BuildContext context, DeliveryViewModel model) async {
  final picked = await showDialog<MapApp>(
    context: context,
    builder: (_) => const SplgChoiceDialog<MapApp>(
      message: 'Elegí con qué mapa querés ir a la dirección:',
      choices: [
        SplgChoice(MapApp.stay, 'Permanecer en SPLG', bold: true),
        SplgChoice(MapApp.google, 'Ir a Google Maps'),
        SplgChoice(MapApp.waze, 'Ir a Waze'),
      ],
    ),
  );
  if (picked == null) return;
  if (picked == MapApp.stay) {
    await model.fitRoute();
  } else {
    await model.navigateWith(picked);
  }
}

Future<void> _showMore(BuildContext context, DeliveryViewModel model) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SplgOptionRow(
            icon: SplgIcons.flame,
            title: 'Cargar envases',
            onTap: () {
              Navigator.pop(sheet);
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16,
                      MediaQuery.of(context).viewInsets.bottom + 16),
                  child: SingleChildScrollView(
                      child: CylinderAssignCard(viewModel: model)),
                ),
              );
            },
          ),
          if (model.canRelease)
            SplgOptionRow(
              key: const Key('trip-release'),
              icon: SplgIcons.userMinus,
              title: 'Liberar pedido',
              onTap: () {
                Navigator.pop(sheet);
                _confirmRelease(context, model);
              },
            ),
          SplgOptionRow(
            icon: SplgIcons.error,
            title: 'Reportar un problema',
            onTap: () {
              Navigator.pop(sheet);
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) =>
                    IncidentSheet(orderId: model.orderId, viewModel: model),
              );
            },
          ),
        ],
      ),
    ),
  );
}

/// Liberar el pedido no tiene vuelta atrás: se confirma antes.
Future<void> _confirmRelease(
    BuildContext context, DeliveryViewModel model) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('¿Liberar el pedido?'),
      content: const Text('Si no podés entregarlo, el pedido vuelve a quedar '
          'pendiente para otro chofer y dejás de verlo. Seguís en línea para '
          'recibir otros.'),
      actions: [
        TextButton(
          key: const Key('trip-release-cancel'),
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Volver'),
        ),
        TextButton(
          key: const Key('trip-release-confirm'),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Liberar'),
        ),
      ],
    ),
  );
  if (ok == true) await model.releaseOrder();
}
