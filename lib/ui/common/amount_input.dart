/// Lee un importe tipeado por el chofer en formato argentino: el punto separa
/// miles y la coma los decimales (`1.500` = 1500, `1500,50` = 1500.5,
/// `40,5` = 40.5). Acepta un `$` adelante. Null si está vacío, no es un número
/// o tiene más de [maxDecimals] decimales (`42.5` no es válido: el punto es de
/// miles).
num? parseAmount(String raw, {int maxDecimals = 2}) {
  final s = raw.trim().replaceAll(RegExp(r'[\s$]'), '');
  final m = RegExp(r'^(\d{1,3}(?:\.\d{3})+|\d+)(?:,(\d+))?$').firstMatch(s);
  if (m == null) return null;
  final decimals = m.group(2) ?? '';
  if (decimals.length > maxDecimals) return null;
  final whole = m.group(1)!.replaceAll('.', '');
  return num.parse(decimals.isEmpty ? whole : '$whole.$decimals');
}
