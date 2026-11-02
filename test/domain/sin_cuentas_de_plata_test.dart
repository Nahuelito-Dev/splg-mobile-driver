import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Los montos, los saldos y las diferencias los calcula el back; la app sólo
/// los muestra. Si alguien vuelve a hacer una cuenta de plata en `lib/`
/// (multiplicar o dividir un monto, restar o sumar montos, acumularlos,
/// aplicar un porcentaje), este test falla.

const _palabras =
    r'price|subtotal|total|amount|surcharge|balance|deposit|difference|expected|declared|ticket|expenses?|cash|cents|sena|seña|declarado|gastos?|esperado|cobrado|saldo|importe|monto|precio';

/// Un identificador (con sus puntos) que lleva en el nombre una palabra de plata.
const _idMonto = '[\\p{L}\\w.\$]*(?:$_palabras)[\\p{L}\\w\$]*';

/// Lo que puede haber entre el monto y el operador: `?? 0`, `!`, `?` y paréntesis que cierran.
const _cola = r'(?:\s*(?:\?\?|\|\|)\s*[\w.]+)?[\s)!?]*';

/// Operador aritmético, con su forma de asignación (`+=`, `-=`), sin `++` ni `--`.
const _op = r'(?:[*]|/(?!>)|[+-])=?(?![+\-])';

/// Dividir por el tamaño de página es paginar, no una cuenta.
const _noEsPagina = r'(?!\s*[\w.]*(?:[Pp]age|PAGE|[Ll]imit|LIMIT|[Ss]ize))';

/// Un texto delante del operador ('Total: ' + total) es armar un rótulo.
const _noEsRotulo = r'(?<!§\s*)';

RegExp _r(String s) => RegExp(s, caseSensitive: false, unicode: true);

final _cuentas = <String, RegExp>{
  'monto antes del operador': _r('$_idMonto$_cola$_op$_noEsPagina'),
  'monto después del operador':
      _r('$_noEsRotulo$_op\\s*\\(*\\s*[\\p{L}\\w.!?]*(?:$_palabras)'),
  'cuenta con porcentaje': _r(
      r'percentage\w*!?\s*[*/]|[*/]\s*\(?\s*[\w.!?]*percentage|\b1\s*-\s*\(?[\w.!?]*percentage|\b100\s*-\s*[\w.!?]*percentage'),
  'Decimal en la app':
      RegExp(r'\bDecimal\b|\.(?:minus|plus|times|dividedBy)\('),
  'acumula montos': _r(
      '\\.(?:fold|reduce)(?:<[^>]*>)?\\([^;]{0,200}?(?:$_palabras)|(?:$_palabras)[^;]{0,80}?\\.(?:fold|reduce)(?:<[^>]*>)?\\(|\\.sum\\b[^;]{0,120}?(?:$_palabras)|(?:$_palabras)[^;]{0,80}?\\.sum\\b'),
};

/// Las cuentas de plata que hay en [codigo] (sin comentarios ni saltos de
/// línea, para que una cuenta cortada por `dart format` también se vea).
/// De cada texto sólo cuenta lo interpolado: una ruta como '/cash' no es una
/// cuenta.
List<String> cuentasDePlata(String codigo) {
  final sinComentarios = codigo
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ')
      .replaceAll(RegExp(r'//[^\n]*'), ' ');
  final sinTextos = sinComentarios.replaceAllMapped(
      RegExp("\"(?:[^\"\\\\\\n]|\\\\.)*\"|'(?:[^'\\\\\\n]|\\\\.)*'"),
      (m) =>
          '§${RegExp(r'\$\{[^}]*\}').allMatches(m.group(0)!).map((i) => i.group(0)).join(' ')}');
  final plano = sinTextos.replaceAll(RegExp(r'\s+'), ' ');
  return [
    for (final e in _cuentas.entries)
      for (final m in e.value.allMatches(plano))
        '${e.key}: «${m.group(0)!.trim()}»',
  ];
}

/// El fragmento exacto de una cuenta ('regla: «fragmento»').
String _fragmento(String cuenta) =>
    cuenta.substring(cuenta.indexOf('«') + 1, cuenta.length - 1);

class _Excepcion {
  const _Excepcion(this.ruta, this.fragmento, this.motivo);
  final String ruta;
  final String fragmento;
  final String motivo;
}

/// Cuentas de plata que existían antes de esta regla y todavía no pasaron al
/// back. Cada una es un fragmento exacto de un archivo: tocar otra parte del
/// archivo con una cuenta nueva sí se detecta. Sólo se achica: nada se agrega
/// acá.
const _pendientesDelBack = <_Excepcion>[];

/// Cuentas que no son de plata.
const _noSonPlata = <_Excepcion>[
  _Excepcion('lib/models/route_batch.dart', 'totalDistanceKm => stops.fold(',
      'suma de kilómetros de las paradas, no de pesos'),
];

