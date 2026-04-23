import 'package:jennygas_lib/domain/address.dart';
import 'package:jennygas_lib/domain/gas_cylinder.dart';
import 'package:jennygas_lib/domain/order_item.dart';
import 'package:stacked/stacked.dart';

import 'package:jennygas_lib/domain/order.dart';

class OrderService with ListenableServiceMixin {
  final ReactiveList<Order> _orders = ReactiveList<Order>();
  List<Order> get orders => _orders;

  Future<void> init() async {
    await fetch();
  }

  Future<void> fetch() async {
    try {
      await Future.delayed(Duration(seconds: 2));
      List<Order> fetchedOrders = [
        Order(
            id: '1',
            total: 200000,
            status: OrderStatus.pending,
            createdAt: DateTime.now().subtract(Duration(days: 3)),
            address: Address(
                addressId: '1',
                streetName: 'Santa Clara 12'),
            items: [
              OrderItem(
                  cylinder: GasCylinder(
                      id: '1',
                      type: '10kg',
                      price: 200000,
                      active: true,
                      weight: '10 kg',
                      description: 'Garrafa 10 kg'),
                  quantity: 1)
            ],
            paymentMethod: PaymentMethod.cash),
        Order(
            id: '2',
            total: 200000,
            status: OrderStatus.pending,
            createdAt: DateTime.now().subtract(Duration(days: 1)),
            address: Address(
                addressId: '2',
                streetName: 'Santa Elena 16'),
            items: [
              OrderItem(
                  cylinder: GasCylinder(
                      id: '2',
                      type: '10kg',
                      price: 200000,
                      active: true,
                      weight: '10 kg',
                      description: 'Garrafa 10 kg'),
                  quantity: 1)
            ],
            paymentMethod: PaymentMethod.online),
        Order(
            id: '3',
            total: 200000,
            status: OrderStatus.accepted,
            createdAt: DateTime.now(),
            address: Address(
                addressId: '3',
                streetName: 'San Martin 200'),
            items: [
              OrderItem(
                  cylinder: GasCylinder(
                      id: '3',
                      type: '10kg',
                      price: 200000,
                      active: true,
                      weight: '10 kg',
                      description: 'Garrafa 10 kg'),
                  quantity: 1)
            ],
            paymentMethod: PaymentMethod.cash),
        Order(
            id: '4',
            total: 200000,
            status: OrderStatus.outForDelivery,
            createdAt: DateTime.now(),
            address: Address(
                addressId: '4',
                streetName: 'San Martin 200'),
            items: [
              OrderItem(
                  cylinder: GasCylinder(
                      id: '4',
                      type: '10kg',
                      price: 200000,
                      active: true,
                      weight: '10 kg',
                      description: 'Garrafa 10 kg'),
                  quantity: 1)
            ],
            paymentMethod: PaymentMethod.cash),
        Order(
            id: '5',
            total: 150000,
            status: OrderStatus.pending,
            createdAt: DateTime.now().subtract(Duration(days: 3)),
            address: Address(
                addressId: '5',
                streetName: 'Santa Clara 12'),
            items: [
              OrderItem(
                  cylinder: GasCylinder(
                      id: '5',
                      type: '15kg',
                      price: 150000,
                      active: true,
                      weight: '15 kg',
                      description: 'Garrafa 15 kg'),
                  quantity: 1)
            ],
            paymentMethod: PaymentMethod.online),
        Order(
            id: '6',
            total: 360000,
            status: OrderStatus.pending,
            createdAt: DateTime.now().subtract(Duration(days: 3)),
            address: Address(
                addressId: '6',
                streetName: 'Santa Clara 12'),
            items: [
              OrderItem(
                  cylinder: GasCylinder(
                      id: '6',
                      type: '45kg',
                      price: 180000,
                      active: true,
                      weight: '45 kg',
                      description: 'Garrafa 45 kg'),
                  quantity: 2)
            ],
            paymentMethod: PaymentMethod.online),
      ];
      _orders.clear();
      _orders.addAll(fetchedOrders);
      notifyListeners();
    } catch (e) {
      print('Error fetching orders: $e');
    }
  }

  Future<void> remove(Order order) async {
    _orders.remove(order);
    notifyListeners();
  }
}
