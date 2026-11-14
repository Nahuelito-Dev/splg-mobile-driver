import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:splg_lib/splg_lib.dart';
import 'package:stacked/stacked.dart';

import 'package:splg_driver/ui/common/navigation_helpers.dart';
import 'package:splg_driver/ui/widgets/driver_menu_drawer.dart';

import 'home_viewmodel.dart';

/// Inicio del chofer: mapa a pantalla completa que sigue al chofer, el botón
/// del menú arriba a la izquierda, el total de hoy arriba a la derecha y abajo
/// la hoja con el estado (chip) y "Conectarse" / "Desconectarse".
class HomeView extends StackedView<HomeViewModel> {
  const HomeView({super.key});

  /// Sólo para tests: reemplaza el mapa de Google por un placeholder.
  @visibleForTesting
  static Widget Function(BuildContext, HomeViewModel)? debugMapBuilder;

  /// Sólo para tests: fabrica el ViewModel (con el estado que se quiera ver).
  @visibleForTesting
  static HomeViewModel Function()? debugViewModelFactory;

  @override
  Widget builder(BuildContext context, HomeViewModel viewModel, Widget? child) {
    return _RouteVisibility(
      onChanged: viewModel.setRouteVisible,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        drawer: DriverMenuDrawer(onLogout: viewModel.logout),
        body: viewModel.isBusy
            ? const Center(child: CircularProgressIndicator())
            : _buildBody(context, viewModel),
      ),
    );
  }

  Widget _buildBody(BuildContext context, HomeViewModel viewModel) {
    // En entrega sin permiso no se tapa el mapa: queda la franja roja.
    if (!viewModel.hasLocationPermission && !viewModel.showsNoLocationBanner) {
      return SafeArea(child: _buildPermissionDeniedView(context, viewModel));
    }

    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            // Tocar el mapa frena el seguimiento un rato (no se pelea con el
            // usuario que lo arrastra).
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => viewModel.onMapTouched(),
            child: HomeView.debugMapBuilder?.call(context, viewModel) ??
                GoogleMap(
                  mapType: MapType.terrain,
                  initialCameraPosition: HomeViewModel.initialPosition,
                  onMapCreated: viewModel.onMapCreated,
                  markers: viewModel.markers,
                  myLocationEnabled: false, // Usamos nuestro propio marcador
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  compassEnabled: false,
                  mapToolbarEnabled: false,
                ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (viewModel.showsNoLocationBanner)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: _NoLocationBanner(
                      onTap: viewModel.requestLocationPermission,
                    ),
                  ),
                if (viewModel.showsLocationAlert)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: _LocationAlert(
                      onTap: viewModel.openLocationAlertSettings,
                    ),
                  ),
                if (viewModel.noOrdersReason != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: _NoOrdersNotice(
                      message: viewModel.noOrdersReason!,
                      onTap: viewModel.openMyLoad,
                    ),
                  ),
                if (viewModel.pendingMaintenance > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8, bottom: 4),
                    child: _MaintenanceNotice(
                      count: viewModel.pendingMaintenance,
                      onTap: viewModel.openTaller,
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Builder(
                          builder: (ctx) => SplgFloatingButton(
                            key: const Key('home-menu'),
                            tooltip: 'Menú',
                            icon: SplgIcons.menu,
                            onPressed: () => Scaffold.of(ctx).openDrawer(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (viewModel.search != HomeSearch.idle)
          Center(child: _SearchCard(search: viewModel.search)),
        Align(
          alignment: Alignment.bottomCenter,
          child: _ConnectSheet(viewModel: viewModel),
        ),
      ],
    );
  }

  Widget _buildPermissionDeniedView(
      BuildContext context, HomeViewModel viewModel) {
    final type = SplgType.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(SplgIcons.location,
                size: 80, color: Theme.of(context).colorScheme.error),
            const SizedBox(height: 24),
            Text(
              'Permisos de ubicación requeridos',
              style: type.title.copyWith(fontSize: context.sp(14)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              viewModel.permissionMessage ??
                  'No se pueden obtener los permisos de ubicación',
              style: type.body,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            SplgButton(
              title: 'Solicitar permisos',
              onPressed: viewModel.requestLocationPermission,
            ),
            const SizedBox(height: 12),
            SplgButton(
              title: 'Abrir configuración',
              style: SplgButtonStyle.outlined,
              onPressed: viewModel.openSettings,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              child: const Text('Abrir el menú'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  HomeViewModel viewModelBuilder(BuildContext context) =>
      HomeView.debugViewModelFactory?.call() ?? HomeViewModel();

  @override
  void onViewModelReady(HomeViewModel viewModel) {
    viewModel.initialize();
    super.onViewModelReady(viewModel);
  }
}

/// Avisa si la ruta del Inicio está al frente o tapada por otra pantalla
/// (`RouteObserver` del navegador de la app).
class _RouteVisibility extends StatefulWidget {
  const _RouteVisibility({required this.onChanged, required this.child});

  final ValueChanged<bool> onChanged;
  final Widget child;

  @override
  State<_RouteVisibility> createState() => _RouteVisibilityState();
}

class _RouteVisibilityState extends State<_RouteVisibility> with RouteAware {
  RouteObserver<PageRoute<dynamic>>? _observer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    final observer = appRouteObserver;
    if (route is PageRoute && _observer == null) {
      _observer = observer;
      observer.subscribe(this, route);
    }
  }

  @override
  void didPushNext() => widget.onChanged(false);

  @override
  void didPopNext() => widget.onChanged(true);

  @override
  void dispose() {
    _observer?.unsubscribe(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Hay una propuesta de taller esperando respuesta (también fuera de línea).
/// Al tocarlo abre Taller.
class _MaintenanceNotice extends StatelessWidget {
  const _MaintenanceNotice({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brasa = context.brasa;
    final type = SplgType.of(context);
    return Material(
      key: const Key('home-maintenance-notice'),
      color: brasa.infoSoft,
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(SplgIcons.vehicle, color: brasa.info),
              const SizedBox(width: 12),
              Expanded(
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Text(
                      count == 1
                          ? 'Tenés un turno de taller para responder.'
                          : 'Tenés $count turnos de taller para responder.',
                      style: type.bodyStrong.copyWith(color: brasa.ink2)),
                ),
              ),
              Icon(SplgIcons.next, color: brasa.info),
            ],
          ),
        ),
      ),
    );
  }
}

/// Aviso persistente: en línea pero sin ubicación, el despacho no ve al chofer.
class _LocationAlert extends StatelessWidget {
  const _LocationAlert({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brasa = context.brasa;
    final type = SplgType.of(context);
    return Material(
      key: const Key('home-location-alert'),
      color: brasa.warnSoft,
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(SplgIcons.location, color: brasa.warn),
            const SizedBox(width: 12),
            Expanded(
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: Text('Activá la ubicación para recibir pedidos',
                    style: type.bodyStrong.copyWith(color: brasa.ink2)),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: const Key('home-location-alert-action'),
              onPressed: onTap,
              child: const Text('Activar'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Entrega en curso sin permiso de ubicación: el cliente y el despacho no
/// reciben la posición del chofer. Persistente hasta que vuelva el permiso; el
/// botón lo pide (o lleva a Ajustes si quedó denegado para siempre).
class _NoLocationBanner extends StatelessWidget {
  const _NoLocationBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brasa = context.brasa;
    final type = SplgType.of(context);
    return Material(
      key: const Key('home-no-location-banner'),
      color: brasa.dangerSoft,
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Icon(SplgIcons.location, color: brasa.danger),
            const SizedBox(width: 12),
            Expanded(
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.3,
                child: Text(
                    'Sin permiso de ubicación: no se está enviando tu posición',
                    style: type.bodyStrong.copyWith(color: brasa.ink2)),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: const Key('home-no-location-banner-action'),
              onPressed: onTap,
              style: TextButton.styleFrom(foregroundColor: brasa.danger),
              child: const Text('Permitir'),
            ),
          ],
        ),
      ),
    );
  }
}

/// El back no le da pedidos por su carga del camión (D5 sin carga, carga sin
/// salir o ya devuelta): muestra el motivo que da el back. Al tocarlo abre
/// Mi carga.
class _NoOrdersNotice extends StatelessWidget {
  const _NoOrdersNotice({required this.message, required this.onTap});

  final String message;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brasa = context.brasa;
    final type = SplgType.of(context);
    return Material(
      key: const Key('home-no-orders-notice'),
      color: brasa.warnSoft,
      elevation: 3,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(SplgIcons.truck, color: brasa.warn),
              const SizedBox(width: 12),
              Expanded(
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Text(message,
                      style: type.bodyStrong.copyWith(color: brasa.ink2)),
                ),
              ),
              Icon(SplgIcons.next, color: brasa.warn),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Buscando pedidos…" y "Sin pedidos disponibles", sobre el mapa.
class _SearchCard extends StatelessWidget {
  const _SearchCard({required this.search});

  final HomeSearch search;

  @override
  Widget build(BuildContext context) {
    final type = SplgType.of(context);
    final searching = search == HomeSearch.searching;
    return IgnorePointer(
      child: Container(
        key: Key(searching ? 'search-searching' : 'search-empty'),
        width: context.sp(150),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: searching ? SplgGradients.button : null,
          color:
              searching ? null : Theme.of(context).colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
                color: Colors.black26, blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            searching
                ? const SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                        strokeWidth: 3, color: Colors.white),
                  )
                : const Icon(SplgIcons.search, size: 44, color: Colors.white),
            const SizedBox(height: 14),
            Text(
              searching ? 'Buscando pedidos…' : 'Sin pedidos disponibles',
              textAlign: TextAlign.center,
              style: type.title
                  .copyWith(color: Colors.white, fontSize: context.sp(13)),
            ),
            const SizedBox(height: 8),
            Text(
              searching
                  ? 'Estamos buscando algún pedido cercano para vos.'
                  : '¡Te avisaremos cuando haya uno!',
              textAlign: TextAlign.center,
              style: type.body.copyWith(color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hoja inferior con el botón de conexión.
class _ConnectSheet extends StatelessWidget {
  const _ConnectSheet({required this.viewModel});

  final HomeViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final online = viewModel.showsDisconnect;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        boxShadow: const [
          BoxShadow(
              color: Colors.black26, blurRadius: 12, offset: Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 100,
                height: 5,
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black26,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: _StatusChip(
                  label: viewModel.statusLabel,
                  state: !viewModel.isOnline
                      ? _LinkState.off
                      : (viewModel.isConnected
                          ? _LinkState.on
                          : _LinkState.reconnecting),
                ),
              ),
              const SizedBox(height: 10),
              SplgButton(
                title: online ? 'Desconectarse' : 'Conectarse',
                style: online ? SplgButtonStyle.danger : SplgButtonStyle.filled,
                loading: viewModel.isConnecting,
                onPressed: online ? viewModel.disconnect : viewModel.connect,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _LinkState { off, on, reconnecting }

/// Estado de la conexión del chofer: chip chico con un punto de color
/// (Desconectado / En línea / Reconectando…), en la hoja inferior.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.state});

  final String label;
  final _LinkState state;

  @override
  Widget build(BuildContext context) {
    final b = context.brasa;
    final (bg, dot) = switch (state) {
      _LinkState.off => (b.surfaceMuted, b.muted),
      _LinkState.on => (b.successSoft, b.success),
      _LinkState.reconnecting => (b.warnSoft, b.warn),
    };
    return Semantics(
      label: 'Estado: $label',
      child: Container(
        key: const Key('home-status'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            MediaQuery.withClampedTextScaling(
              maxScaleFactor: 1.3,
              child: Text(label,
                  style: SplgType.of(context)
                      .caption
                      .copyWith(color: b.ink2, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