void main() {
  group('el detector', () {
    const marca = <String, List<String>>{
      'multiplicar o dividir un monto': [
        'final s = item.quantity * item.cylinder.price;',
        'final s = qty * cylinder.price;',
        'final u = cylinder.price * (100 - d.percentage) / 100;',
        'final pct = (1 - line.unitPrice / list) * 100;',
        'final u = cylinder.price *\n      (1 - d.percentage / 100);',
        'int toCents(num amount) => (amount * 100).round();',
      ],
      'sumar o restar montos': [
        'final rest = total - items - zoneSurcharge - expressSurchargeInTotal;',
        'final d = declaredCash + driverExpenses - expectedCash;',
        'return (toCents(d) + _expensesCents - toCents(s.expectedCash)) / 100;',
        r"Text('Faltan ${total - deposit}')",
      ],
      'asignación compuesta con montos': [
        'var acc = 0; acc += order.amount;',
        'saldo -= payment.amount;',
        'total *= 1.21;',
        'balance /= 2;',
      ],
      'paréntesis entre el monto y el operador': [
        'final t = (o.total ?? 0) - (d.deposit ?? 0);',
        'final t = num.parse(o.total) - other;',
        'final t = double.parse(o.total) + double.parse(p.total);',
        'final t = (amount) * 100;',
      ],
      'monto contra una variable sin nombre de monto': [
        'final r = s.expectedCash - d;',
        'final r = d - s.expectedCash;',
        'final r = k * item.price;',
      ],
      'nombres en castellano': [
        'final r = total - sena;',
        'final r = seña + gastos;',
        'final r = declarado + gastos - esperado;',
        'final r = cobrado - importe;',
        'final r = monto * precio;',
        'final r = saldo - x;',
      ],
      'porcentaje': [
        'final f = d.percentage * 0.01;',
        'final f = 100 - d.percentage;',
      ],
      'Decimal': [
        'final d = Decimal.parse(a) + Decimal.one;',
        'final d = x.plus(y);',
        'final d = x.times(y).dividedBy(z);',
      ],
      'acumular con fold, reduce o sum': [
        'final t = lines.fold(0.0, (a, l) => a + l.subtotal);',
        'final g = expenses.fold<int>(0, (a, e) => a + e.amount);',
        'final t = orders.map((o) => o.total).reduce((a, b) => a + b);',
        'final t = orders.map((o) => o.amount).sum;',
        'final t = orders.map((o) => o.total).fold(0, (a, b) => a + b);',
      ],
    };
    for (final grupo in marca.entries) {
      for (final c in grupo.value) {
        test('marca (${grupo.key}): ${c.replaceAll(RegExp(r"\s*\n\s*"), " ")}',
            () => expect(cuentasDePlata(c), isNotEmpty));
      }
    }

    const mostrar = [
      'Text(money.format(o.total))',
      'value: money.format(i.subtotal!)',
      'final diff = model.previewDifference;',
      "diff == 0 ? '' : formatMoney(diff.abs())",
      'final total = _num(raw["total_amount"]);',
      "'declaredCash': declaredCash,",
      'paymentSurchargeAmount ?? 0',
      '// final x = price * 2;',
      '/* total - deposit */',
      'final pages = (count / 20).ceil();',
      'final pages = (total / pageSize).ceil();',
      'width: size.width * 0.8,',
      "final url = '/driver-settlements/cash/total';",
      "final label = 'Total: ' + total;",
      'final n = list.length - 1;',
      'i++; j--;',
      'if (balance >= 0) return null;',
    ];
    for (final c in mostrar) {
      test('no marca: $c', () => expect(cuentasDePlata(c), isEmpty));
    }
  });

  group('lib/ no calcula montos, saldos, diferencias ni descuentos', () {
    final hallazgos = <({String ruta, String fragmento})>[];
    for (final f
        in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.endsWith('.g.dart')) continue;
      for (final c in cuentasDePlata(f.readAsStringSync())) {
        hallazgos.add((ruta: f.path, fragmento: _fragmento(c)));
      }
    }

    /// Cada excepción cubre una aparición; lo que queda sin cubrir es una
    /// cuenta nueva.
    ({List<String> nuevas, List<String> sobrantes}) reparto() {
      final libres = [..._pendientesDelBack, ..._noSonPlata];
      final nuevas = <String>[];
      for (final h in hallazgos) {
        final i = libres
            .indexWhere((e) => e.ruta == h.ruta && e.fragmento == h.fragmento);
        if (i == -1) {
          nuevas.add('${h.ruta}: «${h.fragmento}»');
        } else {
          libres.removeAt(i);
        }
      }
      return (
        nuevas: nuevas,
        sobrantes: [for (final e in libres) '${e.ruta}: «${e.fragmento}»'],
      );
    }

    test('no hay cuentas de plata fuera de las excepciones', () {
      final r = reparto();
      expect(r.nuevas, isEmpty, reason: r.nuevas.join('\n'));
    });

    test('cada excepción sigue teniendo su cuenta: si ya no está, se saca', () {
      final r = reparto();
      expect(r.sobrantes, isEmpty, reason: r.sobrantes.join('\n'));
    });
  });
}
